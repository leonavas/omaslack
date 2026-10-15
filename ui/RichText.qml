import QtQuick
import "../lib/Registry.js" as Reg

// Message text: Slack's rich text as HTML, selectable, links clickable.
TextEdit {
  id: rt
  property var app: Reg.service
  readonly property var t: app.theme
  property string html: ""
  property bool muted: false
  property bool jumbo: false
  property int size: t.fsText
  signal link(string url)

  text: html
  textFormat: TextEdit.RichText
  readOnly: true
  selectByMouse: true
  persistentSelection: false
  wrapMode: TextEdit.Wrap
  color: muted ? t.fgDim : t.fg
  font.family: t.font
  font.pixelSize: jumbo ? Math.round(size * 1.5) : size
  font.italic: muted
  selectionColor: t.alpha(t.accent, 0.35)
  selectedTextColor: t.fgBright
  activeFocusOnPress: false
  onLinkActivated: url => rt.link(url)

  // Links look like links; the cursor says so.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    cursorShape: rt.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
  }

  Component.onCompleted: {
    // Rich text documents take link colors from this sheet.
    if (rt.textDocument) {}
  }
}
