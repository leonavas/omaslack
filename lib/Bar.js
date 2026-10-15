.pragma library
.import "Util.js" as U
.import "Mrkdwn.js" as Md
.import "Emoji.js" as E

// Pure helpers for the bar widget (Widget.qml). The signed-in workspaces
// are folded into one shape (`snapshot`), so the badges, the hover card's
// rows and the labels follow the same rules. `snapshot` reads every
// workspace's revision counters first: QML captures them, so the widget's
// bindings follow every change.

function countOf(value) {
  var count = Number(value)
  return isFinite(count) && count > 0 ? Math.floor(count) : 0
}

function tr(lang, en, pt) { return lang === "pt-BR" ? pt : en }

// The bar's kinds: dm, group, private, channel.
function kindOf(c) {
  var k = c ? c.kind : ""
  return k === "im" ? "dm" : k === "mpim" ? "group" : k === "private" ? "private" : "channel"
}

// Nerd Font glyphs: account, account-multiple, lock; a plain # for channels.
function kindGlyph(kind) {
  if (kind === "dm") return "󰀄"
  if (kind === "group") return "󰀎"
  if (kind === "private") return "󰌾"
  return "#"
}

// -------------------------------------------------------------------- state

function emptySnapshot() {
  return {
    live: false, connecting: false, team: "", attention: 0, quietKnown: true,
    totals: { mentions: 0, dms: 0, groups: 0, channels: 0, channelsMentioned: 0, channelsQuiet: 0,
              directMessages: 0, channelMentions: 0 },
    conversations: [], threads: { replies: 0, mentions: 0, attention: 0, list: [] }, reactions: [], dnd: null
  }
}

// Every signed-in workspace as one state: counts added up, the lists merged
// (conversations and threads by latest activity, reactions newest first).
// `current` is the workspace on screen: its name heads the card and its
// pause is the one told. A workspace counts once it is booted; until its
// notification preferences are in, every channel waits quietly, so no badge
// shows more than is there.
function snapshot(list, current, nowSec) {
  var s = emptySnapshot()
  var paused = []
  for (var i = 0; i < (list || []).length; i++) {
    var w = list[i]
    if (!w) continue
    w.countsRev; w.convsRev; w.usersRev; w.threadsRev; w.presenceRev; w.reactionRev
    if (!w.booted) continue
    s.live = true
    // Its socket is down: the counts are the last known until it is back.
    if (!w.live) s.connecting = true
    if (!w.prefsLoaded) s.quietKnown = false
    addWorkspace(s, w, nowSec)
    if (w.dnd) paused.push(w)
  }
  s.conversations.sort(function(a, b) { return U.cmpTs(b.latest, a.latest) })
  s.threads.list.sort(function(a, b) { return U.cmpTs(b.latest, a.latest) })
  s.reactions.sort(function(a, b) { return b.at - a.at })
  // Conversations with something waiting: DMs and group DMs, channels that
  // mention you, and threads that mention you or sit in a DM.
  s.attention = s.totals.dms + s.totals.groups + s.totals.channelsMentioned + s.threads.attention
  var head = current || (list && list.length ? list[0] : null)
  s.team = head && head.team ? String(head.team.name || "") : ""
  if (paused.length) {
    var p = paused.indexOf(current) >= 0 ? current : paused[0]
    s.dnd = { paused: true, until: Number(p.dnd.until) || 0, snooze: p.dnd.snooze === true }
  }
  return s
}

