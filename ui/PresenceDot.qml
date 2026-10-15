import QtQuick
import "../lib/Registry.js" as Reg

// Slack's presence dot: filled green when active, a ring when away, a
// small "z" when the person paused notifications.
Item {
  id: d
  property var app: Reg.service
  readonly property var t: app.theme
  property bool active: false
  property bool paused: false
  property color ring: t.sidebar
  property int size: t.sp(10)
  width: size
  height: size

  // The away ring and the "z": the dim text color, or a step from the ring
  // toward the text when the ring is too close to it (a selected row).
  readonly property color dim: d.ring.a > 0 && Math.abs(d.t.luma(d.ring) - d.t.luma(d.t.fgDim)) < 0.25 ? d.t.mix(d.ring, d.t.fg, 0.6) : d.t.fgDim

  Rectangle {
    anchors.centerIn: parent
    width: d.size + 4
    height: width
    radius: width / 2
    color: d.ring
    visible: d.ring.a > 0
  }
  Rectangle {
    anchors.centerIn: parent
    width: d.size
    height: d.size
    radius: d.size / 2
    color: d.active ? d.t.presence : "transparent"
    border.width: d.active ? 0 : Math.max(1.5, d.size * 0.18)
    border.color: d.dim
  }
  Text {
    visible: d.paused
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -0.5
    text: "z"
    font.pixelSize: Math.max(7, d.size * 0.8)
    font.bold: true
    font.family: d.t.font
    color: d.active ? d.t.onColor(d.t.presence) : d.dim
  }
}
