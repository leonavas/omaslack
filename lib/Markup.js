.pragma library

// The message box's markup going out to Slack, the way the official
// clients send it: `text` escaped for notifications, and the same text as
// one `rich_text` block (bold, italic, strike, code, code blocks, quotes,
// lists, links, mentions, emoji). Also the way back, a message's blocks as
// box markup, for editing. Links with words of their own are written as
// Slack writes them, <https://…|words>.

var REF = /^<([@#][A-Z0-9]+|![A-Za-z0-9^_.\-]+|(?:https?:\/\/|mailto:)[^\s<>|]+)(\|[^<>\n]*)?>/
var LINK_REF = /^<(?:https?:\/\/|mailto:)/

function isAlnum(c) { return !!c && (/[A-Za-z0-9]/.test(c) || c.toLowerCase() !== c.toUpperCase()) }
function isSpace(c) { return !c || /\s/.test(c) }

// & < > escaped, Slack references (<@U1>, <#C1>, <!here>) kept as they are.
function escape(s) {
  s = String(s || "")
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if (c === "<") {
      var m = s.slice(i).match(REF)
      if (m) { out += LINK_REF.test(m[0]) ? m[0].replace(/&/g, "&amp;") : m[0]; i += m[0].length - 1; continue }
      out += "&lt;"
    } else if (c === "&") out += "&amp;"
    else if (c === ">") out += "&gt;"
    else out += c
  }
  return out
}

// ------------------------------------------------------------------ inline

// Atoms the style markers never look inside: Slack refs and bare URLs.
function atomAt(s, i) {
  if (s[i] === "<") {
    var m = s.slice(i).match(REF)
    if (m) return { len: m[0].length, kind: "ref", text: m[0] }
  }
  if ((s.substr(i, 7) === "http://" || s.substr(i, 8) === "https://") && (i === 0 || !isAlnum(s[i - 1]))) {
    var j = i
    while (j < s.length && !/[\s<>]/.test(s[j])) j++
    var url = s.slice(i, j)
    for (;;) {
      var last = url.charAt(url.length - 1)
      if (".,;:!?*_~'\"`".indexOf(last) >= 0) { url = url.slice(0, -1); continue }
      if (last === ")" && url.indexOf("(") < 0) { url = url.slice(0, -1); continue }
      break
    }
    if (url.length > 8) return { len: url.length, kind: "url", text: url }
  }
  return null
}

function refElement(text, style) {
  var inner = text.slice(1, -1)
  var bar = inner.indexOf("|")
  var label = bar >= 0 ? inner.slice(bar + 1) : ""
  var id = bar >= 0 ? inner.slice(0, bar) : inner
  var el
  if (LINK_REF.test(text)) { el = { type: "link", url: id }; if (label && label !== id) el.text = label }
  else if (id[0] === "@") el = { type: "user", user_id: id.slice(1) }
  else if (id[0] === "#") el = { type: "channel", channel_id: id.slice(1) }
  else if (id.indexOf("!subteam^") === 0) el = { type: "usergroup", usergroup_id: id.slice(9) }
  else if (/^!(here|channel|everyone)$/.test(id)) el = { type: "broadcast", range: id.slice(1) }
  else el = { type: "text", text: label || id.slice(1) }
  if (style) el.style = style
  return el
}

function styleOf(st) {
  var o = {}, any = false
  if (st.bold) { o.bold = true; any = true }
  if (st.italic) { o.italic = true; any = true }
  if (st.underline) { o.underline = true; any = true }
  if (st.strike) { o.strike = true; any = true }
  if (st.code) { o.code = true; any = true }
  return any ? o : null
}

function sameStyle(a, b) { return JSON.stringify(a || null) === JSON.stringify(b || null) }

function pushText(out, text, style) {
  if (!text) return
  var last = out[out.length - 1]
  if (last && last.type === "text" && sameStyle(last.style, style)) { last.text += text; return }
  var el = { type: "text", text: text }
  if (style) el.style = style
  out.push(el)
}

// Text with refs / urls / emoji → elements, in one style.
function emit(out, s, st, literal) {
  var style = styleOf(st)
  var buf = ""
  var i = 0
  while (i < s.length) {
    var a = atomAt(s, i)
    if (a) {
      pushText(out, buf, style); buf = ""
      if (a.kind === "ref") out.push(refElement(a.text, style))
      else { var l = { type: "link", url: a.text }; if (style) l.style = style; out.push(l) }
      i += a.len
      continue
    }
    if (!literal && !st.code && s[i] === ":" && (i === 0 || !isAlnum(s[i - 1]))) {
      var m = s.slice(i).match(/^:([A-Za-z0-9_+'\-]+):(?::skin-tone-([2-6]):)?/)
      if (m) {
        pushText(out, buf, style); buf = ""
        var e = { type: "emoji", name: m[1] }
        if (m[2]) e.skin_tone = parseInt(m[2], 10)
        if (style) e.style = style
        out.push(e)
        i += m[0].length
        continue
      }
    }
    buf += s[i]
    i++
  }
  pushText(out, buf, style)
}

function findCloser(s, i, mark) {
  for (var j = i + 2; j < s.length; j++) {
    var a = atomAt(s, j)
    if (a) { j += a.len - 1; continue }
    if (s[j] === mark && !isSpace(s[j - 1]) && !isAlnum(s[j + 1])) return j
  }
  return -1
}

function inline(out, s, st) {
  var buf = ""
  var i = 0
  while (i < s.length) {
    var a = atomAt(s, i)
    if (a) { buf += s.substr(i, a.len); i += a.len; continue }
    var c = s[i]
    if (c === "`") {
      var k = s.indexOf("`", i + 1)
      if (k > i + 1) {
        emit(out, buf, st); buf = ""
        var cs = { bold: st.bold, italic: st.italic, strike: st.strike, code: true }
        emit(out, s.slice(i + 1, k), cs)
        i = k + 1
        continue
      }
    }
    if ((c === "*" || c === "_" || c === "~") && (i === 0 || !isAlnum(s[i - 1])) && !isSpace(s[i + 1])) {
      var e = findCloser(s, i, c)
      if (e > i + 1) {
        emit(out, buf, st); buf = ""
        var ns = { bold: st.bold, italic: st.italic, strike: st.strike, code: st.code }
        if (c === "*") ns.bold = true
        else if (c === "_") ns.italic = true
        else ns.strike = true
        inline(out, s.slice(i + 1, e), ns)
        i = e + 1
        continue
      }
    }
    buf += c
    i++
  }
  emit(out, buf, st)
}

function lineElements(line) {
  var out = []
  inline(out, line, {})
  return out
}

// ------------------------------------------------------------------ blocks

function blocks(text) {
  text = String(text || "")
  var els = []
  // Code fences, paired in order; an unpaired last one is plain text.
  var fences = []
  var at = text.indexOf("```")
  while (at >= 0) { fences.push(at); at = text.indexOf("```", at + 3) }
  if (fences.length % 2 === 1) fences.pop()
  var pos = 0
  for (var f = 0; f < fences.length; f += 2) {
    var before = text.slice(pos, fences[f])
    if (pos > 0) before = before.replace(/^\n/, "")
    before = before.replace(/\n$/, "")
    lines(els, before)
    var code = text.slice(fences[f] + 3, fences[f + 1]).replace(/^\n/, "").replace(/\n$/, "")
    if (code.length) {
      var ce = []
      emit(ce, code, {}, true)
      els.push({ type: "rich_text_preformatted", elements: ce, border: 0 })
    }
    pos = fences[f + 1] + 3
  }
  var rest = text.slice(pos)
  if (pos > 0) rest = rest.replace(/^\n/, "")
  lines(els, rest)
  return [{ type: "rich_text", elements: els }]
}

function lines(els, text) {
  if (!text) return
  var ls = text.split("\n")
  var group = null // {kind: "plain"|"quote"|"bullet"|"ordered", indent, items}
  function flush() {
    if (!group) return
    if (group.kind === "plain" || group.kind === "quote") {
      var out = []
      for (var i = 0; i < group.items.length; i++) {
        if (i > 0) pushText(out, "\n", null)
        var le = lineElements(group.items[i])
        for (var j = 0; j < le.length; j++) {
          if (le[j].type === "text") pushText(out, le[j].text, le[j].style || null)
          else out.push(le[j])
        }
      }
      if (out.length) els.push({ type: group.kind === "quote" ? "rich_text_quote" : "rich_text_section", elements: out })
    } else {
      var items = group.items.filter(function(x) { return x.trim().length > 0 }).map(function(x) {
        return { type: "rich_text_section", elements: lineElements(x) }
      })
      if (items.length) {
        var l = { type: "rich_text_list", style: group.kind === "ordered" ? "ordered" : "bullet", indent: group.indent, border: 0, elements: items }
        if (group.kind === "ordered" && group.first > 1) l.offset = group.first - 1
        els.push(l)
      }
    }
    group = null
  }
  for (var n = 0; n < ls.length; n++) {
    var line = ls[n]
    var kind = "plain", indent = 0, content = line, num = 0
    var q = line.match(/^>( ?)/)
    var b = line.match(/^( *)[-*•] (.*)$/)
    var o = line.match(/^( *)(\d{1,3})\. (.*)$/)
    if (q) { kind = "quote"; content = line.slice(q[0].length) }
    else if (b) { kind = "bullet"; indent = Math.min(Math.floor(b[1].length / 2), 8); content = b[2] }
    else if (o) { kind = "ordered"; indent = Math.min(Math.floor(o[1].length / 2), 8); content = o[3]; num = parseInt(o[2], 10) }
    if (!group || group.kind !== kind || ((kind === "bullet" || kind === "ordered") && group.indent !== indent)) {
      flush()
      group = { kind: kind, indent: indent, items: [], first: num }
    }
    group.items.push(content)
  }
  flush()
}

// Whether the cursor sits inside an open ``` block (Enter adds a line there).
function inBlock(text, cursor) {
  var before = String(text || "").slice(0, cursor)
  var n = 0, at = before.indexOf("```")
  while (at >= 0) { n++; at = before.indexOf("```", at + 3) }
  return n % 2 === 1
}

// ------------------------------------------------------------------ back

// A message's rich_text blocks as box markup (for editing); "" when the
// blocks aren't all rich_text (then the caller uses the message text).
function markup(blocksArr) {
  if (!blocksArr || !blocksArr.length) return ""
  for (var i = 0; i < blocksArr.length; i++) if (blocksArr[i].type !== "rich_text") return ""
  var parts = []
  blocksArr.forEach(function(b) {
    (b.elements || []).forEach(function(e) {
      if (e.type === "rich_text_section") parts.push(inlineBack(e.elements).replace(/\n$/, ""))
      else if (e.type === "rich_text_quote") parts.push(inlineBack(e.elements).replace(/\n$/, "").split("\n").map(function(l) { return "> " + l }).join("\n"))
      else if (e.type === "rich_text_preformatted") {
        var code = (e.elements || []).map(function(x) { return x.type === "text" ? x.text : refBack(x) }).join("")
        parts.push(code.indexOf("\n") >= 0 ? "```\n" + code + "\n```" : "```" + code + "```")
      } else if (e.type === "rich_text_list") {
        var pad = ""
        for (var p = 0; p < (e.indent || 0); p++) pad += "  "
        ;(e.elements || []).forEach(function(it, k) {
          parts.push(pad + (e.style === "ordered" ? ((e.offset || 0) + k + 1) + ". " : "- ") + inlineBack(it.elements).replace(/\n$/, ""))
        })
      }
    })
  })
  return parts.join("\n")
}

function refBack(x) {
  switch (x.type) {
  case "link": return x.text && x.text !== x.url ? "<" + x.url + "|" + x.text.replace(/[<>|\n]/g, "") + ">" : x.url
  case "user": return "<@" + x.user_id + ">"
  case "channel": return "<#" + x.channel_id + ">"
  case "usergroup": return "<!subteam^" + x.usergroup_id + ">"
  case "broadcast": return "<!" + x.range + ">"
  case "emoji": return ":" + x.name + ":" + (x.skin_tone ? ":skin-tone-" + x.skin_tone + ":" : "")
  case "date": return x.fallback || ""
  case "color": return x.value || ""
  default: return x.text || ""
  }
}

function inlineBack(els) {
  var out = ""
  ;(els || []).forEach(function(x) {
    var t = x.type === "text" ? x.text : refBack(x)
    var st = x.style || {}
    if (!t) return
    var lead = t.match(/^\s*/)[0], trail = t.match(/\s*$/)[0]
    var core = t.slice(lead.length, t.length - trail.length)
    if (!core) { out += t; return }
    var open = "", close = ""
    if (st.code) { open = "`"; close = "`" }
    if (st.strike) { open = "~" + open; close = close + "~" }
    if (st.italic) { open = "_" + open; close = close + "_" }
    if (st.bold) { open = "*" + open; close = close + "*" }
    out += lead + open + core + close + trail
  })
  return out
}
