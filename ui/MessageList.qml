import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Model.js" as Model
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The messages of a conversation (or of a thread), newest at the bottom.
// Scrolling up loads older pages; "Jump to recent" comes back.
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
  onConvChanged: { root.rowCache = new Map(); root.stick = true; root.opened = false; wheelOff.stop(); Qt.callLater(root.settle) }

  // Pinned to the newest message unless the reader scrolled up; on open,
  // the New line comes into view if there is one.
  property bool stick: true
  property bool opened: false
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
      if (root.rows.some(function(r) { return r.isNew })) { root.stick = false; root._auto = true; root.showNew(); root._auto = false; return }
    }
    if (root.stick && !root.scrolling) { root._auto = true; list.positionViewAtBeginning(); root._auto = false }
  }
  onRowsChanged: Qt.callLater(root.settle)

  readonly property var hist: {
    if (!ws) return null
    if (inThread) return ws.repliesOf(conv, threadTs)
    return ws.history(conv)
  }
  readonly property var rows: {
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
    cacheBuffer: 1200
    topMargin: root.t.sp(8)
    model: ScriptModel { values: root.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: root.app }

    // Visually below the newest message: the room above the message box.
    // A margin would do, but positionViewAtBeginning() hides it here.
    header: Item { width: list.width; height: root.t.sp(root.inThread ? 12 : 22) }

    delegate: MessageItem {
      required property var modelData
      width: list.width
      app: root.app
      win: root.win
      ws: root.ws
      row: modelData
      conv: root.conv
      inThread: root.inThread
      ctx: root.ctx
    }

    // Visually above the oldest message (the list grows upward).
    footer: Item {
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

    // Pictures and unfurls grow after loading: stay on the newest message.
    onContentHeightChanged: if (root.stick && !root.inThread) Qt.callLater(root.settle)
    // Any scroll away from the newest message lets go of it; back down there holds it again.
    onContentYChanged: {
      root.maybeLoad()
      if (!root._auto && root.scrolling) root.stick = root.nearNewest()
    }
    onMovementEnded: root.stick = root.nearNewest()
    // Only notices the wheel / touchpad: a blocking handler would take the
    // event from the list, which then doesn't scroll at all.
    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      blocking: false
      target: null
      onWheel: wheelOff.restart()
    }
    Timer { id: wheelOff; interval: 400; onTriggered: root.stick = root.nearNewest() }
    onHeightChanged: root.maybeLoad()
  }

  function maybeLoad() {
    if (root.inThread || !root.ws || root.loading || root.atStart) return
    if (list.visibleArea.yPosition < 0.08) root.ws.loadOlder(root.conv)
  }

  readonly property bool scrolledUp: list.visibleArea.heightRatio < 1 && (1 - list.visibleArea.yPosition - list.visibleArea.heightRatio) * list.contentHeight > root.t.sp(120)
  readonly property bool detached: !!hist && !!hist.detached

  function toBottom() {
    if (root.detached) root.ws.jumpToPresent(root.conv)
    root.stick = true
    root._auto = true
    list.positionViewAtBeginning()
    root._auto = false
  }

  function jump(ts) {
    for (var i = 0; i < root.rows.length; i++) {
      var r = root.rows[i]
      if (r.msg && r.msg.ts === ts || (r.run && r.run.some(function(x) { return x.ts === ts }))) {
        root.stick = false
        root._auto = true
        list.positionViewAtIndex(i, ListView.Center)
        root._auto = false
        return true
      }
    }
    return false
  }

  // On open with unread: the New line near the top.
  function showNew() {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].isNew) { list.positionViewAtIndex(i, ListView.End); return }
  }

  Connections {
    target: root.ws
    function onJumpTo(conv, ts) { if (conv === root.conv && !root.inThread) Qt.callLater(function() { root.jump(ts) }) }
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
