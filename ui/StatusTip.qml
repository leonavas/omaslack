import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import qs.Commons
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// Slack's bubble over someone's status emoji: the emoji and the status in
// bold ("⛔ Out of Office • Google Calendar": an app's status already ends
// with its name), then when it clears ("Until tomorrow, 12:00 AM"), all
// centered, with an arrow at the emoji. Declared inside the emoji, in the
// shell's tooltip colors and with its delay, like PanelToolTip. `hovered`
// is the emoji's HoverHandler; `area` a MouseArea lying over the emoji
// (a row's own), which only counts while the mouse is on the emoji.
ToolTip {
  id: tip
  property var app: Reg.service
  property var ws
  property var status: null     // Model.status
  property bool hovered: false
  property var area: null
  readonly property var t: app.theme

  readonly property bool hasEmoji: !!status && (status.emoji !== "" || status.unicode !== "" || status.url !== "")
  readonly property bool overArea: !!area && area.containsMouse && !!parent
                                   && parent.contains(parent.mapFromItem(area, area.mouseX, area.mouseY))
  property real shownAt: 0
  readonly property string until: { tip.shownAt; return status && status.exp ? U.statusUntil(status.exp, app.lang, app.clock24) : "" }

  readonly property int arrow: t.sp(6)
  readonly property int gap: t.sp(3)       // the arrow's tip to the emoji
  readonly property int edge: t.sp(8)      // kept from the window's sides
  readonly property int corner: Math.max(6, t.radiusSmall)
  readonly property var borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Color.tooltip.border, Color.tooltip.border, Style.normalBorderWidth)
  readonly property real stroke: Border.uniformWidth(borderSpec)
  readonly property color ink: Color.tooltip.text
  property bool below: false               // no room above: under the emoji, the arrow up
  property real arrowX: implicitWidth / 2  // the arrow's tip, from the bubble's left

  visible: (hovered || overArea) && !!parent && parent.visible && (hasEmoji || (!!status && status.text !== ""))
  delay: 400
  padding: 0
  topPadding: stroke + (below ? arrow : 0) + t.sp(7)
  bottomPadding: stroke + (below ? 0 : arrow) + t.sp(7)
  leftPadding: stroke + t.sp(12)
  rightPadding: stroke + t.sp(12)
  text: status ? [status.text, until].filter(function(x) { return x }).join("  ·  ") : ""

  onAboutToShow: place()
  onImplicitWidthChanged: if (opened) place()

  // Centered over the emoji (under it when the window's top is too close),
  // kept inside the window, the arrow still at the emoji.
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

  contentItem: Column {
    spacing: tip.t.sp(2)
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: tip.t.sp(5)
      EmojiIcon {
        id: face
        visible: tip.hasEmoji
        // Level with the first line when the status wraps.
        y: line.visible ? Math.max(0, Math.round((line.implicitHeight / Math.max(1, line.lineCount) - height) / 2)) : 0
        app: tip.app
        ws: tip.ws
        name: tip.status ? tip.status.emoji.replace(/:/g, "") : ""
        glyph: tip.status && tip.status.unicode ? Emoji.fromHex(tip.status.unicode) : ""
        url: tip.status ? tip.status.url : ""
        size: tip.t.px(13) + 3
      }
      Text {
        id: line
        visible: text !== ""
        width: Math.min(implicitWidth, tip.t.sp(260))
        text: tip.status ? tip.status.text : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        color: tip.ink
        font.family: tip.t.font
        font.pixelSize: tip.t.px(13)
        font.bold: true
      }
    }
    Text {
      visible: text !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      text: tip.until
      textFormat: Text.PlainText
      color: tip.t.mix(tip.ink, Color.tooltip.background, 0.35)
      font.family: tip.t.font
      font.pixelSize: tip.t.px(13)
    }
  }
}
