import QtQuick
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A workspace's icon in Slack's rounded square: the team's picture, or its
// initials over a color of their own when it has none. As Avatar: from disk
// when it's there, up at once; on its way, a moment before the initials
// stand in, and a fade over them if they did.
Item {
  id: wi
  property var app: Reg.service
  readonly property var t: app.theme
  property var w: null
  property int size: t.sp(36)
  property real radius: Math.max(t.sp(8), t.radiusSmall + 2)
  width: size
  height: size

  readonly property string icon: wi.w ? (wi.w.team.icon || "") : ""
  readonly property bool shown: teamImg.status === Image.Ready
  property bool late: false
  readonly property bool initialsUp: !shown ? (teamImg.status !== Image.Loading || late) : (late && teamImg.opacity < 1)

  Timer {
    interval: wi.late ? 150 : 200
    running: wi.late ? wi.shown : teamImg.status === Image.Loading
    onTriggered: wi.late = !wi.late
  }

  Clip {
    anchors.fill: parent
    radius: wi.radius
    color: wi.shown || wi.initialsUp ? Qt.hsla(U.hue(wi.w ? wi.w.teamId : ""), 0.45, 0.42, 1) : "transparent"
    Text {
      anchors.centerIn: parent
      visible: wi.initialsUp
      text: U.initials(wi.w ? (wi.w.team.name || "?") : "?")
      textFormat: Text.PlainText
      color: "white"
      font.family: wi.t.font
      font.pixelSize: Math.max(8, Math.round(wi.size * 0.42))
      font.bold: true
    }
    Image {
      id: teamImg
      anchors.fill: parent
      source: wi.icon !== "" ? (wi.app.photoFile(wi.icon) || wi.icon) : ""
      asynchronous: false
      cache: true
      opacity: wi.shown ? 1 : 0
      Behavior on opacity {
        enabled: wi.late
        NumberAnimation { duration: 120 }
      }
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 96
      sourceSize.height: 96
      onStatusChanged: if (status === Image.Error && String(source).indexOf("file://" + wi.app.photosDir + "/") === 0) wi.app.photoFailed(wi.icon)
    }
  }
}
