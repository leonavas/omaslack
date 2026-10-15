.pragma library
.import "Util.js" as U

// Slack's JSON → the store's shapes, and the derived lists the views draw:
// sidebar rows, the message list with its headers, day dividers, the New
// line and folded joins.

// ------------------------------------------------------------------ users

function str(v) { return typeof v === "string" ? v : "" }

function parseUser(u, old) {
  var p = u.profile || {}
  var o = old ? U.copy(old) : {}
  o.id = u.id
  var name = [p.display_name, p.real_name, u.name].filter(function(x) { return typeof x === "string" && x.length > 0 })[0]
  if (name) o.name = name
  else if (!o.name) o.name = "?"
  if (u.name) o.handle = u.name
  if (p.real_name) o.real = p.real_name
  if (typeof p.display_name === "string") o.display = p.display_name
  o.bot = u.is_bot === true || u.id === "USLACKBOT"
  // A bot user: its app, for the "App" panel (bots.info, apps.profile.get).
  if (typeof p.bot_id === "string" && p.bot_id) o.botId = p.bot_id
  if (typeof p.api_app_id === "string" && p.api_app_id) o.appId = p.api_app_id
  if (typeof u.deleted === "boolean") o.deleted = u.deleted
  if (p.image_72) o.avatar = p.image_72
  if (p.image_192) o.avatar192 = p.image_192
  if (p.image_512 || p.image_192) o.avatar512 = p.image_512 || p.image_192
  if (p.image_original || p.image_1024) o.photo = p.image_original || p.image_1024
  if (typeof p.title === "string") o.title = p.title
  if (typeof p.email === "string") o.email = p.email
  if (typeof p.phone === "string") o.phone = p.phone
  if (typeof u.tz_offset === "number") o.tzOffset = u.tz_offset
  if (u.tz_label || u.tz) o.tzLabel = u.tz_label || u.tz
  if (typeof u.is_restricted === "boolean") o.guest = u.is_restricted || u.is_ultra_restricted === true
  if (typeof u.is_admin === "boolean") o.admin = u.is_admin
  if (typeof p.status_emoji === "string" || typeof p.status_text === "string") {
    o.statusEmoji = str(p.status_emoji)
    o.statusText = str(p.status_text)
    o.statusExp = p.status_expiration || 0
    var info = (p.status_emoji_display_info || [])[0] || {}
    o.statusUnicode = info.unicode || ""
    o.statusUrl = !info.unicode && typeof info.display_url === "string" && info.display_url.indexOf("http") === 0 ? info.display_url : ""
  }
  return o
}

// {emoji, text} of a status still in force, or null.
function status(u) {
  if (!u) return null
  if (!u.statusEmoji && !u.statusText) return null
  if (u.statusExp && u.statusExp * 1000 <= Date.now()) return null
  return { emoji: u.statusEmoji || "", text: u.statusText || "", unicode: u.statusUnicode || "", url: u.statusUrl || "", exp: u.statusExp || 0 }
}

// ------------------------------------------------------------------ convs

function convKind(c) {
  if (c.is_im) return "im"
  if (c.is_mpim) return "mpim"
  if (c.is_private || c.is_group) return "private"
  return "channel"
}

function parseConv(c, old) {
  var o = old ? U.copy(old) : {}
  o.id = c.id
  if (c.is_im !== undefined || c.is_mpim !== undefined || c.is_private !== undefined || c.is_channel !== undefined || !o.kind) o.kind = convKind(c)
  if (typeof c.name === "string") o.name = c.name
  if (c.user) o.user = c.user
  if (typeof c.is_ext_shared === "boolean") o.ext = c.is_ext_shared
  if (typeof c.is_archived === "boolean") o.archived = c.is_archived
  if (typeof c.is_general === "boolean") o.general = c.is_general
  if (typeof c.is_member === "boolean") o.member = c.is_member
  else if (o.member === undefined) o.member = true
  if (c.topic) o.topic = str(c.topic.value)
  if (c.purpose) o.purpose = str(c.purpose.value)
  if (c.created) o.created = c.created
  if (c.creator) o.creator = c.creator
  if (typeof c.num_members === "number") o.numMembers = c.num_members
  o.updated = c.updated > 0 ? c.updated : (c.created ? c.created * 1000 : (o.updated || 0))
  if (typeof c.is_user_deleted === "boolean") o.userDeleted = c.is_user_deleted
  // Slack's flag for a channel quiet for 30 days: "Active only" hides it.
  if (c.properties && typeof c.properties === "object") o.dormant = c.properties.is_dormant === true
  return o
}

function isDm(c) { return c && (c.kind === "im" || c.kind === "mpim") }

