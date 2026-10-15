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
//   c             colors as "#rrggbb": link, mention, mentionBg, meText,
//                 meBg, code, codeBg, dim, text
//   emojiPx       emoji size in the text
//   ask(kind, id) asks the store to look a name up ("user" / "conv")

var SYSTEM_SUBTYPES = ["channel_join", "group_join", "channel_leave", "group_leave"]

function unescape(s) { return String(s || "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&") }
function esc(s) { return U.escapeHtml(s) }
function isAlnum(c) { return !!c && (/[A-Za-z0-9]/.test(c) || U.isLetter(c)) }
function isSpace(c) { return !c || /\s/.test(c) }

// ------------------------------------------------------------------ pills

function pill(text, fg, bg, href) {
  var inner = "<span style=\"color:" + fg + ";background-color:" + bg + ";\"> " + esc(text) + " </span>"
  return href ? "<a href=\"" + href + "\" style=\"text-decoration:none;\">" + inner + "</a>" : inner
}

function userPill(id, label, ctx) {
  var name = ctx.user(id)
  if (!name) {
    if (ctx.ask) ctx.ask("user", id)
    name = label ? String(label).replace(/^@/, "") : id
  }
  var me = id === ctx.me
  return pill("@" + name, me ? ctx.c.meText : ctx.c.mention, me ? ctx.c.meBg : ctx.c.mentionBg, "slackqs://user/" + id)
}

function convPill(id, label, ctx) {
  var c = ctx.conv(id)
  var name = label || (c && c.name) || ""
  if (!c && ctx.ask) ctx.ask("conv", id)
  if (!name) name = "…"
  var lock = c && c.private
  return pill((lock ? "🔒" : "#") + name, ctx.c.mention, ctx.c.mentionBg, "slackqs://channel/" + id)
}

function broadcastPill(range, ctx) {
  return pill("@" + range, ctx.c.meText, ctx.c.meBg, "")
}

// A standard emoji: Slack's picture of it (the Apple set the official app
// draws), or the system font's glyph when the app is set to that.
function glyphHtml(glyph, ctx, px) {
  px = px || ctx.emojiPx
  if (ctx.slackEmoji !== false) {
    var g = E.known(glyph) || glyph
    return "<img src=\"" + E.imageUrl(g) + "\" width=\"" + px + "\" height=\"" + px + "\" />"
  }
  return "<span style=\"font-size:" + Math.round(px * 0.92) + "px;\">" + glyph + "</span>"
}

function emojiHtml(name, ctx, px) {
  var r = E.resolve(name, ctx.custom, ctx.aliases)
  if (!r) return null
  px = px || ctx.emojiPx
  if (r.glyph) return glyphHtml(r.glyph, ctx, px)
  return "<img src=\"" + esc(r.url) + "\" width=\"" + px + "\" height=\"" + px + "\" />"
}

// Plain text with emoji typed as characters turned into pictures too.
function textHtml(text, ctx, px) {
  if (ctx.slackEmoji === false) return esc(text)
  return E.split(text).map(function(run) { return run[0] ? glyphHtml(run[1], ctx, px) : esc(run[1]) }).join("")
}

function aOpen(url, ctx) {
  return "<a href=\"" + esc(url) + "\" style=\"color:" + ctx.c.link + ";text-decoration:none;\">"
}

function codeSpan(text, ctx) {
  return "<span style=\"font-family:monospace;color:" + ctx.c.code + ";background-color:" + ctx.c.codeBg + ";\"> " + esc(text).replace(/ /g, "&nbsp;") + " </span>"
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
    if (body.indexOf("subteam^") === 0) return pill(label || "@subteam", ctx.c.mention, ctx.c.mentionBg, "")
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
  var d = new Date(epoch * 1000)
  var fmt = parts[2] || "{date_short}"
  return fmt.replace(/\{date_num\}/g, d.toLocaleDateString())
            .replace(/\{date(_short|_long|_pretty|_short_pretty|_long_pretty)?\}/g, function() { return U.fullDate(d, ctx.lang) })
            .replace(/\{time(_secs)?\}/g, function() { return U.time(d, ctx.clock24) })
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
    var label = el.text ? plainHtml(el.text, ctx, px) : esc(el.url || "")
    return styled(aOpen(el.url || "", ctx) + label + "</a>", st)
  }
  case "user": return styled(userPill(el.user_id, "", ctx), st)
  case "channel": return styled(convPill(el.channel_id, "", ctx), st)
  case "usergroup": return styled(pill("@" + (el.usergroup_id || "group"), ctx.c.mention, ctx.c.mentionBg, ""), st)
  case "broadcast": return styled(broadcastPill(el.range || "here", ctx), st)
  case "emoji": {
    var g = el.unicode ? E.fromHex(el.unicode) : ""
    if (g) return glyphHtml(g, ctx, px)
    var h = emojiHtml(el.skin_tone ? el.name + "::skin-tone-" + el.skin_tone : el.name, ctx, px)
    return h !== null ? h : esc(":" + el.name + ":")
  }
  case "date": return esc(el.fallback || dateToken("date^" + el.timestamp + "^" + (el.format || "{date_short}"), ctx))
  case "color": return esc(el.value || "")
  default: return el.text ? esc(el.text) : ""
  }
}

