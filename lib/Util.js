.pragma library

// Small pure helpers shared by the store and the views: Slack timestamps,
// dates the way Slack writes them, names, search ranking, sizes.

function tr(lang, en, pt) { return lang === "pt-BR" ? pt : en }

// ------------------------------------------------------------------ ts

function tsDate(ts) { return new Date(Math.floor(parseFloat(ts || "0") * 1000)) }
function tsNum(ts) { return parseFloat(ts || "0") || 0 }
function nowTs() {
  var ms = Date.now()
  return Math.floor(ms / 1000) + "." + String((ms % 1000) * 1000).padStart(6, "0")
}

// The ts right before this one (mark unread): one microsecond earlier.
function tsBefore(ts) {
  var parts = String(ts || "").split(".")
  var sec = parseInt(parts[0] || "0", 10)
  var us = parseInt((parts[1] || "0").padEnd(6, "0").slice(0, 6), 10)
  if (us > 0) us -= 1
  else { sec -= 1; us = 999999 }
  return sec + "." + String(us).padStart(6, "0")
}

function cmpTs(a, b) {
  var x = tsNum(a), y = tsNum(b)
  if (x !== y) return x < y ? -1 : 1
  return String(a) < String(b) ? -1 : (String(a) > String(b) ? 1 : 0)
}

// ------------------------------------------------------------------ dates

var MONTHS_EN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var MONTHS_PT = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
var DAYS_EN = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var DAYS_PT = ["domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado"]
var MON_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MON_PT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