// A channel's own preference muted, or set to mentions only (or nothing):
// it waits quietly, out of the badges and the bar's rows. Only its own
// level counts: one that follows the global level
// still notifies, whatever that level is.
function quietPref(p) {
  return !!p && (p.muted === true || ["mentions", "mentions_dms", "nothing"].indexOf(p.desktop || "") >= 0)
}

// mpdm-ana--bruno.silva--me-1 → ["ana", "bruno.silva", "me"]
function mpimHandles(name) {
  return String(name || "").replace(/^mpdm-/, "").replace(/-\d+$/, "").split("--").filter(function(x) { return x })
}

// What the sidebar calls a conversation.
function label(c, users, meId, handles, lang) {
  if (!c) return ""
  if (c.kind === "im") {
    var u = users[c.user]
    var n = u ? u.name : (c.user || "?")
    return c.user === meId ? n + (lang === "pt-BR" ? " (você)" : " (you)") : n
  }
  if (c.kind === "mpim") {
    var me = users[meId]
    var mine = me ? me.handle : ""
    var names = mpimHandles(c.name).filter(function(h) { return h !== mine }).map(function(h) {
      var id = handles[h]
      return id && users[id] ? users[id].name : h
    })
    return mpimLabel(names)
  }
  return c.name || c.id
}

// A group DM's name as Slack writes it (getMpimDisplayNameAlphabetical):
// the others' names in alphabetical order, comma-separated.
function mpimLabel(names) {
  return names.filter(function(n) { return n }).sort(function(a, b) { return String(a).localeCompare(String(b)) }).join(", ")
}

function mpimMembers(c, users, meId, handles) {
  var me = users[meId]
  var mine = me ? me.handle : ""
  return mpimHandles(c.name).filter(function(h) { return h !== mine }).map(function(h) { return handles[h] || "" }).filter(function(x) { return x })
}

// ------------------------------------------------------------------ messages

function parseFile(f) {
  var isImage = String(f.mimetype || "").indexOf("image/") === 0
  var keys = ["thumb_720", "thumb_480", "thumb_360"]
  var thumb = null, w = 0, h = 0
  if (isImage) {
    for (var i = 0; i < keys.length; i++) if (typeof f[keys[i]] === "string") { thumb = f[keys[i]]; w = f[keys[i] + "_w"] || 0; h = f[keys[i] + "_h"] || 0; break }
    if (!thumb && f.url_private) thumb = f.url_private
  }
  if (!w) { w = f.original_w || 0; h = f.original_h || 0 }
  return {
    id: f.id || "", name: f.name || f.title || "file", title: f.title || "", thumb: thumb, w: w, h: h,
    full: f.url_private || "", permalink: f.permalink || "",
    download: f.is_external === true ? "" : (f.url_private_download || f.url_private || ""),
    size: f.size || 0, filetype: f.filetype || "", prettyType: f.pretty_type || "", mimetype: f.mimetype || "",
    external: f.is_external === true, image: isImage, mode: f.mode || "",
    preview: typeof f.preview === "string" ? f.preview : ""
  }
}

// A file as the rail's Files lists it (files.list, stars.list): parseFile's
// plus who made it, when, when it changed and when you last looked (Slack
// only says so for some, canvases mostly), and a canvas's reading time.
// Times in seconds (some come in milliseconds).
function parseListedFile(f) {
  function secs(v) { var n = Number(v) || 0; return n > 1e12 ? Math.floor(n / 1000) : n }
  var o = parseFile(f)
  o.user = f.user || ""
  o.created = secs(f.created || f.timestamp)
  o.updated = secs(f.updated || f.edit_timestamp) || o.created
  o.viewed = secs(f.last_read || f.last_viewed)
  o.readtime = Number(f.canvas_readtime) || 0
  o.externalUrl = f.is_external === true ? str(f.external_url) || str(f.url_private) : ""
  o.kind = U.fileKind(o)
  return o
}

