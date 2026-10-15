.pragma library
.import "EmojiData.js" as Data
.import "Util.js" as U

// Standard emoji by Slack shortcode, skin tones, Slack's pictures, and the
// search the `:` autocomplete and the reaction picker share. Custom
// workspace emoji are passed in as {name: url} / {name: glyph} maps.

var byName = null   // shortcode -> entry index
var names = []      // entry index -> first shortcode
var glyphIndex = null

var TONES = { "skin-tone-2": 0, "skin-tone-3": 1, "skin-tone-4": 2, "skin-tone-5": 3, "skin-tone-6": 4 }
var FREQUENT = ["+1", "heart", "joy", "tada", "eyes", "white_check_mark", "raised_hands", "pray", "fire", "100", "rocket", "slightly_smiling_face"]
// Slack's one-click reactions out of the box, and what tops up a short
// "Frequently used" (the web client's getFrequentlyUsedEmoji).
var QUICK = ["white_check_mark", "eyes", "raised_hands"]
var FREQUENT_MIN = ["slightly_smiling_face", "heart", "+1", "100", "bug"]

function ensure() {
  if (byName) return
  byName = {}
  glyphIndex = {}
  for (var i = 0; i < Data.list.length; i++) {
    var e = Data.list[i]
    var codes = e[1].split(" ")
    names.push(codes[0])
    for (var j = 0; j < codes.length; j++) if (!(codes[j] in byName)) byName[codes[j]] = i
    glyphIndex[e[0]] = i
    glyphIndex[e[0].replace(/️/g, "")] = i
  }
  // Slack's own names where they differ from gemoji.
  var extra = { "slightly_smiling_face": "slightly_smiling_face", "simple_smile": "slightly_smiling_face", "thumbsup": "+1", "thumbsdown": "-1",
                "white_frowning_face": "frowning_face", "skin-tone-2": null }
  for (var k in extra) if (extra[k] && !(k in byName) && extra[k] in byName) byName[k] = byName[extra[k]]
}

function entry(name) { ensure(); var i = byName[name]; return i === undefined ? null : Data.list[i] }

// A standard emoji glyph from a Slack name, "+1::skin-tone-3" included.
function standard(name) {
  ensure()
  name = String(name || "").replace(/^:|:$/g, "")
  var tone = -1
  var cut = name.indexOf("::")
  if (cut >= 0) {
    var t = name.slice(cut + 2)
    name = name.slice(0, cut)
    if (t in TONES) tone = TONES[t]
  }
  var e = entry(name)
  if (!e) return ""
  if (tone >= 0 && e[4]) return e[4][tone]
  return e[0]
}

function hasTones(name) { var e = entry(String(name).split("::")[0]); return !!(e && e[4]) }

// "1f44d-1f3fd" → glyph (rich_text emoji elements carry it).
function fromHex(hex) {
  var parts = String(hex || "").split("-")
  var cps = []
  for (var i = 0; i < parts.length; i++) {
    var n = parseInt(parts[i], 16)
    if (!isFinite(n) || n <= 0) return ""
    cps.push(n)
  }
  try { return String.fromCodePoint.apply(null, cps) } catch (e) { return "" }
}

// Slack's file names pad code points to four digits (00a9-fe0f).
function hex(glyph) {
  return U.codePoints(glyph).map(function(c) { var h = c.toString(16); return h.length < 4 ? ("000" + h).slice(-4) : h }).join("-")
}

// Slack's picture of a standard emoji (Apple set), as the official app draws it.
function imageUrl(glyph) {
  return "https://a.slack-edge.com/production-standard-emoji-assets/15.0/apple-large/" + hex(glyph) + ".png"
}

function shortcodeOf(glyph) {
  ensure()
  var i = glyphIndex[glyph]
  if (i === undefined) i = glyphIndex[String(glyph).replace(/️/g, "")]
  return i === undefined ? "" : names[i]
}

// What to draw for `:name:` — {glyph} or {url} or null. `custom` maps
// name → image url, `aliases` name → glyph (custom aliases of standard ones).
function resolve(name, custom, aliases) {
  name = String(name || "").replace(/^:|:$/g, "")
  var g = standard(name)
  if (g) return { glyph: g }
  var base = name.split("::")[0]
  if (aliases && aliases[base]) return { glyph: aliases[base] }
  if (custom && custom[base]) return { url: custom[base] }
  return null
}

