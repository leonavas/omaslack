import QtQuick
import QtQuick.Controls
import "../lib/Registry.js" as Reg

// The thin rounded scrollbar Slack draws, shown on hover/scroll.
ScrollBar {
  id: sb
  property var app: Reg.service
  readonly property var t: app.theme
  policy: ScrollBar.AsNeeded
  minimumSize: 0.06
  contentItem: Rectangle {
    implicitWidth: sb.t.sp(6)
    radius: width / 2
    color: sb.pressed ? sb.t.alpha(sb.t.fg, 0.45) : sb.t.alpha(sb.t.fg, sb.hovered ? 0.35 : 0.22)
    opacity: sb.active || sb.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }
  background: null
}
