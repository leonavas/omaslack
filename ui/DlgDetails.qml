import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Mrkdwn.js" as Md

// Slack's channel details: the name with the star and the notifications
// pill, then About (name, topic, description, who made it, leave),
// Members (search, add people, profiles) and Settings (private, archive,
// delete). Group DMs only have Members.
DialogFrame {
  id: d
  cardWidth: t.sp(640)
  initialFocus: d.tab === "members" ? (d.adding ? addInput : search) : null

  readonly property string convId: args.conv || ""
  property var fresh: null
  property bool infoDone: false
  readonly property var c: (d.ws ? d.ws.conv(d.convId) : null) || d.fresh
  readonly property bool group: !!d.c && d.c.kind === "mpim"
  readonly property bool priv: !!d.c && d.c.kind === "private"
  readonly property bool archived: !!d.c && !!d.c.archived
  readonly property bool general: !!d.c && !!d.c.general
  readonly property bool member: !!d.c && d.c.member !== false && !d.c.guest
  // How the texts name it: #name, or just the name when private.
  readonly property string hashName: d.c ? (d.group ? d.ws.convLabel(d.convId) : (d.priv ? "" : "#") + d.c.name) : ""

  property string tab: d.group ? "members" : (["about", "members", "settings"].indexOf(args.tab) >= 0 ? args.tab : "about")
  property var memberIds: []
  property bool membersLoaded: false
  property string editing: ""        // name | topic | purpose
  property string busy: ""           // the action waiting for Slack
  property string error: ""
  property string confirm: ""        // leave | archive | convert | delete
  property bool deleteChecked: false
  property bool adding: false
  property var picked: []
  property int sel: 0
  property var life: ({ on: true })
  Component.onDestruction: d.life.on = false

  title: d.c ? (d.group ? d.ws.convLabel(d.convId) : (d.priv ? "󰌾 " : "# ") + d.c.name)
             : (d.infoDone ? d.app.tr("Conversation not found", "Conversa não encontrada") : "")

  readonly property int paneH: Math.max(t.sp(160), Math.min(t.sp(470), d.maxHeight - t.sp(190)))
  readonly property var ctx: d.ws ? d.ws.renderCtx(d.t.html, d.t.emojiPx) : null

  Component.onCompleted: {
    var c = d.ws ? d.ws.conv(d.convId) : null
    if (c && c.kind === "im") {
      // A 1:1 DM has no details: its person's profile instead.
      d.ws.profileUser = c.user
      d.ws.thread = null
      Qt.callLater(function() { d.closed() })
      return
    }
    var life = d.life
    d.ws.convInfo(d.convId, function(x) { if (life.on) { d.fresh = x; d.infoDone = true } })
    d.loadMembers()
    if (d.args.edit && !d.group) { d.tab = "about"; Qt.callLater(function() { if (life.on) d.startEdit(d.args.edit) }) }
    if (d.args.add && !d.group) { d.tab = "members"; d.adding = true }
  }

  function loadMembers() {
    var life = d.life
    d.ws.members(d.convId, function(list) {
      if (!life.on) return
      d.memberIds = list || []
      d.membersLoaded = true
    })
  }

  function setTab(name) {
    if (d.group && name !== "members") return
    d.tab = name
    d.editing = ""
    d.confirm = ""
    d.deleteChecked = false
    d.error = ""
    d.adding = false
    d.picked = []
    Qt.callLater(d.focusTab)
  }
  function focusTab() {
    if (!d.life.on) return
    if (d.tab === "members") { if (d.adding) addInput.forceActiveFocus(); else search.forceActiveFocus() }
    else d.forceActiveFocus()
  }

  // A run of Slack's mrkdwn as text to edit: links as their address,
  // mentions as names.
  function plain(s) {
    var w = d.ws
    return String(s || "").replace(/<([^>|]+)(?:\|([^>]*))?>/g, function(all, target, label) {
      if (/^@[UWB]/.test(target)) return "@" + (w.userName(target.slice(1)) || label || target.slice(1))
      if (/^#[CGD]/.test(target)) return "#" + (label || ((w.conv(target.slice(1)) || {}).name) || "")
      if (target.charAt(0) === "!") return label || "@" + target.slice(1).split("^")[0]
      if (target.indexOf("mailto:") === 0) return target.slice(7)
      return target
    }).replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
  }

  function link(url) {
    var m = String(url || "").match(/^slackqs:\/\/(user|channel)\/([A-Z0-9]+)$/)
    if (m) {
      var w = d.ws
      d.closed()
      if (m[1] === "user") { w.profileUser = m[2]; w.thread = null }
      else w.open(m[2])
      return
    }
    d.app.openUrl(url)
  }

  // ------------------------------------------------------------ edits
  function startEdit(key) {
    if (d.archived || !d.c) return
    d.confirm = ""
    d.error = ""
    d.editing = key
  }
  function cancelEdit() { d.editing = ""; d.error = ""; d.forceActiveFocus() }

  function save(key, text) {
    if (d.busy) return
    var w = d.ws, life = d.life, app = d.app, win = d.win
    var done = function(okText) {
      return function(err) {
        if (!life.on) return
        d.busy = ""
        if (err) { d.error = err; return }
        d.editing = ""
        d.error = ""
        d.forceActiveFocus()
        if (okText) win.toast(okText)
      }
    }
    if (key === "name") {
      var n = U.normalizeChannel(text).replace(/^[-_]+|[-_]+$/g, "")
      if (!n) { d.error = app.tr("Give the channel a name.", "Dê um nome ao canal."); return }
      if (n === d.c.name) { d.cancelEdit(); return }
      d.busy = "name"
      w.rename(d.convId, n, done(app.tr("Channel renamed", "Canal renomeado")))
    } else if (key === "topic") {
      var tp = String(text).replace(/\s*\n\s*/g, " ").trim()
      if (tp === d.plain(d.c.topic).trim()) { d.cancelEdit(); return }
      d.busy = "topic"
      w.setTopic(d.convId, tp, done(app.tr("Topic saved", "Tópico salvo")))
    } else if (key === "purpose") {
      var pp = String(text).trim()
      if (pp === d.plain(d.c.purpose).trim()) { d.cancelEdit(); return }
      d.busy = "purpose"
      w.setPurpose(d.convId, pp, done(app.tr("Description saved", "Descrição salva")))
    }
  }

  // ------------------------------------------------------------ actions
  function leave() {
    if (d.busy) return
    if (d.priv && d.confirm !== "leave") { d.confirm = "leave"; return }
    var w = d.ws, life = d.life, win = d.win, app = d.app, name = d.hashName
    d.busy = "leave"
    w.leave(d.convId, function(err) {
      if (!life.on) return
      d.busy = ""
      if (err) { d.error = err; return }
      win.toast(app.tr("You left ", "Você saiu de ") + name)
      d.closed()
    })
  }

  function archive(on) {
    if (d.busy) return
    var w = d.ws, life = d.life, win = d.win, app = d.app
    d.busy = on ? "archive" : "unarchive"
    d.error = ""
    w.setArchived(d.convId, on, function(err) {
      if (!life.on) return
      d.busy = ""
      d.confirm = ""
      if (err) { d.error = err; return }
      if (on) win.toast(app.tr("Channel archived", "Canal arquivado"))
    })
  }

  function makePrivate() {
    if (d.busy) return
    var w = d.ws, life = d.life, win = d.win, app = d.app
    d.busy = "convert"
    d.error = ""
    w.convertToPrivate(d.convId, function(err) {
      if (!life.on) return
      d.busy = ""
      d.confirm = ""
      if (err) { d.error = err; return }
      win.toast(app.tr("The channel is now private", "O canal agora é privado"))
    })
  }

  function destroyChannel() {
    if (d.busy || !d.deleteChecked) return
    var w = d.ws, life = d.life, win = d.win, app = d.app
    d.busy = "delete"
    d.error = ""
    w.deleteChannel(d.convId, function(err) {
      if (!life.on) return
      d.busy = ""
      if (err) { d.error = err; return }
      win.toast(app.tr("Channel deleted", "Canal apagado"))
      d.closed()
    })
  }

  function notifyMenu(item) {
    var w = d.ws, id = d.convId
    var level = w.notifyLevel(id)
    d.win.menuAt(item, [
      { header: d.app.tr("Notify you about…", "Notificar você sobre…") },
      { label: d.app.tr("All new messages", "Todas as novas mensagens"), checked: level === "all", action: function() { w.setNotify(id, "all") } },
      { label: d.app.tr("Mentions", "Menções"), checked: level === "mentions", action: function() { w.setNotify(id, "mentions") } },
      { label: d.app.tr("Mute", "Silenciar"), checked: level === "mute", action: function() { w.setNotify(id, "mute") } }
    ], 0, item.height + d.t.sp(4))
  }

  // Focus comes back from a menu.
  Connections {
    target: d.win
    ignoreUnknownSignals: true
    function onMenusShownChanged() { if (d.win && !d.win.menusShown) Qt.callLater(d.focusTab) }
  }

  // ------------------------------------------------------------ fast search
  // U.rank's tiers over names folded once per person or channel (folding
  // is what costs with thousands of them).
  property var _folds: ({})
  function index(id, names) {
    var key = names.join("\u0001")
    var f = d._folds[id]
    if (f && f.key === key) return f
    f = { key: key, parts: names.filter(function(s) { return !!s }).map(function(s) {
      var n = U.fold(s), toks = U.tokens(s)
      return { n: n, sep: n.replace(/[\s._-]+/g, " "), toks: toks, ini: toks.map(function(w) { return w[0] }).join("") }
    }) }
    d._folds[id] = f
    return f
  }
  function needle(q) {
    var f = U.fold(q).replace(/^[#@]/, "").trim()
    return { q: f, sep: f.replace(/[\s._-]+/g, " "), toks: U.tokens(f) }
  }
  function rankPart(p, Q) {
    if (!Q.q) return 5
    if (p.n === Q.q) return 0
    if (p.sep.indexOf(Q.sep) === 0) return 1
    var qt = Q.toks, nt = p.toks, i, k
    if (!qt.length) return -1
    var j = 0
    for (i = 0; i < nt.length && j < qt.length; i++) if (nt[i].indexOf(qt[j]) === 0) j++
    if (j === qt.length) return 2
    var all = true
    for (k = 0; k < qt.length && all; k++) {
      var hit = false
      for (i = 0; i < nt.length && !hit; i++) hit = nt[i].indexOf(qt[k]) === 0
      all = hit
    }
    if (all) return 3
    if (qt.length > 1) return -1
    var t0 = qt[0]
    if (t0.length >= 2 && t0.length <= 12 && nt.length >= 2 && p.ini.indexOf(t0) === 0) return 4
    if (p.n.indexOf(t0) >= 0) return 5
    if (t0.length >= 4) {
      for (k = 0; k < nt.length; k++) {
        var w = nt[k]
        // One edit leaves one of these letters in place; skip the rest.
        if (w[0] !== t0[0] && w[1] !== t0[1] && w[0] !== t0[1] && w[1] !== t0[0]) continue
        if (U.oneTypo(w.slice(0, t0.length + 1), t0)) return 6
      }
    }
    return -1
  }
  // Best tier over the names (-1: no match).
  function score(id, names, Q) {
    var f = d.index(id, names), r = -1
    for (var i = 0; i < f.parts.length; i++) { var x = d.rankPart(f.parts[i], Q); if (x >= 0 && (r < 0 || x < r)) r = x }
    return r
  }
  // Folds everyone's names ahead, a slice at a time, so the first
  // keystroke in a big workspace doesn't stall.
  Timer {
    property var ids: null
    property int at: 0
    interval: 1
    repeat: true
    running: !!d.ws
    onTriggered: {
      var users = d.ws.users
      if (!ids) ids = Object.keys(users)
      var end = Math.min(ids.length, at + 600)
      for (; at < end; at++) { var u = users[ids[at]]; if (u) d.index(ids[at], [u.name || "", u.real || "", u.handle || ""]) }
      if (at >= ids.length) stop()
    }
  }

  // ------------------------------------------------------------ members
  readonly property bool canAdd: !d.group && !d.archived && d.member
  readonly property var shownMembers: {
    var w = d.ws
    if (!w) return []
    w.usersRev
    return d.memberIds.filter(function(uid) { var u = w.users[uid]; return !(u && u.deleted) })
  }
  readonly property var memberRows: {
    var w = d.ws
    if (!w) return []
    w.usersRev
    var q = search.text.trim(), out = [], Q = d.needle(q)
    d.shownMembers.forEach(function(uid) {
      var u = w.users[uid]
      var r = !q ? 0 : (u ? d.score(uid, [u.name || "", u.real || "", u.handle || ""], Q) : -1)
      if (r < 0) return
      out.push({ key: uid, kind: "user", id: uid, rank: r, name: (u ? u.name : uid).toLowerCase() })
    })
    out.sort(function(a, b) { return a.rank - b.rank || (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)) })
    if (!q && d.canAdd) out.unshift({ key: "+add", kind: "add" })
    return out
  }

  function openMember(i) {
    var r = d.memberRows[i]
    if (!r) return
    if (r.kind === "add") { d.startAdding(); return }
    var w = d.ws
    d.closed()
    w.profileUser = r.id
    w.thread = null
  }

  function copyNames() {
    var w = d.ws
    var names = d.shownMembers.map(function(uid) { return w.userName(uid) || uid })
    d.app.copy(names.join(", "))
    d.win.toast(names.length + d.app.tr(" names copied", " nomes copiados"))
  }

  readonly property string addQuery: addInput.text.trim()
  onAddQueryChanged: d.sel = 0
  readonly property var candidates: {
    var w = d.ws
    if (!w || !d.adding) return []
    w.usersRev
    var q = d.addQuery, me = w.me.id, out = [], inside = {}, Q = d.needle(q)
    d.memberIds.forEach(function(x) { inside[x] = true })
    for (var id in w.users) {
      var u = w.users[id]
      if (!u || u.bot || u.deleted || id === me || inside[id] || d.picked.indexOf(id) >= 0) continue
      var r = q ? d.score(id, [u.name || "", u.real || "", u.handle || ""], Q) : 0
      if (r < 0) continue
      out.push({ key: id, id: id, rank: r, name: (u.name || "").toLowerCase() })
    }
    out.sort(function(a, b) { return a.rank - b.rank || (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)) })
    return out.slice(0, 60)
  }

  function startAdding() { d.adding = true; d.picked = []; d.error = ""; Qt.callLater(d.focusTab) }
  function stopAdding() { d.adding = false; d.picked = []; d.error = ""; addInput.text = ""; Qt.callLater(d.focusTab) }
  function pickPerson(i) {
    var o = d.candidates[i]
    if (!o) return
    d.picked = d.picked.concat([o.id])
    addInput.text = ""
    d.error = ""
  }
  function unpickPerson(uid) { d.picked = d.picked.filter(function(x) { return x !== uid }); addInput.forceActiveFocus() }
  function moveSel(delta) {
    var n = d.candidates.length
    if (!n) return
    d.sel = Math.max(0, Math.min(n - 1, d.sel + delta))
    addList.positionViewAtIndex(d.sel, ListView.Contain)
  }

  function addPeople() {
    if (d.busy) return
    if (d.addQuery !== "" && d.candidates.length) d.pickPerson(d.sel)
    if (!d.picked.length) { d.error = d.app.tr("Pick at least one person.", "Escolha pelo menos uma pessoa."); return }
    var w = d.ws, life = d.life, win = d.win, app = d.app, n = d.picked.length
    d.busy = "add"
    d.error = ""
    w.invite(d.convId, d.picked.slice(), function(err) {
      if (!life.on) return
      d.busy = ""
      if (err) { d.error = err; return }
      win.toast(n === 1 ? app.tr("1 person added to the channel", "1 pessoa adicionada ao canal") : n + app.tr(" people added to the channel", " pessoas adicionadas ao canal"))
      d.stopAdding()
      d.loadMembers()
    })
  }

  // Alt+1/2/3: About, Members, Settings.
  Keys.onPressed: event => {
    if (!(event.modifiers & Qt.AltModifier)) return
    var name = event.key === Qt.Key_1 ? "about" : (event.key === Qt.Key_2 ? "members" : (event.key === Qt.Key_3 ? "settings" : ""))
    if (name) { d.setTab(name); event.accepted = true }
  }

  // ================================================================ layout
  Column {
    width: parent.width

    Text {
      visible: !d.c
      width: parent.width
      wrapMode: Text.Wrap
      topPadding: d.t.sp(4)
      bottomPadding: d.t.sp(12)
      text: d.infoDone ? d.app.tr("Slack couldn't find this conversation: it may be gone, or you may not have access to it.",
                                  "O Slack não encontrou esta conversa: talvez ela não exista mais ou você não tenha acesso.")
                       : d.app.tr("Loading…", "Carregando…")
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsText
    }

    Column {
      visible: !!d.c
      width: parent.width
      spacing: 0

      // ------------------------------------------------------------ star · notifications
      Row {
        spacing: d.t.sp(8)
        height: d.t.sp(32)

        Rectangle {
          id: starBtn
          readonly property bool on: d.ws ? d.ws.isStarred(d.convId) : false
          width: d.t.sp(34)
          height: d.t.sp(30)
          radius: Math.max(6, d.t.radiusSmall)
          color: starMa.containsMouse ? d.t.hover : "transparent"
          border.width: 1
          border.color: d.t.lineStrong
          Glyph { anchors.centerIn: parent; app: d.app; icon: starBtn.on ? "󰓎" : "󰓒"; color: starBtn.on ? d.t.yellow : d.t.fgSoft; size: d.t.fsIcon }
          MouseArea { id: starMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.ws.setStar(d.convId, !starBtn.on) }
          PanelToolTip {
            visible: starMa.containsMouse
            text: starBtn.on ? d.app.tr("Remove from starred", "Remover dos favoritos")
                             : (d.group ? d.app.tr("Star conversation", "Adicionar conversa aos favoritos") : d.app.tr("Star channel", "Adicionar canal aos favoritos"))
          }
        }

        Rectangle {
          id: bellBtn
          visible: !d.group && !d.archived
          readonly property string level: d.ws ? d.ws.notifyLevel(d.convId) : "all"
          height: d.t.sp(30)
          width: bellRow.implicitWidth + d.t.sp(22)
          radius: Math.max(6, d.t.radiusSmall)
          color: bellMa.containsMouse ? d.t.hover : "transparent"
          border.width: 1
          border.color: d.t.lineStrong
          Row {
            id: bellRow
            anchors.centerIn: parent
            spacing: d.t.sp(7)
            Glyph {
              app: d.app
              anchors.verticalCenter: parent.verticalCenter
              icon: bellBtn.level === "mute" ? "󰂛" : (bellBtn.level === "mentions" ? "󰂚" : "󰂞")
              color: d.t.fgSoft
              size: d.t.fsIcon - 1
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: bellBtn.level === "mute" ? d.app.tr("Muted", "Silenciado")
                  : bellBtn.level === "mentions" ? d.app.tr("Just mentions", "Só menções")
                  : d.app.tr("All new messages", "Todas as novas mensagens")
              color: d.t.fg
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall + 1
              font.bold: true
            }
            Glyph { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰅀"; color: d.t.fgDim; size: d.t.fsSmall }
          }
          MouseArea { id: bellMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.notifyMenu(bellBtn) }
        }

        Rectangle {
          visible: d.archived
          height: d.t.sp(30)
          width: archRow.implicitWidth + d.t.sp(20)
          radius: Math.max(6, d.t.radiusSmall)
          color: d.t.alpha(d.t.yellow, 0.12)
          Row {
            id: archRow
            anchors.centerIn: parent
            spacing: d.t.sp(6)
            Glyph { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󱈎"; color: d.t.yellow; size: d.t.fsIcon - 1 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: d.app.tr("Archived", "Arquivado"); color: d.t.yellow; font.family: d.t.font; font.pixelSize: d.t.fsSmall + 1; font.bold: true }
          }
        }
      }

      Item { width: 1; height: d.t.sp(10) }

      // ------------------------------------------------------------ tabs
      Item {
        width: parent.width
        height: d.t.sp(36)
        Row {
          height: parent.height
          spacing: d.t.sp(4)
          HeaderTab {
            visible: !d.group
            app: d.app
            label: d.app.tr("About", "Sobre")
            active: d.tab === "about"
            onClicked: d.setTab("about")
          }
          HeaderTab {
            app: d.app
            label: d.app.tr("Members", "Membros") + " " + (d.membersLoaded ? d.shownMembers.length : (d.c && d.c.numMembers ? d.c.numMembers : ""))
            active: d.tab === "members"
            onClicked: d.setTab("members")
          }
          HeaderTab {
            visible: !d.group
            app: d.app
            label: d.app.tr("Settings", "Configurações")
            active: d.tab === "settings"
            onClicked: d.setTab("settings")
          }
        }
        Rectangle { x: -d.t.sp(24); anchors.bottom: parent.bottom; width: parent.width + d.t.sp(48); height: 1; color: d.t.line }
      }

      Item { width: 1; height: d.t.sp(14) }

      // ------------------------------------------------------------ panes
      Item {
        width: parent.width
        height: d.paneH

        // ======================================================== About
        Flickable {
          id: aboutPane
          visible: d.tab === "about"
          anchors.fill: parent
          clip: true
          contentWidth: width
          contentHeight: aboutCol.implicitHeight + d.t.sp(4)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ThinScroll { app: d.app }

          Column {
            id: aboutCol
            width: aboutPane.width
            spacing: d.t.sp(12)

            Rectangle {
              width: parent.width
              height: nameRows.implicitHeight
              radius: Math.max(6, d.t.radiusCard)
              color: d.t.alpha(d.t.fg, 0.025)
              border.width: 1
              border.color: d.t.line
              Column { id: nameRows; width: parent.width; Repeater { model: ["name"]; delegate: editRow } }
            }

            Rectangle {
              width: parent.width
              height: infoRows.implicitHeight
              radius: Math.max(6, d.t.radiusCard)
              color: d.t.alpha(d.t.fg, 0.025)
              border.width: 1
              border.color: d.t.line
              Column {
                id: infoRows
                width: parent.width
                Repeater { model: ["topic", "purpose"]; delegate: editRow }

                // Who made it, and when.
                Item {
                  visible: !!d.c && !!d.c.creator
                  width: parent.width
                  height: visible ? createdCol.implicitHeight + d.t.sp(28) : 0
                  Rectangle { width: parent.width; height: 1; color: d.t.line }
                  Column {
                    id: createdCol
                    x: d.t.sp(16)
                    y: d.t.sp(14)
                    width: parent.width - d.t.sp(32)
                    spacing: d.t.sp(4)
                    Text { text: d.app.tr("Created by", "Criado por"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
                    Text {
                      width: parent.width
                      wrapMode: Text.Wrap
                      text: !d.c || !d.c.creator ? "" : (d.ws.userName(d.c.creator) || d.c.creator)
                          + (d.c.created ? d.app.tr(" on ", " em ") + U.fullDate(new Date(d.c.created * 1000), d.app.lang) : "")
                      textFormat: Text.PlainText
                      color: d.t.fg
                      font.family: d.t.font
                      font.pixelSize: d.t.fsText
                    }
                  }
                }

                // Leave (not #general, not archived, members only).
                Item {
                  visible: !d.general && !d.archived && d.member
                  width: parent.width
                  height: visible ? leaveCol.implicitHeight + d.t.sp(24) : 0
                  Rectangle { width: parent.width; height: 1; color: d.t.line }
                  Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    radius: Math.max(6, d.t.radiusCard)
                    color: leaveMa.containsMouse && d.confirm !== "leave" ? d.t.alpha(d.t.red, 0.07) : "transparent"
                  }
                  MouseArea { id: leaveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: d.confirm === "leave" ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: if (d.confirm !== "leave") d.leave() }
                  Column {
                    id: leaveCol
                    x: d.t.sp(16)
                    y: d.t.sp(12)
                    width: parent.width - d.t.sp(32)
                    spacing: d.t.sp(10)
                    Text {
                      text: d.busy === "leave" ? d.app.tr("Leaving…", "Saindo…") : d.app.tr("Leave channel", "Sair do canal")
                      color: d.t.red
                      font.family: d.t.font
                      font.pixelSize: d.t.fsText
                      font.bold: true
                    }
                    Text {
                      visible: d.confirm === "leave"
                      width: parent.width
                      wrapMode: Text.Wrap
                      text: d.app.tr("Leave ", "Sair de ") + d.hashName + d.app.tr("? It's private: you'll need an invitation to come back.", "? Ele é privado: você só volta com um convite.")
                      textFormat: Text.PlainText
                      color: d.t.fg
                      font.family: d.t.font
                      font.pixelSize: d.t.fsSmall + 1
                    }
                    Row {
                      visible: d.confirm === "leave"
                      spacing: d.t.sp(8)
                      SButton { app: d.app; small: true; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.confirm = "" }
                      SButton { app: d.app; small: true; kind: "danger"; text: d.app.tr("Leave channel", "Sair do canal"); enabled2: d.busy === ""; onClicked: d.leave() }
                    }
                  }
                }
              }
            }

            Text {
              visible: d.error !== "" && d.editing === ""
              width: parent.width
              wrapMode: Text.Wrap
              text: "󰗖  " + d.error
              textFormat: Text.PlainText
              color: d.t.red
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
            }

            // The channel's id, to copy.
            Row {
              spacing: d.t.sp(6)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: d.app.tr("Channel ID: ", "ID do canal: ") + d.convId
                color: d.t.fgDim
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
              }
              IconButton {
                anchors.verticalCenter: parent.verticalCenter
                app: d.app
                size: d.t.sp(24)
                iconSize: d.t.fsSmall
                icon: "󰆏"
                tip: d.app.tr("Copy channel ID", "Copiar ID do canal")
                onClicked: { d.app.copy(d.convId); d.win.toast(d.app.tr("Channel ID copied", "ID do canal copiado")) }
              }
            }
          }
        }

        // ======================================================== Members
        Item {
          id: membersPane
          visible: d.tab === "members" && !d.adding
          anchors.fill: parent

          Item {
            id: searchRow
            width: parent.width
            height: search.implicitHeight
            SField {
              id: search
              app: d.app
              width: parent.width - copyBtn.width - d.t.sp(8)
              icon: "󰍉"
              placeholderText: d.app.tr("Find members", "Encontrar membros")
              Keys.onEscapePressed: event => { if (search.text !== "") { search.text = ""; event.accepted = true } else event.accepted = false }
              Keys.onDownPressed: memberList.incrementCurrentIndex()
              Keys.onUpPressed: memberList.decrementCurrentIndex()
              onTextEdited: memberList.currentIndex = text.trim() !== "" ? 0 : -1
              onAccepted: if (memberList.currentIndex >= 0) d.openMember(memberList.currentIndex)
            }
            IconButton {
              id: copyBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              app: d.app
              size: search.implicitHeight
              icon: "󰆏"
              tip: d.app.tr("Copy member names", "Copiar nomes dos membros")
              enabled2: d.membersLoaded && d.shownMembers.length > 0
              onClicked: d.copyNames()
            }
          }

          ListView {
            id: memberList
            y: searchRow.height + d.t.sp(10)
            width: parent.width
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1
            model: ScriptModel { values: d.memberRows; objectProp: "key" }
            ScrollBar.vertical: ThinScroll { app: d.app }

            delegate: Rectangle {
              id: mrow
              required property var modelData
              required property int index
              readonly property bool isAdd: modelData.kind === "add"
              readonly property var u: !isAdd && d.ws ? d.ws.user(modelData.id) : null
              readonly property var status: !isAdd && d.ws ? d.ws.statusOf(modelData.id) : null
              width: memberList.width
              height: d.t.sp(52)
              radius: Math.max(6, d.t.radiusSmall)
              color: mrowMa.containsMouse || memberList.currentIndex === index ? d.t.hover : "transparent"

              // Add people: a tinted square with the icon, like Slack.
              Rectangle {
                visible: mrow.isAdd
                x: d.t.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                width: d.t.sp(36)
                height: width
                radius: Math.max(6, d.t.radiusSmall)
                color: d.t.alpha(d.t.accent, 0.16)
                Glyph { anchors.centerIn: parent; app: d.app; icon: "󰠁"; color: d.t.accent; size: d.t.fsIcon + 2 }
              }
              Avatar {
                visible: !mrow.isAdd
                x: d.t.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                app: d.app
                ws: d.ws
                user: mrow.isAdd ? "" : mrow.modelData.id
                size: d.t.sp(36)
                showPresence: true
                ring: d.t.popup
              }

              Column {
                x: d.t.sp(56)
                width: parent.width - x - d.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: d.t.sp(2)
                Row {
                  spacing: d.t.sp(6)
                  width: parent.width
                  Text {
                    text: mrow.isAdd ? d.app.tr("Add people", "Adicionar pessoas") : (d.ws.userName(mrow.modelData.id) || mrow.modelData.id)
                    textFormat: Text.PlainText
                    color: mrow.isAdd ? d.t.fgBright : d.t.fgBright
                    font.family: d.t.font
                    font.pixelSize: d.t.fsText
                    font.bold: true
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - d.t.sp(90))
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  EmojiIcon {
                    visible: !!mrow.status && !!mrow.status.emoji
                    anchors.verticalCenter: parent.verticalCenter
                    app: d.app
                    ws: d.ws
                    name: mrow.status ? String(mrow.status.emoji || "").replace(/^:|:$/g, "") : ""
                    size: d.t.sp(16)
                    StatusTip { app: d.app; ws: d.ws; status: mrow.status; area: mrowMa }
                  }
                  Text {
                    visible: !mrow.isAdd && d.ws && mrow.modelData.id === d.ws.me.id
                    text: d.app.tr("(you)", "(você)")
                    color: d.t.fgDim
                    font.family: d.t.font
                    font.pixelSize: d.t.fsText
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
                Text {
                  visible: text !== ""
                  width: parent.width
                  elide: Text.ElideRight
                  text: mrow.isAdd ? "" : (mrow.u ? (mrow.u.title || (mrow.u.real && mrow.u.real !== mrow.u.name ? mrow.u.real : "")) : "")
                  textFormat: Text.PlainText
                  color: d.t.fgDim
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall
                }
              }

              MouseArea {
                id: mrowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: d.openMember(mrow.index)
              }
            }

          }

          Text {
            visible: d.membersLoaded && d.memberRows.filter(function(r) { return r.kind === "user" }).length === 0 && search.text.trim() !== ""
            anchors.centerIn: memberList
            text: d.app.tr("No one found", "Ninguém encontrado")
            color: d.t.fgDim
            font.family: d.t.font
            font.pixelSize: d.t.fsText
          }
          Text {
            visible: !d.membersLoaded
            anchors.centerIn: memberList
            text: d.app.tr("Loading…", "Carregando…")
            color: d.t.fgDim
            font.family: d.t.font
            font.pixelSize: d.t.fsText
          }
        }

        // ======================================================== Add people
        Item {
          id: addPane
          visible: d.tab === "members" && d.adding
          anchors.fill: parent

          Row {
            id: addHead
            spacing: d.t.sp(8)
            height: d.t.sp(30)
            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              app: d.app
              icon: "󰁍"
              tip: d.app.tr("Back to members", "Voltar aos membros")
              onClicked: d.stopAdding()
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: d.app.tr("Add people to ", "Adicionar pessoas a ") + d.hashName
              textFormat: Text.PlainText
              color: d.t.fgBright
              font.family: d.t.font
              font.pixelSize: d.t.fsTitle
              font.bold: true
            }
          }

          Rectangle {
            id: addBox
            y: addHead.height + d.t.sp(10)
            width: parent.width
            height: Math.max(d.t.sp(40), addFlow.implicitHeight + d.t.sp(12))
            radius: Math.max(4, d.t.radiusSmall)
            color: d.t.alpha(d.t.bg, 0.6)
            border.width: addInput.activeFocus ? 2 : 1
            border.color: addInput.activeFocus ? d.t.accent : d.t.lineStrong
            MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: addInput.forceActiveFocus() }
            Flow {
              id: addFlow
              x: d.t.sp(8)
              y: d.t.sp(6)
              width: parent.width - d.t.sp(16)
              spacing: d.t.sp(4)
              Repeater {
                model: d.picked
                delegate: Rectangle {
                  id: pchip
                  required property var modelData
                  height: d.t.sp(28)
                  width: pchipRow.implicitWidth + d.t.sp(10)
                  radius: Math.max(4, d.t.radiusSmall)
                  color: pchipMa.containsMouse ? d.t.alpha(d.t.accent, 0.28) : d.t.alpha(d.t.accent, 0.16)
                  Row {
                    id: pchipRow
                    x: d.t.sp(4)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: d.t.sp(6)
                    Avatar { app: d.app; ws: d.ws; user: pchip.modelData; size: d.t.sp(20); anchors.verticalCenter: parent.verticalCenter }
                    Text { text: d.ws.userName(pchip.modelData); textFormat: Text.PlainText; color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    Glyph { app: d.app; icon: "󰅖"; size: d.t.fsSmall; color: pchipMa.containsMouse ? d.t.fgBright : d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { id: pchipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.unpickPerson(pchip.modelData) }
                }
              }
              TextField {
                id: addInput
                width: d.picked.length ? Math.max(d.t.sp(160), Math.min(addFlow.width, contentWidth + d.t.sp(24))) : addFlow.width
                height: d.t.sp(28)
                padding: 0
                leftPadding: d.t.sp(4)
                verticalAlignment: TextInput.AlignVCenter
                background: null
                color: d.t.fg
                placeholderText: d.picked.length ? "" : d.app.tr("Type a name", "Digite um nome")
                placeholderTextColor: d.t.fgDim
                selectionColor: d.t.alpha(d.t.accent, 0.35)
                selectedTextColor: d.t.fgBright
                selectByMouse: true
                font.family: d.t.font
                font.pixelSize: d.t.fsText
                Keys.onPressed: event => {
                  var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                  if (event.key === Qt.Key_Down) { d.moveSel(1); event.accepted = true }
                  else if (event.key === Qt.Key_Up) { d.moveSel(-1); event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true
                    if (ctrl || d.addQuery === "") d.addPeople()
                    else d.pickPerson(d.sel)
                  } else if (event.key === Qt.Key_Backspace && addInput.text === "" && d.picked.length) {
                    d.unpickPerson(d.picked[d.picked.length - 1]); event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    if (addInput.text !== "") addInput.text = ""
                    else d.stopAdding()
                  }
                }
              }
            }
          }

          ListView {
            id: addList
            y: addBox.y + addBox.height + d.t.sp(8)
            width: parent.width
            height: parent.height - y - addFoot.height - d.t.sp(10)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: d.candidates; objectProp: "key" }
            ScrollBar.vertical: ThinScroll { app: d.app }
            delegate: Rectangle {
              id: crow
              required property var modelData
              required property int index
              readonly property bool hot: index === d.sel
              readonly property var u: d.ws ? d.ws.user(modelData.id) : null
              width: addList.width
              height: d.t.sp(40)
              radius: Math.max(4, d.t.radiusSmall)
              color: hot ? d.t.accent : (crowMa.containsMouse ? d.t.hover : "transparent")
              Row {
                x: d.t.sp(10)
                width: parent.width - d.t.sp(20)
                anchors.verticalCenter: parent.verticalCenter
                spacing: d.t.sp(10)
                Avatar { anchors.verticalCenter: parent.verticalCenter; app: d.app; ws: d.ws; user: crow.modelData.id; size: d.t.sp(26); showPresence: true; ring: crow.hot ? d.t.accent : d.t.popup }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: crow.u ? crow.u.name : ""
                  textFormat: Text.PlainText
                  color: crow.hot ? d.t.onColor(d.t.accent) : d.t.fg
                  font.family: d.t.font
                  font.pixelSize: d.t.fsText
                  font.bold: true
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: crow.u ? (crow.u.title || (crow.u.real && crow.u.real !== crow.u.name ? crow.u.real : "")) : ""
                  textFormat: Text.PlainText
                  color: crow.hot ? d.t.alpha(d.t.onColor(d.t.accent), 0.75) : d.t.fgDim
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall
                  elide: Text.ElideRight
                  width: Math.max(0, parent.width - x)
                }
              }
              MouseArea { id: crowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { d.sel = crow.index; d.pickPerson(crow.index); addInput.forceActiveFocus() } }
            }
          }
          Text {
            visible: d.candidates.length === 0
            anchors.centerIn: addList
            text: d.addQuery !== "" ? d.app.tr("No one found", "Ninguém encontrado") : d.app.tr("Everyone is already here", "Todo mundo já está aqui")
            color: d.t.fgDim
            font.family: d.t.font
            font.pixelSize: d.t.fsText
          }

          Item {
            id: addFoot
            anchors.bottom: parent.bottom
            width: parent.width
            height: addBtn.height
            Text {
              anchors.left: parent.left
              anchors.right: addBtns.left
              anchors.rightMargin: d.t.sp(12)
              anchors.verticalCenter: parent.verticalCenter
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              text: d.error !== "" ? "󰗖  " + d.error : d.app.tr("Enter picks · Enter on empty adds · Esc goes back", "Enter escolhe · Enter vazio adiciona · Esc volta")
              textFormat: Text.PlainText
              color: d.error !== "" ? d.t.red : d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
            }
            Row {
              id: addBtns
              anchors.right: parent.right
              spacing: d.t.sp(10)
              SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.stopAdding() }
              SButton {
                id: addBtn
                app: d.app
                kind: "primary"
                text: d.busy === "add" ? d.app.tr("Adding…", "Adicionando…") : d.app.tr("Add", "Adicionar")
                enabled2: d.busy === "" && (d.picked.length > 0 || (d.addQuery !== "" && d.candidates.length > 0))
                onClicked: d.addPeople()
              }
            }
          }
        }

        // ======================================================== Settings
        Flickable {
          id: settingsPane
          visible: d.tab === "settings"
          anchors.fill: parent
          clip: true
          contentWidth: width
          contentHeight: setCol.implicitHeight + d.t.sp(4)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ThinScroll { app: d.app }

          Column {
            id: setCol
            width: settingsPane.width
            spacing: d.t.sp(12)

            Rectangle {
              visible: d.confirm !== "delete"
              width: parent.width
              height: setRows.implicitHeight
              radius: Math.max(6, d.t.radiusCard)
              color: d.t.alpha(d.t.fg, 0.025)
              border.width: 1
              border.color: d.t.line
              Column {
                id: setRows
                width: parent.width
                Repeater {
                  model: {
                    var out = []
                    if (!d.c || d.group) return out
                    if (d.c.kind === "channel" && !d.general && !d.archived) out.push("convert")
                    if (!d.general) out.push(d.archived ? "unarchive" : "archive")
                    if (!d.general) out.push("delete")
                    return out
                  }
                  delegate: settingRow
                }
                Text {
                  visible: d.general
                  x: d.t.sp(16)
                  width: parent.width - d.t.sp(32)
                  topPadding: d.t.sp(14)
                  bottomPadding: d.t.sp(14)
                  wrapMode: Text.Wrap
                  text: d.app.tr("This is the workspace's general channel: everyone is in it, and it can't be archived, deleted or made private.",
                                 "Este é o canal geral do workspace: todo mundo está nele, e ele não pode ser arquivado, apagado nem ficar privado.")
                  color: d.t.fgDim
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall + 1
                }
              }
            }

            // "Delete channel?": a box to tick, then the red button.
            Rectangle {
              visible: d.confirm === "delete"
              width: parent.width
              height: delCol.implicitHeight + d.t.sp(32)
              radius: Math.max(6, d.t.radiusCard)
              color: d.t.alpha(d.t.red, 0.05)
              border.width: 1
              border.color: d.t.alpha(d.t.red, 0.45)
              Column {
                id: delCol
                x: d.t.sp(16)
                y: d.t.sp(16)
                width: parent.width - d.t.sp(32)
                spacing: d.t.sp(12)
                Text { text: d.app.tr("Delete ", "Apagar ") + d.hashName + "?"; textFormat: Text.PlainText; color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true; width: parent.width; elide: Text.ElideRight }
                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  textFormat: Text.StyledText
                  text: d.app.tr("When you delete a channel, all messages from it are removed from Slack immediately. <b>This can't be undone.</b>",
                                 "Ao apagar um canal, todas as mensagens dele saem do Slack na hora. <b>Isso não pode ser desfeito.</b>")
                  color: d.t.fg
                  font.family: d.t.font
                  font.pixelSize: d.t.fsText - 1
                }
                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: d.app.tr("Keep in mind that:\n•  Files uploaded to it aren't removed.\n•  You can archive the channel instead, keeping its messages.",
                                 "Tenha em mente que:\n•  Os arquivos enviados a ele não são removidos.\n•  Você pode arquivar o canal, mantendo as mensagens.")
                  color: d.t.fgSoft
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall + 1
                  lineHeight: 1.15
                }
                Item {
                  width: parent.width
                  height: d.t.sp(26)
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: d.t.sp(10)
                    Glyph { anchors.verticalCenter: parent.verticalCenter; app: d.app; icon: d.deleteChecked ? "󰄲" : "󰄱"; color: d.deleteChecked ? d.t.red : d.t.fgSoft; size: d.t.fsIcon + 3 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: d.app.tr("Yes, permanently delete the channel", "Sim, apagar o canal para sempre"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText }
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { d.deleteChecked = !d.deleteChecked; d.error = "" } }
                }
                Row {
                  anchors.right: parent.right
                  spacing: d.t.sp(10)
                  SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: { d.confirm = ""; d.deleteChecked = false; d.error = "" } }
                  SButton {
                    app: d.app
                    kind: "danger"
                    text: d.busy === "delete" ? d.app.tr("Deleting…", "Apagando…") : d.app.tr("Delete channel", "Apagar canal")
                    enabled2: d.deleteChecked && d.busy === ""
                    onClicked: d.destroyChannel()
                  }
                }
              }
            }

            Text {
              visible: d.error !== ""
              width: parent.width
              wrapMode: Text.Wrap
              text: "󰗖  " + d.error
              textFormat: Text.PlainText
              color: d.t.red
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- About rows
  // Channel name / Topic / Description: the value, Edit, and in place the
  // field to change it.
  Component {
    id: editRow
    Item {
      id: er
      required property var modelData
      required property int index
      readonly property string key: modelData
      readonly property bool isEditing: d.editing === key
      readonly property string value: !d.c ? "" : (key === "name" ? d.c.name || "" : (key === "topic" ? d.c.topic || "" : d.c.purpose || ""))
      width: parent ? parent.width : 0
      height: erCol.implicitHeight + d.t.sp(28)

      onIsEditingChanged: if (isEditing) {
        var v = er.key === "name" ? er.value : d.plain(er.value)
        if (er.key === "name") { nameEdit.text = v; nameEdit.cursorPosition = v.length; nameEdit.forceActiveFocus() }
        else { textEdit.text = v; textEdit.cursorPosition = v.length; textEdit.forceActiveFocus() }
      }

      Rectangle { visible: er.index > 0; width: parent.width; height: 1; color: d.t.line }
      MouseArea {
        anchors.fill: parent
        enabled: !er.isEditing && !d.archived
        cursorShape: Qt.PointingHandCursor
        onClicked: d.startEdit(er.key)
      }

      Column {
        id: erCol
        x: d.t.sp(16)
        y: d.t.sp(14)
        width: parent.width - d.t.sp(32)
        spacing: d.t.sp(6)

        Item {
          width: parent.width
          height: label.implicitHeight
          Text {
            id: label
            text: er.key === "name" ? d.app.tr("Channel name", "Nome do canal") : (er.key === "topic" ? d.app.tr("Topic", "Tópico") : d.app.tr("Description", "Descrição"))
            color: d.t.fgBright
            font.family: d.t.font
            font.pixelSize: d.t.fsText
            font.bold: true
          }
          Text {
            visible: !er.isEditing && !d.archived
            anchors.right: parent.right
            text: d.app.tr("Edit", "Editar")
            color: d.t.link
            font.family: d.t.font
            font.pixelSize: d.t.fsSmall + 1
            font.bold: true
            font.underline: editMa.containsMouse
            MouseArea { id: editMa; anchors.fill: parent; anchors.margins: -d.t.sp(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.startEdit(er.key) }
          }
        }

        // The value.
        Text {
          visible: !er.isEditing && er.key === "name"
          width: parent.width
          elide: Text.ElideRight
          text: (d.priv ? "󰌾 " : "# ") + er.value
          textFormat: Text.PlainText
          color: d.t.fg
          font.family: d.t.font
          font.pixelSize: d.t.fsText
        }
        RichText {
          visible: !er.isEditing && er.key !== "name" && er.value !== ""
          width: parent.width
          app: d.app
          html: er.key !== "name" && er.value !== "" && d.ctx ? Md.inlineBlock(er.value, d.ctx, d.t.emojiPx) : ""
          onLink: url => d.link(url)
        }
        Text {
          visible: !er.isEditing && er.key !== "name" && er.value === ""
          text: d.archived ? d.app.tr("None", "Nenhum")
              : er.key === "topic" ? d.app.tr("Add a topic", "Adicionar um tópico") : d.app.tr("Add a description", "Adicionar uma descrição")
          color: d.archived ? d.t.fgDim : d.t.link
          font.family: d.t.font
          font.pixelSize: d.t.fsText
        }

        // Editing: the name in one line, topic and description wrapped.
        Item {
          visible: er.isEditing && er.key === "name"
          width: parent.width
          height: visible ? nameEdit.implicitHeight : 0
          SField {
            id: nameEdit
            app: d.app
            anchors.fill: parent
            leftPadding: d.t.sp(30)
            maximumLength: 80
            onTextEdited: {
              var p = cursorPosition
              var tidy = function(s) { var o = "", x = String(s).toLowerCase().replace(/\s/g, "-"); for (var i = 0; i < x.length; i++) if (/[a-z0-9_-]/.test(x[i]) || U.isLetter(x[i])) o += x[i]; return o }
              var before = tidy(text.slice(0, p)), next = (before + tidy(text.slice(p))).slice(0, 80)
              if (next !== text) { text = next; cursorPosition = Math.min(before.length, next.length) }
              d.error = ""
            }
            Keys.onReturnPressed: d.save("name", nameEdit.text)
            Keys.onEnterPressed: d.save("name", nameEdit.text)
            Keys.onEscapePressed: d.cancelEdit()
          }
          Glyph { x: d.t.sp(10); anchors.verticalCenter: parent.verticalCenter; app: d.app; icon: d.priv ? "󰌾" : "#"; color: d.t.fgDim; size: d.t.fsText }
        }
        Rectangle {
          visible: er.isEditing && er.key !== "name"
          width: parent.width
          height: visible ? Math.min(textEdit.implicitHeight, d.t.sp(140)) : 0
          radius: Math.max(4, d.t.radiusSmall)
          color: d.t.alpha(d.t.bg, 0.6)
          border.width: textEdit.activeFocus ? 2 : 1
          border.color: textEdit.activeFocus ? d.t.accent : d.t.lineStrong
          clip: true
          TextArea {
            id: textEdit
            width: parent.width
            color: d.t.fg
            placeholderText: er.key === "topic" ? d.app.tr("Add a topic", "Adicionar um tópico") : d.app.tr("What is this channel about?", "Sobre o que é este canal?")
            placeholderTextColor: d.t.fgDim
            selectionColor: d.t.alpha(d.t.accent, 0.35)
            selectedTextColor: d.t.fgBright
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            font.family: d.t.font
            font.pixelSize: d.t.fsText
            padding: d.t.sp(9)
            background: null
            onTextChanged: if (er.isEditing) d.error = ""
            Keys.onPressed: event => {
              if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) { d.save(er.key, textEdit.text); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { d.cancelEdit(); event.accepted = true }
            }
          }
        }
        Text {
          visible: er.isEditing && d.error !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: "󰗖  " + d.error
          textFormat: Text.PlainText
          color: d.t.red
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
        }
        Item {
          visible: er.isEditing
          width: parent.width
          height: visible ? saveBtn.height : 0
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: er.key === "name" ? d.app.tr("Lowercase, no spaces or periods, at most 80 characters", "Minúsculas, sem espaços nem pontos, até 80 caracteres")
                                    : d.app.tr("Enter saves · Shift+Enter new line · Esc cancels", "Enter salva · Shift+Enter nova linha · Esc cancela")
            color: d.t.fgDim
            font.family: d.t.font
            font.pixelSize: d.t.fsTiny
            elide: Text.ElideRight
            width: parent.width - saveRow.width - d.t.sp(10)
          }
          Row {
            id: saveRow
            anchors.right: parent.right
            spacing: d.t.sp(8)
            SButton { app: d.app; small: true; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.cancelEdit() }
            SButton {
              id: saveBtn
              app: d.app
              small: true
              kind: "primary"
              text: d.busy === er.key ? d.app.tr("Saving…", "Salvando…") : d.app.tr("Save", "Salvar")
              enabled2: d.busy === ""
              onClicked: d.save(er.key, er.key === "name" ? nameEdit.text : textEdit.text)
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- Settings rows
  Component {
    id: settingRow
    Item {
      id: sr
      required property var modelData
      required property int index
      readonly property string key: modelData
      readonly property bool danger: key === "archive" || key === "delete"
      readonly property bool asking: d.confirm === key
      width: parent ? parent.width : 0
      height: srCol.implicitHeight + d.t.sp(28)

      Rectangle { visible: sr.index > 0; width: parent.width; height: 1; color: d.t.line }
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: sr.index > 0 ? 1 : 0
        radius: Math.max(6, d.t.radiusCard)
        color: srMa.containsMouse && !sr.asking ? (sr.danger ? d.t.alpha(d.t.red, 0.07) : d.t.hover) : "transparent"
      }
      MouseArea {
        id: srMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: !sr.asking
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          d.error = ""
          if (sr.key === "unarchive") d.archive(false)
          else d.confirm = sr.key
        }
      }

      Glyph {
        x: d.t.sp(16)
        y: d.t.sp(14)
        app: d.app
        width: d.t.sp(20)
        icon: sr.key === "convert" ? "󰌾" : (sr.key === "delete" ? "󰧧" : (sr.key === "unarchive" ? "󱉜" : "󱈎"))
        color: sr.danger ? d.t.red : d.t.fgSoft
        size: d.t.fsIcon + 1
      }

      Column {
        id: srCol
        x: d.t.sp(48)
        y: d.t.sp(14)
        width: parent.width - x - d.t.sp(16)
        spacing: d.t.sp(4)
        Text {
          text: sr.key === "convert" ? d.app.tr("Change to a private channel", "Mudar para um canal privado")
              : sr.key === "archive" ? d.app.tr("Archive channel for everyone", "Arquivar canal para todos")
              : sr.key === "unarchive" ? (d.busy === "unarchive" ? d.app.tr("Unarchiving…", "Desarquivando…") : d.app.tr("Unarchive channel", "Desarquivar canal"))
              : d.app.tr("Delete this channel", "Apagar este canal")
          color: sr.danger ? d.t.red : d.t.fgBright
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          font.bold: true
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: sr.key === "convert" ? d.app.tr("Only invited people will see it and its history. This can't be undone.", "Só quem for convidado verá o canal e o histórico. Isso não pode ser desfeito.")
              : sr.key === "archive" ? d.app.tr("Nobody can post to it any more; its history stays searchable. You can unarchive it later.", "Ninguém mais pode publicar nele; o histórico continua pesquisável. Dá para desarquivar depois.")
              : sr.key === "unarchive" ? d.app.tr("Bring it back to everyone's sidebar and let people post again.", "Volta para a barra lateral de todos e libera as publicações.")
              : d.app.tr("Removes every message for good.", "Remove todas as mensagens para sempre.")
          color: d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
        }
        // Are you sure?
        Item { visible: sr.asking; width: 1; height: d.t.sp(6) }
        Text {
          visible: sr.asking
          width: parent.width
          wrapMode: Text.Wrap
          text: sr.key === "convert" ? d.app.tr("Make ", "Tornar ") + d.hashName + d.app.tr(" private for good?", " privado de vez?")
              : d.app.tr("Archive ", "Arquivar ") + d.hashName + d.app.tr(" for everyone?", " para todos?")
          textFormat: Text.PlainText
          color: d.t.fg
          font.family: d.t.font
          font.pixelSize: d.t.fsText - 1
          font.bold: true
        }
        Row {
          visible: sr.asking
          spacing: d.t.sp(8)
          topPadding: d.t.sp(4)
          SButton { app: d.app; small: true; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.confirm = "" }
          SButton {
            app: d.app
            small: true
            kind: sr.key === "convert" ? "primary" : "danger"
            enabled2: d.busy === ""
            text: sr.key === "convert" ? (d.busy === "convert" ? d.app.tr("Changing…", "Mudando…") : d.app.tr("Change to private", "Mudar para privado"))
                                       : (d.busy === "archive" ? d.app.tr("Archiving…", "Arquivando…") : d.app.tr("Archive channel", "Arquivar canal"))
            onClicked: sr.key === "convert" ? d.makePrivate() : d.archive(true)
          }
        }
      }
    }
  }
}
