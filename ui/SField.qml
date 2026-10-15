import QtQuick
import QtQuick.Controls
import "../lib/Registry.js" as Reg

// A single-line input in Slack's style: quiet border, accent ring on focus.
TextField {
  id: f
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  color: t.fg
  placeholderTextColor: t.fgDim
  selectionColor: t.alpha(t.accent, 0.35)
  selectedTextColor: t.fgBright
  selectByMouse: true
  font.family: t.font
  font.pixelSize: t.fsText
  leftPadding: (icon ? t.sp(30) : t.sp(10))
  rightPadding: t.sp(10)
  topPadding: t.sp(8)
  bottomPadding: t.sp(8)
  background: Rectangle {
    radius: Math.max(4, f.t.radiusSmall)
    color: f.t.alpha(f.t.bg, 0.6)
    border.width: f.activeFocus ? 2 : 1
    border.color: f.activeFocus ? f.t.accent : f.t.lineStrong
    Glyph {
      app: f.app
      visible: f.icon !== ""
      icon: f.icon
      color: f.t.fgDim
      anchors.left: parent.left
      anchors.leftMargin: f.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
