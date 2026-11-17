import QtQuick
import "../lib/Registry.js" as Reg

// A Block Kit select or picker box (BlockControl): [icon] value-or-hint ⌄.
Rectangle {
  id: box
  property var app: Reg.service
  readonly property var t: app.theme
  property real fill: 0
  function label(html, color) { return "<span style=\"color:" + color + ";\">" + html + "</span>" }
  property string html: ""
  property bool hint: false
  property string icon: ""
  property bool chevron: true
  property real minW: box.t.sp(150)
  property real maxW: box.t.sp(260)
  signal hit()
  implicitHeight: box.t.sp(30)
  implicitWidth: box.fill > 0 ? box.fill : Math.min(maxW, Math.max(minW, boxRow.implicitWidth + box.t.sp(20)))
  radius: Math.max(4, box.t.radiusSmall)
  color: boxMa.containsMouse ? box.t.hover : box.t.alpha(box.t.bg, 0.4)
  border.width: 1
  border.color: box.t.lineStrong
  Row {
    id: boxRow
    x: box.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: box.t.sp(6)
    Glyph { visible: box.icon !== ""; app: box.app; anchors.verticalCenter: parent.verticalCenter; icon: box.icon; size: box.t.fsSmall; color: box.t.fgSoft }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, box.width - box.t.sp(20) - (box.icon !== "" ? box.t.sp(20) : 0) - (box.chevron ? box.t.sp(20) : 0))
      text: box.label(box.html, box.t.hex(box.hint ? box.t.fgDim : box.t.fg))
      textFormat: Text.RichText
      elide: Text.ElideRight
      font.family: box.t.font
      font.pixelSize: box.t.fsSmall
    }
  }
  Glyph { visible: box.chevron; app: box.app; anchors.right: parent.right; anchors.rightMargin: box.t.sp(10); anchors.verticalCenter: parent.verticalCenter; icon: "󰅀"; size: box.t.fsSmall; color: box.t.fgSoft }
  MouseArea { id: boxMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: box.hit() }
}
