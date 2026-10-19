import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import qs.Commons
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Slack's tooltip bubble: centered over the item it's declared in (under it
// when the window's top is too close), kept inside the window, with an
// arrow at the item. In the shell's tooltip colors and with its delay, like
// PanelToolTip. The content and when it shows are the user's.
ToolTip {
  id: tip
  property var app: Reg.service
  readonly property var t: app.theme

  property int padX: t.sp(12)
  property int padY: t.sp(7)
  property real shownAt: 0                 // when it last opened

  readonly property int arrow: t.sp(6)
  readonly property int gap: t.sp(3)       // the arrow's tip to the item
  readonly property int edge: t.sp(8)      // kept from the window's sides
  readonly property int corner: Math.max(6, t.radiusSmall)
  readonly property var borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Color.tooltip.border, Color.tooltip.border, Style.normalBorderWidth)
  readonly property real stroke: Border.uniformWidth(borderSpec)
  readonly property color ink: Color.tooltip.text
  readonly property color soft: t.mix(ink, Color.tooltip.background, 0.35)
  property bool below: false               // no room above: under the item, the arrow up
  property real arrowX: implicitWidth / 2  // the arrow's tip, from the bubble's left

  delay: 400
  padding: 0
  topPadding: stroke + (below ? arrow : 0) + padY
  bottomPadding: stroke + (below ? 0 : arrow) + padY
  leftPadding: stroke + padX
  rightPadding: stroke + padX

  onAboutToShow: place()
  onImplicitWidthChanged: if (opened) place()

  function place() {
    tip.shownAt = Date.now()
    var p = tip.parent, win = p ? p.Window.window : null
    if (!p || !win) return
    var at = p.mapToItem(null, 0, 0)
    var w = tip.implicitWidth, h = tip.implicitHeight
    var cx = at.x + p.width / 2
    var left = U.clamp(Math.round(cx - w / 2), tip.edge, Math.max(tip.edge, win.width - tip.edge - w))
    tip.below = at.y - h - tip.gap < tip.edge
    tip.x = left - at.x
    tip.y = tip.below ? p.height + tip.gap : -h - tip.gap
    tip.arrowX = cx - left
  }

  // The bubble and its arrow as one outline, so a border runs round both.
  function outline(w, h) {
    var s = tip.stroke / 2, a = tip.arrow
    var x0 = s, x1 = w - s
    var y0 = s + (tip.below ? a : 0), y1 = h - s - (tip.below ? 0 : a)
    var r = Math.max(0, Math.min(tip.corner, (x1 - x0) / 2 - a, (y1 - y0) / 2))
    var ax = U.clamp(tip.arrowX, x0 + r + a, x1 - r - a)
    var p = "M " + (x0 + r) + " " + y0
    if (tip.below) p += " H " + (ax - a) + " L " + ax + " " + (y0 - a) + " L " + (ax + a) + " " + y0
    p += " H " + (x1 - r) + " A " + r + " " + r + " 0 0 1 " + x1 + " " + (y0 + r)
    p += " V " + (y1 - r) + " A " + r + " " + r + " 0 0 1 " + (x1 - r) + " " + y1
    if (!tip.below) p += " H " + (ax + a) + " L " + ax + " " + (y1 + a) + " L " + (ax - a) + " " + y1
    p += " H " + (x0 + r) + " A " + r + " " + r + " 0 0 1 " + x0 + " " + (y1 - r)
    p += " V " + (y0 + r) + " A " + r + " " + r + " 0 0 1 " + (x0 + r) + " " + y0 + " Z"
    return p
  }

  background: Item {
    Shape {
      id: bubble
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: Color.tooltip.background
        strokeColor: Border.color(tip.borderSpec)
        strokeWidth: tip.stroke > 0 ? tip.stroke : -1
        joinStyle: ShapePath.MiterJoin
        PathSvg { path: tip.outline(bubble.width, bubble.height) }
      }
    }
  }
}