function addWorkspace(s, w, nowSec) {
  var t = s.totals
  // The conversation in front of you counts as read.
  var reading = w.focused && w.view === "conv" ? w.current : ""
  for (var id in w.counts) {
    var k = w.counts[id], c = w.convs[id]
    if (!k || !c || c.archived || c.guest || id === reading) continue
    var unread = k.unread === true, m = countOf(k.mentions)
    if (!unread && m === 0) continue
    if (c.kind === "im" && w.users[c.user] && w.users[c.user].deleted) continue
    var kind = kindOf(c)
    var direct = kind === "dm" || kind === "group"
    // Muted, or set to notify of mentions only (or nothing) on its own:
    // such a channel waits quietly, out of the badges and the rows. A
    // channel that follows the global level still notifies.
    var quiet = !direct && (!w.prefsLoaded || w.isQuiet(id))
    t.mentions += m
    // Messages rather than conversations: in a DM every unread message is
    // a mention, so this is how many wait there; in channels, the mentions.
    if (direct) t.directMessages += Math.max(1, m)
    else t.channelMentions += m
    if (kind === "dm") t.dms++
    else if (kind === "group") t.groups++
    else if (m > 0) t.channelsMentioned++
    else { t.channels++; if (quiet) t.channelsQuiet++ }
    s.conversations.push({ ws: w, id: id, kind: kind, name: w.convLabel(id) || id, mentions: m, unread: unread,
                           latest: String(k.latest || ""), lastRead: String(k.lastRead || ""), quiet: quiet })
  }

  // Threads you follow with replies after where you read: Slack's count of
  // those replies, and of the ones that mention you.
  var me = w.me ? w.me.id : ""
  var view = w.threadsView || { list: [], total: 0 }
  var sum = 0, attention = 0
  for (var j = 0; j < (view.list || []).length; j++) {
    var th = view.list[j]
    if (!th || !th.unread || !th.root) continue
    var fresh = unreadReplies(th)
    var mention = fresh.some(function(r) { return Md.mentions(r, me) })
    var tkind = kindOf(w.convs[th.conv])
    if (mention || tkind === "dm" || tkind === "group") attention++
    var n = Math.max(1, countOf(th.newCount))
    sum += n
    s.threads.list.push({ ws: w, id: th.conv, kind: tkind, name: w.convLabel(th.conv) || th.conv, ts: String(th.root.ts || ""),
                          root: th.root, latest: String(th.latest || th.root.ts || ""), count: n, mention: mention,
                          messages: fresh.slice(-5) })
  }
  s.threads.replies += Math.max(countOf(view.total), sum)
  s.threads.mentions += countOf(w.threads ? w.threads.mentions : 0)
  s.threads.attention += attention

  // Reactions to your messages, for a day.
  var feed = w.reactionFeed || []
  for (var r = 0; r < feed.length; r++) {
    var it = feed[r]
    if (!it || nowSec - it.at >= 86400) continue
    s.reactions.push({ ws: w, conv: it.conv, ts: it.ts, name: it.name, user: it.user, at: it.at, msg: it.msg || null })
  }
}

function unreadReplies(th) {
  return (th.replies || []).filter(function(r) { return r && U.cmpTs(r.ts, th.lastRead) > 0 })
}

// The card's "waiting" number (see `snapshot`).
function attention(state) {
  return state ? countOf(state.attention) : 0
}

// `mentionsOnly` (the "Channel mentions only" setting) treats every unread
// channel without a mention as quiet.
function totals(state, mentionsOnly) {
  var t = state ? state.totals : emptySnapshot().totals
  var known = !!state && state.quietKnown && !mentionsOnly
  return {
    mentions: countOf(t.mentions),
    dms: countOf(t.dms),
    groups: countOf(t.groups),
    channels: countOf(t.channels),
    channelsMentioned: countOf(t.channelsMentioned),
    // Unread channels without a mention that are muted or set to mentions
    // only; with "Channel mentions only", all of them.
    channelsQuiet: known ? countOf(t.channelsQuiet) : countOf(t.channels),
    quietKnown: known,
  }
}

// Unread messages in DMs and group DMs: the red badge.
function directMessages(state) {
  return state ? countOf(state.totals.directMessages) : 0
}

// Messages mentioning you in channels: the blue badge's base.
function channelMentions(state) {
  return state ? countOf(state.totals.channelMentions) : 0
}

