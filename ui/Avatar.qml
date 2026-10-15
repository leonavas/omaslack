import QtQuick
import Quickshell.Widgets
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A person's (or bot's) photo in Slack's rounded square, initials over a
// color of their own while it loads, and an optional presence dot.
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
  property real round: 0.22
  property bool big: size > 48
  signal clicked()

  readonly property var u: ws && user ? ws.user(user) : null
  readonly property string src: url !== "" ? url : (u ? (a.big ? (u.avatar192 || u.avatar || "") : (u.avatar || "")) : "")
  readonly property string label: name !== "" ? name : (u ? u.name : "")

  width: size
  height: size

  Clip {
    anchors.fill: parent
    radius: Math.round(a.size * a.round)
    color: Qt.hsla(U.hue(a.user || a.label), 0.45, a.t.dark ? 0.38 : 0.62, 1)

    Text {
      anchors.centerIn: parent
      visible: img.status !== Image.Ready
      text: U.initials(a.label)
      color: "white"
      font.family: a.t.font
      font.pixelSize: Math.max(8, a.size * 0.38)
      font.bold: true
    }
    Image {
      id: img
      anchors.fill: parent
      source: a.src
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: a.size * 2
      sourceSize.height: a.size * 2
      smooth: true
      mipmap: true
    }
  }

  PresenceDot {
    visible: a.showPresence && a.u && !a.u.bot
    app: a.app
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -2
    anchors.bottomMargin: -2
    size: Math.max(8, Math.round(a.size * 0.3))
    ring: a.ring
    active: a.ws ? a.ws.isActive(a.user) : false
    paused: a.ws ? a.ws.isPaused(a.user) : false
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: a.clicked()
  }
}
