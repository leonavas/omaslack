import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// What stands where the message box would: an archived channel, a channel
// you're previewing, a deactivated account.
Rectangle {
  id: n
  property var app: Reg.service
  property var ws
  property string conv: ""
  property string reason: ""
  readonly property var t: app.theme
  readonly property var c: ws ? ws.conv(conv) : null
  height: col.implicitHeight + t.sp(28)
  radius: Math.max(8, t.radiusCard)
  color: t.alpha(t.fg, 0.04)
  border.width: 1
  border.color: t.lineStrong

  // [Close] on a deactivated account's archives: back where you came from,
  // and out of Slack's sidebar too (Workspace.closeDm).
  function close() {
    var w = n.ws, id = n.conv
    if (w.backStack.length) w.goBack()
    w.closeDm(id)
  }

  Column {
    id: col
    anchors.centerIn: parent
    width: parent.width - n.t.sp(40)
    spacing: n.t.sp(10)
    Text {
      visible: n.reason !== "deactivated"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      color: n.t.fg
      font.family: n.t.font
      font.pixelSize: n.t.fsText
      text: n.reason === "archived" ? n.app.tr("You're viewing an archived channel", "Você está vendo um canal arquivado")
          : n.app.tr("You're viewing ", "Você está vendo ") + "#" + (n.c ? n.c.name : "")
    }
    // Slack's bar on a deactivated account's DM: the archive mark, what
    // this is, and [Close].
    Row {
      visible: n.reason === "deactivated"
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: n.t.sp(10)
      Glyph {
        app: n.app
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰀼"
        size: n.t.fsTitle
        color: n.t.fgSoft
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, col.width - n.t.sp(140))
        wrapMode: Text.Wrap
        color: n.t.fgSoft
        font.family: n.t.font
        font.pixelSize: n.t.fsText
        text: n.app.tr("You are viewing the archives of a deactivated account", "Você está vendo os arquivos de uma conta desativada")
      }
      SButton {
        anchors.verticalCenter: parent.verticalCenter
        app: n.app
        small: true
        text: n.app.tr("Close", "Fechar")
        onClicked: n.close()
      }
    }
    Row {
      visible: n.reason !== "deactivated"
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: n.t.sp(8)
      SButton {
        visible: n.reason === "guest"
        app: n.app
        kind: "primary"
        text: n.app.tr("Join channel", "Entrar no canal")
        onClicked: n.ws.join(n.conv)
      }
      SButton {
        visible: n.reason === "archived"
        app: n.app
        text: n.app.tr("Unarchive channel", "Desarquivar canal")
        onClicked: n.ws.setArchived(n.conv, false)
      }
    }
  }
}