function parseMessage(m) {
  var botName = ""
  if (m.user_profile && m.user_profile.display_name && !m.user) botName = m.user_profile.display_name
  else if (m.username) botName = m.username
  else if (m.bot_profile && m.bot_profile.name) botName = m.bot_profile.name
  // The picture the message set (icon_url, icon_emoji), else its app's.
  var botIcon = iconOf(m.icons)
  var botEmoji = !botIcon && m.icons && typeof m.icons.emoji === "string" ? m.icons.emoji.replace(/^:|:$/g, "") : ""
  if (!botIcon && !botEmoji && m.bot_profile) botIcon = iconOf(m.bot_profile.icons)
  var out = {
    ts: str(m.ts),
    user: m.user || "",
    botName: botName,
    botIcon: botIcon,
    botEmoji: botEmoji,
    botId: m.bot_id || "",
    appId: m.app_id || (m.bot_profile && m.bot_profile.app_id) || "",
    subtype: m.subtype || "",
    text: str(m.text),
    blocks: Array.isArray(m.blocks) ? m.blocks : [],
    attachments: Array.isArray(m.attachments) ? m.attachments : [],
    files: (m.files || []).filter(function(f) { return f && f.mode !== "tombstone" }).map(parseFile),
    replyCount: m.reply_count || 0,
    threadTs: m.thread_ts || "",
    latestReply: m.latest_reply || "",
    replyUsers: m.reply_users || [],
    replyUsersCount: m.reply_users_count || 0,
    reactions: (m.reactions || []).map(function(r) { return { name: r.name, users: r.users || [], count: r.count || (r.users || []).length } }),
    edited: m.edited ? { user: m.edited.user || "", ts: m.edited.ts || "" } : null,
    pinnedTo: m.pinned_to || [],
    subscribed: m.subscribed === true,
    lastRead: m.last_read || "",
    topic: m.topic, purpose: m.purpose, name: m.name, old_name: m.old_name, inviter: m.inviter,
    ephemeral: m.is_ephemeral === true,
    hidden: m.hidden === true
  }
  // A thread's parent deleted under its replies: Slack's tombstone, Slackbot's
  // hidden "This message was deleted.", at times without the subtype.
  if (m.subtype === "tombstone" || (out.hidden && out.user === "USLACKBOT" && (out.replyCount > 0 || out.threadTs === out.ts) && out.text === "This message was deleted.")) {
    out.tombstone = true
    out.subtype = "tombstone"
  }
  return out
}

// The same message deleted under its replies, as Slack keeps it (a
// tombstone): its thread and reactions stay, the rest goes.
function tombstone(m) {
  return patch(m, { tombstone: true, subtype: "tombstone", hidden: true, user: "USLACKBOT", botName: "", botIcon: "", botEmoji: "", botId: "", appId: "",
                    text: "This message was deleted.", blocks: [], attachments: [], files: [], edited: null, pinnedTo: [] })
}

// The same message with some fields changed (messages are never mutated:
// the list views diff by identity).
function patch(m, fields) {
  var o = U.copy(m)
  for (var k in fields) o[k] = fields[k]
  return o
}

function isMine(m, me) {
  return m.user === me && ["", "thread_broadcast", "file_share", "me_message"].indexOf(m.subtype || "") >= 0
}

// Who heads a group: an app's messages part where the name they post
// with changes, even through the same bot user.
function authorKey(m) { return m.user && !m.botId ? m.user : (m.user || "") + "bot:" + (m.botName || m.botId) }

// ------------------------------------------------------------------ apps

// An `icons` object's picture (a message's, bot_profile's, bots.info's,
// apps.profile.get's): the first of `sizes` it has, 72px and near by default.
function iconOf(icons, sizes) {
  if (!icons) return ""
  var keys = sizes || ["image_72", "image_64", "image_48", "image_36", "image_32", "image_102", "image_128", "image_192"]
  for (var i = 0; i < keys.length; i++) {
    var u = icons[keys[i]]
    if (typeof u === "string" && u.indexOf("http") === 0) return u
  }
  return ""
}

// Who a message (or a search hit) shows as. A person by their profile; an
// app (no user, or a bot user) by the name and picture the message set
// (username, icons), else its bot_profile's, else its bot user's, else what
// bots.info said (`known`: {name, icon, user}). {name, icon, emoji, app,
// profile, ask}: `profile` is what a click opens (a user id, or "bot:B…"
// for an app whose bot user isn't known), `ask` a bot id bots.info would
// name or picture.
function author(m, users, known) {
  var u = m.user ? (users[m.user] || null) : null
  var app = !m.user || (!!u && !!u.bot && m.user !== "USLACKBOT")
  if (!app) return { name: u ? u.name : (m.botName || ""), icon: "", emoji: "", app: false, profile: m.user, ask: "" }
  var k = known || {}
  var name = m.botName || (u ? u.name : "") || k.name || ""
  var icon = m.botIcon || (m.botEmoji ? "" : ((u && u.avatar) || k.icon || ""))
  var ask = !u && m.botId && (!m.botName || (!m.botIcon && !m.botEmoji)) ? m.botId : ""
  var profile = u ? m.user : (k.user || (m.botId ? "bot:" + m.botId : ""))
  return { name: name || "bot", icon: icon, emoji: icon ? "" : (m.botEmoji || ""), app: true, profile: profile, ask: ask }
}

