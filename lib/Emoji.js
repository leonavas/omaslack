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
