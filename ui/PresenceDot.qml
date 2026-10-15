import QtQuick
import QtQuick.Shapes
import "../lib/Registry.js" as Reg

// Slack's presence dot: filled green when active, a ring when away, a
// small "z" when the person paused notifications, in a break at the dot's
// top right (the ring open there, or a bite out of the filled dot).
Item {
  id: d
  property var app: Reg.service
  readonly property var t: app.theme
  property bool active: false
  property bool paused: false
  property color ring: t.sidebar
  // A selected row's text color: Slack draws the dot in it instead of green
  // (filled or a ring, and the "z").
  property color ink: "transparent"
  property int size: t.sp(10)
  width: size
  height: size

  readonly property bool inked: d.ink.a > 0
  // The away ring and the "z": the ink when there's one, else the dim text
  // color, or a step from the ring toward the text when the ring is too
  // close to it.
  readonly property color dim: d.inked ? d.ink : (d.ring.a > 0 && Math.abs(d.t.luma(d.ring) - d.t.luma(d.t.fgDim)) < 0.25 ? d.t.mix(d.ring, d.t.fg, 0.6) : d.t.fgDim)
  readonly property color fill: d.inked ? d.ink : d.t.presence
  readonly property real stroke: Math.max(1.5, d.size * 0.18)

  // Paused: the ring open ~70° at its top right (1:30), the "z" in the
  // break, centered on the ring's outer edge. Active, the dot filled with
  // a round bite around the "z", clear of it.
  readonly property bool awayPaused: !d.active && d.paused
  readonly property bool activePaused: d.active && d.paused
  readonly property real zSide: Math.max(3, d.size * 0.36)
  readonly property real zStroke: Math.max(1, d.size * 0.12)
  readonly property real zx: d.size / 2 + d.size / 2 * Math.SQRT1_2
  readonly property real zy: d.size / 2 - d.size / 2 * Math.SQRT1_2
  readonly property real bite: d.zSide * Math.SQRT1_2 + d.zStroke / 2 + Math.max(0.6, d.size * 0.06)
  // Half the bite's opening on the dot's edge, in degrees.
  readonly property real biteHalf: Math.acos(1 - d.bite * d.bite / (d.size * d.size / 2)) * 180 / Math.PI

  Rectangle {
    anchors.centerIn: parent
    width: d.size + 4
    height: width
    radius: width / 2
    color: d.ring
    visible: d.ring.a > 0
  }
  // The "z" pokes past the ring's cut-out: its own, under the ring.
  Rectangle {
    visible: d.paused && d.ring.a > 0
    width: d.zSide * Math.SQRT2 + d.zStroke + 2
    height: width
    radius: width / 2
    x: d.zx - width / 2
    y: d.zy - height / 2
    color: d.ring
  }
  Rectangle {
    visible: !d.paused
    anchors.centerIn: parent
    width: d.size
    height: d.size
    radius: d.size / 2
    color: d.active ? d.fill : "transparent"
    border.width: d.active ? 0 : d.stroke
    border.color: d.dim
  }
  Shape {
    visible: d.awayPaused
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: d.dim
      strokeWidth: d.stroke
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        moveToStart: true
        centerX: d.size / 2
        centerY: d.size / 2
        radiusX: (d.size - d.stroke) / 2
        radiusY: radiusX
        startAngle: -10
        sweepAngle: 290
      }
    }
  }
  Shape {
    visible: d.activePaused
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      fillColor: d.fill
      PathAngleArc {
        moveToStart: true
        centerX: d.size / 2
        centerY: d.size / 2
        radiusX: d.size / 2
        radiusY: radiusX
        startAngle: -45 + d.biteHalf
        sweepAngle: 360 - 2 * d.biteHalf
      }
      PathArc {
        x: d.size / 2 + d.size / 2 * Math.cos((-45 + d.biteHalf) * Math.PI / 180)
        y: d.size / 2 + d.size / 2 * Math.sin((-45 + d.biteHalf) * Math.PI / 180)
        radiusX: d.bite
        radiusY: d.bite
        direction: PathArc.Counterclockwise
      }
    }
  }
  Shape {
    visible: d.paused
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: d.active ? d.fill : d.dim
      strokeWidth: d.zStroke
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.BevelJoin
      startX: d.zx - d.zSide / 2
      startY: d.zy - d.zSide / 2
      PathLine { x: d.zx + d.zSide / 2; y: d.zy - d.zSide / 2 }
      PathLine { x: d.zx - d.zSide / 2; y: d.zy + d.zSide / 2 }
      PathLine { x: d.zx + d.zSide / 2; y: d.zy + d.zSide / 2 }
    }
  }
}