// Inserts by ts into a sorted array (new array); replaces an equal ts.
function upsert(list, m) {
  var out = list.slice()
  var lo = 0, hi = out.length
  while (lo < hi) {
    var mid = (lo + hi) >> 1
    if (U.cmpTs(out[mid].ts, m.ts) < 0) lo = mid + 1
    else hi = mid
  }
  if (lo < out.length && out[lo].ts === m.ts) out[lo] = m
  else out.splice(lo, 0, m)
  return out
}

function indexOfTs(list, ts) {
  for (var i = list.length - 1; i >= 0; i--) if (list[i].ts === ts) return i
  return -1
}

// A fetched page merged into what is loaded: the span the page covers is
// replaced by it (messages gone from it were deleted), older history kept,
// newer local sends kept, ephemeral messages kept.
function mergePage(loaded, page, isNewest) {
  if (!loaded || loaded.length === 0) return page.slice()
  if (page.length === 0) return isNewest ? loaded.filter(function(m) { return m.ephemeral || m.pending }) : loaded
  var first = page[0].ts, last = page[page.length - 1].ts
  var out = []
  var i
  for (i = 0; i < loaded.length && U.cmpTs(loaded[i].ts, first) < 0; i++) out.push(loaded[i])
  var keep = []
  for (; i < loaded.length; i++) {
    var m = loaded[i]
    if (U.cmpTs(m.ts, last) > 0) { if (!isNewest || m.pending || m.ephemeral || m.local) keep.push(m) ; continue }
    if (m.ephemeral) keep.push(m)
  }
  // Reuse loaded objects that did not change, so views keep their items.
  var byTs = {}
  for (var j = 0; j < loaded.length; j++) byTs[loaded[j].ts] = loaded[j]
  for (var k = 0; k < page.length; k++) {
    var p = page[k], old = byTs[p.ts]
    out.push(old && same(old, p) ? old : p)
  }
  for (var n = 0; n < keep.length; n++) {
    var kk = keep[n]
    if (!out.some(function(x) { return x.ts === kk.ts })) out = upsert(out, kk)
  }
  return out
}

function same(a, b) {
  if (a === b) return true
  return a.text === b.text && a.replyCount === b.replyCount && a.latestReply === b.latestReply &&
    JSON.stringify(a.reactions) === JSON.stringify(b.reactions) && JSON.stringify(a.edited) === JSON.stringify(b.edited) &&
    JSON.stringify(a.pinnedTo) === JSON.stringify(b.pinnedTo) && a.subscribed === b.subscribed &&
    a.files.length === b.files.length && JSON.stringify(a.blocks) === JSON.stringify(b.blocks) && a.subtype === b.subtype &&
    JSON.stringify(a.replyUsers) === JSON.stringify(b.replyUsers) && JSON.stringify(a.attachments) === JSON.stringify(b.attachments)
}

// ------------------------------------------------------------------ list rows

// The conversation's messages as rows: who heads a group, day dividers,
// the New line, runs of joins and leaves folded into one line. `cache`
// (a Map) keeps row objects stable across rebuilds.
function messageRows(msgs, opts, cache) {
  var rows = []
  var prev = null
  var newDone = false
  var lastDay = ""
  var i = 0
  while (i < msgs.length) {
    var m = msgs[i]
    var d = U.tsDate(m.ts)
    var dayKey = d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
    var day = dayKey !== lastDay && !opts.noDays ? dayKey : ""
    lastDay = dayKey
    var memb = membershipOf(m)
    if (memb) {
      var run = [m]
      var j = i + 1
      while (j < msgs.length && membershipOf(msgs[j])) {
        var dj = U.tsDate(msgs[j].ts)
        if (dj.getFullYear() + "-" + dj.getMonth() + "-" + dj.getDate() !== dayKey) break
        run.push(msgs[j]); j++
      }
      var isNew = false
      if (!newDone && opts.newTs && run.some(function(x) { return U.cmpTs(x.ts, opts.newTs) >= 0 })) { isNew = true; newDone = true }
      rows.push(row(cache, { key: "run:" + m.ts, kind: "members", msg: m, run: run, header: true, day: day ? d : null, isNew: isNew }))
      prev = null
      i = j
      continue
    }
    var newHere = !newDone && opts.newTs && U.cmpTs(m.ts, opts.newTs) >= 0
    if (newHere) newDone = true
    var pinned = opts.conv && m.pinnedTo && m.pinnedTo.indexOf(opts.conv) >= 0
    // A tombstone heads itself and nothing after it.
    var grouped = prev && !day && !newHere && !pinned && !m.tombstone && !prev.tombstone && authorKey(prev) === authorKey(m) &&
      (U.tsNum(m.ts) - U.tsNum(prev.ts) < 300) && !prev.ephemeral && !m.ephemeral &&
      m.subtype !== "thread_broadcast" && prev.subtype !== "thread_broadcast" && !(m.subtype && membershipOf(prev))
    rows.push(row(cache, { key: m.ts, kind: "msg", msg: m, header: !grouped, day: day ? d : null, isNew: !!newHere, pinned: !!pinned }))
    prev = m
    i++
  }
  return rows
}

