import QtQuick
import Quickshell.Widgets
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A message's files: images inline (fetched with the session), the rest
// as Slack's file cards with open / download.
Flow {
  id: fl
  property var app: Reg.service
  property var win
  property var ws
  property var files: []
  property string user: ""
  property string conv: ""
  property string ts: ""
  readonly property var t: app.theme
  spacing: t.sp(8)

  Repeater {
    model: fl.files
    delegate: Loader {
      required property var modelData
      sourceComponent: modelData.image && modelData.thumb ? imageC : cardC
    }
  }

  Component {
    id: imageC
    Column {
      readonly property var f: parent.modelData
      spacing: fl.t.sp(4)
      Text {
        text: parent.f.name
        textFormat: Text.PlainText
        color: fl.t.fgDim
        font.family: fl.t.font
        font.pixelSize: fl.t.fsSmall
        width: Math.min(implicitWidth, fl.width)
        elide: Text.ElideMiddle
      }
      SlackImage {
        app: fl.app
        // A picture given inline (a data: URL, the demo's) needs no download.
        readonly property bool inline: String(parent.f.thumb).indexOf("data:") === 0
        readonly property string local: inline ? "" : fl.ws.localFile(parent.f.thumb)
        source: inline ? parent.f.thumb : local ? "file://" + local : ""
        Component.onCompleted: if (!inline && !local) Qt.callLater(function() { fl.ws.fetchFile(parent.f.thumb, parent.f.id + "-thumb-" + parent.f.name) })
        natW: parent.f.w
        natH: parent.f.h
        maxW: Math.min(fl.width, fl.t.sp(480))
        onOpen: fl.win.viewImage(Object.assign({}, parent.f, { user: fl.user, conv: fl.conv, ts: fl.ts }))
      }
    }
  }

  Component {
    id: cardC
    Rectangle {
      readonly property var f: parent.modelData
      width: Math.min(fl.width, fl.t.sp(380))
      height: fl.t.sp(58)
      radius: Math.max(8, fl.t.radiusCard)
      color: cardMa.containsMouse ? fl.t.hover : fl.t.alpha(fl.t.fg, 0.03)
      border.width: 1
      border.color: fl.t.lineStrong
      Rectangle {
        id: ic
        x: fl.t.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        width: fl.t.sp(38); height: width; radius: Math.max(4, fl.t.radiusSmall)
        color: fl.t.alpha(fl.t.blue, 0.16)
        Glyph { app: fl.app; anchors.centerIn: parent; icon: U.fileIcon(parent.parent.f); size: fl.t.fsTitle + 4; color: fl.t.blue }
      }
      Column {
        anchors.left: ic.right
        anchors.leftMargin: fl.t.sp(10)
        anchors.right: btns.left
        anchors.rightMargin: fl.t.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: parent.parent.f.title || parent.parent.f.name; textFormat: Text.PlainText; color: fl.t.fgBright; font.family: fl.t.font; font.pixelSize: fl.t.fsText - 1; font.bold: true; width: parent.width; elide: Text.ElideMiddle }
        Text {
          text: (parent.parent.f.prettyType || (parent.parent.f.filetype || "").toUpperCase()) + (parent.parent.f.size ? "  ·  " + U.humanSize(parent.parent.f.size, fl.app.lang) : "")
          textFormat: Text.PlainText
          color: fl.t.fgDim; font.family: fl.t.font; font.pixelSize: fl.t.fsSmall; width: parent.width; elide: Text.ElideRight
        }
      }
      Row {
        id: btns
        anchors.right: parent.right
        anchors.rightMargin: fl.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: cardMa.containsMouse || dl.hovered || op.hovered || lk.hovered
        IconButton { id: op; app: fl.app; icon: "󰏌"; tip: fl.app.tr("Open", "Abrir"); onClicked: fl.ws.openFile(parent.parent.f) }
        IconButton { id: dl; app: fl.app; visible: !!parent.parent.f.download; icon: "󰇚"; tip: fl.app.tr("Download", "Baixar"); onClicked: fl.ws.saveFile(parent.parent.f) }
        IconButton { id: lk; app: fl.app; visible: !!parent.parent.f.permalink; icon: "󰌷"; tip: fl.app.tr("Copy link to file", "Copiar link do arquivo"); onClicked: { fl.app.copy(parent.parent.f.permalink); fl.win.toast(fl.app.tr("Link copied", "Link copiado")) } }
      }
      MouseArea {
        id: cardMa
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: fl.ws.openFile(parent.f)
      }
    }
  }
}
