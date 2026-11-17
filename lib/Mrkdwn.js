.pragma library
.import "Util.js" as U
.import "Emoji.js" as E

// Incoming messages → what the views draw. A message becomes a list of
// parts; text parts carry HTML for QML's rich text (links, mentions,
// emoji, inline code), the rest (quotes, code blocks, Block Kit images,
// buttons, attachments) are drawn by their own components.
//
// `ctx` describes the workspace for the renderer:
//   me            the user's id
//   lang, clock24
//   user(id)      → display name or ""
//   conv(id)      → {name, private} or null
//   custom, aliases   custom emoji {name: url}, aliases {name: glyph}
//   slackEmoji    Slack's emoji pictures (else the font's)
//   previewImages pictures from other sites (an app link's icon)
//   c             colors as "#rrggbb": link, mention, mentionBg, meText,
//                 meBg, code, codeBg, dim, text; pillSpacing, codeSpacing
//                 (px, `pill`, `codeSpan`)
//   emojiPx       emoji size in the text
//   ask(kind, id) asks the store to look a name up ("user" / "conv")

var SYSTEM_SUBTYPES = ["channel_join", "group_join", "channel_leave", "group_leave"]

function unescape(s) { return String(s || "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&") }
function esc(s) { return U.escapeHtml(s) }
function isAlnum(c) { return !!c && (/[A-Za-z0-9]/.test(c) || U.isLetter(c)) }
function isSpace(c) { return !c || /\s/.test(c) }

// ------------------------------------------------------------------ pills

// Slack's pill: the name on its tint, with a little room at both ends.
// Rich text has no padding for inline text, and a space at a pill's start
// goes into the one before it (thin ones too: they come in as spaces), so
// the room is a no-break space at each end that the pills' word spacing
// (`c.pillSpacing`, Theme) draws a couple of pixels wide; a space in the
// name is a space and one of those, so it keeps its width. One span, one
// background: pieces of it would show seams. Copies leave the room out
// (RichText.copySelection).
var NBSP = String.fromCharCode(0xa0)

// Slack can leave its search highlight marks (\ue000 … \ue001) in an
// unfurled link's title; the icon font draws them as glyphs.
function unmark(s) { return String(s || "").replace(/[\ue000\ue001]/g, "") }

// `lead`: HTML before the text (an app link's icon).
function pill(text, fg, bg, href, c, lead) {
  var ws = c && typeof c.pillSpacing === "number" ? "word-spacing:" + c.pillSpacing + "px;" : ""
  var inner = "<span style=\"color:" + fg + ";background-color:" + bg + ";" + ws + "\">" + NBSP + (lead || "") + esc(text).replace(/ /g, " " + NBSP) + NBSP + "</span>"
  return href ? "<a href=\"" + esc(href) + "\" style=\"text-decoration:none;\">" + inner + "</a>" : inner
}

function userPill(id, label, ctx) {
  var name = ctx.user(id)
  if (!name) {
    if (ctx.ask) ctx.ask("user", id)
    name = label ? String(label).replace(/^@/, "") : id
  }
  var me = id === ctx.me
  return pill("@" + name, me ? ctx.c.meText : ctx.c.mention, me ? ctx.c.meBg : ctx.c.mentionBg, "slackqs://user/" + id, ctx.c)
}

function convPill(id, label, ctx) {
  var c = ctx.conv(id)
  var name = label || (c && c.name) || ""
  if (!c && ctx.ask) ctx.ask("conv", id)
  if (!name) name = "…"
  var lock = c && c.private
  return pill((lock ? "󰌾" : "#") + name, ctx.c.mention, ctx.c.mentionBg, "slackqs://channel/" + id, ctx.c)
}

function broadcastPill(range, ctx) {
  return pill("@" + range, ctx.c.meText, ctx.c.meBg, "", ctx.c)
}

// A standard emoji: Slack's picture of it (the Apple set the official app
// draws), or the system font's glyph when the app is set to that. A
// picture's alt is what a copy of the text says for it (RichText).
function glyphHtml(glyph, ctx, px) {
  px = px || ctx.emojiPx
  if (ctx.slackEmoji !== false) {
    var g = E.known(glyph) || glyph
    return "<img src=\"" + E.imageUrl(g) + "\" alt=\"" + esc(glyph) + "\" width=\"" + px + "\" height=\"" + px + "\" />"
  }
  return "<span style=\"font-size:" + Math.round(px * 0.92) + "px;\">" + esc(glyph) + "</span>"
}

function emojiHtml(name, ctx, px) {
  var r = E.resolve(name, ctx.custom, ctx.aliases)
  if (!r) return null
  px = px || ctx.emojiPx
  if (r.glyph) return glyphHtml(r.glyph, ctx, px)
  return "<img src=\"" + esc(r.url) + "\" alt=\"" + esc(":" + name + ":") + "\" width=\"" + px + "\" height=\"" + px + "\" />"
}

// Plain text with emoji typed as characters turned into pictures too.
function textHtml(text, ctx, px) {
  if (ctx.slackEmoji === false) return esc(text)
  return E.split(text).map(function(run) { return run[0] ? glyphHtml(run[1], ctx, px) : esc(run[1]) }).join("")
}

function aOpen(url, ctx) {
  return "<a href=\"" + esc(url) + "\" style=\"color:" + ctx.c.link + ";text-decoration:none;\">"
}

// Inline code: its room the way a pill has it (`pill`), drawn by the code
// font's word spacing (`c.codeSpacing`). Spaces are no-break spaces, so
// they keep their count; a run of them inside the code takes one more,
// as only a run's last one is drawn narrow.
function codeSpan(text, ctx) {
  var ws = typeof ctx.c.codeSpacing === "number" ? "word-spacing:" + ctx.c.codeSpacing + "px;" : ""
  var t = esc(text)
  t = t.replace(/ +/g, function(run, at) { return NBSP.repeat(run.length) + (at > 0 && at + run.length < t.length ? NBSP : "") })
  return "<span style=\"font-family:monospace;color:" + ctx.c.code + ";background-color:" + ctx.c.codeBg + ";" + ws + "\">" + NBSP + t + NBSP + "</span>"
}

