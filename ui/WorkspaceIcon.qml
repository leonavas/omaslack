import QtQuick
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A workspace's icon in Slack's rounded square: the team's picture, or its
// initials over a color of its own while it loads (or when it has none).
Item {
  id: wi
  property var app: Reg.service
  readonly property var t: app.theme
  property var w: null
  property int size: t.sp(36)
  property real radius: Math.max(t.sp(8), t.radiusSmall + 2)
  width: size
  height: size

  Clip {
    anchors.fill: parent
    radius: wi.radius
    color: Qt.hsla(U.hue(wi.w ? wi.w.teamId : ""), 0.45, 0.42, 1)
    Text {
      anchors.centerIn: parent
      visible: teamImg.status !== Image.Ready
      text: U.initials(wi.w ? (wi.w.team.name || "?") : "?")
      color: "white"
      font.family: wi.t.font
      font.pixelSize: Math.max(8, Math.round(wi.size * 0.42))
      font.bold: true
    }
    Image {
      id: teamImg
      anchors.fill: parent
      source: wi.w ? (wi.w.team.icon || "") : ""
      asynchronous: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 96
      sourceSize.height: 96
    }
  }
}