function row(cache, r) {
  if (!cache) return r
  var old = cache.get(r.key)
  if (old && old.msg === r.msg && old.header === r.header && !!old.day === !!r.day && old.isNew === r.isNew &&
      old.pinned === r.pinned && (r.kind !== "members" || (old.run.length === r.run.length && old.run.every(function(x, k) { return x === r.run[k] })))) return old
  cache.set(r.key, r)
  return r
}

function membershipOf(m) {
  var st = m && m.subtype
  if (st === "channel_join" || st === "group_join") return "join"
  if (st === "channel_leave" || st === "group_leave") return "leave"
  return ""
}

// The folded line for a run of joins/leaves:
// [{text, user?}] segments, names as links.
function membershipSentence(run, ctx) {
  var lang = ctx.lang
  var tr = function(en, pt) { return lang === "pt-BR" ? pt : en }
  var people = [], byUser = {}
  run.forEach(function(m) {
    var a = membershipOf(m)
    var p = byUser[m.user]
    if (!p) { p = byUser[m.user] = { user: m.user, first: a, last: a, by: "" }; people.push(p) }
    p.last = a
    if (a === "join" && m.inviter && m.inviter !== m.user) p.by = m.inviter
  })
  var cats = { joined: [], left: [], rejoined: [] }
  var order = []
  people.forEach(function(p) {
    var c = p.last === "leave" ? "left" : (p.first === "leave" ? "rejoined" : "joined")
    if (cats[c].length === 0) order.push(c)
    cats[c].push(p)
  })
  var main = order[0]
  order.forEach(function(c) { if (cats[c].length > cats[main].length) main = c })
  var chan = ctx.chanName ? (ctx.chanPrivate ? "🔒" : "#") + ctx.chanName : ""
  function who(list) {
    var segs = [{ user: list[0].user }]
    if (list.length === 2) segs.push({ text: tr(" and ", " e ") }, { user: list[1].user })
    else if (list.length > 2) segs.push({ text: lang === "pt-BR" ? " e mais " + (list.length - 1) + " pessoas" : " and " + (list.length - 1) + " others" })
    return segs
  }
  var plural = function(list) { return list.length > 1 }
  var segs = who(cats[main])
  var list = cats[main]
  var inviter = list.every(function(p) { return p.by && p.by === list[0].by }) ? list[0].by : ""
  if (main === "joined" && inviter) {
    if (lang === "pt-BR") segs.push({ text: (plural(list) ? " entraram em " : " entrou em ") + (chan || "o canal") + " a convite de " }, { user: inviter, at: true }, { text: "." })
    else segs.push({ text: (plural(list) ? " were added to " : " was added to ") + (chan || "the channel") + " by " }, { user: inviter, at: true }, { text: "." })
  } else {
    var verbs = lang === "pt-BR"
      ? { joined: [chan ? "entrou em " : "entrou no canal", chan ? "entraram em " : "entraram no canal"], left: [chan ? "saiu de " : "saiu do canal", chan ? "saíram de " : "saíram do canal"], rejoined: [chan ? "voltou para " : "voltou para o canal", chan ? "voltaram para " : "voltaram para o canal"] }
      : { joined: [chan ? "joined " : "joined the channel", chan ? "joined " : "joined the channel"], left: [chan ? "left " : "left the channel", chan ? "left " : "left the channel"], rejoined: [chan ? "rejoined " : "rejoined the channel", chan ? "rejoined " : "rejoined the channel"] }
    segs.push({ text: " " + verbs[main][plural(list) ? 1 : 0] + (chan ? chan : "") + "." })
  }
  var others = order.filter(function(c) { return c !== main })
  others.forEach(function(c, k) {
    segs.push({ text: k === 0 ? tr(" Also, ", " Além disso, ") : tr(" and ", " e ") })
    segs = segs.concat(who(cats[c]))
    var v = lang === "pt-BR"
      ? { joined: ["entrou", "entraram"], left: ["saiu", "saíram"], rejoined: ["voltou", "voltaram"] }
      : { joined: ["joined", "joined"], left: ["left", "left"], rejoined: ["rejoined", "rejoined"] }
    segs.push({ text: " " + v[c][plural(cats[c]) ? 1 : 0] })
  })
  if (others.length) segs.push({ text: "." })
  return segs
}