// The channel badge's number for the `channelBadge` setting: "Unread"
// (mentions plus unread channels that notify you: not muted, not set to
// mentions only), "Mentions", "All unread" (mentions plus every unread
// channel) or "None".
function channelBadgeCount(state, mode, mentionsOnly) {
  if (mode === "None") return 0
  var count = channelMentions(state)
  var t = totals(state, mentionsOnly)
  if (mode === "All unread") count += t.channels
  else if (mode !== "Mentions") count += Math.max(0, t.channels - t.channelsQuiet)
  return count
}

// Paused by the user (Slack's snooze), still in the future. Slack's
// scheduled night-time DND (`snooze: false`) is deliberately not "muted":
// the badges keep counting through it.
function snoozed(state, nowSec) {
  var dnd = state ? state.dnd : null
  if (!dnd || dnd.paused !== true || dnd.snooze !== true) return false
  var until = Number(dnd.until)
  return !(isFinite(until) && until > 0 && until <= nowSec)
}

function dndActive(state, nowSec) {
  var dnd = state ? state.dnd : null
  if (!dnd || dnd.paused !== true) return false
  var until = Number(dnd.until)
  return !(isFinite(until) && until > 0 && until <= nowSec)
}

function dndUntil(state) {
  var dnd = state ? state.dnd : null
  var until = dnd ? Number(dnd.until) : 0
  return isFinite(until) && until > 0 ? until : 0
}

// ------------------------------------------------------------------- labels

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var WEEKDAYS_PT = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS_PT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

// Calendar days from now's day to when's day; DST days are 23 or 25 hours
// long, so the difference is rounded rather than floored.
function dayOffset(when, now) {
  var a = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var b = new Date(when.getFullYear(), when.getMonth(), when.getDate()).getTime()
  return Math.round((b - a) / 86400000)
}

// "Oct 20" / "20 de out", with the year only when it is not this one.
function dateLabel(when, now, lang) {
  var other = when.getFullYear() !== now.getFullYear()
  if (lang === "pt-BR") return when.getDate() + " de " + MONTHS_PT[when.getMonth()] + (other ? " de " + when.getFullYear() : "")
  return MONTHS[when.getMonth()] + " " + when.getDate() + (other ? " " + when.getFullYear() : "")
}

function hourMinute(when, clock24) {
  return clock24 === false ? U.time(when, false) : pad(when.getHours()) + ":" + pad(when.getMinutes())
}

// "14:30" today, "tomorrow 08:00", "Tue 08:00" within the coming week,
// otherwise "Oct 20, 08:00". A bare weekday further out would point at the
// wrong week.
function clockLabel(unixSec, nowSec, lang, clock24) {
  if (!unixSec) return ""
  var when = new Date(unixSec * 1000)
  var now = new Date(nowSec * 1000)
  var hm = hourMinute(when, clock24)
  var days = dayOffset(when, now)
  if (days === 0) return hm
  if (days === 1) return tr(lang, "tomorrow ", "amanhã ") + hm
  if (days > 1 && days <= 6) return (lang === "pt-BR" ? WEEKDAYS_PT : WEEKDAYS)[when.getDay()] + " " + hm
  return dateLabel(when, now, lang) + ", " + hm
}

// The day picker's label for `offset` days from now: "Today", "Tomorrow",
// then "Wed, Oct 14".
function pickerDayLabel(offset, nowSec, lang) {
  if (offset === 0) return tr(lang, "Today", "Hoje")
  if (offset === 1) return tr(lang, "Tomorrow", "Amanhã")
  var now = new Date(nowSec * 1000)
  var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset)
  return (lang === "pt-BR" ? WEEKDAYS_PT : WEEKDAYS)[day.getDay()] + ", " + dateLabel(day, now, lang)
}

// Unix seconds of hour:minute, `offset` days from now's day. Built from the
// calendar date, so month ends and DST come out right.
function pickerTarget(offset, hour, minute, nowSec) {
  var now = new Date(nowSec * 1000)
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset, hour, minute, 0).getTime() / 1000
}

// Where the picker starts: the full hour after the next one (14:20 gives
// 16:00), rolling over into tomorrow when that passes midnight.
function pickerDefault(nowSec) {
  var now = new Date(nowSec * 1000)
  var hour = now.getHours() + 2
  return { day: hour >= 24 ? 1 : 0, hour: hour % 24, minute: 0 }
}

