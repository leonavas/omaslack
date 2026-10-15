.pragma library
.import "Markup.js" as Markup

// The message box's document, the way Slack's WYSIWYG box keeps it: what
// the composer edits, draws (rich text for the TextEdit) and sends (a
// `rich_text` block, and box markup for the `text` fallback and drafts).
//
// A document is a list of lines. A line has a kind ("p" paragraph, "q"
// quote, "ul" / "ol" list item with its indent `n`, "pre" code block line)
// and cells, one per character the editor shows. A cell carries its
// character `c`, its marks `f` ("b" bold, "i" italic, "u" underline, "x"
// strike, "c" code, in that order), a link address `l`, and the atom `a` it
// belongs to: an emoji (one picture, U+FFFC in the editor's text) or a pill
// (@person, #channel, @here; as many cells as its label). The editor's
// plain text is the cells' characters with the lines joined by "\n", so a
// position in the editor is a position in the document.
//
// Documents are values: every edit returns a new one (cells are shared and
// never changed), so the composer's undo keeps them as they are.
//
// `ctx` (loading, typing :emoji:) describes the workspace:
//   user(id), conv(id)   → a name for a pill's label
//   emoji(name, tone)    → {url} | {glyph} | null

var OBJ = String.fromCharCode(0xfffc)
var PARA = String.fromCharCode(0x2029)
var LSEP = String.fromCharCode(0x2028)
var NBSP = String.fromCharCode(0xa0)
var MARKS = "biuxc"
var MARK_OF = { "*": "b", "_": "i", "~": "x", "`": "c" }
var NAME_CH = /[A-Za-z0-9_+'\-]/

function cell(c, f, l, a) { return { c: c, f: f || "", l: l || "", a: a || null } }
function line(k, n, cells) { return { k: k || "p", n: n || 0, cells: cells || [] } }
// An inserted line whose kind comes from the line it lands in.
function loose(cells) { return { k: null, n: 0, cells: cells || [] } }
function empty() { return [line("p", 0, [])] }
function clone(doc) { return doc.map(function(l) { return line(l.k, l.n, l.cells.slice()) }) }

function isSpace(c) { return /\s/.test(c) }
function isAlnum(c) { return !!c && (/[A-Za-z0-9]/.test(c) || c.toLowerCase() !== c.toUpperCase()) }
function bare(x) { return !!x && !x.a }

function withMark(f, m, on) {
  var out = ""
  for (var i = 0; i < MARKS.length; i++) {
    var k = MARKS.charAt(i)
    if (k === m ? on : f.indexOf(k) >= 0) out += k
  }
  return out
}
function marksOf(st) { return st ? (st.bold ? "b" : "") + (st.italic ? "i" : "") + (st.underline ? "u" : "") + (st.strike ? "x" : "") + (st.code ? "c" : "") : "" }
function flags(f) { return { bold: f.indexOf("b") >= 0, italic: f.indexOf("i") >= 0, underline: f.indexOf("u") >= 0, strike: f.indexOf("x") >= 0, code: f.indexOf("c") >= 0 } }
function styleOf(f) {
  if (!f) return null
  var o = {}
  if (f.indexOf("b") >= 0) o.bold = true
  if (f.indexOf("i") >= 0) o.italic = true
  if (f.indexOf("u") >= 0) o.underline = true
  if (f.indexOf("x") >= 0) o.strike = true
  if (f.indexOf("c") >= 0) o.code = true
  return o
}

// ------------------------------------------------------------------ text

function lineText(cells) { var s = ""; for (var i = 0; i < cells.length; i++) s += cells[i].c; return s }
function plain(doc) { return doc.map(function(l) { return lineText(l.cells) }).join("\n") }
// The same with pills, emoji and code hidden, for the autocomplete's
// patterns (nothing is suggested inside code).
function masked(doc) {
  return doc.map(function(l) {
    var s = ""
    l.cells.forEach(function(x) { s += x.a || l.k === "pre" || x.f.indexOf("c") >= 0 ? OBJ : x.c })
    return s
  }).join("\n")
}
function size(doc) { var n = doc.length - 1; for (var i = 0; i < doc.length; i++) n += doc[i].cells.length; return n }
function isEmpty(doc) { return doc.length === 1 && doc[0].cells.length === 0 }
function isBlank(doc) {
  for (var i = 0; i < doc.length; i++) for (var j = 0; j < doc[i].cells.length; j++) { var x = doc[i].cells[j]; if (x.a || !isSpace(x.c)) return false }
  return true
}

// The editor's text (getText) in the document's terms.
function normalize(s) { return String(s || "").split(PARA).join("\n").split(LSEP).join("\n").replace(/\r\n?/g, "\n") }

function locate(doc, pos) {
  for (var i = 0; i < doc.length; i++) {
    var len = doc[i].cells.length
    if (pos <= len) return { li: i, col: Math.max(0, pos) }
    pos -= len + 1
  }
  var last = doc.length - 1
  return { li: last, col: doc[last].cells.length }
}
function posOf(doc, li, col) { var p = 0; for (var i = 0; i < li; i++) p += doc[i].cells.length + 1; return p + col }

// The line at a position: kind, indent, length, first / last of its group.
function lineAt(doc, pos) {
  var at = locate(doc, pos), L = doc[at.li]
  return { li: at.li, col: at.col, k: L.k, n: L.n, len: L.cells.length,
           first: at.li === 0 || doc[at.li - 1].k !== L.k, last: at.li === doc.length - 1 }
}

// ------------------------------------------------------------------ atoms

// An emoji by Slack name ("+1", "+1::skin-tone-3"); without a picture or a
// glyph it stays text.
function mkEmoji(name, tone, ctx) {
  name = String(name || "").replace(/^:|:$/g, "")
  var cut = name.indexOf("::skin-tone-")
  if (cut >= 0) { tone = parseInt(name.slice(cut + 12), 10) || 0; name = name.slice(0, cut) }
  var r = ctx && ctx.emoji ? ctx.emoji(name, tone || 0) : null
  return { k: "emoji", name: name, tone: tone || 0, url: r && r.url ? r.url : "", glyph: r && r.glyph ? r.glyph : "" }
}
function drawable(a) { return a.k !== "emoji" || !!a.url || !!a.glyph }
// A workspace emoji that moves (a GIF): the editor's rich text only ever
// shows its first frame, so the composer plays it over the text.
function animated(a) { return !!a && a.k === "emoji" && /\.gif(\?|#|$)/i.test(a.url || "") }
function emojiCode(a) { return ":" + a.name + ":" + (a.tone ? ":skin-tone-" + a.tone + ":" : "") }
// What an atom shows in the editor: one picture, or a pill's label that
// doesn't break across lines.
function atomText(a) {
  if (a.k === "emoji") return a.url ? OBJ : (a.glyph || emojiCode(a))
  return String(a.label || "").replace(/\s/g, NBSP)
}
function atomCells(a, f) {
  var t = atomText(a), out = []
  for (var i = 0; i < t.length; i++) out.push(cell(t.charAt(i), f, "", a))
  return out
}
function atomWire(a) {
  switch (a.k) {
  case "emoji": return emojiCode(a)
  case "user": return "<@" + a.id + ">"
  case "channel": return "<#" + a.id + ">"
  case "group": return "<!subteam^" + a.id + ">"
  default: return "<!" + a.id + ">"
  }
}
// A pick from the autocomplete ("<@U1>", "<#C1>", "<!here>") as a pill.
function atomFromWire(wire, label) {
  var m = String(wire || "").match(/^<([@#!])([^|>]+)(?:\|[^>]*)?>$/)
  if (!m) return null
  if (m[1] === "@") return { k: "user", id: m[2], label: label }
  if (m[1] === "#") return { k: "channel", id: m[2], label: label }
  if (m[2].indexOf("subteam^") === 0) return { k: "group", id: m[2].slice(8), label: label }
  return { k: "broadcast", id: m[2], label: label }
}

// [a, b) grown so it never cuts a pill or an emoji in two.
function expand(doc, a, b) {
  var A = locate(doc, a), cs = doc[A.li].cells
  while (A.col > 0 && A.col < cs.length && cs[A.col].a && cs[A.col - 1].a === cs[A.col].a) { A.col--; a-- }
  var B = locate(doc, b), cs2 = doc[B.li].cells
  while (B.col > 0 && B.col < cs2.length && cs2[B.col].a && cs2[B.col - 1].a === cs2[B.col].a) { B.col++; b++ }
  return [a, b]
}
// A position inside a pill moved to its edge (the end, or the start going back).
function snap(doc, pos, forward) {
  var at = locate(doc, pos), cs = doc[at.li].cells, col = at.col
  if (col <= 0 || col >= cs.length || !cs[col].a || cs[col - 1].a !== cs[col].a) return pos
  var s = col, e = col
  while (s > 0 && cs[s - 1].a === cs[col].a) s--
  while (e < cs.length && cs[e].a === cs[col].a) e++
  return pos - col + (forward ? e : s)
}

// ------------------------------------------------------------------ loading

// Slack's rich_text blocks as a document; null when the blocks aren't all
// rich_text (the caller falls back on the text).
function fromBlocks(blocks, ctx) {
  if (!blocks || !blocks.length) return null
  for (var i = 0; i < blocks.length; i++) if (!blocks[i] || blocks[i].type !== "rich_text") return null
  var doc = []
  blocks.forEach(function(b) {
    (b.elements || []).forEach(function(e) {
      if (e.type === "rich_text_list") {
        (e.elements || []).forEach(function(it) {
          var cs = []
          ;(it.elements || []).forEach(function(x) { pushElement(cs, x, ctx, false) })
          while (cs.length && bare(cs[cs.length - 1]) && cs[cs.length - 1].c === "\n") cs.pop()
          cs = cs.map(function(x) { return x.c === "\n" && !x.a ? cell(" ", x.f, x.l, null) : x })
          doc.push(line(e.style === "ordered" ? "ol" : "ul", Math.max(0, Math.min(8, e.indent || 0)), cs))
        })
        return
      }
      var kind = e.type === "rich_text_quote" ? "q" : e.type === "rich_text_preformatted" ? "pre" : e.type === "rich_text_section" ? "p" : ""
      if (!kind) return
      var cells = []
      ;(e.elements || []).forEach(function(x) { pushElement(cells, x, ctx, kind === "pre") })
      var ls = splitLines(cells)
      if (kind !== "pre" && ls.length > 1 && !ls[ls.length - 1].length) ls.pop()
      ls.forEach(function(cs) { doc.push(line(kind, 0, cs)) })
    })
  })
  return doc.length ? doc : empty()
}

function splitLines(cells) {
  var out = [[]]
  cells.forEach(function(x) { if (x.c === "\n" && !x.a) out.push([]); else out[out.length - 1].push(x) })
  return out
}

function pushElement(cells, x, ctx, literal) {
  var f = literal ? "" : marksOf(x.style)
  function text(s, l) { s = String(s || ""); for (var i = 0; i < s.length; i++) if (s.charAt(i) !== OBJ) cells.push(cell(s.charAt(i), f, l || "", null)) }
  function atom(a) { cells.push.apply(cells, atomCells(a, f)) }
  function name(fn, id) { return (ctx && ctx[fn] && ctx[fn](id)) || id }
  switch (x.type) {
  case "text": text(x.text); break
  case "link": text(x.text || x.url, x.url); break
  case "emoji": {
    var e = mkEmoji(x.name, x.skin_tone || 0, ctx)
    if (drawable(e)) atom(e)
    else text(emojiCode(e))
    break
  }
  case "user": atom({ k: "user", id: x.user_id, label: "@" + name("user", x.user_id) }); break
  case "channel": atom({ k: "channel", id: x.channel_id, label: "#" + name("conv", x.channel_id) }); break
  case "usergroup": atom({ k: "group", id: x.usergroup_id, label: "@" + ((ctx && ctx.group && ctx.group(x.usergroup_id)) || "group") }); break
  case "broadcast": atom({ k: "broadcast", id: x.range || "here", label: "@" + (x.range || "here") }); break
  case "date": text(x.fallback || ""); break
  case "color": text(x.value || ""); break
  default: text(x.text || "")
  }
}

// Box markup (drafts, a failed send coming back) as a document.
function fromMarkup(text, ctx) { return fromBlocks(Markup.blocks(String(text || "")), ctx) || empty() }
// A message's mrkdwn `text` (entities escaped) as a document.
function fromMrkdwn(text, ctx) {
  return fromMarkup(String(text || "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"), ctx)
}

// ------------------------------------------------------------------ sending

function trimmed(doc) {
  function blank(l) { for (var i = 0; i < l.cells.length; i++) { var x = l.cells[i]; if (x.a || !isSpace(x.c)) return false } return true }
  var a = 0, b = doc.length
  while (a < b && blank(doc[a])) a++
  while (b > a && blank(doc[b - 1])) b--
  return doc.slice(a, b)
}

// Runs of cells: a whole atom, or text in one style and link.
function runs(cells, fn) {
  var i = 0
  while (i < cells.length) {
    var x = cells[i], j = i
    if (x.a) {
      while (j < cells.length && cells[j].a === x.a) j++
      fn({ atom: x.a, f: x.f })
    } else {
      var text = ""
      while (j < cells.length && !cells[j].a && cells[j].f === x.f && cells[j].l === x.l) { text += cells[j].c; j++ }
      fn({ text: text, f: x.f, l: x.l })
    }
    i = j
  }
}

function atomElement(a, f) {
  var el
  switch (a.k) {
  case "emoji": el = { type: "emoji", name: a.name }; if (a.tone) el.skin_tone = a.tone; return el
  case "user": el = { type: "user", user_id: a.id }; break
  case "channel": el = { type: "channel", channel_id: a.id }; break
  case "group": el = { type: "usergroup", usergroup_id: a.id }; break
  default: el = { type: "broadcast", range: a.id }
  }
  var st = styleOf(f.replace("c", ""))
  if (st) el.style = st
  return el
}

function inlineElements(out, cells, literal) {
  runs(cells, function(r) {
    if (r.atom) { out.push(atomElement(r.atom, literal ? "" : r.f)); return }
    var st = literal ? null : styleOf(r.f)
    if (r.l) {
      var el = { type: "link", url: r.l }
      if (r.text !== r.l) el.text = r.text
      if (st) el.style = st
      out.push(el)
    } else if (literal || r.f.indexOf("c") >= 0) Markup.pushText(out, r.text, st)
    else Markup.emit(out, r.text, flags(r.f))   // bare addresses, :emoji: typed as text
  })
}

// The document as Slack's client sends it: one rich_text block.
function toBlocks(doc) {
  var lines = trimmed(doc)
  var els = []
  var i = 0
  while (i < lines.length) {
    var L = lines[i], j = i
    if (L.k === "ul" || L.k === "ol") {
      var counters = {}
      while (j < lines.length && (lines[j].k === "ul" || lines[j].k === "ol")) {
        var k = lines[j].k, n = lines[j].n, items = []
        while (j < lines.length && lines[j].k === k && lines[j].n === n) {
          var ie = []
          inlineElements(ie, lines[j].cells, false)
          if (ie.length) items.push({ type: "rich_text_section", elements: ie })
          j++
        }
        for (var d in counters) if (Number(d) > n) delete counters[d]
        if (!items.length) continue
        var list = { type: "rich_text_list", style: k === "ol" ? "ordered" : "bullet", indent: n, border: 0, elements: items }
        if (k === "ol") { if (counters[n]) list.offset = counters[n]; counters[n] = (counters[n] || 0) + items.length }
        else delete counters[n]
        els.push(list)
      }
    } else {
      var out = []
      while (j < lines.length && lines[j].k === L.k) {
        if (j > i) Markup.pushText(out, "\n", null)
        inlineElements(out, lines[j].cells, L.k === "pre")
        j++
      }
      if (out.length) {
        if (L.k === "pre") els.push({ type: "rich_text_preformatted", elements: out, border: 0 })
        else els.push({ type: L.k === "q" ? "rich_text_quote" : "rich_text_section", elements: out })
      }
    }
    i = j
  }
  return [{ type: "rich_text", elements: els }]
}

// Underline has no markup: in the `text` (and drafts) it's plain words.
function wrapMarks(t, f) {
  if (!f) return t
  var lead = t.match(/^\s*/)[0]
  var core = t.slice(lead.length)
  var trail = core.match(/\s*$/)[0]
  core = core.slice(0, core.length - trail.length)
  if (!core) return t
  var open = "", close = ""
  if (f.indexOf("c") >= 0) { open = "`"; close = "`" }
  if (f.indexOf("x") >= 0) { open = "~" + open; close = close + "~" }
  if (f.indexOf("i") >= 0) { open = "_" + open; close = close + "_" }
  if (f.indexOf("b") >= 0) { open = "*" + open; close = close + "*" }
  return lead + open + core + close + trail
}

function inlineMarkup(cells, literal) {
  var s = ""
  runs(cells, function(r) {
    if (r.atom) { s += literal ? atomWire(r.atom) : wrapMarks(atomWire(r.atom), r.f.replace("c", "")); return }
    var t = r.l ? (r.text === r.l ? r.l : "<" + r.l + "|" + r.text.replace(/[<>|\n]/g, "") + ">") : r.text
    s += literal ? t : wrapMarks(t, r.f)
  })
  return s
}

// The document as box markup (Slack's markup with its wire references):
// the `text` that goes with the blocks, drafts, slash commands.
function toMarkup(doc) {
  var lines = trimmed(doc)
  var out = []
  var counters = {}
  var i = 0
  while (i < lines.length) {
    var L = lines[i]
    if (L.k === "pre") {
      var code = []
      while (i < lines.length && lines[i].k === "pre") { code.push(inlineMarkup(lines[i].cells, true)); i++ }
      out.push("```" + code.join("\n") + "```")
      counters = {}
      continue
    }
    if (L.k === "ul" || L.k === "ol") {
      for (var d in counters) if (Number(d) > L.n) delete counters[d]
      var pad = ""
      for (var p = 0; p < L.n; p++) pad += "  "
      var mark = "- "
      if (L.k === "ol") { counters[L.n] = (counters[L.n] || 0) + 1; mark = counters[L.n] + ". " }
      else delete counters[L.n]
      out.push(pad + mark + inlineMarkup(L.cells, false))
    } else {
      counters = {}
      out.push((L.k === "q" ? "> " : "") + inlineMarkup(L.cells, false))
    }
    i++
  }
  return out.join("\n")
}

// Plain words (copying out of the box): emoji by name, pills by label.
function flatText(lines) {
  return lines.map(function(l) {
    var s = ""
    runs(l.cells, function(r) { s += r.atom ? (r.atom.k === "emoji" ? emojiCode(r.atom) : r.atom.label) : r.text })
    return s
  }).join("\n")
}

// Hand-typed @here / #channel as pills (`find(sigil, name)` → atom | null).
function refs(doc, find) {
  var d = clone(doc), changed = false
  d.forEach(function(L) {
    if (L.k === "pre") return
    var s = ""
    L.cells.forEach(function(x) { s += x.a || x.l || x.f.indexOf("c") >= 0 ? OBJ : x.c })
    var re = /(^|[\s(])([@#])([A-Za-z0-9_.\-]{1,80})/g
    var cuts = [], m
    while ((m = re.exec(s)) !== null) {
      var name = m[3].replace(/[.\-]+$/, "")
      var a = name ? find(m[2], name) : null
      if (!a) continue
      var start = m.index + m[1].length
      cuts.push({ start: start, end: start + 1 + name.length, a: a })
    }
    for (var k = cuts.length - 1; k >= 0; k--) {
      var c = cuts[k]
      L.cells = L.cells.slice(0, c.start).concat(atomCells(c.a, L.cells[c.start].f), L.cells.slice(c.end))
      changed = true
    }
  })
  return changed ? d : doc
}

// ------------------------------------------------------------------ drawing

function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;") }

function blockStyle(top, bottom, left, right, extra) {
  return "margin-top:" + top + "px;margin-bottom:" + bottom + "px;margin-left:" + left + "px;margin-right:" + right +
         "px;-qt-block-indent:0;text-indent:0px;white-space:pre-wrap;" + (extra || "")
}

function marksHtml(h, f) {
  if (f.indexOf("x") >= 0) h = "<s>" + h + "</s>"
  if (f.indexOf("u") >= 0) h = "<u>" + h + "</u>"
  if (f.indexOf("i") >= 0) h = "<i>" + h + "</i>"
  if (f.indexOf("b") >= 0) h = "<b>" + h + "</b>"
  return h
}

// Addresses typed as text are drawn as links (Slack links them on send).
function urlsHtml(text, o) {
  var re = /https?:\/\/[^\s<>"]*[^\s<>".,;:!?)\]'*_~`]/g
  var out = "", last = 0, m
  while ((m = re.exec(text)) !== null) {
    out += esc(text.slice(last, m.index)) + "<span style=\"color:" + o.c.link + ";\">" + esc(m[0]) + "</span>"
    last = m.index + m[0].length
  }
  return out + esc(text.slice(last))
}

function atomHtml(a, f, o) {
  var h
  if (a.k === "emoji") {
    var src = o.blank && animated(a) ? o.blank : a.url
    if (a.url) h = "<img src=\"" + esc(src) + "\" width=\"" + o.emojiPx + "\" height=\"" + o.emojiPx + "\" style=\"vertical-align:middle;\" />"
    else h = "<span style=\"font-size:" + Math.round(o.emojiPx * 0.92) + "px;\">" + esc(atomText(a)) + "</span>"
  } else {
    var me = a.k === "broadcast" || (a.k === "user" && a.id === o.me)
    h = "<span style=\"color:" + (me ? o.c.meText : o.c.mention) + ";background-color:" + (me ? o.c.meBg : o.c.mentionBg) + ";\">" + esc(atomText(a)) + "</span>"
  }
  return marksHtml(h, f)
}

function inlineHtml(cells, o, literal) {
  var h = ""
  runs(cells, function(r) {
    if (r.atom) { h += atomHtml(r.atom, literal ? "" : r.f, o); return }
    var t
    if (literal) t = esc(r.text)
    else if (r.f.indexOf("c") >= 0) t = "<span style=\"font-family:" + o.mono + ";color:" + o.c.code + ";background-color:" + o.c.codeBg + ";\">" + esc(r.text) + "</span>"
    else if (r.l) t = "<span style=\"color:" + o.c.link + ";\">" + esc(r.text) + "</span>"
    else t = urlsHtml(r.text, o)
    h += literal ? t : marksHtml(t, r.f)
  })
  return h
}

var BULLETS = ["disc", "circle", "square"]
var NUMBERS = ["decimal", "lower-alpha", "lower-roman"]

// The document as the TextEdit's rich text: one Qt block per line, so the
// editor's text is the document's. `o`: c (Theme.html colors), mono,
// emojiPx, me (the user's id), quotePad, codePad, gap, blank (a see-through
// picture that holds an animated emoji's place, played over it by the
// composer; without it the GIF's first frame shows).
function toHtml(doc, o) {
  var h = ""
  var counters = {}
  var i = 0
  function body(L) { return L.cells.length ? inlineHtml(L.cells, o, L.k === "pre") : "<br />" }
  function blank(L) { return L.cells.length ? "" : "-qt-paragraph-type:empty;" }
  while (i < doc.length) {
    var L = doc[i]
    if (L.k === "ul" || L.k === "ol") {
      var j = i, items = ""
      while (j < doc.length && doc[j].k === L.k && doc[j].n === L.n) {
        items += "<li style=\"" + blockStyle(0, 0, 0, 0, blank(doc[j])) + "\">" + body(doc[j]) + "</li>"
        j++
      }
      for (var d in counters) if (Number(d) > L.n) delete counters[d]
      var start = 1
      if (L.k === "ol") { start = (counters[L.n] || 0) + 1; counters[L.n] = (counters[L.n] || 0) + (j - i) }
      else delete counters[L.n]
      var tag = L.k === "ol" ? "ol" : "ul"
      h += "<" + tag + (start > 1 ? " start=\"" + start + "\"" : "") + " style=\"margin-top:0px;margin-bottom:0px;margin-left:0px;margin-right:0px;-qt-list-indent:" +
           (L.n + 1) + ";list-style-type:" + (L.k === "ol" ? NUMBERS : BULLETS)[L.n % 3] + ";\">" + items + "</" + tag + ">"
      i = j
      continue
    }
    counters = {}
    var top = 0, bottom = 0, left = 0, right = 0, extra = ""
    if (L.k === "q") left = o.quotePad
    else if (L.k === "pre") {
      left = o.codePad + 2
      right = o.codePad
      if (i === 0 || doc[i - 1].k !== "pre") top = o.codePad + (i > 0 ? o.gap : 0)
      if (i === doc.length - 1 || doc[i + 1].k !== "pre") bottom = o.codePad + (i < doc.length - 1 ? o.gap : 0)
      extra = "font-family:" + o.mono + ";"
    }
    h += "<p style=\"" + blockStyle(top, bottom, left, right, extra + blank(L)) + "\">" + body(L) + "</p>"
    i++
  }
  return h
}

// Quotes and code blocks, as ranges, for the bar / box drawn behind them.
function groups(doc) {
  var out = [], pos = 0
  for (var i = 0; i < doc.length; i++) {
    var L = doc[i], start = pos
    pos += L.cells.length + 1
    if (L.k !== "q" && L.k !== "pre") continue
    var prev = out[out.length - 1]
    if (prev && prev.k === L.k && prev.li === i - 1) { prev.to = start + L.cells.length; prev.li = i }
    else out.push({ k: L.k, from: start, to: start + L.cells.length, li: i })
  }
  return out
}

// The animated emoji and where they are in the editor: [{pos, url}].
function gifs(doc) {
  var out = [], pos = 0
  doc.forEach(function(L) {
    L.cells.forEach(function(x, i) { if (animated(x.a)) out.push({ pos: pos + i, url: x.a.url }) })
    pos += L.cells.length + 1
  })
  return out
}

// ------------------------------------------------------------------ editing

// What text typed at `pos` looks like: the marks pending there (`typing`,
// B / I… pressed with nothing selected), else the character before's.
// Links don't grow at their ends; code blocks take no marks.
function formatAt(doc, pos, typing) {
  if (typing && typing.pos === pos) return { f: typing.f, l: "" }
  var at = locate(doc, pos), L = doc[at.li], cs = L.cells
  if (L.k === "pre") return { f: "", l: "" }
  if (at.col > 0) {
    var prev = cs[at.col - 1], next = cs[at.col]
    return { f: prev.f, l: bare(prev) && prev.l && bare(next) && next.l === prev.l ? prev.l : "" }
  }
  var first = cs[0]
  return { f: bare(first) ? first.f.replace("c", "") : "", l: "" }
}

function textLines(text, f, l) {
  return normalize(text).split("\n").map(function(s) {
    var cs = []
    for (var i = 0; i < s.length; i++) if (s.charAt(i) !== OBJ) cs.push(cell(s.charAt(i), f, l, null))
    return loose(cs)
  })
}

// [a, b) becomes the lines `ins`: the first joins the text before, the last
// the text after; lines without a kind take the kind of the line the edit
// starts in. → {doc, cursor (after the insertion)}
function replace(doc, a, b, ins) {
  if (a > b) { var t = a; a = b; b = t }
  var d = clone(doc)
  var A = locate(d, a), B = locate(d, b)
  var first = d[A.li]
  var head = first.cells.slice(0, A.col), tail = d[B.li].cells.slice(B.col)
  if (!ins || !ins.length) ins = [loose([])]
  var out = []
  for (var i = 0; i < ins.length; i++) {
    var src = ins[i]
    var k = first.k, n = first.n
    if (src.k && (i > 0 || (!head.length && first.k === "p"))) { k = src.k; n = src.n }
    var cells = src.cells
    if (i === 0) cells = head.concat(cells)
    if (i === ins.length - 1) cells = cells.concat(tail)
    if (k === "pre") cells = cells.map(function(x) { return x.f ? cell(x.c, "", x.l, x.a) : x })
    out.push(line(k, n, cells))
  }
  Array.prototype.splice.apply(d, [A.li, B.li - A.li + 1].concat(out))
  var lastIns = ins[ins.length - 1].cells.length
  return { doc: d, cursor: posOf(d, A.li + ins.length - 1, (ins.length === 1 ? head.length : 0) + lastIns) }
}

function span(doc, a, b) {
  if (a > b) { var t = a; a = b; b = t }
  if (a === b) { var p = snap(doc, a, true); return [p, p] }
  return expand(doc, a, b)
}

// Typed / pasted text in place of [a, b). `fmt`: {f, l}.
function insertText(doc, a, b, text, fmt) {
  var s = span(doc, a, b)
  return replace(doc, s[0], s[1], textLines(text, fmt ? fmt.f : "", fmt ? fmt.l : ""))
}
function insertLines(doc, a, b, lines) {
  var s = span(doc, a, b)
  return replace(doc, s[0], s[1], lines)
}
// An emoji or a pill in place of [a, b), and `after` (a space) behind it.
function insertAtom(doc, a, b, atom, f, after) {
  var s = span(doc, a, b)
  var cells = atomCells(atom, f || "")
  for (var i = 0; i < (after || "").length; i++) cells.push(cell(after.charAt(i), f || "", "", null))
  return replace(doc, s[0], s[1], [loose(cells)])
}

// [a, b) of the document as lines of their own (copy, cut).
function slice(doc, a, b) {
  var s = expand(doc, Math.min(a, b), Math.max(a, b))
  var A = locate(doc, s[0]), B = locate(doc, s[1]), out = []
  for (var li = A.li; li <= B.li; li++) {
    var from = li === A.li ? A.col : 0, to = li === B.li ? B.col : doc[li].cells.length
    out.push(line(doc[li].k, doc[li].n, doc[li].cells.slice(from, to)))
  }
  return out
}
function textOf(doc, a, b) { return a === b ? "" : flatText(slice(doc, a, b)) }

// The editor's new text against the document: the one change between them
// (typing, deleting, Qt's own paste…), taken where the cursor says it
// happened. Pills and emoji go whole. → {doc, cursor, at, text, typed} or
// null when nothing changed. `typed`: one character typed in place.
function applyDiff(doc, now, hint, typing) {
  var old = plain(doc)
  if (old === now) return null
  var max = Math.min(old.length, now.length)
  var suf = 0
  while (suf < max && old.charCodeAt(old.length - 1 - suf) === now.charCodeAt(now.length - 1 - suf)) suf++
  if (hint >= 0 && hint <= now.length) suf = Math.min(suf, now.length - hint)
  var pre = 0
  while (pre < max - suf && old.charCodeAt(pre) === now.charCodeAt(pre)) pre++
  var a = pre, b = old.length - suf
  var text = now.slice(pre, now.length - suf)
  var s = span(doc, a, b)
  var fmt = formatAt(doc, s[0], typing)
  var r = replace(doc, s[0], s[1], textLines(text, fmt.f, fmt.l))
  return { doc: r.doc, cursor: r.cursor, at: s[0], text: text,
           typed: a === b && s[0] === a && text.length === 1 && text !== "\n" && text !== OBJ }
}

// Slack's markdown as you type, after the character before `pos` was typed:
// *bold* _italic_ ~strike~ `code`, ``` (code block in / out), "> " quote,
// "- " / "1. " lists, :emoji: → {doc, cursor, typing} or null.
function autoformat(doc, pos, ctx) {
  var at = locate(doc, pos), L = doc[at.li], cs = L.cells, col = at.col
  if (col === 0 || !bare(cs[col - 1])) return null
  var ch = cs[col - 1].c
  if (ch === "`" && col >= 3 && bare(cs[col - 2]) && cs[col - 2].c === "`" && bare(cs[col - 3]) && cs[col - 3].c === "`") return fence(doc, at.li, col)
  if (L.k === "pre" || cs[col - 1].f.indexOf("c") >= 0) return null
  if (ch === " ") return listStart(doc, at.li, col)
  if (ch === ":") return emojiName(doc, at.li, col, ctx)
  if (MARK_OF[ch]) return closeMark(doc, at.li, col, ch)
  return null
}

function closeMark(doc, li, col, m) {
  var cs = doc[li].cells, close = col - 1, flag = MARK_OF[m]
  if (close < 2) return null
  var inner = cs[close - 1]
  if (bare(inner) && isSpace(inner.c)) return null
  var after = cs[col]
  if (bare(after) && isAlnum(after.c)) return null
  for (var o = close - 2; o >= 0; o--) {
    var x = cs[o]
    if (!bare(x) || x.c !== m || x.f.indexOf("c") >= 0) continue
    var nx = cs[o + 1]
    if (bare(nx) && isSpace(nx.c)) continue
    var pv = cs[o - 1]
    if (bare(pv) && isAlnum(pv.c)) continue
    var mid = cs.slice(o + 1, close).map(function(y) { return cell(y.c, withMark(y.f, flag, true), flag === "c" ? "" : y.l, y.a) })
    var d = clone(doc)
    d[li].cells = cs.slice(0, o).concat(mid, cs.slice(col))
    var cur = posOf(d, li, close - 1)
    // What comes next is back to the marks before the closing one.
    return { doc: d, cursor: cur, typing: { pos: cur, f: cs[close].f } }
  }
  return null
}

function listStart(doc, li, col) {
  var L = doc[li]
  if (L.k !== "p") return null
  var cs = L.cells, pre = ""
  for (var i = 0; i < col - 1; i++) { if (!bare(cs[i])) return null; pre += cs[i].c }
  var k = pre === ">" ? "q" : (pre === "-" || pre === "*" || pre === "•") ? "ul" : /^\d{1,3}[.)]$/.test(pre) ? "ol" : ""
  if (!k) return null
  var d = clone(doc)
  d[li] = line(k, 0, cs.slice(col))
  return { doc: d, cursor: posOf(d, li, 0), typing: null }
}

function emojiName(doc, li, col, ctx) {
  var cs = doc[li].cells, close = col - 1
  var j = close - 1, name = ""
  while (j >= 0 && bare(cs[j]) && NAME_CH.test(cs[j].c)) { name = cs[j].c + name; j-- }
  if (!name || j < 0 || !bare(cs[j]) || cs[j].c !== ":") return null
  var pv = cs[j - 1]
  if (bare(pv) && isAlnum(pv.c)) return null
  var d = clone(doc)
  var tm = name.match(/^skin-tone-([2-6])$/)
  if (tm) {
    // ":skin-tone-3:" right after an emoji gives it that tone.
    if (!pv || !pv.a || pv.a.k !== "emoji") return null
    var s = j - 1
    while (s > 0 && cs[s - 1].a === pv.a) s--
    var toned = mkEmoji(pv.a.name, parseInt(tm[1], 10), ctx)
    if (!drawable(toned)) return null
    var tc = atomCells(toned, pv.f)
    d[li].cells = cs.slice(0, s).concat(tc, cs.slice(col))
    return { doc: d, cursor: posOf(d, li, s + tc.length), typing: null }
  }
  var a = mkEmoji(name, 0, ctx)
  if (!drawable(a)) return null
  var ac = atomCells(a, cs[j].f)
  d[li].cells = cs.slice(0, j).concat(ac, cs.slice(col))
  return { doc: d, cursor: posOf(d, li, j + ac.length), typing: null }
}

// ``` typed: outside a code block it starts one (the rest of the line goes
// in); inside, it leaves it (the rest of the line comes out).
function fence(doc, li, col) {
  var L = doc[li], cs = L.cells
  var head = cs.slice(0, col - 3), tail = cs.slice(col)
  var lines
  if (L.k === "pre") lines = head.length ? [line("pre", 0, head), line("p", 0, tail)] : [line("p", 0, tail)]
  else {
    var code = line("pre", 0, tail.map(function(x) { return cell(x.c, "", x.l, x.a) }))
    lines = head.length ? [line(L.k, L.n, head), code] : [code]
  }
  var d = clone(doc)
  Array.prototype.splice.apply(d, [li, 1].concat(lines))
  return { doc: d, cursor: posOf(d, li + lines.length - 1, 0), typing: null }
}

// ------------------------------------------------------------------ formatting

function eachCell(doc, a, b, fn) {
  var A = locate(doc, Math.min(a, b)), B = locate(doc, Math.max(a, b))
  for (var li = A.li; li <= B.li; li++) {
    var s = li === A.li ? A.col : 0, e = li === B.li ? B.col : doc[li].cells.length
    for (var i = s; i < e; i++) fn(doc[li], i, li)
  }
}

// B / I / U / S / code on [a, b): off when all of it has it, else on. Code
// block lines keep no marks.
function toggleMark(doc, a, b, m) {
  if (a === b) return null
  var all = true, any = false
  eachCell(doc, a, b, function(L, i) {
    if (L.k === "pre") return
    var x = L.cells[i]
    if (bare(x) && isSpace(x.c)) return
    any = true
    if (x.f.indexOf(m) < 0) all = false
  })
  if (!any) return null
  var d = clone(doc)
  eachCell(d, a, b, function(L, i) {
    if (L.k === "pre") return
    var x = L.cells[i]
    L.cells[i] = cell(x.c, withMark(x.f, m, !all), m === "c" ? "" : x.l, x.a)
  })
  return d
}

function setLink(doc, a, b, url) {
  var d = clone(doc)
  eachCell(d, a, b, function(L, i) { var x = L.cells[i]; if (bare(x)) L.cells[i] = cell(x.c, x.f.replace("c", ""), url, null) })
  return d
}

// What the toolbar shows as on at [a, b): marks (all of a selection has
// them), the link under the cursor, the kind of the lines.
function marksAt(doc, a, b, typing) {
  var out = { b: false, i: false, u: false, x: false, c: false, link: "", k: "p", n: 0 }
  var lo = Math.min(a, b), hi = Math.max(a, b)
  var A = locate(doc, lo), B = locate(doc, hi)
  if (hi > lo && B.col === 0 && B.li > A.li) B = { li: B.li - 1, col: doc[B.li - 1].cells.length }
  var k = doc[A.li].k
  for (var li = A.li + 1; li <= B.li; li++) if (doc[li].k !== k) k = "mixed"
  out.k = k
  out.n = doc[A.li].n
  if (k === "pre") return out
  if (lo === hi) {
    var fmt = formatAt(doc, lo, typing)
    for (var m = 0; m < MARKS.length; m++) out[MARKS.charAt(m)] = fmt.f.indexOf(MARKS.charAt(m)) >= 0
    var prev = doc[A.li].cells[A.col - 1]
    out.link = bare(prev) ? prev.l : ""
    return out
  }
  var fs = [], link = null
  eachCell(doc, lo, hi, function(L, i) {
    var x = L.cells[i]
    if (L.k === "pre" || (bare(x) && isSpace(x.c))) return
    fs.push(x.f)
    if (link === null) link = x.l
    else if (link !== x.l) link = ""
  })
  for (var n = 0; n < MARKS.length; n++) {
    var mk = MARKS.charAt(n)
    out[mk] = fs.length > 0 && fs.every(function(f) { return f.indexOf(mk) >= 0 })
  }
  out.link = link || ""
  return out
}

function lineRange(doc, a, b) {
  var lo = Math.min(a, b), hi = Math.max(a, b)
  var A = locate(doc, lo), B = locate(doc, hi)
  return [A.li, hi > lo && B.col === 0 && B.li > A.li ? B.li - 1 : B.li]
}

function setKind(doc, a, b, kind) {
  var r = lineRange(doc, a, b), d = clone(doc)
  for (var li = r[0]; li <= r[1]; li++) {
    var L = d[li]
    var n = (kind === "ul" || kind === "ol") && (L.k === "ul" || L.k === "ol") ? L.n : 0
    d[li] = line(kind, n, kind === "pre" ? L.cells.map(function(x) { return x.f ? cell(x.c, "", x.l, x.a) : x }) : L.cells)
  }
  return d
}

// Lists, quote, code block on the lines of [a, b): off when they all are.
function toggleKind(doc, a, b, kind) {
  var r = lineRange(doc, a, b), all = true
  for (var li = r[0]; li <= r[1]; li++) if (doc[li].k !== kind) all = false
  return setKind(doc, a, b, all ? "p" : kind)
}

function indent(doc, a, b, delta) {
  var r = lineRange(doc, a, b), d = clone(doc), any = false
  for (var li = r[0]; li <= r[1]; li++) {
    var L = d[li]
    if (L.k !== "ul" && L.k !== "ol") continue
    var n = Math.max(0, Math.min(8, L.n + delta))
    if (n !== L.n) { d[li] = line(L.k, n, L.cells); any = true }
  }
  return any ? d : null
}
