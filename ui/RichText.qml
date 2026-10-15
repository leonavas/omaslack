import QtQuick
import "../lib/Mrkdwn.js" as Md
import "../lib/Registry.js" as Reg

// Message text: Slack's rich text as HTML, selectable, links clickable.
// Animated emoji play over the text (`gifs`): rich text only draws a GIF's
// first frame.
TextEdit {
  id: rt
  property var app: Reg.service
  readonly property var t: app.theme
  property string html: ""
  property bool muted: false
  property bool jumbo: false
  property int size: t.fsText
  signal link(string url)

  // The html as drawn: each GIF a see-through picture of its size that
  // holds its place (Md.animated); null without GIFs, the html as it is.
  readonly property var drawn: rt.html.indexOf(".gif") < 0 ? null : Md.animated(rt.html, String(Qt.resolvedUrl("../assets/blank.png")))
  property var gifs: []          // the GIFs playing over the text: [{url, px, x, y}]
  property var _at: null         // where the html's pictures are in the text (U+FFFC)
  property bool _still: false    // the pictures didn't add up: the GIFs stay as the text draws them
  // The list the text scrolls in (found once it has GIFs) and the text's
  // top in it: GIFs out of sight don't play.
  property Item _view: null
  readonly property real _top: {
    var v = rt._view
    if (!v) return 0
    v.contentY; v.originY; v.contentHeight; v.height
    return rt.mapToItem(v, 0, 0).y
  }

  text: rt.drawn && !rt._still ? rt.drawn.html : rt.html
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

  onHtmlChanged: rt._still = false
  onTextChanged: if (rt.drawn || rt.gifs.length) { rt._at = null; Qt.callLater(rt.place) }
  onWidthChanged: if (rt.drawn || rt.gifs.length) Qt.callLater(rt.place)
  onFontChanged: if (rt.drawn || rt.gifs.length) Qt.callLater(rt.place)
  onContentSizeChanged: if (rt.drawn || rt.gifs.length) Qt.callLater(rt.place)

  // Where the GIFs play: the html's n-th picture is the text's n-th U+FFFC
  // (when the text has some of its own, the pictures are told apart by
  // their html; when they still don't add up, the GIFs stay still, as
  // before). A GIF keeps its player while the text moves it.
  function place() {
    var d = rt._still ? null : rt.drawn
    if (!d) { if (rt.gifs.length) rt.gifs = []; return }
    if (!rt._at) {
      var s = rt.getText(0, rt.length), at = []
      for (var i = s.indexOf("￼"); i >= 0; i = s.indexOf("￼", i + 1)) at.push(i)
      if (at.length !== d.count) at = at.filter(function(p) { return /<img\b/i.test(rt.getFormattedText(p, p + 1)) })
      if (at.length !== d.count) { rt.gifs = []; rt._still = true; return }
      rt._at = at
    }
    if (!rt._view) rt._view = rt.findView()
    rt.gifs = d.gifs.map(function(g) {
      var r = rt.positionToRectangle(rt._at[g.n])
      return { url: g.url, px: g.px || rt.t.emojiPx, x: Math.round(r.x), y: r.y }
    })
  }

  // The nearest Flickable up the tree (the message list, a pane, a dialog).
  function findView() {
    for (var p = rt.parent; p; p = p.parent)
      if (p.contentY !== undefined && p.flicking !== undefined) return p
    return null
  }

  // Links look like links; the cursor says so.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    cursorShape: rt.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
  }

  // Animated emoji, on the see-through picture that holds their place,
  // under the text (a selection still tints them). They sit on the line's
  // baseline as the text's pictures do: at its top, unless the font rises
  // higher than the picture. Only the ones in sight play.
  Repeater {
    model: rt.gifs.length
    delegate: AnimatedImage {
      required property int index
      readonly property var g: rt.gifs[index] || null
      readonly property bool inView: !rt._view || (rt._top + y + height > 0 && rt._top + y < rt._view.height)
      FontMetrics { id: fm; font: rt.font }
      z: -0.5
      x: g ? g.x : 0
      y: g ? Math.round(g.y + Math.max(0, fm.ascent - g.px)) : 0
      width: g ? g.px : 0
      height: width
      source: g ? g.url : ""
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      playing: visible && inView
      smooth: true
      mipmap: true
    }
  }

  Component.onCompleted: {
    // Rich text documents take link colors from this sheet.
    if (rt.textDocument) {}
    if (rt.drawn) Qt.callLater(rt.place)
  }
}
