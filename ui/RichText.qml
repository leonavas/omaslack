import QtQuick
import "../lib/Mrkdwn.js" as Md
import "../lib/Emoji.js" as Emoji
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
  selectByKeyboard: true         // Shift+arrows grow a selection made with the mouse
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

  // A click leaves the keyboard where it was (the message box); text
  // selected with the mouse takes it, so Ctrl+C, Ctrl+A and Shift+arrows
  // reach the selection (which clears once the keyboard moves on).
  onSelectedTextChanged: if (rt.selectedText !== "" && !rt.activeFocus) rt.forceActiveFocus()

  // Typing goes on in the message box, as in Slack: on the ShortcutOverride
  // Qt sends before the press itself, so the press lands in the box and
  // nothing typed is lost (`typing`, `toComposer`).
  Keys.onShortcutOverride: event => { if (rt.typing(event)) rt.toComposer() }

  // Ctrl+C: the selection as plain text (copySelection). ↑ / ↓ stop at the
  // text's first and last lines: past them the list around it would take
  // them and jump to its current row; plain, they give the keyboard back to
  // the box (a next ↑ there selects messages).
  Keys.onPressed: event => {
    var k = event.key
    if (event.matches(StandardKey.Copy)) {
      if (rt.selectedText !== "") { rt.copySelection(); event.accepted = true }
      return
    }
    if (rt.typing(event)) { rt.toComposer(); return }
    if (k !== Qt.Key_Up && k !== Qt.Key_Down) return
    var y = rt.positionToRectangle(rt.cursorPosition).y
    var edge = k === Qt.Key_Up ? y <= rt.positionToRectangle(0).y : y >= rt.positionToRectangle(rt.length).y
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) event.accepted = true
    else if (edge) { if (!(event.modifiers & Qt.ShiftModifier)) rt.toComposer(); event.accepted = true }
  }

  // A key that types (Shift at most): a character, Backspace, Enter, Esc.
  function typing(event) {
    if (!rt.activeFocus || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return false
    var k = event.key
    if (k === Qt.Key_Backspace || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape) return true
    var c = event.text.length ? event.text.charCodeAt(0) : 0
    return c >= 32 && c !== 127
  }

  // The keyboard back to the box of the conversation or thread this text
  // is in (their focusComposer; dialogs and search have none, and keep it),
  // the selection let go.
  function toComposer() {
    for (var p = rt.parent; p; p = p.parent) {
      if (typeof p.focusComposer !== "function") continue
      p.focusComposer()
      if (!rt.activeFocus) rt.deselect()
      return
    }
  }

  // Slack's copy: plain text, emoji as their characters or :name: (each
  // picture's alt, Mrkdwn), lines as lines, pills without their room.
  function copySelection() {
    var a = rt.selectionStart, s = rt.selectedText, out = ""
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i)
      if (c === "￼") {
        var alt = /<img\b[^>]*\salt="([^"]*)"/i.exec(rt.getFormattedText(a + i, a + i + 1))
        if (alt) out += Md.unescape(alt[1].replace(/&quot;/g, "\""))
      }
      else if (c === "\u2029" || c === "\u2028") out += "\n"
      else if (c === "\u00a0") { if (!rt.pillRoom(a + i)) out += " " }
      else out += c
    }
    rt.app.copy(out)
  }

  // The room at a pill's or inline code's ends (Md.pill, Md.codeSpan): in
  // their word spacing, the no-break space that ends a run of them.
  function pillRoom(p) {
    function spaced(q) { return /word-spacing:/.test(rt.getFormattedText(q, q + 1)) }
    return spaced(p) && !(rt.getText(p + 1, p + 2) === "\u00a0" && spaced(p + 1))
  }

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
    cursorShape: rt.hoveredLink || rt.emojiHover ? Qt.PointingHandCursor : Qt.IBeamCursor
  }

  // An emoji under the mouse: Slack's bubble with its :name: (EmojiTip);
  // a click copies it (a standard one as its character, a workspace's as
  // :name:, which Slack draws wherever it's pasted).
  // The text's picture (U+FFFC) under the point, its alt the name (a
  // custom one's ":name:", a standard one's character) and its picture
  // the html's (a GIF's in the text is a see-through stand-in).
  property var emojiHover: null      // {name, src, x, y, w, h}
  HoverHandler {
    id: emojiHov
    onPointChanged: rt.hoverEmoji(emojiHov.point.position)
    onHoveredChanged: if (!emojiHov.hovered) rt.emojiHover = null
  }
  function hoverEmoji(p) {
    var hit = null
    var at = rt.positionAt(p.x, p.y)
    for (var c = Math.max(0, at - 1); c <= at && !hit; c++) {
      if (rt.getText(c, c + 1) !== "\ufffc") continue
      var r = rt.positionToRectangle(c), n = rt.positionToRectangle(c + 1)
      var w = n.y === r.y && n.x > r.x ? n.x - r.x : rt.t.emojiPx
      if (p.x < r.x || p.x > r.x + w || p.y < r.y || p.y > r.y + r.height) continue
      var tag = /<img\b[^>]*>/i.exec(rt.getFormattedText(c, c + 1))
      if (!tag) continue
      var alt = (/\balt="([^"]*)"/i.exec(tag[0]) || [])[1] || ""
      var src = (/\bsrc="([^"]*)"/i.exec(tag[0]) || [])[1] || ""
      alt = Md.unescape(alt.replace(/&quot;/g, "\""))
      var name = /^:.+:$/.test(alt) ? alt.slice(1, -1) : Emoji.shortcodeOf(alt)
      if (!name) continue
      if (src.indexOf("blank.png") >= 0) {
        var m = new RegExp("<img\\b[^>]*\\balt=\"" + alt.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\"[^>]*>", "i").exec(rt.html)
        var real = m ? (/\bsrc="([^"]*)"/i.exec(m[0]) || [])[1] : ""
        if (real) src = real
      }
      hit = { name: name, glyph: /^:.+:$/.test(alt) ? "" : alt, src: src.replace(/&amp;/g, "&"), x: r.x, y: r.y, w: w, h: r.height }
    }
    if (!hit) { rt.emojiHover = null; return }
    var o = rt.emojiHover
    if (!o || o.name !== hit.name || o.x !== hit.x || o.y !== hit.y) rt.emojiHover = hit
  }
  TapHandler {
    enabled: !!rt.emojiHover
    acceptedButtons: Qt.LeftButton
    onTapped: {
      var e = rt.emojiHover
      if (!e) return
      var text = e.glyph || ":" + e.name + ":"
      rt.app.copy(text)
      if (rt.app.current) rt.app.current.say(rt.app.tr("Copied ", "Copiado ") + text)
    }
  }
  Item {
    id: emojiSpot
    x: rt.emojiHover ? rt.emojiHover.x : 0
    y: rt.emojiHover ? rt.emojiHover.y : 0
    width: rt.emojiHover ? rt.emojiHover.w : 0
    height: rt.emojiHover ? rt.emojiHover.h : 0
    EmojiTip {
      app: rt.app
      name: rt.emojiHover ? rt.emojiHover.name : ""
      src: rt.emojiHover ? rt.emojiHover.src : ""
      hovered: !!rt.emojiHover
    }
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
