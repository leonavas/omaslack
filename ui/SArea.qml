import QtQuick
import QtQuick.Controls
import "../lib/Registry.js" as Reg

// A multi-line input with the same look as SField.
ScrollView {
  id: s
  property var app: Reg.service
  readonly property var t: app.theme
  property alias text: area.text
  property alias placeholderText: area.placeholderText
  property alias area: area
  implicitHeight: t.sp(84)
  clip: true
  background: Rectangle {
    radius: Math.max(4, s.t.radiusSmall)
    color: s.t.alpha(s.t.bg, 0.6)
    border.width: area.activeFocus ? 2 : 1
    border.color: area.activeFocus ? s.t.accent : s.t.lineStrong
  }
  TextArea {
    id: area
    color: s.t.fg
    placeholderTextColor: s.t.fgDim
    selectionColor: s.t.alpha(s.t.accent, 0.35)
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    font.family: s.t.font
    font.pixelSize: s.t.fsText
    padding: s.t.sp(10)
    background: null
  }
}
