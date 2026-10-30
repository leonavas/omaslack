import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// Slack's toolbar over a message (`row`, a MessageItem): the one-click
// reactions, react, reply, forward, save, more. MessageList keeps one for
// all its rows and moves it; a message elsewhere makes its own on hover.
Rectangle {
  id: bar
  property var app: Reg.service
  property var win
  property var ws
  property Item row: null
  readonly property var t: app.theme
  readonly property var msg: row ? row.msg : null
  readonly property bool hovered: barHover.hovered
  property alias reactBtn: reactB
  property alias moreBtn: moreB
  visible: !!row && row.barShown
  height: t.sp(34)
  width: tools.implicitWidth + t.sp(8)
  radius: Math.max(6, t.radiusSmall)
  color: t.popup
  border.width: 1
  border.color: t.lineStrong

  // The mouse on it keeps its message lit (MessageItem.barHovered).
  property Item _row: null
  Component.onCompleted: bar._row = bar.row
  onRowChanged: { if (bar._row) bar._row.barHovered = false; bar._row = bar.row; if (bar.row) bar.row.barHovered = barHover.hovered }
  Component.onDestruction: if (bar._row) bar._row.barHovered = false
  HoverHandler { id: barHover; onHoveredChanged: if (bar.row) bar.row.barHovered = barHover.hovered }

  Row {
    id: tools
    anchors.centerIn: parent
    spacing: bar.t.sp(1)
    // The user's one-click reactions (Workspace.quickReactions).
    Repeater {
      id: quick
      model: bar.ws ? bar.ws.quickReactions : []
      delegate: Rectangle {
        required property var modelData
        width: bar.t.sp(30); height: width; radius: Math.max(4, bar.t.radiusSmall)
        color: qma.containsMouse ? bar.t.hoverStrong : "transparent"
        EmojiIcon { anchors.centerIn: parent; app: bar.app; ws: bar.ws; name: parent.modelData; size: bar.t.sp(18) }
        MouseArea { id: qma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (bar.ws.react(bar.row.conv, bar.msg.ts, parent.modelData)) bar.ws.bumpEmoji(parent.modelData) }
      }
    }
    Rectangle { visible: quick.count > 0; width: 1; height: bar.t.sp(20); color: bar.t.line; anchors.verticalCenter: parent.verticalCenter }
    IconButton { id: reactB; app: bar.app; size: bar.t.sp(30); icon: "󰇵"; tip: bar.app.tr("Add reaction", "Adicionar reação"); onClicked: bar.row.pickReaction(reactB) }
    // A tombstone keeps its reactions and the menu; its replies bar opens the thread.
    IconButton { visible: !!bar.row && !bar.row.inThread && !bar.row.tombstone && !bar.row.members; app: bar.app; size: bar.t.sp(30); icon: "󰍪"; tip: bar.app.tr("Reply in thread", "Responder na conversa"); onClicked: bar.ws.openThread(bar.row.conv, bar.msg.threadTs || bar.msg.ts) }
    IconButton { visible: !!bar.row && !bar.row.tombstone && !bar.row.members; app: bar.app; size: bar.t.sp(30); icon: "󰒖"; tip: bar.app.tr("Forward message", "Encaminhar mensagem"); onClicked: bar.win.dialog("forward", { conv: bar.row.conv, msg: bar.msg }) }
    IconButton {
      readonly property bool saved: !!bar.ws && !!bar.msg && bar.ws.isSaved(bar.row.conv, bar.msg.ts)
      visible: !!bar.row && !bar.row.tombstone && !bar.row.members
      app: bar.app; size: bar.t.sp(30)
      icon: saved ? "󰃀" : "󰃃"
      color: saved ? bar.t.red : bar.t.fgSoft
      tip: saved ? bar.app.tr("Remove from Later", "Remover de Depois") : bar.app.tr("Save for later", "Salvar para depois")
      onClicked: bar.ws.toggleSaved(bar.row.conv, bar.msg)
    }
    IconButton { id: moreB; app: bar.app; size: bar.t.sp(30); icon: "󰇙"; tip: bar.app.tr("More actions", "Mais ações"); onClicked: { var p = moreB.mapToItem(bar.win.contentItem, 0, moreB.height + 4); bar.row.openMenu(p.x - bar.t.sp(200), p.y) } }
  }
}