// Whole minutes from now to the target, rounded up so the pause never ends
// before the time picked. 0 when the target is not in the future.
function minutesUntil(targetSec, nowSec) {
  var delta = targetSec - nowSec
  return delta > 0 ? Math.ceil(delta / 60) : 0
}

// Minutes until 08:00 of the next morning. Past midnight but before 04:00
// "tomorrow" still means the coming morning, not the one after it.
function minutesUntilTomorrow(nowSec) {
  var now = new Date(nowSec * 1000)
  var target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 8, 0, 0)
  if (now.getHours() >= 4) target.setDate(target.getDate() + 1)
  return Math.max(1, Math.ceil((target.getTime() - now.getTime()) / 60000))
}

// Slack timestamps are "seconds.micros" strings.
function tsSeconds(ts) {
  var value = parseFloat(String(ts || ""))
  return isFinite(value) && value > 0 ? value : 0
}

function relativeTime(ts, nowSec, lang) {
  var then = tsSeconds(ts)
  if (!then) return ""
  var delta = Math.max(0, nowSec - then)
  if (delta < 60) return tr(lang, "now", "agora")
  if (delta < 3600) return Math.floor(delta / 60) + tr(lang, "m", " min")
  if (delta < 86400) return Math.floor(delta / 3600) + tr(lang, "h", " h")
  return Math.floor(delta / 86400) + tr(lang, "d", " d")
}

function badgeLabel(count) {
  return count > 99 ? "99+" : String(count)
}

// ----------------------------------------------------------------- messages

// Who a message shows as: the person, or the app and the name it set.
function authorName(w, m) {
  if (!m) return ""
  if (typeof w.author === "function") {
    var a = w.author(m)
    if (a && a.name) return String(a.name)
  }
  return m.user ? (w.userName(m.user) || "") : String(m.botName || "")
}

function oneLine(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}