function ordinal(n) {
  var s = ["th", "st", "nd", "rd"], v = n % 100
  return n + (s[(v - 20) % 10] || s[v] || s[0])
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

function dayDiff(d, now) {
  var a = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  var b = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  return Math.round((b - a) / 86400000)
}

function time(d, clock24, seconds) {
  var h = d.getHours(), m = String(d.getMinutes()).padStart(2, "0")
  if (seconds) m += ":" + String(d.getSeconds()).padStart(2, "0")
  if (clock24) return String(h).padStart(2, "0") + ":" + m
  var ap = h >= 12 ? "PM" : "AM"
  h = h % 12; if (h === 0) h = 12
  return h + ":" + m + " " + ap
}

function tsTime(ts, clock24) { return time(tsDate(ts), clock24) }

// "Today", "Yesterday", "Monday, September 28th" (year added when not this year).
function dayLabel(d, lang) {
  var now = new Date()
  var diff = dayDiff(d, now)
  if (diff === 0) return tr(lang, "Today", "Hoje")
  if (diff === 1) return tr(lang, "Yesterday", "Ontem")
  var year = d.getFullYear() !== now.getFullYear()
  if (lang === "pt-BR") {
    var s = DAYS_PT[d.getDay()] + ", " + d.getDate() + " de " + MONTHS_PT[d.getMonth()]
    if (year) s += " de " + d.getFullYear()
    return s.charAt(0).toUpperCase() + s.slice(1)
  }
  return DAYS_EN[d.getDay()] + ", " + MONTHS_EN[d.getMonth()] + " " + ordinal(d.getDate()) + (year ? ", " + d.getFullYear() : "")
}

// "today at 10:20", "yesterday at 9:00", "on October 3rd", "on October 3rd, 2024".
function whenLabel(ts, lang, clock24) {
  var d = tsDate(ts), now = new Date()
  var diff = dayDiff(d, now)
  if (diff === 0) return tr(lang, "today at ", "hoje às ") + time(d, clock24)
  if (diff === 1) return tr(lang, "yesterday at ", "ontem às ") + time(d, clock24)
  var year = d.getFullYear() !== now.getFullYear()
  if (lang === "pt-BR") return "em " + d.getDate() + " de " + MONTHS_PT[d.getMonth()] + (year ? " de " + d.getFullYear() : "")
  return "on " + MONTHS_EN[d.getMonth()] + " " + ordinal(d.getDate()) + (year ? ", " + d.getFullYear() : "")
}

// A message's time standing on its own (the Delete message preview):
// "Today at 7:53 AM", "Yesterday at 9:00 AM", "Oct 3rd at 10:20 AM",
// "Oct 3rd, 2024 at 10:20 AM".
function atLabel(ts, lang, clock24) {
  var d = tsDate(ts), now = new Date()
  var diff = dayDiff(d, now)
  var t = time(d, clock24)
  if (diff === 0) return tr(lang, "Today at ", "Hoje às ") + t
  if (diff === 1) return tr(lang, "Yesterday at ", "Ontem às ") + t
  var year = d.getFullYear() !== now.getFullYear()
  if (lang === "pt-BR") return d.getDate() + " de " + MON_PT[d.getMonth()] + (year ? " de " + d.getFullYear() : "") + " às " + t
  return MON_EN[d.getMonth()] + " " + ordinal(d.getDate()) + (year ? ", " + d.getFullYear() : "") + " at " + t
}

// A day on its own: "Oct 22nd", "22 de out." (year added when not this year).
function dateStamp(ts, lang) {
  var d = tsDate(ts), year = d.getFullYear() !== new Date().getFullYear()
  if (lang === "pt-BR") return d.getDate() + " de " + MON_PT[d.getMonth()] + "." + (year ? " de " + d.getFullYear() : "")
  return MON_EN[d.getMonth()] + " " + ordinal(d.getDate()) + (year ? ", " + d.getFullYear() : "")
}

// Short stamp for lists: "10:20", "Yesterday", "Mon", "Oct 3", "Oct 3, 2024".
function shortStamp(ts, lang, clock24) {
  var d = tsDate(ts), now = new Date()
  var diff = dayDiff(d, now)
  if (diff === 0) return time(d, clock24)
  if (diff === 1) return tr(lang, "Yesterday", "Ontem")
  if (diff < 7) return (lang === "pt-BR" ? DAYS_PT : DAYS_EN)[d.getDay()].slice(0, 3)
  var s = lang === "pt-BR" ? d.getDate() + " de " + MON_PT[d.getMonth()] : MON_EN[d.getMonth()] + " " + d.getDate()
  if (d.getFullYear() !== now.getFullYear()) s += ", " + d.getFullYear()
  return s
}

// "2 minutes ago" style for the Threads view and search results.
function relative(ts, lang, clock24) {
  var d = tsDate(ts), now = new Date()
  var secs = Math.max(0, (now - d) / 1000)
  if (secs < 60) return tr(lang, "just now", "agora")
  if (secs < 3600) {
    var m = Math.floor(secs / 60)
    return lang === "pt-BR" ? "há " + m + (m === 1 ? " minuto" : " minutos") : m + (m === 1 ? " minute ago" : " minutes ago")
  }
  var diff = dayDiff(d, now)
  if (diff === 0) return tr(lang, "Today at ", "Hoje às ") + time(d, clock24)
  if (diff === 1) return tr(lang, "Yesterday at ", "Ontem às ") + time(d, clock24)
  if (diff < 7) {
    var day = lang === "pt-BR" ? DAYS_PT[d.getDay()] : DAYS_EN[d.getDay()]
    return (lang === "pt-BR" ? day.charAt(0).toUpperCase() + day.slice(1) + " às " : day + " at ") + time(d, clock24)
  }
  if (lang === "pt-BR") return d.getDate() + " de " + MON_PT[d.getMonth()] + " às " + time(d, clock24)
  return MON_EN[d.getMonth()] + " " + ordinal(d.getDate()) + " at " + time(d, clock24)
}

// "just now", "5 minutes ago", "3 days ago", "2 years ago": the rail's
// An app card's footer (Slack's work object), when its data is from:
// "As of today at 3:58 PM", "As of Monday at 3:58 PM", "As of Oct 3rd".
function asOfLabel(d, lang, clock24) {
  var diff = dayDiff(d, new Date()), t = time(d, clock24), pt = lang === "pt-BR"
  if (diff === 0) return tr(lang, "As of today at ", "Atualizado hoje às ") + t
  if (diff === 1) return tr(lang, "As of yesterday at ", "Atualizado ontem às ") + t
  if (diff <= 7) return pt ? "Atualizado " + DAYS_PT[d.getDay()] + " às " + t : "As of " + DAYS_EN[d.getDay()] + " at " + t
  return tr(lang, "As of ", "Atualizado em ") + cardDate(d, lang)
}

// …once the app says when it changed: "Updated 5 min ago", "Updated on Monday".
function updatedLabel(d, lang) {
  var pt = lang === "pt-BR"
  var secs = Math.max(0, (Date.now() - d.getTime()) / 1000)
  var mins = Math.floor(secs / 60), hours = Math.floor(mins / 60), days = Math.floor(hours / 24)
  if (secs < 60) return tr(lang, "Updated just now", "Atualizado agora")
  if (mins < 60) return pt ? "Atualizado há " + mins + " min" : "Updated " + mins + " min ago"
  if (hours < 24) return pt ? "Atualizado há " + hours + (hours === 1 ? " hora" : " horas") : "Updated " + hours + (hours === 1 ? " hour" : " hours") + " ago"
  if (days === 1) return tr(lang, "Updated yesterday", "Atualizado ontem")
  if (days <= 7) return pt ? "Atualizado " + DAYS_PT[d.getDay()] : "Updated on " + DAYS_EN[d.getDay()]
  return tr(lang, "Updated on ", "Atualizado em ") + cardDate(d, lang)
}

// "Oct 3rd" ("Oct 3rd, 2024" another year).
function cardDate(d, lang) {
  var year = d.getFullYear() !== new Date().getFullYear()
  if (lang === "pt-BR") return d.getDate() + " de " + MON_PT[d.getMonth()] + (year ? " de " + d.getFullYear() : "")
  return MON_EN[d.getMonth()] + " " + ordinal(d.getDate()) + (year ? ", " + d.getFullYear() : "")
}

// Files card ("Updated 2 years ago"). `unix` in seconds.
function ago(unix, lang) {
  var secs = Math.max(0, Date.now() / 1000 - (Number(unix) || 0))
  var units = [[31536000, "year", "ano", "anos"], [2592000, "month", "mês", "meses"], [604800, "week", "semana", "semanas"],
               [86400, "day", "dia", "dias"], [3600, "hour", "hora", "horas"], [60, "minute", "minuto", "minutos"]]
  for (var i = 0; i < units.length; i++) {
    var n = Math.floor(secs / units[i][0])
    if (n < 1) continue
    return lang === "pt-BR" ? "há " + n + " " + (n === 1 ? units[i][2] : units[i][3]) : n + " " + units[i][1] + (n === 1 ? "" : "s") + " ago"
  }
  return tr(lang, "just now", "agora")
}

// "until 14:30", "until tomorrow, 8:00", "until Oct 17, 8:00".
function untilLabel(unix, lang, clock24) {
  var d = new Date(unix * 1000), now = new Date()
  var diff = dayDiff(d, now) * -1
  var t = time(d, clock24)
  if (diff <= 0) return tr(lang, "until ", "até ") + t
  if (diff === 1) return tr(lang, "until tomorrow, ", "até amanhã, ") + t
  if (lang === "pt-BR") return "até " + String(d.getDate()).padStart(2, "0") + "/" + String(d.getMonth() + 1).padStart(2, "0") + ", " + t
  return "until " + MON_EN[d.getMonth()] + " " + d.getDate() + ", " + t
}

// When a status clears, as Slack's bubble over it says: "Until today,
// 5:00 PM", "Until tomorrow, 12:00 AM", "Until Friday, 9:00 AM", then a
// date ("Until Oct 20, 9:00 AM"; "Até 20 de out., 09:00").
function statusUntil(unix, lang, clock24) {
  var d = new Date(unix * 1000), now = new Date()
  var ahead = -dayDiff(d, now)
  var pt = lang === "pt-BR"
  var day
  if (ahead <= 0) day = tr(lang, "today", "hoje")
  else if (ahead === 1) day = tr(lang, "tomorrow", "amanhã")
  else if (ahead < 7) day = (pt ? DAYS_PT : DAYS_EN)[d.getDay()]
  else {
    var year = d.getFullYear() !== now.getFullYear()
    day = pt ? d.getDate() + " de " + MON_PT[d.getMonth()] + "." + (year ? " de " + d.getFullYear() : "")
             : MON_EN[d.getMonth()] + " " + d.getDate() + (year ? ", " + d.getFullYear() : "")
  }
  return tr(lang, "Until ", "Até ") + day + ", " + time(d, clock24)
}

function fullDate(d, lang) {
  if (lang === "pt-BR") return d.getDate() + " de " + MONTHS_PT[d.getMonth()] + " de " + d.getFullYear()
  return MONTHS_EN[d.getMonth()] + " " + ordinal(d.getDate()) + ", " + d.getFullYear()
}

// Minutes from now until 09:00 tomorrow / next Monday 09:00.
function minutesUntilTomorrow9() {
  var now = new Date()
  var t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9, 0, 0)
  return Math.max(1, Math.ceil((t - now) / 60000))
}
function minutesUntilNextWeek9() {
  var now = new Date()
  var wd = (now.getDay() + 6) % 7 // monday = 0
  var t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (7 - wd), 9, 0, 0)
  return Math.max(1, Math.ceil((t - now) / 60000))
}
function endOfToday() {
  var n = new Date()
  return Math.floor(new Date(n.getFullYear(), n.getMonth(), n.getDate(), 23, 59, 59) / 1000)
}
function endOfWeek() {
  var n = new Date()
  var wd = (n.getDay() + 6) % 7
  return Math.floor(new Date(n.getFullYear(), n.getMonth(), n.getDate() + (6 - wd), 23, 59, 59) / 1000)
}

