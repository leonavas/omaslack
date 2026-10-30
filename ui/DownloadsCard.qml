import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The files being saved to Downloads (Service.saveKeys), in the window's
// corner: the name and a bar while it comes; then Downloaded and Show in
// folder (the file manager at it). One that's done goes by itself after a
// while, unless the mouse is on it; × sends it away sooner.
Column {
  id: dc
  property var app: Reg.service
  property var ws
  readonly property var t: app.theme
  spacing: t.sp(8)

  Repeater {
    model: dc.app.saveKeys
    delegate: Rectangle {
      id: card
      required property var modelData
      readonly property var s: dc.app.saveState(modelData)
      readonly property real frac: s && s.total > 0 ? Math.min(1, s.done / s.total) : 0
      readonly property bool running: !!s && s.state === "running"
      readonly property bool failed: !!s && s.state === "failed"
      width: dc.t.sp(340)
      height: body.implicitHeight + dc.t.sp(24)
      radius: Math.max(8, dc.t.radiusCard)
      color: dc.t.alpha(dc.t.bgDarker, 0.97)
      border.width: 1
      border.color: dc.t.lineStrong

      HoverHandler { id: cardHover }
      Timer {
        interval: card.failed ? 12000 : 20000
        running: !!card.s && !card.running && !cardHover.hovered
        onTriggered: dc.app.saveDismiss(card.modelData)
      }

      Rectangle {
        id: icon
        x: dc.t.sp(12)
        y: dc.t.sp(12)
        width: dc.t.sp(36); height: width
        radius: Math.max(4, dc.t.radiusSmall)
        color: dc.t.alpha(card.failed ? dc.t.red : card.running ? dc.t.blue : dc.t.green, 0.16)
        Glyph {
          app: dc.app
          anchors.centerIn: parent
          visible: !card.running
          icon: card.failed ? "󰀨" : "󰄬"
          size: dc.t.fsTitle + 2
          color: card.failed ? dc.t.red : dc.t.green
        }
        Spinner { app: dc.app; anchors.centerIn: parent; visible: card.running; size: dc.t.sp(18); color: dc.t.blue }
      }

      Column {
        id: body
        anchors.left: icon.right
        anchors.leftMargin: dc.t.sp(10)
        anchors.right: closeBtn.left
        anchors.rightMargin: dc.t.sp(4)
        y: dc.t.sp(12)
        spacing: dc.t.sp(4)
        Text {
          width: parent.width
          text: card.s ? card.s.name : ""
          textFormat: Text.PlainText
          color: dc.t.fgBright
          font.family: dc.t.font
          font.pixelSize: dc.t.fsText - 1
          font.bold: true
          elide: Text.ElideMiddle
        }
        // The bar, while it comes.
        Rectangle {
          visible: card.running
          width: parent.width
          height: dc.t.sp(4)
          radius: height / 2
          color: dc.t.alpha(dc.t.fg, 0.12)
          Rectangle {
            width: parent.width * card.frac
            height: parent.height
            radius: parent.radius
            color: dc.t.blue
            Behavior on width { NumberAnimation { duration: 180 } }
          }
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: !card.s ? ""
                : card.running ? (card.s.total > 0 ? Math.round(card.frac * 100) + "%  ·  " + U.humanSize(card.s.done, dc.app.lang) + dc.app.tr(" of ", " de ") + U.humanSize(card.s.total, dc.app.lang)
                                                  : dc.app.tr("Downloading…", "Baixando…") + (card.s.done > 0 ? "  " + U.humanSize(card.s.done, dc.app.lang) : ""))
                : card.failed ? card.s.error
                : dc.app.tr("Downloaded", "Baixado")
          textFormat: Text.PlainText
          color: card.failed ? dc.t.red : dc.t.fgDim
          font.family: dc.t.font
          font.pixelSize: dc.t.fsSmall
          font.features: { "tnum": 1 }
          wrapMode: Text.Wrap
        }
        // Done: its folder, with the file selected.
        Text {
          visible: !!card.s && card.s.state === "done"
          text: "󰉋  " + dc.app.tr("Show in folder", "Mostrar na pasta")
          textFormat: Text.PlainText
          color: folderMa.containsMouse ? dc.t.fgBright : dc.t.link
          font.family: dc.t.font
          font.pixelSize: dc.t.fsSmall + 1
          font.bold: true
          font.underline: folderMa.containsMouse
          MouseArea {
            id: folderMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (dc.ws) dc.ws.showInFolder(card.s.path)
              dc.app.saveDismiss(card.modelData)
            }
          }
        }
      }

      IconButton {
        id: closeBtn
        app: dc.app
        anchors.right: parent.right
        anchors.rightMargin: dc.t.sp(6)
        y: dc.t.sp(8)
        size: dc.t.sp(24)
        icon: "󰅖"
        tip: card.running ? dc.app.tr("Hide (it keeps downloading)", "Ocultar (o download continua)") : dc.app.tr("Close", "Fechar")
        onClicked: dc.app.saveDismiss(card.modelData)
      }
    }
  }
}