// Plain text (already unescaped) with :shortcodes:, to HTML.
function plainHtml(text, ctx, px) {
  var out = ""
  var re = /:([A-Za-z0-9_+'\-]+):(?::(skin-tone-[2-6]):)?/g
  var last = 0, m
  while ((m = re.exec(text)) !== null) {
    var h = emojiHtml(m[2] ? m[1] + "::" + m[2] : m[1], ctx, px)
    if (h === null) continue
    out += textHtml(text.slice(last, m.index), ctx, px) + h
    last = m.index + m[0].length
  }
  out += textHtml(text.slice(last), ctx, px)
  return out.replace(/\n/g, "<br/>")
}

// ------------------------------------------------------------------ mrkdwn

function linkToken(inner, ctx) {
  var bar = inner.indexOf("|")
  var target = bar >= 0 ? inner.slice(0, bar) : inner
  var rawLabel = bar >= 0 ? inner.slice(bar + 1).trim() : ""
  var label = unescape(rawLabel)
  var c0 = target.charAt(0)
  if (c0 === "@" && /^@[UWB][A-Z0-9]+$/.test(target)) return userPill(target.slice(1), label, ctx)
  if (c0 === "#" && /^#[CGD][A-Z0-9]+$/.test(target)) return convPill(target.slice(1), label, ctx)
  if (c0 === "!") {
    var body = target.slice(1)
    if (body === "here" || body === "channel" || body === "everyone") return broadcastPill(body, ctx)
    if (body.indexOf("subteam^") === 0) return pill(label || "@subteam", ctx.c.mention, ctx.c.mentionBg, "", ctx.c)
    if (body.indexOf("date^") === 0) return esc(label || dateToken(body, ctx))
    return esc(label || "@" + body.split("^")[0])
  }
  if (target.indexOf("mailto:") === 0) {
    return aOpen(target, ctx) + esc(label || target.slice(7)) + "</a>"
  }
  var url = unescape(target)
  // Labels keep their own formatting (GitHub's `sha (main)`, *bold*…).
  var shown = rawLabel ? inlineMrkdwn(rawLabel, ctx) : esc(url)
  return aOpen(url, ctx) + shown + "</a>"
}

// <!date^1700000000^{date_short} at {time}|fallback>
function dateToken(body, ctx) {
  var parts = body.split("^")
  var epoch = parseInt(parts[1] || "0", 10)
  if (!epoch) return ""
  return dateFormat(new Date(epoch * 1000), parts[2] || "{date_short}", ctx)
}

// Slack's date tokens: the `_pretty` ones say Today / Yesterday /
// Tomorrow when they can; {day_divider_pretty} as the day dividers do.
function dateFormat(d, fmt, ctx) {
  var diff = U.dayDiff(d, new Date())
  var near = diff === 0 ? U.tr(ctx.lang, "Today", "Hoje") : diff === 1 ? U.tr(ctx.lang, "Yesterday", "Ontem") : diff === -1 ? U.tr(ctx.lang, "Tomorrow", "Amanhã") : ""
  var short = U.shortDate(d, ctx.lang)
  return String(fmt)
    .replace(/\{date_num\}/g, String(d.getFullYear()) + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"))
    .replace(/\{day_divider_pretty\}/g, function() { return U.dayLabel(d, ctx.lang) })
    .replace(/\{date_(short_|long_)?pretty\}/g, function(all, kind) { return near || (kind === "short_" ? short : U.fullDate(d, ctx.lang)) })
    .replace(/\{date_short\}/g, function() { return short })
    .replace(/\{date(_long)?\}/g, function() { return U.fullDate(d, ctx.lang) })
    .replace(/\{time_secs\}/g, function() { return U.time(d, ctx.clock24, true) })
    .replace(/\{time\}/g, function() { return U.time(d, ctx.clock24) })
    .replace(/\{ago\}/g, function() { return U.dayLabel(d, ctx.lang) })
}

function findClose(src, i, mark) {
  for (var j = i + 2; j < src.length; j++) {
    var c = src[j]
    if (c === "<") {
      var k = src.indexOf(">", j)
      if (k > j) { j = k; continue }
    }
    if (c === mark && !isSpace(src[j - 1]) && !isAlnum(src[j + 1])) return j
  }
  return -1
}

function inlineMrkdwn(src, ctx, px) {
  var out = "", plain = "", i = 0
  function flush() { if (plain) { out += plainHtml(unescape(plain), ctx, px); plain = "" } }
  while (i < src.length) {
    var c = src[i]
    if (c === "<") {
      var j = src.indexOf(">", i + 1)
      if (j > i + 1) { flush(); out += linkToken(src.slice(i + 1, j), ctx); i = j + 1; continue }
    }
    if (c === "`") {
      var k = src.indexOf("`", i + 1)
      if (k > i + 1) { flush(); out += codeSpan(unescape(src.slice(i + 1, k)), ctx); i = k + 1; continue }
    }
    if ((c === "*" || c === "_" || c === "~") && (i === 0 || !isAlnum(src[i - 1])) && !isSpace(src[i + 1])) {
      var e = findClose(src, i, c)
      if (e > i + 1) {
        flush()
        var inner = inlineMrkdwn(src.slice(i + 1, e), ctx, px)
        out += c === "*" ? "<b>" + inner + "</b>" : c === "_" ? "<i>" + inner + "</i>" : "<s>" + inner + "</s>"
        i = e + 1
        continue
      }
    }
    plain += c
    i++
  }
  flush()
  return out
}

// A mrkdwn string → parts (text, quote, code).
function mrkdwnParts(text, ctx, px) {
  var parts = []
  var src = String(text || "")
  var chunks = src.split("```")
  var closed = chunks.length % 2 === 1
  for (var n = 0; n < chunks.length; n++) {
    var chunk = chunks[n]
    var isCode = n % 2 === 1 && (closed || n < chunks.length - 1)
    if (n % 2 === 1 && !isCode) chunk = "```" + chunk
    if (isCode) {
      chunk = chunk.replace(/^\n/, "").replace(/\n$/, "")
      parts.push({ t: "code", text: unescape(chunk) })
      continue
    }
    if (n > 0) chunk = chunk.replace(/^\n/, "")
    if (n < chunks.length - 1) chunk = chunk.replace(/\n$/, "")
    if (chunk.length === 0) continue
    var lines = chunk.split("\n")
    var buf = [], quote = null
    function flushText() {
      if (buf.length) { parts.push({ t: "text", html: buf.join("<br/>") }); buf = [] }
    }
    function flushQuote() {
      if (quote) { parts.push({ t: "quote", html: quote.join("<br/>") }); quote = null }
    }
    for (var l = 0; l < lines.length; l++) {
      var line = lines[l]
      var qm = line.match(/^(&gt;|>)\s?/)
      if (qm) {
        flushText()
        if (!quote) quote = []
        quote.push(inlineMrkdwn(line.slice(qm[0].length), ctx, px))
      } else {
        flushQuote()
        buf.push(inlineMrkdwn(line, ctx, px))
      }
    }
    flushText()
    flushQuote()
  }
  return mergeText(parts)
}

function mergeText(parts) {
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    var prev = out[out.length - 1]
    if (prev && prev.t === "text" && p.t === "text" && !prev.jumbo && !p.jumbo) prev.html += "<br/>" + p.html
    else out.push(p)
  }
  return out
}

// ------------------------------------------------------------------ rich_text

function styled(html, st) {
  if (!st) return html
  if (st.code) html = "<span style=\"font-family:monospace;\">" + html + "</span>"
  if (st.strike) html = "<s>" + html + "</s>"
  if (st.underline) html = "<u>" + html + "</u>"
  if (st.italic) html = "<i>" + html + "</i>"
  if (st.bold) html = "<b>" + html + "</b>"
  return html
}

function richInline(el, ctx, px, literal) {
  var st = el.style || null
  switch (el.type) {
  case "text": {
    var t = String(el.text || "")
    if (st && st.code) return styled(codeSpan(t, ctx), { bold: st.bold, italic: st.italic, underline: st.underline, strike: st.strike })
    return styled(literal ? esc(t).replace(/\n/g, "<br/>") : plainHtml(t, ctx, px), st)
  }
  case "link": {
    var label = el.text ? plainHtml(unmark(el.text), ctx, px) : esc(el.url || "")
    return styled(aOpen(el.url || "", ctx) + label + "</a>", st)
  }
  // A link an app turned into a card (Jira issue): its icon and title on
  // the link's tint, like Slack.
  case "attachment_mention": {
    var icon = el.icon_url && ctx.previewImages !== false ? "<img src=\"" + esc(el.icon_url) + "\" width=\"" + px + "\" height=\"" + px + "\" />" + NBSP : ""
    return styled(pill(unmark(el.text) || el.url || "", ctx.c.link, ctx.c.mentionBg, el.url || "", ctx.c, icon), st)
  }
  case "user": return styled(userPill(el.user_id, "", ctx), st)
  case "channel": return styled(convPill(el.channel_id, "", ctx), st)
  case "usergroup": return styled(pill("@" + (el.usergroup_id || "group"), ctx.c.mention, ctx.c.mentionBg, "", ctx.c), st)
  case "broadcast": return styled(broadcastPill(el.range || "here", ctx), st)
  case "emoji": {
    var g = el.unicode ? E.fromHex(el.unicode) : ""
    if (g) return glyphHtml(g, ctx, px)
    var h = emojiHtml(el.skin_tone ? el.name + "::skin-tone-" + el.skin_tone : el.name, ctx, px)
    return h !== null ? h : esc(":" + el.name + ":")
  }
  case "date": {
    var dt = el.timestamp ? dateToken("date^" + el.timestamp + "^" + (el.format || "{date_short}"), ctx) : ""
    var dh = esc(dt || el.fallback || "")
    return styled(el.url ? aOpen(el.url, ctx) + dh + "</a>" : dh, st)
  }
  // The value and a swatch of it, as Slack draws it.
  case "color": {
    var cv = String(el.value || "")
    var ok = /^#[0-9a-fA-F]{3,8}$/.test(cv)
    return styled(esc(cv) + (ok ? NBSP + "<span style=\"color:" + cv + ";\">■</span>" : ""), st)
  }
  default: return el.text ? esc(el.text) : ""
  }
}

function richSection(elements, ctx, px, literal) {
  var out = ""
  var list = elements || []
  for (var i = 0; i < list.length; i++) out += richInline(list[i], ctx, px, literal)
  return out
}

// An ordered list's marker by depth, as Slack: 1. → a. → i.
function listNumber(n, indent) {
  var k = indent % 3
  if (k === 1) { var a = ""; while (n > 0) { n--; a = String.fromCharCode(97 + n % 26) + a; n = Math.floor(n / 26) } return a }
  if (k === 2) {
    var r = "", v = [[1000, "m"], [900, "cm"], [500, "d"], [400, "cd"], [100, "c"], [90, "xc"], [50, "l"], [40, "xl"], [10, "x"], [9, "ix"], [5, "v"], [4, "iv"], [1, "i"]]
    for (var i = 0; i < v.length; i++) while (n >= v[i][0]) { r += v[i][1]; n -= v[i][0] }
    return r
  }
  return String(n)
}

function richTextParts(block, ctx, px) {
  var parts = []
  var els = block.elements || []
  var textBuf = []
  function flush() { if (textBuf.length) { parts.push({ t: "text", html: textBuf.join("<br/>") }); textBuf = [] } }
  for (var i = 0; i < els.length; i++) {
    var e = els[i]
    if (e.type === "rich_text_preformatted") {
      flush()
      var code = ""
      for (var k = 0; k < (e.elements || []).length; k++) {
        var x = e.elements[k]
        code += x.type === "text" ? x.text : x.type === "link" ? (x.text || x.url) : x.type === "user" ? "@" + (ctx.user(x.user_id) || x.user_id) : x.type === "channel" ? "#" + ((ctx.conv(x.channel_id) || {}).name || x.channel_id) : (x.text || "")
      }
      parts.push({ t: "code", text: code })
    } else if (e.type === "rich_text_quote") {
      flush()
      parts.push({ t: "quote", html: richSection(e.elements, ctx, px).replace(/\n/g, "<br/>").replace(/(<br\/>)+$/, "") })
    } else if (e.type === "rich_text_list") {
      var indent = Math.max(0, Math.min(8, parseInt(e.indent, 10) || 0))
      var items = e.elements || []
      var lines = []
      for (var n = 0; n < items.length; n++) {
        var bullet = e.style === "ordered" ? listNumber((parseInt(e.offset, 10) || 0) + n + 1, indent) + ". " : (["•", "◦", "▪"][indent % 3]) + " "
        var pad = ""
        for (var p = 0; p < indent + 1; p++) pad += "&nbsp;&nbsp;&nbsp;"
        lines.push(pad + bullet + richSection(items[n].elements, ctx, px).replace(/(<br\/>)+$/, ""))
      }
      textBuf.push(lines.join("<br/>"))
    } else {
      var html = richSection(e.elements, ctx, px).replace(/\n/g, "<br/>").replace(/(<br\/>)+$/, "")
      textBuf.push(html)
    }
  }
  flush()
  return parts
}

// ------------------------------------------------------------------ Block Kit

function textObj(t, ctx, px) {
  if (!t) return ""
  if (t.type === "mrkdwn") return mrkdwnParts(t.text, ctx, px).map(function(p) { return p.html || esc(p.text || "") }).join("<br/>")
  return plainHtml(String(t.text || ""), ctx, px)
}

// A text object as parts: mrkdwn keeps its quotes and code blocks.
function textParts(t, ctx, px) {
  if (!t) return []
  if (t.type === "mrkdwn") return mrkdwnParts(t.text, ctx, px)
  return [{ t: "text", html: plainHtml(String(t.text || ""), ctx, px) }]
}

// "2026-11-17" → Today / Yesterday / Tomorrow / Nov 17, 2026 (the pickers).
function pickedDate(ymd, ctx) {
  var m = String(ymd || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return String(ymd || "")
  return dateFormat(new Date(+m[1], +m[2] - 1, +m[3]), "{date_short_pretty}", ctx)
}
function pickedTime(hm, ctx) {
  var m = String(hm || "").match(/^(\d{1,2}):(\d{2})$/)
  if (!m) return String(hm || "")
  var d = new Date(); d.setHours(+m[1], +m[2], 0, 0)
  return U.time(d, ctx.clock24)
}

// An interactive element as the views draw it (BlockControl.qml):
//   kind  button | overflow | select | datetime | checks | radios | field
//   html  its label (emoji drawn); placeholder: the label is the hint
//   icon  a select's lead glyph (date, time); options (overflow, checks,
//   radios): [{html, desc, on, url, value}]
// `el`: the element as Slack sent it, for blocks.actions (MessageBody.press).
function control(el, ctx) {
  if (!el) return null
  var pt = ctx.lang === "pt-BR"
  var c = { kind: "", html: "", placeholder: false, icon: "", style: el.style || "", url: el.url || "", el: el, options: [], multi: false }
  function ph(fallbackEn, fallbackPt) {
    c.placeholder = true
    return el.placeholder ? plainHtml(String(el.placeholder.text || ""), ctx) : esc(pt ? fallbackPt : fallbackEn)
  }
  function opt(o, on) {
    return { html: o.text ? textObj(o.text, ctx) : "", desc: o.description ? textObj(o.description, ctx) : "", on: !!on, url: o.url || "", value: o.value || "" }
  }
  var initial = function(o) { return o && o.text ? textObj(o.text, ctx) : "" }
  var type = el.type || ""
  switch (type) {
  case "button": c.kind = "button"; c.html = el.text ? textObj(el.text, ctx) : ""; break
  case "workflow_button": c.kind = "button"; c.html = el.text ? textObj(el.text, ctx) : ""; break
  case "overflow":
    c.kind = "overflow"
    c.options = (el.options || []).map(function(o) { return opt(o, false) })
    break
  case "datepicker":
    c.kind = "select"; c.icon = "date"
    c.html = el.initial_date ? esc(pickedDate(el.initial_date, ctx)) : ph("Select a date", "Escolha uma data")
    break
  case "timepicker":
    c.kind = "select"; c.icon = "time"
    c.html = el.initial_time ? esc(pickedTime(el.initial_time, ctx)) : ph("Select time", "Escolha um horário")
    break
  case "datetimepicker": {
    c.kind = "datetime"
    var dt = el.initial_date_time ? new Date(el.initial_date_time * 1000) : null
    c.date = dt ? esc(dateFormat(dt, "{date_short_pretty}", ctx)) : esc(pt ? "Escolha uma data" : "Select a date")
    c.time = dt ? esc(U.time(dt, ctx.clock24)) : esc(pt ? "Escolha um horário" : "Select time")
    c.placeholder = !dt
    break
  }
  case "checkboxes": case "radio_buttons": {
    c.kind = type === "checkboxes" ? "checks" : "radios"
    var picked = (type === "checkboxes" ? (el.initial_options || []) : (el.initial_option ? [el.initial_option] : [])).map(function(o) { return o.value })
    c.options = (el.options || []).map(function(o) { return opt(o, picked.indexOf(o.value) >= 0) })
    break
  }
  case "plain_text_input": case "email_text_input": case "url_text_input": case "number_input": case "rich_text_input":
    c.kind = "field"
    if (el.initial_value !== undefined && el.initial_value !== "") c.html = esc(String(el.initial_value))
    else c.html = ph("", "")
    c.multi = el.multiline === true
    break
  case "file_input": c.kind = "field"; c.icon = "file"; c.html = esc(pt ? "Enviar arquivos" : "Upload files"); c.placeholder = true; break
  default: {
    if (!/select$/.test(type)) return null
    c.kind = "select"
    c.multi = type.indexOf("multi_") === 0
    var picks = []
    if (el.initial_option) picks.push(initial(el.initial_option))
    ;(el.initial_options || []).forEach(function(o) { picks.push(initial(o)) })
    if (el.initial_user) picks.push(esc("@" + (ctx.user(el.initial_user) || el.initial_user)))
    ;(el.initial_users || []).forEach(function(u) { picks.push(esc("@" + (ctx.user(u) || u))) })
    var convOf = function(id) { var x = ctx.conv(id); return esc(x ? (x.private ? "" : "#") + x.name : id) }
    if (el.initial_conversation) picks.push(convOf(el.initial_conversation))
    if (el.initial_channel) picks.push(convOf(el.initial_channel))
    ;(el.initial_conversations || el.initial_channels || []).forEach(function(id) { picks.push(convOf(id)) })
    c.html = picks.length ? picks.join(", ") : ph(c.multi ? "Select items" : "Select an item", c.multi ? "Selecione itens" : "Selecione um item")
    // Its choices, flat (a menu on click shows them: MessageBody.press).
    var flatOpts = (el.options || []).slice()
    ;(el.option_groups || []).forEach(function(g) { flatOpts = flatOpts.concat(g.options || []) })
    c.options = flatOpts.map(function(o) { return opt(o, false) })
  }
  }
  c.label = el.text && el.text.text ? String(el.text.text) : String(c.html).replace(/<[^>]*>/g, "")
  return c
}

function blockParts(blocks, ctx, px) {
  var parts = []
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i]
    switch (b.type) {
    case "rich_text": parts = parts.concat(richTextParts(b, ctx, px)); break
    case "section": {
      // `sub`: its text as parts (quotes, code blocks), drawn in its column.
      var p = { t: "section", html: "", sub: b.text ? textParts(b.text, ctx, px) : [], fields: [], accessory: null }
      if (p.sub.length === 1 && p.sub[0].t === "text") { p.html = p.sub[0].html; p.sub = [] }
      if (b.fields) p.fields = b.fields.map(function(f) { return textObj(f, ctx, px) })
      var a = b.accessory
      if (a && a.type === "image") p.accessory = { kind: "image", url: a.image_url || (a.slack_file && a.slack_file.url) || "", alt: a.alt_text || "" }
      else if (a) { var ctl = control(a, ctx); if (ctl) { ctl.blockId = b.block_id || ""; p.accessory = ctl } }
      parts.push(p)
      break
    }
    case "header": parts.push({ t: "header", html: textObj(b.text, ctx, px) }); break
    case "context": {
      // In order, pictures among the words, as Slack lays them out.
      var bits = []
      ;(b.elements || []).forEach(function(el) {
        if (el.type === "image") { var u = el.image_url || (el.slack_file && el.slack_file.url) || ""; if (u) bits.push({ image: u }) }
        else bits.push({ html: textObj(el, ctx, px) })
      })
      parts.push({ t: "context", bits: bits, html: bits.filter(function(x) { return x.html }).map(function(x) { return x.html }).join("&nbsp;&nbsp;"), images: bits.filter(function(x) { return x.image }).map(function(x) { return x.image }) })
      break
    }
    case "actions": {
      var items = (b.elements || []).map(function(el) { return control(el, ctx) }).filter(function(x) { return x })
      items.forEach(function(x) { x.blockId = b.block_id || "" })
      if (items.length) parts.push({ t: "actions", items: items })
      break
    }
    case "input": {
      var ic = control(b.element, ctx)
      parts.push({ t: "input", label: b.label ? textObj(b.label, ctx, px) : "", hint: b.hint ? textObj(b.hint, ctx, px) : "",
                   optional: b.optional === true, ctl: ic ? Object.assign(ic, { blockId: b.block_id || "" }) : null })
      break
    }
    case "divider": parts.push({ t: "divider" }); break
    case "image": {
      var url = b.image_url || (b.slack_file && b.slack_file.url) || ""
      if (url) parts.push({ t: "image", url: url, w: b.image_width || 0, h: b.image_height || 0,
                            title: b.title ? b.title.text : "", titleHtml: b.title ? textObj(b.title, ctx, px) : "",
                            bytes: b.image_bytes || 0, alt: b.alt_text || "" })
      break
    }
    case "video": parts.push({ t: "video", title: (b.title && b.title.text) || "", url: b.title_url || b.video_url || "", thumb: b.thumbnail_url || "" }); break
    case "file": parts.push({ t: "text", html: "📎 " + esc(b.source === "remote" ? "file" : "file"), muted: true }); break
    case "markdown": parts = parts.concat(markdownParts(String(b.text || ""), ctx, px)); break
    case "table": {
      var settings = b.column_settings || []
      var rows = (b.rows || []).map(function(r) {
        return r.map(function(cell) {
          if (!cell) return ""
          if (cell.type === "rich_text") return richTextParts(cell, ctx, px).map(function(x) { return x.html || esc(x.text || "") }).join("<br/>")
          return plainHtml(String(cell.text || ""), ctx, px)
        })
      })
      if (rows.length) parts.push({ t: "table", rows: rows, align: settings.map(function(c) { return (c && c.align) || "left" }), header: true })
      break
    }
    default: break
    }
  }
  return parts
}

// ------------------------------------------------------------------ markdown block

// Standard Markdown (Block Kit's `markdown` block, what AI apps send):
// headings, paragraphs, lists, quotes, code fences, tables, rules; inline
// **bold**, *italic*/_italic_, ~~strike~~, `code`, [text](url), <url>.
function mdInline(src, ctx, px) {
  var out = "", plain = "", i = 0
  function flush() { if (plain) { out += plainHtml(unescape(plain), ctx, px); plain = "" } }
  function closeAt(mark, from) { var k = src.indexOf(mark, from); return k > from ? k : -1 }
  while (i < src.length) {
    var c = src[i], two = src.substr(i, 2)
    if (c === "\\" && i + 1 < src.length && /[\\`*_{}\[\]()#+\-.!~|>]/.test(src[i + 1])) { plain += src[i + 1]; i += 2; continue }
    if (c === "`") { var k = closeAt("`", i + 1); if (k > 0) { flush(); out += codeSpan(src.slice(i + 1, k), ctx); i = k + 1; continue } }
    if (two === "**" || two === "__") { var e2 = closeAt(two, i + 2); if (e2 > 0) { flush(); out += "<b>" + mdInline(src.slice(i + 2, e2), ctx, px) + "</b>"; i = e2 + 2; continue } }
    if (two === "~~") { var e3 = closeAt("~~", i + 2); if (e3 > 0) { flush(); out += "<s>" + mdInline(src.slice(i + 2, e3), ctx, px) + "</s>"; i = e3 + 2; continue } }
    if ((c === "*" || c === "_") && !isSpace(src[i + 1]) && (i === 0 || !isAlnum(src[i - 1]))) {
      var e1 = closeAt(c, i + 1)
      if (e1 > 0 && !isSpace(src[e1 - 1])) { flush(); out += "<i>" + mdInline(src.slice(i + 1, e1), ctx, px) + "</i>"; i = e1 + 1; continue }
    }
    if (c === "[") {
      var m = src.slice(i).match(/^\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/)
      if (m) { flush(); out += aOpen(m[2], ctx) + mdInline(m[1] || m[2], ctx, px) + "</a>"; i += m[0].length; continue }
    }
    if (c === "<") {
      var u = src.slice(i).match(/^<((?:https?|mailto):[^>\s]+)>/)
      if (u) { flush(); out += aOpen(u[1], ctx) + esc(u[1].replace(/^mailto:/, "")) + "</a>"; i += u[0].length; continue }
      var sl = src.indexOf(">", i + 1)
      if (sl > i + 1 && /^[@#!]/.test(src[i + 1])) { flush(); out += linkToken(src.slice(i + 1, sl), ctx); i = sl + 1; continue }
    }
    plain += c
    i++
  }
  flush()
  return out
}

function markdownParts(text, ctx, px) {
  var parts = []
  var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n")
  var buf = []
  function flush() { if (buf.length) { parts.push({ t: "text", html: buf.join("<br/>") }); buf = [] } }
  function cells(line) {
    var l = line.trim().replace(/^\|/, "").replace(/\|$/, "")
    var out = [], cur = ""
    for (var k = 0; k < l.length; k++) {
      if (l[k] === "\\" && l[k + 1] === "|") { cur += "|"; k++ }
      else if (l[k] === "|") { out.push(cur.trim()); cur = "" }
      else cur += l[k]
    }
    out.push(cur.trim())
    return out
  }
  var i = 0
  while (i < lines.length) {
    var line = lines[i]
    var fence = line.match(/^\s*(```|~~~)/)
    if (fence) {
      flush()
      var code = []
      i++
      while (i < lines.length && lines[i].trim().indexOf(fence[1]) !== 0) { code.push(lines[i]); i++ }
      i++
      parts.push({ t: "code", text: code.join("\n") })
      continue
    }
    // A table: a header row, then |---|:--:| …
    if (/\|/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(lines[i + 1])) {
      flush()
      var align = cells(lines[i + 1]).map(function(x) { return /^:-+:$/.test(x) ? "center" : /-:$/.test(x) ? "right" : "left" })
      var rows = [cells(line)]
      i += 2
      while (i < lines.length && /\|/.test(lines[i]) && lines[i].trim() !== "") { rows.push(cells(lines[i])); i++ }
      parts.push({ t: "table", header: true, align: align, rows: rows.map(function(r) { return r.map(function(x) { return mdInline(x, ctx, px) }) }) })
      continue
    }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { flush(); parts.push({ t: "divider" }); i++; continue }
    var h = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/)
    if (h) {
      flush()
      parts.push({ t: "header", html: mdInline(h[2], ctx, px), level: h[1].length })
      i++
      continue
    }
    if (/^\s*>/.test(line)) {
      flush()
      var q = []
      while (i < lines.length && /^\s*>/.test(lines[i])) { q.push(mdInline(lines[i].replace(/^\s*>\s?/, ""), ctx, px)); i++ }
      parts.push({ t: "quote", html: q.join("<br/>") })
      continue
    }
    var li = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/)
    if (li) {
      var depth = Math.floor(li[1].replace(/\t/g, "    ").length / 2)
      var ordered = /\d/.test(li[2])
      var task = li[3].match(/^\[([ xX])\]\s+(.*)$/)
      var mark = task ? (task[1] === " " ? "☐" : "☑") : ordered ? li[2].replace(")", ".") : ["•", "◦", "▪"][depth % 3]
      var pad = ""
      for (var p = 0; p < depth + 1; p++) pad += "&nbsp;&nbsp;&nbsp;"
      buf.push(pad + mark + " " + mdInline(task ? task[2] : li[3], ctx, px))
      i++
      continue
    }
    if (line.trim() === "") {
      // A blank line between paragraphs: a gap, not a run of them.
      if (buf.length && buf[buf.length - 1] !== "") buf.push("")
      i++
      continue
    }
    buf.push(mdInline(line, ctx, px))
    i++
  }
  while (buf.length && buf[buf.length - 1] === "") buf.pop()
  flush()
  return parts
}