// Replaces :shortcodes: (and :name::skin-tone-N:) in plain text with glyphs;
// custom ones are handed to `onCustom(name, url)` for the caller to draw.
function shortcodes(text, custom, aliases, onCustom) {
  return String(text || "").replace(/:([A-Za-z0-9_+'\-]+):(?::(skin-tone-[2-6]):)?/g, function(all, name, tone) {
    var r = resolve(tone ? name + "::" + tone : name, custom, aliases)
    if (!r) return all
    if (r.glyph) return r.glyph
    return onCustom ? onCustom(name, r.url) : all
  })
}

// Up to `max` matches for the `:` autocomplete and the picker's search:
// [{name, glyph|url}], prefix matches and frequent ones first.
function search(query, custom, aliases, max) {
  ensure()
  var q = String(query || "").toLowerCase().replace(/^:|:$/g, "")
  var out = []
  var seen = {}
  function consider(name, item, words) {
    if (seen[name]) return
    var at = name.indexOf(q)
    var inWords = at < 0 && words && words.indexOf(q) >= 0
    if (at < 0 && !inWords) return
    seen[name] = true
    item.name = name
    item.prefix = at === 0
    item.freq = FREQUENT.indexOf(name)
    out.push(item)
  }
  for (var i = 0; i < Data.list.length; i++) {
    var e = Data.list[i]
    var codes = e[1].split(" ")
    var best = null
    for (var j = 0; j < codes.length; j++) {
      if (codes[j].indexOf(q) === 0) { best = codes[j]; break }
      if (best === null && codes[j].indexOf(q) >= 0) best = codes[j]
    }
    if (best === null && q.length >= 3 && e[3].indexOf(q) >= 0) best = codes[0]
    if (best !== null) consider(best, { glyph: e[0], tones: !!e[4] }, e[3])
  }
  for (var n in (custom || {})) consider(n, { url: custom[n] }, "")
  for (var a in (aliases || {})) consider(a, { glyph: aliases[a] }, "")
  out.sort(function(x, y) {
    if (x.prefix !== y.prefix) return x.prefix ? -1 : 1
    var fx = x.freq < 0 ? 999 : x.freq, fy = y.freq < 0 ? 999 : y.freq
    if (fx !== fy) return fx - fy
    if (x.name.length !== y.name.length) return x.name.length - y.name.length
    return x.name < y.name ? -1 : 1
  })
  return out.slice(0, max || 8)
}

// ------------------------------------------------------- frequently used
// A pref Slack keeps as JSON, as an object ({} when it isn't one).
function jsonPref(v) {
  if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { return {} } }
  return v && typeof v === "object" ? v : {}
}

// A list of emoji names in a pref: an array, its JSON, or "a,b,c".
function nameList(v) {
  if (typeof v === "string") {
    var s = v.trim()
    if (s.charAt(0) === "[") { try { v = JSON.parse(s) } catch (e) { v = [] } } else v = s.split(",")
  }
  return (Array.isArray(v) ? v : []).map(function(n) { return String(n || "").trim().replace(/^:|:$/g, "") }).filter(function(n) { return n })
}

// The one name Slack counts an emoji under ("thumbsup" → "+1", a custom
// alias of a standard one → that one), "" for one we can't draw.
function canonical(name, custom, aliases) {
  name = String(name || "").replace(/^:|:$/g, "").split("::")[0]
  var g = standard(name)
  if (g) return shortcodeOf(g) || name
  if (aliases && aliases[name]) return shortcodeOf(aliases[name]) || name
  return custom && custom[name] ? name : ""
}

// A `frecency` emoji id: "E" + code points ("E1f44d", skin tones dropped)
// or "E" + a custom emoji's name.
function frecencyName(id, custom, aliases) {
  var key = String(id).slice(1)
  var hexKey = key.toLowerCase().replace(/-1f3f[b-f]/g, "")
  if (/^[0-9a-f]{2,6}(-[0-9a-f]{2,6})*$/.test(hexKey)) {
    var n = shortcodeOf(fromHex(hexKey))
    if (n) return n
  }
  return canonical(key, custom, aliases)
}

// Slack's frecency (the web client's calculateScore): the visits weighed by
// age, averaged, times the count; halved once Slack trimmed the entry.
var VISIT_WEIGHTS = [[144e5, 100], [864e5, 80], [2592e5, 60], [6048e5, 40], [2592e6, 20], [7776e6, 10]]
function visitScore(it, now) {
  if (!it || !it.visits || !it.visits.length) return 0
  var w = 0
  for (var i = 0; i < it.visits.length; i++) {
    var age = now - it.visits[i]
    for (var j = 0; j < VISIT_WEIGHTS.length; j++) if (age < VISIT_WEIGHTS[j][0]) { w += VISIT_WEIGHTS[j][1]; break }
  }
  if (it._reduced) w *= 0.5
  return w / it.visits.length * (Number(it.count) || 0)
}

