import QtQuick
import "../lib/Registry.js" as Reg

// A count pill (mentions: red; Slack blue for new thread replies).
Rectangle {
  id: b
  property var app: Reg.service
  readonly property var t: app.theme
  property int count: 0
  property string text: count > 99 ? "99+" : String(count)
  property color fill: t.badge
  property color ink: t.onColor(fill)
  visible: count > 0 || (text !== "" && text !== "0")
  implicitHeight: t.sp(18)
  implicitWidth: Math.max(implicitHeight, label.implicitWidth + t.sp(12))
  radius: height / 2
  color: fill
  Text {
    id: label
    anchors.centerIn: parent
    text: b.text
    color: b.ink
    font.family: b.t.font
    font.pixelSize: b.t.fsTiny
    font.bold: true
  }
}
