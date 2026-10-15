import QtQuick
import "../lib/Registry.js" as Reg

// A tab under the conversation's name, underlined when active.
Item {
  id: tab
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  property string label: ""
  property bool active: false
  signal clicked()
  height: parent ? parent.height : t.sp(34)
  width: row.implicitWidth + t.sp(16)
  Rectangle {
    anchors.fill: parent
    anchors.bottomMargin: tab.t.sp(4)
    anchors.topMargin: tab.t.sp(2)
    radius: Math.max(4, tab.t.radiusSmall)
    color: ma.containsMouse ? tab.t.hover : "transparent"
  }
  Row {
    id: row
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -tab.t.sp(1)
    spacing: tab.t.sp(6)
    Glyph { app: tab.app; icon: tab.icon; size: tab.t.fsSmall + 1; color: tab.active ? tab.t.fgBright : tab.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
    Text {
      visible: tab.label !== ""
      text: tab.label
      textFormat: Text.PlainText
      color: tab.active ? tab.t.fgBright : tab.t.fgDim
      font.family: tab.t.font
      font.pixelSize: tab.t.fsSmall + 1
      font.bold: tab.active
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  Rectangle {
    visible: tab.active
    anchors.bottom: parent.bottom
    width: parent.width
    height: 2
    radius: 1
    color: tab.t.accent
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.clicked() }
}
