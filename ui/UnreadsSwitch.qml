import QtQuick
import "../lib/Registry.js" as Reg

// "Unreads" and a small switch: the header of the cards that hovering the
// rail's tabs shows (AppWindow's peek), as Slack's.
Row {
  id: us
  property var app: Reg.service
  readonly property var t: app.theme
  property bool checked: false
  property string text: app.tr("Unreads", "Não lidas")
  signal toggled()
  spacing: t.sp(6)

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: us.text
    color: us.t.fgDim
    font.family: us.t.font
    font.pixelSize: us.t.fsSmall
  }
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: us.t.sp(28); height: us.t.sp(16); radius: height / 2
    color: us.checked ? us.t.accent : us.t.lineStrong
    Behavior on color { ColorAnimation { duration: 120 } }
    Rectangle {
      width: parent.height - 4; height: width; radius: width / 2
      y: 2
      x: us.checked ? parent.width - width - 2 : 2
      color: us.checked ? us.t.onColor(us.t.accent) : us.t.fg
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; anchors.margins: -us.t.sp(4); cursorShape: Qt.PointingHandCursor; onClicked: us.toggled() }
  }
}
