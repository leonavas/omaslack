import QtQuick
import "../lib/Registry.js" as Reg

// A Nerd Font icon in the theme's family.
Text {
  id: g
  property var app: Reg.service
  property string icon: ""
  property int size: app ? app.theme.fsIcon : 15
  text: icon
  color: app ? app.theme.fg : "white"
  font.family: app ? app.theme.font : "monospace"
  font.pixelSize: size
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  textFormat: Text.PlainText
}
