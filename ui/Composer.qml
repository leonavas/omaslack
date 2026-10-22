import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import "../lib/Util.js" as U
import "../lib/RichDoc.js" as RD
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// Slack's message box: the formatting bar, the text drawn the way it will
// look (Slack's WYSIWYG box: bold, italic, strike, code, code blocks,
// quotes, lists, links, emoji pictures, mention pills, and its markdown
// turning into formatting as you type), autocomplete for :emoji:, @people,
// #channels and /commands, files and pasted images, and the send button.
// The same box edits a message in place (`editTs`), and writes a note
// that someone else sends (`note`: Forward's; no drafts, files or send
// button, Enter is `submitted`).
//
// The text is a document (lib/RichDoc.js) the TextEdit only shows: what Qt
// types, deletes or pastes is read back as a change of the plain text and
// applied to the document, which is then drawn again; formatting, pills and
// emoji only ever change the document. It goes out the way Slack's client
// sends it: a rich_text block, with the markup as `text`.
Rectangle {
  id: box
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  property string threadTs: ""
  property string editTs: ""
  property string initialText: ""
  property string placeholder: ""
  readonly property var t: app.theme
  readonly property bool editing: editTs !== ""
  property bool broadcast: false
  property bool showFormatting: app.setting("composerToolbar", true) !== false
  property var files: []         // [{path, name, size, mime, preview}]
  property Item messageList: null // the messages above: ↑ in the empty box selects them (MessageList)
  property bool note: false
  signal done()
  signal submitted()

  // The document, and what the editor shows of it.
  property var doc: RD.empty()
  property var typing: null      // {pos, f}: marks for what's typed next (B / I… with nothing selected)
  property var marks: ({ b: false, i: false, u: false, x: false, c: false, link: "", k: "p", n: 0 })
  property string acText: ""     // the text with pills masked, for the autocomplete
  property bool hasText: false
  property var decos: []         // quote bars and code boxes: [{k, y, h}]
  property var gifs: []          // animated emoji playing over the text: [{key, url, x, y}]
  property var undos: []
  property var redos: []
  property var _clip: null       // the last copy out of the box: {text, lines}
  property string _editBase: ""
  property var _before: null     // editing: what had the keyboard before, which gets it back after
  property string _draftFor: ""
  property bool _rendering: false
  property bool _dirty: false
  property int _cursor: 0
  property int _anchor: 0
  property int _lastPos: 0
  property double _undoAt: 0

  readonly property var c: ws ? ws.conv(conv) : null
  readonly property string sendLabel: editing ? app.tr("Save", "Salvar") : app.tr("Send now", "Enviar agora")
  // Colors and sizes the drawn text depends on (theme switch, zoom).
  readonly property var look: [t.html, t.emojiPx, t.sp(8)]
  onLookChanged: if (!box._rendering) { if (box._dirty) box.flush(); else box.render(input.cursorPosition, box.anchorPos()) }

  implicitHeight: col.implicitHeight + 2
  radius: t.sp(8)
  color: t.alpha(t.fg, 0.02)
  border.width: 1
  border.color: input.activeFocus ? t.alpha(t.fg, 0.3) : t.lineStrong

  function focusInput() { input.forceActiveFocus() }
  // Box markup (Slack's markup with its wire references) into the box.
  function setText(s) { box.load(RD.fromMarkup(s, box.dctx())) }

  Component.onCompleted: {
    if (box.editing) {
      box.loadEdit()
      Qt.callLater(function() { var w = box.Window.window; box._before = w ? w.activeFocusItem : null; input.forceActiveFocus(); input.cursorPosition = input.length })
    }
    else if (!box.note) box.restoreDraft()
  }
  Component.onDestruction: box.saveDraftNow()
  onConvChanged: if (!box.editing && !box.note) { box.saveDraftNow(); box.restoreDraft() }
  onThreadTsChanged: if (!box.editing && !box.note) { box.saveDraftNow(); box.restoreDraft() }

  // ---------------------------------------------------------------- the workspace
  function dctx() {
    return {
      user: function(id) { return box.ws ? box.ws.userName(id) : "" },
      conv: function(id) { return box.ws ? box.ws.convLabel(id) : "" },
      emoji: function(name, tone) { return box.emojiFor(name, tone) }
    }
  }

  // An emoji's picture as the app draws it elsewhere: Slack's image of a
  // standard one (or the system glyph when set so), the workspace's own.
  // Animated ones play over the text (`gifs`).
  function emojiFor(name, tone) {
    if (!box.ws) return null
    var r = Emoji.resolve(tone ? name + "::skin-tone-" + tone : name, box.ws.customEmoji, box.ws.emojiAliases)
    if (!r) return null
    if (r.url) return { url: r.url }
    if (box.app.slackEmoji) return { url: Emoji.imageUrl(Emoji.known(r.glyph) || r.glyph) }
    return { glyph: r.glyph }
  }

  function rctx() {
    return { c: box.t.html, mono: "monospace", emojiPx: box.t.emojiPx, me: box.ws && box.ws.me ? box.ws.me.id : "",
             quotePad: box.t.sp(14), codePad: box.t.sp(8), gap: box.t.sp(4), blank: String(Qt.resolvedUrl("../assets/blank.png")) }
  }

  // @here / #channel typed by hand become Slack's references on the way out.
  function findRef(sigil, name) {
    if (sigil === "@") return ["here", "channel", "everyone"].indexOf(name) >= 0 ? { k: "broadcast", id: name, label: "@" + name } : null
    if (!box.ws || !/^[a-z0-9_\-]+$/.test(name)) return null
    for (var id in box.ws.convs) {
      var cc = box.ws.convs[id]
      if ((cc.kind === "channel" || cc.kind === "private") && cc.name === name) return { k: "channel", id: id, label: "#" + name }
    }
    var d = (box.ws.directory.chans || []).filter(function(x) { return x.name === name })[0]
    return d ? { k: "channel", id: d.id, label: "#" + name } : null
  }
  function outgoing() { return RD.refs(box.doc, box.findRef) }

  // ---------------------------------------------------------------- loading
  function load(d, pos) {
    box.doc = d || RD.empty()
    box.typing = null
    box.undos = []
    box.redos = []
    box.render(pos === undefined ? RD.size(box.doc) : pos)
  }

  // The message being edited, from its rich_text (or its mrkdwn).
  function loadEdit() {
    var m = box.ws ? box.ws.findAny(box.conv, box.editTs) : null
    var ctx = box.dctx()
    var d = m ? RD.fromBlocks(m.blocks, ctx) : null
    if (!d && m && m.text) d = RD.fromMrkdwn(m.text, ctx)
    if (!d) d = RD.fromMarkup(box.initialText, ctx)
    box._editBase = JSON.stringify(RD.toBlocks(RD.refs(d, box.findRef)))
    box.load(d)
  }

  function draftKey() { return box.threadTs ? box.conv + "/" + box.threadTs : box.conv }
  function restoreDraft() {
    if (!box.ws) return
    box.files = []
    box._draftFor = box.draftKey()
    box.load(RD.fromMarkup(box.ws.draft(box._draftFor), box.dctx()))
  }
  function saveDraft(key) {
    if (!key || box.editing || !box.ws) return
    box.ws.setDraft(key, RD.toMarkup(box.doc))
    box.app.setTeamSetting(box.ws.teamId, "drafts", box.ws.drafts)
  }
  function saveDraftNow() { if (draftSave.running) { draftSave.stop(); box.saveDraft(box._draftFor) } }

  Timer {
    id: draftSave
    interval: 500
    onTriggered: box.saveDraft(box._draftFor)
  }

  Connections {
    target: box.ws
    function onRestoreText(conv, threadTs, text) {
      if (conv === box.conv && threadTs === box.threadTs && !box.editing && RD.isBlank(box.doc)) box.load(RD.fromMarkup(text, box.dctx()))
    }
  }

  // ---------------------------------------------------------------- drawing
  function anchorPos() { return input.cursorPosition === input.selectionStart ? input.selectionEnd : input.selectionStart }

  // The document into the TextEdit, the cursor (and selection) back.
  function render(pos, anchor) {
    box._cursor = pos
    box._anchor = anchor === undefined ? pos : anchor
    if (input.inputMethodComposing) { box._dirty = true; return }
    box._dirty = false
    box._rendering = true
    input.text = RD.toHtml(box.doc, box.rctx())
    var n = input.length
    var p = Math.max(0, Math.min(n, box._cursor)), q = Math.max(0, Math.min(n, box._anchor))
    if (p !== q) { input.cursorPosition = q; input.moveCursorSelection(p, TextEdit.SelectCharacters) }
    else input.cursorPosition = p
    box._rendering = false
    box._lastPos = p
    box.acText = RD.masked(box.doc)
    box.hasText = !RD.isBlank(box.doc)
    box.updateMarks()
    box.layoutDecos()
    complete.update()
  }
  function flush() { if (box._dirty) box.render(box._cursor, box._anchor) }

  function updateMarks() { box.marks = RD.marksAt(box.doc, input.selectionStart, input.selectionEnd, box.typing) }

  // Where the quote bars and code boxes go, behind the text, and where the
  // animated emoji play: on the see-through picture that holds their place,
  // centered in the line the way the text draws it. An emoji keeps its
  // player while the text moves it: it's known by its picture and which
  // one of that picture it is.
  function layoutDecos() {
    if (box._dirty) return
    var out = []
    RD.groups(box.doc).forEach(function(g) {
      var a = input.positionToRectangle(g.from), b = input.positionToRectangle(g.to)
      out.push({ k: g.k, y: a.y, h: b.y + b.height - a.y })
    })
    box.decos = out
    var px = box.t.emojiPx, nth = {}
    box.gifs = RD.gifs(box.doc).map(function(e) {
      var r = input.positionToRectangle(e.pos)
      nth[e.url] = (nth[e.url] || 0) + 1
      return { key: e.url + "#" + nth[e.url], url: e.url, x: Math.round(r.x), y: Math.round(r.y + (r.height - px) / 2) }
    })
  }

  // The cursor moved: never inside a pill; the toolbar and the
  // autocomplete follow.
  function cursorMoved() {
    if (box._dirty || box._rendering) return
    var p = input.cursorPosition
    if (input.selectionStart === input.selectionEnd) {
      var s = RD.snap(box.doc, p, p >= box._lastPos)
      if (s !== p) { input.cursorPosition = s; p = s }
    }
    box._lastPos = p
    box.updateMarks()
    complete.update()
  }

  // ---------------------------------------------------------------- editing
  // Qt changed the text (typing, deleting, its own paste): the change goes
  // into the document, Slack's markdown is applied, and it's drawn again
  // once Qt is done with the key.
  function edited() {
    var now = RD.normalize(input.getText(0, input.length))
    var res = RD.applyDiff(box.doc, now, input.cursorPosition, box.typing)
    if (!res) return
    box.remember(res.at, res.typed && !/\s/.test(res.text))
    box.doc = res.doc
    var cur = res.cursor, typing = null
    if (res.typed) {
      var af = RD.autoformat(box.doc, cur, box.dctx())
      // Undo first takes the formatting back, leaving what was typed.
      if (af) { box.remember(cur, false); box.doc = af.doc; cur = af.cursor; typing = af.typing }
    }
    box.typing = typing
    box._dirty = true
    box._cursor = cur
    box._anchor = cur
    Qt.callLater(box.flush)
    box.touched()
  }

  // A change made here (toolbar, shortcuts, picks): drawn at once.
  function change(d, pos, anchor) {
    if (!d) return
    box.remember(input.cursorPosition, false)
    box.doc = d
    box.typing = null
    box.render(pos, anchor)
    box.touched()
  }

  function touched() {
    if (box.editing || box.note || !box.ws) return
    box._draftFor = box.draftKey()
    draftSave.restart()
    if (!RD.isEmpty(box.doc)) box.ws.sendTyping(box.conv, box.threadTs)
  }

  // Undo keeps whole documents; typing a word is one step.
  function remember(pos, coalesce) {
    var now = Date.now()
    if (coalesce && box._undoAt && now - box._undoAt < 1200) { box._undoAt = now; return }
    var u = box.undos.slice(-99)
    u.push({ doc: box.doc, pos: pos })
    box.undos = u
    box.redos = []
    box._undoAt = coalesce ? now : 0
  }
  function undo() {
    if (!box.undos.length) return
    var u = box.undos.slice(), s = u.pop()
    box.undos = u
    box.redos = box.redos.concat([{ doc: box.doc, pos: input.cursorPosition }])
    box._undoAt = 0
    box.doc = s.doc
    box.typing = null
    box.render(s.pos)
    box.touched()
  }
  function redo() {
    if (!box.redos.length) return
    var r = box.redos.slice(), s = r.pop()
    box.redos = r
    box.undos = box.undos.concat([{ doc: box.doc, pos: input.cursorPosition }])
    box._undoAt = 0
    box.doc = s.doc
    box.typing = null
    box.render(s.pos)
    box.touched()
  }

  // ---------------------------------------------------------------- send
  function submit() {
    if (complete.visible && complete.pick()) return
    if (box.note) { box.submitted(); return }
    var d = box.outgoing()
    var typed = RD.toMarkup(d)
    var blocks = RD.toBlocks(d)
    if (box.editing) {
      // Emptied, it's Slack's Delete message instead; Cancel leaves the box
      // open, empty.
      if (!typed.trim()) {
        var m = box.ws.findAny(box.conv, box.editTs)
        if (m) box.win.confirmDelete(box.conv, m, function() { box.finish() })
        return
      }
      if (JSON.stringify(blocks) !== box._editBase) box.ws.editMessage(box.conv, box.editTs, typed, blocks)
      box.finish()
      return
    }
    if (!typed.trim() && !box.files.length) return
    var ok = box.ws.send(box.conv, typed, { threadTs: box.threadTs, broadcast: box.broadcast, files: box.files, blocks: blocks })
    if (ok === false) return
    box.clearBox()
  }

  // The edit is over (saved, cancelled, deleted): the keyboard goes back
  // where it was, a selected message or the message box.
  function finish() {
    var f = box._before
    box._before = null
    if (input.activeFocus) { try { if (f && f.visible) f.forceActiveFocus() } catch (e) {} }
    box.done()
  }

  function clearBox() {
    draftSave.stop()
    box.load(RD.empty())
    box.files = []
    box.broadcast = false
    box.ws.setDraft(box.draftKey(), "")
    box.app.setTeamSetting(box.ws.teamId, "drafts", box.ws.drafts)
  }

  // ---------------------------------------------------------------- formatting
  // B / I / U / S / code: on the selection, or for what's typed next.
  function toggleMark(m) {
    input.forceActiveFocus()
    if (box.marks.k === "pre") return
    var s = input.selectionStart, e = input.selectionEnd
    if (s !== e) {
      box.change(RD.toggleMark(box.doc, s, e, m), input.cursorPosition, box.anchorPos())
      return
    }
    var f = RD.formatAt(box.doc, s, box.typing).f
    box.typing = { pos: s, f: RD.withMark(f, m, f.indexOf(m) < 0) }
    box.updateMarks()
  }

  // Lists, quote, code block: on the lines of the selection.
  function toggleKind(kind) {
    input.forceActiveFocus()
    box.change(RD.toggleKind(box.doc, input.selectionStart, input.selectionEnd, kind), input.cursorPosition, box.anchorPos())
  }

  function insertLink() {
    var s = input.selectionStart, e = input.selectionEnd
    var sel = RD.textOf(box.doc, s, e)
    box.win.dialog("link", { text: sel, onDone: function(out) {
      // The dialog hands back the address, after the words when they say
      // something else.
      out = String(out || "").trim()
      if (!out) return
      var sp = out.lastIndexOf(" ")
      var url = sp >= 0 ? out.slice(sp + 1) : out
      var words = sp >= 0 ? out.slice(0, sp).trim() : ""
      if (!/^[a-z][a-z0-9+.\-]*:/i.test(url) && url.indexOf("@") > 0) url = "mailto:" + url
      if (s !== e && (!words || words === sel.trim())) box.change(RD.setLink(box.doc, s, e, url), e)
      else {
        var r = RD.insertText(box.doc, s, e, words || url, { f: RD.formatAt(box.doc, s, null).f.replace("c", ""), l: url })
        box.change(r.doc, r.cursor)
      }
      input.forceActiveFocus()
    } })
  }

  function insertEmoji(name) {
    var a = RD.mkEmoji(name, 0, box.dctx())
    var s = input.selectionStart, e = input.selectionEnd
    var fmt = RD.formatAt(box.doc, s, box.typing)
    var r = a.url || a.glyph ? RD.insertAtom(box.doc, s, e, a, fmt.f, "") : RD.insertText(box.doc, s, e, ":" + name + ":", fmt)
    box.change(r.doc, r.cursor)
  }

  function mention() {
    var p = input.cursorPosition
    var r = RD.insertText(box.doc, p, p, p > 0 && !/\s/.test(box.acText.charAt(p - 1)) ? " @" : "@", RD.formatAt(box.doc, p, box.typing))
    box.change(r.doc, r.cursor)
    input.forceActiveFocus()
  }

  // An autocomplete pick: the emoji's picture, a pill, or the command.
  function choose(start, end, label, wire) {
    var f = RD.formatAt(box.doc, start, null).f
    var r
    if (complete.kind === "emoji") {
      var a = RD.mkEmoji(label, 0, box.dctx())
      r = a.url || a.glyph ? RD.insertAtom(box.doc, start, end, a, f, " ") : RD.insertText(box.doc, start, end, label + " ", { f: f, l: "" })
    } else if (wire && RD.atomFromWire(wire, label)) r = RD.insertAtom(box.doc, start, end, RD.atomFromWire(wire, label), "", " ")
    else r = RD.insertText(box.doc, start, end, label + " ", null)
    box.change(r.doc, r.cursor)
  }

  // Shift+Enter (and Enter in a code block): a new line that keeps the
  // list / quote / code block going; on an empty item it ends the list.
  function newline() {
    var s = input.selectionStart, e = input.selectionEnd
    var L = RD.lineAt(box.doc, s)
    if (s === e && L.len === 0 && (L.k === "ul" || L.k === "ol" || L.k === "q")) { box.change(RD.setKind(box.doc, s, s, "p"), s); return }
    var fmt = RD.formatAt(box.doc, s, box.typing)
    var r = RD.insertText(box.doc, s, e, "\n", fmt)
    box.change(r.doc, r.cursor)
    if (fmt.f) { box.typing = { pos: r.cursor, f: fmt.f }; box.updateMarks() }
  }

  // Backspace at the start of a list item, quote or code block takes the
  // formatting off the line (a nested item goes out a level first).
  function unformatLine() {
    var s = input.selectionStart
    if (s !== input.selectionEnd) return false
    var L = RD.lineAt(box.doc, s)
    if (L.col !== 0 || L.k === "p" || ((L.k === "pre" || L.k === "q") && !L.first)) return false
    box.change((L.k === "ul" || L.k === "ol") && L.n > 0 ? RD.indent(box.doc, s, s, -1) : RD.setKind(box.doc, s, s, "p"), s)
    return true
  }

  // Tab / Shift+Tab in a list: in and out a level.
  function indentList(delta) {
    if (box.marks.k !== "ul" && box.marks.k !== "ol") return false
    var d = RD.indent(box.doc, input.selectionStart, input.selectionEnd, delta)
    if (d) box.change(d, input.cursorPosition, box.anchorPos())
    return true
  }

  // ↓ on the last line, in a code block or quote that ends the text: a
  // plain line after it.
  function leaveBlock() {
    var p = input.cursorPosition
    var L = RD.lineAt(box.doc, p)
    if (!L.last || (L.k !== "pre" && L.k !== "q")) return false
    if (input.positionToRectangle(input.length).y > input.cursorRectangle.y + 1) return false
    var end = RD.size(box.doc)
    var r = RD.insertText(box.doc, end, end, "\n", null)
    box.change(RD.setKind(r.doc, r.cursor, r.cursor, "p"), r.cursor)
    return true
  }

  // Copy / cut: plain words for other apps, the formatted lines for a paste
  // back in here.
  function copySelection(cut) {
    var a = input.selectionStart, b = input.selectionEnd
    var lines = RD.slice(box.doc, a, b)
    var text = RD.flatText(lines)
    box._clip = { text: text, lines: lines }
    box.app.copy(text)
    if (cut) { var r = RD.insertText(box.doc, a, b, "", null); box.change(r.doc, r.cursor) }
  }

  // Pasted text keeps its markup (Slack formats pasted markdown); in code
  // it stays as it is.
  function pasteText(s) {
    s = String(s || "").replace(/\r\n?/g, "\n")
    if (!s) { input.paste(); return }
    var a = input.selectionStart, b = input.selectionEnd
    var r
    if (box._clip && box._clip.text === s) r = RD.insertLines(box.doc, a, b, box._clip.lines)
    else if (box.marks.k === "pre" || box.marks.c) r = RD.insertText(box.doc, a, b, s, RD.formatAt(box.doc, a, box.typing))
    else r = RD.insertLines(box.doc, a, b, RD.fromMarkup(s, box.dctx()).map(function(l) { return l.k === "p" ? { k: null, n: 0, cells: l.cells } : l }))
    box.change(r.doc, r.cursor)
  }

  // ---------------------------------------------------------------- files
  // The desktop's file chooser (Omarchy's, else zenity: U.filePicker).
  Process {
    id: picker
    command: U.filePicker(box.app.tr("Upload files", "Enviar arquivos"), true)
    stdout: StdioCollector {
      onStreamFinished: {
        box.addFile(String(text).split("\n").map(function(p) { return p.trim() }).filter(function(p) { return p }))
        input.forceActiveFocus()
      }
    }
    onExited: code => {
      var why = U.filePickerError(code, box.app.lang)
      if (why && box.win) box.win.toast(why)
    }
  }
  function pickFiles() { if (!box.note && !picker.running) picker.running = true }

  Process {
    id: statProc
    property var queue: []
    property bool busy: false
    stdout: StdioCollector {
      onStreamFinished: {
        var list = box.files.slice()
        String(text).split("\n").forEach(function(line) {
          var parts = line.split("\t")
          var size = parseInt(parts[0], 10) || 0
          var path = parts.slice(1).join("\t")
          if (!path || list.some(function(f) { return f.path === path })) return
          var name = path.split("/").pop()
          list.push({ path: path, name: name, size: size, mime: U.guessMime(path), preview: /\.(png|jpe?g|gif|webp)$/i.test(path) ? "file://" + path : "" })
        })
        box.files = list.slice(0, 10)
        statProc.busy = false
        Qt.callLater(box.statNext)
      }
    }
  }
  // One path or a list; one stat call covers every queued path, and paths
  // that arrive while it runs wait for the next.
  function addFile(paths) {
    if (box.note) return
    statProc.queue = statProc.queue.concat(paths)
    box.statNext()
  }
  function statNext() {
    if (statProc.busy || !statProc.queue.length) return
    var paths = statProc.queue
    statProc.queue = []
    statProc.busy = true
    statProc.command = ["sh", "-c", 'for p; do printf "%s\\t%s\\n" "$(stat -c %s "$p")" "$p"; done', "stat"].concat(paths)
    statProc.running = true
  }

  // Ctrl+V: an image on the clipboard waits to be sent; text comes in
  // through the document.
  Process {
    id: pasteProc
    property string dest: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(text)
        if (out.indexOf("IMAGE ") === 0) box.addFile(out.trim().slice(6))
        else if (out.indexOf("TEXT\n") === 0) box.pasteText(out.slice(5))
        else input.paste()
      }
    }
  }
  function paste() {
    var dir = box.app.cacheDir + "/paste"
    var dest = dir + "/image-" + Date.now()
    pasteProc.command = ["sh", "-c",
      'types=$(wl-paste --list-types 2>/dev/null); for m in image/png image/jpeg image/gif image/webp; do echo "$types" | grep -qx "$m" || continue; ext=${m#image/}; [ "$ext" = jpeg ] && ext=jpg; mkdir -p "$1"; wl-paste --type "$m" > "$2.$ext" && echo "IMAGE $2.$ext"; exit 0; done; echo TEXT; wl-paste --no-newline --type text 2>/dev/null; exit 0',
      "paste", dir, dest]
    pasteProc.running = true
  }

  // ---------------------------------------------------------------- layout
  Column {
    id: col
    x: 1
    y: 1
    width: parent.width - 2

    // Formatting bar: what's on at the cursor shows as on. Slack's: faint
    // icons, in groups set apart by a wider gap. What doesn't fit (a narrow
    // thread) goes under "…" at the end, as in Slack.
    Row {
      id: fmtBar
      visible: box.showFormatting && !box.editing
      x: box.t.sp(6)
      height: visible ? box.t.sp(36) : 0
      spacing: box.t.sp(4)
      readonly property bool inCode: box.marks.k === "pre"
      readonly property color tone: box.t.alpha(box.t.fgDim, input.activeFocus ? 0.9 : 0.6)
      // {icon, en, pt, keys} and what it does: a mark, a line kind, the link.
      readonly property var items: [
        { icon: "", en: "Bold", pt: "Negrito", keys: "Ctrl+B", mark: "b" },
        { icon: "", en: "Italic", pt: "Itálico", keys: "Ctrl+I", mark: "i" },
        { icon: "󰊇", en: "Underline", pt: "Sublinhado", keys: "", mark: "u" },
        { icon: "", en: "Strikethrough", pt: "Tachado", keys: "Ctrl+Shift+X", mark: "x" },
        { gap: true },
        { icon: "", en: "Link", pt: "Link", keys: "Ctrl+Shift+U", link: true },
        { icon: "", en: "Numbered list", pt: "Lista numerada", keys: "Ctrl+Shift+7", kind: "ol" },
        { icon: "", en: "Bulleted list", pt: "Lista com marcadores", keys: "Ctrl+Shift+8", kind: "ul" },
        { gap: true },
        { icon: "", en: "Quote", pt: "Citação", keys: "Ctrl+Shift+9", kind: "q" },
        { icon: "󰗀", en: "Code", pt: "Código", keys: "Ctrl+Shift+C", mark: "c" },
        { icon: "", en: "Code block", pt: "Bloco de código", keys: "Ctrl+Alt+Shift+C", kind: "pre" }
      ]
      // How many fit, "…" taking its place when not all do.
      readonly property int fits: {
        var btn = box.t.sp(28), gap = box.t.sp(4), sp = fmtBar.spacing
        var room = box.width - 2 * box.t.sp(6)
        function width(n) { var w = 0; for (var i = 0; i < n; i++) w += (i ? sp : 0) + (items[i].gap ? gap : btn); return w }
        if (width(items.length) <= room) return items.length
        var n = items.length
        while (n > 0 && (width(n) + sp + btn > room || items[n - 1].gap)) n--
        return n
      }
      function on(it) { return it.mark ? box.marks[it.mark] : it.kind ? box.marks.k === it.kind : it.link ? box.marks.link !== "" : false }
      function dims(it) { return fmtBar.inCode && (!!it.mark || !!it.link) }
      function run(it) { if (it.mark) box.toggleMark(it.mark); else if (it.kind) box.toggleKind(it.kind); else if (it.link) box.insertLink() }
      function tipOf(it) { return box.app.tr(it.en, it.pt) + (it.keys ? "  " + it.keys : "") }

      Repeater {
        model: fmtBar.items
        delegate: Item {
          required property var modelData
          required property int index
          visible: index < fmtBar.fits
          width: modelData.gap ? box.t.sp(4) : fb.width
          height: fmtBar.height
          FmtButton {
            id: fb
            visible: !parent.modelData.gap
            app: box.app
            icon: parent.modelData.icon || ""
            tone: fmtBar.tone
            active: fmtBar.on(parent.modelData)
            dim: fmtBar.dims(parent.modelData)
            tip: parent.modelData.gap ? "" : fmtBar.tipOf(parent.modelData)
            onClicked: fmtBar.run(parent.modelData)
          }
        }
      }
      FmtButton {
        id: fmtMore
        visible: fmtBar.fits < fmtBar.items.length
        app: box.app
        icon: "󰇘"
        tone: fmtBar.tone
        tip: box.app.tr("More formatting", "Mais formatação")
        onClicked: {
          var out = []
          fmtBar.items.slice(fmtBar.fits).forEach(function(it) {
            if (it.gap) return
            out.push({ label: box.app.tr(it.en, it.pt), icon: it.icon, hint: it.keys, action: function() { fmtBar.run(it) } })
          })
          box.win.menuAt(fmtMore, out, 0, fmtMore.height + box.t.sp(4))
        }
      }
    }

    // Files waiting to go.
    Flow {
      visible: box.files.length > 0
      x: box.t.sp(10)
      width: parent.width - box.t.sp(20)
      spacing: box.t.sp(8)
      topPadding: box.t.sp(8)
      Repeater {
        model: box.files
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: modelData.preview ? box.t.sp(64) : Math.min(box.t.sp(240), fname.implicitWidth + box.t.sp(56))
          height: box.t.sp(64)
          radius: Math.max(6, box.t.radiusSmall)
          color: box.t.codeBg
          border.width: 1
          border.color: box.t.lineStrong
          clip: true
          Image { anchors.fill: parent; visible: !!parent.modelData.preview; source: parent.modelData.preview || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 128 }
          Row {
            visible: !parent.modelData.preview
            anchors.centerIn: parent
            spacing: box.t.sp(8)
            Glyph { app: box.app; icon: "󰈔"; size: box.t.fsTitle + 4; color: box.t.blue; anchors.verticalCenter: parent.verticalCenter }
            Text { id: fname; text: parent.parent.modelData.name; textFormat: Text.PlainText; color: box.t.fg; font.family: box.t.font; font.pixelSize: box.t.fsSmall; width: Math.min(implicitWidth, box.t.sp(170)); elide: Text.ElideMiddle; anchors.verticalCenter: parent.verticalCenter }
          }
          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: box.t.sp(3)
            width: box.t.sp(20); height: width; radius: width / 2
            color: box.t.alpha(box.t.bgDarker, 0.85)
            Glyph { app: box.app; anchors.centerIn: parent; icon: "󰅖"; size: box.t.fsTiny; color: box.t.fgBright }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { var l = box.files.slice(); l.splice(index, 1); box.files = l } }
          }
        }
      }
    }

    // The text.
    ScrollView {
      id: scroll
      width: parent.width
      height: Math.min(Math.max(input.implicitHeight, box.t.sp(40)), box.t.sp(260))
      clip: true
      TextArea {
        id: input
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.RichText
        color: box.t.fg
        placeholderText: box.placeholder !== "" ? box.placeholder : box.defaultPlaceholder()
        placeholderTextColor: box.t.fgDim
        selectionColor: box.t.alpha(box.t.accent, 0.35)
        selectedTextColor: box.t.fgBright
        selectByMouse: true
        font.family: box.t.font
        font.pixelSize: box.t.fsText
        leftPadding: box.t.sp(12)
        rightPadding: box.t.sp(12)
        topPadding: box.t.sp(10)
        bottomPadding: box.t.sp(8)
        background: null

        onTextChanged: if (!box._rendering) box.edited()
        onCursorPositionChanged: if (!box._rendering) Qt.callLater(box.cursorMoved)
        onSelectionStartChanged: if (!box._rendering) Qt.callLater(box.cursorMoved)
        onSelectionEndChanged: if (!box._rendering) Qt.callLater(box.cursorMoved)
        onPressed: box.typing = null
        onInputMethodComposingChanged: if (!inputMethodComposing) box.flush()
        onContentSizeChanged: box.layoutDecos()
        onWidthChanged: Qt.callLater(box.layoutDecos)
        onFontChanged: Qt.callLater(box.layoutDecos)
        // An input method's unfinished word pushes what follows along.
        onPreeditTextChanged: Qt.callLater(box.layoutDecos)

        // Quote bars and code block boxes, under the text.
        Repeater {
          model: box.decos
          delegate: Rectangle {
            required property var modelData
            readonly property bool code: modelData.k === "pre"
            z: -1
            x: input.leftPadding
            y: modelData.y - (code ? box.t.sp(8) : 0)
            width: code ? input.width - input.leftPadding - input.rightPadding : box.t.sp(4)
            height: modelData.h + (code ? box.t.sp(16) : 0)
            radius: code ? Math.max(4, box.t.radiusSmall) : width / 2
            color: code ? box.t.codeBg : box.t.alpha(box.t.fg, 0.28)
            border.width: code ? 1 : 0
            border.color: box.t.codeBorder
          }
        }

        // Animated emoji: the text only shows a GIF's first frame, so they
        // play here, on the see-through picture that holds their place.
        // Under the text (a selection still tints them), over the code
        // boxes; only the ones in view play.
        Repeater {
          model: ScriptModel { values: box.gifs; objectProp: "key" }
          delegate: AnimatedImage {
            required property var modelData
            readonly property Flickable view: scroll.contentItem as Flickable
            readonly property bool inView: !view || (y + height > view.contentY && y < view.contentY + view.height)
            z: -0.5
            x: modelData.x
            y: modelData.y
            width: box.t.emojiPx
            height: width
            source: modelData.url
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            playing: visible && inView
            smooth: true
            mipmap: true
          }
        }

        Keys.onPressed: event => {
          var ctrl = event.modifiers & Qt.ControlModifier
          var shift = event.modifiers & Qt.ShiftModifier
          var alt = event.modifiers & Qt.AltModifier
          var key = event.key
          if (complete.visible) {
            if (key === Qt.Key_Up) { complete.move(-1); event.accepted = true; return }
            if (key === Qt.Key_Down) { complete.move(1); event.accepted = true; return }
            if (key === Qt.Key_Tab || ((key === Qt.Key_Return || key === Qt.Key_Enter) && !shift)) { if (complete.pick()) { event.accepted = true; return } }
            if (key === Qt.Key_Escape) { complete.dismiss(); event.accepted = true; return }
          }
          if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            // In a code block Enter is a new line, and Ctrl+Enter sends.
            if (shift || (!ctrl && box.marks.k === "pre")) box.newline()
            else box.submit()
            event.accepted = true
            return
          }
          if (key === Qt.Key_Escape && box.editing) { box.finish(); event.accepted = true; return }
          // ↑ in the empty box: the messages above take the keyboard, from
          // the newest (Slack's message selection). Ctrl+↑ edits your last
          // one, as ↑ does in a box with no list above (Threads).
          if (key === Qt.Key_Up && !alt && !shift && RD.isEmpty(box.doc) && !box.editing && !box.note) {
            if (!ctrl && box.messageList) { if (box.messageList.selectLatest()) event.accepted = true; return }
            var last = box.ws.lastMine(box.conv, box.threadTs)
            if (last) { box.ws.editing = { conv: box.conv, ts: last.ts }; event.accepted = true }
            return
          }
          if (key === Qt.Key_Backspace && !ctrl && !alt && box.unformatLine()) { event.accepted = true; return }
          if ((key === Qt.Key_Tab || key === Qt.Key_Backtab) && !ctrl && !alt && box.indentList(key === Qt.Key_Backtab || shift ? -1 : 1)) { event.accepted = true; return }
          if (key === Qt.Key_Down && !ctrl && !alt && !shift && box.leaveBlock()) { event.accepted = true; return }
          if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown].indexOf(key) >= 0) box.typing = null
          if (ctrl && !alt && key === Qt.Key_Z) { if (shift) box.redo(); else box.undo(); event.accepted = true; return }
          if (ctrl && !shift && !alt && key === Qt.Key_Y) { box.redo(); event.accepted = true; return }
          if (ctrl && !shift && !alt && (key === Qt.Key_C || key === Qt.Key_X) && input.selectionStart !== input.selectionEnd) { box.copySelection(key === Qt.Key_X); event.accepted = true; return }
          if (ctrl && !shift && !alt && key === Qt.Key_V) { box.paste(); event.accepted = true; return }
          if ((ctrl && !shift && !alt && key === Qt.Key_B) || (alt && !ctrl && key === Qt.Key_B)) { box.toggleMark("b"); event.accepted = true; return }
          if (ctrl && !shift && !alt && key === Qt.Key_I) { box.toggleMark("i"); event.accepted = true; return }
          if ((ctrl && shift && !alt && key === Qt.Key_X) || (alt && !ctrl && key === Qt.Key_X)) { box.toggleMark("x"); event.accepted = true; return }
          if (ctrl && shift && alt && key === Qt.Key_C) { box.toggleKind("pre"); event.accepted = true; return }
          if ((ctrl && shift && key === Qt.Key_C) || (alt && !ctrl && key === Qt.Key_C)) { box.toggleMark("c"); event.accepted = true; return }
          if (ctrl && shift && (key === Qt.Key_9 || key === Qt.Key_ParenLeft)) { box.toggleKind("q"); event.accepted = true; return }
          if (ctrl && shift && (key === Qt.Key_8 || key === Qt.Key_Asterisk)) { box.toggleKind("ul"); event.accepted = true; return }
          if (ctrl && shift && (key === Qt.Key_7 || key === Qt.Key_Ampersand)) { box.toggleKind("ol"); event.accepted = true; return }
          if (ctrl && shift && key === Qt.Key_U) { box.insertLink(); event.accepted = true; return }
          if (ctrl && !shift && key === Qt.Key_U) { box.pickFiles(); event.accepted = true; return }
          if (key === Qt.Key_Escape && !shift && !box.editing && !box.note) { if (box.threadTs) box.ws.closeThread(); else box.ws.markRead(box.conv); event.accepted = true; return }
        }
      }
    }

    // Thread: also send to the channel.
    Item {
      visible: box.threadTs !== "" && !box.editing
      width: parent.width
      height: visible ? box.t.sp(26) : 0
      Row {
        x: box.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: box.t.sp(8)
        Rectangle {
          width: box.t.sp(16); height: width; radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: box.broadcast ? box.t.accent : "transparent"
          border.width: box.broadcast ? 0 : 1
          border.color: box.t.lineStrong
          Glyph { app: box.app; anchors.centerIn: parent; visible: box.broadcast; icon: "󰄬"; size: box.t.fsTiny; color: box.t.onColor(box.t.accent) }
        }
        Text {
          id: alsoText
          anchors.verticalCenter: parent.verticalCenter
          text: box.app.tr("Also send to ", "Também enviar para ") + (box.c && box.c.kind !== "im" && box.c.kind !== "mpim" ? "#" + box.c.name : box.app.tr("the conversation", "a conversa"))
          textFormat: Text.PlainText
          color: box.t.fgSoft
          font.family: box.t.font
          font.pixelSize: box.t.fsSmall
        }
      }
      MouseArea { x: box.t.sp(8); width: alsoText.x + alsoText.width + box.t.sp(16); height: parent.height; cursorShape: Qt.PointingHandCursor; onClicked: box.broadcast = !box.broadcast }
    }

    // Bottom bar. What doesn't fit beside the send button (a narrow
    // conversation) goes under "…", the shortcuts first, then @, emoji, Aa.
    Item {
      width: parent.width
      height: box.t.sp(40)
      Row {
        id: botRow
        x: box.t.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: box.t.sp(4)
        visible: !box.editing
        readonly property var order: box.note ? ["aa", "emoji", "at"] : ["plus", "aa", "emoji", "at", "shortcut"]
        readonly property int fits: {
          var btn = box.t.sp(28), sp = botRow.spacing
          var room = parent.width - botRow.x - (sendPill.visible ? sendPill.width + box.t.sp(8) : 0) - box.t.sp(10)
          function width(n) { var w = 0; for (var i = 0; i < n; i++) w += (i ? sp : 0) + btn + (order[i] === "shortcut" ? box.t.sp(8) + sp : 0); return w }
          if (width(order.length) <= room) return order.length
          var n = order.length - 1
          while (n > 0 && width(n) + sp + btn > room) n--
          return n
        }
        function keeps(k) { var i = order.indexOf(k); return i >= 0 && i < fits }
        function runShortcut() { if (RD.isEmpty(box.doc)) box.change(RD.insertText(box.doc, 0, 0, "/", null).doc, 1); input.forceActiveFocus() }
        function toggleFormatting() { box.showFormatting = !box.showFormatting; box.app.setSetting("composerToolbar", box.showFormatting) }
        Rectangle {
          visible: botRow.keeps("plus")
          width: box.t.sp(28); height: width; radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: plusMa.containsMouse ? box.t.hoverStrong : box.t.alpha(box.t.fg, 0.1)
          Glyph { app: box.app; anchors.centerIn: parent; inkCentered: true; icon: ""; size: box.t.fsIcon + 3; color: plusMa.containsMouse ? box.t.fgBright : box.t.fgSoft }
          MouseArea { id: plusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: box.pickFiles() }
          PanelToolTip { visible: plusMa.containsMouse; text: box.app.tr("Upload from your computer", "Enviar do seu computador") + "  Ctrl+U" }
        }
        FmtButton { visible: botRow.keeps("aa"); app: box.app; icon: ""; iconSize: box.t.fsIcon + 5; tone: box.t.fgSoft; underlined: box.showFormatting
                    tip: box.showFormatting ? box.app.tr("Hide formatting", "Ocultar formatação") : box.app.tr("Show formatting", "Mostrar formatação")
                    onClicked: botRow.toggleFormatting() }
        FmtButton { id: emojiBtn; visible: botRow.keeps("emoji"); app: box.app; icon: ""; iconSize: box.t.fsIcon + 5; tone: box.t.fgSoft; tip: box.app.tr("Emoji", "Emoji")
                    onClicked: box.win.emojiPicker(emojiBtn, function(name) { box.insertEmoji(name); input.forceActiveFocus() }, {}) }
        FmtButton { visible: botRow.keeps("at"); app: box.app; icon: ""; iconSize: box.t.fsIcon + 5; tone: box.t.fgSoft; tip: box.app.tr("Mention someone", "Mencionar alguém"); onClicked: box.mention() }
        Item { visible: botRow.keeps("shortcut"); width: box.t.sp(8); height: 1 }
        FmtButton { visible: botRow.keeps("shortcut"); app: box.app; icon: ""; iconSize: box.t.fsIcon + 5; tone: box.t.alpha(box.t.fgDim, 0.7); tip: box.app.tr("Run a shortcut", "Executar um atalho")
                    onClicked: botRow.runShortcut() }
        FmtButton {
          id: botMore
          visible: botRow.fits < botRow.order.length
          app: box.app
          icon: "󰇘"
          iconSize: box.t.fsIcon + 3
          tone: box.t.fgSoft
          tip: box.app.tr("More", "Mais")
          onClicked: {
            var labels = {
              plus: [box.app.tr("Upload from your computer", "Enviar do seu computador"), "Ctrl+U", function() { box.pickFiles() }],
              aa: [box.showFormatting ? box.app.tr("Hide formatting", "Ocultar formatação") : box.app.tr("Show formatting", "Mostrar formatação"), "", function() { botRow.toggleFormatting() }],
              emoji: [box.app.tr("Emoji", "Emoji"), "", function() { box.win.emojiPicker(botMore, function(name) { box.insertEmoji(name); input.forceActiveFocus() }, {}) }],
              at: [box.app.tr("Mention someone", "Mencionar alguém"), "", function() { box.mention() }],
              shortcut: [box.app.tr("Run a shortcut", "Executar um atalho"), "", function() { botRow.runShortcut() }]
            }
            var out = botRow.order.slice(botRow.fits).map(function(k) { var l = labels[k]; return { label: l[0], hint: l[1], action: l[2] } })
            box.win.menuAt(botMore, out, 0, -box.t.sp(8) - out.length * box.t.sp(32))
          }
        }
      }

      // Edit: Cancel / Save. Otherwise the send button.
      Row {
        visible: box.editing
        anchors.right: parent.right
        anchors.rightMargin: box.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: box.t.sp(8)
        SButton { app: box.app; small: true; text: box.app.tr("Cancel", "Cancelar"); onClicked: box.finish() }
        SButton { app: box.app; small: true; kind: "primary"; text: box.app.tr("Save", "Salvar"); onClicked: box.submit() }
      }
      // Send, and Slack's "Schedule for later" beside it: one pill split by
      // a thin line, each half lighting up on its own.
      Rectangle {
        id: sendPill
        visible: !box.editing && !box.note
        anchors.right: parent.right
        anchors.rightMargin: box.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool can: box.hasText || box.files.length > 0
        readonly property int r: box.t.sp(5)
        readonly property color lit: Qt.lighter(box.t.accent, 1.1)
        width: sendHalf.width + (schedBtn.visible ? 1 + schedBtn.width : 0)
        height: box.t.sp(28)
        radius: r
        color: can ? box.t.accent : "transparent"
        Rectangle {
          id: sendHalf
          width: box.t.sp(36)
          height: parent.height
          topLeftRadius: sendPill.r
          bottomLeftRadius: sendPill.r
          topRightRadius: schedBtn.visible ? 0 : sendPill.r
          bottomRightRadius: schedBtn.visible ? 0 : sendPill.r
          color: sendPill.can && sendMa.containsMouse ? sendPill.lit : "transparent"
          Glyph { app: box.app; anchors.centerIn: parent; inkCentered: true; icon: "󰒊"; size: box.t.fsIcon + 1; color: sendPill.can ? box.t.onColor(box.t.accent) : box.t.fgDim }
          MouseArea { id: sendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: sendPill.can ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (sendPill.can) box.submit() }
          PanelToolTip { visible: sendMa.containsMouse && sendPill.can; text: box.sendLabel + "  Enter" }
        }
        Rectangle {
          visible: schedBtn.visible
          x: sendHalf.width
          anchors.verticalCenter: parent.verticalCenter
          width: 1
          height: Math.round(parent.height * 0.6)
          color: sendPill.can ? box.t.alpha(box.t.onColor(box.t.accent), 0.3) : box.t.lineStrong
        }
        Rectangle {
          id: schedBtn
          visible: box.files.length === 0
          x: sendHalf.width + 1
          width: box.t.sp(26)
          height: parent.height
          topRightRadius: sendPill.r
          bottomRightRadius: sendPill.r
          color: sendPill.can && schedMa.containsMouse ? sendPill.lit : "transparent"
          Glyph { app: box.app; anchors.centerIn: parent; inkCentered: true; icon: ""; size: box.t.fsSmall + 1; color: sendPill.can ? box.t.onColor(box.t.accent) : box.t.fgDim }
          MouseArea { id: schedMa; anchors.fill: parent; hoverEnabled: true; cursorShape: sendPill.can ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (sendPill.can) box.scheduleMenu() }
          PanelToolTip { visible: schedMa.containsMouse && sendPill.can; text: box.app.tr("Schedule for later", "Agendar para depois") }
        }
      }
    }
  }

  // Under the box, on the right (the conversation's "typing…" line is on
  // the left), Slack's reminder of the keys once something is typed. It
  // sits in the space below the box, so the box keeps its height.
  Text {
    visible: box.hasText && !box.editing && !box.note
    anchors.right: parent.right
    anchors.rightMargin: box.t.sp(2)
    anchors.top: parent.bottom
    anchors.topMargin: box.t.sp(4)
    readonly property bool inCode: box.marks.k === "pre"
    text: "<b><font color=\"" + box.t.hex(box.t.fgSoft) + "\">" + (inCode ? "Ctrl + Enter" : "Shift + Enter") + "</font></b> " +
          (inCode ? box.app.tr("to send", "para enviar") : box.app.tr("to add a new line", "para nova linha"))
    textFormat: Text.StyledText
    color: box.t.fgDim
    font.family: box.t.font
    font.pixelSize: box.t.fsTiny
  }

  // ---------------------------------------------------------------- autocomplete
  Autocomplete {
    id: complete
    app: box.app
    ws: box.ws
    input: input
    text: box.acText
    conv: box.conv
    threadTs: box.threadTs
    kinds: box.note ? ["emoji", "user", "channel"] : ["command", "emoji", "user", "channel"]
    anchors.left: parent.left
    anchors.bottom: parent.top
    anchors.bottomMargin: box.t.sp(4)
    width: Math.min(parent.width, box.t.sp(480))
    onChose: (start, end, label, wire) => box.choose(start, end, label, wire)
  }

  function scheduleMenu() {
    var now = new Date()
    function at(days, h) { var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + days, h, 0, 0); return Math.floor(d.getTime() / 1000) }
    var monday = (8 - now.getDay()) % 7 || 7
    function go(postAt) {
      var d = box.outgoing()
      box.ws.schedule(box.conv, RD.toMarkup(d), postAt, box.threadTs, RD.toBlocks(d))
      box.clearBox()
    }
    var p = schedBtn.mapToItem(box.win.contentItem, schedBtn.width, 0)
    box.win.menu([
      { header: box.app.tr("Schedule message", "Agendar mensagem") },
      { label: box.app.tr("Tomorrow at 9:00", "Amanhã às 9:00"), icon: "󰅐", action: function() { go(at(1, 9)) } },
      { label: box.app.tr("Next Monday at 9:00", "Próxima segunda às 9:00"), icon: "󰅐", action: function() { go(at(monday, 9)) } },
      { label: box.app.tr("In 1 hour", "Em 1 hora"), icon: "󰅐", action: function() { go(Math.floor(Date.now() / 1000) + 3600) } },
      { label: box.app.tr("In 3 hours", "Em 3 horas"), icon: "󰅐", action: function() { go(Math.floor(Date.now() / 1000) + 3 * 3600) } }
    ], p.x - box.t.sp(240), p.y - box.t.sp(190))
  }

  function defaultPlaceholder() {
    if (box.editing) return ""
    if (box.threadTs) return box.app.tr("Reply…", "Responder…")
    if (!box.c) return ""
    if (box.c.kind === "im") return box.app.tr("Message ", "Mensagem para ") + box.ws.convLabel(box.conv)
    if (box.c.kind === "mpim") return box.app.tr("Message ", "Mensagem para ") + box.ws.convLabel(box.conv)
    return box.app.tr("Message #", "Mensagem para #") + box.c.name
  }
}
