import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// A small square button in the message box's bars. `active`: the format is
// on at the cursor (Slack lights it up); `dim`: not available there (marks
// in a code block).
Rectangle {
  id: b
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  property string tip: ""
  property bool active: false
  property bool dim: false
  signal clicked()
  width: t.sp(28)
  height: t.sp(28)
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  radius: Math.max(4, t.radiusSmall)
  color: dim ? "transparent" : (ma.pressed ? t.press : (active ? t.hoverStrong : (ma.containsMouse ? t.hover : "transparent")))
  Glyph { app: b.app; anchors.centerIn: parent; icon: b.icon; size: b.t.fsIcon - 1; color: b.dim ? b.t.alpha(b.t.fgDim, 0.4) : (ma.containsMouse || b.active ? b.t.fgBright : b.t.fgDim) }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: b.dim ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: if (!b.dim) b.clicked() }
  PanelToolTip { visible: ma.containsMouse && b.tip !== ""; text: b.tip }
}
