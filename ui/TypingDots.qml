import QtQuick
import "../lib/Registry.js" as Reg

// Slack's "someone is typing" dots, a wave.
Row {
  id: d
  property var app: Reg.service
  readonly property var t: app.theme
  property color color: t.fg
  property int dot: t.sp(4)
  spacing: Math.max(2, dot * 0.6)
  property int step: 0
  Timer { interval: 220; running: d.visible && d.app.onScreen; repeat: true; onTriggered: d.step = (d.step + 1) % 4 }
  Repeater {
    model: 3
    delegate: Rectangle {
      required property int index
      width: d.dot; height: d.dot; radius: d.dot / 2
      color: d.color
      opacity: d.step === index ? 1 : (d.step === (index + 1) % 4 ? 0.6 : 0.3)
      y: d.step === index ? -1 : 0
    }
  }
}
