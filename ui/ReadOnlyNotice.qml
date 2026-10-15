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

  Column {
    id: col
    anchors.centerIn: parent
    width: parent.width - n.t.sp(40)
    spacing: n.t.sp(10)
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      color: n.t.fg
      font.family: n.t.font
      font.pixelSize: n.t.fsText
      text: n.reason === "archived" ? n.app.tr("You're viewing an archived channel", "Você está vendo um canal arquivado")
          : n.reason === "guest" ? n.app.tr("You're viewing ", "Você está vendo ") + "#" + (n.c ? n.c.name : "")
          : n.app.tr("This account has been deactivated. You can read the conversation, but no longer reply.", "Esta conta foi desativada. Dá para ler a conversa, mas não responder.")
    }
    Row {
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