// The emoji in Slack's `frecency` pref ({key: item | [item]}, an item
// {id, count, visits: [ms]}; emoji ids start with "E"), scored as its
// "Frequently used" search does: the best hit plus the item itself,
// fading by 0.9755 a day since the last visit. id → score.
function frecencyScores(cache, now) {
  cache = jsonPref(cache)
  now = now || Date.now()
  var best = {}, last = {}, out = {}
  function consider(it) {
    if (!it || typeof it.id !== "string" || it.id.charAt(0) !== "E") return
    var s = visitScore(it, now)
    if (!(it.id in best) || s > best[it.id]) best[it.id] = s
    var v = it.visits || []
    for (var i = 0; i < v.length; i++) if (v[i] > (last[it.id] || 0)) last[it.id] = v[i]
  }
  for (var k in cache) {
    var e = cache[k]
    if (Array.isArray(e)) e.forEach(consider)
    else consider(e)
  }
  for (var id in best) {
    var own = cache[id] && !Array.isArray(cache[id]) && cache[id].id === id ? visitScore(cache[id], now) : 0
    var score = (best[id] + own) * Math.pow(0.9755, Math.floor((now - (last[id] || now)) / 864e5))
    if (score > 0) out[id] = score
  }
  return out
}

// The user's frequently used emoji, most first, as Slack ranks them: by
// frecency (Slack's, plus `local`: name → {count, visits} used here), then
// the `emoji_use` counts (name → times), then Slack's five to make five.
function frequentlyUsed(scores, use, local, custom, aliases, max) {
  ensure()
  var now = Date.now()
  var score = {}
  for (var id in (scores || {})) {
    var n = frecencyName(id, custom, aliases)
    if (n) score[n] = Math.max(score[n] || 0, scores[id])
  }
  for (var l in (local || {})) {
    var ln = canonical(l, custom, aliases)
    var ls = ln ? 2 * visitScore(local[l], now) : 0
    if (ls > 0) score[ln] = (score[ln] || 0) + ls
  }
  var out = Object.keys(score).sort(function(a, b) { return score[b] - score[a] || (a < b ? -1 : 1) })
  var counts = {}
  for (var u in (use || {})) {
    var un = canonical(u, custom, aliases)
    if (un) counts[un] = (counts[un] || 0) + (Number(use[u]) || 0)
  }
  Object.keys(counts).sort(function(a, b) { return counts[b] - counts[a] || (a < b ? -1 : 1) }).forEach(function(n2) {
    if (out.indexOf(n2) < 0) out.push(n2)
  })
  for (var i = 0; out.length < 5 && i < FREQUENT_MIN.length; i++) if (out.indexOf(FREQUENT_MIN[i]) < 0) out.push(FREQUENT_MIN[i])
  return out.slice(0, max || 36)
}

// `name` in skin tone 2–6 when it has tones ("+1" → "+1::skin-tone-3").
function withTone(name, tone) {
  var base = String(name || "").split("::")[0]
  return tone >= 2 && tone <= 6 && hasTones(base) ? base + "::skin-tone-" + tone : base
}

// The picker's catalogue: [{key, label, items:[{name, glyph|url, tones}]}].
function catalogue(custom, lang) {
  ensure()
  var labels = {
    smileys: ["Smileys & People", "Smileys e pessoas"], people: ["People & Body", "Pessoas e corpo"],
    nature: ["Animals & Nature", "Animais e natureza"], food: ["Food & Drink", "Comidas e bebidas"],
    travel: ["Travel & Places", "Viagens e lugares"], activities: ["Activities", "Atividades"],
    objects: ["Objects", "Objetos"], symbols: ["Symbols", "Símbolos"], flags: ["Flags", "Bandeiras"]
  }
  var groups = Data.groups.map(function(g) {
    return { key: g, label: labels[g][lang === "pt-BR" ? 1 : 0], icon: GROUP_ICONS[g], items: [] }
  })
  for (var i = 0; i < Data.list.length; i++) {
    var e = Data.list[i]
    groups[e[2]].items.push({ name: e[1].split(" ")[0], glyph: e[0], tones: !!e[4] })
  }
  var out = []
  var customItems = []
  for (var n in (custom || {})) customItems.push({ name: n, url: custom[n] })
  customItems.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
  out.push({ key: "frequent", label: lang === "pt-BR" ? "Usados com frequência" : "Frequently used", icon: "󰄉",
             items: FREQUENT.map(function(n) { return { name: n, glyph: standard(n), tones: hasTones(n) } }) })
  for (var g = 0; g < groups.length; g++) out.push(groups[g])
  if (customItems.length) out.push({ key: "custom", label: lang === "pt-BR" ? "Personalizados" : "Custom", icon: "󰏘", items: customItems })
  return out
}

