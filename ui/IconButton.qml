import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// A square icon button with Slack's soft hover, a tooltip and an optional
// label beside the icon.
Item {
  id: b
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  property string label: ""
  property string tip: ""
  property bool active: false
  property bool enabled2: true
  property color color: active ? t.fgBright : t.fgSoft
  property color hoverColor: t.hover
  property int size: t.sp(28)
  property int iconSize: t.fsIcon
  property int radius: t.radiusSmall
  readonly property bool hovered: ma.containsMouse
  signal clicked()
  signal rightClicked()

  implicitWidth: label ? row.implicitWidth + t.sp(14) : size
  implicitHeight: size
  opacity: enabled2 ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: b.radius
    color: ma.pressed ? b.t.press : (b.active ? b.t.hoverStrong : (ma.containsMouse ? b.hoverColor : "transparent"))
  }

  Row {
    id: row
    anchors.centerIn: parent
    // Icon only: centre the drawing, not the font's narrower advance cell.
    anchors.horizontalCenterOffset: b.label ? 0 : glyph.anchors.horizontalCenterOffset
    spacing: b.t.sp(6)
    Glyph {
      id: glyph
      app: b.app
      inkCentered: b.label === ""
      icon: b.icon
      size: b.iconSize
      color: b.color
      visible: b.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      visible: b.label !== ""
      text: b.label
      textFormat: Text.PlainText
      color: b.color
      font.family: b.t.font
      font.pixelSize: b.t.fsSmall
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    enabled: b.enabled2
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => mouse.button === Qt.RightButton ? b.rightClicked() : b.clicked()
  }

  PanelToolTip {
    visible: ma.containsMouse && b.tip !== ""
    text: b.tip
  }
}
