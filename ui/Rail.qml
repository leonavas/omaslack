import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// The rail on the far left: the workspaces (stacked like Slack's, only the
// one you're in, or all of them, Preferences → Sidebar), Slack's tabs (Home,
// DMs, Activity, Later, More), the "+", pausing notifications and your photo
// with your status. Everything sits on one center line, in squares of one
// size (`tile`).
Item {
  id: rail
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme

  readonly property int tile: t.sp(36)
  readonly property real tileRadius: Math.max(t.sp(8), t.radiusSmall + 2)
  readonly property bool stacked: app.setting("railWorkspaces", "stacked") !== "expanded"
  readonly property bool many: app.workspaces.length > 1

  // What's unread in the workspaces you're not in: the stacked tile's badge.
  readonly property var others: {
    var out = { total: 0, channels: 0 }
    rail.app.workspaces.forEach(function(w) {
      if (w === rail.ws) return
      out.total += w.attention.total
      out.channels += w.attention.channels
    })
    return out
  }

  // Your status, and the pause (every workspace pauses together).
  readonly property var myStatus: rail.ws && rail.ws.me.id ? rail.ws.statusOf(rail.ws.me.id) : null
  readonly property var pausedUntil: {
    if (rail.ws && rail.ws.dnd) return rail.ws.dnd.until || 0
    var list = rail.app.workspaces
    for (var i = 0; i < list.length; i++) if (list[i].dnd) return list[i].dnd.until || 0
    return null
  }
  readonly property bool paused: rail.pausedUntil !== null

  Column {
    id: top
    anchors.horizontalCenter: parent.horizontalCenter
    y: rail.t.sp(10)
    spacing: rail.t.sp(10)

    // Workspaces: the one you're in (the others stacked behind it), or all.
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: rail.t.sp(14)
      Repeater {
        model: rail.stacked ? (rail.ws ? [rail.ws] : []) : rail.app.workspaces
        delegate: Item {
          id: wsItem
          required property var modelData
          readonly property var w: modelData
          readonly property bool cur: w === rail.ws
          readonly property int pos: rail.app.workspaces.indexOf(w)
          // Stacked: what's unread elsewhere; expanded: in this one.
          readonly property int count: rail.stacked ? rail.others.total : (cur ? 0 : w.attention.total)
          readonly property bool dot: count === 0 && (rail.stacked ? rail.others.channels > 0 : (!cur && w.attention.channels > 0))
          width: rail.tile
          height: rail.tile + (stackLayer.visible ? stackLayer.peek : 0)
          anchors.horizontalCenter: parent.horizontalCenter

          // The other workspaces, a narrower layer peeking out below.
          Rectangle {
            id: stackLayer
            readonly property int peek: rail.t.sp(5)
            visible: rail.stacked && rail.many
            y: peek
            width: rail.tile - rail.t.sp(10)
            height: rail.tile
            anchors.horizontalCenter: parent.horizontalCenter
            radius: rail.tileRadius
            color: rail.t.alpha(rail.t.fgBright, wma.containsMouse ? 0.36 : 0.26)
          }
          // Expanded: a thin ring, a gap away, around the one you're in
          // (fainter on hover): drawn outside, the tile keeps its size.
          Rectangle {
            readonly property int out: rail.t.sp(4)
            visible: !rail.stacked && rail.many && (wsItem.cur || wma.containsMouse)
            x: -out
            y: -out
            width: rail.tile + 2 * out
            height: width
            radius: rail.tileRadius + out
            color: "transparent"
            border.width: Math.max(2, rail.t.sp(2))
            border.color: wsItem.cur ? rail.t.fgBright : rail.t.alpha(rail.t.fgBright, 0.3)
          }
          WorkspaceIcon {
            app: rail.app
            w: wsItem.w
            size: rail.tile
            radius: rail.tileRadius
          }
          Badge {
            app: rail.app
            visible: wsItem.count > 0
            count: wsItem.count
            x: rail.tile - width + rail.t.sp(6)
            y: -rail.t.sp(5)
          }
          Rectangle {
            visible: wsItem.dot
            width: rail.t.sp(11); height: width; radius: width / 2
            color: rail.t.fgBright
            border.width: 2
            border.color: rail.t.frame
            x: rail.tile - width + rail.t.sp(3)
            y: -rail.t.sp(3)
          }
          MouseArea {
            id: wma
            width: rail.tile
            height: wsItem.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
              if (mouse.button === Qt.RightButton) rail.teamMenu(wsItem, wsItem.w)
              else if (rail.stacked) rail.switcher(wsItem)
              else if (wsItem.cur) rail.teamMenu(wsItem, wsItem.w)
              else rail.app.switchTo(wsItem.w.teamId)
            }
          }
          PanelToolTip {
            visible: wma.containsMouse
            text: rail.stacked
                  ? wsItem.w.team.name + (rail.many ? "  ·  " + rail.app.tr("Switch workspace", "Trocar de workspace") : "")
                  : wsItem.w.team.name + (wsItem.pos >= 0 && wsItem.pos < 9 ? "  Ctrl+" + (wsItem.pos + 1) : "")
          }
        }
      }
    }

    Rectangle { visible: !rail.stacked && rail.many; width: rail.t.sp(28); height: 1; color: rail.t.alpha(rail.t.fgBright, 0.18); anchors.horizontalCenter: parent.horizontalCenter }

    RailTab { app: rail.app; icon: "󰋜"; label: rail.app.tr("Home", "Início"); active: rail.win.railTab === "home"; onClicked: rail.win.railTab = "home" }
    RailTab {
      app: rail.app; icon: "󰠢"; label: "DMs"; active: rail.win.railTab === "dms"
      dot: !!rail.ws && rail.ws.attention.dms > 0
      onClicked: rail.win.railTab = rail.win.railTab === "dms" ? "home" : "dms"
    }
    RailTab {
      app: rail.app; icon: "󰂚"; label: rail.app.tr("Activity", "Atividade"); active: rail.win.railTab === "activity"
      count: rail.ws ? rail.ws.attention.mentions : 0
      onClicked: rail.win.railTab = rail.win.railTab === "activity" ? "home" : "activity"
    }
    RailTab {
      app: rail.app; icon: "󰃀"; label: rail.app.tr("Later", "Depois"); active: rail.win.railTab === "later"
      onClicked: rail.win.railTab = rail.win.railTab === "later" ? "home" : "later"
    }
    RailTab {
      id: moreTab
      app: rail.app; icon: "󰇘"; label: rail.app.tr("More", "Mais")
      onClicked: rail.win.menuAt(moreTab, [
        { header: rail.app.tr("More", "Mais") },
        { label: rail.app.tr("Threads", "Conversas"), icon: "󰍪", hint: "Ctrl+Shift+T", action: function() { rail.win.railTab = "home"; rail.ws.showView("threads") } },
        { label: rail.app.tr("Drafts & sent", "Rascunhos e enviados"), icon: "󰒊", action: function() { rail.win.railTab = "home"; rail.ws.showView("drafts") } },
        { label: rail.app.tr("Browse channels", "Navegar pelos canais"), icon: "󰐣", hint: "Ctrl+Shift+L", action: function() { rail.win.dialog("browse") } },
        { label: rail.app.tr("People", "Pessoas"), icon: "󰀏", action: function() { rail.win.dialog("people") } },
        { separator: true },
        { label: rail.app.tr("Invite people", "Convidar pessoas"), icon: "󰠁", action: function() { rail.win.dialog("invite") } }
      ], rail.t.sp(62), 0)
    }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: rail.t.sp(12)
    spacing: rail.t.sp(14)
    visible: !!rail.ws

    Rectangle {
      width: rail.tile; height: width; radius: width / 2
      anchors.horizontalCenter: parent.horizontalCenter
      color: plusMa.containsMouse ? rail.t.alpha(rail.t.fgBright, 0.3) : rail.t.alpha(rail.t.fgBright, 0.18)
      Glyph { app: rail.app; anchors.centerIn: parent; icon: "󰐕"; color: rail.t.fgBright; size: rail.t.fsTitle + 2 }
      MouseArea {
        id: plusMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rail.win.menuAt(parent, [
          { header: rail.app.tr("Create", "Criar") },
          { label: rail.app.tr("Message", "Mensagem"), icon: "󰤌", hint: "Ctrl+N", action: function() { rail.win.dialog("newMessage") } },
          { label: rail.app.tr("Channel", "Canal"), icon: "󰐣", action: function() { rail.win.dialog("newChannel") } },
          { separator: true },
          { label: rail.app.tr("Invite people", "Convidar pessoas"), icon: "󰠁", action: function() { rail.win.dialog("invite") } },
          { label: rail.app.tr("Add a workspace", "Adicionar um workspace"), icon: "󰐕", action: function() { rail.win.dialog("addWorkspace") } }
        ], parent.width + rail.t.sp(8), -rail.t.sp(150))
      }
    }

    // Pause notifications: filled while paused.
    Rectangle {
      id: moon
      width: rail.tile; height: width; radius: width / 2
      anchors.horizontalCenter: parent.horizontalCenter
      color: rail.paused ? (moonMa.containsMouse ? Qt.darker(rail.t.fgBright, 1.08) : rail.t.fgBright)
                         : (moonMa.containsMouse ? rail.t.alpha(rail.t.fgBright, 0.3) : rail.t.alpha(rail.t.fgBright, 0.18))
      Glyph { app: rail.app; anchors.centerIn: parent; icon: "󰤄"; color: rail.paused ? rail.t.frame : rail.t.fgBright; size: rail.t.fsTitle + 1 }
      MouseArea {
        id: moonMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rail.pauseMenu(moon)
      }
      PanelToolTip {
        visible: moonMa.containsMouse
        text: !rail.paused ? rail.app.tr("Pause notifications", "Pausar notificações")
              : rail.app.tr("Notifications paused", "Notificações pausadas") + (rail.pausedUntil ? " " + U.untilLabel(rail.pausedUntil, rail.app.lang, rail.app.clock24) : "")
      }
    }

    // A newer version: a small green button over your photo, like slick's by
    // your name (core/Updater.qml); faded while it updates, "reload" once
    // it's on disk but not loaded. Your menu has it too.
    Rectangle {
      id: upPill
      readonly property var up: rail.app.updater
      readonly property bool busy: !!upPill.up && upPill.up.phase === "updating"
      visible: !!upPill.up && upPill.up.phase !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(rail.width - rail.t.sp(8), upText.implicitWidth + rail.t.sp(14))
      height: rail.t.sp(18)
      radius: height / 2
      color: upPill.busy ? rail.t.alpha(rail.t.fgBright, 0.18) : (upMa.containsMouse ? Qt.lighter(rail.t.green, 1.12) : rail.t.green)
      Text {
        id: upText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, upPill.width - rail.t.sp(8))
        elide: Text.ElideRight
        text: !upPill.up ? "" : upPill.busy ? rail.app.tr("updating…", "atualizando…")
              : upPill.up.phase === "updated" ? rail.app.tr("↻ reload", "↻ recarregar") : "↑ " + upPill.up.latest
        color: upPill.busy ? rail.t.fgDim : rail.t.onColor(rail.t.green)
        font.family: rail.t.font
        font.pixelSize: rail.t.fsTiny
        font.bold: true
      }
      MouseArea {
        id: upMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: upPill.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: upPill.up.update()
      }
      PanelToolTip {
        visible: upMa.containsMouse
        text: !upPill.up ? "" : upPill.busy ? rail.app.tr("Updating Slack to ", "Atualizando o Slack para ") + upPill.up.latest + "…"
              : upPill.up.phase === "updated" ? rail.app.tr("Reload to use ", "Recarregue para usar a versão ") + upPill.up.latest
              : upPill.up.how || rail.app.tr("Update to ", "Atualizar para ") + upPill.up.latest
      }
    }

    // Your photo, its presence dot and, over its top edge, your status emoji.
    Item {
      width: rail.tile
      height: rail.tile
      anchors.horizontalCenter: parent.horizontalCenter

      Avatar {
        app: rail.app
        ws: rail.ws
        user: rail.ws ? rail.ws.me.id : ""
        size: rail.tile
        showPresence: true
        ring: rail.t.frame
        onClicked: rail.win.dialog("account", {})
      }
      Rectangle {
        visible: !!rail.myStatus
        width: rail.t.sp(22); height: width; radius: width / 2
        x: rail.tile - Math.round(width * 0.7)
        y: -Math.round(height * 0.45)
        color: rail.t.frame
        EmojiIcon {
          anchors.centerIn: parent
          app: rail.app
          ws: rail.ws
          size: rail.t.sp(16)
          name: rail.myStatus && rail.myStatus.emoji ? rail.myStatus.emoji.replace(/^:|:$/g, "") : "speech_balloon"
          glyph: rail.myStatus && rail.myStatus.unicode ? Emoji.fromHex(rail.myStatus.unicode) : ""
          url: rail.myStatus ? rail.myStatus.url : ""
        }
        MouseArea {
          id: statusMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: rail.win.dialog("status", {})
        }
        PanelToolTip {
          visible: statusMa.containsMouse
          text: {
            var s = rail.myStatus
            if (!s) return ""
            var out = s.text || s.emoji
            if (s.exp) out += (out ? "  ·  " : "") + U.untilLabel(s.exp, rail.app.lang, rail.app.clock24)
            return out
          }
        }
      }
    }
  }

  // The workspace switcher, beside the stacked tile.
  function switcher(item) {
    var p = item.mapToItem(rail.win.rootItem, item.width + rail.t.sp(12), 0)
    rail.win.dialog("workspaces", { x: p.x, y: p.y })
  }

  // The moon's menu: pause for a while (or resume, or change the pause).
  function pauseMenu(item) {
    var a = rail.app, w = rail.win
    function p(min) { a.pauseAll(min); w.toast(a.tr("Notifications paused ", "Notificações pausadas ") + U.untilLabel(Math.floor(Date.now() / 1000) + min * 60, a.lang, a.clock24)) }
    var items = []
    if (rail.paused) {
      items.push({ header: rail.pausedUntil ? a.tr("Paused ", "Pausadas ") + U.untilLabel(rail.pausedUntil, a.lang, a.clock24) : a.tr("Paused", "Pausadas") })
      items.push({ label: a.tr("Resume notifications", "Retomar notificações"), action: function() { a.resumeAll(); w.toast(a.tr("Notifications resumed", "Notificações retomadas")) } })
      items.push({ separator: true })
      items.push({ header: a.tr("Change the pause to…", "Mudar a pausa para…") })
    } else items.push({ header: a.tr("Pause notifications for…", "Pausar notificações por…") })
    items.push({ label: a.tr("30 minutes", "30 minutos"), action: function() { p(30) } })
    items.push({ label: a.tr("1 hour", "1 hora"), action: function() { p(60) } })
    items.push({ label: a.tr("2 hours", "2 horas"), action: function() { p(120) } })
    items.push({ label: a.tr("Until tomorrow", "Até amanhã"), hint: U.time(new Date(Date.now() + U.minutesUntilTomorrow9() * 60000), a.clock24), action: function() { p(U.minutesUntilTomorrow9()) } })
    items.push({ label: a.tr("Until next week", "Até a próxima semana"), hint: a.tr("Mon ", "seg ") + U.time(new Date(Date.now() + U.minutesUntilNextWeek9() * 60000), a.clock24),
                 action: function() { p(U.minutesUntilNextWeek9()) } })
    items.push({ label: a.tr("Custom…", "Personalizado…"), action: function() { w.dialog("pause", {}) } })
    items.push({ separator: true })
    items.push({ label: a.tr("Notification preferences", "Preferências de notificação"), action: function() { w.dialog("preferences", { section: "notifications" }) } })
    w.menuAt(item, items, item.width + rail.t.sp(10), item.height)
  }

  function teamMenu(item, w) {
    var items = [{ header: w.team.name + (w.team.domain ? "  ·  " + w.team.domain + ".slack.com" : "") }]
    rail.app.workspaces.forEach(function(o, i) {
      if (o === w) return
      items.push({ label: o.team.name, icon: "󰀻", hint: i < 9 ? "Ctrl+" + (i + 1) : "", action: function() { rail.app.switchTo(o.teamId) } })
    })
    items.push({ separator: true })
    items.push({ label: rail.app.tr("Add a workspace", "Adicionar um workspace"), icon: "󰐕", action: function() { rail.win.dialog("addWorkspace") } })
    items.push({ label: rail.app.tr("Invite people to ", "Convidar pessoas para ") + w.team.name, icon: "󰠁", action: function() { rail.win.dialog("invite") } })
    items.push({ label: rail.app.tr("Preferences", "Preferências"), icon: "󰒓", action: function() { rail.win.dialog("preferences") } })
    items.push({ separator: true })
    items.push({ label: rail.app.tr("Sign out of ", "Sair de ") + w.team.name, icon: "󰍃", danger: true, action: function() { rail.win.dialog("confirm", {
      title: rail.app.tr("Sign out of ", "Sair de ") + w.team.name + "?",
      text: rail.app.tr("This app forgets the session. Slack in your browser stays signed in.", "Este app esquece a sessão. O Slack no navegador continua conectado."),
      confirm: rail.app.tr("Sign out", "Sair"), danger: true,
      action: function() { rail.app.signOut(w.teamId) } }) } })
    rail.win.menuAt(item, items, item.width + rail.t.sp(10), 0)
  }
}