// ------------------------------------------------------------------ sidebar

// Sidebar rows from the store's state. Every conversation lives in one
// section; muted channels gather in "Silenced" at the end.
function sidebar(s) {
  var tr = function(en, pt) { return s.lang === "pt-BR" ? pt : en }
  var convs = s.convs, users = s.users, counts = s.counts
  var placed = {}
  var sections = []
  var eligible = function(c) {
    if (!c || c.archived || c.guest || c.member === false) return false
    if (c.kind === "im") {
      // Slack's own bots: search's and channel expert's DMs never show;
      // Slackbot's leaves when the new Slackbot has its sidebar link.
      if (c.user === "USEARCH" || c.user === "UCHANNELEXPERT") return false
      if (c.user === "USLACKBOT" && s.hideSlackbot) return false
      var u = users[c.user]
      if (!u) return c.user === s.me
      if (u.deleted) return false
    }
    return true
  }
  var muted = function(c) { return !isDm(c) && s.prefs[c.id] && s.prefs[c.id].muted }
  // Slack's "Active only" (sidebar_behavior "hide_inactive_channels"): a
  // conversation Slack flags dormant (30 days without a message), DMs and
  // apps' too, leaves the sidebar, unless it's unread, mentions you, is
  // open, was opened here lately or holds a draft. Starred ones stay: the
  // user put them there.
  var opened = {}
  ;(s.recents || []).forEach(function(id) { opened[id] = true })
  var inactive = function(c) {
    if (!s.hideInactive || !c.dormant) return false
    if (c.id === s.current || opened[c.id] || s.drafts[c.id]) return false
    var k = counts[c.id]
    if (k && (k.unread || k.mentions > 0)) return false
    // A message since Slack flagged it (the flag is as old as the last
    // users.conversations).
    return !(k && k.latest && Date.now() - U.tsNum(k.latest) * 1000 < 30 * 86400000)
  }
  var hasSections = s.sections && s.sections.length > 0
  var src = hasSections ? s.sections : [
    { id: "stars", type: "stars", name: "", ids: [] },
    { id: "dms", type: "direct_messages", name: "", ids: [] },
    { id: "channels", type: "channels", name: "", ids: [] }
  ]
  // Explicit sections claim their members first: the user's own, Starred,
  // then a user group's (Slack shows those apart from Channels, unless hidden).
  var explicit = {}
  var own = function(sec) { return sec.type === "standard" || sec.type === "custom" }
  var claims = function(sec) { return own(sec) || (sec.type === "user_group" && !sec.hidden) }
  var claim = function(sec) { sec.ids.forEach(function(id) { if (convs[id] && !explicit[id]) explicit[id] = sec.id }) }
  src.forEach(function(sec) { if (own(sec)) claim(sec) })
  for (var sid in s.stars) if (convs[sid] && !explicit[sid]) explicit[sid] = "stars"
  src.forEach(function(sec) { if (claims(sec) && !own(sec)) claim(sec) })
  var all = Object.keys(convs).map(function(k) { return convs[k] }).filter(eligible)
  var silenced = []
  var buckets = { stars: [], dms: [], channels: [], apps: [], connect: [] }
  var custom = {}
  // A section emptied only by "Active only" keeps its header (what muting
  // empties still goes, as before).
  var thinned = {}
  all.forEach(function(c) {
    var ex = explicit[c.id]
    if (ex !== "stars" && inactive(c)) { if (ex && !muted(c)) thinned[ex] = true; return }
    if (muted(c)) { silenced.push(c); return }
    if (ex === "stars") { buckets.stars.push(c); return }
    if (ex) { (custom[ex] = custom[ex] || []).push(c); return }
    // Apps: bots, Slackbot and "Slack" (USLACK, its system notices).
    if (c.kind === "im" && (c.user === "USLACK" || (users[c.user] && users[c.user].bot))) { buckets.apps.push(c); return }
    if (c.ext && !isDm(c) && hasSections && src.some(function(x) { return x.type === "slack_connect" })) { buckets.connect.push(c); return }
    if (isDm(c)) buckets.dms.push(c)
    else buckets.channels.push(c)
  })
  var lbl = function(c) { return label(c, users, s.me, s.handles, s.lang) }
  var byName = function(a, b) { var x = lbl(a).toLowerCase(), y = lbl(b).toLowerCase(); return x < y ? -1 : x > y ? 1 : 0 }
  var unread = function(c) { var k = counts[c.id]; return !!(k && (k.unread || k.mentions > 0)) && c.id !== s.current }
  // DMs: open ones (Slack's sidebar state), unread ones, the current one.
  var dms = buckets.dms.filter(function(c) {
    if (c.id === s.current || unread(c)) return true
    if (s.openIms) return !!s.openIms[c.id]
    return true
  })
  if (!s.openIms) {
    dms.sort(function(a, b) { return U.cmpTs((counts[b.id] || {}).latest || "0", (counts[a.id] || {}).latest || "0") })
    dms = dms.filter(function(c, k) { return k < 15 || unread(c) || c.id === s.current })
  }
  dms.sort(function(a, b) {
    var ua = unread(a), ub = unread(b)
    if (ua !== ub) return ua ? -1 : 1
    if (ua) return U.cmpTs((counts[b.id] || {}).latest || "0", (counts[a.id] || {}).latest || "0")
    return byName(a, b)
  })
  // Apps: the open ones, Slackbot first (its own sort group), then by name.
  var apps = buckets.apps.filter(function(c) { return c.id === s.current || unread(c) || !s.openIms || s.openIms[c.id] }).sort(function(a, b) {
    if ((a.user === "USLACKBOT") !== (b.user === "USLACKBOT")) return a.user === "USLACKBOT" ? -1 : 1
    return byName(a, b)
  })
  var starred = buckets.stars.sort(function(a, b) {
    if (a.kind === "im" && a.user === s.me) return -1
    if (b.kind === "im" && b.user === s.me) return 1
    return byName(a, b)
  })
  var rows = []
  // The new Slackbot's link, first among the pages (its DM's place).
  if (s.hideSlackbot) {
    var bot = Object.keys(convs).filter(function(id) { return convs[id].kind === "im" && convs[id].user === "USLACKBOT" })[0] || ""
    rows.push({ kind: "nav", key: "nav:slackbot", id: "slackbot", user: "USLACKBOT", label: tr("Slackbot", "Slackbot"),
                unread: false, mentions: 0, active: !!bot && s.current === bot && s.view === "conv" })
  }
  rows.push({ kind: "nav", key: "nav:threads", id: "threads", icon: "󰍪", label: tr("Threads", "Conversas"),
              unread: s.threads.unread, mentions: s.threads.mentions, active: s.view === "threads" })
  rows.push({ kind: "nav", key: "nav:drafts", id: "drafts", icon: "󰒊", label: tr("Drafts & sent", "Rascunhos e enviados"),
              unread: false, mentions: 0, count: s.draftCount, active: s.view === "drafts" })
  var appsPlaced = false
  src.forEach(function(sec) {
    var list = null, title = sec.name
    switch (sec.type) {
    case "stars": list = starred; title = tr("Starred", "Favoritos"); break
    case "direct_messages": list = dms; title = tr("Direct messages", "Mensagens diretas"); break
    case "channels": list = buckets.channels.sort(byName); title = tr("Channels", "Canais"); break
    case "recent_apps": list = apps; title = "Apps"; appsPlaced = true; break
    case "slack_connect": list = buckets.connect.sort(byName); title = "Slack Connect"; break
    case "standard": case "custom": case "user_group": list = claims(sec) ? (custom[sec.id] || []).sort(byName) : null; break
    default: list = null
    }
    if (!list || (list.length === 0 && !thinned[sec.id])) return
    pushSection(rows, s, sec.id, sec.type, title, sec.emoji || "", list, false)
  })
  if (!appsPlaced && apps.length) pushSection(rows, s, "apps", "recent_apps", "Apps", "", apps, false)
  if (silenced.length) pushSection(rows, s, "silenced", "silenced", tr("Silenced", "Silenciados"), "", silenced.sort(byName), true)
  return rows
}

