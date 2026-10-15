import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Registry.js" as Reg

// The rail's DMs tab (in the sidebar's place): every direct and group
// message, latest activity first, with the photo, when and the last
// message ("You: …"). Unread ones are bold with their count; "Unreads"
// keeps only those.
Rectangle {
  id: dl
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  readonly property bool narrow: width < t.sp(150)
  property bool unreadsOnly: app.setting("dmsUnreadsOnly", false) === true
  property string query: ""
  color: t.sidebar

  readonly property var rows: {
    if (!ws) return []
    ws.convsRev; ws.countsRev; ws.usersRev
    var me = ws.me.id
    var out = []
    for (var id in ws.convs) {
      var c = ws.convs[id]
      if (!c || (c.kind !== "im" && c.kind !== "mpim") || c.archived) continue
      var k = ws.counts[id] || null
      var latest = k && k.latest ? k.latest : (c.updated ? String(c.updated / 1000) : "")
      var unread = !!k && (k.unread || k.mentions > 0)
      var u = c.kind === "im" ? ws.users[c.user] : null
      if (u && u.deleted && !unread) continue
      if (dl.unreadsOnly && !unread && id !== ws.current) continue
      var label = ws.convLabel(id)
      if (dl.query && U.rank(label, dl.query) < 0) continue
      var members = c.kind === "mpim" ? Model.mpimMembers(c, ws.users, me, ws.handles) : []
      out.push({ key: id, id: id, kind: c.kind, user: c.user || "", self: c.user === me, label: label, members: members,
                 latest: latest, unread: unread, mentions: k ? (k.mentions || 0) : 0 })
    }
    out.sort(function(a, b) { return U.cmpTs(b.latest, a.latest) })
    return out
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: dl.t.sp(50)
    Text {
      visible: !dl.narrow
      x: dl.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - compose.width - dl.t.sp(20)
      text: dl.app.tr("Direct messages", "Mensagens diretas")
      color: dl.t.fgBright
      font.family: dl.t.font
      font.pixelSize: dl.t.fsHeader
      font.bold: true
      elide: Text.ElideRight
    }
    IconButton {
      id: compose
      app: dl.app
      anchors.right: parent.right
      anchors.rightMargin: dl.narrow ? (parent.width - width) / 2 : dl.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      size: dl.t.sp(32)
      icon: "󰤌"
      tip: dl.app.tr("New message", "Nova mensagem") + "  Ctrl+N"
      color: dl.t.fgBright
      hoverColor: dl.t.hoverStrong
      onClicked: dl.win.dialog("newMessage")
    }
  }

  // Find a DM · Unreads.
  Item {
    id: tools
    visible: !dl.narrow
    y: header.height
    width: parent.width
    height: visible ? dl.t.sp(44) : 0
    SField {
      id: find
      app: dl.app
      x: dl.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - unreadChip.width - dl.t.sp(20)
      height: dl.t.sp(32)
      icon: "󰍉"
      placeholderText: dl.app.tr("Find a DM", "Buscar uma DM")
      font.pixelSize: dl.t.fsSmall + 1
      topPadding: 0
      bottomPadding: 0
      onTextChanged: dl.query = text.trim()
      Keys.onEscapePressed: text = ""
    }
    Rectangle {
      id: unreadChip
      anchors.right: parent.right
      anchors.rightMargin: dl.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      height: dl.t.sp(30)
      width: chipRow.implicitWidth + dl.t.sp(16)
      radius: height / 2
      color: dl.unreadsOnly ? dl.t.accent : (chipMa.containsMouse ? dl.t.hover : "transparent")
      border.width: dl.unreadsOnly ? 0 : 1
      border.color: dl.t.lineStrong
      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: dl.t.sp(5)
        Glyph { app: dl.app; icon: dl.unreadsOnly ? "󰄬" : "󰇮"; size: dl.t.fsSmall; color: dl.unreadsOnly ? dl.t.selectedText : dl.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: dl.app.tr("Unreads", "Não lidas")
          color: dl.unreadsOnly ? dl.t.selectedText : dl.t.fg
          font.family: dl.t.font
          font.pixelSize: dl.t.fsSmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      MouseArea {
        id: chipMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { dl.unreadsOnly = !dl.unreadsOnly; dl.app.setSetting("dmsUnreadsOnly", dl.unreadsOnly) }
      }
      PanelToolTip { visible: chipMa.containsMouse; text: dl.app.tr("Show only unread messages", "Mostrar só mensagens não lidas") }
    }
  }

  Rectangle { y: tools.y + tools.height; width: parent.width; height: 1; color: dl.t.line }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    y: tools.y + tools.height + 1
    width: parent.width
    height: parent.height - y
    clip: true
    topMargin: dl.t.sp(6)
    bottomMargin: dl.t.sp(12)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: dl.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: dl.app }

    delegate: Item {
      id: row
      required property var modelData
      readonly property bool selected: dl.ws.view === "conv" && dl.ws.current === modelData.id
      readonly property bool hot: ma.containsMouse
      readonly property var last: { dl.ws.lastRev; return dl.ws.lastMsgs[modelData.id] || null }
      readonly property color ink: selected ? dl.t.rowSelectedText : (modelData.unread ? dl.t.fgBright : dl.t.fg)
      readonly property color soft: selected ? dl.t.alpha(dl.t.rowSelectedText, 0.8) : (modelData.unread ? dl.t.fg : dl.t.fgDim)
      // The row's fill, and the color it makes over the list: the photos'
      // rings (and so the presence dot) match it on every state.
      readonly property color fill: selected ? dl.t.rowSelected : (ma.pressed ? dl.t.hoverStrong : (hot ? dl.t.hover : "transparent"))
      readonly property color under: Qt.tint(dl.t.sidebar, fill)
      width: list.width
      height: dl.narrow ? dl.t.sp(52) : dl.t.sp(66)

      Component.onCompleted: dl.ws.fetchLast(modelData.id)

      Rectangle {
        x: dl.t.sp(8)
        width: parent.width - dl.t.sp(16)
        height: parent.height - dl.t.sp(2)
        y: 1
        radius: Math.max(6, dl.t.radiusSmall)
        color: row.fill
      }

      // Photo(s).
      Item {
        id: lead
        x: dl.narrow ? (row.width - width) / 2 : dl.t.sp(18)
        anchors.verticalCenter: parent.verticalCenter
        width: dl.t.sp(36)
        height: width
        Avatar {
          visible: row.modelData.kind === "im"
          anchors.fill: parent
          app: dl.app
          ws: dl.ws
          user: row.modelData.user
          size: parent.width
          showPresence: true
          ring: row.under
          onClicked: dl.ws.open(row.modelData.id)
        }
        // A group: two photos, one over the other.
        Item {
          visible: row.modelData.kind === "mpim"
          anchors.fill: parent
          Avatar {
            app: dl.app
            ws: dl.ws
            user: row.modelData.members[0] || ""
            name: row.modelData.members.length ? "" : row.modelData.label
            size: dl.t.sp(26)
          }
          Rectangle {
            x: dl.t.sp(10) - 2
            y: dl.t.sp(10) - 2
            width: dl.t.sp(26) + 4
            height: width
            radius: Math.round(width * 0.24)
            color: row.under
            Avatar {
              x: 2
              y: 2
              app: dl.app
              ws: dl.ws
              user: row.modelData.members[1] || ""
              name: row.modelData.members.length > 1 ? "" : String(Math.max(2, row.modelData.members.length + 1))
              size: dl.t.sp(26)
            }
          }
        }
      }

      Badge {
        app: dl.app
        visible: dl.narrow && row.modelData.mentions > 0
        count: row.modelData.mentions
        anchors.right: lead.right
        anchors.top: lead.top
        anchors.rightMargin: -dl.t.sp(8)
        anchors.topMargin: -dl.t.sp(6)
      }

      Column {
        visible: !dl.narrow
        anchors.left: lead.right
        anchors.leftMargin: dl.t.sp(10)
        anchors.right: parent.right
        anchors.rightMargin: dl.t.sp(18)
        anchors.verticalCenter: parent.verticalCenter
        spacing: dl.t.sp(3)

        Item {
          width: parent.width
          height: nameText.implicitHeight
          Text {
            id: nameText
            width: parent.width - when.implicitWidth - dl.t.sp(8)
            text: row.modelData.label
            color: row.ink
            font.family: dl.t.font
            font.pixelSize: dl.t.fsSidebar
            font.bold: row.modelData.unread || row.selected
            elide: Text.ElideRight
          }
          Text {
            id: when
            anchors.right: parent.right
            y: nameText.baselineOffset - baselineOffset
            text: row.modelData.latest ? U.shortStamp(row.modelData.latest, dl.app.lang, dl.app.clock24) : ""
            color: row.soft
            font.family: dl.t.font
            font.pixelSize: dl.t.fsTiny
          }
        }
        Item {
          width: parent.width
          height: preview.implicitHeight
          Text {
            id: preview
            width: parent.width - (badge.visible ? badge.width + dl.t.sp(8) : 0)
            text: dl.previewOf(row.modelData, row.last)
            color: row.soft
            font.family: dl.t.font
            font.pixelSize: dl.t.fsSmall
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
          }
          Badge {
            id: badge
            app: dl.app
            anchors.right: parent.right
            anchors.verticalCenter: preview.verticalCenter
            visible: row.modelData.mentions > 0
            count: row.modelData.mentions
          }
        }
      }

      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        z: -1
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
          if (mouse.button === Qt.RightButton) { var p = ma.mapToItem(dl.win.contentItem, mouse.x, mouse.y); dl.rowMenu(row.modelData, p.x, p.y); return }
          if (mouse.button === Qt.MiddleButton) { dl.ws.markRead(row.modelData.id); return }
          dl.ws.open(row.modelData.id)
        }
      }
      PanelToolTip { visible: ma.containsMouse && dl.narrow; text: row.modelData.label }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: dl.rows.length === 0 && !dl.narrow
    anchors.horizontalCenter: parent.horizontalCenter
    y: list.y + dl.t.sp(48)
    width: parent.width - dl.t.sp(40)
    spacing: dl.t.sp(8)
    Glyph { app: dl.app; anchors.horizontalCenter: parent.horizontalCenter; icon: dl.unreadsOnly ? "󰄬" : "󰠢"; size: dl.t.sp(30); color: dl.t.fgDim }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: dl.query ? dl.app.tr("No DMs match “", "Nenhuma DM corresponde a “") + dl.query + "”"
            : (dl.unreadsOnly ? dl.app.tr("You're all caught up", "Você está em dia") : dl.app.tr("No direct messages yet", "Nenhuma mensagem direta ainda"))
      color: dl.t.fgBright
      font.family: dl.t.font
      font.pixelSize: dl.t.fsText
      font.bold: true
    }
    Text {
      visible: !dl.query
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: dl.unreadsOnly ? dl.app.tr("No unread direct messages.", "Nenhuma mensagem direta não lida.")
                           : dl.app.tr("Start a conversation with someone from your team.", "Comece uma conversa com alguém da sua equipe.")
      color: dl.t.fgDim
      font.family: dl.t.font
      font.pixelSize: dl.t.fsSmall
    }
  }

  // "You: …", "Ana: …" (groups), or the last message as is.
  function previewOf(r, m) {
    if (!m) return ""
    var text = Md.flat(m, dl.ctx, 160)
    if (Model.isMine(m, dl.ws.me.id)) return dl.app.tr("You: ", "Você: ") + text
    if (r.kind === "mpim" && m.user) return (dl.ws.userName(m.user) || "").split(" ")[0] + ": " + text
    return text
  }

  function rowMenu(r, x, y) {
    var w = dl.ws
    var items = []
    items.push({ label: dl.app.tr("Mark as read", "Marcar como lida"), icon: "󰄬", enabled: r.unread, action: function() { w.markRead(r.id) } })
    if (r.kind === "im") items.push({ label: dl.app.tr("View profile", "Ver perfil"), icon: "󰋼", action: function() { w.profileUser = r.user; w.thread = null } })
    else items.push({ label: dl.app.tr("View members", "Ver membros"), icon: "󰀏", action: function() { dl.win.dialog("details", { conv: r.id, tab: "members" }) } })
    items.push({ label: w.isStarred(r.id) ? dl.app.tr("Remove from starred", "Remover dos favoritos") : dl.app.tr("Star conversation", "Adicionar aos favoritos"),
                 icon: w.isStarred(r.id) ? "󰓒" : "󰓎", action: function() { w.setStar(r.id, !w.isStarred(r.id)) } })
    items.push({ separator: true })
    items.push({ label: dl.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() { dl.app.copy(U.convUrl(w.team.domain, r.id)); dl.win.toast(dl.app.tr("Link copied", "Link copiado")) } })
    items.push({ separator: true })
    items.push({ label: dl.app.tr("Close conversation", "Fechar conversa"), icon: "󰅖", action: function() { w.closeDm(r.id) } })
    dl.win.menu(items, x, y)
  }
}
