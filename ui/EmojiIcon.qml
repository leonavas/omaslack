import QtQuick
import "../lib/Emoji.js" as E
import "../lib/Registry.js" as Reg

// One emoji by Slack name ("+1::skin-tone-3", "partyparrot"): Slack's
// picture of a standard one, the workspace's image (animated GIFs play) of
// a custom one, or the name itself when neither is known. `url` is a
// picture to fall back on (a status emoji from another workspace).
Item {
  id: e
  property var app: Reg.service
  property var ws
  property string name: ""
  property string glyph: ""
  property string url: ""
  property int size: app.theme.sp(18)
  width: size
  height: size

  readonly property var res: {
    if (e.glyph) return { glyph: e.glyph }
    var found = null
    if (!e.ws) found = E.resolve(e.name, null, null)
    else { e.ws.emojiRev; found = E.resolve(e.name, e.ws.customEmoji, e.ws.emojiAliases) }
    return found || (e.url ? { url: e.url } : null)
  }
  readonly property bool useImage: !!res && (!!res.url || e.app.slackEmoji)
  readonly property string src: !res ? "" : (res.url ? res.url : E.imageUrl(E.known(res.glyph) || res.glyph))

  AnimatedImage {
    id: img
    anchors.fill: parent
    visible: e.useImage && status === Image.Ready
    source: e.useImage ? e.src : ""
    asynchronous: true
    fillMode: Image.PreserveAspectFit
    playing: visible
    smooth: true
    mipmap: true
  }
  Text {
    anchors.centerIn: parent
    visible: !e.useImage || img.status === Image.Error || img.status === Image.Loading && !!e.res && !!e.res.glyph
    width: e.size
    text: e.res ? (e.res.glyph || "") : "?"
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: e.res && e.res.glyph ? Math.round(e.size * 0.85) : Math.max(8, Math.round(e.size * 0.6))
    font.bold: !e.res
    color: e.app.theme.fgDim
    elide: Text.ElideRight
  }
}
