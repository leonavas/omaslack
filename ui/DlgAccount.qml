import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// Slack's profile menu (your photo at the bottom of the rail, Ctrl+P): a
// card that grows up beside the rail. You and your presence, your status
// (✕ clears it), away/active, pausing notifications in every workspace (a
// submenu of presets, or Resume while paused), your profile, Preferences,
// the shortcuts guide, About and signing out. Same API as DialogFrame
// (app, win, ws, args, closed()), but placed like Slack's menu, not centered.
Item {
  id: d
  property var app: Reg.service
  property var win
  property var ws
  property var args: ({})
  readonly property var t: app.theme
  // The theme's popup color, made opaque over the pane (Omarchy's is see-through).
  readonly property color cardColor: t.mix(t.pane, t.alpha(t.popup, 1), t.popup.a)
  signal closed()
  anchors.fill: parent
  z: 800

  // ---------------------------------------------------------------- state
  readonly property string me: d.ws ? d.ws.me.id : ""
  readonly property var meUser: d.ws && d.me ? d.ws.user(d.me) : null
  readonly property var status: d.ws && d.me ? d.ws.statusOf(d.me) : null
  readonly property bool active: d.ws && d.me ? (d.ws.isActive(d.me) && !d.ws.away) : false
  readonly property var pausedUntil: {
    var list = d.app.workspaces
    if (d.ws && d.ws.dnd) return d.ws.dnd.until || 0
    for (var i = 0; i < list.length; i++) if (list[i].dnd) return list[i].dnd.until || 0
    return null
  }
  readonly property bool paused: d.pausedUntil !== null
  readonly property string teamName: d.ws ? (d.ws.team.name || d.ws.team.domain || "") : ""
  // New versions (core/Updater.qml): "Check for updates", and the update
  // under it while there is one.
  readonly property var up: d.app.updater
  readonly property string upPhase: d.up ? d.up.phase : ""

  property int hot: -1          // keyboard/hover row of the menu
  property bool subOpen: false  // the "Pause notifications" submenu
  property int subHot: -1
  property bool subKeys: false  // the keyboard is in the submenu

  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
  function until(unix) { return d.cap(U.untilLabel(unix, d.app.lang, d.app.clock24)) }

  readonly property var items: [
    { kind: "status" },
    { kind: "item", label: d.active ? d.app.tr("Set yourself as away", "Defina seu status como ausente") : d.app.tr("Set yourself as active", "Defina seu status como ativo"),
      run: function() { var s = d.ws, on = d.active; d.closed(); s.setAway(on) } },
    { kind: "item", pause: true, label: d.paused ? d.app.tr("Notifications paused", "Notificações pausadas") : d.app.tr("Pause notifications", "Pausar notificações"),
      sub2: d.paused && d.pausedUntil ? d.until(d.pausedUntil) : "" },
    { kind: "sep" },
    { kind: "item", label: d.app.tr("Profile", "Perfil"), run: function() { var s = d.ws, uid = d.me; d.closed(); s.profileUser = uid } },
    { kind: "item", label: d.app.tr("Preferences", "Preferências"), hint: "Ctrl+,", run: function() { d.open("preferences", {}) } },
    { kind: "item", label: d.app.tr("Keyboard shortcuts", "Atalhos de teclado"), hint: "Ctrl+/", run: function() { d.open("shortcuts", {}) } },
    // Stays open on a check, so what it finds shows up under it.
    { kind: "item", hidden: !d.up,
      label: d.upPhase === "updated" ? d.app.tr("Reload to update", "Recarregue para atualizar")
             : d.up && d.up.checking ? d.app.tr("Checking for updates…", "Procurando atualizações…") : d.app.tr("Check for updates", "Procurar atualizações"),
      hint: d.upPhase === "updated" ? "↻" : "", faded: !!d.up && d.up.checking,
      run: function() { if (d.upPhase === "updated") d.up.update(); else d.up.check(true) } },
    // In green, as what's new: opens the update in a terminal; faded while
    // that's open; how to, when the copy isn't in git.
    { kind: "item", hidden: d.upPhase !== "available" && d.upPhase !== "updating",
      good: d.upPhase === "available", faded: d.upPhase === "updating",
      label: d.upPhase === "available" ? d.app.tr("Update to ", "Atualizar para ") + d.up.latest + "…" : d.app.tr("Updating in the terminal…", "Atualizando no terminal…"),
      hint: d.upPhase === "available" ? "↓" : "", sub2: d.upPhase === "available" && d.up.how ? d.up.how : "",
      run: function() { d.up.update() } },
    { kind: "item", label: d.app.tr("About Slack", "Sobre o Slack"), hint: d.upPhase !== "" ? d.app.tr("· update available", "· atualização disponível") : "",
      run: function() { d.open("about", {}) } },
    { kind: "sep" },
    { kind: "item", danger: true, label: d.app.tr("Sign out of ", "Sair de ") + d.teamName, run: function() { d.signOut() } }
  ].filter(function(it) { return !it.hidden })

  readonly property var subItems: {
    var out = []
    if (d.paused) {
      out.push({ kind: "head", label: d.pausedUntil ? d.app.tr("Paused ", "Pausadas ") + U.untilLabel(d.pausedUntil, d.app.lang, d.app.clock24) : d.app.tr("Paused", "Pausadas") })
      out.push({ kind: "item", label: d.app.tr("Resume notifications", "Retomar notificações"), run: function() { d.resume() } })
      out.push({ kind: "sep" })
      out.push({ kind: "head", label: d.app.tr("Change the pause to…", "Mudar a pausa para…") })
    } else out.push({ kind: "head", label: d.app.tr("Pause notifications for…", "Pausar notificações por…") })
    out.push({ kind: "item", label: d.app.tr("30 minutes", "30 minutos"), run: function() { d.pause(30) } })
    out.push({ kind: "item", label: d.app.tr("1 hour", "1 hora"), run: function() { d.pause(60) } })
    out.push({ kind: "item", label: d.app.tr("2 hours", "2 horas"), run: function() { d.pause(120) } })
    out.push({ kind: "item", label: d.app.tr("Until tomorrow", "Até amanhã"), hint: U.time(new Date(Date.now() + U.minutesUntilTomorrow9() * 60000), d.app.clock24),
               run: function() { d.pause(U.minutesUntilTomorrow9()) } })
    out.push({ kind: "item", label: d.app.tr("Until next week", "Até a próxima semana"), hint: d.app.tr("Mon ", "seg ") + U.time(new Date(Date.now() + U.minutesUntilNextWeek9() * 60000), d.app.clock24),
               run: function() { d.pause(U.minutesUntilNextWeek9()) } })
    out.push({ kind: "item", label: d.app.tr("Custom…", "Personalizado…"), run: function() { d.open("pause", {}) } })
    out.push({ kind: "sep" })
    out.push({ kind: "item", label: d.app.tr("Notification preferences", "Preferências de notificação"), run: function() { d.open("preferences", { section: "notifications" }) } })
    return out
  }

  // ---------------------------------------------------------------- actions
  function open(name, a) { var w = d.win; d.closed(); w.dialog(name, a) }
  function pause(minutes) {
    var a = d.app, w = d.win
    var label = U.untilLabel(Math.floor(Date.now() / 1000) + minutes * 60, a.lang, a.clock24)
    d.closed()
    a.pauseAll(minutes)
    w.toast(a.tr("Notifications paused ", "Notificações pausadas ") + label)
  }
  function resume() {
    var a = d.app, w = d.win
    d.closed()
    a.resumeAll()
    w.toast(a.tr("Notifications resumed", "Notificações retomadas"))
  }
  function signOut() {
    var a = d.app, w = d.win, team = d.ws ? d.ws.teamId : "", name = d.teamName
    d.closed()
    w.dialog("confirm", {
      title: a.tr("Sign out of ", "Sair de ") + name + "?",
      text: a.tr("This app forgets the session, with this workspace's drafts and cached files. Slack in your browser stays signed in.", "Este app esquece a sessão, com os rascunhos e arquivos em cache deste workspace. O Slack no navegador continua conectado."),
      confirm: a.tr("Sign out", "Sair"), danger: true,
      action: function() { a.signOut(team) }
    })
  }
  function clearStatus() { if (d.ws) d.ws.setStatus("", "", 0) }
  function activate(i) {
    var it = d.items[i]
    if (!it) return
    if (it.kind === "status") { d.open("status", {}); return }
    if (it.pause) { d.openSub(true); return }
    if (it.run) it.run()
  }
  function selectable(list, i) { var it = list[i]; return !!it && (it.kind === "item" || it.kind === "status") }
  function step(list, from, dir) {
    var n = list.length
    var i = from
    for (var k = 0; k < n; k++) {
      i = (i + dir + n) % n
      if (d.selectable(list, i)) return i
    }
    return from
  }
  function openSub(byKeys) {
    d.subOpen = true
    d.subKeys = byKeys
    d.subHot = byKeys ? d.step(d.subItems, -1, 1) : -1
  }
  function closeSub() { d.subOpen = false; d.subKeys = false; d.subHot = -1 }

  focus: true
  Keys.onPressed: event => {
    var k = event.key
    if (k === Qt.Key_Escape) { if (d.subOpen) d.closeSub(); else d.closed(); event.accepted = true; return }
    if (d.subKeys) {
      if (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_Backtab) d.subHot = d.step(d.subItems, d.subHot, k === Qt.Key_Up || k === Qt.Key_Backtab ? -1 : 1)
      else if (k === Qt.Key_Left) d.closeSub()
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Right) { var it = d.subItems[d.subHot]; if (it && it.run) it.run() }
      else return
      event.accepted = true
      return
    }
    if (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      d.hot = d.step(d.items, d.hot < 0 && (k === Qt.Key_Up || k === Qt.Key_Backtab) ? d.items.length : d.hot, k === Qt.Key_Up || k === Qt.Key_Backtab ? -1 : 1)
      if (!d.items[d.hot].pause) d.closeSub()
    } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) d.activate(d.hot)
    else if (k === Qt.Key_Right && d.hot >= 0 && d.items[d.hot].pause) d.openSub(true)
    else if ((k === Qt.Key_Backspace || k === Qt.Key_Delete) && d.hot === 0 && d.status) d.clearStatus()
    else return
    event.accepted = true
  }

  // Clicks outside close it, like any menu.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: d.closed()
    onWheel: wheel => {}
  }

  // ---------------------------------------------------------------- the card
  BorderSurface {
    id: card
    x: d.args.x !== undefined ? Math.max(d.t.sp(6), Math.min(d.args.x, d.width - width - d.t.sp(6))) : d.t.sp(78)
    y: d.args.y !== undefined ? Math.max(d.t.sp(6), Math.min(d.args.y, d.height - height - d.t.sp(6))) : d.height - height - d.t.sp(10)
    width: d.t.sp(300)
    height: col.implicitHeight + d.t.sp(12)
    color: d.cardColor
    borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, 1)
    radius: Math.max(6, d.t.radiusCard)

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      id: col
      x: d.t.sp(6)
      y: d.t.sp(6)
      width: card.width - d.t.sp(12)

      // You.
      Item {
        width: parent.width
        height: d.t.sp(60)
        Avatar {
          id: photo
          app: d.app
          ws: d.ws
          user: d.me
          size: d.t.sp(38)
          x: d.t.sp(10)
          anchors.verticalCenter: parent.verticalCenter
          onClicked: d.items[4].run()
        }
        Column {
          anchors.left: photo.right
          anchors.leftMargin: d.t.sp(12)
          anchors.right: parent.right
          anchors.rightMargin: d.t.sp(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: d.t.sp(3)
          Text {
            width: parent.width
            text: d.meUser ? (d.meUser.display || d.meUser.real || d.meUser.name || "") : ""
            textFormat: Text.PlainText
            color: d.t.fgBright
            font.family: d.t.font
            font.pixelSize: d.t.fsText + 1
            font.bold: true
            elide: Text.ElideRight
          }
          Row {
            spacing: d.t.sp(6)
            PresenceDot {
              app: d.app
              anchors.verticalCenter: parent.verticalCenter
              size: d.t.sp(9)
              ring: "transparent"
              active: d.active
              paused: d.paused
            }
            Text {
              text: d.active ? d.app.tr("Active", "Ativo") : d.app.tr("Away", "Ausente")
              color: d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      Repeater {
        model: d.items
        delegate: Loader {
          id: row
          required property var modelData
          required property int index
          width: col.width
          sourceComponent: modelData.kind === "sep" ? sepC : (modelData.kind === "status" ? statusC : itemC)

          Component {
            id: sepC
            Item { height: d.t.sp(11); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: d.t.line } }
          }

          // The status "field": what you're up to, or the invitation to say it.
          Component {
            id: statusC
            Item {
              height: d.t.sp(48)
              Rectangle {
                id: field
                anchors.fill: parent
                anchors.leftMargin: d.t.sp(6)
                anchors.rightMargin: d.t.sp(6)
                anchors.topMargin: d.t.sp(2)
                anchors.bottomMargin: d.t.sp(8)
                radius: Math.max(6, d.t.radiusSmall)
                color: d.hot === row.index ? d.t.hoverStrong : d.t.alpha(d.t.fg, 0.04)
                border.width: 1
                border.color: d.hot === row.index ? d.t.alpha(d.t.accent, 0.7) : d.t.lineStrong

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: { d.hot = row.index; d.closeSub() }
                  onExited: if (d.hot === row.index) d.hot = -1
                  onClicked: d.activate(row.index)
                }
                Loader {
                  x: d.t.sp(10)
                  anchors.verticalCenter: parent.verticalCenter
                  active: !!d.status
                  sourceComponent: EmojiIcon {
                    app: d.app
                    ws: d.ws
                    size: d.t.sp(18)
                    name: d.status ? (d.status.emoji ? d.status.emoji.replace(/^:|:$/g, "") : "speech_balloon") : "speech_balloon"
                    glyph: d.status && d.status.unicode ? Emoji.fromHex(d.status.unicode) : ""
                  }
                }
                Glyph {
                  app: d.app
                  visible: !d.status
                  x: d.t.sp(10)
                  width: d.t.sp(18)
                  anchors.verticalCenter: parent.verticalCenter
                  icon: "󰞅"
                  size: d.t.fsTitle + 2
                  color: d.t.fgDim
                }
                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: d.t.sp(38)
                  anchors.right: clearBtn.visible ? clearBtn.left : parent.right
                  anchors.rightMargin: d.t.sp(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1
                  Text {
                    width: parent.width
                    text: d.status ? (d.status.text || d.app.tr("(no text)", "(sem texto)")) : d.app.tr("Update your status", "Atualizar seu status")
                    textFormat: Text.PlainText
                    color: d.status ? d.t.fg : d.t.fgDim
                    font.family: d.t.font
                    font.pixelSize: d.t.fsText - 1
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: !!d.status && d.status.exp > 0
                    width: parent.width
                    text: d.status && d.status.exp > 0 ? d.cap(U.untilLabel(d.status.exp, d.app.lang, d.app.clock24)) : ""
                    color: d.t.fgDim
                    font.family: d.t.font
                    font.pixelSize: d.t.fsTiny
                    elide: Text.ElideRight
                  }
                }
                IconButton {
                  id: clearBtn
                  app: d.app
                  visible: !!d.status
                  anchors.right: parent.right
                  anchors.rightMargin: d.t.sp(5)
                  anchors.verticalCenter: parent.verticalCenter
                  size: d.t.sp(24)
                  icon: "󰅖"
                  iconSize: d.t.fsSmall
                  tip: d.app.tr("Clear status", "Limpar status")
                  onClicked: d.clearStatus()
                }
              }
            }
          }

          Component {
            id: itemC
            Rectangle {
              id: ir
              readonly property var it: row.modelData
              readonly property bool hot: d.hot === row.index || (!!ir.it.pause && d.subOpen)
              readonly property color fill: ir.it.danger ? d.t.red : (ir.it.good ? d.t.green : d.t.accent)
              readonly property color ink: ir.hot ? d.t.onColor(ir.fill) : (ir.it.danger ? d.t.red : (ir.it.good ? d.t.green : (ir.it.faded ? d.t.fgDim : d.t.fg)))
              height: ir.it.sub2 ? d.t.sp(44) : d.t.sp(30)
              radius: Math.max(4, d.t.radiusSmall)
              color: ir.hot ? ir.fill : "transparent"
              Column {
                anchors.left: parent.left
                anchors.leftMargin: d.t.sp(12)
                anchors.right: hintText.left
                anchors.rightMargin: d.t.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: ir.it.label
                  textFormat: Text.PlainText
                  color: ir.ink
                  font.bold: !!ir.it.good
                  font.family: d.t.font
                  font.pixelSize: d.t.fsText - 1
                  elide: Text.ElideRight
                }
                Text {
                  visible: !!ir.it.sub2
                  width: parent.width
                  text: ir.it.sub2 || ""
                  textFormat: Text.PlainText
                  color: ir.hot ? d.t.alpha(ir.ink, 0.8) : d.t.yellow
                  font.family: d.t.font
                  font.pixelSize: d.t.fsTiny
                  elide: Text.ElideRight
                }
              }
              Text {
                id: hintText
                anchors.right: parent.right
                anchors.rightMargin: d.t.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                text: ir.it.pause ? "›" : (ir.it.hint || "")
                color: ir.hot ? ir.ink : d.t.fgDim
                font.family: d.t.font
                font.pixelSize: ir.it.pause ? d.t.fsTitle : d.t.fsSmall
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  d.hot = row.index
                  if (ir.it.pause) { if (!d.subOpen) d.openSub(false) }
                  else d.closeSub()
                }
                onExited: if (d.hot === row.index && !ir.it.pause) d.hot = -1
                onClicked: d.activate(row.index)
              }
              // Where the submenu goes.
              Component.onCompleted: if (ir.it.pause) d.pauseRow = ir
            }
          }
        }
      }
    }
  }

  property Item pauseRow: null

  // ---------------------------------------------------------------- the submenu
  BorderSurface {
    id: sub
    visible: d.subOpen
    readonly property point at: d.pauseRow && d.subOpen ? d.pauseRow.mapToItem(d, d.pauseRow.width + d.t.sp(12), -d.t.sp(6)) : Qt.point(0, 0)
    x: Math.min(sub.at.x, d.width - width - d.t.sp(6))
    y: Math.max(d.t.sp(6), Math.min(sub.at.y, d.height - height - d.t.sp(6)))
    width: d.t.sp(270)
    height: subCol.implicitHeight + d.t.sp(12)
    color: d.cardColor
    borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, 1)
    radius: Math.max(6, d.t.radiusCard)

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true; onEntered: d.hot = 2 }

    Column {
      id: subCol
      x: d.t.sp(6)
      y: d.t.sp(6)
      width: sub.width - d.t.sp(12)
      Repeater {
        model: d.subOpen ? d.subItems : []
        delegate: Loader {
          id: srow
          required property var modelData
          required property int index
          width: subCol.width
          sourceComponent: modelData.kind === "sep" ? ssepC : (modelData.kind === "head" ? sheadC : sitemC)
          Component {
            id: ssepC
            Item { height: d.t.sp(11); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: d.t.line } }
          }
          Component {
            id: sheadC
            Text {
              text: srow.modelData.label
              textFormat: Text.PlainText
              color: srow.index === 0 && d.paused ? d.t.yellow : d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              font.bold: true
              leftPadding: d.t.sp(12)
              rightPadding: d.t.sp(12)
              topPadding: d.t.sp(5)
              bottomPadding: d.t.sp(5)
              width: subCol.width
              elide: Text.ElideRight
            }
          }
          Component {
            id: sitemC
            Rectangle {
              id: sr
              readonly property bool hot: d.subHot === srow.index
              height: d.t.sp(30)
              radius: Math.max(4, d.t.radiusSmall)
              color: sr.hot ? d.t.accent : "transparent"
              Text {
                anchors.left: parent.left
                anchors.leftMargin: d.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                text: srow.modelData.label
                textFormat: Text.PlainText
                color: sr.hot ? d.t.selectedText : d.t.fg
                font.family: d.t.font
                font.pixelSize: d.t.fsText - 1
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: d.t.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                text: srow.modelData.hint || ""
                textFormat: Text.PlainText
                color: sr.hot ? d.t.selectedText : d.t.fgDim
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: d.subHot = srow.index
                onExited: if (!d.subKeys && d.subHot === srow.index) d.subHot = -1
                onClicked: srow.modelData.run()
              }
            }
          }
        }
      }
    }
  }
}
