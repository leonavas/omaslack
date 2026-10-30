import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "core"
import "ui"
import "lib/Util.js" as U
import "lib/Bar.js" as Bar
import "lib/Registry.js" as Registry
import "lib/Emoji.js" as Emoji
import "lib/Demo.js" as Demo

// The whole app, once per shell: the signed-in workspaces, preferences,
// the window, the sign-in flow and desktop notifications. The bar widget
// is only a door into it (Widget.qml).
Item {
  id: root

  // Host injection (ignored when absent).
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "omaslack"
  // Views find the app here before anything is handed to them.
  readonly property bool _registered: { Registry.service = root; return true }
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omaslack"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omaslack"
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/omaslack"
  // The session's runtime dir (a tmpfs, the user's alone, gone at logout):
  // the workspaces' caches and the sign-in window's profile, never on disk.
  // "" without one (they fall back to cacheDir and dataDir).
  readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/omaslack" : ""
  readonly property string downloadsDir: Quickshell.env("XDG_DOWNLOAD_DIR") || home + "/Downloads"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  // Videos and sounds play in the message with Qt Multimedia (qt6-multimedia),
  // which a stock Omarchy may lack: without it they stay file cards.
  // Saves to Downloads (Workspace.saveFile), for the window's downloads card
  // (DownloadsCard): their keys in order, each one's state by key:
  // {name, done, total (bytes; 0 when not known), state: running | done | failed, path, error}.
  property var saveKeys: []
  property var _saves: ({})
  property int savesRev: 0
  property int _saveSeq: 0
  function saveState(key) { root.savesRev; return root._saves[key] || null }
  function saveStarted(name) {
    var key = ++root._saveSeq
    root._saves[key] = { name: name, done: 0, total: 0, state: "running", path: "", error: "" }
    root.saveKeys = root.saveKeys.concat([key])
    return key
  }
  function saveUpdate(key, fields) {
    if (!root._saves[key]) return
    root._saves[key] = Object.assign({}, root._saves[key], fields)
    root.savesRev++
  }
  function saveDismiss(key) {
    delete root._saves[key]
    root.saveKeys = root.saveKeys.filter(function(k) { return k !== key })
  }
  readonly property bool canPlayMedia: {
    try { Qt.createQmlObject("import QtMultimedia\nimport QtQml\nQtObject {}", root, "omaslack-media-probe").destroy(); return true }
    catch (e) { return false }
  }

  // ---------------------------------------------------------------- settings
  property var settings: ({})
  property bool settingsLoaded: false
  function setting(key, fallback) { var v = root.settings[key]; return v === undefined || v === null ? fallback : v }
  function setSetting(key, value) {
    var s = U.copy(root.settings)
    s[key] = value
    root.settings = s
    saveSettingsSoon.restart()
  }

  readonly property string lang: setting("lang", (Quickshell.env("LANG") || "").indexOf("pt") === 0 ? "pt-BR" : "en")
  readonly property bool clock24: setting("clock", "24h") !== "12h"
  readonly property bool compact: setting("spacing", "comfortable") === "compact"
  readonly property bool unreadBar: setting("unreadBar", true) !== false
  readonly property bool unreadBackground: setting("unreadBackground", false) === true
  // Desktop notifications and their text are the bar widget's settings
  // ("notifications", "notificationText", pushed in `barOptions`); the app's
  // own stand in while no widget is on the bar. A switch in Preferences
  // writes both (setNotifySetting).
  readonly property bool notificationsOn: root.barOptions.notifications !== undefined ? root.barOptions.notifications !== false
                                                                                     : setting("notifications", true) !== false
  readonly property bool previewOn: root.barOptions.notificationText !== undefined ? root.barOptions.notificationText !== false
                                                                                   : setting("notificationPreview", true) !== false
  // The notification sound: "none" or one of the bundled assets/sounds/<id>.oga.
  // Unset, the old on/off switch ("sound") decides: off is "none".
  readonly property var notifySounds: ["glass-chime", "synth-pluck", "kalimba-tap", "crystal-ping", "mention",
                                       "droplet", "vibraphone", "wood-blocks", "retro-blip", "paper-chime"]
  readonly property string notifySound: {
    var v = setting("notifySound", null)
    if (v === null) return setting("sound", true) === false ? "none" : "glass-chime"
    return v === "none" || root.notifySounds.indexOf(v) >= 0 ? v : "glass-chime"
  }
  // Plays a sound with pw-play (Preferences' preview too); the freedesktop
  // one when the bundled file is missing.
  function playSound(id) {
    if (!id || id === "none") return
    Quickshell.execDetached(["sh", "-c", 'for f in "$1" /usr/share/sounds/freedesktop/stereo/message-new-instant.oga /usr/share/sounds/freedesktop/stereo/message.oga; do [ -f "$f" ] && exec pw-play "$f"; done; exit 0',
                             "sh", root.pluginDir + "/assets/sounds/" + id + ".oga"])
  }
  // The bar widget that writes its settings (shell.json), set while one is
  // on the bar.
  property var barWidget: null
  function setNotifySetting(key, value) {
    root.setSetting(key, value)
    var bw = root.barWidget
    if (bw && typeof bw.writeSetting === "function") bw.writeSetting(key === "notificationPreview" ? "notificationText" : key, value)
  }
  readonly property real zoom: setting("zoom", 1.0)
  readonly property bool slackEmoji: setting("emojiStyle", "slack") !== "system"
  // Pictures in link previews and apps' messages from other sites, which
  // load straight from them (MessageBody.imageSource). Slack's own always do.
  readonly property bool previewImages: setting("previewImages", true) !== false
  function tr(en, pt) { return root.lang === "pt-BR" ? pt : en }

  FileView {
    id: settingsFile
    path: root.configDir + "/settings.json"
    printErrors: false
    blockLoading: true
    onLoaded: {
      try { root.settings = JSON.parse(text()) || {} } catch (e) { root.settings = {} }
      root.settingsLoaded = true
    }
    onLoadFailed: { root.settings = {}; root.settingsLoaded = true }
  }

  Timer { id: saveSettingsSoon; interval: 600; onTriggered: settingsFile.setText(JSON.stringify(root.settings, null, 2)) }

  // The workspace in front and the scratchpad card's first-run check wait
  // for both files: they can still be loading when the app is complete,
  // and a currentTeam left empty shows the first workspace while none
  // counts as in front (nothing would be marked read).
  readonly property bool filesLoaded: root.settingsLoaded && root.accountsLoaded
  onFilesLoadedChanged: if (root.ready) root.startUp()
  property bool _startedUp: false
  function startUp() {
    if (root._startedUp || !root.filesLoaded) return
    root._startedUp = true
    var active = root.setting("active", "")
    root.currentTeam = root.accounts.some(function(a) { return a.teamId === active }) ? active : (root.accounts.length ? root.accounts[0].teamId : "")
    // The scratchpad's card is for a first run: signed in already, or with
    // settings written before, the app was used and it counts as seen.
    if (!root.demo && root.setting("seenScratchpadHint", null) === null && (root.accounts.length > 0 || Object.keys(root.settings).length > 0))
      root.setSetting("seenScratchpadHint", true)
    root._hintChecked = true
  }

  function teamSetting(team, key, fallback) {
    var t = (root.settings.teams || {})[team] || {}
    return t[key] === undefined ? fallback : t[key]
  }
  function setTeamSetting(team, key, value) {
    // Not for a workspace signed out of (a draft saved as its view goes).
    if (!root.accounts.some(function(a) { return a.teamId === team })) return
    var teams = U.copy(root.settings.teams || {})
    var t = U.copy(teams[team] || {})
    t[key] = value
    teams[team] = t
    root.setSetting("teams", teams)
  }
  function rememberConv(team, conv) { root.setTeamSetting(team, "lastConv", conv) }
  function saveCollapsed(team, map) { root.setTeamSetting(team, "collapsed", map) }

  // ---------------------------------------------------------------- accounts
  // [{teamId, token, cookie, domain, name, userId, icon}] — the sessions.
  // Their secrets (token and cookie) live in the system keyring (the
  // Secret Service, through secret-tool), one entry per workspace, and
  // accounts.json only says so (`vault: "keyring"`). Without a keyring they
  // stay in accounts.json, readable only by the user, as they always did.
  property var accounts: []
  property bool accountsLoaded: false
  property string currentTeam: ""
  // What each workspace has in the keyring, as stored (team → secretOf).
  property var _vaulted: ({})
  // Off once the keyring refuses a secret: for the rest of the run they're
  // saved in the file.
  property bool _vaultWorks: true

  FileView {
    id: accountsFile
    path: root.configDir + "/accounts.json"
    printErrors: false
    blockLoading: true
    onLoaded: {
      var list = []
      try { list = (JSON.parse(text()) || {}).accounts || [] } catch (e) { list = [] }
      if (root.demo) list = Demo.accounts.slice()
      // Once the whole app is there (utilWire reads the keyring).
      Qt.callLater(function() { root.unlockAccounts(list) })
    }
    onLoadFailed: {
      root.accounts = root.demo ? Demo.accounts.slice() : []
      root.accountsLoaded = true
    }
  }
  // Pretend workspaces (lib/Demo.js), for trying the app without signing in.
  readonly property bool demo: Quickshell.env("SLACKQS_DEMO") === "1"

  function secretOf(a) { return JSON.stringify({ token: a.token || "", cookie: a.cookie || "" }) }

  // The secrets of the workspaces kept in the keyring, before any of them
  // starts. One that can't be read (the keyring locked and its prompt
  // dismissed, the entry deleted, no keyring any more) asks to sign in
  // again. Sessions still in the file (saved by a version before the
  // keyring, or while there was none) move into it.
  function unlockAccounts(list) {
    var left = list.filter(function(a) { return a.vault === "keyring" }).length
    function done() {
      root.accounts = list
      root.accountsLoaded = true
      if (list.some(function(a) { return a.token && root._vaulted[a.teamId] !== root.secretOf(a) })) root.saveAccounts()
    }
    if (!left) { done(); return }
    list.forEach(function(a) {
      if (a.vault !== "keyring") return
      utilWire.secretLookup(a.teamId, function(r) {
        var s = null
        try { s = r.ok ? JSON.parse(r.secret) : null } catch (e) { s = null }
        if (s && s.token) {
          a.token = s.token
          a.cookie = s.cookie || ""
          root._vaulted[a.teamId] = root.secretOf(a)
        } else {
          console.warn("omaslack: couldn't read the session of", a.teamId, "from the keyring:", r.error || "bad entry")
          root.sessionExpired(a.teamId, "keyring")
        }
        if (--left === 0) done()
      })
    })
  }

  // Each session's secrets go to the keyring first, when they changed;
  // then accounts.json, without the secrets the keyring took (with those
  // it didn't: no keyring, the file as before).
  function saveAccounts() {
    if (root.demo) return
    var todo = root._vaultWorks ? root.accounts.filter(function(a) { return a.token && root._vaulted[a.teamId] !== root.secretOf(a) }) : []
    var left = todo.length
    if (!left) { root.writeAccounts(); return }
    todo.forEach(function(a) {
      var secret = root.secretOf(a)
      utilWire.secretStore(a.teamId, "Omaslack: " + (a.name || a.domain || a.teamId), secret, function(r) {
        if (r.ok) root._vaulted[a.teamId] = secret
        else { root._vaultWorks = false; console.warn("omaslack: no keyring, the session stays in accounts.json:", r.error) }
        if (--left === 0) root.writeAccounts()
      })
    })
  }

  // Written by transport.py (write_private): 0600 from its first byte and
  // replaced in one step, never a moment readable by others or half there.
  // A session in the keyring is only marked; so is one that's there but
  // couldn't be read this run, kept for the next.
  function writeAccounts() {
    var list = root.accounts.map(function(a) {
      var o = U.copy(a)
      delete o.vault
      if (a.token ? root._vaulted[a.teamId] === root.secretOf(a) : a.vault === "keyring") {
        delete o.token
        delete o.cookie
        o.vault = "keyring"
      }
      return o
    })
    utilWire.writePrivate("accounts.json", JSON.stringify({ accounts: list }, null, 2), function(r) {
      if (!r.ok) console.warn("omaslack: couldn't save the accounts:", r.error)
    })
  }

  function accountSeen(teamId, info) {
    var changed = false
    var list = root.accounts.map(function(a) {
      if (a.teamId !== teamId) return a
      var b = U.copy(a)
      for (var k in info) if (info[k] && b[k] !== info[k]) { b[k] = info[k]; changed = true }
      return b
    })
    if (changed) { root.accounts = list; root.saveAccounts() }
  }

  function addAccount(acc) {
    var list = root.accounts.filter(function(a) { return a.teamId !== acc.teamId })
    var at = root.accounts.findIndex(function(a) { return a.teamId === acc.teamId })
    if (at >= 0) list.splice(at, 0, acc)
    else list.push(acc)
    root.accounts = list
    root.saveAccounts()
    root.currentTeam = acc.teamId
    root.setSetting("active", acc.teamId)
  }

  // Signing out forgets the workspace here, and only here: its session (and
  // its keyring entry), its cache and fetched files, its drafts, sent
  // messages and place in settings.json. Nothing is revoked on Slack's side
  // (a pasted session may be your browser's own). With the last one gone,
  // the sign-in window's browser profile (its cookies) and cache go too.
  function signOut(teamId) {
    root.workspaces.forEach(function(w) { if (w.teamId === teamId) w.signedOut = true })
    root.accounts = root.accounts.filter(function(a) { return a.teamId !== teamId })
    root.saveAccounts()
    delete root._vaulted[teamId]
    utilWire.secretClear(teamId)
    if (root.currentTeam === teamId) root.currentTeam = root.accounts.length ? root.accounts[0].teamId : ""
    var teams = U.copy(root.settings.teams || {})
    delete teams[teamId]
    root.setSetting("teams", teams)
    if (root.setting("active", "") === teamId) root.setSetting("active", root.currentTeam)
    // A Slack id, or nothing is deleted (files/<id> sits beside files/avatars).
    if (!/^[A-Z0-9]+$/.test(String(teamId))) return
    var gone = [(root.runDir || root.cacheDir) + "/team-" + teamId + ".json", root.cacheDir + "/files/" + teamId]
    if (!root.accounts.length && !loginProc.running) gone.push(root.webProfile, root.webCache)
    Quickshell.execDetached(["rm", "-rf", "--"].concat(gone))
  }

  function switchTo(teamId) {
    if (!root.accounts.some(function(a) { return a.teamId === teamId })) return
    root.currentTeam = teamId
    root.setSetting("active", teamId)
  }
  function switchBy(delta) {
    var i = root.accounts.findIndex(function(a) { return a.teamId === root.currentTeam })
    if (i < 0 || root.accounts.length < 2) return
    var n = (i + delta + root.accounts.length) % root.accounts.length
    root.switchTo(root.accounts[n].teamId)
  }

  // ---------------------------------------------------------------- workspaces
  property var workspaces: []
  readonly property var current: {
    var list = root.workspaces
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].teamId === root.currentTeam) return list[i]
    return list.length ? list[0] : null
  }
  readonly property bool signedIn: root.accounts.length > 0

  Instantiator {
    id: spaces
    // Keyed by team: an account whose name or icon changes keeps its workspace.
    model: ScriptModel { values: root.accountsLoaded && root.settingsLoaded ? root.accounts : []; objectProp: "teamId" }
    delegate: Workspace {
      required property var modelData
      account: modelData
      app: root
      onAuthFailed: error => root.sessionExpired(modelData.teamId, error)
      onNotify: info => root.notifyFrom(this, info)
    }
    onObjectAdded: (index, object) => {
      var list = root.workspaces.slice()
      list.splice(index, 0, object)
      root.workspaces = list
      var collapsed = root.teamSetting(object.teamId, "collapsed", null)
      if (collapsed) object.collapsed = collapsed
      var last = root.teamSetting(object.teamId, "lastConv", "")
      if (last && !object.current) Qt.callLater(function() { object.open(last, { noHistory: true }) })
      var drafts = root.teamSetting(object.teamId, "drafts", null)
      if (drafts) { object.drafts = drafts; object.draftsRev++ }
      var sent = root.teamSetting(object.teamId, "sentLog", null)
      if (sent) object.sentLog = sent
    }
    onObjectRemoved: (index, object) => {
      root.workspaces = root.workspaces.filter(function(w) { return w !== object })
    }
  }

  // The token stopped working: back to the sign-in screen for it.
  property var expired: ({})
  // "keyring": its secrets couldn't be read, which says more than the
  // refusal its workspace then gets from Slack.
  function sessionExpired(teamId, error) {
    var e = U.copy(root.expired)
    if (e[teamId] !== "keyring") e[teamId] = error
    root.expired = e
  }

  // Badges, summed over every workspace.
  readonly property var attention: {
    var out = { mentions: 0, dms: 0, channels: 0, total: 0 }
    root.workspaces.forEach(function(w) {
      var a = w.attention
      out.mentions += a.mentions; out.dms += a.dms; out.channels += a.channels; out.total += a.total
    })
    return out
  }
  readonly property bool paused: root.workspaces.some(function(w) { return w.dnd !== null })

  function pauseAll(minutes) { root.workspaces.forEach(function(w) { w.pause(minutes) }) }
  function resumeAll() { root.workspaces.forEach(function(w) { if (w.dnd) w.resume() }) }

  // ---------------------------------------------------------------- window
  property bool windowOpen: Quickshell.env("SLACKQS_OPEN") === "1"
  property bool windowFocused: false
  property string pendingDialog: ""
  signal dialogRequested(string name, var args)

  // Shown, put away or closed, the way the bar widget's settings say
  // (`barOptions`, pushed by Widget.qml): a click on the focused window
  // parks it in a Hyprland special workspace (Omarchy's scratchpad,
  // SUPER+S), where it stays as it was, or leaves it be; a window opened
  // with "Open in Scratchpad" goes straight there, and one opened in the
  // background (Launch in Foreground off) is born there, unseen. Closing it
  // (hideWindow) unmaps it; the app keeps counting and notifying either way.
  property var barOptions: ({ specialName: "scratchpad", openInSpecial: false, hideMode: "Special workspace", launchForeground: true })
  property bool autoStarted: false
  // Without what would split a hyprctl command (`;` between batch commands,
  // `,` between a dispatcher's arguments) or a line.
  readonly property string specialName: String(root.barOptions.specialName || "").replace(/[;,\x00-\x1f]/g, "") || "scratchpad"
  readonly property var toplevel: root.windowOpen ? root.ourToplevel() : null
  readonly property bool parked: root.workspaceOf(root.toplevel) === "special:" + root.specialName
  readonly property bool specialShown: {
    var m = Hyprland.focusedMonitor
    var ipc = m ? m.lastIpcObject : null
    var s = ipc ? ipc["specialWorkspace"] : null
    return !!s && String(s.name || "") === "special:" + root.specialName
  }
  // The window where you can see it: open, and on a workspace a monitor is
  // showing (the scratchpad shown, when parked). GIFs and busy rings only
  // move then: each of their frames is a redraw, seen or not. Not reported
  // by Hyprland (yet): seen.
  readonly property bool onScreen: {
    if (!root.windowOpen) return false
    var t = root.toplevel
    if (!t) return true
    var ws = root.workspaceOf(t)
    if (ws.indexOf("special:") === 0) {
      var ms = Hyprland.monitors ? (Hyprland.monitors.values || []) : []
      for (var i = 0; i < ms.length; i++) {
        var ipc = ms[i].lastIpcObject
        var s = ipc ? ipc["specialWorkspace"] : null
        if (s && String(s.name || "") === ws) return true
      }
      return false
    }
    return !t.workspace || t.workspace.active
  }
  // On while a background launch puts the window away: when the launch rule
  // missed, Hyprland focuses it for a moment on the way, which must not
  // count as reading it.
  property bool stowing: false

  function showWindow() {
    if (!root.windowOpen) { root.launchWindow(true); return }
    if (root.barOptions.openInSpecial === true) {
      // Out on a workspace (opened before "Open in Scratchpad" was on, or
      // moved there): into the scratchpad, not silent, so it opens with it.
      if (!root.parked) { var address = root.windowAddress(); if (address) root.moveWindow(address, "special:" + root.specialName, false) }
      else if (!root.specialShown) root.toggleSpecial()
    } else if (root.parked) root.moveToActive()
    root.raiseSoon()
  }
  function hideWindow() { root._launchPending = false; root.endLaunch(); root.windowOpen = false }
  // Left click: open it, bring it back, put it away.
  function toggleWindow() {
    if (!root.windowOpen) root.launchWindow(root.barOptions.launchForeground !== false)
    else if (root.windowFocused && root.barOptions.hideMode === "Special workspace") root.park()
    else root.showWindow()
  }

  // A Quickshell window maps where Hyprland's window rules send it, so one
  // headed for the scratchpad (a background launch, or "Open in
  // Scratchpad") is born there. For the launch it carries a one-time title
  // (`launchTitle`, shown by AppWindow instead of its own), and a named
  // rule for exactly that title and our app id, set before it maps, sends
  // it to the special workspace: silently and without the focus in the
  // background (nothing shows on the current workspace, the focus and the
  // cursor stay where they were), opening the scratchpad with it in the
  // foreground. Once Hyprland reports it (openwindow) the title goes back
  // and the rule is switched off. Hyprlang configs get the same rules with
  // `keyword`, which can't be taken back but name a title no window will
  // have again; a window a rule missed still maps on the current workspace
  // and is moved once Hyprland lists it, as before.
  property bool _launchForeground: true
  property string _launchBack: ""
  property bool _launchPending: false
  property string _launchWorkspace: ""
  property string launchTitle: ""
  readonly property string launchRule: "omaslack-launch"
  function launchWindow(foreground) {
    if (root._launchPending) return
    root._launchForeground = foreground
    root._launchBack = root.lastOtherAddress
    root._launchWorkspace = ""
    root._ourAddress = ""
    root.stowing = !foreground
    if (foreground && root.barOptions.openInSpecial !== true) { root.mapLaunch(); return }
    root.launchTitle = "omaslack-launch-" + Math.random().toString(36).slice(2, 10)
    root._launchPending = true
    launchRuleProc.command = Hyprland.usingLua === true
      ? ["hyprctl", "eval", root.launchRuleLua(true)]
      : ["hyprctl", "--batch", root.launchRuleLegacy()]
    launchRuleProc.running = true
    launchRuleWait.restart()
  }
  // The window maps once the rule is in (or Hyprland took too long to say).
  function mapLaunch() {
    root._launchPending = false
    launchRuleWait.stop()
    root.windowOpen = true
    placeTimer.ticks = 0
    placeTimer.restart()
  }
  Process {
    id: launchRuleProc
    onExited: (code, status) => { if (root._launchPending) root.mapLaunch() }
  }
  Timer { id: launchRuleWait; interval: 1000; onTriggered: if (root._launchPending) root.mapLaunch() }

  function luaString(text) { return '"' + String(text).replace(/["\\]/g, "\\$&").replace(/[\x00-\x1f]/g, "") + '"' }
  // One name per kind of launch: a named rule is declared again on each
  // launch, and a foreground one must not keep a background one's effects.
  function launchRuleLua(on) {
    var spec = ["name = " + root.luaString(root.launchRule + (root._launchForeground ? "-fg" : "-bg")), "enabled = " + on,
                "match = { class = \"^org[.]quickshell$\", title = " + root.luaString("^" + root.launchTitle + "$") + " }"]
    var special = "special:" + root.specialName
    if (on && root._launchForeground) spec.push("workspace = " + root.luaString(special))
    else if (on) spec.push("workspace = " + root.luaString(special + " silent"), "no_initial_focus = true",
                           "focus_on_activate = false", 'suppress_event = "activate activatefocus"')
    return "hl.window_rule({ " + spec.join(", ") + " })"
  }
  // Both syntaxes, today's and the windowrulev2 one: the one Hyprland
  // doesn't know is refused and changes nothing.
  function launchRuleLegacy() {
    var ws = "special:" + root.specialName + (root._launchForeground ? "" : " silent")
    var cls = "^(org\\.quickshell)$", title = "^(" + root.launchTitle + ")$"
    var rules = ["keyword windowrule workspace " + ws + (root._launchForeground ? "" : ", no_initial_focus on")
                   + ", match:class " + cls + ", match:title " + title,
                 "keyword windowrulev2 workspace " + ws + ", class:" + cls + ", title:" + title]
    if (!root._launchForeground) rules.push("keyword windowrulev2 noinitialfocus, class:" + cls + ", title:" + title)
    return rules.join(" ; ")
  }
  // The window is in: its own title back, the rule off.
  function endLaunch() {
    if (!root.launchTitle) return
    if (Hyprland.usingLua === true) Quickshell.execDetached(["hyprctl", "eval", root.launchRuleLua(false)])
    root.launchTitle = ""
  }

  Timer {
    id: placeTimer
    property int ticks: 0
    interval: 50
    repeat: true
    onTriggered: {
      var address = root.windowAddress()
      if (!address && ++ticks < 60 && root.windowOpen) return
      stop()
      root.endLaunch()
      if (!address || !root.windowOpen) { root.stowing = false; return }
      root._ourAddress = root.bareAddress(address.slice(8))
      root.tagWindow(address.slice(8))
      var special = "special:" + root.specialName
      var there = (root._launchWorkspace || root.workspaceOf(root.ourToplevel())) === special
      if (!root._launchForeground) {
        if (there) stowEnd.restart()
        else { root.moveWindow(address, special, true); backgroundFix.restart() }
      } else if (root.barOptions.openInSpecial === true) {
        // Not silent: the scratchpad opens with it.
        if (!there) root.moveWindow(address, special, false)
        root.raiseSoon()
      } else root.raiseSoon()
    }
  }

  // Only when the launch rule missed. Moving the window that just took the
  // focus makes Hyprland refocus, and its pick can be a window in the
  // scratchpad, which opens it on screen. A background launch puts that
  // back: scratchpad hidden, focus on the window you were using. Checked
  // against hyprctl rather than the cached monitor state, which lags the
  // events by a beat.
  Timer {
    id: backgroundFix
    interval: 200
    onTriggered: {
      var lua = Hyprland.usingLua === true
      var hide = lua ? "hl.dsp.workspace.toggle_special(" + root.luaString(root.specialName) + ")" : "togglespecialworkspace " + root.specialName
      var back = root._launchBack
      var focus = back.length === 0 ? "" : lua ? "hl.dsp.focus({ window = " + root.luaString(back) + " })" : "focuswindow " + back
      Quickshell.execDetached(["bash", "-c",
        'shown=$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | .specialWorkspace.name\'); '
        + '[ "$shown" = "special:$1" ] && hyprctl dispatch "$2" >/dev/null; '
        + '[ -n "$3" ] && hyprctl dispatch "$3" >/dev/null; exit 0',
        "slack-background", root.specialName, hide, focus])
      stowEnd.restart()
    }
  }
  Timer { id: stowEnd; interval: 300; onTriggered: root.stowing = false }

  function park() {
    var address = root.windowAddress()
    if (!address) return
    if (root.parked && root.specialShown) { root.toggleSpecial(); return }
    root.moveWindow(address, "special:" + root.specialName, true)
  }

  // The workspace under the scratchpad when the focus is in it: the
  // focused monitor's own (Hyprland lists the special one apart).
  function moveToActive() {
    var address = root.windowAddress()
    var ws = Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.name || "") : ""
    if (!ws || ws.indexOf("special:") === 0) {
      var m = Hyprland.focusedMonitor
      var ipc = m ? m.lastIpcObject : null
      ws = ipc && ipc["activeWorkspace"] ? String(ipc["activeWorkspace"]["name"] || "") : ""
    }
    if (address && ws && ws.indexOf("special:") !== 0) root.moveWindow(address, ws, false)
  }

  // ---------------------------------------------------------------- scratchpad hint
  // The special workspace is a dimmed layer over the one you're on, which
  // reads as something broken the first time. So the first time the window
  // shows there, a card in it says what that is (AppWindow's
  // `scratchpadCard`): Got it, or Open as a normal window, which turns
  // "Open in Scratchpad" off in the bar's settings, as its menu does, and
  // brings the window out onto the workspace you're on. Either one is for
  // good ("seenScratchpadHint" in settings.json). Only on a first run: a
  // workspace signed in or a settings.json at start-up is an app used
  // before, and the card counts as seen (start-up, below).
  property bool _hintChecked: false
  property bool _hintDue: false
  readonly property bool inScratchpad: root.windowOpen && root.parked && root.specialShown
  onInScratchpadChanged: {
    if (root.inScratchpad && root._hintChecked && root.barOptions.openInSpecial === true
        && root.setting("seenScratchpadHint", false) !== true) root._hintDue = true
  }
  readonly property bool scratchpadHint: root._hintDue && root.windowOpen && root.barOptions.openInSpecial === true
                                         && root.setting("seenScratchpadHint", false) !== true
  function dismissScratchpadHint(asWindow) {
    root._hintDue = false
    root.setSetting("seenScratchpadHint", true)
    if (asWindow) root.openAsWindow()
  }
  // "Open in Scratchpad" off (the bar widget's setting, in shell.json; here
  // at once, before the widget hands it back) and the window out of it.
  function openAsWindow() {
    var bw = root.barWidget
    if (bw && typeof bw.writeSetting === "function") bw.writeSetting("openInSpecial", false)
    var options = U.copy(root.barOptions)
    options.openInSpecial = false
    root.barOptions = options
    if (root.parked) { root.moveToActive(); unparkFix.restart() }
    else root.raiseSoon()
  }
  // A scratchpad that still holds other windows stays on screen over the
  // workspace the window went to: put away, as it was before Slack opened it.
  Timer {
    id: unparkFix
    interval: 250
    onTriggered: {
      var hide = Hyprland.usingLua === true ? "hl.dsp.workspace.toggle_special(" + root.luaString(root.specialName) + ")" : "togglespecialworkspace " + root.specialName
      Quickshell.execDetached(["bash", "-c",
        'shown=$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | .specialWorkspace.name\'); '
        + '[ "$shown" = "special:$1" ] && hyprctl dispatch "$2" >/dev/null; exit 0',
        "slack-unpark", root.specialName, hide])
      root.raiseSoon()
    }
  }

  function hyprDispatch(luaForm, legacyForm) {
    Hyprland.dispatch(Hyprland.usingLua === true ? luaForm : legacyForm)
  }
  function moveWindow(address, workspace, silent) {
    root.hyprDispatch("hl.dsp.window.move({ window = " + root.luaString(address) + ", workspace = " + root.luaString(workspace) + (silent ? ", silent = true" : "") + " })",
                      (silent ? "movetoworkspacesilent " : "movetoworkspace ") + workspace + "," + address)
  }
  function toggleSpecial() {
    root.hyprDispatch("hl.dsp.workspace.toggle_special(" + root.luaString(root.specialName) + ")", "togglespecialworkspace " + root.specialName)
  }

  function windowAddress() {
    var t = root.ourToplevel()
    if (!t || !t.address) return ""
    var a = String(t.address)
    return "address:" + (a.indexOf("0x") === 0 ? a : "0x" + a)
  }
  function workspaceOf(t) {
    if (!t) return ""
    if (t.workspace && t.workspace.name) return String(t.workspace.name)
    var ipc = t.lastIpcObject
    return ipc && ipc["workspace"] && ipc["workspace"]["name"] ? String(ipc["workspace"]["name"]) : ""
  }

  // The window you were using, to give the focus back to after a
  // background launch.
  property string lastOtherAddress: ""
  Connections {
    target: Hyprland
    // The monitors' cached state (`specialShown`) follows the scratchpad.
    function onRawEvent(event) {
      if (event.name === "activespecial" || event.name === "activespecialv2") Hyprland.refreshMonitors()
    }
    function onActiveToplevelChanged() {
      var t = Hyprland.activeToplevel
      if (!t || !t.address || root.isOurToplevel(t) || root.workspaceOf(t).indexOf("special:") === 0) return
      var a = String(t.address)
      root.lastOtherAddress = "address:" + (a.indexOf("0x") === 0 ? a : "0x" + a)
    }
  }
  function openDialog(name, args) { root.showWindow(); root.dialogRequested(name, args || {}) }

  // Focus the window through Hyprland (a click on the bar doesn't move focus).
  function raiseSoon() { raiseTimer.restart() }
  // Our window: Quickshell's app id and AppWindow's title ("… - Slack", or
  // the launch's one-time one). The title alone is not enough: the Slack
  // desktop app's ends the same way (its class is "slack"). The address
  // Hyprland reported it with (openwindow, which carries the class) wins.
  readonly property string appClass: "org.quickshell"
  property string _ourAddress: ""
  function bareAddress(a) { a = String(a || ""); return a.indexOf("0x") === 0 ? a.slice(2) : a }
  function isOurTitle(title) {
    title = String(title || "")
    return (root.launchTitle !== "" && title === root.launchTitle) || title === "Slack" || / - Slack$/.test(title)
  }
  function classOf(t) {
    if (t.wayland && t.wayland.appId) return String(t.wayland.appId)
    var ipc = t.lastIpcObject
    return ipc ? String(ipc["class"] || ipc["initialClass"] || "") : ""
  }
  function isOurToplevel(t) {
    if (!t) return false
    var cls = root.classOf(t)
    if (cls && cls !== root.appClass) return false
    if (root._ourAddress && root.bareAddress(t.address) === root._ourAddress) return true
    // A class not known yet: only the launch's one-time title is surely ours.
    return cls ? root.isOurTitle(t.title) : root.launchTitle !== "" && String(t.title || "") === root.launchTitle
  }
  function ourToplevel() {
    var list = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
    if (root._ourAddress) for (var i = 0; i < list.length; i++) if (root.bareAddress(list[i].address) === root._ourAddress) return list[i]
    for (var j = 0; j < list.length; j++) if (root.isOurToplevel(list[j])) return list[j]
    return null
  }
  Timer {
    id: raiseTimer
    interval: 150
    onTriggered: {
      var t = root.ourToplevel()
      if (!t || !t.address) return
      var addr = String(t.address)
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      Hyprland.dispatch(Hyprland.usingLua === true ? 'hl.dsp.focus({ window = "address:' + addr + '" })' : "focuswindow address:" + addr)
      root.tagWindow(addr)
    }
  }

  // The window is Quickshell's, and its app id (org.quickshell) is the whole
  // shell's, so docks would draw Quickshell's icon for it. A Hyprland tag,
  // "icon:<path>", names ours for the bar widgets that read it
  // (a workspaces or dock widget). Hiding the window closes it for Hyprland, so it's
  // tagged on every open (and on every raise, for a window kept across a
  // shell reload); adding a tag it already has changes nothing.
  readonly property string appIcon: root.pluginDir + "/assets/slack.svg"
  function tagWindow(address) {
    var addr = String(address || "")
    if (!addr) return
    if (addr.indexOf("0x") !== 0) addr = "0x" + addr
    var tag = "+icon:" + root.appIcon
    Hyprland.dispatch(Hyprland.usingLua === true
                      ? 'hl.dsp.window.tag({ tag = "' + tag.replace(/["\\]/g, "\\$&") + '", window = "address:' + addr + '" })'
                      : "tagwindow " + tag + " address:" + addr)
  }
  // Also where a launch ends: the window is in, wherever the rule put it.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "closewindow") {
        if (root._ourAddress && root.bareAddress(event.data) === root._ourAddress) root._ourAddress = ""
        return
      }
      if (event.name !== "openwindow") return
      var f = event.parse(4)   // address, workspace, class, title
      if (f.length < 4 || f[2] !== root.appClass || !root.isOurTitle(f[3])) return
      root._ourAddress = root.bareAddress(f[0])
      root.tagWindow(f[0])
      if (root.launchTitle !== "" && f[3] === root.launchTitle) {
        root._launchWorkspace = String(f[1])
        root.endLaunch()
      }
    }
  }

  function openConversation(teamId, conv, ts, threadTs) {
    if (teamId) root.switchTo(teamId)
    var w = root.current
    if (!w) return
    root.showWindow()
    w.open(conv, { ts: ts || "", threadTs: threadTs || "" })
  }

  Theme {
    id: themeObj
    zoom: root.zoom
  }
  readonly property alias theme: themeObj
  readonly property var window: windowLoader.item

  // The window is made once the app is complete (views read it at birth).
  property bool ready: false
  LazyLoader {
    id: windowLoader
    active: root.ready
    AppWindow { app: root }
  }
  readonly property var appWindow: windowLoader.item

  // ---------------------------------------------------------------- sign in
  property bool loginRunning: false
  property string loginError: ""
  property string loginStatus: ""
  property var _loginResult: null
  // Its cookies and storage hold the sessions: in the runtime dir, never on
  // disk (transport.py's op_read_cookie looks for it in the same place).
  readonly property string webProfile: (root.runDir || root.dataDir) + "/webview"
  // The sign-in window's HTTP cache (its profile's cachePath, Login.qml).
  readonly property string webCache: root.cacheDir + "/webview"

  Process {
    id: loginProc
    // Chromium's sandbox stays on: Qt only asks whether
    // QTWEBENGINE_DISABLE_SANDBOX is set (any value turns it off), so it's
    // taken out of what the window inherits (null), and again by the launcher.
    environment: ({ QT_FORCE_STDERR_LOGGING: "1", QTWEBENGINE_DISABLE_SANDBOX: null })
    stdout: SplitParser { onRead: data => root.loginLine(data) }
    stderr: SplitParser { onRead: data => root.loginLine(data) }
    onExited: (code, status) => { purgeSoon.restart(); root.loginExited(code) }
  }

  // The sign-in window's caches (Slack's pages and scripts, ~100 MB: the
  // HTTP cache, and the code, GPU and service-worker caches it leaves in
  // the profile), useless once it's closed. Cookies and storage stay until
  // you log out (the profile is in the runtime dir): they keep the window
  // signed in, so adding a workspace or signing in again skips the
  // password. A moment after the window quits (its web processes
  // go with it), and never while one is open again.
  Timer { id: purgeSoon; interval: 2000; onTriggered: root.purgeWebCache() }
  function purgeWebCache() {
    if (loginProc.running) return
    var p = root.webProfile + "/"
    Quickshell.execDetached(["rm", "-rf", "--", root.webCache, p + "Cache", p + "Code Cache", p + "GPUCache", p + "GrShaderCache", p + "ShaderCache",
                             p + "DawnGraphiteCache", p + "DawnWebGPUCache", p + "Service Worker/CacheStorage"])
  }

  function startLogin(workspace) {
    if (root.loginRunning) return
    root.loginError = ""
    root.loginStatus = root.tr("Sign in to Slack in the window that opened…", "Entre no Slack na janela que abriu…")
    root._loginResult = null
    var known = root.accounts.map(function(a) { return a.teamId }).join(",")
    var qml = root.pluginDir + "/login/Login.qml"
    loginProc.command = ["bash", "-c", 'unset QTWEBENGINE_DISABLE_SANDBOX; bin=$(command -v qml6 || true); [ -x "$bin" ] || bin=/usr/lib/qt6/bin/qml; [ -x "$bin" ] || bin=$(command -v qml); exec "$bin" "$@"',
                         "qml", qml, "--", root.webProfile, known, root.lang, String(workspace || "").trim(), root.webCache, U.chromeUa()]
    root.loginRunning = true
    loginProc.running = true
  }

  function cancelLogin() { if (loginProc.running) loginProc.signal(15) }

  function loginLine(line) {
    var at = line.indexOf("SLACKQS-RESULT ")
    if (at >= 0) {
      try { root._loginResult = JSON.parse(line.slice(at + 15)) } catch (e) {}
      return
    }
    if (line.indexOf("SLACKQS-STATUS ") >= 0) root.loginStatus = line.slice(line.indexOf("SLACKQS-STATUS ") + 15)
    if (/module "QtWebEngine" is not installed|QtWebEngine.*not installed/.test(line)) root.loginError = root.tr("Install the qt6-webengine package to use the sign-in window, or sign in with a token.", "Instale o pacote qt6-webengine para usar a janela de login, ou entre com um token.")
  }

  function loginExited(code) {
    var res = root._loginResult
    if (!res || !res.token) {
      root.loginRunning = false
      root.loginStatus = ""
      if (!root.loginError && code !== 0 && code !== 1 && code !== 15 && code !== 143) root.loginError = root.tr("The sign-in window closed unexpectedly (exit " + code + ").", "A janela de login fechou inesperadamente (saída " + code + ").")
      return
    }
    root.loginStatus = root.tr("Checking the session…", "Conferindo a sessão…")
    utilWire.readCookie(root.webProfile + "/Cookies", function(r) {
      if (!r.ok || !r.cookie) {
        root.loginRunning = false
        root.loginStatus = ""
        root.loginError = root.tr("Signed in, but the session cookie wasn't saved. Try again.", "Entrou, mas o cookie da sessão não foi salvo. Tente de novo.")
        return
      }
      root.checkSession(res.token, r.cookie, function(err) {
        root.loginRunning = false
        root.loginStatus = ""
        if (err) root.loginError = err
        else root.shareCookie(res.team, r.cookie)
      })
    })
  }

  Transport { id: utilWire }

  Component {
    id: probeComponent
    Transport { }
  }

  // Slack's `d` cookie is one per browser, every workspace's, and signing
  // in again replaces it: the one the other workspaces were added with
  // stops working. Each that takes the new one (auth.test with its token)
  // gets it; one that doesn't (a session pasted from another browser)
  // keeps its own.
  function shareCookie(teamId, cookie) {
    root.accounts.forEach(function(a) {
      if (a.teamId === teamId || !a.token || a.cookie === cookie || a.token.indexOf("xoxc-") !== 0) return
      var probe = probeComponent.createObject(root, { token: a.token, cookie: cookie })
      probe.call("auth.test", {}, function(r) {
        probe.destroy()
        if (!r.ok || !r.body || !r.body.ok || r.body.team_id !== a.teamId) return
        var e = U.copy(root.expired); delete e[a.teamId]; root.expired = e
        root.accounts = root.accounts.map(function(b) {
          if (b.teamId !== a.teamId) return b
          var c = U.copy(b)
          c.cookie = cookie
          return c
        })
        root.saveAccounts()
      })
    })
  }

  // auth.test with these credentials; on success the workspace is added.
  function checkSession(token, cookie, cb) {
    token = String(token || "").trim()
    cookie = String(cookie || "").trim()
    if (token.indexOf("xox") !== 0) { cb(root.tr("The token starts with xoxc- or xoxp-.", "O token começa com xoxc- ou xoxp-.")); return }
    if (token.indexOf("xoxc-") === 0 && !cookie) { cb(root.tr("A xoxc- token needs the d cookie (xoxd-…).", "Um token xoxc- precisa do cookie d (xoxd-…).")); return }
    var probe = probeComponent.createObject(root, { token: token, cookie: cookie })
    probe.call("auth.test", {}, function(r) {
      probe.destroy()
      if (!r.ok || !r.body || !r.body.ok) {
        var err = r.ok ? (r.body && r.body.error) || "?" : r.error
        cb(err === "invalid_auth" || err === "not_authed"
           ? root.tr("Slack refused: check the token and the cookie.", "O Slack recusou: confira o token e o cookie.")
           : root.tr("Couldn't sign in: ", "Não foi possível entrar: ") + err)
        return
      }
      var b = r.body
      var domain = String(b.url || "").replace(/^https?:\/\//, "").split(".")[0]
      var e = U.copy(root.expired); delete e[b.team_id]; root.expired = e
      root.addAccount({ teamId: b.team_id, token: token, cookie: cookie, domain: domain, name: b.team || domain, userId: b.user_id, icon: "" })
      cb("")
    })
  }

  // ---------------------------------------------------------------- notifications
  // One notification per message that notifies you in Slack
  // (Workspace.maybeNotify: DMs, mentions, channels set to every message,
  // replies in threads you follow) and per reaction to your messages (but
  // not in a muted channel, Workspace.maybeNotifyReaction); none
  // while paused (Slack's do-not-disturb) or for the conversation open on
  // screen. The summary is who wrote, and where outside a DM; the body the
  // message with its bold, italic and strikethrough (or only "New message");
  // the icon their photo. A click runs, in Omarchy's notification center,
  // the IPC call that opens the conversation at that message, so it still
  // works after a shell restart. A message heard twice (the socket and a
  // catch-up fetch) notifies once.
  property real _lastSound: 0
  property var _notifiedIds: ({})
  property var _notifiedOrder: []

  function firstNotice(key) {
    if (root._notifiedIds[key]) return false
    root._notifiedIds[key] = true
    root._notifiedOrder.push(key)
    while (root._notifiedOrder.length > 200) delete root._notifiedIds[root._notifiedOrder.shift()]
    return true
  }

  function notifyFrom(w, info) {
    if (!root.notificationsOn || Quickshell.env("SLACKQS_READONLY") === "1") return
    var reaction = info.kind === "reaction"
    if (!root.firstNotice([info.team, info.conv, info.ts, reaction ? info.reaction + "/" + info.user : ""].join("|"))) return
    var c = w.conv(info.conv)
    var label = w.convLabel(info.conv)
    var where = !c || c.kind === "im" ? "" : c.kind === "mpim" ? label : "#" + label
    var title = "", body = "", photo = ""
    if (reaction) {
      var who = w.userName(info.user) || root.tr("Someone", "Alguém")
      var reactor = w.user(info.user)
      photo = reactor ? String(reactor.avatar || "") : ""
      title = where ? who + " · " + where : who
      if (info.threadTs) title += root.tr(" (thread)", " (conversa)")
      // The emoji as a character; the workspace's own as :name:, as the
      // message bodies have them. Then the message, with its text on.
      var r = Emoji.resolve(info.reaction, {}, w.emojiAliases)
      var glyph = r && r.glyph ? r.glyph : ":" + String(info.reaction).split("::")[0] + ":"
      body = U.escapeHtml(root.tr("reacted ", "reagiu com ") + glyph + root.tr(" to your message", " à sua mensagem"))
      var said = root.previewOn && info.msg ? Bar.notificationHtml(info.msg, w.renderCtx(themeObj.html, 16)) : ""
      if (said) body += ": " + said
    } else {
      var m = info.msg
      var a = w.author(m)
      var person = m.user ? w.user(m.user) : null
      photo = a.icon || (person ? String(person.avatar || "") : "")
      title = (a.name || label || "?") + (where ? " · " + where : "")
      if (info.threadTs) title += root.tr(" (thread)", " (conversa)")
      body = root.previewOn ? Bar.notificationHtml(m, w.renderCtx(themeObj.html, 16)) : ""
      if (!body) body = root.tr("New message", "Nova mensagem")
    }
    if (root.workspaces.length > 1) title += " · " + (w.team.name || "")
    var open = info.threadTs ? ["omarchy-shell", "-q", "omaslack", "openThread", String(info.team), String(info.conv), String(info.ts), String(info.threadTs)]
                             : ["omarchy-shell", "-q", "omaslack", "openAt", String(info.team), String(info.conv), String(info.ts)]
    root.sendNotification(title, body, photo, open)
    if (root.notifySound !== "none" && Date.now() - root._lastSound > 1500) {
      root._lastSound = Date.now()
      root.playSound(root.notifySound)
    }
  }

  // The photo is fetched once into the cache, by its URL (a new photo is a
  // new file; a week unused and it goes, as the files do); Slack's mark
  // while it is missing or didn't come. One drawn inline (an SVG data URL,
  // the demo's) is written there as it is. `open` is the click's argv.
  function sendNotification(title, body, photo, open) {
    var url = String(photo || "")
    var svgUrl = "data:image/svg+xml;utf8,"
    var drawn = url.indexOf(svgUrl) === 0 ? decodeURIComponent(url.slice(svgUrl.length)) : ""
    var file = drawn ? root.photosDir + "/" + Qt.md5(url) + ".svg" : (url.indexOf("https://") === 0 ? root.photosDir + "/" + root.photoName(url) : "")
    Quickshell.execDetached(["bash", "-c",
      'f="$1"; u="$2"; icon="$3"; drawn="$4"; shift 4; '
      + 'if [ -n "$f" ]; then '
      + '[ -s "$f" ] && touch "$f" || { mkdir -p "${f%/*}" && { if [ -n "$drawn" ]; then printf %s "$drawn" > "$f.part"; else curl -fsSL -m 4 -o "$f.part" "$u"; fi; } '
      + '&& mv -f "$f.part" "$f" || rm -f "$f.part"; }; '
      + '[ -s "$f" ] && icon="$f"; '
      + 'fi; '
      + 'exec notify-send "--icon=$icon" "$@"',
      "slack-notify", file, url, root.appIcon, drawn,
      "--app-name=Slack", "--hint=string:omarchy-exec-argv:" + JSON.stringify(open), title, body])
  }

  // ---------------------------------------------------------------- photos
  // People's photos (and apps' and workspaces' icons) are kept on disk by
  // their URL, beside the notifications' (a new photo is a new URL, so a new
  // file; a week unseen and it goes, as the files do), and the avatars show
  // them from there, decoded on the spot: one seen before is up at once,
  // this session or the next, with no initials in between. (Qt keeps only a
  // few decoded pictures, and the shell no HTTP cache: anything else came
  // from Slack again, every time.) One not there yet loads from Slack
  // meanwhile and is fetched behind it, a batch at a time.
  readonly property string photosDir: root.cacheDir + "/files/avatars"
  property int photosRev: 0
  property bool _photosListed: false
  property var _photoNames: ({})    // url → its file's name
  property var _photosHere: ({})    // file name → on disk
  property var _photosUsed: ({})    // file name → touched this session
  property var _photosAsked: ({})   // url → fetched (once a session)
  property var _photoQueue: []      // name, url, name, url…
  property var _photoTouches: []

  function photoName(url) {
    var name = root._photoNames[url]
    if (!name) {
      var ext = ((url.match(/\.(png|jpe?g|gif|webp)(?:[?#]|$)/i) || [])[1] || "jpg").toLowerCase()
      name = root._photoNames[url] = Qt.md5(url) + "." + ext
    }
    return name
  }

  // The photo at `url` as a file:// URL when it's on disk, else "" (and,
  // unless `peek`, it's fetched there).
  function photoFile(url, peek) {
    root.photosRev
    url = String(url || "")
    if (url.indexOf("https://") !== 0) return ""
    var name = root.photoName(url)
    if (root._photosHere[name]) {
      if (!root._photosUsed[name]) {
        root._photosUsed[name] = true
        root._photoTouches.push(root.photosDir + "/" + name)
        Qt.callLater(root._touchPhotosSoon)
      }
      return "file://" + root.photosDir + "/" + name
    }
    if (!peek && root._photosListed && !root._photosAsked[url]) {
      root._photosAsked[url] = true
      root._photoQueue.push(name, url)
      Qt.callLater(root._fetchPhotos)
    }
    return ""
  }

  // One on disk that didn't decode (cut short, or gone): out of the way,
  // and from Slack again (fetched anew unless it already was this session).
  function photoFailed(url) {
    var name = root._photoNames[String(url || "")]
    if (!name || !root._photosHere[name]) return
    delete root._photosHere[name]
    Quickshell.execDetached(["rm", "-f", "--", root.photosDir + "/" + name])
    if (!photosLanded.running) photosLanded.start()
  }

  // A dozen side by side; each one printed as it lands. One already there
  // (a notification's) is only marked as just used.
  function _fetchPhotos() {
    if (photoFetch.running || !root._photoQueue.length) return
    photoFetch.command = ["bash", "-c",
      'd="$1"; shift; mkdir -p "$d" || exit 0; '
      + 'get() { [ -s "$1" ] && { touch -c -- "$1"; return 0; }; local t="$1.$BASHPID.part"; '
      + 'curl -fsSL -m 15 -o "$t" "$2" && [ -s "$t" ] && mv -f -- "$t" "$1" && return 0; rm -f -- "$t"; return 1; }; '
      + 'while [ $# -ge 2 ]; do { get "$d/$1" "$2" && printf "%s\\n" "$1"; } & shift 2; done; wait',
      "omaslack-photos", root.photosDir].concat(root._photoQueue.splice(0, 24))
    photoFetch.running = true
  }
  Process {
    id: photoFetch
    stdout: SplitParser {
      onRead: data => {
        root._photosHere[String(data).trim()] = true
        if (!photosLanded.running) photosLanded.start()
      }
    }
    onExited: (code, status) => Qt.callLater(root._fetchPhotos)
  }
  // Those that landed, in one go: every avatar looks again.
  Timer { id: photosLanded; interval: 120; onTriggered: root.photosRev++ }

  // What's on disk, at the start. Only the week's: older ones are on their
  // way out (lifecycle), and fetched again if still in use.
  Process {
    id: photoList
    command: ["find", root.photosDir, "-maxdepth", "1", "-type", "f", "-size", "+0", "-mtime", "-7", "!", "-name", "*.part", "-printf", "%f\\n"]
    stdout: SplitParser { onRead: data => { root._photosHere[String(data).trim()] = true } }
    onExited: (code, status) => { root._photosListed = true; root.photosRev++ }
  }

  // Their last use, for the week: once a session, a batch at a time.
  function _touchPhotosSoon() { if (!photosTouch.running) photosTouch.start() }
  Timer {
    id: photosTouch
    interval: 3000
    onTriggered: {
      if (root._photoTouches.length) Quickshell.execDetached(["touch", "-c", "--"].concat(root._photoTouches.splice(0)))
    }
  }

  // ---------------------------------------------------------------- utilities
  function copy(text) {
    Quickshell.execDetached(["wl-copy", "--", String(text)])
  }

  // A link from a message: a permalink to this workspace opens here; out
  // of the app only web pages and mail (no file:, slack:, or any scheme
  // that would hand it to some other program).
  function openUrl(url) {
    url = String(url || "").trim()
    if (!url) return
    var link = U.parsePermalink(url)
    if (link && root.current && url.indexOf((root.current.team.domain || "-") + ".slack.com") >= 0) {
      root.current.open(link.conv, { ts: link.ts, threadTs: link.threadTs })
      return
    }
    if (!/^(https?:\/\/|mailto:)/i.test(url)) { console.warn("omaslack: not opening a link of this kind:", url.slice(0, 40)); return }
    Qt.openUrlExternally(url)
  }

  // ---------------------------------------------------------------- updates
  // New versions of the plugin: the button over your photo (core/Updater.qml).
  Updater { id: updaterObj; app: root }
  readonly property alias updater: updaterObj

  // ---------------------------------------------------------------- lifecycle
  Component.onCompleted: {
    // Ours alone: the dirs 0700 (an existing one too), the sessions 0600
    // (one saved looser by an older version, or by hand).
    Quickshell.execDetached(["sh", "-c", 'mkdir -p -m 700 -- "$@" && chmod 700 -- "$@"; [ -f "$1/accounts.json" ] && chmod 600 -- "$1/accounts.json"; exit 0',
                             "omaslack-dirs", root.configDir, root.cacheDir, root.runDir || root.dataDir])
    // What versions before the runtime dir left on disk: the workspaces'
    // caches (messages, the people) and the sign-in window's profile (the
    // sessions, in its cookies and storage). The first start after fetches
    // the caches again; the next sign-in asks for the password once.
    if (root.runDir) Quickshell.execDetached(["sh", "-c", 'rm -rf -- "$1"/team-*.json "$2"', "omaslack-old", root.cacheDir, root.dataDir])
    photoList.running = true
    Registry.service = root
    root.ready = true
    Qt.callLater(function() {
      root.startUp()
      // Images of files fetched with the session: a week unseen is enough.
      // Their modification time is their last use (reused ones are touched:
      // transport.py's `reuse`, Workspace.openFile), so what you keep
      // looking at stays. Images pasted into the composer go after a week too.
      Quickshell.execDetached(["find", root.cacheDir + "/files", root.cacheDir + "/paste", "-type", "f", "-mtime", "+7", "-delete"])
    })
  }

  Component.onDestruction: {
    if (Registry.service === root) Registry.service = null
    if (root.settingsLoaded) settingsFile.setText(JSON.stringify(root.settings, null, 2))
  }

  IpcHandler {
    target: "omaslack"
    function toggle(): void { root.toggleWindow() }
    function show(): void { root.showWindow() }
    function hide(): void { root.hideWindow() }
    function open(url: string): void { root.showWindow(); root.openUrl(url) }
    // A notification's click: the conversation (or the thread) at that message.
    function openAt(team: string, conv: string, ts: string): void { root.openConversation(team, conv, ts, "") }
    function openThread(team: string, conv: string, ts: string, threadTs: string): void { root.openConversation(team, conv, ts, threadTs) }
    function pause(minutes: int): void { root.pauseAll(minutes) }
    function resume(): void { root.resumeAll() }
    // Demo mode only (SLACKQS_DEMO=1): something happens in the workspace
    // you're in, as its socket would tell it: "reaction" (people react to
    // one of your messages) or "message" (a new DM).
    function demoEvent(kind: string): string {
      if (!root.demo || !root.current) return "demo mode only"
      root.current.playDemo(kind)
      return "ok"
    }
    function status(): string {
      return JSON.stringify({ signedIn: root.signedIn, attention: root.attention, paused: root.paused,
                              workspaces: root.workspaces.map(function(w) { return { id: w.teamId, name: w.team.name, live: w.live, booted: w.booted } }) })
    }
  }
}