// A message as the card's HTML: its own bold, italic and strikethrough, and
// emoji as <img> (standard ones as Slack's pictures, the workspace's own
// from their URL, GIFs included). Mentions, channels and links stay as
// their labels once `messageTokens` drops every other tag.
function messageHtml(m, ctx) {
  var text = String(m.text || "")
  if (Md.systemText(m, ctx.lang) || text.trim().length === 0) return U.escapeHtml(Md.flat(m, ctx, 500))
  if (text.length > 500) {
    text = text.slice(0, 500)
    var open = text.lastIndexOf("<")
    if (open > text.lastIndexOf(">")) text = text.slice(0, open)
    text += "…"
  }
  text = text.split("\n").map(function(line) { return line.replace(/^(&gt;|>)\s?/, "") }).join(" ").replace(/```/g, " ")
  return Md.inlineMrkdwn(text, ctx, ctx.emojiPx)
}

var STYLE_TAGS = { b: true, i: true, s: true }

// A message as tokens for a Flow: { kind: "text", html } per word, its
// style kept, and { kind: "img", src, animated } per emoji. The HTML comes
// from our own renderer (`messageHtml`), which escapes what the message
// says: only <b>, <i>, <s> and its emoji <img> survive here, every other
// tag (links, pills, code) gives way to its text.
function messageTokens(html, prefix) {
  html = U.escapeHtml(prefix || "") + String(html || "").replace(/\s+/g, " ").trim()
  var tokens = []
  var open = []
  var word = ""
  function wrap(text) {
    var opening = open.map(function (t) { return "<" + t + ">" }).join("")
    var closing = open.slice().reverse().map(function (t) { return "</" + t + ">" }).join("")
    return opening + text + closing
  }
  function flush() {
    if (word.length === 0) return
    tokens.push({ kind: "text", html: wrap(word) + "&nbsp;", src: "", animated: false })
    word = ""
  }
  var i = 0
  while (i < html.length) {
    var c = html[i]
    if (c === " ") { flush(); i++; continue }
    if (c === "<") {
      var end = html.indexOf(">", i)
      if (end < 0) break
      var tag = html.slice(i + 1, end)
      var name = tag.replace(/^\//, "").split(/[\s\/]/)[0].toLowerCase()
      if (STYLE_TAGS[name]) {
        // A word split by a tag ("ab<b>cd</b>") stays one word.
        if (word.length > 0) {
          tokens.push({ kind: "text", html: wrap(word), src: "", animated: false })
          word = ""
        }
        if (tag[0] === "/") {
          var at = open.lastIndexOf(name)
          if (at >= 0) open.splice(at, 1)
        } else {
          open.push(name)
        }
      } else if (name === "img") {
        flush()
        var src = (tag.match(/src="([^"]*)"/) || [])[1] || ""
        src = src.replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
        if (/^(https?|file):\/\//i.test(src))
          tokens.push({ kind: "img", html: "", src: src, animated: /\.gif(\?|#|$)/i.test(src) })
      } else if (name === "br") {
        flush()
      }
      i = end + 1
      continue
    }
    word += c
    i++
  }
  flush()
  return tokens
}

// A message as a desktop notification's body: markup with only its own
// bold, italic and strikethrough; mentions, channels, links and code as
// their text, emoji as characters (the workspace's own as :name:). Escaped
// like the card's: nothing a message says becomes markup of its own.
function notificationHtml(m, ctx) {
  var plain = {}
  for (var k in ctx) plain[k] = ctx[k]
  plain.slackEmoji = false
  plain.custom = {}
  return messageHtml(m, plain).replace(/<br\s*\/?>/gi, " ").replace(/<(\/?)([A-Za-z]+)[^>]*>/g, function(all, close, name) {
    name = name.toLowerCase()
    return STYLE_TAGS[name] ? "<" + close + name + ">" : ""
  }).replace(/\s+/g, " ").trim()
}

// One renderer context per workspace and call: `colors` the theme's HTML
// colors, `px` the emoji size.
function contexts(colors, px) {
  var cache = {}
  return function(w) {
    if (!cache[w.teamId]) cache[w.teamId] = w.renderCtx(colors, px)
    return cache[w.teamId]
  }
}

// The unread messages the card shows for a conversation, oldest first: the
// ones fetched after where you read (`Workspace.fetchUnreadPreview`), else
// the last one heard, when it is newer than those (a fetch is on its way).
function unreadMessages(conv) {
  var w = conv.ws
  w.previewRev; w.lastRev
  var have = w.unreadPreviews ? w.unreadPreviews[conv.id] : null
  var msgs = have && have.msgs ? have.msgs.filter(function(m) { return U.cmpTs(m.ts, conv.lastRead) > 0 }) : []
  var last = w.lastMsgs ? w.lastMsgs[conv.id] : null
  var newest = msgs.length ? msgs[msgs.length - 1].ts : conv.lastRead
  if (last && !(last.threadTs && last.threadTs !== last.ts && last.subtype !== "thread_broadcast") && U.cmpTs(last.ts, newest) > 0)
    msgs = msgs.concat([last]).slice(-5)
  return msgs
}

// Does a conversation belong in the preview? DMs, group DMs, channels that
// mention you and channels that notify you get a row; muted or
// mentions-only channels only count in the footer, unless every unread
// channel was asked for.
function eligible(conv, includeChannels, mentionsOnly) {
  var kind = conv.kind
  if (kind === "dm" || kind === "group") return true
  return includeChannels || countOf(conv.mentions) > 0 || (!mentionsOnly && conv.quiet === false)
}

// The rows the hover card renders, already trimmed so the QML side can
// trust every field to exist. `messagesPerChat` is how many of the newest
// unread messages each row shows (up to the five fetched). Returns
// { rows, hidden } where hidden counts eligible conversations past the row
// cap.
function previewRows(state, max, messagesPerChat, includeChannels, mentionsOnly, colors, px) {
  var result = { rows: [], hidden: 0 }
  if (!state) return result
  var limit = Math.max(1, Number(max) || 6)
  var perChat = Math.max(1, Math.min(5, Number(messagesPerChat) || 3))
  var ctxOf = contexts(colors, px)
  var list = state.conversations
  for (var i = 0; i < list.length; i++) {
    var conv = list[i]
    if (!eligible(conv, includeChannels, mentionsOnly)) continue
    if (result.rows.length >= limit) { result.hidden += 1; continue }
    var w = conv.ws
    var ctx = ctxOf(w)
    var kind = conv.kind
    var name = String(conv.name).trim()
    var messages = unreadMessages(conv).slice(-perChat)
    // The newest unread messages, oldest first; the author only where it
    // changes, and never in a DM with that person.
    var lines = []
    var lastAuthor = ""
    for (var m = 0; m < messages.length; m++) {
      var msg = messages[m]
      if (!msg) continue
      var by = authorName(w, msg).trim()
      var prefixed = by.length > 0 && by !== lastAuthor && !(kind === "dm" && by === name)
      var tokens = messageTokens(messageHtml(msg, ctx), prefixed ? by + ": " : "")
      if (tokens.length === 0) continue
      lines.push({ tokens: tokens })
      lastAuthor = by
    }
    var last = messages.length > 0 ? messages[messages.length - 1] : null
    var ts = last && last.ts ? String(last.ts) : ""
    var threadTs = last && last.threadTs ? String(last.threadTs) : ""
    result.rows.push({
      team: w.teamId,
      teamName: w.team ? String(w.team.name || "") : "",
      id: conv.id,
      kind: kind,
      glyph: kindGlyph(kind),
      name: kind === "channel" || kind === "private" ? name.replace(/^#/, "") : name,
      mentions: countOf(conv.mentions),
      unread: conv.unread !== false,
      latest: conv.latest || ts,
      messages: lines,
      ts: ts,
      threadTs: threadTs !== ts ? threadTs : "",
    })
  }
  return result
}

// The conversations a card's rows show, for fetching their unread messages.
function previewTargets(state, max, includeChannels, mentionsOnly) {
  var out = []
  var list = state ? state.conversations : []
  var limit = Math.max(1, Number(max) || 6)
  for (var i = 0; i < list.length && out.length < limit; i++)
    if (eligible(list[i], includeChannels, mentionsOnly)) out.push(list[i])
  return out
}

// ------------------------------------------------------------------ threads

// New replies in the threads you follow.
function threadReplies(state) {
  return state ? countOf(state.threads.replies) : 0
}

// Thread replies that mention you: Slack's own count.
function threadMentions(state) {
  return state ? countOf(state.threads.mentions) : 0
}

// The thread replies the blue badge adds, for the `channelBadge` setting:
// the new replies that do not mention you (those go to the red badge, as in
// Slack). None under "Mentions" or "None".
function threadBadgeCount(state, mode) {
  if (mode === "None" || mode === "Mentions") return 0
  return Math.max(0, threadReplies(state) - threadMentions(state))
}

// Unread threads as rows for the hover card, newest activity first: where,
// the thread's first message, and its latest new reply. Returns
// { rows, hidden } like previewRows. A click opens the thread at that reply.
function threadRows(state, max, colors, px) {
  var result = { rows: [], hidden: 0 }
  var list = state ? state.threads.list : []
  var limit = Math.max(1, Number(max) || 6)
  var ctxOf = contexts(colors, px)
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (result.rows.length >= limit) { result.hidden += 1; continue }
    var w = item.ws
    var ctx = ctxOf(w)
    var kind = item.kind
    var name = String(item.name).trim()
    if (kind === "channel" || kind === "private") name = name.replace(/^#/, "")
    var rootBy = authorName(w, item.root).trim()
    var rootText = oneLine(Md.flat(item.root, ctx, 300))
    var last = item.messages.length > 0 ? item.messages[item.messages.length - 1] : null
    var by = last ? authorName(w, last).trim() : ""
    var reply = last ? messageTokens(messageHtml(last, ctx), by.length > 0 ? by + ": " : "") : []
    var ts = last && last.ts ? String(last.ts) : item.ts
    result.rows.push({
      team: w.teamId,
      teamName: w.team ? String(w.team.name || "") : "",
      id: item.id,
      kind: kind,
      glyph: kindGlyph(kind),
      name: name,
      count: item.count,
      mention: item.mention === true,
      latest: item.latest || ts,
      root: rootText.length > 0 ? (rootBy.length > 0 ? rootBy + ": " + rootText : rootText) : "",
      reply: reply,
      ts: ts,
      threadTs: item.ts,
    })
  }
  return result
}

// ---------------------------------------------------------------- reactions

// How to draw a reaction: { text, image, animated }. Slack's picture of a
// standard emoji (or its character, with the app set to the system's), the
// workspace's own from its URL, animated when it is a GIF, else :name:.
// `text` is there with a picture too: the character (or :name:) that
// stands in while it loads or when it doesn't come.
function reactionVisual(item) {
  var w = item.ws
  var name = String(item.name || "")
  var shortcode = ":" + name.split("::")[0] + ":"
  var r = E.resolve(name, w.customEmoji, w.emojiAliases)
  if (!r) return { text: shortcode, image: "", animated: false }
  if (r.url) return { text: shortcode, image: String(r.url), animated: /\.gif(\?|#|$)/i.test(r.url) }
  if (!w.app || w.app.slackEmoji !== false) return { text: r.glyph, image: E.imageUrl(E.known(r.glyph) || r.glyph), animated: false }
  return { text: r.glyph, image: "", animated: false }
}

// What tells one reaction from another across snapshots: a new key in the
// next snapshot is a reaction that just happened.
function reactionKey(item) {
  if (!item) return ""
  return [item.ws ? item.ws.teamId : "", item.conv, item.ts, item.name, item.user, item.at].join("|")
}

// Reactions in `state` whose keys are not in `seen` (a key -> true map), as
// visuals, newest first. Returns { keys, fresh }; `keys` replaces `seen`.
function newReactions(state, seen) {
  var result = { keys: {}, fresh: [] }
  var list = state ? state.reactions : []
  for (var i = 0; i < list.length; i++) {
    var key = reactionKey(list[i])
    if (key.length === 0) continue
    result.keys[key] = true
    if (seen && !seen[key]) result.fresh.push(reactionVisual(list[i]))
  }
  return result
}

// The reactions other people put on your messages, as rows for the hover
// card: newest first. Returns { rows, hidden } like previewRows. They never
// count toward the badges.
function reactionRows(state, max, colors, px, lang) {
  var result = { rows: [], hidden: 0 }
  if (!state) return result
  var limit = Math.max(1, Number(max) || 6)
  var ctxOf = contexts(colors, px)
  var list = state.reactions
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var visual = reactionVisual(item)
    if (visual.text.length === 0 && visual.image.length === 0) continue
    if (result.rows.length >= limit) { result.hidden += 1; continue }
    var w = item.ws
    var c = w.convs[item.conv]
    var kind = kindOf(c)
    var name = String(w.convLabel(item.conv) || item.conv).trim()
    if (kind === "channel" || kind === "private") name = name.replace(/^#/, "")
    var who = String(w.userName(item.user) || "").trim()
    var msg = item.msg
    var ts = String(item.ts || "")
    var threadTs = msg && msg.threadTs ? String(msg.threadTs) : ""
    // In a DM with the person who reacted, the conversation's name is
    // theirs: the line goes to the message instead.
    var where = kind === "dm" && name === who ? "" : name
    var text = msg ? oneLine(Md.flat(msg, ctxOf(w), 200)) : ""
    result.rows.push({
      team: w.teamId,
      id: item.conv,
      kind: kind,
      glyph: kindGlyph(kind),
      who: who.length > 0 ? who : tr(lang, "Someone", "Alguém"),
      emoji: visual,
      where: where,
      line: where.length > 0 && text.length > 0 ? where + " · " + text : (text.length > 0 ? text : where),
      latest: String(item.at),
      ts: ts,
      threadTs: threadTs !== ts ? threadTs : "",
    })
  }
  return result
}