var GROUP_ICONS = { smileys: "󰞅", people: "󰀉", nature: "󰩃", food: "󰉚", travel: "󰄋", activities: "󰒸", objects: "󰌵", symbols: "󰘧", flags: "󰈻" }

// A message made only of emoji (≤ 23) is drawn large, like Slack's jumbomoji.
function onlyEmoji(text, custom, aliases) {
  var s = String(text || "").trim()
  if (!s || s.length > 400) return false
  var count = 0
  var rest = s.replace(/:([A-Za-z0-9_+'\-]+):(?::skin-tone-[2-6]:)?/g, function(all, name) {
    if (resolve(name, custom, aliases)) { count++; return "" }
    return all
  })
  var cps = U.codePoints(rest.replace(/\s+/g, ""))
  for (var i = 0; i < cps.length; i++) {
    var c = cps[i]
    if (c === 0xfe0f || c === 0x200d || (c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0020 && c <= 0xe007f)) continue
    if (c >= 0x1f000 || (c >= 0x2600 && c <= 0x27bf) || (c >= 0x2190 && c <= 0x21ff) || (c >= 0x2b00 && c <= 0x2bff) || c === 0x3030 || c === 0x303d || c === 0xa9 || c === 0xae || (c >= 0x2300 && c <= 0x23ff)) { count++; continue }
    return false
  }
  return count > 0 && count <= 23
}

// The canonical glyph of an emoji sequence we know ("❤" → "❤️"), or "".
function known(seq) {
  ensure()
  var i = glyphIndex[seq]
  if (i === undefined) i = glyphIndex[String(seq).replace(/️/g, "")]
  if (i !== undefined) return Data.list[i][0]
  // Skin-toned variants live in the entries' tone lists.
  var base = String(seq).replace(/\uD83C[\uDFFB-\uDFFF]/g, "")
  var j = glyphIndex[base]
  if (j === undefined) j = glyphIndex[base.replace(/️/g, "")]
  if (j !== undefined && Data.list[j][4]) {
    var tones = Data.list[j][4]
    for (var k = 0; k < tones.length; k++) if (tones[k] === seq || tones[k].replace(/️/g, "") === String(seq).replace(/️/g, "")) return tones[k]
  }
  return ""
}

function emojiStart(cp) {
  return (cp >= 0x1f000 && cp <= 0x1faff) || (cp >= 0x2600 && cp <= 0x27bf) || (cp >= 0x2300 && cp <= 0x23ff) ||
         (cp >= 0x2b00 && cp <= 0x2bff) || (cp >= 0x2190 && cp <= 0x21ff) || cp === 0x3030 || cp === 0x303d ||
         cp === 0x3297 || cp === 0x3299 || cp === 0xa9 || cp === 0xae || cp === 0x203c || cp === 0x2049 ||
         cp === 0x2122 || cp === 0x2139 || cp === 0x24c2 || (cp >= 0x25aa && cp <= 0x25fe) || (cp >= 0x2934 && cp <= 0x2935)
}

// Text split into [plain, emoji, plain, …] runs, emoji being sequences we
// know (so Slack's pictures can stand in for them).
function split(text) {
  var s = String(text || "")
  var out = []
  var buf = ""
  var i = 0
  while (i < s.length) {
    var cp = s.codePointAt(i)
    var len = cp > 0xffff ? 2 : 1
    var keycap = (cp === 0x23 || cp === 0x2a || (cp >= 0x30 && cp <= 0x39)) && s.charCodeAt(i + 1) === 0xfe0f && s.charCodeAt(i + 2) === 0x20e3
    if (!emojiStart(cp) && !keycap) { buf += s.substr(i, len); i += len; continue }
    var j = i + len
    for (;;) {
      if (j >= s.length) break
      var c = s.codePointAt(j)
      if (c === 0xfe0f || c === 0x20e3 || (c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0020 && c <= 0xe007f)) { j += c > 0xffff ? 2 : 1; continue }
      if (c === 0x200d && j + 1 < s.length) { var n = s.codePointAt(j + 1); j += 1 + (n > 0xffff ? 2 : 1); continue }
      if (cp >= 0x1f1e6 && cp <= 0x1f1ff && c >= 0x1f1e6 && c <= 0x1f1ff && j === i + 2) { j += 2; continue }
      break
    }
    var seq = s.slice(i, j)
    var g = known(seq)
    if (g) {
      if (buf) { out.push([false, buf]); buf = "" }
      out.push([true, g])
    } else buf += seq
    i = j
  }
  if (buf) out.push([false, buf])
  return out
}