// ------------------------------------------------------------------ attachments

function attColor(c) {
  if (!c) return ""
  if (c === "good") return "good"
  if (c === "warning") return "warning"
  if (c === "danger") return "danger"
  var m = String(c).match(/^#?([0-9a-fA-F]{6})$/)
  return m ? "#" + m[1] : ""
}

function attachment(a, ctx, px) {
  var out = { t: "attachment", color: attColor(a.color), pretext: a.pretext ? inlineBlock(a.pretext, ctx, px) : "",
              service: a.service_name || "", serviceIcon: a.service_icon || "",
              author: a.author_name || "", authorIcon: a.author_icon || "", authorLink: a.author_link || "",
              title: a.title ? inlineMrkdwn(a.title, ctx, px) : "", titleText: a.title ? flatMrkdwn(a.title, ctx) : "", titleLink: a.title_link || a.from_url || "",
              parts: [], fields: [], image: null, thumb: a.thumb_url || "", footer: a.footer ? inlineBlock(a.footer, ctx, px) : "",
              footerIcon: a.footer_icon || "",
              // The footer's time, as Slack: "Today at 9:00 AM".
              when: !a.ts || a.is_msg_unfurl || a.is_share ? "" : esc(dateToken("date^" + Math.floor(Number(a.ts)) + "^" + (ctx.lang === "pt-BR" ? "{date_short_pretty} às {time}" : "{date_short_pretty} at {time}"), ctx)),
              actions: [], ts: a.ts || "", isMsg: a.is_msg_unfurl === true || a.is_share === true,
              // A shared message's own: who, where, its files, and whether
              // it sits in a thread (Slack's footer: "Thread in …").
              authorId: a.author_id || "", channelId: a.channel_id || "", files: a.files || [],
              thread: a.is_reply_unfurl === true || /^(thread|conversa)/i.test(String(a.footer || "")),
              threadTs: a.thread_ts || ((U.parsePermalink(a.from_url) || {}).threadTs) || "" }
  if (a.blocks && a.blocks.length) out.parts = blockParts(a.blocks, ctx, px)
  if (!out.parts.length && a.text) out.parts = mrkdwnParts(a.text, ctx, px)
  if (a.message_blocks && !out.parts.length) {
    a.message_blocks.forEach(function(mb) { if (mb.message && mb.message.blocks) out.parts = out.parts.concat(blockParts(mb.message.blocks, ctx, px)) })
  }
  ;(a.fields || []).forEach(function(f) {
    out.fields.push({ title: f.title ? inlineMrkdwn(f.title, ctx, px) : "", html: inlineBlock(f.value || "", ctx, px), short: f.short === true })
  })
  if (a.image_url) out.image = { url: a.image_url, w: a.image_width || 0, h: a.image_height || 0 }
  ;(a.actions || []).forEach(function(x) {
    // Legacy buttons answer through chat.attachmentAction (MessageBody.press).
    out.actions.push({ label: x.text || x.name || "", style: x.style || "", url: x.url || "", legacy: x,
                       attachmentId: String(a.id === undefined ? "" : a.id), callbackId: a.callback_id || "" })
  })
  if (!out.parts.length && !out.title && !out.fields.length && !out.image && !out.pretext && !out.author && a.fallback) {
    out.parts = mrkdwnParts(a.fallback, ctx, px)
  }
  if (a.is_msg_unfurl || a.is_share) {
    // A shared message: author line from the original.
    if (!out.author && a.author_subname) out.author = a.author_subname
  }
  out.work = workObject(a, ctx)
  return out
}

// Slack's work object, an app's card for a link (a Jira issue): its
// expanded layout, drawn by WorkObjectView in place of the attachment,
// whose blocks are the fallback for clients without cards. A button that
// is also among those blocks answers as that one, the way the app knows.
function workObject(a, ctx) {
  var e = a.work_object_entity
  var l = e && e.layouts && e.layouts.expanded
  if (!l || !l.title) return null
  var txt = function(x) { return x && x.text ? String(x.text) : "" }
  var img = function(x) { return x && x.image_url ? x.image_url : "" }
  var fields = ((l.fields && l.fields.elements) || []).map(function(f) {
    var tags = (f.tag || []).map(function(g) { return { text: String(g.text || ""), color: g.color || "", icon: g.icon_url || "" } })
    if (!tags.length && (f.text || f.value)) tags = [{ text: String(f.text || f.value), color: "", icon: "" }]
    return { label: String(f.label || ""), tags: tags }
  }).filter(function(f) { return f.tags.length })
  var ctl = function(x) {
    var c = control(x, ctx)
    if (!c) return null
    c.blockId = x.block_id || ""
    ;(a.blocks || []).forEach(function(b) {
      if (b.type === "actions" && !c.url) (b.elements || []).forEach(function(y) { if (y.type === x.type && y.action_id === x.action_id) { c.el = y; c.blockId = b.block_id || "" } })
    })
    return c
  }
  // When the app last changed it (ms; 0: not said): seconds, ms or a date.
  var upd = l.updated_at
  var updatedAt = !upd ? 0 : (isFinite(Number(upd)) ? (Number(upd) < 1e12 ? Number(upd) * 1000 : Number(upd)) : (Date.parse(upd) || 0))
  var acts = l.actions || {}
  return { header: txt(l.header_title) || e.app_name || e.product_name || "", title: txt(l.title), subtitle: txt(l.subtitle),
           entityId: e.entity_id || "", updatedAt: updatedAt,
           url: e.external_url || a.app_unfurl_url || a.from_url || "", link: a.from_url || a.app_unfurl_url || e.external_url || "",
           icon: img(l.product_icon), badge: img(e.app_icons && e.app_icons.image_36), fields: fields,
           actions: (acts.primary_actions || []).map(ctl).filter(function(x) { return x }),
           more: ((acts.overflow_actions && acts.overflow_actions.app_actions) || []).map(ctl).filter(function(x) { return x }) }
}

function inlineBlock(text, ctx, px) {
  return mrkdwnParts(text, ctx, px).map(function(p) { return p.html || esc(p.text || "") }).join("<br/>")
}

// ------------------------------------------------------------------ system

// The text of a system message, in the app's language (mrkdwn), or "".
function systemText(m, lang) {
  var st = m.subtype || ""
  var tr = function(en, pt) { return lang === "pt-BR" ? pt : en }
  var v = function(x) { return String(x || "").trim() }
  switch (st) {
  case "channel_topic": case "group_topic":
    return v(m.topic) ? tr("set the channel topic: ", "definiu o tópico do canal: ") + m.topic : tr("cleared the channel topic", "limpou o tópico do canal")
  case "channel_purpose": case "group_purpose":
    return v(m.purpose) ? tr("set the channel description: ", "definiu a descrição do canal: ") + m.purpose : tr("cleared the channel description", "limpou a descrição do canal")
  case "channel_name": case "group_name":
    if (!v(m.name)) return ""
    return v(m.old_name) ? tr("renamed the channel from #", "renomeou o canal de #") + m.old_name + tr(" to #", " para #") + m.name : tr("renamed the channel to #", "renomeou o canal para #") + m.name
  case "channel_join": case "group_join":
    return v(m.inviter) ? tr("was added by ", "foi adicionado(a) por ") + "<@" + m.inviter + ">" : tr("joined the channel", "entrou no canal")
  case "channel_leave": case "group_leave": return tr("left the channel", "saiu do canal")
  case "channel_archive": case "group_archive": return tr("archived the channel", "arquivou o canal")
  case "channel_unarchive": case "group_unarchive": return tr("unarchived the channel", "desarquivou o canal")
  case "channel_convert_to_private": return tr("made the channel private", "tornou o canal privado")
  case "channel_convert_to_public": return tr("made the channel public", "tornou o canal público")
  case "pinned_item": return tr("pinned a message to this channel", "fixou uma mensagem neste canal")
  }
  return ""
}

function isMuted(m) {
  if (m.ephemeral || m.subtype === "ephemeral") return true
  var st = m.subtype || ""
  if (["channel_join", "channel_leave", "group_join", "group_leave", "channel_topic", "channel_purpose", "group_topic", "group_purpose", "huddle_thread"].indexOf(st) >= 0) return true
  return st !== "pinned_item" && systemText(m, "en") !== ""
}

function membership(m) {
  var st = m && m.subtype
  if (st === "channel_join" || st === "group_join") return "join"
  if (st === "channel_leave" || st === "group_leave") return "leave"
  return ""
}

// ------------------------------------------------------------------ message

// The whole body of a message as parts. Files, reactions and the thread
// footer are drawn by the message view from the message itself.
function render(m, ctx) {
  if (m.subtype === "huddle_thread") return [{ t: "text", html: "📞 " + esc(ctx.lang === "pt-BR" ? "começou uma huddle" : "started a huddle"), muted: true }]
  var parts = []
  var sys = systemText(m, ctx.lang)
  var jumbo = false
  if (sys) {
    parts = mrkdwnParts(sys, ctx).map(function(p) { p.muted = true; return p })
  } else {
    jumbo = E.onlyEmoji(m.text, ctx.custom, ctx.aliases) && !(m.files && m.files.length)
    var px = jumbo ? Math.round(ctx.emojiPx * 1.9) : ctx.emojiPx
    if (m.blocks && m.blocks.length) parts = blockParts(m.blocks, ctx, px)
    var hasText = parts.some(function(p) { return p.t !== "text" || String(p.html || "").replace(/<[^>]*>|&nbsp;|\s/g, "").length > 0 })
    if (!hasText) parts = mrkdwnParts(m.text, ctx, px)
    if (jumbo) parts.forEach(function(p) { if (p.t === "text") p.jumbo = true })
    if (m.ephemeral || m.subtype === "ephemeral") parts.forEach(function(p) { p.muted = true })
    if (m.subtype === "me_message") parts.forEach(function(p) { if (p.t === "text") p.html = "<i>" + p.html + "</i>" })
  }
  var atts = m.attachments || []
  for (var i = 0; i < atts.length; i++) parts.push(attachment(atts[i], ctx, ctx.emojiPx))
  return parts
}

// ------------------------------------------------------------------ flat text

// A message as one line of plain text: previews, notifications, search,
// the bar's hover card.
function flat(m, ctx, max) {
  var s = ""
  var sys = systemText(m, ctx.lang)
  if (sys) s = flatMrkdwn(sys, ctx)
  else {
    if (m.blocks && m.blocks.length) s = flatBlocks(m.blocks, ctx)
    if (!s.trim()) s = flatMrkdwn(m.text || "", ctx)
    if (!s.trim() && m.attachments && m.attachments.length) {
      var a = m.attachments[0]
      s = flatMrkdwn(a.pretext || a.title || a.text || a.fallback || "", ctx)
    }
    if (!s.trim() && m.files && m.files.length) s = m.files.map(function(f) { return "📎 " + f.name }).join("  ")
  }
  s = s.replace(/\s+/g, " ").trim()
  if (max && s.length > max) s = s.slice(0, max - 1) + "…"
  return s
}

function flatMrkdwn(text, ctx) {
  var s = String(text || "").replace(/<([^>]+)>/g, function(all, inner) {
    var bar = inner.indexOf("|")
    var target = bar >= 0 ? inner.slice(0, bar) : inner
    var label = bar >= 0 ? inner.slice(bar + 1) : ""
    if (/^@[UWB]/.test(target)) return "@" + (ctx.user(target.slice(1)) || label.replace(/^@/, "") || target.slice(1))
    if (/^#[CGD]/.test(target)) return "#" + (label || ((ctx.conv(target.slice(1)) || {}).name) || "…")
    if (target.charAt(0) === "!") {
      var b = target.slice(1)
      if (b === "here" || b === "channel" || b === "everyone") return "@" + b
      return label || "@" + b.split("^")[0]
    }
    if (target.indexOf("mailto:") === 0) return label || target.slice(7)
    return label || target
  })
  s = unescape(s).replace(/```/g, "").replace(/(^|\s)[*_~]+(?=\S)|(\S)[*_~]+(?=\s|$)/g, "$1$2")
  return E.shortcodes(s, ctx.custom, ctx.aliases, function(name) { return ":" + name + ":" })
}

function flatBlocks(blocks, ctx) {
  var out = []
  blocks.forEach(function(b) {
    if (b.type === "rich_text") {
      (b.elements || []).forEach(function(e) {
        var inner = e.type === "rich_text_list" ? (e.elements || []).map(function(it) { return flatInline(it.elements, ctx) }).join(" ") : flatInline(e.elements, ctx)
        out.push(inner)
      })
    } else if (b.type === "section" || b.type === "header") {
      if (b.text) out.push(b.text.type === "mrkdwn" ? flatMrkdwn(b.text.text, ctx) : b.text.text)
    } else if (b.type === "markdown") {
      out.push(String(b.text || "").replace(/[*_~`#>|]+/g, "").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1"))
    } else if (b.type === "context") {
      (b.elements || []).forEach(function(e) { if (e.text) out.push(e.type === "mrkdwn" ? flatMrkdwn(e.text, ctx) : e.text) })
    }
  })
  return out.join(" ")
}

