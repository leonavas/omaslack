import QtQuick
import "../lib/Registry.js" as Reg

// A rail button: an icon in a rounded square with its label under it. The
// square is the rail's tile (the workspaces' size and corners), centered.
Item {
  id: tab
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  property string label: ""
  property bool active: false
  property bool dot: false
  property color dotColor: t.badge
  property int count: 0
  readonly property bool hovered: ma.containsMouse
  signal clicked()
  width: t.sp(56)
  height: t.sp(52)
  anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

  Rectangle {
    id: sq
    width: tab.t.sp(36)
    height: width
    anchors.horizontalCenter: parent.horizontalCenter
    radius: Math.max(tab.t.sp(8), tab.t.radiusSmall + 2)
    color: tab.active ? tab.t.alpha(tab.t.fgBright, 0.22) : (ma.containsMouse ? tab.t.alpha(tab.t.fgBright, 0.13) : "transparent")
    Glyph {
      app: tab.app
      anchors.centerIn: parent
      icon: tab.icon
      size: tab.t.fsTitle + 3
      color: tab.t.fgBright
      scale: ma.containsMouse && !tab.active ? 1.08 : 1
      Behavior on scale { NumberAnimation { duration: 120 } }
    }
    Badge {
      app: tab.app
      count: tab.count
      visible: tab.count > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -tab.t.sp(6)
      anchors.topMargin: -tab.t.sp(5)
    }
    Rectangle {
      visible: tab.dot && tab.count === 0
      width: tab.t.sp(9); height: width; radius: width / 2
      color: tab.dotColor
      border.width: 2
      border.color: tab.t.frame
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -tab.t.sp(2)
      anchors.topMargin: -tab.t.sp(2)
    }
  }
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: sq.bottom
    anchors.topMargin: tab.t.sp(2)
    text: tab.label
    color: tab.t.fgBright
    opacity: tab.active || ma.containsMouse ? 1 : 0.85
    font.family: tab.t.font
    font.pixelSize: tab.t.fsTiny
    font.bold: true
  }
  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tab.clicked()
  }
}
