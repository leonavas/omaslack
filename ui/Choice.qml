import QtQuick
import "../lib/Registry.js" as Reg

// A row of options, one chosen (Slack's radio lists, flattened).
Column {
  id: c
  property var app: Reg.service
  readonly property var t: app.theme
  property var options: []      // [{value, label, hint}]
  property var value: null
  signal picked(var value)
  spacing: t.sp(4)

  Repeater {
    model: c.options
    delegate: Rectangle {
      required property var modelData
      width: c.width
      height: Math.max(c.t.sp(34), body.implicitHeight + c.t.sp(14))
      radius: Math.max(4, c.t.radiusSmall)
      color: ma.containsMouse ? c.t.hover : "transparent"
      border.width: c.value === modelData.value ? 1 : 0
      border.color: c.t.alpha(c.t.accent, 0.6)
      Rectangle {
        id: dot
        x: c.t.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        width: c.t.sp(16); height: width; radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: c.value === modelData.value ? c.t.accent : c.t.lineStrong
        Rectangle { anchors.centerIn: parent; width: parent.width - 8; height: width; radius: width / 2; color: c.t.accent; visible: c.value === modelData.value }
      }
      Column {
        id: body
        anchors.left: dot.right
        anchors.leftMargin: c.t.sp(10)
        anchors.right: parent.right
        anchors.rightMargin: c.t.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: modelData.label; color: c.t.fg; font.family: c.t.font; font.pixelSize: c.t.fsText; width: parent.width; wrapMode: Text.Wrap }
        Text { visible: !!modelData.hint; text: modelData.hint || ""; color: c.t.fgDim; font.family: c.t.font; font.pixelSize: c.t.fsSmall; width: parent.width; wrapMode: Text.Wrap }
      }
      MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { c.value = modelData.value; c.picked(modelData.value) } }
    }
  }
}
