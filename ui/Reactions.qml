import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// The reactions under a message: emoji and count, yours highlighted, who
// reacted on hover, and the button to add one.
Flow {
  id: rx
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  property var msg: null
  readonly property var t: app.theme
  spacing: t.sp(4)

  Repeater {
    model: rx.msg ? rx.msg.reactions : []
    delegate: Rectangle {
      id: pill
      required property var modelData
      readonly property bool mine: rx.ws && modelData.users.indexOf(rx.ws.me.id) >= 0
      height: rx.t.sp(26)
      width: pillRow.implicitWidth + rx.t.sp(14)
      radius: height / 2
      color: mine ? rx.t.alpha(rx.t.blue, 0.18) : (pma.containsMouse ? rx.t.hoverStrong : rx.t.alpha(rx.t.fg, 0.06))
      border.width: 1
      border.color: mine ? rx.t.blue : (pma.containsMouse ? rx.t.lineStrong : "transparent")
      Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: rx.t.sp(5)
        EmojiIcon { app: rx.app; ws: rx.ws; name: pill.modelData.name; size: rx.t.sp(16); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: pill.modelData.count
          color: pill.mine ? rx.t.blue : rx.t.fg
          font.family: rx.t.font
          font.pixelSize: rx.t.fsSmall
          font.bold: pill.mine
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      MouseArea {
        id: pma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rx.ws.react(rx.conv, rx.msg.ts, pill.modelData.name)
      }
      ReactionTip { app: rx.app; ws: rx.ws; reaction: pill.modelData; hovered: pma.containsMouse }
    }
  }

  Rectangle {
    height: rx.t.sp(26)
    width: rx.t.sp(34)
    radius: height / 2
    color: ama.containsMouse ? rx.t.hoverStrong : rx.t.alpha(rx.t.fg, 0.06)
    Glyph { app: rx.app; anchors.centerIn: parent; icon: "󰇵"; size: rx.t.fsIcon - 1; color: rx.t.fgSoft }
    MouseArea {
      id: ama
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rx.win.emojiPicker(parent, function(name) { rx.ws.react(rx.conv, rx.msg.ts, name) }, {})
    }
    PanelToolTip { visible: ama.containsMouse; text: rx.app.tr("Add reaction", "Adicionar reação") }
  }
}
