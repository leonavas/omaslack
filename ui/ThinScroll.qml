import QtQuick
import QtQuick.Controls
import "../lib/Registry.js" as Reg

// The thin rounded scrollbar Slack draws, shown while scrolling and while
// the mouse is over its list (a passive HoverHandler put on the list, so
// nothing in it loses the hover).
ScrollBar {
  id: sb
  property var app: Reg.service
  readonly property var t: app.theme
  property var lane: null
  readonly property bool laneHovered: !!sb.lane && sb.lane.hovered
  function attach() {
    if (sb.lane || !sb.parent) return
    sb.lane = Qt.createQmlObject("import QtQuick; HoverHandler {}", sb.parent, "ThinScrollLane")
  }
  onParentChanged: attach()
  Component.onCompleted: attach()
  policy: ScrollBar.AsNeeded
  minimumSize: 0.06
  contentItem: Rectangle {
    implicitWidth: sb.t.sp(6)
    radius: width / 2
    color: sb.pressed ? sb.t.alpha(sb.t.fg, 0.45) : sb.t.alpha(sb.t.fg, sb.hovered ? 0.35 : 0.22)
    opacity: sb.active || sb.hovered || sb.laneHovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }
  background: null
}
