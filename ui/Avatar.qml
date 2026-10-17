import QtQuick
import Quickshell.Widgets
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A person's (or bot's) photo in Slack's rounded square, initials over a
// color of their own when there's none, and an optional presence dot. A
// photo seen before comes from disk (Service.photoFile), up at once. One on
// its way gets a moment before the initials stand in, and fades in over
// them if they did; a bigger one waits behind a smaller one of the same
// person already at hand, stretched, not behind initials.
Item {
  id: a
  property var app: Reg.service
  property var ws: null
  readonly property var t: app.theme
  property string user: ""
  property string url: ""
  property string name: ""
  property int size: t.avatar
  property bool showPresence: false
  property color ring: t.pane
  // A selected row's text color, for the presence dot (PresenceDot.ink).
  property color presenceInk: "transparent"
  property real round: 0.22
  property bool big: size > 48
  signal clicked()

  readonly property var u: ws && user ? ws.user(user) : null
  // "Slack" (its system notices): the logo on its own, as Slack draws it,
  // not the square photo its user has.
  readonly property bool slack: user === "USLACK"
  readonly property string src: slack ? Qt.resolvedUrl("../assets/slack.svg") : url !== "" ? url : (u ? (a.big ? (u.avatar192 || u.avatar || "") : (u.avatar || "")) : "")
  readonly property string label: name !== "" ? name : (u ? u.name : "")
  readonly property string photo: a.slack ? a.src : a.src !== "" ? (a.app.photoFile(a.src) || a.src) : ""
  // Another size of their photo already on disk, for while this one loads
  // (or if it doesn't come). Not an app's icon over its bot user's photo.
  readonly property string stand: {
    if (img.status !== Image.Loading && img.status !== Image.Error) return ""
    if (a.slack || !a.u || (a.url !== "" && [a.u.avatar, a.u.avatar192, a.u.avatar512, a.u.photo].indexOf(a.url) < 0)) return ""
    var sizes = [a.u.avatar192, a.u.avatar, a.u.avatar512]
    for (var i = 0; i < sizes.length; i++) {
      var f = sizes[i] && sizes[i] !== a.src ? a.app.photoFile(sizes[i], true) : ""
      if (f) return f
    }
    return ""
  }
  // Decoded at a step of a short ladder, not at its own size: nearby sizes
  // share one picture in Qt's cache, and a pane resizing doesn't load it
  // again. Up to 512, Slack's biggest.
  readonly property int px: {
    var want = a.size * 2
    var steps = [32, 48, 64, 96, 128, 192, 256, 384]
    for (var i = 0; i < steps.length; i++) if (steps[i] >= want) return steps[i]
    return 512
  }

  readonly property bool shown: img.status === Image.Ready || low.status === Image.Ready
  // On its way (or the person not known yet): a moment of nothing first.
  readonly property bool coming: !shown && (img.status === Image.Loading || (a.src === "" && a.user !== "" && !!a.ws && !a.u))
  // The moment ran out and the initials came up: the photo fades in over
  // them, and once it's in the next one gets its moment again.
  property bool late: false
  readonly property bool initialsUp: !shown ? (!coming || late) : (late && face.opacity < 1)

  width: size
  height: size

  Timer {
    interval: a.late ? 150 : 200
    running: a.late ? a.shown : a.coming
    onTriggered: a.late = !a.late
  }

  Clip {
    anchors.fill: parent
    radius: Math.round(a.size * a.round)
    // Their color, under the photo too (an app's icon may be see-through);
    // none in the moment before.
    color: a.slack ? "transparent" : a.shown || a.initialsUp ? Qt.hsla(U.hue(a.user || a.label), 0.45, a.t.dark ? 0.38 : 0.62, 1) : "transparent"

    Text {
      anchors.centerIn: parent
      visible: a.initialsUp
      text: U.initials(a.label)
      textFormat: Text.PlainText
      color: "white"
      font.family: a.t.font
      font.pixelSize: Math.max(8, a.size * 0.38)
      font.bold: true
    }
    Item {
      id: face
      anchors.fill: parent
      opacity: a.shown ? 1 : 0
      Behavior on opacity {
        enabled: a.late
        NumberAnimation { duration: 120 }
      }

      Image {
        id: low
        anchors.fill: parent
        visible: img.status !== Image.Ready
        source: a.stand
        asynchronous: false
        cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.min(a.px, 192)
        sourceSize.height: Math.min(a.px, 192)
        smooth: true
        mipmap: true
      }
      Image {
        id: img
        anchors.fill: parent
        anchors.margins: a.slack ? Math.round(a.size * 0.06) : 0
        source: a.photo
        // From disk on the spot, so one at hand is never a frame late; a
        // file the caller picked (any size: a new photo) aside. One from
        // Slack always comes aside.
        asynchronous: a.url.indexOf("file:") === 0
        cache: true
        fillMode: a.slack ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        sourceSize.width: a.px
        sourceSize.height: a.px
        smooth: true
        mipmap: true
        onStatusChanged: if (status === Image.Error && a.photo.indexOf("file://" + a.app.photosDir + "/") === 0) a.app.photoFailed(a.src)
      }
    }
  }

  PresenceDot {
    visible: a.showPresence && !a.slack && a.u && !a.u.bot
    app: a.app
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -2
    anchors.bottomMargin: -2
    size: Math.max(8, Math.round(a.size * 0.3))
    ring: a.ring
    ink: a.presenceInk
    // A deactivated account: always Slack's hollow ring.
    active: a.ws && !(a.u && a.u.deleted) ? a.ws.isActive(a.user) : false
    paused: a.ws && !(a.u && a.u.deleted) ? a.ws.isPaused(a.user) : false
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: a.clicked()
  }
}
