import QtQuick
import qs.Ui
import "../lib/Model.js" as Model
import "../lib/Registry.js" as Reg

// The thread beside the conversation: its parent, "N replies", the replies
// and a box to reply (with "Also send to #channel").
Rectangle {
  id: tp
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var th: ws ? ws.thread : null
  readonly property string conv: th ? th.conv : ""
  readonly property string ts: th ? th.ts : ""
  readonly property var c: ws && conv ? ws.conv(conv) : null
  readonly property var hist: ws && th ? ws.repliesOf(conv, ts) : null
  readonly property var parentMsg: hist && hist.msgs.length && hist.msgs[0].ts === ts ? hist.msgs[0] : (ws && th ? ws.findAny(conv, ts) : null)
  readonly property int replies: hist && hist.msgs.length > 1 ? hist.msgs.length - 1 : (parentMsg ? (parentMsg._replyCount || parentMsg.replyCount || 0) : 0)
  color: t.pane

  Item {
    id: header
    width: parent.width
    height: tp.t.sp(52)
    Column {
      x: tp.t.sp(18)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text { text: tp.app.tr("Thread", "Conversa"); color: tp.t.fgBright; font.family: tp.t.font; font.pixelSize: tp.t.fsTitle + 1; font.bold: true }
      Text {
        text: tp.c ? ((tp.c.kind === "im" || tp.c.kind === "mpim" ? "" : (tp.c.kind === "private" ? "🔒" : "#")) + tp.ws.convLabel(tp.conv)) : ""
        color: tp.t.fgDim
        font.family: tp.t.font
        font.pixelSize: tp.t.fsSmall
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tp.ws.open(tp.conv) }
      }
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: tp.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      IconButton {
        id: threadMore
        app: tp.app
        icon: "󰇙"
        tip: tp.app.tr("More actions", "Mais ações")
        onClicked: {
          var p = tp.parentMsg
          if (!p) return
          var on = !!p.subscribed
          tp.win.menuAt(threadMore, [
            { label: on ? tp.app.tr("Turn off notifications for replies", "Desativar notificações de respostas") : tp.app.tr("Get notified about new replies", "Ativar notificações de respostas"), icon: on ? "󰂛" : "󰂚", action: function() { tp.ws.setFollow(tp.conv, p, !on) } },
            { label: tp.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() { tp.app.copy(tp.ws.permalink(tp.conv, p)); tp.win.toast(tp.app.tr("Link copied", "Link copiado")) } },
            { label: tp.app.tr("Mark as read", "Marcar como lida"), icon: "󰄬", action: function() { var s = tp.hist; if (s && s.msgs.length) tp.ws.markThread(tp.conv, tp.ts, s.msgs[s.msgs.length - 1].ts) } }
          ], -tp.t.sp(220), threadMore.height + 4)
        }
      }
      IconButton { app: tp.app; icon: "󰅖"; tip: tp.app.tr("Close", "Fechar") + "  Ctrl+."; onClicked: tp.ws.closeThread() }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: tp.t.line }
  }

  MessageList {
    id: list
    anchors.top: header.bottom
    anchors.bottom: box.top
    anchors.bottomMargin: tp.t.sp(8)
    width: parent.width
    app: tp.app
    win: tp.win
    ws: tp.ws
    conv: tp.conv
    threadTs: tp.ts
    intro: parentC
  }

  Component {
    id: parentC
    Column {
      width: list.width
      MessageItem {
        visible: !!tp.parentMsg
        width: parent.width
        app: tp.app
        win: tp.win
        ws: tp.ws
        conv: tp.conv
        inThread: true
        isParent: true
        ctx: list.ctx
        row: tp.parentMsg ? ({ key: "parent", kind: "msg", msg: tp.parentMsg, header: true, day: null, isNew: false, pinned: false }) : null
      }
      Item {
        visible: tp.replies > 0
        width: parent.width
        height: tp.t.sp(28)
        Text {
          id: count
          x: tp.t.sp(20)
          anchors.verticalCenter: parent.verticalCenter
          text: tp.replies === 1 ? tp.app.tr("1 reply", "1 resposta") : tp.replies + tp.app.tr(" replies", " respostas")
          color: tp.t.fgDim
          font.family: tp.t.font
          font.pixelSize: tp.t.fsSmall
        }
        Rectangle { anchors.left: count.right; anchors.leftMargin: tp.t.sp(10); anchors.right: parent.right; anchors.rightMargin: tp.t.sp(20); anchors.verticalCenter: parent.verticalCenter; height: 1; color: tp.t.line }
      }
    }
  }

  Composer {
    id: box
    anchors.bottom: parent.bottom
    anchors.bottomMargin: tp.t.sp(24)
    x: tp.t.sp(16)
    width: parent.width - tp.t.sp(32)
    app: tp.app
    win: tp.win
    ws: tp.ws
    conv: tp.conv
    threadTs: tp.ts
    visible: !!tp.c && !tp.c.archived && tp.c.member !== false
  }

  onTsChanged: Qt.callLater(function() { box.focusInput() })
}