function richSection(elements, ctx, px, literal) {
  var out = ""
  var list = elements || []
  for (var i = 0; i < list.length; i++) out += richInline(list[i], ctx, px, literal)
  return out
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
      var indent = e.indent || 0
      var items = e.elements || []
      var lines = []
      for (var n = 0; n < items.length; n++) {
        var bullet = e.style === "ordered" ? ((e.offset || 0) + n + 1) + ". " : (["•", "◦", "▪"][indent % 3]) + " "
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

function control(el, lang) {
  if (!el) return null
  var pt = lang === "pt-BR"
  var label = ""
  switch (el.type) {
  case "button": label = (el.text && el.text.text) || ""; break
  case "overflow": label = "⋯"; break
  case "datepicker": label = el.initial_date || (el.placeholder && el.placeholder.text) || (pt ? "Escolha uma data" : "Pick a date"); break
  case "timepicker": label = el.initial_time || (el.placeholder && el.placeholder.text) || (pt ? "Escolha um horário" : "Pick a time"); break
  default:
    if (/select$/.test(el.type || "")) label = ((el.initial_option && el.initial_option.text && el.initial_option.text.text) || (el.placeholder && el.placeholder.text) || (pt ? "Selecionar" : "Select")) + " ▾"
    else return null
  }
  return { label: label, style: el.style || "", url: el.url || "" }
}

function blockParts(blocks, ctx, px) {
  var parts = []
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i]
    switch (b.type) {
    case "rich_text": parts = parts.concat(richTextParts(b, ctx, px)); break
    case "section": {
      var p = { t: "section", html: b.text ? textObj(b.text, ctx, px) : "", fields: [], accessory: null }
      if (b.fields) p.fields = b.fields.map(function(f) { return textObj(f, ctx, px) })
      var a = b.accessory
      if (a && a.type === "image") p.accessory = { kind: "image", url: a.image_url || (a.slack_file && a.slack_file.url) || "", alt: a.alt_text || "" }
      else if (a) { var ctl = control(a, ctx.lang); if (ctl) p.accessory = { kind: "button", label: ctl.label, style: ctl.style, url: ctl.url } }
      parts.push(p)
      break
    }
    case "header": parts.push({ t: "header", html: textObj(b.text, ctx, px) }); break
    case "context": {
      var bits = []
      var imgs = []
      ;(b.elements || []).forEach(function(el) {
        if (el.type === "image") imgs.push(el.image_url || (el.slack_file && el.slack_file.url) || "")
        else bits.push(textObj(el, ctx, px))
      })
      parts.push({ t: "context", html: bits.join("&nbsp;&nbsp;"), images: imgs.filter(function(u) { return u }) })
      break
    }
    case "actions": {
      var items = (b.elements || []).map(function(el) { return control(el, ctx.lang) }).filter(function(x) { return x })
      if (items.length) parts.push({ t: "actions", items: items })
      break
    }
    case "divider": parts.push({ t: "divider" }); break
    case "image": {
      var url = b.image_url || (b.slack_file && b.slack_file.url) || ""
      if (url) parts.push({ t: "image", url: url, w: b.image_width || 0, h: b.image_height || 0, title: b.title ? b.title.text : "", alt: b.alt_text || "" })
      break
    }
    case "video": parts.push({ t: "video", title: (b.title && b.title.text) || "", url: b.title_url || b.video_url || "", thumb: b.thumbnail_url || "" }); break
    case "file": parts.push({ t: "text", html: "📎 " + esc(b.source === "remote" ? "file" : "file"), muted: true }); break
    default: break
    }
  }
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
              title: a.title ? inlineMrkdwn(a.title, ctx, px) : "", titleLink: a.title_link || a.from_url || "",
              parts: [], fields: [], image: null, thumb: a.thumb_url || "", footer: a.footer ? inlineBlock(a.footer, ctx, px) : "",
              actions: [], ts: a.ts || "", isMsg: a.is_msg_unfurl === true || a.is_share === true }
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
    out.actions.push({ label: x.text || x.name || "", style: x.style || "", url: x.url || "" })
  })
  if (!out.parts.length && !out.title && !out.fields.length && !out.image && !out.pretext && !out.author && a.fallback) {
    out.parts = mrkdwnParts(a.fallback, ctx, px)
  }
  if (a.is_msg_unfurl || a.is_share) {
    // A shared message: author line from the original.
    if (!out.author && a.author_subname) out.author = a.author_subname
  }
  return out
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