function pushSection(rows, s, id, type, title, emoji, list, isSilenced) {
  var collapsed = isSilenced ? s.collapsed[id] !== false : !!s.collapsed[id]
  var anyUnread = false
  var counts = s.counts
  list.forEach(function(c) {
    var k = counts[c.id]
    if (k && k.unread && c.id !== s.current && !(s.prefs[c.id] && s.prefs[c.id].muted && !isDm(c))) anyUnread = true
  })
  // Slack's spacer above every section header but the first.
  var gap = rows.some(function(r) { return r.kind === "section" })
  rows.push({ kind: "section", key: "sec:" + id, id: id, type: type, label: title, emoji: emoji, collapsed: collapsed,
              unread: collapsed && anyUnread && !isSilenced, silenced: isSilenced, gap: gap })
  list.forEach(function(c) {
    var k = counts[c.id] || {}
    var isCurrent = c.id === s.current && s.view === "conv"
    var mentions = isCurrent && s.focused ? 0 : (k.mentions || 0)
    var unread = isCurrent && s.focused ? false : !!k.unread
    var mutedC = !isDm(c) && s.prefs[c.id] && s.prefs[c.id].muted
    if (collapsed && !(isCurrent || mentions > 0 || (!isSilenced && unread && !mutedC))) return
    rows.push({ kind: "conv", key: "conv:" + c.id, id: c.id, section: id, sectionType: type, convKind: c.kind, user: c.user || "",
                label: label(c, s.users, s.me, s.handles, s.lang), unread: unread && !mutedC, mentions: mentions,
                muted: !!mutedC, active: isCurrent, self: c.kind === "im" && c.user === s.me, ext: !!c.ext,
                draft: !!s.drafts[c.id] && !isCurrent, members: c.kind === "mpim" ? mpimHandles(c.name).length - 1 : 0 })
  })
  // Slack's "Add channels" / "Add coworkers": only in a section that shows
  // all its conversations; the DMs' also needs more than 10 of them or a
  // way to invite people. Newer workspaces' says "Invite people".
  var showsAll = sectionShow(s, id, type) === "all"
  if (!collapsed && showsAll && (type === "channels" || (type === "direct_messages" && (list.length > 10 || s.canInvite))))
    rows.push({ kind: "add", key: "add:" + id, id: id, sectionType: type, invite: !!s.invitePeople })
}

