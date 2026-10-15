import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Registry.js" as Reg

// A conversation: Slack's header (name, members, tabs), the messages or the
// pinned ones, and the message box — or, read-only, what keeps it so.
Item {
  id: cv
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property string convId: ws ? ws.current : ""
  readonly property var c: ws && convId ? ws.conv(convId) : null
  readonly property bool dm: !!c && (c.kind === "im" || c.kind === "mpim")
  readonly property var other: c && c.kind === "im" && ws ? ws.user(c.user) : null
  property string tab: "messages"
  onConvIdChanged: { cv.tab = "messages"; Qt.callLater(function() { cv.focusComposer() }) }

  function focusComposer() { if (composerLoader.item) composerLoader.item.focusInput() }

  readonly property string readOnly: {
    if (!c) return ""
    if ((other && other.deleted) || (c.kind === "im" && c.userDeleted)) return "deactivated"
    if (c.archived) return "archived"
    if (c.guest || c.member === false) return "guest"
    return ""
  }

  // ---------------------------------------------------------------- header
  Rectangle {
    id: header
    width: parent.width
    height: cv.t.sp(52) + tabs.height
    color: cv.t.pane

    Item {
      id: titleRow
      width: parent.width
      height: cv.t.sp(52)

      Rectangle {
        id: nameBtn
        x: cv.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        height: cv.t.sp(34)
        width: Math.min(nameRow.implicitWidth + cv.t.sp(20), parent.width - right.width - cv.t.sp(40))
        radius: Math.max(6, cv.t.radiusSmall)
        color: nameMa.containsMouse ? cv.t.hover : "transparent"
        Row {
          id: nameRow
          x: cv.t.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: cv.t.sp(8)
          Avatar {
            visible: cv.c && cv.c.kind === "im"
            app: cv.app
            ws: cv.ws
            user: cv.c ? (cv.c.user || "") : ""
            size: cv.t.sp(24)
            showPresence: true
            ring: cv.t.pane
            anchors.verticalCenter: parent.verticalCenter
          }
          Glyph {
            visible: !!cv.c && cv.c.kind !== "im"
            app: cv.app
            icon: !cv.c ? "" : (cv.c.kind === "private" ? "󰌾" : (cv.c.kind === "mpim" ? "󰀏" : (cv.c.archived ? "󱈎" : "#")))
            size: cv.t.fsHeader
            font.bold: true
            color: cv.t.fgBright
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: cv.c ? cv.ws.convLabel(cv.convId).replace(/ \((you|você)\)$/, "") : ""
            textFormat: Text.PlainText
            color: cv.t.fgBright
            font.family: cv.t.font
            font.pixelSize: cv.t.fsHeader
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: Math.min(implicitWidth, cv.width * 0.45)
          }
          EmojiIcon {
            visible: !!cv.other && !!cv.ws.statusOf(cv.other.id)
            app: cv.app
            ws: cv.ws
            name: cv.other && cv.ws.statusOf(cv.other.id) ? cv.ws.statusOf(cv.other.id).emoji.replace(/:/g, "") : ""
            size: cv.t.sp(18)
            anchors.verticalCenter: parent.verticalCenter
          }
          Glyph { app: cv.app; icon: "󰅀"; size: cv.t.fsSmall; color: cv.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
          id: nameMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: cv.details()
        }
      }

      Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: cv.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: cv.t.sp(6)

        // The member faces and count.
        Rectangle {
          visible: !!cv.c && !cv.dm && (cv.c.numMembers || 0) > 0
          height: cv.t.sp(30)
          width: faces.implicitWidth + cv.t.sp(14)
          radius: Math.max(6, cv.t.radiusSmall)
          color: memMa.containsMouse ? cv.t.hover : "transparent"
          border.width: 1
          border.color: cv.t.lineStrong
          Row {
            id: faces
            anchors.centerIn: parent
            spacing: cv.t.sp(6)
            Glyph { app: cv.app; icon: "󰀏"; size: cv.t.fsIcon - 1; color: cv.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
            Text { text: cv.c ? (cv.c.numMembers || 0) : ""; color: cv.t.fg; font.family: cv.t.font; font.pixelSize: cv.t.fsSmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { id: memMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cv.win.dialog("details", { conv: cv.convId, tab: "members" }) }
          PanelToolTip { visible: memMa.containsMouse; text: cv.app.tr("View all members of this channel", "Ver todos os membros do canal") }
        }
        IconButton {
          app: cv.app
          icon: cv.ws && cv.ws.isStarred(cv.convId) ? "󰓎" : "󰓒"
          color: cv.ws && cv.ws.isStarred(cv.convId) ? cv.t.yellow : cv.t.fgSoft
          tip: cv.ws && cv.ws.isStarred(cv.convId) ? cv.app.tr("Remove from starred", "Remover dos favoritos") : cv.app.tr("Star conversation", "Adicionar aos favoritos")
          visible: !cv.readOnly
          onClicked: cv.ws.setStar(cv.convId, !cv.ws.isStarred(cv.convId))
        }
        IconButton {
          app: cv.app
          icon: "󰍉"
          tip: cv.app.tr("Search in this conversation", "Buscar nesta conversa")
          onClicked: cv.win.search("in:" + (cv.c && !cv.dm ? "#" + cv.c.name : "@" + (cv.other ? cv.other.handle || cv.other.name : "")) + " ")
        }
        IconButton {
          id: moreBtn
          app: cv.app
          icon: "󰇙"
          tip: cv.app.tr("More", "Mais")
          onClicked: cv.headerMenu(moreBtn)
        }
      }
    }

    // Tabs: Messages · Pins · topic.
    Item {
      id: tabs
      y: titleRow.height
      width: parent.width
      height: cv.t.sp(34)
      Row {
        x: cv.t.sp(14)
        height: parent.height
        spacing: cv.t.sp(4)
        HeaderTab { app: cv.app; icon: "󰍥"; label: cv.app.tr("Messages", "Mensagens"); active: cv.tab === "messages"; onClicked: cv.tab = "messages" }
        HeaderTab {
          app: cv.app; icon: "󰐃"
          label: cv.app.tr("Pins", "Fixados") + (cv.pinCount > 0 ? " " + cv.pinCount : "")
          active: cv.tab === "pins"
          visible: cv.pinCount > 0 || cv.tab === "pins"
          onClicked: cv.tab = "pins"
        }
        HeaderTab {
          id: addTab
          app: cv.app; icon: "󰐕"; label: ""
          onClicked: cv.win.menuAt(addTab, [
            { header: cv.app.tr("Add to this conversation", "Adicionar a esta conversa") },
            { label: cv.app.tr("Edit topic", "Editar tópico"), icon: "󰏫", enabled: !cv.dm, action: function() { cv.win.dialog("details", { conv: cv.convId, tab: "about", edit: "topic" }) } },
            { label: cv.app.tr("Add people", "Adicionar pessoas"), icon: "󰠁", enabled: !cv.dm, action: function() { cv.win.dialog("details", { conv: cv.convId, tab: "members", add: true }) } }
          ])
        }
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: cv.t.sp(16)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.45)
        text: cv.c && cv.c.topic ? cv.c.topic.replace(/<[^|>]*\|([^>]*)>/g, "$1").replace(/<([^>]*)>/g, "$1").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/\s+/g, " ") : ""
        textFormat: Text.PlainText
        color: cv.t.fgDim
        font.family: cv.t.font
        font.pixelSize: cv.t.fsSmall
        elide: Text.ElideRight
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cv.win.dialog("details", { conv: cv.convId, tab: "about" }) }
      }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: cv.t.line }
    }
  }

  readonly property int pinCount: { var p = cv.ws ? cv.ws.pinsOf(cv.convId) : null; return p ? p.length : 0 }

  // ---------------------------------------------------------------- messages
  MessageList {
    id: messages
    visible: cv.tab === "messages"
    anchors.top: header.bottom
    anchors.bottom: footer.top
    width: parent.width
    app: cv.app
    win: cv.win
    ws: cv.ws
    conv: cv.convId
    intro: introC
    onLeave: cv.focusComposer()
  }

  Component {
    id: introC
    ConversationIntro { app: cv.app; win: cv.win; ws: cv.ws; conv: cv.convId }
  }

  PinsList {
    visible: cv.tab === "pins"
    anchors.top: header.bottom
    anchors.bottom: footer.top
    width: parent.width
    app: cv.app
    win: cv.win
    ws: cv.ws
    conv: cv.convId
  }

  // ---------------------------------------------------------------- footer
  Column {
    id: footer
    anchors.bottom: parent.bottom
    width: parent.width
    bottomPadding: cv.t.sp(4)

    // The other person paused notifications.
    Text {
      visible: !!cv.other && cv.ws.isPaused(cv.other.id) && !cv.readOnly
      x: cv.t.sp(22)
      width: parent.width - cv.t.sp(44)
      bottomPadding: cv.t.sp(6)
      text: "󰂛  " + (cv.other ? cv.other.name : "") + cv.app.tr(" has paused their notifications.", " pausou as próprias notificações.")
      textFormat: Text.PlainText
      color: cv.t.fgDim
      font.family: cv.t.font
      font.pixelSize: cv.t.fsSmall
      font.italic: true
    }

    Loader {
      id: composerLoader
      active: cv.readOnly === "" && !!cv.c
      visible: active
      x: cv.t.sp(20)
      width: parent.width - cv.t.sp(40)
      sourceComponent: Composer { app: cv.app; win: cv.win; ws: cv.ws; conv: cv.convId; messageList: messages }
    }

    ReadOnlyNotice {
      visible: cv.readOnly !== ""
      x: cv.t.sp(20)
      width: parent.width - cv.t.sp(40)
      app: cv.app
      ws: cv.ws
      conv: cv.convId
      reason: cv.readOnly
    }

    // Who is typing.
    Item {
      width: parent.width
      height: cv.t.sp(20)
      Row {
        x: cv.t.sp(24)
        anchors.verticalCenter: parent.verticalCenter
        spacing: cv.t.sp(6)
        readonly property var names: cv.ws ? cv.ws.typingIn(cv.convId) : []
        visible: names.length > 0
        TypingDots { app: cv.app; color: cv.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: Model.typingText(parent.names, cv.app.lang)
          textFormat: Text.PlainText
          color: cv.t.fgDim
          font.family: cv.t.font
          font.pixelSize: cv.t.fsTiny + 1
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  Rectangle {
    visible: !cv.c && !!cv.ws
    anchors.fill: parent
    color: cv.t.pane
    Text {
      anchors.centerIn: parent
      text: cv.ws && cv.ws.booted ? cv.app.tr("Pick a conversation", "Escolha uma conversa") : cv.app.tr("Loading your workspace…", "Carregando seu workspace…")
      color: cv.t.fgDim
      font.family: cv.t.font
      font.pixelSize: cv.t.fsTitle
    }
  }

  // ---------------------------------------------------------------- actions
  function details() {
    if (!cv.c) return
    if (cv.c.kind === "im") { cv.ws.profileUser = cv.c.user; cv.ws.thread = null; return }
    cv.win.dialog("details", { conv: cv.convId, tab: cv.c.kind === "mpim" ? "members" : "about" })
  }

  function headerMenu(anchor) {
    var w = cv.ws, id = cv.convId, c = cv.c
    if (!c) return
    var items = []
    items.push({ label: cv.dm && c.kind === "im" ? cv.app.tr("View full profile", "Ver perfil completo") : cv.app.tr("Open channel details", "Abrir detalhes do canal"), icon: "󰋼", hint: "Ctrl+Shift+I", action: function() { cv.details() } })
    if (!cv.dm) {
      var level = w.notifyLevel(id)
      items.push({ label: cv.app.tr("Notifications", "Notificações"), icon: "󰂚", sub: [
        { label: cv.app.tr("All new messages", "Todas as novas mensagens"), checked: level === "all", action: function() { w.setNotify(id, "all") } },
        { label: cv.app.tr("Mentions", "Menções"), checked: level === "mentions", action: function() { w.setNotify(id, "mentions") } },
        { label: cv.app.tr("Mute", "Silenciar"), checked: level === "mute", action: function() { w.setNotify(id, "mute") } }
      ] })
    }
    items.push({ label: cv.app.tr("Mark as read", "Marcar como lida"), icon: "󰄬", action: function() { w.markRead(id) } })
    items.push({ separator: true })
    items.push({ label: cv.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() { cv.app.copy(U.convUrl(w.team.domain, id)); cv.win.toast(cv.app.tr("Link copied", "Link copiado")) } })
    items.push({ label: cv.app.tr("Open in browser", "Abrir no navegador"), icon: "󰖟", action: function() { Qt.openUrlExternally(U.convUrl(w.team.domain, id)) } })
    if (!cv.dm && !c.general) {
      items.push({ separator: true })
      items.push({ label: cv.app.tr("Leave channel", "Sair do canal"), icon: "󰍃", danger: true, action: function() { w.leave(id) } })
    }
    if (cv.dm) {
      items.push({ separator: true })
      items.push({ label: cv.app.tr("Close conversation", "Fechar conversa"), icon: "󰅖", action: function() { w.closeDm(id) } })
    }
    cv.win.menuAt(anchor, items, -cv.t.sp(220), anchor.height + cv.t.sp(4))
  }
}
