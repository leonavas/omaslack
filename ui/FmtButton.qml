import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// A small square button in the message box's bars. `active`: the format is
// on at the cursor (Slack lights it up); `dim`: not available there (marks
// in a code block); `underlined`: on, the way Slack shows its "Aa" (a line
// under the icon, no fill). `tone`: the icon at rest.
Rectangle {
  id: b
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  property string tip: ""
  property bool active: false
  property bool dim: false
  property bool underlined: false
  property int iconSize: t.fsIcon + 3
  property color tone: t.fgDim
  signal clicked()
  width: t.sp(28)
  height: t.sp(28)
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  radius: Math.max(4, t.radiusSmall)
  color: dim ? "transparent" : (ma.pressed ? t.press : (active ? t.hoverStrong : (ma.containsMouse ? t.hover : "transparent")))
  Glyph { id: g; app: b.app; anchors.centerIn: parent; inkCentered: true; icon: b.icon; size: b.iconSize; color: b.dim ? b.t.alpha(b.t.fgDim, 0.3) : (ma.containsMouse || b.active ? b.t.fgBright : b.tone) }
  Rectangle {
    visible: b.underlined
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(b.height / 2 + b.iconSize * 0.46)
    width: Math.round(b.iconSize * 0.8)
    height: Math.max(1, b.t.sp(1))
    color: g.color
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: b.dim ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: if (!b.dim) b.clicked() }
  PanelToolTip { visible: ma.containsMouse && b.tip !== ""; text: b.tip }
}