// What a section shows (Slack's channel section sidebar behavior): "all",
// "active" (no dormant channels), "hid" (no read ones) or "mentions". Its
// own choice when the sidebar is set per section (paid teams'
// hide_read_channels_unless_starred), else the global sidebar_behavior's.
function sectionShow(s, id, type) {
  var g = s.sidebarBehavior || ""
  var own = ((s.sectionPrefs || {})[id] || {}).sidebar
  var custom = g === "hide_read_channels_unless_starred" && s.paidTeam
  if (custom && ["all", "hid", "mentions", "active"].indexOf(own) >= 0) return type === "direct_messages" && own === "mentions" ? "hid" : own
  if (g === "hide_inactive_channels") return "active"
  if (g === "hide_read_channels") return "hid"
  if (g === "show_mentions_only") return type === "direct_messages" ? "hid" : "mentions"
  if (custom && ["channels", "direct_messages", "org_channels", "recent_apps", "shared_channels", "slack_connect"].indexOf(type) >= 0) return "hid"
  return "all"
}

// Badges for the bar and the rail: {mentions, dms, dmConvs, channels, total}
// (dms counts messages, dmConvs the conversations with something unread).
function attention(s) {
  var mentions = 0, dms = 0, dmConvs = 0, channels = 0
  for (var id in s.counts) {
    var k = s.counts[id], c = s.convs[id]
    if (!c || c.archived) continue
    if (!k.unread && !(k.mentions > 0)) continue
    if (isDm(c)) {
      if (c.kind === "im" && s.users[c.user] && s.users[c.user].deleted) continue
      dms += Math.max(1, k.mentions || 0)
      dmConvs++
    } else {
      mentions += k.mentions || 0
      if (k.unread && !quietPref(s.prefs[id])) channels++
    }
  }
  mentions += s.threads.mentions || 0
  return { mentions: mentions, dms: dms, dmConvs: dmConvs, channels: channels, total: mentions + dms }
}

// ------------------------------------------------------------------ people

// "Ana", "Ana and Bia", "Ana, Bia and 3 others" (Threads cards, reactions).
function people(names, extra, lang) {
  var tr = function(en, pt) { return lang === "pt-BR" ? pt : en }
  extra = extra || 0
  if (names.length === 0) return ""
  if (names.length === 1 && !extra) return names[0]
  if (names.length === 2 && !extra) return names[0] + tr(" and ", " e ") + names[1]
  if (extra > 0) { var n = extra + Math.max(0, names.length - 3); return names.slice(0, 3).join(", ") + tr(", and ", " e mais ") + n + tr(n === 1 ? " other" : " others", n === 1 ? " pessoa" : " pessoas") }
  if (names.length <= 3) return names.slice(0, -1).join(", ") + tr(", and ", " e ") + names[names.length - 1]
  var r = names.length - 3
  return names.slice(0, 3).join(", ") + tr(", and ", " e mais ") + r + tr(r === 1 ? " other" : " others", r === 1 ? " pessoa" : " pessoas")
}

function typingText(names, lang) {
  if (names.length === 0) return ""
  if (names.length === 1) return lang === "pt-BR" ? names[0] + " está digitando" : names[0] + " is typing"
  if (names.length === 2) return lang === "pt-BR" ? names[0] + " e " + names[1] + " estão digitando" : names[0] + " and " + names[1] + " are typing"
  return lang === "pt-BR" ? "Várias pessoas estão digitando" : "Several people are typing"
}
