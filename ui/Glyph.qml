import QtQuick
import "../lib/Registry.js" as Reg

// A Nerd Font icon in the theme's family. `inkCentered`: centre the drawing,
// not the cell. Nerd Font icons advance one cell but are drawn up to twice
// as wide, spilling to the right, so a centred cell leaves the icon off to
// the right of its button.
Text {
  id: g
  property var app: Reg.service
  property string icon: ""
  property int size: app ? app.theme.fsIcon : 15
  property bool inkCentered: false
  TextMetrics { id: ink; font: g.font; text: g.inkCentered ? g.icon : "" }
  anchors.horizontalCenterOffset: inkCentered ? Math.round(ink.advanceWidth / 2 - ink.tightBoundingRect.x - ink.tightBoundingRect.width / 2) : 0
  text: icon
  color: app ? app.theme.fg : "white"
  font.family: app ? app.theme.font : "monospace"
  font.pixelSize: size
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  textFormat: Text.PlainText
}
