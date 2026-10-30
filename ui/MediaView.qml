import QtQuick
import QtMultimedia
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A video or a sound of a message, played right there as Slack does. A
// video: its cover (a blurred frame of its first second, Workspace.videoCover;
// else Slack's poster) with ▶ and the time; hovered, the controls (seek bar,
// play, time, volume, speed) and, on top, expand and more. `expanded` (in
// the viewer): it fills its box, the controls always there. A sound: a card
// with play, the name, a seek bar and the time. It plays as it comes
// (Workspace.streamUrl), or from the cache when it's already there. Loaded by URL
// (Service.canPlayMedia): without Qt Multimedia this file never compiles.
Item {
  id: mp
  property var app: Reg.service
  property var win: app.window
  property var ws
  property var file: null
  property string user: ""
  property string conv: ""
  property string ts: ""
  property bool expanded: false
  property int maxW: t.sp(480)
  property int maxH: t.sp(360)
  // Where the first play begins (ms) and whether it starts by itself: the
  // viewer, opened from a video already playing in the message.
  property real startAt: 0
  property bool autoPlay: false
  readonly property var t: app.theme

  readonly property bool audio: !!file && U.mediaKind(file) === "audio"
  readonly property string url: ws && file ? ws.fileUrl(file) : ""
  readonly property string local: ws && url ? ws.localFile(url) : ""
  property string src: ""          // what the player plays, fixed at the first play
  property bool wanted: false      // play asked, its stream on the way
  property bool starting: false    // play asked, no frame moving yet (the player may say stopped meanwhile)
  property bool started: false     // the player exists (from the first play)
  property bool rolled: false      // a frame was shown: the poster goes
  property real pendingSeek: -1

  readonly property var player: playerLoader.item ? playerLoader.item.player : null
  readonly property bool playing: !!player && player.playbackState === MediaPlayer.PlayingState
  readonly property real duration: player && player.duration > 0 ? player.duration : (file && file.duration) || 0
  readonly property real position: player ? player.position : mp.startAt
  property real rate: 1
  property bool muted: false
  property real volume: 1

  readonly property real ratio: file && file.posterW > 0 && file.posterH > 0 ? file.posterW / file.posterH
                              : poster.status === Image.Ready && poster.implicitHeight > 0 ? poster.implicitWidth / poster.implicitHeight : 16 / 9
  implicitWidth: audio ? Math.min(maxW, t.sp(420)) : Math.min(maxW, maxH * ratio)
  implicitHeight: audio ? t.sp(64) : implicitWidth / ratio
  width: implicitWidth
  height: implicitHeight

  Component.onCompleted: {
    if (!mp.audio && mp.file && mp.ws) Qt.callLater(function() {
      try {
        if (mp.ws.localFiles["cover:" + mp.url] === "") mp.fetchPoster()   // no cover to be had
        else mp.ws.videoCover(mp.file, function(path) { try { if (!path) mp.fetchPoster() } catch (e) {} })
      } catch (e) {}
    })
    if (mp.autoPlay) Qt.callLater(mp.play)
  }

  function fetchPoster() {
    if (mp.file.poster && !mp.ws.localFile(mp.file.poster)) mp.ws.fetchFile(mp.file.poster, (mp.file.id || "video") + "-poster.jpg")
  }

  // ---------------------------------------------------------------- playing
  function clock(ms) {
    var s = Math.max(0, Math.floor((ms || 0) / 1000))
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (sec < 10 ? "0" : "") + sec
  }
  // A path as a file: URL (a "#" or "?" in a name stays part of it).
  function fileUrlOf(path) { return "file://" + String(path).split("/").map(encodeURIComponent).join("/") }

  function play() {
    if (mp.playing) return
    if (!mp.src) {
      if (mp.local) mp.src = mp.fileUrlOf(mp.local)
      else {
        if (mp.wanted || !mp.url) return
        mp.wanted = true
        mp.ws.streamUrl(mp.file, function(u) {
          try {
            mp.wanted = false
            if (!u) { mp.ws.say(mp.app.tr("Couldn't load the file", "Não foi possível carregar o arquivo")); return }
            mp.src = u
            mp.play()
          } catch (e) {}     // gone meanwhile
        })
        return
      }
    }
    mp.started = true
    if (!mp.player) return
    if (!mp.rolled && mp.startAt > 0) mp.pendingSeek = mp.startAt
    mp.starting = true
    mp.player.play()
  }
  function pause() { mp.starting = false; if (mp.player) mp.player.pause() }
  // While it starts, a click stops it starting.
  function toggle() { if (mp.playing || mp.starting) mp.pause(); else mp.play() }
  function seek(ms) {
    if (!mp.player) { mp.startAt = Math.max(0, ms); return }
    mp.player.position = Math.max(0, Math.min(mp.duration, ms))
  }
  // Asked to play, and not playing yet: the stream starting, or waiting for more.
  readonly property bool loading: mp.wanted || mp.starting || !!player && player.playbackState === MediaPlayer.PlayingState
                                  && (player.mediaStatus === MediaPlayer.LoadingMedia || player.mediaStatus === MediaPlayer.StalledMedia
                                      || player.mediaStatus === MediaPlayer.BufferingMedia && !mp.rolled)

  // The viewer, from where this one is (and this one pauses).
  function expand() {
    if (!mp.win) return
    var at = mp.position, was = mp.playing
    mp.pause()
    mp.win.viewImage(Object.assign({}, mp.file, { user: mp.user, conv: mp.conv, ts: mp.ts, startAt: at, autoPlay: was }))
  }

  function menuItems() {
    var f = mp.file, ws = mp.ws, items = []
    items.push({ label: mp.app.tr("Open in default app", "Abrir no app padrão"), icon: "󰏌", action: function() { ws.openFile(f) } })
    if (f.download) items.push({ label: mp.app.tr("Download", "Baixar"), icon: "󰇚", action: function() { ws.saveFile(f) } })
    if (f.permalink) items.push({ label: mp.app.tr("Copy link to file", "Copiar link do arquivo"), icon: "󰌷",
                                  action: function() { mp.app.copy(f.permalink); ws.say(mp.app.tr("Link copied", "Link copiado")) } })
    return items
  }
  function openMenu(item, items) {
    if (!mp.win) return
    var p = item.mapToItem(mp.win.contentItem, 0, item.height + 4)
    mp.win.menu(items, p.x, p.y)
  }
  function speedMenu(item) {
    var rates = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    mp.openMenu(item, rates.map(function(r) {
      return { label: String(r).replace(".", mp.app.lang === "pt-BR" ? "," : ".") + "x", checked: Math.abs(mp.rate - r) < 0.01, action: function() { mp.rate = r } }
    }))
  }

  HoverHandler { id: hover }
  property bool seeking: false
  readonly property bool controlsShown: mp.expanded || hover.hovered || mp.seeking

  // ---------------------------------------------------------------- the seek bar
  component SeekBar: Item {
    id: sb
    property var m
    implicitHeight: sb.m.t.sp(14)
    readonly property real frac: sb.m.duration > 0 ? Math.min(1, sb.m.position / sb.m.duration) : 0
    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: seekMa.containsMouse || seekMa.pressed ? sb.m.t.sp(6) : sb.m.t.sp(4)
      radius: height / 2
      color: sb.m.audio ? sb.m.t.alpha(sb.m.t.fg, 0.16) : Qt.rgba(1, 1, 1, 0.3)
      Rectangle {
        width: Math.max(height, parent.width * sb.frac)
        height: parent.height
        radius: parent.radius
        color: sb.m.t.blue
        visible: sb.frac > 0 || sb.m.started
      }
    }
    Rectangle {
      visible: (seekMa.containsMouse || seekMa.pressed) && sb.m.duration > 0
      x: track.width * sb.frac - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: sb.m.t.sp(12); height: width; radius: width / 2
      color: sb.m.audio ? sb.m.t.fgBright : "white"
    }
    MouseArea {
      id: seekMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: sb.m.duration > 0
      function at(x) { return Math.max(0, Math.min(1, x / width)) * sb.m.duration }
      onPressedChanged: sb.m.seeking = pressed
      onPressed: mouse => sb.m.seek(at(mouse.x))
      onPositionChanged: mouse => { if (pressed) sb.m.seek(at(mouse.x)) }
    }
  }

  // A round dark button over the video.
  component OverButton: IconButton {
    color: "white"
    hoverColor: Qt.rgba(1, 1, 1, 0.14)
    size: t.sp(30)
    iconSize: t.fsIcon + 1
  }

  // ---------------------------------------------------------------- a sound
  Rectangle {
    visible: mp.audio
    anchors.fill: parent
    radius: Math.max(8, mp.t.radiusCard)
    color: hover.hovered ? mp.t.hover : mp.t.alpha(mp.t.fg, 0.03)
    border.width: 1
    border.color: mp.t.lineStrong

    Rectangle {
      id: bigPlay
      x: mp.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      width: mp.t.sp(40); height: width; radius: width / 2
      color: bigPlayMa.containsMouse ? Qt.lighter(mp.t.blue, 1.15) : mp.t.blue
      Glyph {
        app: mp.app
        anchors.centerIn: parent
        inkCentered: true
        visible: !mp.loading
        icon: mp.playing ? "󰏤" : "󰐊"
        size: mp.t.fsTitle + 4
        color: "white"
      }
      Spinner { app: mp.app; anchors.centerIn: parent; visible: mp.loading; size: mp.t.sp(18); color: "white" }
      MouseArea { id: bigPlayMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mp.toggle() }
      PanelToolTip { visible: bigPlayMa.containsMouse; text: mp.playing ? mp.app.tr("Pause", "Pausar") : mp.app.tr("Play", "Reproduzir") }
    }
    Column {
      anchors.left: bigPlay.right
      anchors.leftMargin: mp.t.sp(12)
      anchors.right: audioTools.left
      anchors.rightMargin: mp.t.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: mp.t.sp(2)
      Text {
        width: parent.width
        text: mp.file ? (mp.file.title || mp.file.name) : ""
        textFormat: Text.PlainText
        color: mp.t.fgBright
        font.family: mp.t.font
        font.pixelSize: mp.t.fsText - 1
        font.bold: true
        elide: Text.ElideMiddle
      }
      Row {
        width: parent.width
        spacing: mp.t.sp(8)
        SeekBar {
          m: mp
          visible: mp.audio
          width: parent.width - audioTime.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          id: audioTime
          anchors.verticalCenter: parent.verticalCenter
          text: mp.loading ? mp.app.tr("Loading…", "Carregando…")
                          : mp.clock(mp.position) + (mp.duration > 0 ? " / " + mp.clock(mp.duration) : "")
          textFormat: Text.PlainText
          color: mp.t.fgDim
          font.family: mp.t.font
          font.pixelSize: mp.t.fsSmall
          font.features: { "tnum": 1 }
        }
      }
    }
    Row {
      id: audioTools
      anchors.right: parent.right
      anchors.rightMargin: mp.t.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      IconButton {
        id: audioRate
        app: mp.app
        label: String(mp.rate).replace(".", mp.app.lang === "pt-BR" ? "," : ".") + "x"
        tip: mp.app.tr("Playback speed", "Velocidade de reprodução")
        onClicked: mp.speedMenu(audioRate)
      }
      IconButton {
        id: audioMore
        app: mp.app
        visible: hover.hovered
        icon: "󰇙"
        tip: mp.app.tr("More actions", "Mais ações")
        onClicked: mp.openMenu(audioMore, mp.menuItems())
      }
    }
  }

  // ---------------------------------------------------------------- a video
  Clip {
    visible: !mp.audio
    anchors.fill: parent
    radius: mp.expanded ? 0 : Math.max(8, mp.t.radiusCard)
    color: mp.expanded ? "transparent" : "black"
    borderWidth: mp.expanded ? 0 : 1
    borderColor: mp.t.line

    Item {
      width: parent.width
      height: parent.height

      // The player, made at the first play (a list of messages makes none); a
      // sound plays from here too, its card drawn instead of this.
      Loader {
        id: playerLoader
        anchors.fill: parent
        active: mp.started
        sourceComponent: Item {
          property alias player: mediaPlayer
          VideoOutput {
            id: videoOut
            anchors.fill: parent
            visible: !mp.audio && mp.rolled
            fillMode: VideoOutput.PreserveAspectFit
          }
          MediaPlayer {
            id: mediaPlayer
            source: mp.src
            videoOutput: mp.audio ? null : videoOut
            audioOutput: AudioOutput { volume: mp.volume; muted: mp.muted }
            playbackRate: mp.rate
            onPositionChanged: {
              if (mediaPlayer.position > 0 && !mp.rolled) mp.rolled = true
              if (mediaPlayer.playbackState === MediaPlayer.PlayingState) mp.starting = false
            }
            onMediaStatusChanged: {
              if (mediaStatus === MediaPlayer.EndOfMedia || mediaStatus === MediaPlayer.InvalidMedia) mp.starting = false
              if (mp.pendingSeek >= 0 && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)) {
                if (seekable) position = mp.pendingSeek
                mp.pendingSeek = -1
              }
            }
            onErrorOccurred: (error, errorString) => {
              mp.starting = false
              console.warn("omaslack: media:", errorString)
              mp.ws.say(mp.app.tr("Couldn't play it here: ", "Não deu para tocar aqui: ") + errorString)
            }
          }
        }
      }

      Image {
        id: poster
        anchors.fill: parent
        visible: !mp.rolled && status === Image.Ready
        readonly property string cover: mp.ws && mp.url ? mp.ws.localFile("cover:" + mp.url) : ""
        readonly property string local: cover || (mp.file && mp.file.poster && mp.ws ? mp.ws.localFile(mp.file.poster) : "")
        source: local ? "file://" + local : ""
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: mp.expanded ? 1920 : mp.width * 2
        smooth: true
      }
      Glyph {
        app: mp.app
        anchors.centerIn: parent
        visible: !mp.rolled && poster.status !== Image.Ready
        icon: "󰕧"
        size: mp.t.sp(40)
        color: Qt.rgba(1, 1, 1, 0.35)
      }

      // A click plays or pauses; a double click (in the message) expands.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: mp.toggle()
        onDoubleClicked: if (!mp.expanded) mp.expand()
      }

      // Not hovered and not playing: ▶ and the time in a pill.
      Rectangle {
        visible: !mp.controlsShown && (!mp.playing || mp.loading)
        x: mp.t.sp(12)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: mp.t.sp(12)
        width: pillRow.implicitWidth + mp.t.sp(20)
        height: mp.t.sp(32)
        radius: Math.max(6, mp.t.radiusSmall)
        color: Qt.rgba(0, 0, 0, 0.6)
        Row {
          id: pillRow
          anchors.centerIn: parent
          spacing: mp.t.sp(8)
          Glyph { app: mp.app; visible: !mp.loading; icon: "󰐊"; size: mp.t.fsTitle + 2; color: "white"; anchors.verticalCenter: parent.verticalCenter }
          Spinner { app: mp.app; visible: mp.loading; size: mp.t.sp(14); color: "white"; anchors.verticalCenter: parent.verticalCenter }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: mp.loading ? mp.app.tr("Loading…", "Carregando…")
                            : mp.clock(mp.rolled || !mp.duration ? mp.position : mp.duration)
            textFormat: Text.PlainText
            color: "white"
            font.family: mp.t.font
            font.pixelSize: mp.t.fsText - 1
            font.features: { "tnum": 1 }
          }
        }
      }

      // Hovered (in the message): expand and more, on top.
      Rectangle {
        visible: !mp.expanded && mp.controlsShown
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: mp.t.sp(10)
        width: topRow.implicitWidth + mp.t.sp(6)
        height: mp.t.sp(36)
        radius: Math.max(6, mp.t.radiusSmall)
        color: Qt.rgba(0, 0, 0, 0.6)
        Row {
          id: topRow
          anchors.centerIn: parent
          spacing: mp.t.sp(2)
          OverButton { app: mp.app; icon: "󰊓"; tip: mp.app.tr("Expand", "Expandir"); onClicked: mp.expand() }
          OverButton { id: videoMore; app: mp.app; icon: "󰇙"; tip: mp.app.tr("More actions", "Mais ações"); onClicked: mp.openMenu(videoMore, mp.menuItems()) }
        }
      }

      // The controls: the seek bar over play, time, volume and speed.
      Rectangle {
        visible: mp.controlsShown
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: mp.expanded ? 0 : mp.t.sp(10)
        height: ctlCol.implicitHeight + mp.t.sp(mp.expanded ? 20 : 12)
        radius: mp.expanded ? 0 : Math.max(6, mp.t.radiusSmall)
        color: mp.expanded ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(0, 0, 0, 0.6)
        MouseArea { anchors.fill: parent }   // not a click on the video
        Column {
          id: ctlCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: mp.t.sp(mp.expanded ? 16 : 10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: mp.t.sp(2)
          SeekBar { m: mp; width: parent.width }
          Item {
            width: parent.width
            height: mp.t.sp(32)
            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: mp.t.sp(4)
              Item {
                width: mp.t.sp(30); height: width
                anchors.verticalCenter: parent.verticalCenter
                OverButton {
                  app: mp.app
                  anchors.fill: parent
                  visible: !mp.loading
                  icon: mp.playing ? "󰏤" : "󰐊"
                  iconSize: mp.t.fsTitle + 4
                  tip: mp.playing ? mp.app.tr("Pause", "Pausar") : mp.app.tr("Play", "Reproduzir")
                  onClicked: mp.toggle()
                }
                Spinner { app: mp.app; anchors.centerIn: parent; visible: mp.loading; size: mp.t.sp(16); color: "white" }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: mp.loading ? mp.app.tr("Loading…", "Carregando…")
                                : mp.clock(mp.position) + (mp.expanded && mp.duration > 0 ? " / " + mp.clock(mp.duration) : "")
                textFormat: Text.PlainText
                color: "white"
                font.family: mp.t.font
                font.pixelSize: mp.t.fsText - 1
                font.features: { "tnum": 1 }
              }
              OverButton {
                app: mp.app
                anchors.verticalCenter: parent.verticalCenter
                icon: mp.muted || mp.volume === 0 ? "󰖁" : "󰕾"
                tip: (mp.muted ? mp.app.tr("Unmute", "Ativar som") : mp.app.tr("Mute", "Silenciar")) + "  M"
                onClicked: mp.muted = !mp.muted
                WheelHandler { onWheel: event => { mp.volume = U.clamp(mp.volume + (event.angleDelta.y > 0 ? 0.1 : -0.1), 0, 1); mp.muted = false } }
              }
              // The volume, beside its button (in the viewer).
              Item {
                visible: mp.expanded
                width: mp.t.sp(80); height: mp.t.sp(30)
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width; height: mp.t.sp(4); radius: height / 2
                  color: Qt.rgba(1, 1, 1, 0.3)
                  Rectangle { width: parent.width * (mp.muted ? 0 : mp.volume); height: parent.height; radius: parent.radius; color: "white" }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  function set(x) { mp.volume = U.clamp(x / width, 0, 1); mp.muted = false }
                  onPressed: mouse => set(mouse.x)
                  onPositionChanged: mouse => { if (pressed) set(mouse.x) }
                }
              }
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: mp.t.sp(2)
              OverButton {
                app: mp.app
                id: videoRate
                icon: ""
                label: String(mp.rate).replace(".", mp.app.lang === "pt-BR" ? "," : ".") + "x  󰅀"
                tip: mp.app.tr("Playback speed", "Velocidade de reprodução")
                onClicked: mp.speedMenu(videoRate)
              }
              OverButton {
                app: mp.app
                id: viewerMore
                visible: mp.expanded
                icon: "󰇙"
                tip: mp.app.tr("More actions", "Mais ações")
                onClicked: mp.openMenu(viewerMore, mp.menuItems())
              }
            }
          }
        }
      }
    }
  }
}
