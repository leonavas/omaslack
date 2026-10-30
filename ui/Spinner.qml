import QtQuick
import QtQuick.Shapes
import "../lib/Registry.js" as Reg

// A busy ring: a faint track and a quarter of it going round.
Item {
  id: s
  property var app: Reg.service
  property int size: app.theme.sp(14)
  property color color: app.theme.fgDim
  property real stroke: Math.max(1.5, size / 8)
  width: size
  height: size

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.rgba(s.color.r, s.color.g, s.color.b, 0.25)
      strokeWidth: s.stroke
      fillColor: "transparent"
      PathAngleArc { centerX: s.size / 2; centerY: s.size / 2; radiusX: (s.size - s.stroke) / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
    }
  }
  Shape {
    id: arc
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: s.color
      strokeWidth: s.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: s.size / 2; centerY: s.size / 2; radiusX: (s.size - s.stroke) / 2; radiusY: radiusX; startAngle: -90; sweepAngle: 100 }
    }
    RotationAnimator on rotation { running: s.visible && s.opacity > 0 && s.app.onScreen; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
  }
}
