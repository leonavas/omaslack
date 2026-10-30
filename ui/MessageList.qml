import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Model.js" as Model
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The messages of a conversation (or of a thread), newest at the bottom.
// Scrolling up loads older pages; "Jump to recent" glides back down. ↑ in
// the empty message box hands it the keyboard (`selectLatest`): ↑ / ↓ select
// messages as in Slack, the selected one takes Slack's keys for a message
// (MessageItem.keyAction), and Esc or ↓ past the newest goes back (`leave`).
Item {
  id: root
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  property string threadTs: ""          // set: the replies of this thread
  property Component intro: null        // drawn above the first message
  readonly property var t: app.theme
  readonly property bool inThread: threadTs !== ""

  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  property var rowCache: new Map()
  onConvChanged: { glide.stop(); root.rowCache = new Map(); root.stick = true; root.opened = false; root.landing = false; root.holdNew = false; root.selKey = ""; wheelOff.stop(); Qt.callLater(root.settle) }
  onThreadTsChanged: root.selKey = ""

  // Pinned to the newest message unless the reader scrolled up; on open,
  // the New line comes into view if there is one.
  property bool stick: true
  property bool opened: false
  property bool landing: false          // back from an old stretch: the newest page glides in
  property bool _auto: false
  // The reader is scrolling (wheel, touchpad, drag, flick): never snap back under them.
  readonly property bool scrolling: list.moving || list.dragging || list.flicking || wheelOff.running
  // Pixels between the bottom of the view and the newest message (negative
  // inside the bottom margin, which positionViewAtBeginning leaves out).
  function fromNewest() { return list.originY + list.contentHeight - list.contentY - list.height }
  function nearNewest() { return root.fromNewest() <= root.t.sp(8) }
  function settle() {
    if (!root.opened && root.rows.length > 0 && !root.loading) {
      root.opened = true
      if (root.rows.some(function(r) { return r.isNew })) { root.stick = false; root.holdNew = true; newHold.restart(); root.keepNew(); return }
    }
    // Back from an old stretch of history: the newest page glides in.
    var land = root.landing && root.rows.length > 0 && !root.loading
    if (land) root.landing = false
    if (!root.stick || root.scrolling || glide.running) return
    if (land) { root.stick = false; glide.enter(function() { list.positionViewAtBeginning() }, 1, root.landed); return }
    root._auto = true; list.positionViewAtBeginning(); root._auto = false
  }
  onRowsChanged: { Qt.callLater(root.keepSel); Qt.callLater(root.settle) }

  // Moves only when this conversation (or thread) does, not with every
  // other one's history (ws.historyRev); the New line moves with it.
  property int histRev: 0
  Connections {
    target: root.ws
    function onHistoryUpdated(c) { if (!root.inThread && c === root.conv) root.histRev++ }
    function onRepliesUpdated(key) { if (root.inThread && key === root.conv + "/" + root.threadTs) root.histRev++ }
  }
  readonly property var hist: {
    if (!ws) return null
    root.histRev
    if (inThread) return ws.replies[conv + "/" + threadTs] || null
    return ws.histories[conv] || null
  }
  readonly property var rows: {
    root.histRev
    var s = root.hist
    if (!s) return []
    var msgs = s.msgs
    var rows = Model.messageRows(inThread ? msgs.slice(1) : msgs, { newTs: inThread ? "" : (root.ws.newLines[root.conv] || ""), conv: root.conv, noDays: inThread }, root.rowCache)
    return rows.slice().reverse()
  }
  readonly property bool loading: !!hist && hist.loading
  readonly property bool atStart: !!hist && (inThread || hist.noOlder)

  ListView {
    id: list
    // A conversation sits on the message box; a short thread hangs from the top.
    y: 0
    width: parent.width
    height: root.inThread ? Math.min(root.height, list.contentHeight + list.topMargin + list.bottomMargin) : root.height
    verticalLayoutDirection: ListView.BottomToTop
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    cacheBuffer: 400
    topMargin: root.t.sp(8)
    model: ScriptModel { values: root.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: root.app }

    // Visually below the newest message: the room above the message box.
    // A margin would do, but positionViewAtBeginning() hides it here.
    header: Item { width: list.width; height: root.t.sp(root.inThread ? 12 : 22) }

    delegate: MessageItem {
      id: rowItem
      required property var modelData
      width: list.width
      app: root.app
      win: root.win
      ws: root.ws
      row: modelData
      conv: root.conv
      inThread: root.inThread
      ctx: root.ctx
      selected: root.focusKey !== "" && root.focusKey === modelData.key
      keyed: root.focusKey !== "" && root.keyed
      sharedBar: rowBar
      onPointedChanged: root.point(rowItem)
      onSelectedChanged: root.mark(rowItem)
      Component.onCompleted: root.mark(rowItem)
    }

    // The rows' one toolbar (MessageItem.sharedBar), in the content so it
    // scrolls and clips with them: over the keyboard's message while it
    // leads, else over the one under the mouse.
    MessageToolbar {
      id: rowBar
      app: root.app
      win: root.win
      ws: root.ws
      row: root.focusKey !== "" && root.keyed ? root.keyRow : root.mouseRow
      x: list.width - width - root.t.sp(16)
      y: row ? row.y + row.barTop - root.t.sp(16) : 0
      z: 20
      onHoveredChanged: root.point(null)
    }

    // Visually above the oldest message (the list grows upward).
    footer: Item {
      readonly property Item intro: introLoader.item
      width: list.width
      height: introLoader.item ? introLoader.item.implicitHeight + root.t.sp(16) : (root.loading ? root.t.sp(48) : root.t.sp(8))
      Loader {
        id: introLoader
        width: parent.width
        active: root.atStart && !root.loading && root.intro !== null
        sourceComponent: root.intro
      }
      Row {
        visible: root.loading
        anchors.centerIn: parent
        spacing: root.t.sp(8)
        TypingDots { app: root.app; color: root.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
        Text { text: root.app.tr("Loading messages…", "Carregando mensagens…"); color: root.t.fgDim; font.family: root.t.font; font.pixelSize: root.t.fsSmall; anchors.verticalCenter: parent.verticalCenter }
      }
    }

    // Pictures and unfurls grow after loading: stay on the newest message,
    // or on the first new one just opened to.
    onContentHeightChanged: {
      if (root.stick && !root.inThread) Qt.callLater(root.settle)
      else if (root.holdNew) Qt.callLater(root.keepNew)
    }
    // Any scroll away from the newest message lets go of it; back down there holds it again.
    onContentYChanged: {
      root.maybeLoad()
      if (!root._auto && root.scrolling) { root.holdNew = false; root.stick = root.nearNewest() }
    }
    onMovementEnded: root.stick = root.nearNewest()
    // The wheel / touchpad, further than Qt's: the reader scrolling.
    WheelScroll { view: list; step: root.t.sp(145); touch: 1.8; onWheeled: { glide.stop(); wheelOff.restart() } }
    Timer { id: wheelOff; interval: 600; onTriggered: root.stick = root.nearNewest() }
    onHeightChanged: root.maybeLoad()
  }

  // The row under the mouse, and the one the toolbar is on: held while the
  // mouse is on the toolbar (it rises over the row above). `keyRow`: the
  // keyboard's.
  property Item under: null
  property Item mouseRow: null
  property Item keyRow: null
  function point(it) {
    if (it) { if (it.pointed) root.under = it; else if (root.under === it) root.under = null }
    if (!(rowBar.hovered && rowBar.visible)) root.mouseRow = root.under
  }
  function mark(it) { if (it.selected) root.keyRow = it; else if (root.keyRow === it) root.keyRow = null }

  function maybeLoad() {
    if (root.inThread || !root.ws || root.loading || root.atStart) return
    if (list.visibleArea.yPosition < 0.08) root.ws.loadOlder(root.conv)
  }

  // The mouse moving (not the messages moving under it) takes the hover
  // back from the keyboard's selection.
  HoverHandler {
    id: pointer
    property point at: Qt.point(-1, -1)
    onPointChanged: {
      var p = pointer.point.scenePosition
      if (p.x === pointer.at.x && p.y === pointer.at.y) return
      pointer.at = p
      root.keyed = false
    }
  }

  readonly property bool scrolledUp: list.visibleArea.heightRatio < 1 && (1 - list.visibleArea.yPosition - list.visibleArea.heightRatio) * list.contentHeight > root.t.sp(120)
  readonly property bool detached: !!hist && !!hist.detached

  // Programmatic scrolls that should read as motion; the rest (opening,
  // keys, staying on the newest) stay instant.
  Glide { id: glide; view: list }

  // "Jump to recent": a glide down, the last stretch only when far up. Off
  // in an old stretch of history, the newest page loads and glides in.
  function toBottom() {
    root.holdNew = false
    if (root.detached) {
      glide.stop()
      root.landing = true
      root.stick = true
      root.ws.jumpToPresent(root.conv)
      return
    }
    glide.to(function() { list.positionViewAtBeginning() }, root.landed)
  }
  function landed() { root.stick = true; root.settle() }

  function rowOfTs(ts) {
    for (var i = 0; i < root.rows.length; i++) {
      var r = root.rows[i]
      if (r.msg && r.msg.ts === ts || (r.run && r.run.some(function(x) { return x.ts === ts }))) return i
    }
    return -1
  }

  // A message from search or a link. `smooth`: the conversation was on
  // screen already (just opened, it's straight there). The row is looked
  // up again on each step: new messages shift the rows on the way.
  function jump(ts, smooth) {
    var i = root.rowOfTs(ts)
    if (i < 0) return false
    root.stick = false
    root.holdNew = false
    if (smooth) {
      glide.to(function() { var j = root.rowOfTs(ts); if (j >= 0) list.positionViewAtIndex(j, ListView.Center) })
      return true
    }
    glide.stop()
    root._auto = true
    list.positionViewAtIndex(i, ListView.Center)
    root._auto = false
    return true
  }

  // On open with unread: the first new message at the top, and below it
  // as many of the rest as fit (all of them, if they do: the list stops at
  // the newest). Held there while pictures and unfurls load and the rows
  // grow (`holdNew`), until the reader scrolls or a few seconds pass.
  property bool holdNew: false
  Timer { id: newHold; interval: 3000; onTriggered: root.holdNew = false }
  function keepNew() {
    if (!root.holdNew || root.scrolling || glide.running) return
    root._auto = true
    root.showNew()
    root._auto = false
  }
  function showNew() {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].isNew) { list.positionViewAtIndex(i, ListView.End); return }
  }

  // ---------------------------------------------------------------- keyboard
  // The selected message (its row key; "parent": a thread's, above the
  // replies), lit while `keyboard` has the keys (`focusKey`). `keyed`:
  // the keyboard was used since the mouse last moved, so the selected
  // message, not the one under the mouse, shows its toolbar.
  property string selKey: ""
  property int _selAt: -1
  property string _selConv: ""
  property bool keyed: false
  property bool held: false
  signal leave()
  readonly property bool overlay: !!root.win && (root.win.menusShown || root.win.dialogName !== "" || root.win.pickerShown)
  onOverlayChanged: if (!root.overlay) root.held = false
  readonly property string focusKey: keyboard.activeFocus || (root.held && root.overlay) ? root.selKey : ""
  // A thread's parent, drawn by the intro (`intro.lead`): ↑ goes on to it.
  readonly property Item lead: {
    var f = list.footerItem, it = f ? f.intro : null
    return it && it.lead && it.lead.visible ? it.lead : null
  }

  function selectable(r) { return !!r && r.kind === "msg" && !!r.msg }
  function indexOfKey(k) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].key === k) return i
    return -1
  }
  // Rows run newest first; the thread's parent comes after the last.
  function selIndex() {
    if (root.selKey === "parent") return root.lead ? root.rows.length : -1
    return root.selKey === "" ? -1 : root.indexOfKey(root.selKey)
  }
  function selItem(i) { return i >= root.rows.length ? root.lead : list.itemAtIndex(i) }

  // ↑ in the empty message box: the newest message. False when there's none.
  function selectLatest() {
    if (!root.visible) return false
    for (var i = 0; i < root.rows.length; i++) if (root.selectable(root.rows[i])) { root.select(i); return true }
    if (root.lead) { root.select(root.rows.length); return true }
    return false
  }

  function select(i) {
    root.selKey = i >= root.rows.length ? "parent" : root.rows[i].key
    root._selAt = i
    root._selConv = root.conv
    root.keyed = true
    if (!keyboard.activeFocus) keyboard.forceActiveFocus()
    root.showRow(i)
  }

  // Scrolled into view, with room above it for its toolbar.
  function showRow(i) {
    glide.stop()
    root._auto = true
    if (i === 0) list.positionViewAtBeginning()
    else if (i >= root.rows.length) list.positionViewAtEnd()
    else {
      list.positionViewAtIndex(i, ListView.Contain)
      var it = list.itemAtIndex(i), room = root.t.sp(24)
      if (it && it.y - list.contentY < room) list.contentY = Math.max(list.originY - list.topMargin, it.y - room)
    }
    root._auto = false
    root.stick = root.nearNewest()
  }

  // d: 1 the older message (↑), -1 the newer (↓). Past the newest, back to
  // the box; past the oldest, the thread's parent, or older history loading
  // as scrolling up there would.
  function step(d) {
    var i = root.selIndex()
    if (i < 0) { if (!root.selectLatest()) root.back(); return }
    for (var j = i + d; j >= 0 && j < root.rows.length; j += d) if (root.selectable(root.rows[j])) { root.select(j); return }
    if (d < 0) { root.back(); return }
    if (root.lead && i < root.rows.length) { root.select(root.rows.length); return }
    root.showRow(root.rows.length)
    root.maybeLoad()
  }

  function back() { root.selKey = ""; root.leave() }

  // The selected message went away (deleted): the newer one beside it takes
  // the selection, else the older; none left, back to the box.
  function keepSel() {
    if (root.selKey === "" || root.selKey === "parent") return
    if (root._selConv !== root.conv) { root.selKey = ""; return }
    var i = root.indexOfKey(root.selKey)
    if (i >= 0) { root._selAt = i; return }
    if (!keyboard.activeFocus) { root.selKey = ""; return }
    var at = Math.min(root._selAt, root.rows.length)
    for (var j = at - 1; j >= 0; j--) if (root.selectable(root.rows[j])) { root.select(j); return }
    for (var k = at; k < root.rows.length; k++) if (root.selectable(root.rows[k])) { root.select(k); return }
    if (root.lead) { root.select(root.rows.length); return }
    root.back()
  }

  // Takes the keys while messages are selected: beside the list, so what an
  // edit box in it leaves unhandled (↑ on its first line) never comes here.
  Item {
    id: keyboard
    Keys.onPressed: event => root.key(event)
    // A menu, the emoji picker or a dialog over it keeps the selection lit.
    onActiveFocusChanged: {
      if (keyboard.activeFocus) root.held = false
      else Qt.callLater(function() { if (!keyboard.activeFocus) root.held = root.overlay })
    }
  }

  function key(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key, shift = event.modifiers & Qt.ShiftModifier
    if (!shift && (k === Qt.Key_Up || k === Qt.Key_Down)) { root.step(k === Qt.Key_Up ? 1 : -1); event.accepted = true; return }
    if (!shift && k === Qt.Key_Escape) { root.back(); event.accepted = true; return }
    var i = root.selIndex()
    if (i < 0) return
    // In a thread, its thread is here: T or Enter goes to the reply box.
    if (root.inThread && (k === Qt.Key_T || k === Qt.Key_Return || k === Qt.Key_Enter)) { root.back(); event.accepted = true; return }
    if (event.text === "" && [Qt.Key_Delete, Qt.Key_Backspace, Qt.Key_Return, Qt.Key_Enter].indexOf(k) < 0) return
    root.keyed = true
    root.showRow(i)
    var it = root.selItem(i)
    if (it && it.keyAction(k)) event.accepted = true
  }

  Connections {
    target: root.ws
    // Here and settled before the jump: glide; opening at the message: straight there.
    function onJumpTo(conv, ts) {
      if (conv !== root.conv || root.inThread) return
      var smooth = root.opened
      Qt.callLater(function() { root.jump(ts, smooth) })
    }
  }

  EdgePill {
    app: root.app
    visible: root.scrolledUp || root.detached
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.t.sp(14)
    anchors.horizontalCenter: parent.horizontalCenter
    mention: false
    color: root.t.blue
    ink: root.t.onColor(root.t.blue)
    border.width: 0
    text: root.app.tr("Jump to recent messages", "Ir para as mensagens recentes")
    arrow: "󰁅"
    onClicked: root.toBottom()
  }
}