// ------------------------------------------------------------------ links

function convUrl(domain, conv) {
  return domain ? "https://" + domain + ".slack.com/archives/" + conv : "https://app.slack.com/client/" + conv
}
function permalink(domain, conv, ts, threadTs) {
  var url = convUrl(domain, conv) + "/p" + String(ts).replace(".", "")
  if (threadTs && threadTs !== ts) url += "?thread_ts=" + threadTs + "&cid=" + conv
  return url
}

// A Slack permalink back to {conv, ts, threadTs}.
function parsePermalink(url) {
  var m = String(url || "").match(/slack\.com\/archives\/([A-Z0-9]+)(?:\/p(\d{16}))?(?:\?(.*))?/)
  if (!m) return null
  var out = { conv: m[1], ts: "", threadTs: "" }
  if (m[2]) out.ts = m[2].slice(0, 10) + "." + m[2].slice(10)
  if (m[3]) {
    var t = m[3].match(/thread_ts=([0-9.]+)/)
    if (t) out.threadTs = t[1]
  }
  return out
}

// ------------------------------------------------------------------ names

function normalizeChannel(name) {
  var s = String(name || "").trim().toLowerCase().replace(/\s+/g, "-")
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if (/[a-z0-9_-]/.test(c) || isLetter(c)) out += c
  }
  return out.slice(0, 80)
}

