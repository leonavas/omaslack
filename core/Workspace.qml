import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Markup.js" as Markup
import "../lib/Mrkdwn.js" as Md
import "../lib/Emoji.js" as Emoji
import "../lib/Demo.js" as Demo

// One signed-in workspace: everything Slack told us about it, kept fresh
// by its socket and a slow poll, and every action the window can take on
// it. Views read the plain JS maps below through the getters, which also
// read the matching revision counter so bindings follow changes.
Item {
  id: root

  // ---------------------------------------------------------------- inputs
  required property var account      // {teamId, token, cookie, domain, name, userId}
  property var app: null             // the Service: settings, window, notifications

  readonly property string teamId: account.teamId || ""
  readonly property string lang: app ? app.lang : "en"
  readonly property bool clock24: app ? app.clock24 : true
  // The one on screen (the app falls back to the first while none is picked).
  readonly property bool foreground: app ? app.current === root : true
  readonly property bool focused: app ? (app.windowFocused && foreground) : false

  // ---------------------------------------------------------------- status
  property bool booted: false        // users + conversations known
  property bool live: false          // socket up
  property string authError: ""      // set when Slack refused the session
  property bool signedOut: false     // on its way out: nothing more is saved
  property string toast: ""
  property int toastSerial: 0

  signal authFailed(string error)
  signal notify(var info)
  signal historyUpdated(string conv)
  signal repliesUpdated(string key)
  signal jumpTo(string conv, string ts)

  // ---------------------------------------------------------------- data
  property var me: ({ id: account.userId || "", handle: "", name: "" })
  property var team: ({ id: account.teamId || "", name: account.name || "", domain: account.domain || "", icon: account.icon || "" })

  property var users: ({})
  property var handles: ({})
  property int usersRev: 0
  property var convs: ({})
  property int convsRev: 0
  property var counts: ({})
  property var threads: ({ unread: false, mentions: 0 })
  property int countsRev: 0
  property var sections: []
  property var stars: ({})
  property var openIms: null
  // The DMs with deactivated accounts (users.conversations' is_user_deleted):
  // out of the lists, as in Slack, but their archives open from search.
  // person id → the conversation, until one is opened (then in `convs`).
  property var goneDms: ({})
  property int sectionsRev: 0
  // Slack's "Active only" sidebar filter (sidebar_behavior
  // "hide_inactive_channels"): dormant channels leave the sidebar.
  property bool hideInactive: false
  property var prefs: ({})
  property string globalNotify: "everything"
  property bool prefsLoaded: false
  property var customEmoji: ({})
  property var emojiAliases: ({})
  property int emojiRev: 0
  property var commands: []
  property var saved: ({})
  property int savedRev: 0
  property var vips: ({})
  property var dnd: null              // {until, snooze} while paused
  property bool away: false
  property var presence: ({})
  property bool presenceLive: false
  property int presenceRev: 0
  property var othersDnd: ({})
  property var typing: ({})
  property int typingRev: 0
  property var directory: ({ at: 0, chans: [] })
  property int directoryRev: 0
  property bool sidebarAvatars: true
  property var collapsed: ({})
  property int collapsedRev: 0
  property var drafts: ({})
  property int draftsRev: 0
  property var sentLog: []            // [{conv, ts, text}] for Drafts & sent

  // messages
  property var histories: ({})        // conv → {msgs, noOlder, loading, detached}
  property int historyRev: 0
  property var fromCache: ({})        // conv → true while its messages are the cache's (until fetchHistory replaces them)
  property var replies: ({})          // "conv/ts" → {msgs, loading}
  property int repliesRev: 0
  property var pins: ({})             // conv → [{msg, by, created}]
  property int pinsRev: 0
  property var newLines: ({})         // conv → ts of the New line
  property var threadsView: ({ list: [], total: 0, loaded: false, loading: false })
  property int threadsRev: 0
  property var localFiles: ({})       // url → local path (downloaded with auth)
  property int filesRev: 0

  // navigation
  property string current: ""
  property string view: "conv"        // conv | threads | activity | saved | dms | drafts
  property var thread: null           // {conv, ts}
  property string profileUser: ""
  property var editing: null          // {conv, ts}
  property string flashTs: ""
  property var backStack: []
  property var forwardStack: []
  property var recents: []            // conversations opened lately, newest first: the cache keeps their latest messages
  readonly property int maxRecents: 30

  // ---------------------------------------------------------------- derived
  readonly property var attention: {
    root.countsRev; root.convsRev
    return Model.attention({ counts: root.counts, convs: root.convs, users: root.users, prefs: root.prefs,
                             threads: root.threads })
  }

  readonly property var sidebarRows: {
    root.countsRev; root.convsRev; root.usersRev; root.sectionsRev; root.collapsedRev; root.draftsRev
    var rules = root.sidebarRules
    return Model.sidebar({
      lang: root.lang, me: root.me.id, convs: root.convs, users: root.users, handles: root.handles, counts: root.counts,
      sections: root.sections, stars: root.stars, openIms: root.openIms, prefs: root.prefsLoaded ? root.prefs : {},
      current: root.current, view: root.view, focused: root.focused, collapsed: root.collapsed, drafts: root.drafts,
      draftCount: Object.keys(root.drafts).length, threads: root.threads, hideInactive: root.hideInactive, recents: root.recents,
      sidebarBehavior: rules.sidebarBehavior, sectionPrefs: rules.sectionPrefs, paidTeam: rules.paidTeam,
      canInvite: rules.canInvite, hideSlackbot: rules.hideSlackbot, invitePeople: rules.invitePeople
    })
  }

  // What Slack's sidebar rules read (Model.sidebar): the sidebar's "Show"
  // and each section's, the plan, whether you can invite people, and
  // whether the new Slackbot's link took its DM's place.
  readonly property var sidebarRules: {
    root.usersRev
    var pref = function(k) { return root.rawPrefs[k] !== undefined ? root.rawPrefs[k] : root.bootPrefs[k] }
    var behavior = pref("sidebar_behavior")
    var secs = pref("channel_sections")
    if (typeof secs === "string") { try { secs = JSON.parse(secs || "{}") } catch (e) { secs = {} } }
    var mine = root.users[root.me.id] || {}
    var tp = root.teamPrefs || {}
    return {
      // Until the prefs come, the cached "Active only".
      sidebarBehavior: typeof behavior === "string" ? behavior : (root.hideInactive ? "hide_inactive_channels" : ""),
      sectionPrefs: secs && typeof secs === "object" ? secs : {},
      paidTeam: root.teamPlan === null || root.teamPlan !== "",
      // Slack's canUserSeeInviteModal: an admin, or a full member when
      // invites aren't for admins only or can be requested.
      canInvite: !!mine.admin || (!mine.guest && (tp.invites_only_admins !== true || tp.invite_requests_enabled === true)),
      // Slack asks permissions.info (an edge API) for the new Slackbot;
      // its link's "New" tag seen, or big mode had, tells it here.
      hideSlackbot: pref("enable_slackbot_view") !== false && (pref("has_seen_slackbot_ai_new_tag") === true || pref("had_slackbot_big_mode_access") === true),
      // "Invite people" over "Add coworkers": a workspace (not an org's)
      // made in March 3–27 2025 or since April 1 2025 (Slack's invite
      // refresh experiments).
      invitePeople: !root.teamEnterprise && ((root.teamCreated >= 1741033260 && root.teamCreated <= 1743102122) || root.teamCreated >= 1743534000)
    }
  }

  // Unread conversations for the bar's hover card, newest first:
  // [{conv, label, kind, user, mentions, latest, msg}].
  function unreadList(max) {
    root.countsRev; root.convsRev; root.lastRev
    var out = []
    for (var id in root.counts) {
      var k = root.counts[id], c = root.convs[id]
      if (!c || c.archived || !(k.unread || k.mentions > 0)) continue
      var dm = Model.isDm(c)
      if (!dm && !(k.mentions > 0) && Model.quietPref(root.prefs[id])) continue
      out.push({ conv: id, label: root.convLabel(id), kind: c.kind, user: c.user || "", mentions: dm ? Math.max(1, k.mentions || 0) : (k.mentions || 0),
                 latest: k.latest || "", msg: root.lastMsgs[id] || null })
    }
    out.sort(function(a, b) { return U.cmpTs(b.latest, a.latest) })
    return out.slice(0, max || 6)
  }

  // The last message seen per conversation (socket or history; not the
  // cache's, which can be behind).
  property var lastMsgs: ({})
  property int lastRev: 0
  onHistoryUpdated: conv => {
    var h = root.histories[conv]
    if (h && h.msgs.length && !h.detached && !root.fromCache[conv]) {
      var m = h.msgs[h.msgs.length - 1]
      if (root.lastMsgs[conv] !== m) { root.lastMsgs[conv] = m; root.lastRev++ }
    }
  }
  function fetchLast(conv) {
    if (root.lastMsgs[conv] || root._asked["last" + conv]) return
    root._asked["last" + conv] = true
    root.api("conversations.history", { channel: conv, limit: 1 }, function(b) {
      var m = (b.messages || [])[0]
      if (m) { root.lastMsgs[conv] = Model.parseMessage(m); root.lastRev++ }
      delete root._asked["last" + conv]
    }, function() { delete root._asked["last" + conv] })
  }

  // ---------------------------------------------------------------- transport
  Transport {
    id: wire
    enabled: !root.account.demo
    token: root.account.token || ""
    cookie: root.account.cookie || ""
    onSocketOpened: root.onSocketUp()
    onSocketClosed: reason => root.onSocketDown(reason)
    onSocketMessage: data => root.onEvent(data)
  }

  readonly property var authErrors: ["invalid_auth", "not_authed", "token_revoked", "token_expired", "account_inactive"]

  // SLACKQS_READONLY=1 (development against a real workspace): only
  // reading methods reach Slack.
  readonly property bool readOnlyMode: Quickshell.env("SLACKQS_READONLY") === "1"
  readonly property var readMethods: ["auth.test", "team.info", "users.list", "users.info", "users.getPresence", "users.conversations",
    "users.channelSections.list", "stars.list", "users.priority.list", "client.counts", "client.userBoot", "client.getWebSocketURL",
    "rtm.connect", "emoji.list", "commands.list", "users.prefs.get", "dnd.info", "dnd.teamInfo", "saved.list", "conversations.history",
    "conversations.replies", "conversations.info", "conversations.members", "conversations.list", "pins.list", "reactions.get",
    "search.messages", "subscriptions.thread.getView", "chat.scheduledMessages.list", "bots.info", "apps.profile.get", "activity.feed", "files.list", "search.files", "admin.apps.requests.list"]

  function api(method, params, ok, fail) {
    if (root.readOnlyMode && root.readMethods.indexOf(method) < 0) {
      console.log("omaslack: read-only, skipped", method)
      Qt.callLater(function() { if (fail) fail("readonly") })
      return
    }
    if (root.account.demo) {
      var answer = Demo.respond(method, params || {}, root.me.id || "U0ME", root.account.teamId)
      Qt.callLater(function() {
        if (answer && answer.ok) { if (ok) ok(answer) }
        else if (fail) fail(answer ? answer.error : "demo")
      })
      return
    }
    wire.call(method, params || {}, function(r) {
      if (r.ok && r.body && r.body.ok) { if (ok) ok(r.body); return }
      var err = r.ok ? ((r.body && r.body.error) || ("http " + r.status)) : (r.error || "network")
      if (root.authErrors.indexOf(err) >= 0 && root.authError === "") {
        root.authError = err
        root.authFailed(err)
      }
      if (fail) fail(err, r.body)
      else console.warn("omaslack:", method, err)
    })
  }

  function paginate(method, params, key, done, fail, eachPage) {
    var all = []
    function page(cursor) {
      var p = U.copy(params || {})
      if (cursor) p.cursor = cursor
      root.api(method, p, function(body) {
        var items = body[key] || []
        if (eachPage) eachPage(items, body)
        else all = all.concat(items)
        var next = body.response_metadata && body.response_metadata.next_cursor
        if (next) page(next)
        else if (done) done(all, body)
      }, fail)
    }
    page("")
  }

  function say(text) { root.toast = text; root.toastSerial++ }
  function tr(en, pt) { return root.lang === "pt-BR" ? pt : en }
  function errorText(err) {
    var code = String(err || "")
    var map = {
      not_authorized: tr("You don't have permission to do that.", "Você não tem permissão para isso."),
      restricted_action: tr("You don't have permission to do that.", "Você não tem permissão para isso."),
      missing_scope: tr("This session can't do that.", "Esta sessão não pode fazer isso."),
      name_taken: tr("That name is already taken.", "Esse nome já está em uso."),
      invalid_name: tr("Names can only have lowercase letters, numbers, - and _.", "Nomes só podem ter letras minúsculas, números, - e _."),
      invalid_name_specials: tr("Names can only have lowercase letters, numbers, - and _.", "Nomes só podem ter letras minúsculas, números, - e _."),
      invalid_name_maxlength: tr("Names can have at most 80 characters.", "Nomes podem ter no máximo 80 caracteres."),
      cant_leave_general: tr("Nobody can leave the general channel.", "Ninguém pode sair do canal geral."),
      cant_archive_general: tr("The general channel can't be archived.", "O canal geral não pode ser arquivado."),
      cant_delete_general: tr("The general channel can't be deleted.", "O canal geral não pode ser excluído."),
      last_member: tr("You're the last member: archive the channel instead.", "Você é o último membro: arquive o canal."),
      channel_not_found: tr("Channel not found.", "Canal não encontrado."),
      already_in_channel: tr("Already in the channel.", "Já está no canal."),
      ratelimited: tr("Slack asked to slow down. Try again in a moment.", "O Slack pediu para ir com calma. Tente de novo daqui a pouco."),
      network: tr("No connection to Slack.", "Sem conexão com o Slack."),
      app_access_restricted: tr("You don’t have permission to use this app. Contact your workspace admin for access.", "Você não tem permissão para usar este app. Entre em contato com o administrador do workspace para obter acesso."),
      request_already_resolved: tr("This request has already been handled.", "Esta solicitação já foi atendida."),
      not_an_admin: tr("You don't have permission to do that.", "Você não tem permissão para isso.")
    }
    if (code.indexOf("network") === 0) return map.network
    return map[code] || code.replace(/_/g, " ")
  }

  // ---------------------------------------------------------------- getters
  function user(id) { root.usersRev; return root.users[id] || null }
  function userName(id) {
    root.usersRev
    if (!id) return ""
    var u = root.users[id]
    if (u) return u.name
    root.lookup("user", id)
    return ""
  }
  function conv(id) { root.convsRev; return root.convs[id] || null }
  function convLabel(id) {
    root.convsRev; root.usersRev
    var c = root.convs[id]
    if (!c) {
      for (var i = 0; i < root.directory.chans.length; i++) if (root.directory.chans[i].id === id) return root.directory.chans[i].name
      return ""
    }
    return Model.label(c, root.users, root.me.id, root.handles, root.lang)
  }
  function countOf(id) { root.countsRev; return root.counts[id] || null }
  function isActive(uid) { root.presenceRev; return root.presence[uid] === true }
  function isPaused(uid) {
    root.presenceRev
    if (uid === root.me.id) return root.dnd !== null
    var d = root.othersDnd[uid]
    var now = Date.now() / 1000
    return !!d && d.start <= now && now < d.end
  }
  function statusOf(uid) { root.usersRev; return Model.status(root.users[uid]) }
  function history(conv) { root.historyRev; return root.histories[conv] || null }
  function repliesOf(conv, ts) { root.repliesRev; return root.replies[conv + "/" + ts] || null }
  function pinsOf(conv) { root.pinsRev; return root.pins[conv] || null }
  function isSaved(conv, ts) { root.savedRev; return !!root.saved[conv + "/" + ts] }
  function isStarred(conv) { root.sectionsRev; return !!root.stars[conv] }
  function notifyLevel(conv) {
    root.convsRev
    var p = root.prefs[conv] || {}
    if (p.muted) return "mute"
    var d = p.desktop || root.globalNotify
    return ["mentions", "mentions_dms", "nothing"].indexOf(d) >= 0 ? "mentions" : "all"
  }
  function isMuted(conv) { root.convsRev; var c = root.convs[conv]; return !Model.isDm(c) && !!(root.prefs[conv] && root.prefs[conv].muted) }
  // Out of the badges and the bar's rows (Model.quietPref); DMs never are.
  function isQuiet(conv) { root.convsRev; var c = root.convs[conv]; return !Model.isDm(c) && Model.quietPref(root.prefs[conv]) }
  function typingIn(conv) {
    root.typingRev
    var t = root.typing[conv] || {}
    var now = Date.now()
    var names = []
    for (var uid in t) if (t[uid] > now && uid !== root.me.id) names.push(root.userName(uid) || "?")
    return names
  }
  function draft(conv) { root.draftsRev; return root.drafts[conv] || "" }
  function localFile(url) { root.filesRev; return root.localFiles[url] || "" }

  // The renderer's view of this workspace (lib/Mrkdwn.js).
  function renderCtx(colors, emojiPx) {
    root.usersRev; root.convsRev; root.emojiRev
    return {
      me: root.me.id, lang: root.lang, clock24: root.clock24,
      user: function(id) { var u = root.users[id]; if (!u) root.lookup("user", id); return u ? u.name : "" },
      conv: function(id) {
        var c = root.convs[id]
        if (c) return { name: Model.label(c, root.users, root.me.id, root.handles, root.lang), private: c.kind === "private" }
        var d = root.directory.chans.filter(function(x) { return x.id === id })[0]
        if (d) return { name: d.name, private: false }
        root.lookup("conv", id)
        return null
      },
      custom: root.customEmoji, aliases: root.emojiAliases, slackEmoji: root.app ? root.app.slackEmoji : true,
      c: colors, emojiPx: emojiPx,
      ask: function(kind, id) { root.lookup(kind, id) }
    }
  }

  // ---------------------------------------------------------------- lookups
  property var _asked: ({})
  function lookup(kind, id) {
    if (!id || root._asked[kind + id]) return
    root._asked[kind + id] = true
    Qt.callLater(function() {
      if (kind === "user") {
        root.api("users.info", { user: id }, function(b) { root.applyUser(b.user); root.usersRev++ }, function() {})
      } else {
        root.api("conversations.info", { channel: id }, function(b) {
          var c = Model.parseConv(b.channel, null)
          if (c.kind === "channel" && !root.convs[c.id]) {
            var chans = root.directory.chans
            if (!chans.some(function(x) { return x.id === c.id })) chans.push({ id: c.id, name: c.name, archived: !!c.archived, members: c.numMembers || 0, updated: c.updated || 0 })
            root.directoryRev++
          }
          if (root.convs[c.id]) root.convs[c.id] = Model.parseConv(b.channel, root.convs[c.id])
          else root._others[c.id] = c
          root.convsRev++
        }, function() {})
      }
    })
  }
  property var _others: ({})

  // ---------------------------------------------------------------- apps
  // The apps that post here, by bot id: {name, icon, app, user}, from
  // bots.info for the messages that come without their name or picture
  // (webhooks, old integrations); kept with the cache, asked again once a
  // session when shown.
  property var bots: ({})
  property int botsRev: 0
  function bot(id) {
    root.botsRev
    if (!id) return null
    if (!root._asked["bot" + id]) root.lookupBot(id)
    return root.bots[id] || null
  }
  function lookupBot(id, cb) {
    root._asked["bot" + id] = true
    Qt.callLater(function() {
      root.api("bots.info", { bot: id }, function(b) {
        var x = b.bot || {}
        root.bots[id] = { name: x.name || "", icon: Model.iconOf(x.icons), app: x.app_id || "", user: x.user_id || "", deleted: x.deleted === true }
        root.botsRev++
        cacheTimer.restart()
        if (cb) cb(root.bots[id])
      }, function() { if (cb) cb(root.bots[id] || null) })
    })
  }

  // Who a message, a reply or a search hit shows as (Model.author), with
  // the people and apps known here, asking Slack for what's missing.
  function author(m) {
    root.usersRev; root.botsRev
    if (!m) return { name: "", icon: "", emoji: "", app: false, profile: "", ask: "" }
    if (m.user && !root.users[m.user]) root.lookup("user", m.user)
    var a = Model.author(m, root.users, m.botId ? root.bots[m.botId] : null)
    if (a.ask && !root._asked["bot" + a.ask]) root.lookupBot(a.ask)
    return a
  }

  // An app as Slack's "App" panel shows it: bots.info, then the web
  // client's apps.profile.get (undocumented). `ids`: {bot, app}, either.
  // cb({name, desc, icon, big, photo, bot, app, user}): `user` its bot
  // user, empty for those without one (webhooks).
  function appProfile(ids, cb) {
    function withApp(base) {
      var appId = ids.app || base.app
      if (!appId) { cb(base); return }
      root.api("apps.profile.get", { app: appId }, function(b) {
        var a = b.app_profile || {}
        var out = U.copy(base)
        out.app = appId
        if (a.name) out.name = a.name
        out.desc = a.desc || ""
        out.icon = Model.iconOf(a.icons, ["image_72", "image_64", "image_48"]) || base.icon
        out.big = Model.iconOf(a.icons, ["image_512", "image_192", "image_128"]) || out.icon
        out.photo = Model.iconOf(a.icons, ["image_1024", "image_original", "image_512"]) || out.big
        if (a.bot_user && a.bot_user.id) out.user = a.bot_user.id
        cb(out)
      }, function() { cb(base) })
    }
    var none = { name: "", desc: "", icon: "", big: "", photo: "", bot: ids.bot || "", app: ids.app || "", user: "" }
    if (!ids.bot) { withApp(none); return }
    root.lookupBot(ids.bot, function(x) {
      if (!x) { withApp(none); return }
      withApp({ name: x.name, desc: "", icon: x.icon, big: x.icon, photo: x.icon, bot: ids.bot, app: x.app, user: x.user })
    })
  }

  function applyUser(u) {
    if (!u || !u.id) return
    var o = Model.parseUser(u, root.users[u.id])
    root.users[u.id] = o
    if (o.handle) root.handles[o.handle] = u.id
    if (u.id === root.me.id) root.me = { id: u.id, handle: o.handle || root.me.handle, name: o.name }
  }

  // ---------------------------------------------------------------- start-up
  Component.onCompleted: {
    root.loadCache()
    Qt.callLater(root.start)
  }

  function start() {
    if (root.app) root.localFrecency = root.app.teamSetting(root.teamId, "emojiFrecency", {}) || {}
    root.api("auth.test", {}, function(b) {
      root.authError = ""
      var domain = String(b.url || "").replace(/^https?:\/\//, "").split(".")[0]
      root.me = { id: b.user_id, handle: b.user, name: (root.users[b.user_id] || {}).name || b.user }
      root.team = { id: b.team_id, name: b.team, domain: domain, icon: root.team.icon || "" }
      if (root.app) root.app.accountSeen(root.account.teamId, { name: b.team, domain: domain, userId: b.user_id })
      root.connectSocket()
      root.loadUsers()
      root.loadConversations()
      root.loadSections()
      root.loadCounts()
      root.loadBoot()
      root.loadPrefs()
      root.loadAccount()
      root.api("team.info", {}, function(t) {
        var icon = t.team && t.team.icon ? (t.team.icon.image_132 || t.team.icon.image_88 || t.team.icon.image_68 || "") : ""
        root.team = { id: root.team.id, name: t.team.name || root.team.name, domain: root.team.domain, icon: icon }
        if (root.app) root.app.accountSeen(root.account.teamId, { icon: icon, name: root.team.name })
      }, function() {})
      Qt.callLater(function() {
        root.loadEmoji()
        root.loadCommands()
        root.loadSaved()
        root.loadVips()
        root.loadThreads()
        root.loadScheduled()
      })
      directoryTimer.restart()
    }, function(err) {
      if (root.authErrors.indexOf(err) < 0) retryStart.restart()
    })
  }

  Timer { id: retryStart; interval: 15000; onTriggered: root.start() }

  function loadUsers() {
    var fresh = {}
    root.paginate("users.list", { limit: 200 }, "members", function() {
      root.usersRev++
      root.booted = root.booted || Object.keys(root.convs).length > 0
      cacheTimer.restart()
    }, function() {}, function(items) {
      for (var i = 0; i < items.length; i++) root.applyUser(items[i])
      root.usersRev++
    })
  }

  function loadConversations(after) {
    var seen = {}, gone = {}
    root.paginate("users.conversations", { types: "public_channel,private_channel,mpim,im", exclude_archived: false, limit: 200 }, "channels", function() {
      for (var id in root.convs) {
        var c = root.convs[id]
        if (!seen[id] && c.member !== false && !c.guest) delete root.convs[id]
      }
      root.goneDms = gone
      root.convsRev++
      root.booted = true
      if (!root.current && root.view === "conv") root.openDefault()
      cacheTimer.restart()
      if (after) after()
    }, function() {}, function(items) {
      for (var i = 0; i < items.length; i++) {
        var c = items[i]
        var o = Model.parseConv(c, root.convs[c.id])
        o.member = true
        o.guest = false
        o.dormant = !!(c.properties && c.properties.is_dormant === true)
        // A deactivated account's DM stays aside, unless it's the one open.
        if (c.is_user_deleted && o.user) gone[o.user] = o
        if (c.is_user_deleted && c.id !== root.current) continue
        seen[c.id] = true
        root.convs[c.id] = o
      }
      root.convsRev++
    })
  }

  function openDefault() {
    var ids = Object.keys(root.convs)
    var general = ids.filter(function(id) { var c = root.convs[id]; return c.general || c.name === "general" })[0]
    if (general) root.open(general, { noHistory: true })
    else if (ids.length) root.open(ids[0], { noHistory: true })
  }

  function loadSections() {
    root.api("users.channelSections.list", {}, function(b) {
      root.sections = (b.channel_sections || []).map(function(s) {
        return { id: s.channel_section_id, type: s.type, name: s.name || "", emoji: s.emoji || "", next: s.next_channel_section_id || "",
                 ids: (s.channel_ids_page && s.channel_ids_page.channel_ids) || [], hidden: s.is_hidden === true }
      })
      root.sectionsRev++
      cacheTimer.restart()
    }, function() {})
    root.loadStars()
  }

  // Starred conversations (the sidebar's Starred) and starred files (the
  // rail's Files): one list.
  function loadStars() {
    root.paginate("stars.list", { limit: 200 }, "items", function(items) {
      var st = {}, fs = {}
      items.forEach(function(i) {
        if (["im", "mpim", "channel", "group"].indexOf(i.type) >= 0 && i.channel) st[i.channel] = true
        else if (i.type === "file" && i.file && i.file.id) fs[i.file.id] = Model.parseListedFile(i.file)
      })
      root.stars = st
      root.fileStars = fs
      root.sectionsRev++
      root.fileStarsRev++
    }, function() {})
  }

  function loadBoot() {
    root.api("client.userBoot", {}, function(b) {
      var open = {}
      ;(b.is_open || []).forEach(function(id) { open[id] = true })
      root.openIms = open
      if (b.prefs && typeof b.prefs.show_sidebar_avatars === "boolean") root.sidebarAvatars = root.app ? root.app.setting("sidebarAvatars", b.prefs.show_sidebar_avatars) !== false : b.prefs.show_sidebar_avatars
      if (b.prefs && typeof b.prefs.sidebar_behavior === "string") root.hideInactive = b.prefs.sidebar_behavior === "hide_inactive_channels"
      root.bootPrefs = b.prefs || {}
      if (b.team && b.team.prefs) root.teamPrefs = b.team.prefs
      if (b.team && typeof b.team.plan === "string") root.teamPlan = b.team.plan
      if (b.team) { root.teamCreated = Number(b.team.date_create || b.team.date_created) || 0; root.teamEnterprise = !!b.team.enterprise_id }
      root.sectionsRev++
    }, function() {})
  }

  function loadCounts() {
    root.api("client.counts", {}, function(b) {
      var out = {}
      ;["channels", "ims", "mpims"].forEach(function(k) {
        (b[k] || []).forEach(function(c) {
          out[c.id] = { latest: c.latest || "", lastRead: c.last_read || "", unread: c.has_unreads === true, mentions: c.mention_count || 0 }
          if ((c.has_unreads || c.mention_count > 0) && !root.convs[c.id]) root.adoptUnknown(c.id)
        })
      })
      // What the user already read here stays read while Slack catches up.
      var cur = root.current
      if (cur && root.focused && root.view === "conv" && out[cur]) { out[cur].unread = false; out[cur].mentions = 0 }
      var prevThreads = root.threads
      root.counts = out
      root.activityCounts = b.activity_v2 || {}
      root.threads = { unread: b.threads ? b.threads.has_unreads === true : false, mentions: b.threads ? (b.threads.mention_count || 0) : 0 }
      root.countsRev++
      if (prevThreads.unread !== root.threads.unread || prevThreads.mentions !== root.threads.mentions) threadsSoon.restart()
    }, function() {})
  }

  // Unread Activity entries by type (client.counts' activity_v2): what
  // Slack badges the Activity tab (and its tabs) with.
  property var activityCounts: ({})
  function activityUnread(types) {
    root.countsRev
    var n = 0
    for (var k in root.activityCounts) if (!types || types.indexOf(k) >= 0) n += root.activityCounts[k] || 0
    return n
  }

  function adoptUnknown(id) {
    if (root._asked["adopt" + id]) return
    root._asked["adopt" + id] = true
    root.api("conversations.info", { channel: id }, function(b) {
      var o = Model.parseConv(b.channel, root.convs[id])
      if (o.kind === "im" || o.kind === "mpim" || b.channel.is_member) {
        o.member = true
        root.convs[id] = o
        if (root.openIms) root.openIms[id] = true
        root.convsRev++
      }
    }, function() {})
  }

  function loadPrefs() {
    root.api("users.prefs.get", {}, function(b) {
      var all = {}
      try { all = JSON.parse((b.prefs && b.prefs.all_notifications_prefs) || "{}") || {} } catch (e) { all = {} }
      var out = {}
      var chans = all.channels || {}
      for (var id in chans) {
        var p = chans[id] || {}
        out[id] = { muted: p.muted === true, desktop: p.desktop && p.desktop !== "default" ? p.desktop : "" }
      }
      root.prefs = out
      root.globalNotify = (all.global && all.global.global_desktop) || "everything"
      root.prefsLoaded = true
      root.rawPrefs = b.prefs || {}
      if (b.prefs && typeof b.prefs.sidebar_behavior === "string") root.hideInactive = b.prefs.sidebar_behavior === "hide_inactive_channels"
      root.convsRev++
    }, function() {})
  }
  property var rawPrefs: ({})
  property var bootPrefs: ({})        // client.userBoot's, until users.prefs.get answers
  property var teamPrefs: ({})        // the workspace's (client.userBoot's team.prefs)
  property var teamPlan: null         // client.userBoot's team.plan ("" when free), null until known
  property real teamCreated: 0        // ... its date_create (seconds)
  property bool teamEnterprise: false // ... part of an Enterprise org
  // The one-click reactions' prefs, asked for by name (loadEmojiUse) and
  // kept current by pref_change.
  readonly property var quickPrefNames: ["user_customized_quick_reactions_display_feature", "user_customized_quick_reactions_use_frequently_used_emoji",
    "user_customized_quick_reactions_has_customized", "user_customized_quick_reactions_emoji_1", "user_customized_quick_reactions_emoji_2",
    "user_customized_quick_reactions_emoji_3", "preferred_skin_tone"]
  property var quickPrefs: ({})
  function userPref(k) {
    if (root.quickPrefs[k] !== undefined) return root.quickPrefs[k]
    return root.rawPrefs[k] !== undefined ? root.rawPrefs[k] : root.bootPrefs[k]
  }

  // ------------------------------------------------------ emoji usage
  // Slack's memory of the emoji the user picks (the web client's
  // loadFrecencyPrefs): `emoji_use`, times by name, and `frecency`, its
  // jumper's visits, emoji among them as "E" + code points / custom name.
  // Only read: the web client writes `frecency` whole, from its own copy,
  // every minute, so what is picked here stays here (bumpEmoji).
  property var emojiUse: ({})
  property var emojiFrecency: ({})    // emoji id → score (Emoji.frecencyScores)
  property var localFrecency: ({})    // name → {count, visits}, picked here
  function loadEmojiUse() {
    root.api("users.prefs.get", { prefs: ["emoji_use", "frecency"].concat(root.quickPrefNames).join(",") }, function(b) {
      var p = b.prefs || {}
      root.emojiUse = Emoji.jsonPref(p.emoji_use)
      root.emojiFrecency = Emoji.frecencyScores(p.frecency)
      var q = {}
      root.quickPrefNames.forEach(function(k) { if (p[k] !== undefined) q[k] = p[k] })
      root.quickPrefs = q
    }, function() {})
  }

  // An emoji used here (a pick in the picker, a one-click reaction),
  // counted as Slack counts a visit: once more, at this time (the last 10).
  function bumpEmoji(name) {
    var base = String(name || "").replace(/^:|:$/g, "").split("::")[0]
    if (!base) return
    var f = U.copy(root.localFrecency)
    var e = f[base] || { count: 0, visits: [] }
    f[base] = { count: (Number(e.count) || 0) + 1, visits: (e.visits || []).concat([Date.now()]).slice(-10) }
    var keys = Object.keys(f)
    if (keys.length > 100) {
      var lastOf = function(k) { var v = f[k].visits || []; return v.length ? v[v.length - 1] : 0 }
      keys.sort(function(a, b) { return lastOf(a) - lastOf(b) })
      for (var i = 0; i < keys.length - 100; i++) delete f[keys[i]]
    }
    root.localFrecency = f
    if (root.app) root.app.setTeamSetting(root.teamId, "emojiFrecency", f)
  }

  // The picker's "Frequently used" and, when so set, the one-click reactions.
  readonly property var frequentEmoji: Emoji.frequentlyUsed(root.emojiFrecency, root.emojiUse, root.localFrecency, root.customEmoji, root.emojiAliases, 36)

  // The skin tone (2–6, 0: none): the picker's, else Slack's preferred_skin_tone.
  readonly property int skinTone: {
    var mine = root.app ? Number(root.app.setting("skinTone", 0)) || 0 : 0
    if (mine > 0) return Math.min(6, mine + 1)
    var s = Number(root.userPref("preferred_skin_tone"))
    return s >= 2 && s <= 6 ? s : 0
  }

  // Slack's one-click reactions (Preferences → Messages & media → Emoji),
  // the emoji on a message's hover bar, as the web client picks them: none
  // when user_customized_quick_reactions_display_feature is 0; the three
  // most used when ..._use_frequently_used_emoji; else the user's three
  // (..._emoji_1–3), the admin's (team admin_customized_quick_reactions)
  // or ✅ 👀 🙌. Standard ones in the skin tone.
  readonly property var quickReactions: {
    var on = function(v) { return v === true || v === "true" || Number(v) > 0 }
    var set = function(v) { return v !== undefined && v !== null && v !== "" }
    var shown = root.userPref("user_customized_quick_reactions_display_feature")
    if (set(shown) && !on(shown)) return []
    var names
    if (on(root.userPref("user_customized_quick_reactions_use_frequently_used_emoji"))) names = root.frequentEmoji.slice(0, 3)
    else {
      var admin = Emoji.nameList(root.teamPrefs.admin_customized_quick_reactions)
      var custom = root.userPref("user_customized_quick_reactions_has_customized")
      var mine = !set(custom) || on(custom)
      names = Emoji.QUICK.map(function(dflt, i) {
        var own = mine ? Emoji.nameList(String(root.userPref("user_customized_quick_reactions_emoji_" + (i + 1)) || ""))[0] : ""
        return own || admin[i] || dflt
      })
    }
    var tone = root.skinTone
    return names.map(function(n) { return Emoji.withTone(n, tone) })
  }

  function loadAccount() {
    root.api("users.getPresence", {}, function(b) {
      root.away = b.manual_away === true || b.presence !== "active"
      root.presence[root.me.id] = !root.away
      root.presenceRev++
    }, function() {})
    root.loadDnd()
  }

  function loadDnd() {
    root.api("dnd.info", {}, function(b) {
      var now = Date.now() / 1000
      if (b.snooze_enabled) root.dnd = { until: b.snooze_endtime || 0, snooze: true }
      else if (b.dnd_enabled && b.next_dnd_start_ts <= now && now < b.next_dnd_end_ts) root.dnd = { until: b.next_dnd_end_ts, snooze: false }
      else root.dnd = null
      root.presenceRev++
    }, function() {})
  }

  function loadEmoji() {
    root.api("emoji.list", {}, function(b) {
      var raw = b.emoji || {}
      var custom = {}, aliases = {}
      for (var name in raw) {
        var v = raw[name]
        for (var hop = 0; hop < 4 && typeof v === "string" && v.indexOf("alias:") === 0; hop++) {
          var target = v.slice(6)
          if (raw[target] !== undefined) v = raw[target]
          else { var g = Emoji.standard(target); if (g) aliases[name] = g; v = ""; break }
        }
        if (typeof v === "string" && v.indexOf("http") === 0) custom[name] = v
      }
      root.customEmoji = custom
      root.emojiAliases = aliases
      root.emojiRev++
      cacheTimer.restart()
    }, function() {})
  }

  function loadCommands() {
    root.api("commands.list", {}, function(b) {
      var list = []
      var src = b.commands || []
      var arr = Array.isArray(src) ? src : Object.keys(src).map(function(k) { return src[k] })
      arr.forEach(function(c) {
        if (!c || !c.name || String(c.name).charAt(0) !== "/") return
        list.push({ name: String(c.name).toLowerCase(), core: c.type === "core", usage: String(c.usage || "").trim(), desc: String(c.desc || "").trim(),
                    app: c.type === "core" ? "" : (c.app_name || c.service_name || ""), aliasOf: c.alias_of || "",
                    inThread: c.type === "core" || c.is_runnable_from_thread === true,
                    icon: c.icons ? (c.icons.image_32 || c.icons.image_48 || c.icons.image_64 || "") : "" })
      })
      list.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
      root.commands = list
    }, function() {})
  }

  function loadSaved() {
    var out = {}
    var items = []
    root.paginate("saved.list", { limit: 100 }, "saved_items", function(all) {
      all.forEach(function(i) {
        if (i.item_type === "message" && i.state === "in_progress") {
          out[i.item_id + "/" + i.ts] = true
          items.push({ conv: i.item_id, ts: i.ts, created: i.date_created || 0, due: i.date_due || 0 })
        }
      })
      root.saved = out
      root.savedItems = items.sort(function(a, b) { return b.created - a.created })
      root.savedRev++
    }, function() {})
  }
  property var savedItems: []

  function loadVips() {
    root.api("users.priority.list", {}, function(b) {
      var out = {}
      var groups = b.users || {}
      for (var g in groups) (groups[g] || []).forEach(function(id) { out[id] = true })
      root.vips = out
      root.usersRev++
    }, function() {})
  }

  function loadDirectory(force) {
    if (!force && root.directory.at && Date.now() / 1000 - root.directory.at < 6 * 3600) return
    var chans = []
    root.paginate("conversations.list", { types: "public_channel", exclude_archived: false, limit: 1000 }, "channels", function() {
      chans.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
      root.directory = { at: Math.floor(Date.now() / 1000), chans: chans }
      root.directoryRev++
      cacheTimer.restart()
    }, function() { root.directory = { at: Math.floor(Date.now() / 1000), chans: root.directory.chans } }, function(items) {
      items.forEach(function(c) { chans.push({ id: c.id, name: c.name, archived: c.is_archived === true, members: c.num_members || 0, updated: c.updated || (c.created || 0) * 1000, created: c.created || 0, purpose: c.purpose ? c.purpose.value : "" }) })
    })
  }

  Timer { id: directoryTimer; interval: 5000; onTriggered: root.loadDirectory(false) }

  // ---------------------------------------------------------------- socket
  property int _backoff: 2000
  property real _upSince: 0

  // The socket's URL carries the session: only ever a wss:// one on a
  // Slack host (transport.py refuses any other too).
  function slackSocket(url) {
    var m = String(url || "").match(/^wss:\/\/([^\/?#@]+)(?:[\/?#]|$)/i)
    var h = m ? m[1].replace(/:\d+$/, "").toLowerCase() : ""
    return h === "slack.com" || /\.slack\.com$/.test(h)
  }

  function connectSocket() {
    if (wire.socketOpen) return
    // The demo's pretend socket is always up (lib/Demo.js, playDemo).
    if (root.account.demo) { root.onSocketUp(); return }
    var tokenIsSession = !!root.account.cookie
    function viaRtm() {
      root.api("rtm.connect", {}, function(b) { if (root.slackSocket(b.url)) wire.openSocket(b.url) }, function() { reconnect.restartWith() })
    }
    if (!tokenIsSession) { viaRtm(); return }
    root.api("client.getWebSocketURL", {}, function(b) {
      var base = String(b.primary_websocket_url || "")
      if (!root.slackSocket(base)) { viaRtm(); return }
      var q = [
        ["token", root.account.token], ["sync_desync", "1"], ["slack_client", "desktop"],
        ["start_args", "?agent=client&org_wide_aware=true&eac_cache_ts=true&cache_ts=0&name_tagging=true&only_self_subteams=true&connect_only=true&ms_latest=true"],
        ["no_query_on_subscribe", "1"], ["flannel", "3"], ["lazy_channels", "1"]
      ]
      if (b.routing_context) q.push(["gateway_server", b.routing_context])
      q.push(["batch_presence_aware", "1"])
      var url = base.replace(/\/+$/, "") + "/?" + q.map(function(kv) { return kv[0] + "=" + encodeURIComponent(kv[1]) }).join("&")
      wire.openSocket(url)
    }, function() { viaRtm() })
  }

  Timer {
    id: reconnect
    function restartWith() { interval = root._backoff; restart() }
    onTriggered: root.connectSocket()
  }

  function onSocketUp() {
    root.live = true
    root._upSince = Date.now()
    root.loadCounts()
    root.loadPrefs()
    root.loadEmojiUse()
    root.refreshOpen()
  }

  function onSocketDown(reason) {
    var lasted = Date.now() - root._upSince
    root.live = false
    root.presenceLive = false
    root._backoff = lasted > 60000 ? 2000 : Math.min(120000, root._backoff * 2)
    if (root.authError === "") reconnect.restartWith()
  }

  function socketSend(obj) { wire.sendSocket(obj) }

  // Demo only: what its pretend socket would say ("reaction": people
  // reacting to one of your messages, "message": a new DM), heard as the
  // real one's events are, one at a time, a beat apart.
  property var _demoQueue: []
  Timer {
    id: demoBeat
    interval: 420
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var e = root._demoQueue.shift()
      if (e) root.onEvent(e)
      if (root._demoQueue.length === 0) stop()
    }
  }
  function playDemo(kind) {
    if (!root.account.demo) return
    root._demoQueue = root._demoQueue.concat(Demo.events(kind, root.account.teamId, root.me.id || "U0ME"))
    if (!demoBeat.running && root._demoQueue.length > 0) demoBeat.start()
  }

  // Who we want presence for: DM partners in the sidebar, and ourselves.
  property string _presenceKey: ""
  function subscribePresence() {
    var ids = [root.me.id]
    for (var id in root.convs) {
      var c = root.convs[id]
      if (c.kind === "im" && c.user && root.users[c.user] && !root.users[c.user].bot && (!root.openIms || root.openIms[id])) ids.push(c.user)
    }
    ids = U.uniq(ids).sort().slice(0, 100)
    var key = ids.join(",")
    if (key === root._presenceKey || !wire.socketOpen) return
    root._presenceKey = key
    wire.sendSocket({ type: "presence_sub", ids: ids })
  }

  property int _typingSent: 0
  function sendTyping(conv, threadTs) {
    if (!wire.socketOpen || !conv || root.readOnlyMode) return
    var now = Date.now()
    if (now - root._typingSent < 3000) return
    root._typingSent = now
    var f = { id: now % 100000, type: "typing", channel: conv }
    if (threadTs) f.thread_ts = threadTs
    wire.sendSocket(f)
  }

  property int eventsSeen: 0
  property var lastEventTypes: ({})
  function onEvent(e) {
    if (!e || !e.type) return
    root.eventsSeen++
    root.lastEventTypes[e.type] = (root.lastEventTypes[e.type] || 0) + 1
    switch (e.type) {
    case "hello": root._presenceKey = ""; root.subscribePresence(); break
    case "goodbye": wire.closeSocket(); break
    case "message": root.onMessageEvent(e); break
    case "reaction_added": case "reaction_removed": root.onReactionEvent(e); break
    case "presence_change": {
      var list = e.users || (e.user ? [e.user] : [])
      list.forEach(function(uid) { root.presence[uid] = e.presence === "active" })
      root.presenceLive = true
      root.presenceRev++
      break
    }
    case "manual_presence_change": root.loadAccount(); break
    case "user_typing": {
      if (e.thread_ts || e.user === root.me.id) break
      var t = root.typing[e.channel] || {}
      t[e.user] = Date.now() + 6000
      root.typing[e.channel] = t
      root.typingRev++
      if (!typingSweep.running) typingSweep.start()
      break
    }
    case "channel_marked": case "group_marked": case "im_marked": case "mpim_marked": {
      var k = root.counts[e.channel]
      if (k) {
        k.lastRead = e.ts || k.lastRead
        var unread = typeof e.unread_count_display === "number" ? e.unread_count_display > 0 : U.cmpTs(k.latest, k.lastRead) > 0
        k.unread = unread
        if (typeof e.mention_count_display === "number") k.mentions = e.mention_count_display
        else if (!unread) k.mentions = 0
        root.countsRev++
      }
      countsSoon.restart()
      break
    }
    case "badge_counts_updated": countsSoon.restart(); break
    case "thread_marked": case "thread_subscribed": case "thread_unsubscribed": case "update_thread_state":
      countsSoon.restart(); threadsSoon.restart(); break
    case "dnd_updated": root.loadDnd(); break
    case "dnd_updated_user": {
      var d = e.dnd_status || {}
      root.othersDnd[e.user] = d.snooze_enabled ? { start: 0, end: d.snooze_endtime || 0 } : (d.dnd_enabled ? { start: d.next_dnd_start_ts || 0, end: d.next_dnd_end_ts || 0 } : { start: 0, end: 0 })
      root.presenceRev++
      break
    }
    case "pref_change":
      if (e.name === "all_notifications_prefs" || e.name === "muted_channels") root.loadPrefs()
      if (e.name === "sidebar_behavior") { root.hideInactive = e.value === "hide_inactive_channels"; root.sectionsRev++ }
      // The sidebar's rules (sidebarRules) read these.
      if (["sidebar_behavior", "channel_sections", "enable_slackbot_view"].indexOf(e.name) >= 0) {
        var sp = U.copy(root.rawPrefs)
        sp[e.name] = e.value
        root.rawPrefs = sp
      }
      if (root.quickPrefNames.indexOf(e.name) >= 0) {
        var qp = U.copy(root.quickPrefs)
        qp[e.name] = e.value
        root.quickPrefs = qp
      }
      if (e.name === "emoji_use" || e.name === "frecency") root.loadEmojiUse()
      break
    // Slack's word that `frecency` / `emoji_use` changed (another client wrote them).
    case "search_frecency":
      if (e.value === "updated") root.loadEmojiUse()
      break
    case "team_pref_change":
      if (e.name === "admin_customized_quick_reactions") {
        var tp = U.copy(root.teamPrefs)
        tp[e.name] = e.value
        root.teamPrefs = tp
      }
      break
    case "channel_joined": case "group_joined": case "im_created": case "mpim_joined": case "channel_created":
      root.loadConversations(); break
    case "im_open": case "mpim_open": case "group_open":
      if (root.openIms) { root.openIms[e.channel] = true; root.sectionsRev++ }
      if (!root.convs[e.channel]) root.loadConversations()
      break
    case "im_close": case "mpim_close": case "group_close":
      if (root.openIms) { delete root.openIms[e.channel]; root.sectionsRev++ }
      break
    case "channel_left": case "group_left":
      if (root.convs[e.channel]) { root.convs[e.channel].member = false; root.convsRev++ }
      break
    case "channel_rename": case "group_rename":
      if (e.channel && root.convs[e.channel.id]) { root.convs[e.channel.id] = Model.parseConv(e.channel, root.convs[e.channel.id]); root.convsRev++ }
      break
    case "channel_archive": case "group_archive":
      if (root.convs[e.channel]) { root.convs[e.channel] = Model.patch(root.convs[e.channel], { archived: true }); root.convsRev++ }
      break
    case "channel_unarchive": case "group_unarchive":
      if (root.convs[e.channel]) { root.convs[e.channel] = Model.patch(root.convs[e.channel], { archived: false }); root.convsRev++ }
      break
    case "channel_deleted": case "group_deleted": root.forget(e.channel); break
    case "user_change": case "user_status_changed": case "user_profile_changed": case "team_join":
      if (e.user && typeof e.user === "object") { root.applyUser(e.user); root.usersRev++ }
      break
    case "user_invalidated":
      if (e.user && e.user.id) { root._asked["user" + e.user.id] = false; delete root._asked["user" + e.user.id]; root.lookup("user", e.user.id) }
      break
    case "emoji_changed": emojiSoon.restart(); break
    case "star_added": case "star_removed": sectionsSoon.restart(); break
    case "pin_added": case "pin_removed":
      if (e.channel_id || e.item) root.loadPins(e.channel_id || (e.item && e.item.channel))
      break
    // An app answering a button of ours with a window (a modal, a dialog):
    // this app can't draw those yet, so it says where to go.
    case "view_opened": case "dialog_opened":
      if (Date.now() - root.actionSentAt < 15000) root.say(tr("This app opened a window that Omaslack can't show yet. Open the message in Slack to continue.",
                                                              "Este app abriu uma janela que o Omaslack ainda não consegue mostrar. Abra a mensagem no Slack para continuar."))
      break
    default:
      if (String(e.type).indexOf("channel_section") === 0) sectionsSoon.restart()
    }
  }

  // Typing entries expire on their own: tick while there are any.
  Timer {
    id: typingSweep
    interval: 1000
    repeat: true
    onTriggered: {
      var now = Date.now(), left = false
      for (var c in root.typing) {
        var t = root.typing[c]
        for (var u in t) { if (t[u] <= now) delete t[u]; else left = true }
        if (Object.keys(t).length === 0) delete root.typing[c]
      }
      root.typingRev++
      if (!left) stop()
    }
  }
  Timer { id: countsSoon; interval: 400; onTriggered: root.loadCounts() }
  Timer { id: threadsSoon; interval: 800; onTriggered: root.loadThreads() }
  Timer { id: emojiSoon; interval: 2000; onTriggered: root.loadEmoji() }
  Timer { id: sectionsSoon; interval: 800; onTriggered: root.loadSections() }

  function onMessageEvent(e) {
    var chan = e.channel
    if (!chan) return
    var st = e.subtype || ""
    if (st === "message_changed" && e.message) {
      var nm = Model.parseMessage(e.message)
      root.replaceEverywhere(chan, nm.ts, function(old) {
        // A parent deleted under its replies: what the tombstone leaves
        // out (the thread, the reactions) stays as it was.
        if (nm.tombstone) return Model.patch(Model.tombstone(old), nm.replyCount ? { replyCount: nm.replyCount, latestReply: nm.latestReply, replyUsers: nm.replyUsers, replyUsersCount: nm.replyUsersCount } : {})
        var keep = { ephemeral: old.ephemeral }
        return Model.patch(nm, keep)
      })
      return
    }
    if (st === "message_deleted") {
      root.deleteEverywhere(chan, e.deleted_ts)
      countsSoon.restart()
      return
    }
    if (st === "message_replied" && e.message) {
      var parent = Model.parseMessage(e.message)
      root.replaceEverywhere(chan, parent.ts, function(old) {
        return Model.patch(old, { replyCount: parent.replyCount, latestReply: parent.latestReply, replyUsers: parent.replyUsers, subscribed: parent.subscribed || old.subscribed })
      })
      return
    }
    var m = Model.parseMessage(e)
    if (e.is_ephemeral) { m.ephemeral = true; if (!m.ts) m.ts = U.nowTs() }
    if (!m.ts) return
    // Who stopped typing: their message arrived.
    if (m.user && root.typing[chan] && root.typing[chan][m.user]) { delete root.typing[chan][m.user]; root.typingRev++ }
    var isReply = m.threadTs && m.threadTs !== m.ts
    var key = chan + "/" + (m.threadTs || m.ts)
    if (isReply) {
      var r = root.replies[key]
      if (r) {
        var shown = Model.patch(m, { subtype: m.subtype === "thread_broadcast" ? "" : m.subtype })
        root.replies[key] = { msgs: Model.upsert(r.msgs.filter(function(x) { return !(x.pending && x.text === m.text && x.user === m.user) }), shown), loading: false }
        root.repliesRev++
        root.repliesUpdated(key)
        if (root.thread && root.thread.conv === chan && root.thread.ts === m.threadTs && root.focused) root.markThread(chan, m.threadTs, m.ts)
      }
      root.replaceEverywhere(chan, m.threadTs, function(old) {
        var users = old.replyUsers.slice()
        if (m.user && users.indexOf(m.user) < 0) users.push(m.user)
        return Model.patch(old, { replyCount: (old.replyCount || 0) + (r && r.msgs.some(function(x) { return x.ts === m.ts }) ? 0 : 1), latestReply: m.ts, replyUsers: users })
      }, true)
      threadsSoon.restart()
    }
    if (!isReply || m.subtype === "thread_broadcast") {
      if (!m.ephemeral) { root.lastMsgs[chan] = m; root.lastRev++ }
      var h = root.histories[chan]
      if (h && !h.detached) {
        var msgs = h.msgs.filter(function(x) { return !(x.pending && x.user === m.user && x.text === m.text) })
        root.setHistory(chan, { msgs: Model.upsert(msgs, m), noOlder: h.noOlder, loading: false, detached: false })
      }
    }
    // Unread counts follow along until client.counts says otherwise.
    if (m.user !== root.me.id && !m.ephemeral && !isReply) {
      var k = root.counts[chan] || { latest: "", lastRead: "", unread: false, mentions: 0 }
      k.latest = m.ts
      var reading = chan === root.current && root.view === "conv" && root.focused
      if (!reading) {
        k.unread = true
        var c = root.convs[chan]
        if (Model.isDm(c) || Md.mentions(m, root.me.id)) k.mentions = (k.mentions || 0) + 1
      }
      root.counts[chan] = k
      root.countsRev++
      if (!root.convs[chan]) root.adoptUnknown(chan)
      if (root.openIms && root.convs[chan] && Model.isDm(root.convs[chan]) && !root.openIms[chan]) { root.openIms[chan] = true; root.sectionsRev++ }
      if (reading) markSoon.restart()
    }
    if (m.user !== root.me.id && !m.ephemeral && m.subtype !== "message_changed") root.maybeNotify(chan, m, isReply)
    countsSoon.restart()
  }

  function onReactionEvent(e) {
    var item = e.item || {}
    if (item.type !== "message" || !item.channel) return
    var added = e.type === "reaction_added"
    root.replaceEverywhere(item.channel, item.ts, function(old) {
      return Model.patch(old, { reactions: root.toggledReactions(old.reactions || [], e.reaction, e.user, added) })
    })
    if (!added) { root.noteReaction(e, false, null); return }
    // Someone else's, on a message of yours: the bar lists it (and floats
    // it out of the icon), and it notifies.
    if (!e.user || e.user === root.me.id) return
    root.ifMine(item.channel, item.ts, e.item_user, function(m) {
      root.noteReaction(e, true, m)
      root.maybeNotifyReaction(e, m)
    })
  }

  // cb(message or null) when the message `ts` is yours. The socket names
  // its author (`item_user`); without it, the message at hand does, or
  // Slack is asked (reactions.get).
  function ifMine(conv, ts, author, cb) {
    var m = root.knownMessage(conv, ts)
    if (author) { if (author === root.me.id) cb(m); return }
    if (m) { if (m.user === root.me.id) cb(m); return }
    root.api("reactions.get", { channel: conv, timestamp: ts }, function(b) {
      var got = b.message ? Model.parseMessage(b.message) : null
      if (got && got.user === root.me.id) cb(got)
    }, function() {})
  }

  // A reaction notifies as a message there would: not while paused, not
  // for the conversation (or thread) in front of you, not in a muted
  // channel or one set to nothing on its own (Slack's account-wide level
  // doesn't count, as in maybeNotify).
  function maybeNotifyReaction(e, m) {
    if (!root.app || !root.app.notificationsOn || root.dnd) return
    var chan = e.item.channel
    var threadTs = m && m.threadTs && m.threadTs !== m.ts ? m.threadTs : ""
    var reading = (chan === root.current && root.view === "conv" && root.focused) ||
                  (threadTs && root.thread && root.thread.conv === chan && root.thread.ts === threadTs && root.focused)
    if (reading || root.isMuted(chan)) return
    if ((root.prefs[chan] || {}).desktop === "nothing") return
    root.notify({ kind: "reaction", conv: chan, ts: e.item.ts, threadTs: threadTs, user: e.user, reaction: e.reaction,
                  msg: m || null, team: root.teamId })
  }

  function toggledReactions(list, name, uid, add) {
    var out = []
    var found = false
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      if (r.name !== name) { out.push(r); continue }
      found = true
      var has = r.users.indexOf(uid) >= 0
      if (add && !has) out.push({ name: r.name, users: r.users.concat([uid]), count: r.count + 1 })
      else if (!add && has) { if (r.count > 1) out.push({ name: r.name, users: r.users.filter(function(x) { return x !== uid }), count: r.count - 1 }) }
      else out.push(r)
    }
    if (!found && add) out.push({ name: name, users: [uid], count: 1 })
    return out
  }

  function replaceEverywhere(chan, ts, fn, parentOnly) {
    var h = root.histories[chan]
    if (h) {
      var i = Model.indexOfTs(h.msgs, ts)
      if (i >= 0) {
        var msgs = h.msgs.slice()
        msgs[i] = fn(msgs[i])
        root.setHistory(chan, { msgs: msgs, noOlder: h.noOlder, loading: h.loading, detached: h.detached })
      }
    }
    for (var key in root.replies) {
      if (key.indexOf(chan + "/") !== 0) continue
      var r = root.replies[key]
      var j = Model.indexOfTs(r.msgs, ts)
      if (j < 0) continue
      var rm = r.msgs.slice()
      var changed = fn(rm[j])
      if (key !== chan + "/" + ts && changed.subtype === "thread_broadcast") changed = Model.patch(changed, { subtype: "" })
      rm[j] = key === chan + "/" + ts ? Model.patch(changed, { replyCount: 0 }) : changed
      root.replies[key] = { msgs: rm, loading: r.loading }
      root.repliesRev++
      root.repliesUpdated(key)
    }
    var pl = root.pins[chan]
    if (pl) {
      var pi = pl.findIndex(function(p) { return p.msg.ts === ts })
      if (pi >= 0) { var np = pl.slice(); np[pi] = { msg: fn(np[pi].msg), by: np[pi].by, created: np[pi].created }; root.pins[chan] = np; root.pinsRev++ }
    }
  }

  // Deleted: gone, but a thread's parent with replies stays over them as
  // Slack's tombstone. Slack deletes a tombstone once its replies are gone.
  function deleteEverywhere(chan, ts) {
    var m = root.findAny(chan, ts)
    var r = root.replies[chan + "/" + ts]
    var heads = !!m && !m.tombstone && (!m.threadTs || m.threadTs === m.ts) && (m.replyCount > 0 || m._replyCount > 0 || (!!r && r.msgs.length > 1))
    if (heads) root.replaceEverywhere(chan, ts, Model.tombstone)
    else root.removeEverywhere(chan, ts)
  }

  function removeEverywhere(chan, ts) {
    var h = root.histories[chan]
    if (h) {
      var msgs = h.msgs.filter(function(m) { return m.ts !== ts })
      if (msgs.length !== h.msgs.length) root.setHistory(chan, { msgs: msgs, noOlder: h.noOlder, loading: h.loading, detached: h.detached })
    }
    for (var key in root.replies) {
      if (key.indexOf(chan + "/") !== 0) continue
      if (key === chan + "/" + ts) {
        delete root.replies[key]
        if (root.thread && root.thread.conv === chan && root.thread.ts === ts) root.thread = null
        root.repliesRev++
        continue
      }
      var r = root.replies[key]
      var rm = r.msgs.filter(function(m) { return m.ts !== ts })
      if (rm.length !== r.msgs.length) { root.replies[key] = { msgs: rm, loading: r.loading }; root.repliesRev++; root.repliesUpdated(key) }
    }
  }

  function setHistory(conv, h) {
    root.histories[conv] = h
    root.historyRev++
    root.historyUpdated(conv)
  }

  // ---------------------------------------------------------------- notify
  // Slack's account-wide level ("Notify me about") only sets what a channel
  // without a level of its own notifies of: every message, or mentions
  // ("nothing" there reads as mentions, as notifyLevel shows it). It never
  // silences DMs or mentions: people set it to Nothing to keep Slack's own
  // apps quiet, and the switch for these is the bar's (notificationsOn).
  // A channel set to nothing on its own stays quiet.
  function maybeNotify(chan, m, isReply) {
    if (!root.app || !root.app.notificationsOn) return
    if (root.dnd) return
    var c = root.convs[chan]
    if (!c) return
    // Joins, topic changes and the like: Slack keeps quiet about them.
    if (Md.systemText(m, "en")) return
    var reading = (chan === root.current && root.view === "conv" && root.focused) ||
                  (isReply && root.thread && root.thread.conv === chan && root.thread.ts === m.threadTs && root.focused)
    if (reading) return
    var dm = Model.isDm(c)
    var mention = Md.mentions(m, root.me.id)
    var p = root.prefs[chan] || {}
    if (!dm) {
      if (isReply && root.followsThread(chan, m.threadTs)) {
        // A reply in a thread you follow notifies whatever the channel's
        // level, as in Slack, except in a
        // muted channel unless it mentions you.
        if (p.muted && !mention) return
      } else {
        if (p.muted && !Md.mentionsMe(m, root.me.id)) return
        if (p.desktop === "nothing") return
        var level = p.desktop || root.globalNotify
        if (!mention && level !== "everything") return
        // Also sent to the channel: a channel message like any other.
        if (isReply && !mention && m.subtype !== "thread_broadcast") return
      }
    }
    root.notify({ kind: "message", conv: chan, ts: m.ts, threadTs: isReply ? m.threadTs : "", msg: m, mention: mention, dm: dm, team: root.teamId })
  }

  function findMessage(conv, ts) {
    var h = root.histories[conv]
    if (h) { var i = Model.indexOfTs(h.msgs, ts); if (i >= 0) return h.msgs[i] }
    var r = root.replies[conv + "/" + ts]
    if (r && r.msgs.length) return r.msgs[0]
    return null
  }

  // Whether you follow a thread: its parent says so when it is loaded, the
  // Threads view lists the ones you follow.
  function followsThread(conv, ts) {
    var parent = root.findMessage(conv, ts)
    if (parent && parent.subscribed) return true
    return root.threadsView.list.some(function(t) { return t.conv === conv && t.root && t.root.ts === ts })
  }

  // ---------------------------------------------------------------- polling
  Timer {
    interval: root.live ? 60000 : 15000
    running: root.booted
    repeat: true
    onTriggered: root.loadCounts()
  }

  Timer {
    interval: root.live ? 60000 : 5000
    running: root.booted && root.foreground
    repeat: true
    onTriggered: root.refreshOpen()
  }

  Timer {
    interval: 60000
    running: root.booted
    repeat: true
    onTriggered: {
      root.loadDnd()
      root.subscribePresence()
      if (!root.presenceLive && root.foreground) root.pollPresence()
      root.pollOthersDnd()
      root.sweepStatuses()
    }
  }

  // A status that ran out since the last look leaves the sidebar, the
  // messages and the profiles (Model.status), whether or not Slack says so.
  property real _statusSweep: Date.now() / 1000
  function sweepStatuses() {
    var since = root._statusSweep, now = Date.now() / 1000
    root._statusSweep = now
    for (var id in root.users) {
      var x = root.users[id].statusExp
      if (x > since && x <= now) { root.usersRev++; return }
    }
  }

  Timer {
    interval: 600000
    running: root.booted
    repeat: true
    onTriggered: root.loadUsers()
  }

  Timer { id: markSoon; interval: 600; onTriggered: if (root.current && root.view === "conv") root.markRead(root.current, true) }

  property var _presenceQueue: []
  Timer {
    id: presenceTick
    interval: 300
    repeat: true
    onTriggered: {
      var uid = root._presenceQueue.shift()
      if (!uid) { stop(); return }
      root.api("users.getPresence", { user: uid }, function(b) { root.presence[uid] = b.presence === "active"; root.presenceRev++ }, function() {})
    }
  }

  function pollPresence() {
    var ids = []
    for (var id in root.convs) {
      var c = root.convs[id]
      if (c.kind === "im" && c.user && root.users[c.user] && !root.users[c.user].bot && (!root.openIms || root.openIms[id])) ids.push(c.user)
    }
    root._presenceQueue = ids.slice(0, 40)
    presenceTick.start()
  }

  function pollOthersDnd() {
    var ids = []
    for (var id in root.convs) {
      var c = root.convs[id]
      if (c.kind === "im" && c.user && c.user !== root.me.id && root.users[c.user] && !root.users[c.user].bot && (!root.openIms || root.openIms[id])) ids.push(c.user)
    }
    ids = ids.slice(0, 50)
    if (!ids.length) return
    root.api("dnd.teamInfo", { users: ids.join(",") }, function(b) {
      var u = b.users || {}
      for (var uid in u) {
        var d = u[uid] || {}
        root.othersDnd[uid] = d.snooze_enabled ? { start: 0, end: d.snooze_endtime || 0 } : (d.dnd_enabled ? { start: d.next_dnd_start_ts || 0, end: d.next_dnd_end_ts || 0 } : { start: 0, end: 0 })
      }
      root.presenceRev++
    }, function() {})
  }

  function refreshOpen() {
    if (root.view === "conv" && root.current) root.fetchHistory(root.current, "poll")
    if (root.thread) root.fetchReplies(root.thread.conv, root.thread.ts)
    if (root.view === "threads") root.loadThreads()
  }

  onFocusedChanged: {
    if (!root.focused) return
    if (root.current && root.view === "conv") {
      var k = root.counts[root.current]
      if (k && (k.unread || k.mentions)) root.markRead(root.current, true)
    }
    // A thread open (from a reply's notification) whose replies came in
    // before the window had the focus.
    var th = root.thread
    var r = th ? root.replies[th.conv + "/" + th.ts] : null
    if (r && !r.loading && r.msgs.length > 1) root.markThread(th.conv, th.ts, r.msgs[r.msgs.length - 1].ts)
  }

  // ---------------------------------------------------------------- navigation
  function open(convId, opts) {
    opts = opts || {}
    if (!convId) return
    if (root.view === "conv" && root.current === convId && !opts.ts) { root.view = "conv"; return }
    if (!opts.noHistory && (root.current || root.view !== "conv")) {
      var bs = root.backStack.slice()
      bs.push({ view: root.view, conv: root.current })
      if (bs.length > 50) bs.shift()
      root.backStack = bs
      root.forwardStack = []
    }
    // A preview of a channel we are not in drops when we move on.
    if (root.current && root.current !== convId && root.convs[root.current] && root.convs[root.current].guest) {
      delete root.convs[root.current]
      delete root.histories[root.current]
      root.convsRev++
    }
    if (!root.convs[convId]) {
      var d = root.directory.chans.filter(function(x) { return x.id === convId })[0]
      var other = root._others[convId]
      // A deactivated account's DM (a search hit, a link): its archives.
      var gone = null
      for (var gu in root.goneDms) if (root.goneDms[gu].id === convId) gone = root.goneDms[gu]
      if (gone) {
        root.convs[convId] = gone
        root.convsRev++
      } else if (d || other) {
        root.convs[convId] = other ? Model.patch(other, { guest: true, member: false }) : { id: convId, kind: "channel", name: d.name, archived: d.archived, guest: true, member: false, updated: d.updated }
        root.convsRev++
      } else {
        root.api("conversations.info", { channel: convId }, function(b) {
          var c = Model.parseConv(b.channel, null)
          if (!root.convs[convId]) { c.guest = b.channel.is_member !== true && c.kind === "channel"; c.member = !c.guest; root.convs[convId] = c; root.convsRev++ }
        }, function() {})
      }
    }
    root.editing = null
    root.view = "conv"
    root.current = convId
    var k = root.counts[convId]
    // The New line: over the first message from someone else after last_read.
    if (k && (k.unread || k.mentions > 0) && k.lastRead) root.newLines[convId] = k.lastRead
    else if (!opts.keepNew) delete root.newLines[convId]
    if (opts.threadTs) root.openThread(convId, opts.threadTs)
    // Messages from the cache show at once (loading, so the New line and
    // older pages wait); the newest page then replaces them.
    var h = root.histories[convId]
    var cached = !!root.fromCache[convId]
    if (opts.ts) {
      root.flashTs = opts.ts
      flashClear.restart()
      if (h && !cached && Model.indexOfTs(h.msgs, opts.ts) >= 0) root.jumpTo(convId, opts.ts)
      else root.fetchAround(convId, opts.ts)
    } else if (!h || h.detached || cached) root.fetchHistory(convId, "initial")
    else root.fetchHistory(convId, "poll")
    if (root.focused && k && (k.unread || k.mentions > 0)) root.markRead(convId)
    root.loadPins(convId)
    var c = root.convs[convId]
    if (c && (c.kind === "channel" || c.kind === "private")) {
      root.api("conversations.info", { channel: convId, include_num_members: true }, function(b) {
        if (!root.convs[convId]) return
        var keep = root.convs[convId]
        var fresh = Model.parseConv(b.channel, keep)
        fresh.guest = keep.guest
        fresh.member = keep.member
        root.convs[convId] = fresh
        root.convsRev++
      }, function() {})
    }
    if (c && c.kind === "im" && c.user) {
      root.api("users.info", { user: c.user }, function(b) { root.applyUser(b.user); root.usersRev++ }, function() {})
      root.api("dnd.info", { user: c.user }, function(b) {
        root.othersDnd[c.user] = b.snooze_enabled ? { start: 0, end: b.snooze_endtime || 0 } : (b.dnd_enabled ? { start: b.next_dnd_start_ts || 0, end: b.next_dnd_end_ts || 0 } : { start: 0, end: 0 })
        root.presenceRev++
      }, function() {})
      if (!root.presenceLive) root.api("users.getPresence", { user: c.user }, function(b) { root.presence[c.user] = b.presence === "active"; root.presenceRev++ }, function() {})
    }
    if (!(c && c.guest)) {
      root.recents = [convId].concat(root.recents.filter(function(x) { return x !== convId })).slice(0, root.maxRecents)
      cacheTimer.restart()
    }
    if (root.app) root.app.rememberConv(root.teamId, convId)
  }

  Timer { id: flashClear; interval: 2200; onTriggered: root.flashTs = "" }

  function showView(v) {
    if (root.view === v) return
    var bs = root.backStack.slice()
    bs.push({ view: root.view, conv: root.current })
    root.backStack = bs
    root.forwardStack = []
    root.view = v
    if (v === "threads") root.loadThreads()
    if (v === "saved") root.loadSaved()
  }

  function goBack() {
    if (!root.backStack.length) return
    var bs = root.backStack.slice()
    var to = bs.pop()
    root.backStack = bs
    var fs = root.forwardStack.slice()
    fs.push({ view: root.view, conv: root.current })
    root.forwardStack = fs
    if (to.view === "conv" && to.conv) root.open(to.conv, { noHistory: true })
    else root.view = to.view
  }

  function goForward() {
    if (!root.forwardStack.length) return
    var fs = root.forwardStack.slice()
    var to = fs.pop()
    root.forwardStack = fs
    var bs = root.backStack.slice()
    bs.push({ view: root.view, conv: root.current })
    root.backStack = bs
    if (to.view === "conv" && to.conv) root.open(to.conv, { noHistory: true })
    else root.view = to.view
  }

  // Next / previous conversation in the sidebar (Alt+↑/↓), unread only with `unreadOnly`.
  function step(rows, dir, unreadOnly) {
    var convRows = rows.filter(function(r) { return r.kind === "conv" && (!unreadOnly || r.unread || r.mentions > 0 || r.active) })
    var i = convRows.findIndex(function(r) { return r.id === root.current })
    var next = convRows[i + dir]
    if (unreadOnly) next = convRows.filter(function(r, k) { return dir > 0 ? k > i : k < i }).filter(function(r) { return !r.active })[dir > 0 ? 0 : -1]
    if (unreadOnly && !next) {
      var list = convRows.filter(function(r) { return !r.active })
      next = dir > 0 ? list[0] : list[list.length - 1]
    }
    if (next) root.open(next.id)
  }

  // ---------------------------------------------------------------- history
  readonly property int pageSize: 60

  function fetchHistory(conv, mode) {
    var h = root.histories[conv]
    if (mode === "poll" && h && h.loading) return
    if (!h) root.setHistory(conv, { msgs: [], noOlder: false, loading: true, detached: false })
    else if (mode === "initial") root.setHistory(conv, { msgs: h.msgs, noOlder: h.noOlder, loading: true, detached: false })
    root.api("conversations.history", { channel: conv, limit: root.pageSize }, function(b) {
      var page = (b.messages || []).map(Model.parseMessage).reverse()
      var cur = root.histories[conv] || { msgs: [] }
      var loaded = cur.msgs
      // The cache's messages only stood in: the page replaces them, and
      // those older than it go, so no gap is left between the two (scrolling
      // up brings them back).
      if (root.fromCache[conv]) {
        delete root.fromCache[conv]
        if (page.length) loaded = loaded.filter(function(m) { return U.cmpTs(m.ts, page[0].ts) >= 0 })
      }
      var msgs = cur.detached && mode === "poll" ? cur.msgs : Model.mergePage(loaded, page, true)
      var noOlder = cur.noOlder || (page.length < root.pageSize && b.has_more !== true)
      root.setHistory(conv, { msgs: msgs, noOlder: noOlder, loading: false, detached: false })
      if (conv === root.current && root.view === "conv" && root.focused) root.markRead(conv, true)
    }, function(err) {
      var cur = root.histories[conv] || { msgs: [] }
      root.setHistory(conv, { msgs: cur.msgs, noOlder: cur.noOlder, loading: false, detached: cur.detached, error: err })
    })
  }

  function loadOlder(conv) {
    var h = root.histories[conv]
    if (!h || h.loading || h.noOlder || !h.msgs.length) return
    root.setHistory(conv, { msgs: h.msgs, noOlder: false, loading: true, detached: h.detached })
    root.api("conversations.history", { channel: conv, limit: root.pageSize, latest: h.msgs[0].ts }, function(b) {
      var page = (b.messages || []).map(Model.parseMessage).reverse()
      var cur = root.histories[conv]
      var msgs = cur.msgs
      for (var i = 0; i < page.length; i++) if (Model.indexOfTs(msgs, page[i].ts) < 0) msgs = Model.upsert(msgs, page[i])
      root.setHistory(conv, { msgs: msgs, noOlder: page.length < root.pageSize && b.has_more !== true, loading: false, detached: cur.detached })
    }, function() {
      var cur = root.histories[conv]
      root.setHistory(conv, { msgs: cur.msgs, noOlder: cur.noOlder, loading: false, detached: cur.detached })
    })
  }

  // The messages around one (a search hit, a link): detached from the
  // live end until the newest page meets it.
  function fetchAround(conv, ts) {
    var cur = root.histories[conv]
    root.setHistory(conv, { msgs: cur ? cur.msgs : [], noOlder: cur ? cur.noOlder : false, loading: true, detached: cur ? cur.detached : false })
    root.api("conversations.history", { channel: conv, limit: root.pageSize, latest: ts, inclusive: true }, function(b1) {
      var before = (b1.messages || []).map(Model.parseMessage).reverse()
      root.api("conversations.history", { channel: conv, limit: root.pageSize, oldest: ts }, function(b2) {
        var after = (b2.messages || []).map(Model.parseMessage).filter(function(m) { return U.cmpTs(m.ts, ts) > 0 })
        after.sort(function(a, b) { return U.cmpTs(a.ts, b.ts) })
        var msgs = before.concat(after)
        var present = after.length < root.pageSize
        delete root.fromCache[conv]
        root.setHistory(conv, { msgs: msgs, noOlder: before.length < root.pageSize, loading: false, detached: !present })
        root.jumpTo(conv, ts)
        if (conv === root.current && root.view === "conv" && root.focused) root.markRead(conv, true)
      }, function() {
        delete root.fromCache[conv]
        root.setHistory(conv, { msgs: before, noOlder: before.length < root.pageSize, loading: false, detached: true })
        root.jumpTo(conv, ts)
      })
    }, function() {
      var c2 = root.histories[conv]
      root.setHistory(conv, { msgs: c2.msgs, noOlder: c2.noOlder, loading: false, detached: c2.detached })
    })
  }

  function loadNewer(conv) {
    var h = root.histories[conv]
    if (!h || !h.detached || h.loading || !h.msgs.length) return
    root.setHistory(conv, { msgs: h.msgs, noOlder: h.noOlder, loading: true, detached: true })
    root.api("conversations.history", { channel: conv, limit: root.pageSize, oldest: h.msgs[h.msgs.length - 1].ts }, function(b) {
      var page = (b.messages || []).map(Model.parseMessage)
      page.sort(function(a, c) { return U.cmpTs(a.ts, c.ts) })
      var cur = root.histories[conv]
      var msgs = cur.msgs
      page.forEach(function(m) { msgs = Model.upsert(msgs, m) })
      root.setHistory(conv, { msgs: msgs, noOlder: cur.noOlder, loading: false, detached: page.length >= root.pageSize })
    }, function() {
      var cur = root.histories[conv]
      root.setHistory(conv, { msgs: cur.msgs, noOlder: cur.noOlder, loading: false, detached: cur.detached })
    })
  }

  function jumpToPresent(conv) {
    var h = root.histories[conv]
    if (h && h.detached) {
      root.setHistory(conv, { msgs: [], noOlder: false, loading: true, detached: false })
      root.fetchHistory(conv, "initial")
    }
  }

  // ---------------------------------------------------------------- threads
  function openThread(conv, ts) {
    root.thread = { conv: conv, ts: ts }
    root.profileUser = ""
    root.fetchReplies(conv, ts)
  }

  function closeThread() { root.thread = null }

  function fetchReplies(conv, ts) {
    var key = conv + "/" + ts
    var cur = root.replies[key]
    if (cur && cur.loading) return
    root.replies[key] = { msgs: cur ? cur.msgs : [], loading: true }
    root.repliesRev++
    var all = []
    function page(cursor) {
      var p = { channel: conv, ts: ts, limit: 200 }
      if (cursor) p.cursor = cursor
      root.api("conversations.replies", p, function(b) {
        all = all.concat((b.messages || []).map(Model.parseMessage))
        var next = b.response_metadata && b.response_metadata.next_cursor
        if (next && b.has_more) { page(next); return }
        all.sort(function(a, c) { return U.cmpTs(a.ts, c.ts) })
        var out = []
        all.forEach(function(m) { if (!out.length || out[out.length - 1].ts !== m.ts) out.push(m) })
        out = out.map(function(m, i) { return i === 0 ? Model.patch(m, { replyCount: 0, _replyCount: m.replyCount }) : (m.subtype === "thread_broadcast" ? Model.patch(m, { subtype: "", broadcast: true }) : m) })
        var old = root.replies[key]
        // Local sends not yet listed, and ephemeral answers, stay.
        if (old) old.msgs.forEach(function(m) {
          if ((m.pending || m.ephemeral) && !out.some(function(x) { return x.ts === m.ts })) out = Model.upsert(out, m)
        })
        if (old) out = out.map(function(m) { var o = old.msgs.filter(function(x) { return x.ts === m.ts })[0]; return o && Model.same(o, m) ? o : m })
        root.replies[key] = { msgs: out, loading: false }
        root.repliesRev++
        root.repliesUpdated(key)
        if (all.length) {
          var parent = all[0]
          if (parent.ts === ts) root.replaceEverywhere(conv, ts, function(o) {
            return Model.patch(o, { replyCount: parent.replyCount, latestReply: parent.latestReply, replyUsers: parent.replyUsers, subscribed: parent.subscribed })
          }, true)
        }
        if (root.thread && root.thread.conv === conv && root.thread.ts === ts && root.focused && out.length > 1) root.markThread(conv, ts, out[out.length - 1].ts)
      }, function() {
        var o = root.replies[key]
        root.replies[key] = { msgs: o ? o.msgs : [], loading: false }
        root.repliesRev++
      })
    }
    page("")
  }

  property var _threadMarked: ({})
  function markThread(conv, ts, upto) {
    var key = conv + "/" + ts
    if (!upto || (root._threadMarked[key] && U.cmpTs(root._threadMarked[key], upto) >= 0)) return
    root._threadMarked[key] = upto
    root.api("subscriptions.thread.mark", { channel: conv, thread_ts: ts, ts: upto, read: 1 }, function() {
      root.threadsView.list.forEach(function(t) { if (t.conv === conv && t.root.ts === ts) { t.lastRead = upto; t.unread = false; t.newCount = 0 } })
      root.threadsRev++
      countsSoon.restart()
    }, function() {})
  }

  function loadThreads() {
    if (root.threadsView.loading) return
    root.threadsView = { list: root.threadsView.list, total: root.threadsView.total, loaded: root.threadsView.loaded, loading: true }
    var list = [], seen = {}, total = 0
    function page(n, cursor) {
      var p = { limit: 10 }
      if (cursor) p.current_ts = cursor
      root.api("subscriptions.thread.getView", p, function(b) {
        if (n === 0) total = b.total_unread_replies || 0
        var last = ""
        ;(b.threads || []).forEach(function(t) {
          var rm = t.root_msg || {}
          if (!rm.channel) return
          var k = rm.channel + "/" + rm.ts
          if (seen[k]) return
          seen[k] = true
          var replies = (t.latest_replies || []).map(Model.parseMessage).sort(function(a, c) { return U.cmpTs(a.ts, c.ts) })
          var latest = rm.latest_reply || (replies.length ? replies[replies.length - 1].ts : "")
          var lastRead = rm.last_read || ""
          var unread = latest !== "" && U.cmpTs(latest, lastRead) > 0
          list.push({ key: k, conv: rm.channel, root: Model.parseMessage(rm), replies: replies, latest: latest, lastRead: lastRead,
                      unread: unread, newCount: unread ? Math.max(1, replies.filter(function(r) { return U.cmpTs(r.ts, lastRead) > 0 }).length) : 0,
                      people: rm.reply_users_count || 0 })
          last = latest || rm.ts
        })
        if (b.has_more === true && n < 2 && last && last !== cursor) page(n + 1, last)
        else {
          list.sort(function(a, c) {
            if (a.unread !== c.unread) return a.unread ? -1 : 1
            return U.cmpTs(c.latest || c.root.ts, a.latest || a.root.ts)
          })
          root.threadsView = { list: list, total: total, loaded: true, loading: false }
          root.threadsRev++
        }
      }, function() {
        root.threadsView = { list: root.threadsView.list, total: root.threadsView.total, loaded: true, loading: false }
        root.threadsRev++
      })
    }
    page(0, "")
  }

  // ---------------------------------------------------------------- read state
  function markRead(conv, onlyIfNewer) {
    var c = root.convs[conv]
    if (!c || c.guest || c.member === false) return
    var h = root.histories[conv]
    var k = root.counts[conv]
    var ts = ""
    if (h && h.msgs.length && !h.detached) ts = h.msgs.filter(function(m) { return !m.pending && !m.ephemeral }).map(function(m) { return m.ts }).pop() || ""
    // Never behind what the counts know (marking there would unread the
    // rest); the cache's messages alone can be, so they don't count.
    if (root.fromCache[conv] && !(k && k.latest)) ts = ""
    else if (k && k.latest && (!ts || U.cmpTs(k.latest, ts) > 0)) ts = k.latest
    if (!ts) return
    if (onlyIfNewer && k && k.lastRead && U.cmpTs(k.lastRead, ts) >= 0 && !k.unread && !k.mentions) return
    if (k) { k.unread = false; k.mentions = 0; k.lastRead = ts; root.countsRev++ }
    root.api("conversations.mark", { channel: conv, ts: ts }, function() {}, function() {})
  }

  function markAllRead() {
    var n = 0
    for (var id in root.counts) {
      var k = root.counts[id]
      if (!(k.unread || k.mentions > 0) || !k.latest) continue
      n++
      root.api("conversations.mark", { channel: id, ts: k.latest }, function() {}, function() {})
      k.unread = false
      k.mentions = 0
      k.lastRead = k.latest
    }
    root.countsRev++
    root.say(root.lang === "pt-BR" ? n + " conversas marcadas como lidas" : n + " conversations marked as read")
  }

  function markUnread(conv, ts) {
    var before = U.tsBefore(ts)
    root.newLines[conv] = before
    root.historyRev++
    root.api("conversations.mark", { channel: conv, ts: before }, function() {
      root.say(root.tr("Marked unread", "Marcada como não lida"))
      countsSoon.restart()
    }, function(err) { root.say(root.errorText(err)) })
  }

  // ---------------------------------------------------------------- sending
  function setDraft(conv, text) {
    if (!conv) return
    if (text && text.trim()) root.drafts[conv] = text
    else delete root.drafts[conv]
    root.draftsRev++
  }

  // Composer text with its mention/channel picks (`refs`: [{label, wire}])
  // turned into Slack's wire form.
  function wireText(text, refs) {
    var out = String(text || "")
    var list = (refs || []).slice().sort(function(a, b) { return b.label.length - a.label.length })
    list.forEach(function(r) { out = out.split(r.label).join(r.wire) })
    out = out.replace(/(^|\s)@(here|channel|everyone)\b/g, "$1<!$2>")
    // #channel typed by hand, when it names one of ours.
    out = out.replace(/(^|\s)#([a-z0-9_\-]{1,80})\b/g, function(all, pre, name) {
      for (var id in root.convs) { var c = root.convs[id]; if ((c.kind === "channel" || c.kind === "private") && c.name === name) return pre + "<#" + id + ">" }
      var d = root.directory.chans.filter(function(x) { return x.name === name })[0]
      return d ? pre + "<#" + d.id + ">" : all
    })
    return out
  }

  function send(conv, text, opts) {
    opts = opts || {}
    var typed = String(text || "").trim()
    if (!typed && !(opts.files && opts.files.length)) return false
    if (opts.files && opts.files.length) { root.upload(conv, opts.files, typed, opts.threadTs || ""); return true }
    if (typed.charAt(0) === "/" && typed.length > 1 && !/\s/.test(typed.charAt(1))) return root.runSlash(conv, typed, opts.threadTs || "")
    // `opts.blocks`: the message box's own rich_text (it knows formatting
    // the markup can't say, bold inside a word); else from the markup.
    var params = { channel: conv, text: Markup.escape(typed), blocks: JSON.stringify(opts.blocks || Markup.blocks(typed)) }
    if (opts.threadTs) params.thread_ts = opts.threadTs
    if (opts.broadcast) params.reply_broadcast = true
    // Shown at once; the answer (or the socket) replaces it.
    var local = Model.parseMessage({ ts: U.nowTs(), user: root.me.id, text: params.text, blocks: JSON.parse(params.blocks) })
    local.pending = true
    var key = conv + "/" + (opts.threadTs || "")
    if (opts.threadTs) {
      var r = root.replies[key]
      if (r) { root.replies[key] = { msgs: Model.upsert(r.msgs, local), loading: r.loading }; root.repliesRev++; root.repliesUpdated(key) }
    } else {
      var h = root.histories[conv]
      if (h && !h.detached) root.setHistory(conv, { msgs: Model.upsert(h.msgs, local), noOlder: h.noOlder, loading: h.loading, detached: false })
    }
    function done(b) {
      var m = Model.parseMessage(b.message || {})
      if (!m.ts) m.ts = b.ts || local.ts
      root.dropLocal(conv, local.ts, opts.threadTs)
      if (opts.threadTs) {
        var r2 = root.replies[key]
        if (r2) { root.replies[key] = { msgs: Model.upsert(r2.msgs, Model.patch(m, { subtype: m.subtype === "thread_broadcast" ? "" : m.subtype })), loading: r2.loading }; root.repliesRev++; root.repliesUpdated(key) }
        root.replaceEverywhere(conv, opts.threadTs, function(o) {
          var users = o.replyUsers.slice(); if (users.indexOf(root.me.id) < 0) users.push(root.me.id)
          return Model.patch(o, { replyCount: (o.replyCount || 0) + 1, latestReply: m.ts, replyUsers: users })
        }, true)
      }
      if (!opts.threadTs || m.subtype === "thread_broadcast") {
        var h2 = root.histories[conv]
        if (h2 && !h2.detached) root.setHistory(conv, { msgs: Model.upsert(h2.msgs, m), noOlder: h2.noOlder, loading: h2.loading, detached: false })
      }
      var log = root.sentLog.slice(0, 49)
      log.unshift({ conv: conv, ts: m.ts, threadTs: opts.threadTs || "", text: typed })
      root.sentLog = log
      if (root.app) root.app.setTeamSetting(root.teamId, "sentLog", log)
      root.markRead(conv, true)
    }
    root.api("chat.postMessage", params, done, function(err) {
      if (["invalid_blocks", "invalid_blocks_format", "invalid_arguments"].indexOf(err) >= 0) {
        var p2 = U.copy(params); delete p2.blocks
        root.api("chat.postMessage", p2, done, function(err2) { root.sendFailed(conv, local, opts, typed, err2) })
      } else root.sendFailed(conv, local, opts, typed, err)
    })
    return true
  }

  // Slack's "Schedule for later" (chat.scheduleMessage).
  property var scheduled: []
  property int scheduledRev: 0
  function schedule(conv, text, postAt, threadTs, blocks) {
    var typed = String(text || "").trim()
    if (!typed) return
    var p = { channel: conv, text: Markup.escape(typed), blocks: JSON.stringify(blocks || Markup.blocks(typed)), post_at: String(Math.floor(postAt)) }
    if (threadTs) p.thread_ts = threadTs
    root.api("chat.scheduleMessage", p, function() {
      root.say(root.tr("Scheduled for ", "Agendada para ") + U.dayLabel(new Date(postAt * 1000), root.lang) + " " + U.time(new Date(postAt * 1000), root.clock24))
      root.loadScheduled()
    }, function(err) { root.say(root.errorText(err)); root.restoreText(conv, threadTs || "", typed) })
  }
  function loadScheduled() {
    root.api("chat.scheduledMessages.list", { limit: 100 }, function(b) {
      root.scheduled = (b.scheduled_messages || []).map(function(m) { return { id: m.id, conv: m.channel_id, postAt: m.post_at, text: m.text || "" } })
      root.scheduledRev++
    }, function() {})
  }
  function unschedule(item) {
    root.api("chat.deleteScheduledMessage", { channel: item.conv, scheduled_message_id: item.id }, function() { root.loadScheduled() }, function(err) { root.say(root.errorText(err)) })
  }

  signal restoreText(string conv, string threadTs, string text)

  function sendFailed(conv, local, opts, typed, err) {
    root.dropLocal(conv, local.ts, opts.threadTs)
    root.say(root.tr("Not sent: ", "Não enviada: ") + root.errorText(err))
    root.restoreText(conv, opts.threadTs || "", typed)
  }

  function dropLocal(conv, ts, threadTs) {
    if (threadTs) {
      var key = conv + "/" + threadTs
      var r = root.replies[key]
      if (r) { root.replies[key] = { msgs: r.msgs.filter(function(m) { return m.ts !== ts }), loading: r.loading }; root.repliesRev++; root.repliesUpdated(key) }
    } else {
      var h = root.histories[conv]
      if (h) root.setHistory(conv, { msgs: h.msgs.filter(function(m) { return m.ts !== ts }), noOlder: h.noOlder, loading: h.loading, detached: h.detached })
    }
  }

  function editMessage(conv, ts, typed, richBlocks) {
    typed = String(typed || "").trim()
    if (!typed) { root.deleteMessage(conv, ts); return }
    var m = root.findAny(conv, ts)
    // `richBlocks`: the message box's rich_text (it checks for no change itself).
    if (m && !richBlocks && (m.text === Markup.escape(typed) || Markup.markup(m.blocks) === typed)) return
    var blocks = richBlocks || Markup.blocks(typed)
    var old = m
    root.replaceEverywhere(conv, ts, function(o) { return Model.patch(o, { text: Markup.escape(typed), blocks: blocks, edited: { user: root.me.id, ts: U.nowTs() } }) })
    var params = { channel: conv, ts: ts, text: Markup.escape(typed), blocks: JSON.stringify(blocks) }
    function fail(err) {
      if (old) root.replaceEverywhere(conv, ts, function() { return old })
      root.say(root.errorText(err))
    }
    root.api("chat.update", params, function() {}, function(err) {
      if (["invalid_blocks", "invalid_blocks_format", "invalid_arguments"].indexOf(err) >= 0) {
        var p2 = U.copy(params); p2.blocks = "[]"
        root.api("chat.update", p2, function() {}, fail)
      } else fail(err)
    })
  }

  function deleteMessage(conv, ts) {
    var m = root.findAny(conv, ts)
    root.deleteEverywhere(conv, ts)
    root.api("chat.delete", { channel: conv, ts: ts }, function() {}, function(err) {
      root.say(root.errorText(err))
      if (m) {
        root.replaceEverywhere(conv, ts, function() { return m })
        var h = root.histories[conv]
        if (h && (!m.threadTs || m.threadTs === m.ts || m.subtype === "thread_broadcast")) root.setHistory(conv, { msgs: Model.upsert(h.msgs, m), noOlder: h.noOlder, loading: h.loading, detached: h.detached })
        root.fetchHistory(conv, "poll")
      }
    })
  }

  function findAny(conv, ts) {
    var h = root.histories[conv]
    if (h) { var i = Model.indexOfTs(h.msgs, ts); if (i >= 0) return h.msgs[i] }
    for (var key in root.replies) {
      if (key.indexOf(conv + "/") !== 0) continue
      var j = Model.indexOfTs(root.replies[key].msgs, ts)
      if (j >= 0) return root.replies[key].msgs[j]
    }
    return null
  }

  // The last message of mine in a conversation (↑ in an empty box edits it).
  function lastMine(conv, threadTs) {
    var list = threadTs ? ((root.replies[conv + "/" + threadTs] || {}).msgs || []) : ((root.histories[conv] || {}).msgs || [])
    for (var i = list.length - 1; i >= 0; i--) if (Model.isMine(list[i], root.me.id) && !list[i].pending) return list[i]
    return null
  }

  function react(conv, ts, name) {
    var m = root.findAny(conv, ts)
    var mine = m && m.reactions.some(function(r) { return r.name === name && r.users.indexOf(root.me.id) >= 0 })
    var add = !mine
    root.replaceEverywhere(conv, ts, function(o) { return Model.patch(o, { reactions: root.toggledReactions(o.reactions, name, root.me.id, add) }) })
    root.api(add ? "reactions.add" : "reactions.remove", { channel: conv, timestamp: ts, name: name }, function() {}, function(err) {
      if (err === "already_reacted" || err === "no_reaction") return
      root.say(root.errorText(err))
      root.api("reactions.get", { channel: conv, timestamp: ts, full: true }, function(b) {
        var rs = ((b.message && b.message.reactions) || []).map(function(r) { return { name: r.name, users: r.users || [], count: r.count } })
        root.replaceEverywhere(conv, ts, function(o) { return Model.patch(o, { reactions: rs }) })
      }, function() {})
    })
    return add
  }

  function runSlash(conv, line, threadTs) {
    var sp = line.search(/\s/)
    var typed = (sp < 0 ? line : line.slice(0, sp)).toLowerCase()
    var args = sp < 0 ? "" : line.slice(sp + 1).trim()
    var cmd = root.commands.filter(function(c) { return c.name === typed })[0]
    if (root.commands.length && !cmd) {
      root.say(root.lang === "pt-BR" ? typed + " não é um comando válido. Para enviar uma mensagem começando com \"/\", ponha um espaço antes."
                                     : typed + " is not a valid command. To send a message starting with \"/\", put a space before it.")
      root.restoreText(conv, threadTs, line)
      return false
    }
    var canonical = cmd && cmd.aliasOf ? cmd.aliasOf : typed
    switch (canonical) {
    case "/shrug": return root.send(conv, (args + " ¯\\_(ツ)_/¯").trim(), { threadTs: threadTs })
    case "/me":
      if (!threadTs) { root.api("chat.meMessage", { channel: conv, text: Markup.escape(args) }, function() { root.fetchHistory(conv, "poll") }, function(err) { root.say(root.errorText(err)) }); return true }
      break
    case "/away": root.setAway(!root.away); return true
    case "/active": if (root.away) root.setAway(false); return true
    case "/status":
      if (!args) { if (root.app) root.app.openDialog("status"); return true }
      if (args === "clear") { root.setStatus("", "", 0); return true }
      var sm = args.match(/^(:[^\s:]+:)\s*(.*)$/)
      root.setStatus(sm ? sm[1] : "", sm ? sm[2] : args, 0)
      return true
    case "/dnd": {
      var a = args.toLowerCase().replace(/^(for|por)\s+/, "")
      if (!a || ["off", "end", "stop", "desligar", "parar"].indexOf(a) >= 0) {
        if (!a && !root.dnd) { if (root.app) root.app.openDialog("pause"); return true }
        if (root.app) root.app.resumeAll(); else root.resume()
        return true
      }
      var dm = a.match(/^(\d+)\s*([a-z]*)$/)
      if (dm) {
        var n = parseInt(dm[1], 10), unit = dm[2]
        var mult = ["", "m", "min", "mins", "minute", "minutes", "minuto", "minutos"].indexOf(unit) >= 0 ? 1 : (["h", "hr", "hrs", "hour", "hours", "hora", "horas"].indexOf(unit) >= 0 ? 60 : (["d", "day", "days", "dia", "dias"].indexOf(unit) >= 0 ? 1440 : 0))
        if (mult) { if (root.app) root.app.pauseAll(n * mult); else root.pause(n * mult); return true }
      }
      break
    }
    case "/topic":
      if (args) { root.setTopic(conv, args); return true }
      break
    case "/open": case "/join": {
      var cm = args.match(/^<#([A-Z0-9]+)/) || null
      var name = cm ? "" : args.replace(/^#/, "")
      var id = cm ? cm[1] : Object.keys(root.convs).filter(function(k) { return root.convs[k].name === name })[0]
      if (id && root.convs[id]) { root.open(id); return true }
      break
    }
    case "/msg": case "/dm": {
      var mm = args.match(/^(<@([A-Z0-9]+)>|@?([\w.\-]+))\s*(.*)$/)
      if (mm) {
        var uid = mm[2] || root.handles[mm[3]] || ""
        if (uid) {
          var text = mm[4]
          root.openDm([uid], function(cid) {
            if (text) { root.send(cid, text, {}); root.say(root.tr("✓ Sent to ", "✓ Enviada para ") + root.userName(uid)) }
            else root.open(cid)
          })
          return true
        }
      }
      break
    }
    }
    var params = { channel: conv, command: typed, disp: typed, text: Markup.escape(args) }
    if (threadTs) params.thread_ts = threadTs
    root.api("chat.command", params, function(b) {
      if (b.response) root.say(String(b.response).split("\n")[0])
    }, function(err) { root.say(root.errorText(err)); root.restoreText(conv, threadTs, line) })
    return true
  }

  // ---------------------------------------------------------------- files
  function upload(conv, files, comment, threadTs) {
    var ids = []
    var left = files.length
    var failed = false
    root.say(root.tr("Uploading…", "Enviando…"))
    files.forEach(function(f) {
      root.api("files.getUploadURLExternal", { filename: f.name, length: f.size }, function(b) {
        if (!b.upload_url) { failed = true; check(); return }
        wire.postFile(b.upload_url, f.path, function(r) {
          if (!r.ok) failed = true
          else ids.push({ id: b.file_id, title: f.name })
          check()
        })
      }, function(err) { failed = true; root.say(root.errorText(err)); check() })
    })
    function check() {
      if (--left > 0) return
      if (!ids.length) { root.say(root.tr("Upload failed", "O envio falhou")); root.restoreText(conv, threadTs, comment); return }
      var p = { files: JSON.stringify(ids), channel_id: conv }
      if (comment) p.initial_comment = Markup.escape(comment)
      if (threadTs) p.thread_ts = threadTs
      root.api("files.completeUploadExternal", p, function() {
        root.say(root.tr("Uploaded", "Enviado"))
        Qt.callLater(function() { if (threadTs) root.fetchReplies(conv, threadTs); else root.fetchHistory(conv, "poll") })
      }, function(err) { root.say(root.errorText(err)); root.restoreText(conv, threadTs, comment) })
    }
  }

  // Slack's files need the session; they are fetched once into the cache,
  // where a later session finds them again (transport.py's `reuse`, which
  // also marks them as just used: a week unseen and they're deleted).
  property var _fetching: ({})
  function fetchFile(url, name, cb) {
    if (!url) return ""
    if (root.localFiles[url]) return root.localFiles[url]
    if (root._fetching[url]) return ""
    root._fetching[url] = true
    var safe = String(name || "file").replace(/[\/\x00-\x1f]/g, "_").slice(-80)
    var hash = Qt.md5(url).slice(0, 16)
    var dest = root.cacheDir + "/files/" + root.teamId + "/" + hash + "-" + safe
    wire.download(url, dest, function(r) {
      delete root._fetching[url]
      if (r.ok) { root.localFiles[url] = r.path; root.filesRev++; if (cb) cb(r.path) }
      else if (cb) cb("")
    }, false, true)
    return ""
  }

  // Into Downloads, beside what's there: a name already taken becomes
  // "name (1).ext" (transport.py's `no_clobber`).
  function saveFile(f) {
    if (!f.download) return
    var dir = root.app ? root.app.downloadsDir : (Quickshell.env("XDG_DOWNLOAD_DIR") || (Quickshell.env("HOME") || "") + "/Downloads")
    var name = String(f.name || "").replace(/[\/\x00-\x1f]/g, "_")
    if (/^\.*$/.test(name)) name = "file"
    root.say(root.tr("Downloading ", "Baixando ") + f.name + "…")
    wire.download(f.download, dir + "/" + name, function(r) {
      if (r.ok) root.say(root.tr("Saved to ", "Salvo em ") + r.path)
      else root.say(r.error === "html" ? root.tr("Slack didn't hand over the file (session expired?)", "O Slack não entregou o arquivo (sessão expirada?)") : root.tr("Download failed: ", "Download falhou: ") + r.error)
    }, f.mimetype === "text/html", false, true)
  }

  function openFile(f) {
    var url = f.download || f.full
    if (!url) { if (f.permalink && root.app) root.app.openUrl(f.permalink); return }
    var have = root.localFiles[url]
    if (have) { Quickshell.execDetached(["touch", "-c", "--", have]); root.openLocal(have); return }
    root.say(root.tr("Opening ", "Abrindo ") + f.name + "…")
    root.fetchFile(url, f.name, function(path) { if (path) root.openLocal(path); else root.say(root.tr("Couldn't open the file", "Não abriu o arquivo")) })
  }
  // A file that would run rather than open (a script, a launcher, a
  // program, or one marked executable) shows in its folder instead.
  function openLocal(path) {
    var runs = /\.(desktop|sh|bash|zsh|fish|ksh|csh|command|run|bin|appimage|exe|msi|com|scr|bat|cmd|ps1|vbs|jar|jnlp)$/i.test(path)
    if (runs) root.say(root.tr("Showing it in its folder: this kind of file can run programs", "Mostrando na pasta: esse tipo de arquivo pode executar programas"))
    Quickshell.execDetached(["sh", "-c", 'if [ "$2" = 1 ] || [ -x "$1" ]; then exec xdg-open "${1%/*}"; fi; exec xdg-open "$1"',
                             "omaslack-open", path, runs ? "1" : "0"])
  }

  // ---------------------------------------------------------------- files
  // The rail's Files: the files you can see, newest first, a page at a time
  // (files.list: the web client's own Files hub, with its "recently
  // viewed", runs on internal methods this session can't count on), every
  // one or only yours (`who`: all | mine), and the ones you starred.
  property var fileLists: ({})        // who → {files, page, pages, total, loading, loaded, error, at}
  property int fileListsRev: 0
  property var fileStars: ({})        // file id → the file (Model.parseListedFile), starred
  property int fileStarsRev: 0
  function fileList(who) { root.fileListsRev; return root.fileLists[who] || null }
  function isFileStarred(id) { root.fileStarsRev; return !!root.fileStars[id] }

  // The first page again (`fresh`, or nothing yet), else the next one.
  function loadFiles(who, fresh) {
    var cur = root.fileLists[who]
    if (cur && cur.loading) return
    if (!fresh && cur && cur.loaded && cur.page >= cur.pages) return
    var page = fresh || !cur || !cur.loaded ? 1 : cur.page + 1
    var p = { count: 100, page: page }
    if (who === "mine") p.user = root.me.id
    root.fileLists[who] = Object.assign({ files: [], page: 0, pages: 0, total: 0, loaded: false, error: "", at: 0 }, cur || {}, { loading: true })
    root.fileListsRev++
    root.api("files.list", p, function(b) {
      var before = page === 1 ? [] : (root.fileLists[who].files || [])
      var have = {}
      before.forEach(function(f) { have[f.id] = true })
      var got = (b.files || []).filter(function(f) {
        return f && f.id && !have[f.id] && f.mode !== "tombstone" && f.mode !== "hidden_by_limit"
      }).map(Model.parseListedFile)
      var paging = b.paging || {}
      root.fileLists[who] = { files: before.concat(got), page: page, pages: paging.pages || page, total: paging.total || 0,
                              loading: false, loaded: true, error: "", at: Date.now() }
      root.fileListsRev++
    }, function(err) {
      root.fileLists[who] = Object.assign({}, root.fileLists[who], { loading: false, loaded: true, error: root.errorText(err) })
      root.fileListsRev++
    })
  }
  // A view showing the list: fetched again once it's a minute old.
  function refreshFiles(who) {
    var cur = root.fileLists[who]
    if (!cur || (!cur.loading && (!cur.loaded || Date.now() - cur.at > 60000))) root.loadFiles(who, true)
  }

  // The Files page's search box: search.files, newest first, a page at a
  // time, every file or only yours (`who`: all | mine, as `from:` asks).
  // One search at a time: the answer to an older one is dropped. A word
  // typed halfway finds nothing as it is: asked again as a prefix ("budg*").
  property var fileSearch: ({ key: "" })  // {key, words, files, page, pages, total, loading, loaded, error, at}
  property int fileSearchRev: 0
  // The search for `query` (and `who`) while it's the one asked, else null.
  function fileSearchOf(query, who) {
    root.fileSearchRev
    return root.fileSearch.key === who + "\n" + query ? root.fileSearch : null
  }
  // The first page (again when it's a minute old, or `fresh`), or the `next` one.
  function searchFiles(query, who, next, fresh) {
    var q = String(query || "").trim()
    if (!q) return
    var key = who + "\n" + q, cur = root.fileSearch, same = cur.key === key
    if (same && cur.loading) return
    if (next && (!same || !cur.loaded || cur.error || cur.page >= cur.pages)) return
    if (!next && same && cur.loaded && !cur.error && !fresh && Date.now() - cur.at < 60000) return
    var page = next ? cur.page + 1 : 1
    var last = q.split(/\s+/).pop()
    var canStar = last.length >= 2 && !/[*":]/.test(last) && last.charAt(0) !== "-"
    // Asked again, what was found stays in the meantime.
    var state = Object.assign({ files: [], words: q, page: 0, pages: 0, total: 0, loaded: false, error: "", at: 0 },
                              same ? cur : {}, { key: key, loading: true, error: "" })
    root.fileSearch = state
    root.fileSearchRev++
    function ask(words) {
      var p = { query: words + (who === "mine" ? " from:<@" + root.me.id + ">" : ""), sort: "timestamp", sort_dir: "desc", count: 50, page: page }
      root.api("search.files", p, function(b) {
        if (root.fileSearch !== state) return
        var res = b.files || {}
        if (page === 1 && !(res.matches || []).length && words === q && canStar) { ask(q + "*"); return }
        var before = page === 1 ? [] : state.files
        var have = {}
        before.forEach(function(f) { have[f.id] = true })
        var got = (res.matches || []).filter(function(f) {
          if (!f || !f.id || have[f.id] || f.mode === "tombstone" || f.mode === "hidden_by_limit") return false
          have[f.id] = true
          return true
        }).map(Model.parseListedFile)
        var paging = res.paging || {}
        root.fileSearch = { key: key, words: words, files: before.concat(got), page: page, pages: paging.pages || (res.pagination || {}).page_count || page,
                            total: paging.total || res.total || 0, loading: false, loaded: true, error: "", at: Date.now() }
        root.fileSearchRev++
      }, function(err) {
        if (root.fileSearch !== state) return
        root.fileSearch = Object.assign({}, state, { loading: false, loaded: true, error: root.errorText(err) })
        root.fileSearchRev++
      })
    }
    ask(next ? cur.words : q)
  }

  function setFileStar(f, on) {
    if (on) root.fileStars[f.id] = f
    else delete root.fileStars[f.id]
    root.fileStarsRev++
    root.api(on ? "stars.add" : "stars.remove", { file: f.id }, null, function(err) {
      if (on) delete root.fileStars[f.id]
      else root.fileStars[f.id] = f
      root.fileStarsRev++
      root.say(root.errorText(err))
    })
  }

  // ---------------------------------------------------------------- message actions
  function permalink(conv, m) { return U.permalink(root.team.domain, conv, m.ts, m.threadTs) }

  // An app's buttons, as the official client sends them: Block Kit ones to
  // blocks.actions, legacy attachment ones to chat.attachmentAction. The app
  // answers by changing the message (message_changed) or opening a window.
  property real actionSentAt: 0
  function clientToken() { return "web-" + Date.now() }
  function blockAction(conv, m, ctl, done) {
    var el = ctl.el || {}
    var act = { action_id: el.action_id || "", block_id: ctl.blockId || "", type: el.type || "button", action_ts: String(Date.now() / 1000) }
    if (el.text) act.text = el.text
    if (el.value !== undefined) act.value = el.value
    if (el.style) act.style = el.style
    var args = { actions: [act], container: { type: "message", message_ts: m.ts, channel_id: conv, is_ephemeral: !!m.ephemeral },
                 client_token: root.clientToken() }
    if (m.botId) args.service_id = m.botId
    if (m.appId) args.app_id = m.appId
    root.actionSentAt = Date.now()
    root.api("blocks.actions", args, function() { if (done) done(true) }, function(err) { root.say(root.errorText(err)); if (done) done(false) })
  }
  function attachmentAction(conv, m, ctl, done) {
    var x = ctl.legacy || {}
    var act = { id: x.id, name: x.name || "", value: x.value || "", type: x.type || "button" }
    var payload = { actions: [act], attachment_id: ctl.attachmentId, callback_id: ctl.callbackId, channel_id: conv,
                    is_ephemeral: !!m.ephemeral, thread_ts: m.threadTs || undefined, message_ts: m.ts, prompt_app_install: false }
    var args = { payload: JSON.stringify(payload), client_token: root.clientToken() }
    if (m.botId) args.service_id = m.botId
    if (m.appId) args.app_id = m.appId
    if (m.user) args.bot_user_id = m.user
    root.actionSentAt = Date.now()
    root.api("chat.attachmentAction", args, function() { if (done) done(true) }, function(err) { root.say(root.errorText(err)); if (done) done(false) })
  }

  // Slack's app install requests ("Review and Approve for Workspace"): the
  // button's callback_id is whitelist_<app>_<request>_<team>. The official
  // client finds the request (admin.apps.requests.list) for its app and
  // scopes, then approves or restricts it (admin.apps.approve / restrict).
  function appRequestOf(ctl) {
    var bits = String(ctl && ctl.callbackId || "").split("_")
    if (bits[0] !== "whitelist" || bits.length < 4 || bits[2].indexOf("Ar") !== 0) return null
    return { appId: bits[1], requestId: bits[2], teamId: bits[3] }
  }
  function teamArgs(teamId) { return /^E/.test(teamId) ? { enterprise_id: teamId } : { team_id: teamId } }
  function fetchAppRequest(req, done) {
    var pages = 0
    function page(cursor) {
      var args = U.copy(root.teamArgs(req.teamId))
      args.app_ids = req.appId
      args.limit = 1000
      args.reason = "Fetch approval request for admin resolution from message"
      if (cursor) args.cursor = cursor
      root.api("admin.apps.requests.list", args, function(body) {
        var found = (body.app_requests || []).filter(function(r) { return r.id === req.requestId })[0]
        if (found) { done(found, ""); return }
        var next = body.response_metadata && body.response_metadata.next_cursor
        if (next && ++pages < 10) page(next)
        else done(null, "")
      }, function(err) { done(null, err) })
    }
    page("")
  }
  // scopes: the request's, [{ name, description, token_type }].
  function resolveAppRequest(req, approve, scopes, done) {
    var names = function(kind) { return (scopes || []).filter(function(s) { return s.token_type === kind }).map(function(s) { return s.name }).join(",") }
    var args = U.copy(root.teamArgs(req.teamId))
    args.request_id = req.requestId
    args.reason = "make-admin-app-resolution-from-slackbot-message"
    if (names("user")) args.user_scopes = names("user")
    if (names("bot")) args.bot_scopes = names("bot")
    root.api(approve ? "admin.apps.approve" : "admin.apps.restrict", args, function() { done("") }, function(err) { done(err || "error") })
  }

  function togglePin(conv, m) {
    var on = !(m.pinnedTo && m.pinnedTo.indexOf(conv) >= 0)
    root.replaceEverywhere(conv, m.ts, function(o) {
      var p = (o.pinnedTo || []).filter(function(x) { return x !== conv })
      if (on) p.push(conv)
      return Model.patch(o, { pinnedTo: p })
    })
    root.api(on ? "pins.add" : "pins.remove", { channel: conv, timestamp: m.ts }, function() { root.loadPins(conv) }, function(err) {
      root.say(root.errorText(err))
      root.replaceEverywhere(conv, m.ts, function(o) { return Model.patch(o, { pinnedTo: m.pinnedTo }) })
    })
  }

  function loadPins(conv) {
    if (!conv) return
    root.api("pins.list", { channel: conv }, function(b) {
      var list = (b.items || []).filter(function(i) { return i.message && typeof i.message === "object" }).map(function(i) {
        return { msg: Model.parseMessage(i.message), by: i.created_by || "", created: i.created || 0 }
      }).sort(function(a, c) { return c.created - a.created })
      root.pins[conv] = list
      root.pinsRev++
    }, function() {})
  }

  function toggleSaved(conv, m) {
    var key = conv + "/" + m.ts
    var on = !root.saved[key]
    if (on) root.saved[key] = true
    else delete root.saved[key]
    root.savedRev++
    root.api(on ? "saved.add" : "saved.delete", { item_type: "message", item_id: conv, ts: m.ts }, function() {
      root.say(on ? root.tr("Saved for later", "Salvo para depois") : root.tr("Removed from Later", "Removido de Depois"))
      root.loadSaved()
    }, function(err) {
      if (on) delete root.saved[key]; else root.saved[key] = true
      root.savedRev++
      root.say(root.errorText(err))
    })
  }

  function remind(conv, m, minutes, at) {
    var when = at || Math.floor(Date.now() / 1000 + minutes * 60)
    root.api("reminders.add", { text: root.permalink(conv, m), time: String(when) }, function() {
      root.say(root.tr("Reminder created", "Lembrete criado"))
    }, function(err) { root.say(root.errorText(err)) })
  }

  function setFollow(conv, m, on) {
    var ts = m.threadTs || m.ts
    root.replaceEverywhere(conv, ts, function(o) { return Model.patch(o, { subscribed: on }) })
    root.api(on ? "subscriptions.thread.add" : "subscriptions.thread.remove", { channel: conv, thread_ts: ts }, function() {
      root.say(on ? root.tr("You'll be notified about replies", "Você será notificado das respostas") : root.tr("Reply notifications off", "Notificações de respostas desligadas"))
    }, function(err) {
      root.replaceEverywhere(conv, ts, function(o) { return Model.patch(o, { subscribed: !on }) })
      root.say(root.errorText(err))
    })
  }

  function forward(conv, m, to, comment) {
    var link = root.permalink(conv, m)
    var text = comment ? comment + "\n" + link : link
    root.send(to, text, {})
    root.say(root.tr("Forwarded to ", "Encaminhada para ") + root.convLabel(to))
  }

  // ---------------------------------------------------------------- conversations
  // The DM with someone, a deactivated account's too; "" while there's none.
  function dmWith(uid) {
    root.convsRev
    for (var id in root.convs) { var c = root.convs[id]; if (c.kind === "im" && c.user === uid) return id }
    var g = root.goneDms[uid]
    return g ? g.id : ""
  }

  function openDm(userIds, cb) {
    var mine = userIds.filter(function(u) { return u !== root.me.id })
    if (mine.length === 1) {
      for (var id in root.convs) { var c = root.convs[id]; if (c.kind === "im" && c.user === mine[0]) { if (cb) cb(id); else root.open(id); return } }
      // A deactivated account's archives: Slack won't open a new DM with
      // them, the one there was comes back to `convs` while it's open.
      var gone = root.goneDms[mine[0]]
      if (gone) {
        root.convs[gone.id] = gone
        root.convsRev++
        if (cb) cb(gone.id); else root.open(gone.id)
        return
      }
    }
    if (mine.length === 0) {
      for (var sid in root.convs) { var sc = root.convs[sid]; if (sc.kind === "im" && sc.user === root.me.id) { if (cb) cb(sid); else root.open(sid); return } }
      mine = [root.me.id]
    }
    root.api("conversations.open", { users: mine.join(","), return_im: true }, function(b) {
      var ch = b.channel || {}
      function adopt(o) {
        o.member = true
        root.convs[o.id] = o
        if (root.openIms) root.openIms[o.id] = true
        if (!root.counts[o.id]) root.counts[o.id] = { latest: U.nowTs(), lastRead: "", unread: false, mentions: 0 }
        root.convsRev++
        root.sectionsRev++
        if (cb) cb(o.id); else root.open(o.id)
      }
      if (ch.is_im === undefined && ch.is_mpim === undefined) root.api("conversations.info", { channel: ch.id }, function(b2) { adopt(Model.parseConv(b2.channel, null)) }, function(err) { root.say(root.errorText(err)) })
      else adopt(Model.parseConv(ch, root.convs[ch.id]))
    }, function(err) { root.say(root.errorText(err)) })
  }

  // `section`: a custom section the new channel goes into (its menu's
  // "Create a channel").
  function createChannel(name, isPrivate, purpose, cb, section) {
    var n = U.normalizeChannel(name)
    root.api("conversations.create", { name: n, is_private: !!isPrivate }, function(b) {
      var c = Model.parseConv(b.channel, null)
      c.member = true
      root.convs[c.id] = c
      root.convsRev++
      if (purpose) root.api("conversations.setPurpose", { channel: c.id, purpose: purpose }, function() {}, function() {})
      if (section) root.moveToSection(c.id, section, true)
      root.open(c.id)
      if (cb) cb("", c.id)
    }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  function join(conv) {
    root.api("conversations.join", { channel: conv }, function(b) {
      var d = root.directory.chans.filter(function(x) { return x.id === conv })[0]
      var c = Model.parseConv(b.channel || { id: conv }, root.convs[conv] || (d ? { id: conv, kind: "channel", name: d.name, numMembers: d.members } : null))
      c.guest = false
      c.member = true
      root.convs[conv] = c
      root.convsRev++
      root.say(root.tr("You joined #", "Você entrou em #") + c.name)
      root.loadCounts()
    }, function(err) { root.say(root.errorText(err)) })
  }

  function leave(conv, cb) {
    root.api("conversations.leave", { channel: conv }, function() {
      root.forget(conv)
      if (cb) cb("")
    }, function(err) { if (cb) cb(root.errorText(err)); else root.say(root.errorText(err)) })
  }

  function forget(conv) {
    delete root.convs[conv]
    delete root.histories[conv]
    delete root.counts[conv]
    delete root.stars[conv]
    root.convsRev++
    root.countsRev++
    root.historyRev++
    if (root.current === conv) { root.current = ""; root.openDefault() }
  }

  function closeDm(conv) {
    if (root.openIms) { delete root.openIms[conv]; root.sectionsRev++ }
    if (root.current === conv) { root.current = ""; root.openDefault() }
    root.api("conversations.close", { channel: conv }, function() {}, function() {})
  }

  function setArchived(conv, on, cb) {
    root.api(on ? "conversations.archive" : "conversations.unarchive", { channel: conv }, function() {
      if (root.convs[conv]) { root.convs[conv] = Model.patch(root.convs[conv], { archived: on }); root.convsRev++ }
      if (!on) root.say("#" + root.convLabel(conv) + root.tr(" unarchived", " desarquivado"))
      if (cb) cb("")
    }, function(err) { if (cb) cb(root.errorText(err)); else root.say(root.errorText(err)) })
  }

  function deleteChannel(conv, cb) {
    root.api("conversations.delete", { channel: conv }, function() { root.forget(conv); if (cb) cb("") }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  function convertToPrivate(conv, cb) {
    root.api("conversations.convertToPrivate", { channel: conv }, function() {
      if (root.convs[conv]) { root.convs[conv] = Model.patch(root.convs[conv], { kind: "private" }); root.convsRev++ }
      if (cb) cb("")
    }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  function rename(conv, name, cb) {
    var n = U.normalizeChannel(name)
    if (!n) { if (cb) cb(root.tr("A name is required.", "O nome é obrigatório.")); return }
    root.api("conversations.rename", { channel: conv, name: n }, function(b) {
      root.convs[conv] = Model.parseConv(b.channel || { id: conv, name: n }, root.convs[conv])
      root.convsRev++
      if (cb) cb("")
    }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  function setTopic(conv, topic, cb) {
    root.api("conversations.setTopic", { channel: conv, topic: topic }, function() {
      if (root.convs[conv]) { root.convs[conv] = Model.patch(root.convs[conv], { topic: Markup.escape(topic) }); root.convsRev++ }
      if (cb) cb("")
    }, function(err) { if (cb) cb(root.errorText(err)); else root.say(root.errorText(err)) })
  }

  function setPurpose(conv, purpose, cb) {
    root.api("conversations.setPurpose", { channel: conv, purpose: purpose }, function() {
      if (root.convs[conv]) { root.convs[conv] = Model.patch(root.convs[conv], { purpose: Markup.escape(purpose) }); root.convsRev++ }
      if (cb) cb("")
    }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  function convInfo(conv, cb) {
    root.api("conversations.info", { channel: conv, include_num_members: true }, function(b) {
      var c = Model.parseConv(b.channel, root.convs[conv])
      if (root.convs[conv]) { root.convs[conv] = c; root.convsRev++ }
      cb(c)
    }, function() { cb(root.convs[conv] || null) })
  }

  function members(conv, cb) {
    root.paginate("conversations.members", { channel: conv, limit: 200 }, "members", function(list) { cb(list) }, function() { cb([]) })
  }

  function invite(conv, userIds, cb) {
    root.api("conversations.invite", { channel: conv, users: userIds.join(",") }, function() { if (cb) cb("") }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  function setNotify(conv, level) {
    var p = root.prefs[conv] || { muted: false, desktop: "" }
    var old = { muted: p.muted, desktop: p.desktop }
    if (level === "mute") p = { muted: true, desktop: p.desktop }
    else p = { muted: false, desktop: level === "all" ? "everything" : "mentions" }
    root.prefs[conv] = p
    root.convsRev++
    root.api("users.prefs.get", {}, function(b) {
      var all = {}
      try { all = JSON.parse((b.prefs && b.prefs.all_notifications_prefs) || "{}") || {} } catch (e) { all = {} }
      if (!all.channels) all.channels = {}
      var c = all.channels[conv] || {}
      if (level === "mute") c.muted = true
      else { var v = level === "all" ? "everything" : "mentions"; c.desktop = v; c.mobile = v; c.muted = false }
      all.channels[conv] = c
      root.api("users.prefs.set", { name: "all_notifications_prefs", value: JSON.stringify(all) }, function() {
        if (typeof (b.prefs || {}).muted_channels === "string") {
          var list = b.prefs.muted_channels.split(",").filter(function(x) { return x && x !== conv })
          if (level === "mute") list.push(conv)
          root.api("users.prefs.set", { name: "muted_channels", value: list.join(",") }, function() {}, function() {})
        }
      }, function(err) { root.prefs[conv] = old; root.convsRev++; root.say(root.errorText(err)); root.loadPrefs() })
    }, function(err) { root.prefs[conv] = old; root.convsRev++; root.say(root.errorText(err)) })
  }

  // Starred = moved to the stars section; the default ones take it back.
  function setStar(conv, on) {
    if (on) root.stars[conv] = true
    else delete root.stars[conv]
    root.sectionsRev++
    var from = root.sections.filter(function(s) { return (s.type === "standard" || s.type === "custom") && s.ids.indexOf(conv) >= 0 })[0]
    root.api(on ? "stars.add" : "stars.remove", { channel: conv }, function() {
      if (from) root.moveToSection(conv, "", true)
    }, function(err) { root.say(root.errorText(err)); root.loadSections() })
  }

  function moveToSection(conv, toId, quiet) {
    var to = root.sections.filter(function(s) { return s.id === toId })[0]
    if (to && to.type === "stars") { root.setStar(conv, true); return }
    var from = root.sections.filter(function(s) { return (s.type === "standard" || s.type === "custom") && s.ids.indexOf(conv) >= 0 })[0]
    if (root.stars[conv] && !quiet) { delete root.stars[conv]; root.api("stars.remove", { channel: conv }, function() {}, function() {}) }
    var params = {}
    if (to && (to.type === "standard" || to.type === "custom")) params.insert = JSON.stringify([{ channel_section_id: to.id, channel_ids: [conv] }])
    if (from && (!to || from.id !== to.id)) params.remove = JSON.stringify([{ channel_section_id: from.id, channel_ids: [conv] }])
    // Local first.
    root.sections = root.sections.map(function(s) {
      // A user group's section is Slack's to fill: it keeps its channels.
      var ids = s.type === "user_group" ? s.ids : s.ids.filter(function(x) { return x !== conv })
      if (to && s.id === to.id && (s.type === "standard" || s.type === "custom")) ids.push(conv)
      return { id: s.id, type: s.type, name: s.name, emoji: s.emoji, next: s.next, ids: ids, hidden: !!s.hidden }
    })
    root.sectionsRev++
    if (!params.insert && !params.remove) return
    root.api("users.channelSections.channels.bulkUpdate", params, function() {}, function(err) { root.say(root.errorText(err)); root.loadSections(); root.loadBoot() })
  }

  function moveSection(id, dir) {
    var list = root.sections
    var i = list.findIndex(function(s) { return s.id === id })
    var j = i + dir
    if (i < 0 || j < 0 || j >= list.length) return
    var out = list.slice()
    var t = out[i]; out[i] = out[j]; out[j] = t
    root.sections = out
    root.sectionsRev++
    var next = out[out.findIndex(function(s) { return s.id === id }) + 1]
    root.api("users.channelSections.set", { channel_section_id: id, next_channel_section_id: next ? next.id : "" }, function() { root.loadSections() }, function(err) { root.say(root.errorText(err)); root.loadSections() })
  }

  // A section dropped before another (sidebar drag): saved as Slack's
  // linked list, "next" = the section that now follows it.
  function moveSectionBefore(id, beforeId) {
    var list = root.sections.slice()
    var from = list.findIndex(function(s) { return s.id === id })
    if (from < 0 || id === beforeId) return
    var moved = list.splice(from, 1)[0]
    var to = beforeId ? list.findIndex(function(s) { return s.id === beforeId }) : list.length
    if (to < 0) to = list.length
    list.splice(to, 0, moved)
    root.sections = list
    root.sectionsRev++
    var next = list[to + 1]
    root.api("users.channelSections.set", { channel_section_id: id, next_channel_section_id: next ? next.id : "" }, function() { root.loadSections() }, function(err) { root.say(root.errorText(err)); root.loadSections() })
  }

  // A conversation dropped on a section.
  function dropConversation(conv, section) {
    var s = root.sections.filter(function(x) { return x.id === section })[0]
    if (!s) return
    if (s.type === "stars") { if (!root.stars[conv]) root.setStar(conv, true); return }
    if (s.type === "channels" || s.type === "direct_messages") { if (root.stars[conv]) root.setStar(conv, false); root.moveToSection(conv, "", false); return }
    if (s.type === "standard" || s.type === "custom") root.moveToSection(conv, s.id, false)
  }

  function createSection(name, cb, emoji) {
    var p = { name: name }
    if (emoji) p.emoji = String(emoji).replace(/^:|:$/g, "")
    root.api("users.channelSections.create", p, function() { root.loadSections(); if (cb) cb("") }, function(err) { if (cb) cb(root.errorText(err)) })
  }

  // A custom section's name and emoji (Slack's name, no colons; "" takes
  // it off): local first, Slack's list again once it answers. `set` also
  // places the section, so its current "next" keeps it where it is.
  function renameSection(id, name, emoji, cb) {
    var e = String(emoji || "").replace(/^:|:$/g, "")
    var old = root.sections
    var sec = old.filter(function(s) { return s.id === id })[0]
    root.sections = old.map(function(s) {
      return s.id !== id ? s : { id: s.id, type: s.type, name: name, emoji: e, next: s.next, ids: s.ids }
    })
    root.sectionsRev++
    root.api("users.channelSections.set", { channel_section_id: id, name: name, emoji: e, next_channel_section_id: sec ? sec.next : "" }, function() {
      root.loadSections()
      if (cb) cb("")
    }, function(err) {
      root.sections = old
      root.sectionsRev++
      root.loadSections()
      if (cb) cb(root.errorText(err))
      else root.say(root.errorText(err))
    })
  }

  // A custom section away: its conversations go back to Channels and
  // Direct messages, as in Slack.
  function deleteSection(id, cb) {
    var old = root.sections
    root.sections = old.filter(function(s) { return s.id !== id })
    root.sectionsRev++
    root.api("users.channelSections.delete", { channel_section_id: id }, function() {
      root.loadSections()
      if (cb) cb("")
    }, function(err) {
      root.sections = old
      root.sectionsRev++
      root.loadSections()
      if (cb) cb(root.errorText(err))
      else root.say(root.errorText(err))
    })
  }

  function toggleCollapsed(id) {
    var silenced = id === "silenced"
    var now = silenced ? root.collapsed[id] !== false : !!root.collapsed[id]
    root.collapsed[id] = !now
    root.collapsedRev++
    if (root.app) root.app.saveCollapsed(root.teamId, root.collapsed)
  }

  // ---------------------------------------------------------------- account
  function setAway(on) {
    root.away = on
    root.presence[root.me.id] = !on
    root.presenceRev++
    root.api("users.setPresence", { presence: on ? "away" : "auto" }, function() {
      root.say(on ? root.tr("You're set to away", "Você está ausente") : root.tr("You're set to active", "Você está ativo"))
    }, function(err) { root.away = !on; root.presenceRev++; root.say(root.errorText(err)) })
  }

  function pause(minutes) {
    root.api("dnd.setSnooze", { num_minutes: String(Math.max(1, Math.round(minutes))) }, function() { root.loadDnd() }, function(err) { root.say(root.errorText(err)) })
  }

  function resume() {
    var snooze = !root.dnd || root.dnd.snooze
    root.api(snooze ? "dnd.endSnooze" : "dnd.endDnd", {}, function() { root.loadDnd() }, function() { root.loadDnd() })
  }

  function setStatus(emoji, text, exp) {
    if (emoji && emoji.charAt(0) !== ":") emoji = ":" + emoji + ":"
    text = String(text || "").trim().slice(0, 100)
    var u = root.users[root.me.id]
    var old = u ? { e: u.statusEmoji, t: u.statusText, x: u.statusExp } : null
    if (u) { u.statusEmoji = emoji; u.statusText = text; u.statusExp = exp || 0; u.statusUnicode = ""; u.statusUrl = ""; root.usersRev++ }
    root.api("users.profile.set", { profile: JSON.stringify({ status_text: text, status_emoji: emoji, status_expiration: exp || 0 }) }, function() {}, function(err) {
      if (u && old) { u.statusEmoji = old.e; u.statusText = old.t; u.statusExp = old.x; root.usersRev++ }
      root.say(root.errorText(err))
    })
  }

  function saveProfile(fields, photoPath, cb) {
    function info() {
      root.api("users.profile.set", { profile: JSON.stringify(fields) }, function() {
        root.api("users.info", { user: root.me.id }, function(b) { root.applyUser(b.user); root.usersRev++; if (cb) cb("") }, function() { if (cb) cb("") })
      }, function(err) { if (cb) cb(root.errorText(err)) })
    }
    if (photoPath) {
      wire.multipart("users.setPhoto", {}, photoPath, "image", U.guessMime(photoPath), function(r) {
        if (!r.ok || !r.body || !r.body.ok) { if (cb) cb(root.errorText((r.body && r.body.error) || r.error)); return }
        info()
      })
    } else info()
  }

  function profile(uid, cb) {
    root.api("users.info", { user: uid }, function(b) {
      root.applyUser(b.user)
      root.usersRev++
      cb(root.users[uid])
    }, function() { cb(root.users[uid] || null) })
    if (uid !== root.me.id) {
      root.api("users.getPresence", { user: uid }, function(b) { root.presence[uid] = b.presence === "active"; root.presenceRev++ }, function() {})
      root.api("dnd.info", { user: uid }, function(b) {
        root.othersDnd[uid] = b.snooze_enabled ? { start: 0, end: b.snooze_endtime || 0 } : (b.dnd_enabled ? { start: b.next_dnd_start_ts || 0, end: b.next_dnd_end_ts || 0 } : { start: 0, end: 0 })
        root.presenceRev++
      }, function() {})
    }
  }

  function setVip(uid, on) {
    if (on) root.vips[uid] = true
    else delete root.vips[uid]
    root.usersRev++
    root.api(on ? "users.priority.add" : "users.priority.remove", { user: uid }, function() {}, function(err) { root.say(root.errorText(err)); root.loadVips() })
  }

  function inviteToTeam(emails, channels, message, cb) {
    var invites = emails.map(function(e) { return { email: e, type: "regular", mode: "manual" } })
    var p = { invites: JSON.stringify(invites), source: "invite_modal", mode: "manual", restricted: false, ultra_restricted: false, email_password_policy_enabled: false }
    if (channels.length) { p.channels = channels.join(","); p.channel_ids = channels.join(",") }
    if (message) p.custom_message = message
    root.api("users.admin.inviteBulk", p, function(b) {
      var listed = (b.invites || []).concat(b.errors || [], b.failures || [])
      var failed = {}
      emails.forEach(function(e) {
        var item = listed.filter(function(i) { return i.email && i.email.toLowerCase() === e.toLowerCase() && (i.error || i.ok === false) })[0]
        if (item) failed[e] = root.errorText(item.error || "unknown_error")
      })
      cb(failed, "")
    }, function(err) {
      if (err === "unknown_method") {
        var left = emails.length, failed = {}
        emails.forEach(function(e) {
          var q = { email: e }
          if (channels.length) q.channels = channels.join(",")
          if (message) q.custom_message = message
          root.api("users.admin.invite", q, function() { if (--left === 0) cb(failed, "") }, function(e2) { failed[e] = root.errorText(e2); if (--left === 0) cb(failed, "") })
        })
      } else cb({}, root.errorText(err))
    })
  }

  // ---------------------------------------------------------------- search
  function searchMessages(query, sort, page, cb) {
    root.api("search.messages", { query: query, sort: sort || "timestamp", sort_dir: "desc", count: 20, page: page || 1, highlight: true }, function(b) {
      var msgs = b.messages || {}
      var hits = (msgs.matches || []).filter(function(m) { return m.channel && m.channel.id && m.ts }).map(function(m) {
        var t = (m.permalink || "").match(/thread_ts=([0-9.]+)/)
        var threadTs = t && t[1] !== m.ts ? t[1] : ""
        var kind = m.channel.is_im ? "im" : m.channel.is_mpim ? "mpim" : m.channel.is_private ? "private" : "channel"
        // An app's hit: its name and picture as its message has them (Model.author).
        var who = Model.parseMessage({ user: m.user, username: m.username, icons: m.icons, bot_profile: m.bot_profile, bot_id: m.bot_id })
        return { ts: m.ts, user: m.user || "", username: m.username || "", text: m.text || "", files: m.files || [], attachments: m.attachments || [],
                 conv: m.channel.id, convName: m.channel.name || "", convKind: kind, threadTs: threadTs, permalink: m.permalink || "",
                 botName: who.botName, botIcon: who.botIcon, botEmoji: who.botEmoji, botId: who.botId }
      })
      var paging = msgs.paging || {}
      cb({ hits: hits, pages: Math.max(1, paging.pages || 1), total: Math.max(msgs.total || 0, paging.total || 0) })
    }, function(err) { cb({ hits: [], pages: 0, total: 0, error: root.errorText(err) }) })
  }

  // A few messages around a hit, for the search preview.
  function context(conv, ts, threadTs, cb) {
    if (threadTs) {
      root.api("conversations.replies", { channel: conv, ts: threadTs, limit: 200 }, function(b) {
        var all = (b.messages || []).map(Model.parseMessage)
        var at = Math.max(1, all.findIndex(function(m) { return m.ts === ts }))
        cb(all.slice(0, 1).concat(all.slice(Math.max(1, at - 4), Math.min(all.length, at + 5))))
      }, function() { cb([]) })
      return
    }
    root.api("conversations.history", { channel: conv, latest: ts, inclusive: true, limit: 5 }, function(b1) {
      var before = (b1.messages || []).map(Model.parseMessage).reverse()
      root.api("conversations.history", { channel: conv, oldest: ts, limit: 4 }, function(b2) {
        var after = (b2.messages || []).map(Model.parseMessage).filter(function(m) { return U.cmpTs(m.ts, ts) > 0 }).sort(function(a, c) { return U.cmpTs(a.ts, c.ts) })
        cb(before.concat(after.slice(0, 4)))
      }, function() { cb(before) })
    }, function() { cb([]) })
  }

  // Single messages, fetched one by one as Later and Activity need them:
  // conv/ts → the message, null while asked, false when it can't be had.
  // A reply comes from its thread (conversations.replies takes any ts in it).
  property var oneMsgs: ({})
  property int oneRev: 0
  function fetchOne(conv, ts, threadTs) {
    var key = conv + "/" + ts
    if (root.oneMsgs[key] !== undefined) return
    root.oneMsgs[key] = null
    function got(m) { root.oneMsgs[key] = m ? Model.parseMessage(m) : false; root.oneRev++ }
    function inThread(parent) {
      root.api("conversations.replies", { channel: conv, ts: parent, oldest: ts, latest: ts, inclusive: true, limit: 2 }, function(b) {
        got((b.messages || []).filter(function(x) { return x.ts === ts })[0])
      }, function() { got(null) })
    }
    if (threadTs && threadTs !== ts) { inThread(threadTs); return }
    root.api("conversations.history", { channel: conv, latest: ts, inclusive: true, limit: 1 }, function(b) {
      var m = (b.messages || [])[0]
      if (m && m.ts === ts) got(m)
      else inThread(ts)
    }, function() { got(null) })
  }

  // The Activity feed (activity.feed, the web client's own): one page of
  // references to what happened, newest first; the messages come apart.
  function activityFeed(types, cursor, unreadOnly, cb) {
    var p = { types: types, mode: "chrono_v1", limit: 20, archive_only: false, unread_only: !!unreadOnly, priority_only: false, is_activity_inbox: true }
    if (cursor) p.cursor = cursor
    root.api("activity.feed", p, function(b) {
      cb({ items: b.items || [], cursor: (b.response_metadata && b.response_metadata.next_cursor) || "" })
    }, function(err) { cb({ items: [], cursor: "", error: root.errorText(err) }) })
  }
  // An entry read or unread again, as the web client marks it: {type, key, when}.
  function markActivity(it, read) {
    var e = { type: it.type, key: it.key, ts: it.when, feed_ts: it.when }
    if (read) root.api("activity.markRead", e)
    else root.api("activity.markUnread", { entries: [e] })
  }

  // ---------------------------------------------------------------- bar feed
  // What the bar's hover card (Widget.qml, lib/Bar.js) shows beyond the
  // counts: each unread conversation's unread messages, and the reactions
  // other people put on your messages.

  // conv → {latest, msgs}: up to five messages after where you read,
  // fetched when the card shows the conversation and again once its newest
  // message moves.
  property var unreadPreviews: ({})
  property int previewRev: 0
  function fetchUnreadPreview(conv) {
    var k = root.counts[conv]
    if (!k || !k.latest || root._asked["preview" + conv]) return
    var have = root.unreadPreviews[conv]
    if (have && have.latest === k.latest) return
    root._asked["preview" + conv] = true
    var latest = k.latest
    var params = { channel: conv, limit: 5 }
    if (k.lastRead) params.oldest = k.lastRead
    root.api("conversations.history", params, function(b) {
      var msgs = (b.messages || []).map(Model.parseMessage).filter(function(m) { return !m.hidden && !m.tombstone }).reverse()
      root.unreadPreviews[conv] = { latest: latest, msgs: msgs }
      root.previewRev++
      delete root._asked["preview" + conv]
    }, function() { delete root._asked["preview" + conv] })
  }

  // Reactions other people put on your messages, newest first: for a day
  // and at most 20, for the bar's widget. One taken back
  // leaves, and so does every one in a conversation once it is read: open
  // in front of you, or unread before and not any more.
  // [{conv, ts, name, user, at, msg, wasUnread}]. `added` comes only for
  // someone else's reaction to a message of yours (onReactionEvent); `msg`
  // is that message when it is at hand.
  property var reactionFeed: []
  property int reactionRev: 0
  function noteReaction(e, added, msg) {
    var item = e.item || {}
    var list = root.reactionFeed.filter(function(r) {
      return !(r.conv === item.channel && r.ts === item.ts && r.name === e.reaction && r.user === e.user)
    })
    var changed = list.length !== root.reactionFeed.length
    if (added) {
      var k = root.counts[item.channel]
      list.unshift({ conv: item.channel, ts: item.ts, name: e.reaction, user: e.user, at: Math.floor(Date.now() / 1000),
                     msg: msg || root.knownMessage(item.channel, item.ts), wasUnread: !!k && (k.unread || k.mentions > 0) })
      changed = true
    }
    if (!changed) return
    root.reactionFeed = list.slice(0, 20)
    root.reactionRev++
  }

  // A message already at hand: loaded, the last one heard, or in a preview.
  function knownMessage(conv, ts) {
    var m = root.findAny(conv, ts)
    if (m) return m
    if (root.lastMsgs[conv] && root.lastMsgs[conv].ts === ts) return root.lastMsgs[conv]
    var p = root.unreadPreviews[conv]
    return p ? (p.msgs.filter(function(x) { return x.ts === ts })[0] || null) : null
  }

  function pruneReactions() {
    if (!root.reactionFeed.length) return
    var now = Date.now() / 1000
    var reading = root.focused && root.view === "conv" ? root.current : ""
    var keep = root.reactionFeed.filter(function(r) {
      var k = root.counts[r.conv]
      var unread = !!k && (k.unread || k.mentions > 0) && r.conv !== reading
      if (unread) r.wasUnread = true
      return now - r.at < 86400 && r.conv !== reading && !(r.wasUnread && !unread)
    })
    if (keep.length !== root.reactionFeed.length) { root.reactionFeed = keep; root.reactionRev++ }
  }

  // While the socket is down its events don't come, but client.counts
  // (every 15 s then) still moves each conversation's newest message: the
  // messages behind it are fetched and go through maybeNotify, so they
  // are announced within 15 seconds. What was waiting at start-up is not.
  property var _heard: null           // conv → newest ts accounted for
  function noticeQuietNews() {
    var first = root._heard === null
    if (first) root._heard = {}
    for (var id in root.counts) {
      var k = root.counts[id]
      if (!k || !k.latest) continue
      var seen = root._heard[id]
      if (seen !== undefined && U.cmpTs(k.latest, seen) <= 0) continue
      root._heard[id] = k.latest
      var after = seen !== undefined ? seen : k.lastRead
      if (first || root.live || !k.unread || !after || !root.convs[id]) continue
      root.fetchQuietNews(id, after)
    }
  }
  function fetchQuietNews(conv, after) {
    root.api("conversations.history", { channel: conv, oldest: after, limit: 20 }, function(b) {
      (b.messages || []).map(Model.parseMessage).reverse().forEach(function(m) {
        if (m.user !== root.me.id && !m.ephemeral && !m.hidden) root.maybeNotify(conv, m, false)
      })
    }, function() {})
  }

  Connections {
    target: root
    function onCountsRevChanged() { root.pruneReactions(); root.noticeQuietNews() }
    function onCurrentChanged() { root.pruneReactions() }
    function onFocusedChanged() { root.pruneReactions() }
  }

  // ---------------------------------------------------------------- cache
  // The app's cache dir; before the app is handed in, the same one from the
  // environment (never a shared, guessable /tmp path).
  readonly property string cacheDir: root.app ? root.app.cacheDir
                                              : (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") || "") + "/.cache") + "/omaslack"
  readonly property string cachePath: root.cacheDir + "/team-" + root.teamId + ".json"

  FileView {
    id: cacheFile
    path: root.cachePath
    blockLoading: true
    printErrors: false
  }

  function loadCache() {
    var raw = ""
    try { raw = cacheFile.text() } catch (e) { raw = "" }
    if (!raw) return
    var c
    try { c = JSON.parse(raw) } catch (e2) { return }
    if (!c || c.v !== 1) return
    root.users = c.users || {}
    var h = {}
    for (var id in root.users) if (root.users[id].handle) h[root.users[id].handle] = id
    root.handles = h
    root.convs = c.convs || {}
    root.sections = c.sections || []
    root.stars = c.stars || {}
    root.openIms = c.openIms || null
    root.customEmoji = c.emoji || {}
    root.emojiAliases = c.aliases || {}
    root.directory = c.directory || { at: 0, chans: [] }
    root.bots = c.bots || {}
    root.botsRev++
    if (c.me && c.me.id) root.me = c.me
    if (c.team && c.team.id) root.team = c.team
    // "Active only" from the last run: the sidebar starts as it was left.
    root.hideInactive = c.hideInactive === true
    // The latest messages of the conversations opened lately: on screen at
    // once when one opens, until the newest page replaces them.
    root.recents = c.recents || []
    var msgs = c.msgs || {}
    for (var conv in msgs) {
      if (!Array.isArray(msgs[conv]) || !msgs[conv].length) continue
      root.histories[conv] = { msgs: msgs[conv].map(function(o) { return root.unpackMessage(o) }), noOlder: false, loading: false, detached: false }
      root.fromCache[conv] = true
    }
    root.usersRev++; root.convsRev++; root.sectionsRev++; root.emojiRev++; root.directoryRev++; root.historyRev++
    root.booted = Object.keys(root.convs).length > 0
  }

  // A message as the cache keeps it: without its empty fields, which
  // unpacking takes back from an empty message (every field of
  // Model.parseMessage({}) is empty).
  function packMessage(m) {
    var o = {}
    for (var k in m) {
      var v = m[k]
      if (v === "" || v === 0 || v === false || v === null || v === undefined || (Array.isArray(v) && !v.length)) continue
      o[k] = v
    }
    return o
  }
  function unpackMessage(o) {
    var m = Model.parseMessage({})
    for (var k in o) m[k] = o[k]
    return m
  }

  Timer {
    id: cacheTimer
    interval: 20000
    onTriggered: root.saveCache()
  }

  function saveCache() {
    if (!root.booted || root.signedOut) return
    var convs = {}
    for (var id in root.convs) if (!root.convs[id].guest) convs[id] = root.convs[id]
    // The last 50 messages of each recent conversation, but
    // not answers only you saw (they were for this session) nor sends still
    // on their way; a stretch away from the present (`detached`) neither.
    var recents = root.recents.filter(function(x) { return !!convs[x] })
    var msgs = {}
    recents.forEach(function(x) {
      var hist = root.histories[x]
      if (!hist || hist.detached) return
      var list = hist.msgs.filter(function(m) { return !m.ephemeral && !m.pending && !m.local })
      if (list.length) msgs[x] = list.slice(-50).map(function(m) { return root.packMessage(m) })
    })
    cacheFile.setText(JSON.stringify({ v: 1, me: root.me, team: root.team, users: root.users, convs: convs, sections: root.sections,
                                       stars: root.stars, openIms: root.openIms, emoji: root.customEmoji, aliases: root.emojiAliases,
                                       directory: root.directory, bots: root.bots, recents: recents, msgs: msgs, hideInactive: root.hideInactive }))
  }

  Component.onDestruction: if (root.booted) root.saveCache()
}
