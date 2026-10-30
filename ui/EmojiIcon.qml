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

  // A GIF plays while it's in sight; any other picture is a still one,
  // decoded at a step of a short ladder (nearby sizes share it in Qt's cache).
  readonly property bool gif: /\.gif(\?|#|$)/i.test(e.src)
  readonly property int px: {
    var want = e.size * 2
    var steps = [32, 48, 64, 96]
    for (var i = 0; i < steps.length; i++) if (steps[i] >= want) return steps[i]
    return 128
  }
  readonly property int picStatus: img.item ? img.item.status : Image.Null

  Loader {
    id: img
    anchors.fill: parent
    active: e.useImage
    sourceComponent: e.gif ? gifC : stillC
  }
  Component {
    id: stillC
    Image {
      visible: status === Image.Ready
      source: e.src
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      sourceSize.width: e.px
      sourceSize.height: e.px
      smooth: true
      mipmap: true
    }
  }
  Component {
    id: gifC
    AnimatedImage {
      visible: status === Image.Ready
      source: e.src
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      playing: visible && e.app.onScreen
      smooth: true
      mipmap: true
    }
  }
  Text {
    anchors.centerIn: parent
    visible: !e.useImage || e.picStatus === Image.Error || e.picStatus === Image.Loading && !!e.res && !!e.res.glyph
    width: e.size
    text: e.res ? (e.res.glyph || "") : "?"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: e.res && e.res.glyph ? Math.round(e.size * 0.85) : Math.max(8, Math.round(e.size * 0.6))
    font.bold: !e.res
    color: e.app.theme.fgDim
    elide: Text.ElideRight
  }
}