function initials(name) {
  var parts = String(name || "?").trim().split(/[\s._-]+/).filter(function(p) { return p.length > 0 })
  if (parts.length === 0) return "?"
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[1][0]).toUpperCase()
}

// A stable pleasant hue per id, for avatars without a photo.
function hue(id) {
  var h = 0
  var s = String(id || "")
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360
  return h / 360
}

function humanSize(bytes, lang) {
  var n = Number(bytes) || 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  var s = i === 0 ? String(Math.round(n)) : (n >= 100 ? String(Math.round(n)) : n.toFixed(1))
  if (lang === "pt-BR") s = s.replace(".", ",")
  return s + " " + units[i]
}

function escapeHtml(s) {
  return String(s === undefined || s === null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// ------------------------------------------------------------------ search

// Lowercase, accents dropped: "Conceição" → "conceicao".
// Memoized: the people and channel lists are folded again and again.
var foldCache = new Map()
function fold(s) {
  s = String(s || "")
  var hit = foldCache.get(s)
  if (hit !== undefined) return hit
  var out = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  if (foldCache.size > 60000) foldCache.clear()
  foldCache.set(s, out)
  return out
}

// A letter beyond ASCII (QML's regexps have no \p{L}): anything with case.
function isLetter(c) { return c.toLowerCase() !== c.toUpperCase() }

var tokenCache = new Map()
function tokens(s) {
  var key = String(s || "")
  var hit = tokenCache.get(key)
  if (hit !== undefined) return hit
  var f = fold(s), out = [], cur = ""
  for (var i = 0; i < f.length; i++) {
    var c = f[i]
    if (/[a-z0-9]/.test(c) || isLetter(c)) cur += c
    else if (cur.length) { out.push(cur); cur = "" }
  }
  if (cur.length) out.push(cur)
  if (tokenCache.size > 60000) tokenCache.clear()
  tokenCache.set(key, out)
  return out
}

// Code points of a string (QML's Array.from splits surrogate pairs).
function codePoints(s) {
  var out = []
  s = String(s || "")
  for (var i = 0; i < s.length; i++) {
    var cp = s.codePointAt(i)
    out.push(cp)
    if (cp > 0xffff) i++
  }
  return out
}

// How well `name` answers `query`: 0 best … 6 worst, -1 no match. The tiers,
// best first: equal, prefix, every token starts a word in order, in any
// order, initials, substring, one typo.
function rank(name, query) {
  var q = fold(query).replace(/^[#@]/, "").trim()
  if (q.length === 0) return 5
  var n = fold(name)
  if (n === q) return 0
  var sepN = n.replace(/[\s._-]+/g, " "), sepQ = q.replace(/[\s._-]+/g, " ")
  if (sepN.indexOf(sepQ) === 0) return 1
  var qt = tokens(q), nt = tokens(n)
  if (qt.length === 0) return -1
  // in order
  var j = 0
  for (var i = 0; i < nt.length && j < qt.length; i++) if (nt[i].indexOf(qt[j]) === 0) j++
  if (j === qt.length) return 2
  var all = qt.every(function(t) { return nt.some(function(w) { return w.indexOf(t) === 0 }) })
  if (all) return 3
  if (qt.length > 1) return -1
  var t0 = qt[0]
  if (t0.length >= 2 && t0.length <= 12 && nt.length >= 2) {
    var ini = nt.map(function(w) { return w[0] }).join("")
    if (ini.indexOf(t0) === 0) return 4
  }
  if (n.indexOf(t0) >= 0) return 5
  if (t0.length >= 4) {
    for (var k = 0; k < nt.length; k++) if (oneTypo(nt[k].slice(0, t0.length + 1), t0)) return 6
  }
  return -1
}

function oneTypo(word, q) {
  // prefix of `word` within one edit of q
  var cands = [word.slice(0, q.length), word.slice(0, q.length - 1), word.slice(0, q.length + 1)]
  for (var c = 0; c < cands.length; c++) if (lev1(cands[c], q)) return true
  return false
}

function lev1(a, b) {
  if (Math.abs(a.length - b.length) > 1) return false
  var i = 0, j = 0, edits = 0
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { i++; j++; continue }
    if (++edits > 1) return false
    if (a.length > b.length) i++
    else if (b.length > a.length) j++
    else if (i + 1 < a.length && a[i] === b[j + 1] && a[i + 1] === b[j]) { i += 2; j += 2 }
    else { i++; j++ }
  }
  return edits + (a.length - i) + (b.length - j) <= 1
}

// What matched a search, lit: Slack's highlight marks (\ue000 … \ue001)
// around the words a query token starts. The search overlay and Files.

// Query words to mark in results (Slack misses accents: "cha" → "chá"),
// leaving out the modifiers ("in:#geral", "-word") and the wildcards.
function markTokens(query) {
  var words = String(query || "").split(/\s+/).filter(function(w) { return w && w.indexOf(":") < 0 && w.charAt(0) !== "-" })
  return tokens(words.join(" ").replace(/\*/g, ""))
}

function wordChar(c) { return /[A-Za-z0-9]/.test(c) || (c >= "À" && isLetter(c)) }

// Wraps every word starting with a query token in Slack's highlight marks;
// `prefixOnly`, just the part the token covers.
function addMarks(str, toks, prefixOnly) {
  if (!toks.length) return str
  var out = "", i = 0, n = str.length, inMark = false
  while (i < n) {
    var c = str.charAt(i)
    if (c === "\ue000") { inMark = true; out += c; i++; continue }
    if (c === "\ue001") { inMark = false; out += c; i++; continue }
    if (!wordChar(c)) { out += c; i++; continue }
    var j = i
    while (j < n && wordChar(str.charAt(j))) j++
    var w = str.slice(i, j)
    if (!inMark) {
      var f = fold(w)
      for (var k = 0; k < toks.length; k++) {
        if (f.indexOf(toks[k]) !== 0) continue
        var cut = prefixOnly && f.length === w.length ? toks[k].length : w.length
        w = "\ue000" + w.slice(0, cut) + "\ue001" + w.slice(cut)
        break
      }
    }
    out += w
    i = j
  }
  return out
}

// A one-line name with what matched `toks` lit, bold in `color`, as styled
// text (which elides), escaped. One token lights up mid-word too.
function nameHtml(label, toks, color) {
  if (!toks.length) return escapeHtml(label)
  var m = addMarks(label, toks, true)
  if (m === label && toks.length === 1) {
    var f = fold(label), at = f.indexOf(toks[0])
    if (at >= 0 && f.length === label.length) m = label.slice(0, at) + "\ue000" + label.slice(at, at + toks[0].length) + "\ue001" + label.slice(at + toks[0].length)
  }
  return escapeHtml(m).replace(/\ue000/g, "<b><font color=\"" + color + "\">").replace(/\ue001/g, "</font></b>")
}

// Wraps words starting with a query token in <b>, for previews.
function markWords(html, query) {
  var qt = tokens(query)
  if (qt.length === 0) return html
  return html
}

// ------------------------------------------------------------------ user agent

// Who the sign-in window and the transport say they are: a current desktop
// Chrome, in the reduced form Chrome itself sends, since Slack's pages turn
// away browsers they think are old. The major comes from the date (140
// shipped on 2025-09-02, then one every 4 weeks), one less so it's never a
// version that isn't out yet. lib/transport.py's chrome_ua is the same sum,
// for when it isn't handed this one.
function chromeMajor() {
  return Math.max(140, 140 + Math.floor((Date.now() - Date.UTC(2025, 8, 2)) / (28 * 86400000)) - 1)
}
function chromeUa() {
  return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" + chromeMajor() + ".0.0.0 Safari/537.36"
}

// ------------------------------------------------------------------ misc

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

function uniq(list) {
  var seen = {}, out = []
  for (var i = 0; i < list.length; i++) if (!seen[list[i]]) { seen[list[i]] = true; out.push(list[i]) }
  return out
}

function copy(obj) {
  var o = {}
  for (var k in obj) o[k] = obj[k]
  return o
}

function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

// The desktop's file chooser, as a Process command: Omarchy's own
// (omarchy-file-select, through the desktop portal), else zenity when it's
// there. The paths come one a line on stdout; it exits 1 when nothing was
// picked, 127 with no chooser at all, else (2) the chooser didn't open.
// `exts` ("png jpg") limits the kinds of file, `label` names them.
function filePicker(title, multiple, exts, label) {
  return ["sh", "-c",
    'command -v omarchy-file-select >/dev/null 2>&1 || PATH=$PATH:${OMARCHY_PATH:-/usr/share/omarchy}/bin\n' +
    'if command -v omarchy-file-select >/dev/null 2>&1; then\n' +
    '  omarchy-file-select --title "$1" ${2:+--multiple} ${3:+--extensions "$3"}; rc=$?\n' +
    '  [ "$rc" -eq 2 ] && command -v zenity >/dev/null 2>&1 || exit "$rc"\n' +
    'fi\n' +
    'command -v zenity >/dev/null 2>&1 || exit 127\n' +
    'title=$1 multiple=$2 exts=$3 label=$4\n' +
    'set -- --file-selection --title="$title"\n' +
    '[ -z "$multiple" ] || set -- "$@" --multiple --separator="\n"\n' +
    'if [ -n "$exts" ]; then f=; for e in $exts; do f="$f *.$e *.$(printf %s "$e" | tr a-z A-Z)"; done; set -- "$@" --file-filter="${label:-$exts} |$f"; fi\n' +
    'exec zenity "$@"',
    "pick", String(title || ""), multiple ? "1" : "", String(exts || ""), String(label || "")]
}

// What to say when the chooser gave nothing (filePicker's exit code): "" for a pick or a cancel.
function filePickerError(code, lang) {
  if (code === 0 || code === 1) return ""
  if (code === 127) return tr(lang, "No file chooser found: update Omarchy or install zenity.", "Nenhum seletor de arquivos encontrado: atualize o Omarchy ou instale o zenity.")
  return tr(lang, "Couldn't open the file chooser.", "Não foi possível abrir o seletor de arquivos.")
}

function guessMime(path) {
  var ext = String(path || "").toLowerCase().split(".").pop()
  return ({ png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", pdf: "application/pdf", txt: "text/plain" })[ext] || "application/octet-stream"
}

function fileIcon(f) {
  var t = String((f && (f.filetype || f.mimetype)) || "").toLowerCase()
  if (t.indexOf("pdf") >= 0) return "󰈦"
  if (t.indexOf("image") >= 0 || ["png", "jpg", "jpeg", "gif", "webp"].indexOf(t) >= 0) return "󰈟"
  if (t.indexOf("video") >= 0 || ["mp4", "mov", "webm"].indexOf(t) >= 0) return "󰈫"
  if (t.indexOf("audio") >= 0 || ["mp3", "m4a", "wav", "ogg"].indexOf(t) >= 0) return "󰈣"
  if (["xls", "xlsx", "csv", "gsheet"].indexOf(t) >= 0) return "󰈛"
  if (["doc", "docx", "gdoc"].indexOf(t) >= 0) return "󰈬"
  if (["ppt", "pptx", "gpres"].indexOf(t) >= 0) return "󰈧"
  if (["zip", "tar", "gz", "rar", "7z"].indexOf(t) >= 0) return "󰗄"
  if (["python", "javascript", "rust", "go", "c", "cpp", "java", "shell", "text", "markdown", "json", "yaml", "html", "css", "snippet"].indexOf(t) >= 0) return "󰈮"
  return "󰈔"
}

// A file played in the message (MediaView): "video", "audio" or "". From
// its type, so messages cached before this knew it play too.
function mediaKind(f) {
  if (!f || f.external === true) return ""
  var mime = String(f.mimetype || "")
  return mime.indexOf("video/") === 0 ? "video" : mime.indexOf("audio/") === 0 ? "audio" : ""
}

// What a file is, for the rail's Files (its icon's color and glyph, the
// types filter): canvas, list, pdf, excel, sheet (Google Sheets), ppt,
// slides (Google Slides), word, gdoc, image, video, audio, zip, code, other.
function fileKind(f) {
  var t = String((f && f.filetype) || "").toLowerCase()
  var pretty = String((f && f.prettyType) || "").toLowerCase()
  var mime = String((f && f.mimetype) || "").toLowerCase()
  if (t === "quip" || t === "canvas" || pretty === "canvas") return "canvas"
  if (t === "list" || pretty === "list") return "list"
  if (t === "pdf" || mime === "application/pdf") return "pdf"
  if (t === "gsheet" || pretty.indexOf("google sheet") === 0) return "sheet"
  if (["xls", "xlsx", "xlsm", "csv", "tsv", "ods"].indexOf(t) >= 0 || mime.indexOf("spreadsheet") >= 0) return "excel"
  if (t === "gpres" || pretty.indexOf("google slide") === 0) return "slides"
  if (["ppt", "pptx", "key", "odp"].indexOf(t) >= 0 || mime.indexOf("presentation") >= 0) return "ppt"
  if (t === "gdoc" || pretty.indexOf("google doc") === 0) return "gdoc"
  if (["doc", "docx", "odt", "rtf"].indexOf(t) >= 0 || mime.indexOf("wordprocessing") >= 0) return "word"
  if (mime.indexOf("image/") === 0 || ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].indexOf(t) >= 0) return "image"
  if (mime.indexOf("video/") === 0 || ["mp4", "mov", "webm", "mkv"].indexOf(t) >= 0) return "video"
  if (mime.indexOf("audio/") === 0 || ["mp3", "m4a", "wav", "ogg", "flac"].indexOf(t) >= 0) return "audio"
  if (["zip", "tar", "gz", "rar", "7z"].indexOf(t) >= 0) return "zip"
  if (["python", "javascript", "rust", "go", "c", "cpp", "java", "shell", "text", "markdown", "json", "yaml", "html", "css", "snippet", "post", "space"].indexOf(t) >= 0) return "code"
  return "other"
}
