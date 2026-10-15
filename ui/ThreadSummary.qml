import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// "[faces] 12 replies  Last reply today at 10:20" under a thread's parent.
Rectangle {
  id: ts
  property var app: Reg.service
  property var ws
  property var msg: null
  readonly property var t: app.theme
  signal open()
  height: t.sp(34)
  radius: Math.max(6, t.radiusSmall)
  color: ma.containsMouse ? t.pane : "transparent"
  border.width: ma.containsMouse ? 1 : 0
  border.color: t.lineStrong
  width: parent ? parent.width : 400

  Row {
    x: ts.t.sp(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: ts.t.sp(8)
    Row {
      spacing: ts.t.sp(3)
      anchors.verticalCenter: parent.verticalCenter
      Repeater {
        model: ts.msg ? ts.msg.replyUsers.slice(0, 5) : []
        // An app among those who replied comes as its bot id: bots.info's picture.
        delegate: Avatar {
          required property var modelData
          readonly property var replier: ts.ws && /^B[A-Z0-9]+$/.test(modelData) ? ts.ws.bot(modelData) : null
          app: ts.app; ws: ts.ws; user: modelData; size: ts.t.sp(24); round: 0.2
          url: replier ? replier.icon : ""
          name: replier ? replier.name : ""
        }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: ts.msg ? (ts.msg.replyCount === 1 ? ts.app.tr("1 reply", "1 resposta") : ts.msg.replyCount + ts.app.tr(" replies", " respostas")) : ""
      color: ts.t.link
      font.family: ts.t.font
      font.pixelSize: ts.t.fsSmall + 1
      font.bold: true
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: ma.containsMouse ? ts.app.tr("View thread", "Ver conversa") : (ts.msg && ts.msg.latestReply ? ts.app.tr("Last reply ", "Última resposta ") + U.whenLabel(ts.msg.latestReply, ts.app.lang, ts.app.clock24) : "")
      color: ts.t.fgDim
      font.family: ts.t.font
      font.pixelSize: ts.t.fsSmall
    }
  }
  Glyph {
    visible: ma.containsMouse
    app: ts.app
    anchors.right: parent.right
    anchors.rightMargin: ts.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    icon: "󰅂"
    size: ts.t.fsSmall
    color: ts.t.fgDim
  }
  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: ts.open()
  }
}
