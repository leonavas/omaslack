import QtQuick
import QtQuick.Window
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Slack's image viewer: the picture over a dark backdrop, fit to the window
// (never enlarged), zoom with the buttons, the wheel, a pinch or + - 0, drag
// to pan when it's bigger than the window. The original is fetched with the
// session; the thumbnail stands in meanwhile. The top bar has the name, who
// posted it where (when known) and open / download / copy link / close.
// A video plays here instead (MediaView, expanded), from where the message
// left it (the file's `startAt`, `autoPlay`).
Item {
  id: v
  property var app: Reg.service
  property var ws
  property var file: null
  signal closed()
  readonly property var t: app.theme

  // The backdrop stays dark in light themes too, like Slack's.
  readonly property color backdrop: t.mix(t.bgDarker, "#000000", t.dark ? 0.55 : 0.85)
  readonly property color ink: t.dark ? t.fgBright : "#f2f2f2"
  readonly property color inkDim: t.dark ? t.fgDim : "#a6a6a6"
  readonly property color glass: Qt.rgba(1, 1, 1, 0.12)

  property var prevFocus: null
  property bool started: false
  focus: true
  opacity: 0
  Component.onCompleted: {
    var w = v.Window.window
    v.prevFocus = w ? w.activeFocusItem : null
    v.forceActiveFocus()
    v.opacity = 1
    v.started = true
    v.load()
    v.loadMedia()
  }
  Behavior on opacity { NumberAnimation { duration: 120 } }

  function close() {
    var f = v.prevFocus
    v.prevFocus = null
    try { if (f && f.visible) f.forceActiveFocus() } catch (e) {}
    v.closed()
  }

  // ---------------------------------------------------------------- sources
  // Files on *.slack.com need the session (fetched into the cache); public
  // URLs (external files, attachments, photos) load directly.
  function slackHosted(url) {
    var m = String(url || "").match(/^https?:\/\/([^\/:?#]+)/i)
    if (!m) return false
    var h = m[1].toLowerCase()
    return h === "slack.com" || /\.slack\.com$/.test(h)
  }
  readonly property string fullUrl: file ? (file.full || file.thumb || "") : ""
  readonly property string thumbUrl: file && file.thumb && file.thumb !== fullUrl ? file.thumb : ""
  readonly property bool direct: !!file && (file.external === true || !slackHosted(fullUrl))
  property string fetched: ""
  property bool fetchFailed: false
  readonly property string fullSrc: {
    if (!fullUrl) return ""
    if (direct) return fullUrl
    var local = ws ? ws.localFile(fullUrl) : ""
    return local ? "file://" + local : (fetched ? "file://" + fetched : "")
  }
  readonly property string thumbSrc: {
    if (!thumbUrl) return ""
    if (file.external === true || !slackHosted(thumbUrl)) return thumbUrl
    var local = ws ? ws.localFile(thumbUrl) : ""
    return local ? "file://" + local : ""
  }
  readonly property bool video: !!file && U.mediaKind(file) === "video" && app.canPlayMedia
  readonly property var media: mediaLoader.item
  // MediaView by URL: it can't compile without Qt Multimedia.
  function loadMedia() {
    if (!v.video) { mediaLoader.source = ""; return }
    mediaLoader.setSource(Qt.resolvedUrl("MediaView.qml"), { app: v.app, ws: v.ws, file: v.file, expanded: true,
                                                             startAt: v.file.startAt || 0, autoPlay: !!v.file.autoPlay })
  }
  readonly property bool animated: !!file && (file.mimetype === "image/gif" || /\.gif($|\?)/i.test(file.name || fullUrl))

  onFileChanged: if (v.started) { v.load(); v.loadMedia() }
  function load() {
    v.fetched = ""
    v.fetchFailed = false
    v.fitMode = true
    v.panX = 0
    v.panY = 0
    if (!v.file || v.video || v.direct || !v.fullUrl || !v.ws) return
    if (v.ws.localFile(v.fullUrl)) return
    var url = v.fullUrl
    v.ws.fetchFile(url, (v.file.id ? v.file.id + "-" : "") + (v.file.name || "image"), function(path) {
      try {
        if (v.fullUrl !== url) return
        if (path) v.fetched = path
        else v.fetchFailed = true
      } catch (e) {}   // closed meanwhile
    })
  }

  readonly property var full: fullLoader.item
  readonly property bool fullReady: !!full && full.status === Image.Ready
  readonly property bool fullError: v.fetchFailed || (!!full && full.status === Image.Error)
  readonly property bool thumbReady: thumbImg.status === Image.Ready

  // ---------------------------------------------------------------- geometry
  // (The pictures stretch to a box already in their aspect, so their
  // implicit size stays the natural one.)
  readonly property real natW: fullReady ? full.implicitWidth : (file && file.w > 0 ? file.w : (thumbReady ? thumbImg.implicitWidth : 0))
  readonly property real natH: fullReady ? full.implicitHeight : (file && file.h > 0 ? file.h : (thumbReady ? thumbImg.implicitHeight : 0))
  // A thumbnail stands for a bigger original: let it fill the window meanwhile.
  readonly property bool provisional: !fullReady && !fullError && !!file && (file.w >= 480 || file.h >= 480)
  readonly property real fitScale: natW > 0 && natH > 0 && stage.width > 0 ? Math.min(provisional ? 1e6 : 1, stage.width / natW, stage.height / natH) : 1
  property bool fitMode: true
  property real zoom: 1
  property real panX: 0
  property real panY: 0
  readonly property real scale2: fitMode ? fitScale : zoom
  readonly property real minZoom: Math.min(fitScale, 1)
  readonly property real maxZoom: Math.max(8, fitScale * 2)
  readonly property bool canZoom: natW > 0 && (fullReady || fullError && thumbReady)
  readonly property bool pannable: natW * scale2 > view.width + 0.5 || natH * scale2 > view.height + 0.5

  onFitScaleChanged: if (v.fitMode) { v.panX = 0; v.panY = 0 } else v.clampPan()

  function zoomBy(f, px, py) {
    if (!v.canZoom) return
    if (px === undefined) { px = view.width / 2; py = view.height / 2 }
    var s0 = v.scale2
    var s1 = Math.max(v.minZoom, Math.min(v.maxZoom, s0 * f))
    if (Math.abs(s1 - s0) < 1e-4) return
    if (s1 <= v.fitScale + 1e-4 && f < 1) { v.fit(); return }
    // Keep the point under the cursor where it is.
    var cx = view.width / 2 + v.panX, cy = view.height / 2 + v.panY
    var k = s1 / s0
    v.zoom = s1
    v.fitMode = false
    v.panX = px - (px - cx) * k - view.width / 2
    v.panY = py - (py - cy) * k - view.height / 2
    v.clampPan()
  }
  function zoomTo(s) { v.zoomBy(s / v.scale2) }
  function fit() { v.fitMode = true; v.panX = 0; v.panY = 0 }
  function clampPan() {
    var mx = Math.max(0, (v.natW * v.scale2 - view.width) / 2)
    var my = Math.max(0, (v.natH * v.scale2 - view.height) / 2)
    v.panX = Math.max(-mx, Math.min(mx, v.panX))
    v.panY = Math.max(-my, Math.min(my, v.panY))
  }
  function panBy(dx, dy) { v.panX += dx; v.panY += dy; v.clampPan() }

  // ---------------------------------------------------------------- actions
  function say(text) { if (v.ws) v.ws.say(text); else if (v.app.window) v.app.window.toast(text) }
  function openApp() { if (v.ws && v.file) v.ws.openFile(v.file) }
  function download() { if (v.ws && v.file && v.file.download) v.ws.saveFile(v.file) }
  function copyLink() {
    if (!v.file || !v.file.permalink) return
    v.app.copy(v.file.permalink)
    v.say(v.app.tr("Link copied", "Link copiado"))
  }

  Keys.onPressed: event => {
    var k = event.key
    if (v.media && !event.modifiers && v.mediaKey(k)) { event.accepted = true; return }
    if (k === Qt.Key_Escape) v.close()
    else if (k === Qt.Key_Plus || k === Qt.Key_Equal) v.zoomBy(1.25)
    else if (k === Qt.Key_Minus || k === Qt.Key_Underscore) v.zoomBy(0.8)
    else if (k === Qt.Key_0) v.fit()
    else if (k === Qt.Key_1) v.zoomTo(1)
    else if (k === Qt.Key_Left) v.panBy(v.t.sp(80), 0)
    else if (k === Qt.Key_Right) v.panBy(-v.t.sp(80), 0)
    else if (k === Qt.Key_Up) v.panBy(0, v.t.sp(80))
    else if (k === Qt.Key_Down) v.panBy(0, -v.t.sp(80))
    else if (k === Qt.Key_O && !event.modifiers) v.openApp()
    else if (k === Qt.Key_D && !event.modifiers) v.download()
    else return
    event.accepted = true
  }

  // A video's keys: Space / K play or pause, ← → 5 s, J L 10 s, M mute.
  function mediaKey(k) {
    var m = v.media
    if (k === Qt.Key_Space || k === Qt.Key_K) m.toggle()
    else if (k === Qt.Key_Left || k === Qt.Key_J) m.seek(m.position - (k === Qt.Key_J ? 10000 : 5000))
    else if (k === Qt.Key_Right || k === Qt.Key_L) m.seek(m.position + (k === Qt.Key_L ? 10000 : 5000))
    else if (k === Qt.Key_M) m.muted = !m.muted
    else return false
    return true
  }

  // ---------------------------------------------------------------- backdrop
  Rectangle {
    anchors.fill: parent
    color: v.t.alpha(v.backdrop, 0.96)
  }

  // ---------------------------------------------------------------- picture
  // The area under the bar (a zoomed picture uses all of it); the fitted
  // picture keeps a margin inside it.
  Item {
    id: view
    anchors.top: bar.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    onWidthChanged: if (!v.fitMode) v.clampPan()
    onHeightChanged: if (!v.fitMode) v.clampPan()

    Item {
      id: stage
      anchors.fill: parent
      anchors.margins: v.t.sp(24)
    }

    Item {
      id: picture
      readonly property real w: Math.max(1, v.natW * v.scale2)
      readonly property real h: Math.max(1, v.natH * v.scale2)
      x: (view.width - w) / 2 + v.panX
      y: (view.height - h) / 2 + v.panY
      width: w
      height: h
      visible: v.natW > 0 && !v.video

      Image {
        id: thumbImg
        anchors.fill: parent
        source: v.thumbSrc
        visible: !v.fullReady
        asynchronous: true
        fillMode: Image.Stretch
        smooth: true
      }
      Loader {
        id: fullLoader
        anchors.fill: parent
        active: v.fullSrc !== ""
        sourceComponent: v.animated ? animC : stillC
      }
    }
  }
  Component {
    id: stillC
    Image {
      source: v.fullSrc
      asynchronous: true
      fillMode: Image.Stretch
      smooth: true
      mipmap: true
      sourceSize: Qt.size(6000, 6000)
    }
  }
  Component {
    id: animC
    AnimatedImage {
      source: v.fullSrc
      fillMode: Image.Stretch
      smooth: true
      playing: v.app.onScreen
    }
  }

  // Loading / failure, over the picture.
  Rectangle {
    readonly property bool loading: !v.fullReady && !v.fullError && v.fullUrl !== ""
    visible: !v.video && (loading || v.fullError)
    anchors.horizontalCenter: view.horizontalCenter
    y: view.y + (v.natW > 0 ? Math.min(view.height - v.t.sp(8), picture.y + picture.height) - height - v.t.sp(16) : (view.height - height) / 2)
    width: stateRow.implicitWidth + v.t.sp(28)
    height: v.t.sp(34)
    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.62)
    Row {
      id: stateRow
      anchors.centerIn: parent
      spacing: v.t.sp(8)
      Glyph {
        id: spin
        app: v.app
        anchors.verticalCenter: parent.verticalCenter
        icon: v.fullError ? "󰋮" : "󰝲"
        color: v.fullError ? v.t.red : v.ink
        size: v.t.fsIcon
        RotationAnimator on rotation { running: spin.visible && !v.fullError && parent.parent.visible && v.app.onScreen; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: v.fullError ? v.app.tr("Couldn't load the full image", "Não foi possível carregar a imagem original") : v.app.tr("Loading full size…", "Carregando tamanho original…")
        color: v.ink
        font.family: v.t.font
        font.pixelSize: v.t.fsSmall
      }
    }
  }

  // Mouse: wheel zooms around the cursor, drag pans, a click off the
  // picture closes, a double click toggles fit / 100%.
  MouseArea {
    id: ma
    anchors.fill: parent
    anchors.topMargin: bar.height
    enabled: !v.video
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: v.pannable ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
    property real sx: 0
    property real sy: 0
    property real spx: 0
    property real spy: 0
    property bool moved: false
    function inPicture(mx, my) {
      var p = ma.mapToItem(picture, mx, my)
      return picture.visible && p.x >= 0 && p.x <= picture.width && p.y >= 0 && p.y <= picture.height
    }
    onPressed: mouse => { sx = mouse.x; sy = mouse.y; spx = v.panX; spy = v.panY; moved = false }
    onPositionChanged: mouse => {
      if (!pressed) return
      if (Math.abs(mouse.x - sx) + Math.abs(mouse.y - sy) > 4) moved = true
      if (moved && v.pannable) { v.panX = spx + mouse.x - sx; v.panY = spy + mouse.y - sy; v.clampPan() }
    }
    onClicked: mouse => { if (!moved && !inPicture(mouse.x, mouse.y)) v.close() }
    onDoubleClicked: mouse => {
      if (!inPicture(mouse.x, mouse.y)) return
      var p = ma.mapToItem(view, mouse.x, mouse.y)
      if (v.fitMode) v.zoomBy(Math.max(1, v.fitScale * 2) / v.scale2, p.x, p.y)
      else v.fit()
    }
    onWheel: wheel => {
      var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
      if (d === 0) return
      var p = ma.mapToItem(view, wheel.x, wheel.y)
      v.zoomBy(Math.pow(1.0018, d), p.x, p.y)
    }
  }

  // The video, over the area under the bar (its own clicks and controls).
  Loader {
    id: mediaLoader
    anchors.fill: view
  }

  PinchHandler {
    target: null
    enabled: !v.video
    onScaleChanged: delta => {
      var p = v.mapToItem(view, centroid.position.x, centroid.position.y)
      v.zoomBy(delta, p.x, p.y)
    }
  }

  // ---------------------------------------------------------------- top bar
  Rectangle {
    id: bar
    width: parent.width
    height: v.t.sp(60)
    color: Qt.rgba(0, 0, 0, 0.28)
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => {} }

    readonly property string author: {
      if (!v.file) return ""
      if (v.file.user && v.ws) return v.ws.userName(v.file.user) || ""
      return v.file.userName || ""
    }
    readonly property string where: v.file && v.file.conv && v.ws ? v.ws.convLabel(v.file.conv) : ""
    readonly property string subtitle: {
      var f = v.file
      if (!f) return ""
      var parts = []
      if (bar.author) parts.push(bar.author)
      if (bar.where) {
        var c = v.ws.conv(f.conv)
        parts.push(c && (c.kind === "channel" || c.kind === "private") ? v.app.tr("in #", "em #") + bar.where : bar.where)
      }
      var ts = f.ts || (f.created ? String(f.created) : "")
      if (ts) {
        var w = U.whenLabel(ts, v.app.lang, v.app.clock24)
        parts.push(w.charAt(0).toUpperCase() + w.slice(1))
      }
      if (!parts.length) {
        var kind = f.prettyType || (f.filetype ? String(f.filetype).toUpperCase() : "")
        if (kind) parts.push(kind)
        if (f.size) parts.push(U.humanSize(f.size, v.app.lang))
      }
      if (v.fullReady) parts.push(Math.round(v.natW) + " × " + Math.round(v.natH))
      return parts.join("  ·  ")
    }

    Avatar {
      id: who
      app: v.app
      ws: v.ws
      visible: !!v.file && !!v.file.user && !!v.ws
      user: v.file && v.file.user ? v.file.user : ""
      size: v.t.sp(36)
      ring: "transparent"
      x: v.t.sp(18)
      anchors.verticalCenter: parent.verticalCenter
    }
    Rectangle {
      id: fileIcon
      visible: !who.visible
      x: v.t.sp(18)
      anchors.verticalCenter: parent.verticalCenter
      width: v.t.sp(36)
      height: width
      radius: Math.max(6, v.t.radiusSmall)
      color: v.glass
      Glyph { app: v.app; anchors.centerIn: parent; icon: v.video ? "󰕧" : "󰋩"; size: v.t.fsTitle + 2; color: v.ink }
    }

    Column {
      anchors.left: who.visible ? who.right : fileIcon.right
      anchors.leftMargin: v.t.sp(12)
      anchors.right: tools.left
      anchors.rightMargin: v.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: v.t.sp(2)
      Text {
        width: parent.width
        elide: Text.ElideMiddle
        text: v.file ? (v.file.title || v.file.name || v.app.tr("image", "imagem")) : ""
        textFormat: Text.PlainText
        color: v.ink
        font.family: v.t.font
        font.pixelSize: v.t.fsText
        font.bold: true
      }
      Text {
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        text: bar.subtitle
        textFormat: Text.PlainText
        color: v.inkDim
        font.family: v.t.font
        font.pixelSize: v.t.fsSmall
      }
    }

    Row {
      id: tools
      anchors.right: parent.right
      anchors.rightMargin: v.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: v.t.sp(4)

      Rectangle {
        visible: !v.video
        anchors.verticalCenter: parent.verticalCenter
        width: zoomRow.implicitWidth + v.t.sp(8)
        height: v.t.sp(36)
        radius: Math.max(6, v.t.radiusSmall)
        color: Qt.rgba(1, 1, 1, 0.06)
        Row {
          id: zoomRow
          anchors.centerIn: parent
          IconButton {
            app: v.app; color: v.ink; hoverColor: v.glass; size: v.t.sp(30)
            icon: "󰛬"; tip: v.app.tr("Zoom out", "Diminuir zoom") + "  −"
            enabled2: v.canZoom && v.scale2 > v.minZoom + 1e-4
            onClicked: v.zoomBy(0.8)
          }
          Text {
            width: v.t.sp(50)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: v.canZoom ? Math.round(v.scale2 * 100) + "%" : "–"
            color: v.ink
            font.family: v.t.font
            font.pixelSize: v.t.fsSmall
            MouseArea { id: pctMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: v.zoomTo(1) }
            PanelToolTip { visible: pctMa.containsMouse; text: v.app.tr("Actual size", "Tamanho real") + "  1" }
          }
          IconButton {
            app: v.app; color: v.ink; hoverColor: v.glass; size: v.t.sp(30)
            icon: "󰛭"; tip: v.app.tr("Zoom in", "Aumentar zoom") + "  +"
            enabled2: v.canZoom && v.scale2 < v.maxZoom - 1e-4
            onClicked: v.zoomBy(1.25)
          }
          IconButton {
            app: v.app; color: v.fitMode ? v.inkDim : v.ink; hoverColor: v.glass; size: v.t.sp(30)
            icon: "󱣵"; tip: v.app.tr("Fit to window", "Ajustar à janela") + "  0"
            onClicked: v.fit()
          }
        }
      }

      Item { visible: !v.video; width: v.t.sp(8); height: 1 }

      IconButton {
        app: v.app; color: v.ink; hoverColor: v.glass; size: v.t.sp(36); iconSize: v.t.fsIcon + 2
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰏌"; tip: v.app.tr("Open in default app", "Abrir no app padrão") + "  O"
        visible: !!v.file && !!(v.file.download || v.file.full)
        onClicked: v.openApp()
      }
      IconButton {
        app: v.app; color: v.ink; hoverColor: v.glass; size: v.t.sp(36); iconSize: v.t.fsIcon + 2
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰇚"; tip: v.app.tr("Download", "Baixar") + "  D"
        visible: !!v.file && !!v.file.download
        onClicked: v.download()
      }
      IconButton {
        app: v.app; color: v.ink; hoverColor: v.glass; size: v.t.sp(36); iconSize: v.t.fsIcon + 2
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰌷"; tip: v.app.tr("Copy link to file", "Copiar link do arquivo")
        visible: !!v.file && !!v.file.permalink
        onClicked: v.copyLink()
      }

      Rectangle { width: 1; height: v.t.sp(22); color: v.glass; anchors.verticalCenter: parent.verticalCenter }

      IconButton {
        app: v.app; color: v.ink; hoverColor: v.glass; size: v.t.sp(36); iconSize: v.t.fsIcon + 4
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰅖"; tip: v.app.tr("Close", "Fechar") + "  Esc"
        onClicked: v.close()
      }
    }
  }
}
