import QtQuick
import "../lib/Registry.js" as Reg

// "↑ Unread mentions" over the edge of a list.
Rectangle {
  id: p
  property var app: Reg.service
  readonly property var t: app.theme
  property bool mention: false
  property string text: ""
  property string arrow: "󰁝"
  property color ink: mention ? t.badgeText : t.fg
  signal clicked()
  z: 10
  height: t.sp(26)
  width: row.implicitWidth + t.sp(22)
  radius: height / 2
  color: mention ? t.badge : t.raised
  border.width: mention ? 0 : 1
  border.color: t.lineStrong
  Row {
    id: row
    anchors.centerIn: parent
    spacing: p.t.sp(6)
    Glyph { app: p.app; icon: p.arrow; size: p.t.fsSmall; color: p.ink; anchors.verticalCenter: parent.verticalCenter }
    Text { text: p.text; color: p.ink; font.family: p.t.font; font.pixelSize: p.t.fsSmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
  }
  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: p.clicked() }
}
