import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// Slack's search: a card dropping from the top bar's search box over a dim
// window. The query finds conversations and people (locally, as you type)
// and messages (Slack's search, once typing pauses), in tabs; the right
// side previews the selected result. With nothing typed it is the quick
// switcher: recent and unread conversations.
Item {
  id: s
  property var app: Reg.service
  property var win
  property var ws
  property string initialQuery: ""
  property int topOffset: 0
  readonly property var t: app.theme
  signal closed()

  // ---------------------------------------------------------------- state
  property string typed: ""
  readonly property string query: typed.trim()
  property string tab: "all"                  // all | messages | channels | people
  property string sort: app.setting("searchSort", "timestamp") === "score" ? "score" : "timestamp"
  property var rows: []
  property int sel: -1
  property var convMatches: []                // ranked index entries: channels
  property var peopleMatches: []              // people and group DMs
  property bool peopleFirst: true             // All: People's best beats Channels'
  property int msgRev: 0
  property int pvRev: 0
  property bool shown: false
  property bool ready: false
  readonly property var life: ({ alive: true })
  readonly property var tabs: ["all", "messages", "channels", "people"]
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  readonly property bool wide: card.width >= t.sp(700)
  readonly property var selRow: sel >= 0 && sel < rows.length ? rows[sel] : null
  // For the views; the code below asks the functions (bindings may lag behind a handler).
  readonly property bool wantsMessages: { s.query; return s.wants() }
  readonly property var msgs: { s.msgRev; s.query; s.sort; return s.entry() }
  readonly property bool searching: { s.msgRev; s.query; s.sort; msgTimer.running; return s.isSearching() }

  function wants() { return s.query.replace(/\s/g, "").length >= 2 }
  function entry() { return s.wants() ? (s._cache[s.sort + "\n" + s.query] || null) : null }
  function isSearching() { var e = s.entry(); return s.wants() && (msgTimer.running || !e || (e.loading && e.page === 0)) }

  // Caches that outlive a query: message results per (sort, query), previews per result.
  property var _cache: ({})
  property var _cacheKeys: []
  property var _pc: ({})
  property var _pcKeys: []
  // The lists the query runs over, rebuilt when Slack's data changed.
  property var _convIdx: null
  property var _userIdx: null
  property string _idxRevs: ""

  Component.onCompleted: {
    if (!s.ws) { s.closed(); return }
    input.text = s.initialQuery
    input.cursorPosition = input.text.length
    s.ready = true
    s.refresh(true)
    s.shown = true
    warmIndex.start()
    Qt.callLater(function() { if (s.life.alive) input.forceActiveFocus() })
  }
  Component.onDestruction: s.life.alive = false

  onInitialQueryChanged: if (s.ready) { input.text = s.initialQuery; input.cursorPosition = input.text.length; input.forceActiveFocus() }
  onWsChanged: if (s.ready) s.close()
  onQueryChanged: if (s.ready) s.refresh(true)
  onTabChanged: if (s.ready) { s.rebuild(true); s.loadMoreIfNear() }
  onSortChanged: if (s.ready) { s.app.setSetting("searchSort", s.sort); s.refresh(false); s.startSearch() }
  onMsgRevChanged: if (s.ready) s.rebuild(false)
  onPvKeyChanged: s.previewSoon()
  onWideChanged: s.previewSoon()

  function close() {
    var w = s.win
    s.closed()
    Qt.callLater(function() { if (w && w.focusComposer) w.focusComposer() })
  }

  // ---------------------------------------------------------------- index
  function latestOf(e) {
    var k = s.ws.counts[e.id], lm = s.ws.lastMsgs[e.id]
    var v = Math.max(k ? U.tsNum(k.latest) : 0, lm ? U.tsNum(lm.ts) : 0)
    if (v) return v
    var u = e.updated || 0
    return u > 1e11 ? u / 1000 : u
  }

  // A conversation as the list draws it.
  function entryOf(c) {
    var w = s.ws
    var label = Model.label(c, w.users, w.me.id, w.handles, s.app.lang)
    var u = c.kind === "im" ? w.users[c.user] : null
    return {
      id: c.id, ckind: c.kind, label: label, archived: !!c.archived, outside: !!c.guest || c.member === false,
      members: c.numMembers || 0, user: c.user || "", self: c.kind === "im" && c.user === w.me.id, deleted: !!(u && u.deleted) || !!c.userDeleted,
      n: c.kind === "mpim" ? Model.mpimMembers(c, w.users, w.me.id, w.handles).length : 0, updated: c.updated || 0, purpose: c.purpose || ""
    }
  }

  // A name made ready for the matcher once, so typing only compares.
  function prep(name) {
    var f = U.fold(name)
    var toks = /^[\x00-\x7f]*$/.test(f) ? f.split(/[^a-z0-9]+/).filter(function(x) { return x }) : U.tokens(f)
    return { f: f, sep: f.replace(/[\s._-]+/g, " "), toks: toks, ini: toks.map(function(w) { return w.charAt(0) }).join("") }
  }

  function prepQuery(query) {
    var q = U.fold(query).replace(/^[#@]/, "").trim()
    return { q: q, sep: q.replace(/[\s._-]+/g, " "), toks: U.tokens(q) }
  }

  // U.rank's tiers (0 best … 6, -1 no match) over prepared names. The
  // typo tier (6) is a second pass, `typo` alone, when little matched.
  function rankPrep(p, Q, typo) {
    if (!Q.q) return 5
    if (p.f === Q.q) return 0
    if (p.sep.indexOf(Q.sep) === 0) return 1
    var qt = Q.toks, nt = p.toks
    if (qt.length === 0) return -1
    var i, j = 0
    for (i = 0; i < nt.length && j < qt.length; i++) if (nt[i].indexOf(qt[j]) === 0) j++
    if (j === qt.length) return 2
    if (qt.length > 1) {
      for (j = 0; j < qt.length; j++) {
        var hit = false
        for (i = 0; i < nt.length && !hit; i++) hit = nt[i].indexOf(qt[j]) === 0
        if (!hit) return -1
      }
      return 3
    }
    var t0 = qt[0]
    if (!typo) {
      if (t0.length >= 2 && t0.length <= 12 && nt.length >= 2 && p.ini.indexOf(t0) === 0) return 4
      if (p.f.indexOf(t0) >= 0) return 5
    } else if (t0.length >= 4) {
      for (i = 0; i < nt.length; i++) {
        var w = nt[i]
        // One edit from a word's start keeps one of these pairs equal.
        if (w.charAt(0) !== t0.charAt(0) && w.charAt(1) !== t0.charAt(1) && w.charAt(0) !== t0.charAt(1) && w.charAt(1) !== t0.charAt(0)) continue
        if (U.oneTypo(w.slice(0, t0.length + 1), t0)) return 6
      }
    }
    return -1
  }

  // Prepared names survive re-indexing while the name stays the same.
  property var _prepCache: ({})
  function prepOf(key, name) {
    var c = s._prepCache[key]
    if (c && c.name === name) return c.p
    var p = s.prep(name)
    s._prepCache[key] = { name: name, p: p }
    return p
  }

  function index() {
    var w = s.ws
    var revs = w.convsRev + "/" + w.usersRev + "/" + w.directoryRev + "/" + s.app.lang
    if (s._convIdx && s._idxRevs === revs) return
    var convs = [], dmOf = {}, known = {}
    for (var id in w.convs) {
      var c = w.convs[id]
      if (c.kind === "im") { if (c.user) dmOf[c.user] = id; continue }
      var en = s.entryOf(c)
      en.p = s.prepOf("c" + id, en.label)
      known[id] = en
      convs.push(en)
    }
    var dir = w.directory.chans || []
    for (var i = 0; i < dir.length; i++) {
      var d = dir[i]
      var k = known[d.id]
      if (k) { if (!k.members) k.members = d.members || 0; if (!k.purpose) k.purpose = d.purpose || ""; continue }
      convs.push({ id: d.id, ckind: "channel", label: d.name, p: s.prepOf("c" + d.id, d.name), archived: !!d.archived, outside: true, members: d.members || 0,
                   user: "", self: false, deleted: false, n: 0, updated: d.updated || 0, purpose: d.purpose || "" })
    }
    // Deactivated accounts too, as Slack finds them: their DM (kept aside,
    // Workspace.goneDms) opens as archives.
    var people = []
    for (var uid in w.users) {
      var u = w.users[uid]
      if (!u || u.bot || uid === "USLACKBOT") continue
      var ps = [s.prepOf("n" + uid, u.name || "")]
      if (u.real && u.real !== u.name) ps.push(s.prepOf("r" + uid, u.real))
      if (u.handle && u.handle !== u.name) ps.push(s.prepOf("h" + uid, u.handle))
      var gone = dmOf[uid] ? null : w.goneDms[uid]
      people.push({ id: uid, name: u.name || "", real: u.real || "", handle: u.handle || "", title: u.title || "",
                    ps: ps, dm: dmOf[uid] || (gone ? gone.id : ""), updated: gone ? gone.updated || 0 : 0, self: uid === w.me.id, deleted: !!u.deleted })
    }
    s._convIdx = convs
    s._userIdx = people
    s._idxRevs = revs
  }

  // The sidebar matcher's tiers as the kinds of match that rank apart:
  // 0 the whole name, 1 its start, 2 words starting with the query, 3
  // weaker (initials, inside a word, a typo). Recent conversations go
  // ahead within each.
  function grade(tier) { return tier === 0 ? 0 : (tier <= 1 ? 1 : (tier <= 3 ? 2 : 3)) }

  function matchLocal() {
    var q = s.query
    if (!q) { s.convMatches = []; s.peopleMatches = []; s.peopleFirst = true; return }
    s.index()
    var Q = s.prepQuery(q)
    var out = [], gout = [], pout = [], i, j, tier
    var cidx = s._convIdx, pidx = s._userIdx
    var cmiss = [], pmiss = []
    // Group DMs go with people, as Slack lists them with DMs. Their name is
    // the members' names: a start that stays inside the first name is only
    // a member's name starting with the query, ranked as a word's.
    function pushConv(at, best) {
      var ce = cidx[at], to = ce.ckind === "mpim" ? gout : out
      if (ce.ckind === "mpim" && best === 1 && Q.q.indexOf(",") < 0) best = 2
      to.push({ e: ce, tier: best, latest: s.latestOf(ce), at: at })
    }
    for (i = 0; i < cidx.length; i++) {
      tier = s.rankPrep(cidx[i].p, Q, false)
      if (tier >= 0) pushConv(i, tier)
      else cmiss.push(i)
    }
    function personTier(pe, typo) {
      var best = -1
      for (var k = 0; k < pe.ps.length; k++) {
        var tk = s.rankPrep(pe.ps[k], Q, typo)
        if (tk >= 0 && (best < 0 || tk < best)) best = tk
      }
      return best
    }
    function pushPerson(at, best) { var pe = pidx[at]; pout.push({ e: pe, tier: best, latest: pe.dm ? s.latestOf({ id: pe.dm, updated: pe.updated }) : 0, at: at }) }
    for (i = 0; i < pidx.length; i++) {
      tier = personTier(pidx[i], false)
      if (tier >= 0) pushPerson(i, tier)
      else pmiss.push(i)
    }
    // One typo away (single word of 4+ letters), only when little matched.
    if (Q.toks.length === 1 && Q.toks[0].length >= 4 && out.length + gout.length + pout.length < 40) {
      for (j = 0; j < cmiss.length; j++) if (s.rankPrep(cidx[cmiss[j]].p, Q, true) === 6) pushConv(cmiss[j], 6)
      for (j = 0; j < pmiss.length; j++) if (personTier(pidx[pmiss[j]], true) === 6) pushPerson(pmiss[j], 6)
    }
    out.sort(function(a, b) {
      if (a.e.archived !== b.e.archived) return a.e.archived ? 1 : -1
      var ga = s.grade(a.tier), gb = s.grade(b.tier)
      if (ga !== gb) return ga - gb
      if (a.latest !== b.latest) return b.latest - a.latest
      if (a.tier !== b.tier) return a.tier - b.tier
      if (a.e.outside !== b.e.outside) return a.e.outside ? 1 : -1
      if (a.e.members !== b.e.members) return b.e.members - a.e.members
      if (a.e.label.length !== b.e.label.length) return a.e.label.length - b.e.label.length
      return a.at - b.at
    })
    // Channels you're not in: at most 50 of them.
    var outside = 0
    out = out.filter(function(m) { return !m.e.outside || ++outside <= 50 })
    s.convMatches = out.map(function(m) { return m.e })

    // People and group DMs: a person ahead of a group that matches as well
    // (most often through that person's name), you behind others who do.
    // Deactivated accounts wait at the end, behind every active one.
    pout = pout.concat(gout)
    pout.sort(function(a, b) {
      if (!!a.e.archived !== !!b.e.archived) return a.e.archived ? 1 : -1
      if (!!a.e.deleted !== !!b.e.deleted) return a.e.deleted ? 1 : -1
      var ga = s.grade(a.tier), gb = s.grade(b.tier)
      if (ga !== gb) return ga - gb
      if (!!a.e.ckind !== !!b.e.ckind) return a.e.ckind ? 1 : -1
      if (a.e.self !== b.e.self) return a.e.self ? 1 : -1
      if (a.latest !== b.latest) return b.latest - a.latest
      if (a.tier !== b.tier) return a.tier - b.tier
      var la = (a.e.label || a.e.name).length, lb = (b.e.label || b.e.name).length
      if (la !== lb) return la - lb
      return a.at - b.at
    })
    s.peopleMatches = pout.map(function(m) { return m.e })

    // All: the section whose first answer is the better match goes first;
    // People on a tie, unless what leads it is you. Archived or deactivated
    // counts as weak.
    function lead(m) { return !m ? 9 : (m.e.archived || m.e.deleted ? 4 : s.grade(m.tier)) }
    var cg = lead(out[0]), pg = lead(pout[0])
    s.peopleFirst = pg < cg || (pg === cg && !(pout.length && pout[0].e.self))
  }

  // Empty query: where you've been, then what's unread, then what moved last.
  function recents() {
    var w = s.ws, out = [], seen = {}
    function add(id) {
      if (!id || seen[id] || id === w.current) return
      var c = w.convs[id]
      if (!c || (c.kind === "im" && !c.user)) return
      seen[id] = true
      out.push(s.entryOf(c))
    }
    for (var i = w.backStack.length - 1; i >= 0 && out.length < 8; i--) if (w.backStack[i].view === "conv") add(w.backStack[i].conv)
    var unread = [], rest = []
    for (var id in w.counts) {
      var k = w.counts[id], c = w.convs[id]
      if (!c || c.archived || c.guest || seen[id]) continue
      var hot = k.unread || k.mentions > 0
      if (hot && (k.mentions > 0 || !w.isMuted(id))) unread.push({ id: id, at: U.tsNum(k.latest) })
      else rest.push({ id: id, at: U.tsNum(k.latest) })
    }
    unread.sort(function(a, b) { return b.at - a.at })
    unread.forEach(function(x) { add(x.id) })
    if (out.length < 12) {
      rest.sort(function(a, b) { return b.at - a.at })
      for (var r = 0; r < rest.length && out.length < 12; r++) add(rest[r].id)
    }
    return out.slice(0, 20)
  }

  // Empty query, People: the DMs and group DMs that moved last.
  function recentPeople() {
    var w = s.ws, out = []
    for (var id in w.convs) {
      var c = w.convs[id]
      if (c.kind === "mpim") { if (!c.archived) out.push({ c: c, at: s.latestOf({ id: id, updated: c.updated }) }); continue }
      if (c.kind !== "im" || !c.user) continue
      var u = w.users[c.user]
      if (!u || u.deleted || u.bot) continue
      out.push({ e: { id: c.user, name: u.name || "", real: u.real || "", handle: u.handle || "", title: u.title || "", dm: id, self: c.user === w.me.id }, at: s.latestOf({ id: id, updated: c.updated }) })
    }
    out.sort(function(a, b) { return b.at - a.at })
    return out.slice(0, 20).map(function(x) { return x.e || s.entryOf(x.c) })
  }

  // ---------------------------------------------------------------- messages
  function canStar(q) {
    var last = q.split(/\s+/).pop() || ""
    return last.length >= 2 && last.slice(-1) !== "*" && last.slice(-1) !== "\"" && last.indexOf(":") < 0
  }

  function startSearch() {
    msgTimer.stop()
    if (!s.wants() || !s.ws) return
    var key = s.sort + "\n" + s.query
    // Results are kept; a failure is asked again next time.
    if (s._cache[key] && !s._cache[key].error) return
    var e = { q: s.query, sort: s.sort, hits: [], seen: {}, page: 0, pages: 1, total: 0, loading: false, error: "", retried: false, done: false }
    s._cache[key] = e
    s._cacheKeys.push(key)
    while (s._cacheKeys.length > 64) delete s._cache[s._cacheKeys.shift()]
    s.fetchPage(e)
  }

  function fetchPage(e) {
    if (e.loading || e.page >= e.pages || e.error) return
    e.loading = true
    s.msgRev++
    var want = e.page + 1, life = s.life
    s.ws.searchMessages(e.q, e.sort, want, function(r) {
      e.loading = false
      if (r.error) { e.error = r.error; e.done = true }
      else if (want === e.page + 1) {
        if (want === 1 && r.hits.length === 0 && !e.retried && s.canStar(e.q)) {
          e.retried = true
          e.q = e.q + "*"
          if (life.alive) s.fetchPage(e)
          return
        }
        r.hits.forEach(function(h) {
          var k = h.conv + "/" + h.ts
          if (!e.seen[k]) { e.seen[k] = true; e.hits.push(h) }
        })
        e.page = want
        e.pages = Math.max(1, r.pages)
        e.total = Math.max(r.total, e.hits.length)
        e.done = true
      }
      if (life.alive) s.msgRev++
    })
  }

  function loadMoreIfNear() {
    var e = s.entry()
    if (!e || e.loading || e.error || e.page >= e.pages || (s.tab !== "all" && s.tab !== "messages")) return
    var lastHit = -1
    for (var i = s.rows.length - 1; i >= 0; i--) if (s.rows[i].kind === "hit") { lastHit = i; break }
    if (lastHit < 0) return
    var nearSel = s.sel >= 0 && lastHit - s.sel <= 5
    var nearEnd = list.contentHeight > 0 && list.contentY + list.height >= list.contentHeight - s.t.sp(240)
    if (nearSel || nearEnd) s.fetchPage(e)
  }

  Timer { id: msgTimer; interval: 300; onTriggered: s.startSearch() }
  // The index is built once the card is up, not on the first keystroke.
  Timer { id: warmIndex; interval: 60; onTriggered: if (s.ws) s.index() }

  // ---------------------------------------------------------------- rows
  function refresh(reset) {
    s.matchLocal()
    var cached = s._cache[s.sort + "\n" + s.query]
    if (s.wants() && (!cached || cached.error)) msgTimer.restart()
    else msgTimer.stop()
    s.rebuild(reset)
  }

  function pickable(r) { return !!r && (r.kind === "conv" || r.kind === "person" || r.kind === "hit") }

  function rebuild(reset) {
    var q = s.query, tab = s.tab
    var out = []
    var qk = "\n" + tab + "\n" + q
    function head(text, extra) { out.push({ key: "head:" + text + qk, kind: "head", text: text, extra: extra || "" }) }
    function note(text, busy) { out.push({ key: "note:" + text + qk, kind: "note", text: text, busy: !!busy }) }
    function more(n, to) {
      out.push({ key: "more:" + to + qk, kind: "more", tab: to,
                 text: s.app.tr("+" + n + " more", "+" + n + " outros") + "  ·  Alt+" + (s.tabs.indexOf(to) + 1) })
    }
    function conv(e) { out.push({ key: "c:" + e.id + qk, kind: "conv", id: e.id, e: e }) }
    function person(e) { out.push({ key: "p:" + e.id + qk, kind: "person", uid: e.id, e: e }) }
    // People lists hold group DMs too (conversation entries).
    function who(e) { if (e.ckind) conv(e); else person(e) }
    function channels(cm) {
      if (!cm.length) return
      head(s.app.tr("Channels", "Canais"), String(cm.length))
      cm.slice(0, 5).forEach(conv)
      if (cm.length > 5) more(cm.length - 5, "channels")
    }
    function people(pm) {
      if (!pm.length) return
      head(s.app.tr("People", "Pessoas"), String(pm.length))
      pm.slice(0, 3).forEach(who)
      if (pm.length > 3) more(pm.length - 3, "people")
    }

    if (!q) {
      if (tab === "all" || tab === "channels") {
        var rec = s.recents().filter(function(e) { return tab === "all" || (e.ckind !== "im" && e.ckind !== "mpim") })
        if (rec.length) { head(s.app.tr("Recent", "Recentes")); rec.forEach(conv) }
        else note(s.app.tr("Type to find a conversation", "Digite para achar uma conversa"))
      } else if (tab === "people") {
        var rp = s.recentPeople()
        if (rp.length) { head(s.app.tr("Recent", "Recentes")); rp.forEach(who) }
        else note(s.app.tr("Type to find someone", "Digite para achar alguém"))
      } else note(s.app.tr("Type two letters or more to search messages", "Digite duas letras ou mais para buscar mensagens"))
    } else {
      var cm = s.convMatches, pm = s.peopleMatches
      if (tab === "all") {
        // The better match first, so it is what's picked (see matchLocal).
        if (s.peopleFirst) { people(pm); channels(cm) }
        else { channels(cm); people(pm) }
      } else if (tab === "channels") {
        if (cm.length) { cm.slice(0, 150).forEach(conv); if (cm.length > 150) note(s.app.tr("Keep typing to narrow it down", "Continue digitando para filtrar")) }
        else note(s.app.tr("No channels match", "Nenhum canal encontrado"))
      } else if (tab === "people") {
        if (pm.length) { pm.slice(0, 150).forEach(who); if (pm.length > 150) note(s.app.tr("Keep typing to narrow it down", "Continue digitando para filtrar")) }
        else note(s.app.tr("No one matches", "Ninguém encontrado"))
      }
      if (tab === "all" || tab === "messages") {
        var e = s.entry()
        if (tab === "all") head(s.app.tr("Messages", "Mensagens"), e && e.done && !e.error ? String(e.total) : "")
        if (!s.wants()) note(s.app.tr("Type two letters or more to search messages", "Digite duas letras ou mais para buscar mensagens"))
        else if (e && e.error) note(e.error)
        else if (!e || e.hits.length === 0) {
          if (s.isSearching()) note(s.app.tr("Searching…", "Buscando…"), true)
          else note(s.app.tr("No messages match", "Nenhuma mensagem encontrada"))
        } else {
          var mk = "\n" + s.sort + "\n" + q
          e.hits.forEach(function(h) { out.push({ key: "h:" + h.conv + "/" + h.ts + mk, kind: "hit", hit: h }) })
          if (e.loading) note(s.app.tr("Loading more…", "Carregando mais…"), true)
        }
      }
    }

    var keep = !reset && s.selRow ? s.selRow.key : ""
    s.rows = out
    var at = -1
    if (keep) for (var i = 0; i < out.length; i++) if (out[i].key === keep) { at = i; break }
    if (at < 0) {
      at = s.firstPickable()
      if (!reset && s.sel >= 0 && s.sel < out.length && s.pickable(out[s.sel])) at = s.sel
      s.sel = at
      if (reset) list.positionViewAtBeginning()
    } else s.sel = at
  }

  function firstPickable() {
    for (var i = 0; i < s.rows.length; i++) if (s.pickable(s.rows[i])) return i
    return -1
  }

  // ---------------------------------------------------------------- moving
  function select(i) {
    if (i < 0 || i >= s.rows.length) return
    s.sel = i
    if (i === s.firstPickable()) list.positionViewAtBeginning()
    else list.positionViewAtIndex(i, ListView.Contain)
    s.loadMoreIfNear()
  }

  function move(d) {
    var steps = Math.abs(d), dir = d > 0 ? 1 : -1, i = s.sel, best = s.sel
    while (steps > 0) {
      i += dir
      if (i < 0 || i >= s.rows.length) break
      if (s.pickable(s.rows[i])) { best = i; steps-- }
    }
    if (best !== s.sel) s.select(best)
    else if (best < 0) s.select(s.firstPickable())
  }

  function pageStep() { return Math.max(1, Math.floor(list.height / s.t.sp(52))) }

  function setTab(name) { if (s.tabs.indexOf(name) >= 0) s.tab = name }
  function cycleTab(d) { s.tab = s.tabs[(s.tabs.indexOf(s.tab) + d + s.tabs.length) % s.tabs.length] }
  function toggleSort() { s.sort = s.sort === "score" ? "timestamp" : "score" }

  // ---------------------------------------------------------------- opening
  function openRow(r) {
    if (!r || !s.ws) return
    var w = s.ws
    if (r.kind === "hit") {
      var h = r.hit
      w.open(h.conv, h.threadTs ? { ts: h.threadTs, threadTs: h.threadTs } : { ts: h.ts })
      if (h.threadTs) w.flashTs = h.ts
    } else if (r.kind === "conv") w.open(r.id)
    // A deactivated account: their DM's archives, or with none, their profile.
    else if (r.kind === "person" && r.e.deleted && !w.dmWith(r.uid)) { w.profileUser = r.uid; w.thread = null }
    else if (r.kind === "person") w.openDm([r.uid])
    else if (r.kind === "more") { s.setTab(r.tab); return }
    else return
    var win = s.win
    s.closed()
    if (!(r.kind === "hit" && r.hit.threadTs)) Qt.callLater(function() { if (win && win.focusComposer) win.focusComposer() })
  }

  function clicked(i) {
    var r = s.rows[i]
    if (!r) return
    if (r.kind === "more") { s.setTab(r.tab); return }
    if (!s.pickable(r)) return
    if (i === s.sel || !s.wide) s.openRow(r)
    else s.select(i)
  }

  // ---------------------------------------------------------------- keys
  function ownsShortcut(e) {
    var ctrl = (e.modifiers & Qt.ControlModifier) !== 0, alt = (e.modifiers & Qt.AltModifier) !== 0
    if (ctrl && [Qt.Key_K, Qt.Key_T, Qt.Key_G, Qt.Key_S, Qt.Key_U].indexOf(e.key) >= 0) return true
    if (alt && e.key >= Qt.Key_1 && e.key <= Qt.Key_4) return true
    return false
  }

  function key(e) {
    var ctrl = (e.modifiers & Qt.ControlModifier) !== 0, alt = (e.modifiers & Qt.AltModifier) !== 0
    switch (e.key) {
    case Qt.Key_Down: s.move(1); return true
    case Qt.Key_Up: s.move(-1); return true
    case Qt.Key_PageDown: s.move(s.pageStep()); return true
    case Qt.Key_PageUp: s.move(-s.pageStep()); return true
    case Qt.Key_Tab: s.cycleTab(1); return true
    case Qt.Key_Backtab: s.cycleTab(-1); return true
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (s.pickable(s.selRow)) s.openRow(s.selRow)
      else if (msgTimer.running) s.startSearch()
      return true
    case Qt.Key_Escape: if (input.text !== "") input.text = ""; else s.close(); return true
    }
    if (ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_T || e.key === Qt.Key_G)) { s.close(); return true }
    if (ctrl && e.key === Qt.Key_S) { s.toggleSort(); return true }
    if (ctrl && e.key === Qt.Key_U) { input.text = ""; return true }
    if (alt && e.key >= Qt.Key_1 && e.key <= Qt.Key_4) { s.setTab(s.tabs[e.key - Qt.Key_1]); return true }
    return false
  }

  // ---------------------------------------------------------------- text
  // Query words to mark in results (U.markTokens).
  readonly property var marks: U.markTokens(s.query)

  function marked(plain) {
    return Md.highlight(U.escapeHtml(plain), s.t.html.meText, s.t.html.meBg)
  }

  // A name with what matched the query lit (styled text, which elides).
  function nameHtml(label) { return U.nameHtml(label, s.marks, s.t.html.meText) }

  // A hit's text: one flowing line, matches lit, cut to start near the
  // first match when that sits far in.
  function hitHtml(h) {
    if (!h || !s.ctx) return ""
    var text = String(h.text || "").replace(/<([^<>]*)>/g, function(all, inner) {
      var bar = inner.indexOf("|")
      if (bar < 0) return "<" + inner.replace(/[\ue000\ue001]/g, "") + ">"
      return "<" + inner.slice(0, bar).replace(/[\ue000\ue001]/g, "") + "|" + inner.slice(bar + 1) + ">"
    }).replace(/:[^\s:]*[\ue000\ue001][^\s:]*:/g, function(code) { return code.replace(/[\ue000\ue001]/g, "") })
    var flat = Md.flat({ text: text, blocks: [], files: (h.files || []).map(function(f) { return { name: f.name || f.title || "" } }), attachments: h.attachments || [], subtype: "" }, s.ctx, 0)
    flat = U.addMarks(flat, s.marks)
    var first = flat.indexOf("\ue000")
    if (first > 110) {
      var from = flat.lastIndexOf(" ", first - 40)
      if (from > 0) flat = "…" + flat.slice(from + 1).replace(/^[\ue001]/, "")
    }
    if (flat.length > 320) flat = flat.slice(0, 319) + "…"
    var opens = (flat.match(/\ue000/g) || []).length, closes = (flat.match(/\ue001/g) || []).length
    if (opens > closes) flat += "\ue001"
    return s.marked(flat)
  }

  // A person, or an app by the name its message posts with (Workspace.author).
  function author(h) { return s.ws.author(h).name || h.username || "?" }

  // Where a hit was said: "#eng", "Direct message with Ana", the group's names.
  function place(h) {
    var w = s.ws, c = w.conv(h.conv)
    if (h.convKind === "im") {
      var uid = c && c.user ? c.user : (/^[UW][A-Z0-9]+$/.test(h.convName) ? h.convName : "")
      if (uid === w.me.id) return s.app.tr("Direct message with yourself", "Mensagem direta com você mesmo")
      var who = uid ? w.userName(uid) : ""
      return who ? s.app.tr("Direct message with ", "Mensagem direta com ") + who : s.app.tr("Direct message", "Mensagem direta")
    }
    if (h.convKind === "mpim") {
      if (c) return w.convLabel(h.conv)
      var names = Model.mpimHandles(h.convName).filter(function(x) { return x !== (w.users[w.me.id] || {}).handle }).map(function(x) { var id = w.handles[x]; return id && w.users[id] ? w.users[id].name : x })
      return Model.mpimLabel(names)
    }
    return (h.convKind === "private" ? "󰌾 " : "#") + (c && c.name ? c.name : h.convName)
  }

  function memberCount(n) {
    if (!n) return ""
    return n === 1 ? s.app.tr("1 member", "1 membro") : n + s.app.tr(" members", " membros")
  }

  function suffixOf(e) {
    var bits = []
    if (e.archived) bits.push(s.app.tr("archived", "arquivado"))
    if (e.ckind === "channel" && e.outside) bits.push(s.app.tr("not a member", "não participa"))
    if (e.deleted) bits.push(s.app.tr("deactivated", "desativada"))
    return bits.length ? " (" + bits.join(", ") + ")" : ""
  }

  // ---------------------------------------------------------------- preview
  readonly property string pvKey: {
    var r = s.selRow
    if (!r) return ""
    return r.kind === "hit" ? "h:" + r.hit.conv + "/" + r.hit.ts : (r.kind === "conv" ? "c:" + r.id : (r.kind === "person" ? "p:" + r.uid : ""))
  }
  readonly property var pv: { s.pvRev; return s.pvKey ? (s._pc[s.pvKey] || null) : null }

  function previewSoon() {
    if (!s.wide || !s.pvKey) return
    if (s._pc[s.pvKey]) { s.pvRev++; return }
    pvTimer.restart()
  }
  Timer { id: pvTimer; interval: 150; onTriggered: s.loadPreview() }

  function remember(key, e) {
    s._pc[key] = e
    s._pcKeys.push(key)
    while (s._pcKeys.length > 48) delete s._pc[s._pcKeys.shift()]
  }

  function loadPreview() {
    var key = s.pvKey, r = s.selRow, w = s.ws, life = s.life
    if (!key || !r || s._pc[key]) { s.pvRev++; return }
    var e = { key: key, loading: true, msgs: [], info: null, error: "" }
    s.remember(key, e)
    s.pvRev++
    // Views see a fresh copy each time the preview moves on.
    function bump() { if (!life.alive) return; if (s._pc[key]) s._pc[key] = U.copy(e); s.pvRev++ }
    function lastOf(conv) {
      var h = w.histories[conv]
      if (h && h.msgs.length && !h.detached && !w.fromCache[conv]) { e.loading = false; bump(); return }
      w.api("conversations.history", { channel: conv, limit: 8 }, function(b) {
        e.msgs = (b.messages || []).map(Model.parseMessage).reverse()
        e.loading = false
        bump()
      }, function(err) { e.loading = false; e.error = w.errorText(err); bump() })
    }
    if (r.kind === "hit") {
      w.context(r.hit.conv, r.hit.ts, r.hit.threadTs, function(list) {
        e.msgs = list
        e.loading = false
        bump()
      })
    } else if (r.kind === "conv") {
      var c = w.convs[r.id]
      if (!c || c.kind === "channel" || c.kind === "private")
        w.api("conversations.info", { channel: r.id, include_num_members: true }, function(b) { e.info = Model.parseConv(b.channel, null); bump() }, function() {})
      lastOf(r.id)
    } else if (r.kind === "person") {
      w.profile(r.uid, function() { bump() })
      var dm = s.dmOf(r.uid)
      if (dm) lastOf(dm)
      else { e.loading = false; bump() }
    }
  }

  // A deactivated account's too (their archives).
  function dmOf(uid) { return s.ws.dmWith(uid) }

  // The messages to draw for a preview: live history when the store has
  // it, else what the preview fetched.
  function previewMsgs(conv, e) {
    var h = s.ws.history(conv)
    // The cache's messages only until the preview's own fetch is in.
    if (h && h.msgs.length && !h.detached && !(s.ws.fromCache[conv] && e && e.msgs.length)) return h.msgs.slice(-8)
    return e ? e.msgs : []
  }

  // ---------------------------------------------------------------- look
  // The dim window behind; a click outside the card closes.
  Rectangle {
    anchors.fill: parent
    color: s.t.scrim
    opacity: s.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140 } }
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: s.close()
      onWheel: wheel => {}
    }
  }

  BorderSurface {
    id: card
    readonly property int boxY: Math.max(s.t.sp(3), Math.round((s.topOffset - s.t.sp(28)) / 2) - s.t.sp(2))
    width: Math.round(Math.min(s.width - s.t.sp(24), s.t.sp(1560), Math.max(s.t.sp(760), s.width * 0.78)))
    height: Math.round(Math.min(s.height - y - s.t.sp(14), Math.max(s.t.sp(480), s.height * 0.9)))
    x: Math.round((s.width - width) / 2)
    y: boxY
    color: s.t.popup
    borderSpec: s.t.popupBorder
    radius: Math.max(8, s.t.radiusCard)
    clip: true
    opacity: s.shown ? 1 : 0
    transform: Translate { y: s.shown ? 0 : -s.t.sp(10); Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => {} }

    // ------------------------------------------------------------ field
    Item {
      id: inputRow
      width: parent.width
      height: s.t.sp(54)

      Glyph {
        app: s.app
        x: s.t.sp(20)
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰍉"
        size: s.t.fsTitle + 2
        color: input.activeFocus ? s.t.fgSoft : s.t.fgDim
      }

      TextInput {
        id: input
        x: s.t.sp(52)
        width: parent.width - x - tools.width - s.t.sp(24)
        anchors.verticalCenter: parent.verticalCenter
        color: s.t.fgBright
        selectionColor: s.t.alpha(s.t.accent, 0.35)
        selectedTextColor: s.t.fgBright
        selectByMouse: true
        clip: true
        font.family: s.t.font
        font.pixelSize: s.t.fsTitle + 1
        onTextChanged: s.typed = text
        Keys.onShortcutOverride: event => { if (s.ownsShortcut(event)) event.accepted = true }
        Keys.onPressed: event => { if (s.key(event)) event.accepted = true }

        Text {
          visible: input.text === ""
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          text: s.app.tr("Search messages, channels and people in ", "Buscar mensagens, canais e pessoas em ") + (s.ws ? s.ws.team.name : "")
          textFormat: Text.PlainText
          color: s.t.fgDim
          font: input.font
          elide: Text.ElideRight
        }
      }

      Row {
        id: tools
        anchors.right: parent.right
        anchors.rightMargin: s.t.sp(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: s.t.sp(8)
        IconButton {
          visible: input.text !== ""
          app: s.app
          anchors.verticalCenter: parent.verticalCenter
          icon: "󰅖"
          tip: s.app.tr("Clear", "Limpar") + "  Esc"
          onClicked: { input.text = ""; input.forceActiveFocus() }
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: escText.implicitWidth + s.t.sp(12)
          height: s.t.sp(22)
          radius: Math.max(4, s.t.radiusSmall)
          color: escMa.containsMouse ? s.t.hoverStrong : s.t.alpha(s.t.fg, 0.07)
          border.width: 1
          border.color: s.t.line
          Text { id: escText; anchors.centerIn: parent; text: "Esc"; color: s.t.fgDim; font.family: s.t.font; font.pixelSize: s.t.fsTiny; font.bold: true }
          MouseArea { id: escMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: s.close() }
          PanelToolTip { visible: escMa.containsMouse; text: s.app.tr("Close", "Fechar") }
        }
      }
    }

    // ------------------------------------------------------------ tabs
    Item {
      id: tabsRow
      y: inputRow.height
      width: parent.width
      height: s.t.sp(36)

      Rectangle { width: parent.width; height: 1; color: s.t.line }

      Row {
        x: s.t.sp(12)
        height: parent.height
        spacing: s.t.sp(2)
        Repeater {
          model: s.tabs
          delegate: Item {
            id: tabItem
            required property var modelData
            readonly property bool on: s.tab === modelData
            readonly property string count: {
              s.msgRev; s.rows; s.query; s.sort
              if (!s.query) return ""
              if (modelData === "channels") return String(s.convMatches.length)
              if (modelData === "people") return String(s.peopleMatches.length)
              var e = s.entry()
              if (modelData === "messages") return e && e.done && !e.error ? String(e.total) : ""
              return ""
            }
            height: parent.height
            width: tabLabel.implicitWidth + s.t.sp(22)
            Rectangle {
              anchors.fill: parent
              anchors.topMargin: s.t.sp(4)
              anchors.bottomMargin: s.t.sp(4)
              radius: Math.max(4, s.t.radiusSmall)
              color: tabMa.containsMouse && !tabItem.on ? s.t.hover : "transparent"
            }
            Row {
              id: tabLabel
              anchors.centerIn: parent
              spacing: s.t.sp(6)
              Glyph {
                app: s.app
                anchors.verticalCenter: parent.verticalCenter
                icon: ({ all: "󰍉", messages: "󰍪", channels: "󰐣", people: "󰀏" })[tabItem.modelData]
                size: s.t.fsSmall + 1
                color: tabItem.on ? s.t.fgBright : s.t.fgDim
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ({ all: s.app.tr("All", "Tudo"), messages: s.app.tr("Messages", "Mensagens"), channels: s.app.tr("Channels", "Canais"), people: s.app.tr("People", "Pessoas") })[tabItem.modelData]
                color: tabItem.on ? s.t.fgBright : s.t.fgDim
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall + 1
                font.bold: tabItem.on
              }
              Rectangle {
                visible: tabItem.count !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: countText.implicitWidth + s.t.sp(10)
                height: s.t.sp(17)
                radius: height / 2
                color: tabItem.on ? s.t.alpha(s.t.accent, 0.22) : s.t.alpha(s.t.fg, 0.08)
                Text { id: countText; anchors.centerIn: parent; text: tabItem.count; color: tabItem.on ? s.t.fgBright : s.t.fgDim; font.family: s.t.font; font.pixelSize: s.t.fsTiny; font.bold: true }
              }
            }
            Rectangle {
              visible: tabItem.on
              anchors.bottom: parent.bottom
              x: s.t.sp(4)
              width: parent.width - s.t.sp(8)
              height: 2
              radius: 1
              color: s.t.accent
            }
            MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { s.tab = tabItem.modelData; input.forceActiveFocus() } }
            PanelToolTip { visible: tabMa.containsMouse; text: "Alt+" + (s.tabs.indexOf(tabItem.modelData) + 1) }
          }
        }
      }

      // Date ↔ relevance.
      Rectangle {
        id: sortBtn
        visible: s.tab === "all" || s.tab === "messages"
        anchors.right: parent.right
        anchors.rightMargin: s.t.sp(14)
        anchors.verticalCenter: parent.verticalCenter
        height: s.t.sp(26)
        width: sortRow.implicitWidth + s.t.sp(18)
        radius: Math.max(4, s.t.radiusSmall)
        color: sortMa.containsMouse ? s.t.hover : "transparent"
        border.width: 1
        border.color: s.t.line
        Row {
          id: sortRow
          anchors.centerIn: parent
          spacing: s.t.sp(6)
          Glyph { app: s.app; anchors.verticalCenter: parent.verticalCenter; icon: s.sort === "score" ? "󰒿" : "󰅐"; size: s.t.fsSmall + 1; color: s.t.fgSoft }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: s.sort === "score" ? s.app.tr("Most relevant", "Mais relevantes") : s.app.tr("Most recent", "Mais recentes")
            color: s.t.fgSoft
            font.family: s.t.font
            font.pixelSize: s.t.fsSmall
            font.bold: true
          }
          Glyph { app: s.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰅀"; size: s.t.fsSmall; color: s.t.fgDim }
        }
        MouseArea {
          id: sortMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: s.win.menuAt(sortBtn, [
            { header: s.app.tr("Sort messages", "Ordenar mensagens") },
            { label: s.app.tr("Most recent", "Mais recentes"), checked: s.sort === "timestamp", action: function() { s.sort = "timestamp" } },
            { label: s.app.tr("Most relevant", "Mais relevantes"), checked: s.sort === "score", action: function() { s.sort = "score" } }
          ], 0, sortBtn.height + s.t.sp(4))
        }
        PanelToolTip { visible: sortMa.containsMouse; text: s.app.tr("Sort  Ctrl+S", "Ordenar  Ctrl+S") }
      }

      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: s.t.line }
    }

    // ------------------------------------------------------------ results
    Item {
      id: bodyArea
      y: tabsRow.y + tabsRow.height
      width: parent.width
      height: parent.height - y - foot.height

      ListView {
        id: list
        width: s.wide ? Math.round(parent.width * 0.46) : parent.width
        height: parent.height
        clip: true
        topMargin: s.t.sp(6)
        bottomMargin: s.t.sp(10)
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: false
        cacheBuffer: s.t.sp(400)
        model: ScriptModel { values: s.rows; objectProp: "key" }
        ScrollBar.vertical: ThinScroll { app: s.app }
        onContentYChanged: if (s.ready) moreTimer.restart()
        Timer { id: moreTimer; interval: 120; onTriggered: s.loadMoreIfNear() }

        delegate: Item {
          id: rowItem
          required property var modelData
          required property int index
          readonly property var r: modelData
          readonly property bool selected: index === s.sel
          readonly property bool hot: s.pickable(r) || r.kind === "more"
          width: list.width
          height: body.item ? body.item.implicitHeight : 0

          Rectangle {
            visible: s.pickable(rowItem.r)
            x: s.t.sp(8)
            y: 1
            width: parent.width - s.t.sp(16)
            height: parent.height - 2
            radius: Math.max(6, s.t.radiusSmall)
            color: rowItem.selected ? s.t.alpha(s.t.accent, 0.17) : (rowMa.containsMouse ? s.t.hover : "transparent")
            Rectangle {
              visible: rowItem.selected
              x: 0
              width: s.t.sp(3)
              height: parent.height - s.t.sp(14)
              anchors.verticalCenter: parent.verticalCenter
              radius: width / 2
              color: s.t.accent
            }
          }

          Loader {
            id: body
            width: parent.width
            sourceComponent: ({ head: headC, note: noteC, more: moreC, conv: convC, person: personC, hit: hitC })[rowItem.r.kind] || null
          }

          MouseArea {
            id: rowMa
            anchors.fill: parent
            enabled: rowItem.hot
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: s.clicked(rowItem.index)
            onDoubleClicked: s.openRow(rowItem.r)
          }

          // -------------------------------------------------------- heading
          Component {
            id: headC
            Item {
              implicitHeight: s.t.sp(rowItem.index === 0 ? 26 : 34)
              Row {
                x: s.t.sp(20)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: s.t.sp(5)
                spacing: s.t.sp(6)
                Text { text: rowItem.r.text; textFormat: Text.PlainText; color: s.t.fgDim; font.family: s.t.font; font.pixelSize: s.t.fsSmall; font.bold: true }
                Text { visible: rowItem.r.extra !== ""; text: rowItem.r.extra; textFormat: Text.PlainText; color: s.t.alpha(s.t.fgDim, 0.8); font.family: s.t.font; font.pixelSize: s.t.fsSmall }
              }
            }
          }

          // -------------------------------------------------------- note
          Component {
            id: noteC
            Item {
              implicitHeight: noteText.implicitHeight + s.t.sp(20)
              Text {
                id: noteText
                x: s.t.sp(20)
                width: parent.width - s.t.sp(40)
                anchors.verticalCenter: parent.verticalCenter
                text: rowItem.r.text
                textFormat: Text.PlainText
                color: s.t.fgDim
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall + 1
                font.italic: true
                wrapMode: Text.Wrap
                opacity: rowItem.r.busy ? 0.6 + 0.4 * busyPulse.v : 1
              }
            }
          }

          // -------------------------------------------------------- more
          Component {
            id: moreC
            Item {
              implicitHeight: s.t.sp(28)
              Text {
                x: s.t.sp(20)
                anchors.verticalCenter: parent.verticalCenter
                text: rowItem.r.text
                textFormat: Text.PlainText
                color: s.t.link
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall
                font.underline: rowMa.containsMouse
              }
            }
          }

          // -------------------------------------------------------- conversation
          Component {
            id: convC
            Item {
              id: cr
              readonly property var e: rowItem.r.e
              readonly property var k: { s.ws.countsRev; return s.ws.counts[cr.e.id] || null }
              readonly property bool unread: !!cr.k && (cr.k.unread || cr.k.mentions > 0) && !cr.e.archived
              readonly property bool dim: cr.e.archived || cr.e.deleted || (cr.e.outside && cr.e.ckind === "channel")
              implicitHeight: s.t.sp(36)

              ConvIcon {
                id: crIcon
                app: s.app
                ws: s.ws
                e: cr.e
                x: s.t.sp(20)
                anchors.verticalCenter: parent.verticalCenter
                size: s.t.sp(20)
                ink: cr.unread ? s.t.fgBright : s.t.fgSoft
                ring: rowItem.selected ? Qt.tint(s.t.popup, s.t.alpha(s.t.accent, 0.17)) : (rowMa.containsMouse ? Qt.tint(s.t.popup, s.t.hover) : s.t.popup)
              }
              Text {
                id: crName
                anchors.left: crIcon.right
                anchors.leftMargin: s.t.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, cr.width - x - crRight.width - s.t.sp(40))
                text: s.nameHtml(cr.e.label)
                textFormat: Text.StyledText
                color: cr.dim ? s.t.fgDim : (cr.unread ? s.t.fgBright : s.t.fg)
                font.family: s.t.font
                font.pixelSize: s.t.fsText
                font.bold: cr.unread
                elide: Text.ElideRight
                maximumLineCount: 1
              }
              Text {
                anchors.left: crName.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, cr.width - x - crRight.width - s.t.sp(32))
                text: s.suffixOf(cr.e) + (cr.e.members && cr.e.ckind !== "im" && cr.e.ckind !== "mpim" ? "  ·  " + s.memberCount(cr.e.members) : "")
                color: s.t.fgDim
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall
                elide: Text.ElideRight
              }
              Row {
                id: crRight
                anchors.right: parent.right
                anchors.rightMargin: s.t.sp(20)
                anchors.verticalCenter: parent.verticalCenter
                spacing: s.t.sp(8)
                Badge { app: s.app; anchors.verticalCenter: parent.verticalCenter; count: cr.k && !cr.e.archived ? (cr.k.mentions || 0) : 0 }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: { var l = s.latestOf(cr.e); return l ? U.shortStamp(String(l), s.app.lang, s.app.clock24) : "" }
                  color: s.t.fgDim
                  font.family: s.t.font
                  font.pixelSize: s.t.fsTiny
                }
              }
            }
          }

          // -------------------------------------------------------- person
          Component {
            id: personC
            Item {
              id: pr
              readonly property var e: rowItem.r.e
              readonly property var st: pr.e.deleted ? null : s.ws.statusOf(pr.e.id)
              implicitHeight: s.t.sp(46)
              Avatar {
                id: prAva
                app: s.app
                ws: s.ws
                user: pr.e.id
                x: s.t.sp(18)
                anchors.verticalCenter: parent.verticalCenter
                size: s.t.sp(30)
                showPresence: true
                ring: rowItem.selected ? Qt.tint(s.t.popup, s.t.alpha(s.t.accent, 0.17)) : (rowMa.containsMouse ? Qt.tint(s.t.popup, s.t.hover) : s.t.popup)
              }
              Column {
                anchors.left: prAva.right
                anchors.leftMargin: s.t.sp(11)
                anchors.right: parent.right
                anchors.rightMargin: s.t.sp(20)
                anchors.verticalCenter: parent.verticalCenter
                spacing: s.t.sp(1)
                Row {
                  width: parent.width
                  spacing: s.t.sp(6)
                  Text {
                    id: prName
                    width: Math.min(implicitWidth, parent.width - prEmoji.width - prReal.implicitWidth - s.t.sp(14))
                    text: s.nameHtml(pr.e.name) + (pr.e.self ? "<font color=\"" + s.t.hex(s.t.fgDim) + "\">" + s.app.tr(" (you)", " (você)") + "</font>" : "")
                    textFormat: Text.StyledText
                    color: s.t.fgBright
                    font.family: s.t.font
                    font.pixelSize: s.t.fsText
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                  EmojiIcon {
                    id: prEmoji
                    visible: !!pr.st && (pr.st.emoji !== "" || pr.st.unicode !== "")
                    anchors.verticalCenter: prName.verticalCenter
                    app: s.app
                    ws: s.ws
                    name: pr.st ? pr.st.emoji.replace(/:/g, "") : ""
                    glyph: pr.st && pr.st.unicode ? Emoji.fromHex(pr.st.unicode) : ""
                    size: s.t.sp(16)
                    StatusTip { app: s.app; ws: s.ws; status: pr.st; area: rowMa }
                  }
                  Text {
                    id: prReal
                    anchors.verticalCenter: prName.verticalCenter
                    width: Math.max(0, Math.min(implicitWidth, parent.width - prName.width - prEmoji.width - s.t.sp(12)))
                    text: pr.e.real && pr.e.real !== pr.e.name ? pr.e.real : (pr.e.handle ? "@" + pr.e.handle : "")
                    textFormat: Text.PlainText
                    color: s.t.fgDim
                    font.family: s.t.font
                    font.pixelSize: s.t.fsSmall
                    elide: Text.ElideRight
                  }
                }
                Text {
                  visible: text !== ""
                  width: parent.width
                  text: pr.e.deleted ? s.app.tr("Deactivated account", "Conta desativada") + (pr.e.title ? "  ·  " + pr.e.title : "") : (pr.e.title || (pr.st ? pr.st.text : ""))
                  textFormat: Text.PlainText
                  color: s.t.fgDim
                  font.family: s.t.font
                  font.pixelSize: s.t.fsSmall
                  elide: Text.ElideRight
                }
              }
            }
          }

          // -------------------------------------------------------- message
          Component {
            id: hitC
            Item {
              id: hr
              readonly property var h: rowItem.r.hit
              readonly property var who: s.ws.author(hr.h)
              implicitHeight: hrCol.implicitHeight + s.t.sp(16)
              Avatar {
                visible: !(hr.who.app && !hr.who.icon && hr.who.emoji)
                app: s.app
                ws: s.ws
                user: hr.h.user
                url: hr.who.app ? hr.who.icon : ""
                name: hr.h.user ? "" : s.author(hr.h)
                x: s.t.sp(18)
                y: s.t.sp(9)
                size: s.t.sp(30)
              }
              EmojiIcon {
                visible: hr.who.app && !hr.who.icon && !!hr.who.emoji
                app: s.app
                ws: s.ws
                name: hr.who.emoji || ""
                x: s.t.sp(18)
                y: s.t.sp(9)
                size: s.t.sp(30)
              }
              Column {
                id: hrCol
                x: s.t.sp(59)
                y: s.t.sp(7)
                width: parent.width - x - s.t.sp(20)
                spacing: s.t.sp(2)
                Item {
                  width: parent.width
                  height: hrName.implicitHeight
                  Text {
                    id: hrName
                    width: Math.min(implicitWidth, parent.width * 0.5)
                    text: s.author(hr.h)
                    textFormat: Text.PlainText
                    color: s.t.fgBright
                    font.family: s.t.font
                    font.pixelSize: s.t.fsText - 1
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    anchors.left: hrName.right
                    anchors.leftMargin: s.t.sp(8)
                    anchors.right: hrDay.left
                    anchors.rightMargin: s.t.sp(8)
                    anchors.baseline: hrName.baseline
                    text: s.place(hr.h) + (hr.h.threadTs ? s.app.tr(" · in a thread", " · numa conversa") : "")
                    textFormat: Text.PlainText
                    color: s.t.fgDim
                    font.family: s.t.font
                    font.pixelSize: s.t.fsSmall
                    elide: Text.ElideRight
                  }
                  Text {
                    id: hrDay
                    anchors.right: parent.right
                    anchors.baseline: hrName.baseline
                    text: U.shortStamp(hr.h.ts, s.app.lang, s.app.clock24)
                    color: s.t.fgDim
                    font.family: s.t.font
                    font.pixelSize: s.t.fsTiny
                  }
                }
                // Three lines at most (rich text doesn't elide: it's clipped).
                Item {
                  width: parent.width
                  height: Math.min(hrText.implicitHeight, Math.ceil(hitFm.lineSpacing * 3) + 1)
                  clip: true
                  Text {
                    id: hrText
                    width: parent.width
                    text: s.hitHtml(hr.h)
                    textFormat: Text.RichText
                    color: s.t.fgSoft
                    font.family: s.t.font
                    font.pixelSize: s.t.fsSmall + 1
                    wrapMode: Text.Wrap
                  }
                }
              }
            }
          }
        }
      }

      Rectangle { visible: s.wide; x: list.width; width: 1; height: parent.height; color: s.t.line }

      // -------------------------------------------------------- preview
      Item {
        id: previewArea
        visible: s.wide
        x: list.width + 1
        width: parent.width - x
        height: parent.height
        clip: true
        Rectangle { anchors.fill: parent; color: s.t.alpha(s.t.pane, 0.35) }
        Loader {
          anchors.fill: parent
          active: s.wide
          sourceComponent: !s.selRow ? emptyPrevC : ({ hit: hitPrevC, conv: convPrevC, person: personPrevC })[s.selRow.kind] || emptyPrevC
        }
      }
    }

    // ------------------------------------------------------------ hints
    Item {
      id: foot
      anchors.bottom: parent.bottom
      width: parent.width
      height: s.t.sp(32)
      Rectangle { width: parent.width; height: 1; color: s.t.line }
      Text {
        x: s.t.sp(20)
        width: parent.width - x - status.implicitWidth - s.t.sp(40)
        anchors.verticalCenter: parent.verticalCenter
        text: "↑↓ " + s.app.tr("move", "mover") + "  ·  Enter " + s.app.tr("open", "abrir") + "  ·  Tab " + s.app.tr("section", "seção")
              + ((s.tab === "all" || s.tab === "messages") ? "  ·  Ctrl+S " + (s.sort === "score" ? s.app.tr("by date", "por data") : s.app.tr("by relevance", "por relevância")) : "")
              + "  ·  Esc " + (input.text !== "" ? s.app.tr("clear", "limpar") : s.app.tr("close", "fechar"))
        color: s.t.fgDim
        font.family: s.t.font
        font.pixelSize: s.t.fsTiny
        elide: Text.ElideRight
      }
      Text {
        id: status
        anchors.right: parent.right
        anchors.rightMargin: s.t.sp(20)
        anchors.verticalCenter: parent.verticalCenter
        text: { s.msgRev; s.query; s.sort; msgTimer.running; var e = s.entry(); return s.isSearching() ? s.app.tr("Searching…", "Buscando…") : (e && e.error ? e.error : "") }
        textFormat: Text.PlainText
        color: { s.msgRev; s.query; s.sort; var e = s.entry(); return e && e.error ? s.t.red : s.t.fgDim }
        font.family: s.t.font
        font.pixelSize: s.t.fsTiny
        font.italic: true
      }
    }
  }

  FontMetrics { id: hitFm; font.family: s.t.font; font.pixelSize: s.t.fsSmall + 1 }

  // A soft pulse for "Searching…".
  QtObject {
    id: busyPulse
    property real v: 0
    property NumberAnimation anim: NumberAnimation { target: busyPulse; property: "v"; from: 0; to: 1; duration: 700; loops: Animation.Infinite; easing.type: Easing.InOutSine; running: s.searching }
  }

  // ---------------------------------------------------------------- preview views
  Component {
    id: emptyPrevC
    Item {
      Column {
        anchors.centerIn: parent
        width: parent.width - s.t.sp(60)
        spacing: s.t.sp(10)
        Glyph { anchors.horizontalCenter: parent.horizontalCenter; app: s.app; icon: "󱎸"; size: s.t.px(40); color: s.t.alpha(s.t.fgDim, 0.6) }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: s.query ? s.app.tr("Nothing to preview", "Nada para mostrar") : s.app.tr("Find messages, channels and people. Slack's modifiers work too: in:#channel, from:@someone, has:link, before:, after:", "Encontre mensagens, canais e pessoas. Os modificadores do Slack também funcionam: in:#canal, from:@alguém, has:link, before:, after:")
          color: s.t.fgDim
          font.family: s.t.font
          font.pixelSize: s.t.fsSmall + 1
          wrapMode: Text.Wrap
        }
      }
    }
  }

  // Messages under a preview, read-only.
  component PreviewMessages: Column {
    id: pm
    property var app: Reg.service
    property var win
    property var ws
    property var ctx
    property string conv: ""
    property var msgs: []
    property string hitTs: ""
    property string hitText: ""   // the hit's text with Slack's highlight marks
    property bool thread: false
    readonly property var t: app.theme
    readonly property var rows: {
      var rs = Model.messageRows(pm.msgs || [], { newTs: "", conv: pm.conv }, null)
      return rs.map(function(r, i) {
        return { key: r.key, kind: r.kind, msg: r.msg, run: r.run, header: r.header || (pm.thread && i === 1), day: r.day, isNew: false, pinned: r.pinned }
      })
    }
    enabled: false
    function hitItem() {
      for (var i = 0; i < rep.count; i++) { var it = rep.itemAt(i); if (it && it.isHit) return it }
      return null
    }
    Repeater {
      id: rep
      model: pm.rows
      delegate: Column {
        id: pmRow
        required property var modelData
        required property int index
        readonly property bool isHit: pm.hitTs !== "" && !!pmRow.modelData.msg && (pmRow.modelData.msg.ts === pm.hitTs || (!!pmRow.modelData.run && pmRow.modelData.run.some(function(x) { return x.ts === pm.hitTs })))
        width: pm.width
        Item {
          width: parent.width
          height: pmItem.implicitHeight
          Rectangle {
            visible: pmRow.isHit
            y: pmRow.modelData.day ? pm.t.sp(40) : 0
            width: parent.width
            height: parent.height - y
            color: pm.t.alpha(pm.t.yellow, 0.09)
            Rectangle { width: pm.t.sp(3); height: parent.height; color: pm.t.yellow }
          }
          MessageItem {
            id: pmItem
            width: parent.width
            app: pm.app
            win: pm.win
            ws: pm.ws
            conv: pm.conv
            ctx: pm.ctx
            row: pmRow.isHit && pm.hitText !== "" && pmRow.modelData.kind === "msg"
              ? ({ key: pmRow.modelData.key, kind: "msg", msg: Model.patch(pmRow.modelData.msg, { text: pm.hitText, blocks: [] }), header: pmRow.modelData.header, day: pmRow.modelData.day, isNew: false, pinned: pmRow.modelData.pinned })
              : pmRow.modelData
            marks: pmRow.isHit && pm.hitText !== "" ? ({ color: pm.t.html.meText, bg: pm.t.html.meBg }) : null
            inThread: pm.thread
          }
        }
        // After a thread's parent: how many replies it has.
        Item {
          visible: pm.thread && pmRow.index === 0 && !!pmRow.modelData.msg && pmRow.modelData.msg.replyCount > 0
          width: parent.width
          height: visible ? pm.t.sp(30) : 0
          Text {
            id: repliesText
            x: pm.t.sp(20)
            anchors.verticalCenter: parent.verticalCenter
            text: pmRow.modelData.msg ? (pmRow.modelData.msg.replyCount === 1 ? pm.app.tr("1 reply", "1 resposta") : pmRow.modelData.msg.replyCount + pm.app.tr(" replies", " respostas")) : ""
            color: pm.t.fgDim
            font.family: pm.t.font
            font.pixelSize: pm.t.fsSmall
          }
          Rectangle { anchors.left: repliesText.right; anchors.leftMargin: pm.t.sp(10); anchors.right: parent.right; anchors.rightMargin: pm.t.sp(20); anchors.verticalCenter: parent.verticalCenter; height: 1; color: pm.t.line }
        }
      }
    }
  }

  // A conversation's sign, in the list and the previews.
  component ConvIcon: Item {
    id: ci
    property var app: Reg.service
    property var ws
    property var e
    property int size: 20
    property color ink: app.theme.fgSoft
    property color ring: app.theme.popup
    readonly property var t: app.theme
    width: size
    height: size
    Glyph {
      visible: !!ci.e && ci.e.ckind !== "im" && ci.e.ckind !== "mpim"
      anchors.centerIn: parent
      app: ci.app
      icon: !ci.e ? "" : (ci.e.archived ? "󰀼" : (ci.e.ckind === "private" ? "󰌾" : "#"))
      size: ci.e && ci.e.ckind === "channel" && !ci.e.archived ? Math.round(ci.size * 0.9) : Math.round(ci.size * 0.8)
      font.bold: !!ci.e && ci.e.ckind === "channel"
      color: ci.ink
    }
    Avatar {
      visible: !!ci.e && ci.e.ckind === "im"
      app: ci.app
      ws: ci.ws
      user: ci.e && ci.e.ckind === "im" ? ci.e.user : ""
      size: ci.size
      showPresence: true
      ring: ci.ring
      round: 0.25
      enabled: false
    }
    Rectangle {
      visible: !!ci.e && ci.e.ckind === "mpim"
      anchors.fill: parent
      radius: Math.round(width * 0.25)
      color: ci.t.alpha(ci.t.fg, 0.14)
      Text {
        anchors.centerIn: parent
        text: ci.e ? String(Math.max(2, ci.e.n || 2)) : ""
        color: ci.ink
        font.family: ci.t.font
        font.pixelSize: Math.round(ci.size * 0.55)
        font.bold: true
      }
    }
  }

  // ------------------------------------------------------------ a message hit
  Component {
    id: hitPrevC
    Item {
      id: hp
      readonly property var h: s.selRow && s.selRow.kind === "hit" ? s.selRow.hit : null
      readonly property var pd: s.pv
      onPdChanged: Qt.callLater(hp.settle)
      function settle() {
        if (!hp.h || !hp.pd || hp.pd.loading) return
        var it = hpMsgs.hitItem()
        if (!it) return
        var y = hpMsgs.y + it.y
        hpFlick.contentY = Math.max(0, Math.min(y - hpFlick.height / 3, hpFlick.contentHeight - hpFlick.height))
      }

      Item {
        id: hpHead
        width: parent.width
        height: s.t.sp(60)
        Column {
          x: s.t.sp(20)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - x - hpOpen.width - s.t.sp(36)
          spacing: s.t.sp(2)
          Text {
            width: parent.width
            text: hp.h ? s.place(hp.h) : ""
            textFormat: Text.PlainText
            color: s.t.fgBright
            font.family: s.t.font
            font.pixelSize: s.t.fsTitle
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: hp.h ? U.relative(hp.h.ts, s.app.lang, s.app.clock24) + (hp.h.threadTs ? s.app.tr("  ·  in a thread", "  ·  numa conversa") : "") : ""
            color: s.t.fgDim
            font.family: s.t.font
            font.pixelSize: s.t.fsSmall
            elide: Text.ElideRight
          }
        }
        SButton {
          id: hpOpen
          app: s.app
          small: true
          anchors.right: parent.right
          anchors.rightMargin: s.t.sp(16)
          anchors.verticalCenter: parent.verticalCenter
          icon: hp.h && hp.h.threadTs ? "󰍪" : "󰁔"
          text: hp.h && hp.h.threadTs ? s.app.tr("Open thread", "Abrir conversa") : s.app.tr("Jump to message", "Ir para a mensagem")
          onClicked: s.openRow(s.selRow)
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: s.t.line }
      }

      Flickable {
        id: hpFlick
        y: hpHead.height
        width: parent.width
        height: parent.height - y
        clip: true
        contentWidth: width
        contentHeight: hpMsgs.y + hpMsgs.implicitHeight + s.t.sp(16)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThinScroll { app: s.app }
        PreviewMessages {
          id: hpMsgs
          y: s.t.sp(6)
          width: hpFlick.width
          app: s.app
          win: s.win
          ws: s.ws
          ctx: s.ctx
          conv: hp.h ? hp.h.conv : ""
          msgs: hp.pd ? hp.pd.msgs : []
          hitTs: hp.h ? hp.h.ts : ""
          hitText: hp.h && hp.h.text && hp.h.text.indexOf("\ue000") >= 0 ? hp.h.text : ""
          thread: !!hp.h && hp.h.threadTs !== ""
          onRowsChanged: Qt.callLater(hp.settle)
        }
        MouseArea { width: hpFlick.contentWidth; height: hpFlick.contentHeight; onDoubleClicked: s.openRow(s.selRow) }
      }

      Text {
        visible: !hp.pd || hp.pd.loading || hp.pd.msgs.length === 0
        anchors.centerIn: hpFlick
        text: !hp.pd || hp.pd.loading ? s.app.tr("Loading…", "Carregando…") : (hp.pd.error || s.app.tr("Couldn't load this message", "Não deu para carregar esta mensagem"))
        textFormat: Text.PlainText
        color: s.t.fgDim
        font.family: s.t.font
        font.pixelSize: s.t.fsSmall + 1
        font.italic: true
      }
    }
  }

  // ------------------------------------------------------------ a conversation
  Component {
    id: convPrevC
    Item {
      id: cp
      readonly property var e: s.selRow && s.selRow.kind === "conv" ? s.selRow.e : null
      readonly property var pd: s.pv
      readonly property var live: cp.e ? s.ws.conv(cp.e.id) : null
      readonly property var info: cp.pd && cp.pd.info ? cp.pd.info : cp.live
      readonly property bool member: !!cp.live && !cp.live.guest && cp.live.member !== false
      readonly property bool im: !!cp.e && cp.e.ckind === "im"
      readonly property var u: cp.im ? s.ws.user(cp.e.user) : null
      readonly property var st: cp.im ? s.ws.statusOf(cp.e.user) : null
      readonly property int members: (cp.info && cp.info.numMembers) || (cp.e ? cp.e.members : 0)
      readonly property var msgs: cp.e ? s.previewMsgs(cp.e.id, cp.pd) : []

      Flickable {
        id: cpFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: cpCol.implicitHeight + s.t.sp(24)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThinScroll { app: s.app }

        Column {
          id: cpCol
          width: cpFlick.width
          topPadding: s.t.sp(20)
          spacing: s.t.sp(10)

          Item {
            x: s.t.sp(20)
            width: parent.width - s.t.sp(40)
            height: Math.max(cpIcon.height, cpTitle.implicitHeight)
            Rectangle {
              id: cpIcon
              width: s.t.sp(44)
              height: width
              radius: Math.max(6, s.t.radiusSmall)
              color: cp.im ? "transparent" : s.t.alpha(s.t.fg, 0.08)
              ConvIcon { anchors.centerIn: parent; app: s.app; ws: s.ws; e: cp.e; size: cp.im ? s.t.sp(44) : s.t.sp(26); ink: s.t.fgBright; ring: s.t.popup }
            }
            Column {
              id: cpTitle
              anchors.left: cpIcon.right
              anchors.leftMargin: s.t.sp(14)
              anchors.right: parent.right
              anchors.verticalCenter: cpIcon.verticalCenter
              spacing: s.t.sp(3)
              Row {
                width: parent.width
                spacing: s.t.sp(8)
                Text {
                  id: cpName
                  width: Math.min(implicitWidth, parent.width - (cpEmoji.visible ? cpEmoji.width + s.t.sp(8) : 0))
                  text: cp.e ? cp.e.label : ""
                  textFormat: Text.PlainText
                  color: s.t.fgBright
                  font.family: s.t.font
                  font.pixelSize: s.t.fsHeader
                  font.bold: true
                  elide: Text.ElideRight
                }
                EmojiIcon {
                  id: cpEmoji
                  visible: !!cp.st && (cp.st.emoji !== "" || cp.st.unicode !== "")
                  anchors.verticalCenter: cpName.verticalCenter
                  app: s.app
                  ws: s.ws
                  name: cp.st ? cp.st.emoji.replace(/:/g, "") : ""
                  glyph: cp.st && cp.st.unicode ? Emoji.fromHex(cp.st.unicode) : ""
                  size: s.t.sp(18)
                  HoverHandler { id: cpStatusHover }
                  StatusTip { app: s.app; ws: s.ws; status: cp.st; hovered: cpStatusHover.hovered }
                }
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: {
                  if (!cp.e) return ""
                  if (cp.im) return cp.u ? [cp.u.title || "", cp.st ? cp.st.text : ""].filter(function(x) { return x }).join("  ·  ") : ""
                  var bits = []
                  if (cp.e.archived) bits.push(s.app.tr("Archived", "Arquivado"))
                  if (!cp.member && cp.e.ckind === "channel") bits.push(s.app.tr("You are not a member", "Você não participa"))
                  if (cp.e.ckind === "private") bits.push(s.app.tr("Private channel", "Canal privado"))
                  if (cp.e.ckind === "mpim") bits.push(s.app.tr("Group conversation", "Conversa em grupo"))
                  if (cp.members && cp.e.ckind !== "mpim") bits.push(s.memberCount(cp.members))
                  return bits.join("  ·  ")
                }
                textFormat: Text.PlainText
                color: s.t.fgDim
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall
                wrapMode: Text.Wrap
              }
            }
          }

          Row {
            x: s.t.sp(20)
            spacing: s.t.sp(8)
            SButton {
              app: s.app
              small: true
              kind: "primary"
              icon: "󰁔"
              text: cp.member || cp.im || cp.e && cp.e.ckind === "mpim" ? s.app.tr("Open", "Abrir") : s.app.tr("View channel", "Ver canal")
              onClicked: s.openRow(s.selRow)
            }
            SButton {
              visible: !!cp.e && cp.e.ckind === "channel" && !cp.member && !cp.e.archived
              app: s.app
              small: true
              text: s.app.tr("Join channel", "Entrar no canal")
              onClicked: { var id = cp.e.id; s.ws.join(id); s.ws.open(id); s.closed() }
            }
          }

          // Topic and description, channels only.
          Repeater {
            model: cp.im || !cp.info ? [] : [
              { label: s.app.tr("Topic", "Tópico"), text: cp.info.topic || "" },
              { label: s.app.tr("Description", "Descrição"), text: cp.info.purpose || cp.e.purpose || "" }
            ].filter(function(x) { return x.text })
            delegate: Column {
              required property var modelData
              x: s.t.sp(20)
              width: cpCol.width - s.t.sp(40)
              spacing: s.t.sp(2)
              Text { text: modelData.label; color: s.t.fgDim; font.family: s.t.font; font.pixelSize: s.t.fsSmall; font.bold: true }
              Text {
                width: parent.width
                text: Md.flat({ text: modelData.text, blocks: [], files: [], attachments: [] }, s.ctx, 400)
                textFormat: Text.PlainText
                color: s.t.fg
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall + 1
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
              }
            }
          }

          Item { width: 1; height: s.t.sp(2) }
          Rectangle { width: parent.width; height: 1; color: s.t.line }
          Text {
            x: s.t.sp(20)
            text: s.app.tr("Latest messages", "Mensagens recentes")
            color: s.t.fgDim
            font.family: s.t.font
            font.pixelSize: s.t.fsSmall
            font.bold: true
          }
          Text {
            visible: cp.msgs.length === 0
            x: s.t.sp(20)
            text: cp.pd && cp.pd.loading ? s.app.tr("Loading…", "Carregando…") : (cp.pd && cp.pd.error ? cp.pd.error : s.app.tr("No messages yet", "Nenhuma mensagem ainda"))
            textFormat: Text.PlainText
            color: s.t.fgDim
            font.family: s.t.font
            font.pixelSize: s.t.fsSmall + 1
            font.italic: true
          }
          PreviewMessages {
            width: cpCol.width
            app: s.app
            win: s.win
            ws: s.ws
            ctx: s.ctx
            conv: cp.e ? cp.e.id : ""
            msgs: cp.msgs
          }
        }
        MouseArea { width: cpFlick.contentWidth; height: cpFlick.contentHeight; z: -1; onDoubleClicked: s.openRow(s.selRow) }
      }
    }
  }

  // ------------------------------------------------------------ a person
  Component {
    id: personPrevC
    Item {
      id: pp
      readonly property string uid: s.selRow && s.selRow.kind === "person" ? s.selRow.uid : ""
      readonly property var u: pp.uid ? s.ws.user(pp.uid) : null
      // A deactivated account: no presence, status or clock; its DM's archives.
      readonly property bool gone: !!pp.u && !!pp.u.deleted
      readonly property var st: pp.uid && !pp.gone ? s.ws.statusOf(pp.uid) : null
      readonly property var pd: s.pv
      readonly property string dm: pp.uid ? s.dmOf(pp.uid) : ""
      readonly property var msgs: pp.dm ? s.previewMsgs(pp.dm, pp.pd) : []
      readonly property bool self: !!s.ws && pp.uid === s.ws.me.id
      readonly property string localTime: {
        if (!pp.u || pp.gone || typeof pp.u.tzOffset !== "number") return ""
        var here = new Date()
        return U.time(new Date(here.getTime() + (pp.u.tzOffset + here.getTimezoneOffset() * 60) * 1000), s.app.clock24)
      }

      Flickable {
        id: ppFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: ppCol.implicitHeight + s.t.sp(24)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThinScroll { app: s.app }

        Column {
          id: ppCol
          width: ppFlick.width
          topPadding: s.t.sp(22)
          spacing: s.t.sp(8)

          Row {
            x: s.t.sp(20)
            width: parent.width - s.t.sp(40)
            spacing: s.t.sp(16)
            Avatar {
              id: ppPhoto
              app: s.app
              ws: s.ws
              user: pp.uid
              url: pp.u ? (pp.u.avatar192 || pp.u.avatar || "") : ""
              size: s.t.sp(96)
              round: 0.12
              enabled: false
            }
            Column {
              width: parent.width - ppPhoto.width - s.t.sp(16)
              anchors.verticalCenter: ppPhoto.verticalCenter
              spacing: s.t.sp(4)
              Row {
                width: parent.width
                spacing: s.t.sp(8)
                Text {
                  id: ppName
                  width: Math.min(implicitWidth, parent.width - s.t.sp(30))
                  text: pp.u ? pp.u.name + (pp.self ? s.app.tr(" (you)", " (você)") : "") : ""
                  textFormat: Text.PlainText
                  color: s.t.fgBright
                  font.family: s.t.font
                  font.pixelSize: s.t.fsHeader + 2
                  font.bold: true
                  elide: Text.ElideRight
                }
                EmojiIcon {
                  visible: !!pp.st && (pp.st.emoji !== "" || pp.st.unicode !== "")
                  anchors.verticalCenter: ppName.verticalCenter
                  app: s.app
                  ws: s.ws
                  name: pp.st ? pp.st.emoji.replace(/:/g, "") : ""
                  glyph: pp.st && pp.st.unicode ? Emoji.fromHex(pp.st.unicode) : ""
                  size: s.t.sp(20)
                  HoverHandler { id: ppStatusHover }
                  StatusTip { app: s.app; ws: s.ws; status: pp.st; hovered: ppStatusHover.hovered }
                }
              }
              Text {
                visible: !!pp.u && !!pp.u.real && pp.u.real !== pp.u.name
                width: parent.width
                text: pp.u ? (pp.u.real || "") : ""
                textFormat: Text.PlainText
                color: s.t.fgDim
                font.family: s.t.font
                font.pixelSize: s.t.fsSmall + 1
                elide: Text.ElideRight
              }
              Text {
                visible: !!pp.u && !!pp.u.title
                width: parent.width
                text: pp.u ? (pp.u.title || "") : ""
                textFormat: Text.PlainText
                color: s.t.fg
                font.family: s.t.font
                font.pixelSize: s.t.fsText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
              Row {
                spacing: s.t.sp(7)
                PresenceDot {
                  app: s.app
                  anchors.verticalCenter: parent.verticalCenter
                  size: s.t.sp(10)
                  ring: "transparent"
                  active: !pp.gone && s.ws.isActive(pp.uid)
                  paused: !pp.gone && s.ws.isPaused(pp.uid)
                }
                Text {
                  text: pp.gone ? s.app.tr("Deactivated account", "Conta desativada")
                        : (s.ws.isActive(pp.uid) ? s.app.tr("Active", "Ativo") : s.app.tr("Away", "Ausente")) + (pp.localTime ? "  ·  " + pp.localTime + s.app.tr(" local time", " hora local") : "")
                  color: s.t.fgSoft
                  font.family: s.t.font
                  font.pixelSize: s.t.fsSmall
                }
              }
            }
          }

          Row {
            visible: !!pp.st && pp.st.text !== ""
            x: s.t.sp(20)
            width: parent.width - s.t.sp(40)
            spacing: s.t.sp(8)
            topPadding: s.t.sp(4)
            EmojiIcon {
              app: s.app
              ws: s.ws
              name: pp.st ? pp.st.emoji.replace(/:/g, "") : ""
              glyph: pp.st && pp.st.unicode ? Emoji.fromHex(pp.st.unicode) : ""
              size: s.t.sp(16)
            }
            Text {
              width: parent.width - s.t.sp(24)
              text: pp.st ? pp.st.text + (pp.st.exp ? "  ·  " + U.untilLabel(pp.st.exp, s.app.lang, s.app.clock24) : "") : ""
              textFormat: Text.PlainText
              color: s.t.fg
              font.family: s.t.font
              font.pixelSize: s.t.fsSmall + 1
              wrapMode: Text.Wrap
            }
          }

          Row {
            x: s.t.sp(20)
            spacing: s.t.sp(8)
            topPadding: s.t.sp(6)
            // A deactivated account's DM opens as its archives (when there is one).
            SButton {
              visible: !pp.gone || pp.dm !== ""
              app: s.app
              small: true
              kind: "primary"
              icon: pp.gone ? "󰀼" : "󰍥"
              text: pp.gone ? s.app.tr("View archives", "Ver arquivos") : s.app.tr("Message", "Mensagem")
              onClicked: s.openRow(s.selRow)
            }
            SButton {
              app: s.app
              small: true
              icon: "󰀄"
              text: s.app.tr("View profile", "Ver perfil")
              onClicked: { s.ws.profileUser = pp.uid; s.ws.thread = null; s.closed() }
            }
          }

          Item { width: 1; height: s.t.sp(6) }
          Rectangle { visible: pp.dm !== ""; width: parent.width; height: 1; color: s.t.line }
          Text {
            visible: pp.dm !== ""
            x: s.t.sp(20)
            text: s.app.tr("Latest messages", "Mensagens recentes")
            color: s.t.fgDim
            font.family: s.t.font
            font.pixelSize: s.t.fsSmall
            font.bold: true
          }
          Text {
            visible: pp.dm !== "" && pp.msgs.length === 0
            x: s.t.sp(20)
            text: pp.pd && pp.pd.loading ? s.app.tr("Loading…", "Carregando…") : s.app.tr("No messages yet", "Nenhuma mensagem ainda")
            color: s.t.fgDim
            font.family: s.t.font
            font.pixelSize: s.t.fsSmall + 1
            font.italic: true
          }
          PreviewMessages {
            visible: pp.dm !== ""
            width: ppCol.width
            app: s.app
            win: s.win
            ws: s.ws
            ctx: s.ctx
            conv: pp.dm
            msgs: pp.msgs
          }
        }
        MouseArea { width: ppFlick.contentWidth; height: ppFlick.contentHeight; z: -1; onDoubleClicked: s.openRow(s.selRow) }
      }
    }
  }
}