function flatInline(els, ctx) {
  return (els || []).map(function(e) {
    switch (e.type) {
    case "text": return e.text
    case "link": return e.text || e.url
    case "user": return "@" + (ctx.user(e.user_id) || e.user_id)
    case "channel": return "#" + ((ctx.conv(e.channel_id) || {}).name || "…")
    case "broadcast": return "@" + e.range
    case "emoji": return (e.unicode && E.fromHex(e.unicode)) || E.standard(e.name) || ":" + e.name + ":"
    case "usergroup": return "@group"
    case "date": return e.fallback || ""
    default: return e.text || ""
    }
  }).join("")
}

// Whether a message calls you: <@me>, @here/@channel/@everyone.
function mentions(m, me) {
  var t = String(m.text || "")
  if (t.indexOf("<@" + me + ">") >= 0 || t.indexOf("<@" + me + "|") >= 0) return true
  return /<!(here|channel|everyone)/.test(t)
}

function mentionsMe(m, me) {
  var t = String(m.text || "")
  return t.indexOf("<@" + me + ">") >= 0 || t.indexOf("<@" + me + "|") >= 0
}

// Search highlights (U+E000 … U+E001) become <b> with the highlight color.
function highlight(html, color, bg) {
  return String(html).replace(//g, "<span style=\"color:" + color + ";background-color:" + bg + ";\"><b>").replace(//g, "</b></span>")
}

// ------------------------------------------------------------------ animated emoji

// Rich text only draws a GIF's first frame, so the view plays a
// workspace's animated emoji over the text (RichText.qml). The html with
// each GIF's `src` swapped for `blank`, a see-through picture of the same
// size that holds its place → {html, count, gifs: [{n, url, px}]}: `n` is
// the GIF's place among the html's pictures (`count` of them, each one
// U+FFFC in the text). null when it has none.
function animated(html, blank) {
  var gifs = [], n = 0
  var out = String(html || "").replace(/<img\b[^>]*>/gi, function(tag) {
    var i = n++
    var src = tag.match(/\ssrc\s*=\s*"([^"]*)"/i)
    var url = src ? unescape(src[1].replace(/&quot;/g, "\"")) : ""
    if (!/\.gif(\?|#|$)/i.test(url)) return tag
    var w = tag.match(/\swidth\s*=\s*"?(\d+)/i)
    gifs.push({ n: i, url: url, px: w ? parseInt(w[1], 10) : 0 })
    return tag.replace(src[0], function() { return " src=\"" + esc(blank) + "\"" })
  })
  return gifs.length ? { html: out, count: n, gifs: gifs } : null
}
