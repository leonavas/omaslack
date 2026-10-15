import QtQuick
import "../lib/Model.js" as Model

// "Are you sure?": title, text, an optional quote — or a message (`msg`,
// `conv`) drawn as the conversation draws it, as in Slack's Delete message —
// then Cancel / confirm. The confirm button has the keyboard: Enter confirms,
// Esc cancels, Tab / ← → move between the two.
DialogFrame {
  id: d
  title: args.title || ""
  cardWidth: t.sp(args.msg ? 520 : 460)
  initialFocus: okBtn

  function confirm() { var f = d.args.action; d.closed(); if (f) f() }

  Column {
    width: parent.width
    spacing: d.t.sp(d.args.msg ? 16 : 12)
    Text { width: parent.width; wrapMode: Text.Wrap; text: d.args.text || ""; color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText }
    Rectangle {
      visible: !!d.args.quote
      width: parent.width
      height: quote.implicitHeight + d.t.sp(16)
      radius: Math.max(6, d.t.radiusSmall)
      color: d.t.alpha(d.t.fg, 0.05)
      border.width: 1
      border.color: d.t.line
      Text { id: quote; anchors.centerIn: parent; width: parent.width - d.t.sp(20); wrapMode: Text.Wrap; text: d.args.quote || ""; color: d.t.fgSoft; font.family: d.t.font; font.pixelSize: d.t.fsSmall; maximumLineCount: 6; elide: Text.ElideRight }
    }

    // The message: photo, name, "Today at 7:53 AM", the body and its files.
    Rectangle {
      id: preview
      visible: !!d.args.msg
      width: parent.width
      readonly property int most: Math.max(d.t.sp(80), Math.min(d.t.sp(320), d.maxHeight - d.t.sp(260)))
      height: Math.min(item.implicitHeight, most) + d.t.sp(12)
      radius: Math.max(6, d.t.radiusCard)
      color: "transparent"
      border.width: 1
      border.color: d.t.lineStrong
      clip: true

      MessageItem {
        id: item
        x: d.t.sp(2)
        y: d.t.sp(4)
        width: parent.width - d.t.sp(4)
        height: Math.min(implicitHeight, preview.most)
        clip: true
        enabled: false
        app: d.app
        win: d.win
        ws: d.ws
        conv: d.args.conv || ""
        inThread: true
        longTime: true
        ctx: d.ws && d.args.msg ? d.ws.renderCtx(d.t.html, d.t.emojiPx) : null
        row: d.args.msg ? { key: d.args.msg.ts, kind: "msg", msg: Model.patch(d.args.msg, { reactions: [], replyCount: 0, replyUsers: [], pinnedTo: [] }), header: true, day: null, isNew: false, pinned: false } : null
      }
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { id: cancelBtn; app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton {
      id: okBtn
      app: d.app
      kind: d.args.danger ? "danger" : "primary"
      text: d.args.confirm || "OK"
      onClicked: d.confirm()
    }
  }
  Keys.onReturnPressed: d.confirm()
  Keys.onEnterPressed: d.confirm()
  Keys.onTabPressed: (okBtn.activeFocus ? cancelBtn : okBtn).forceActiveFocus()
  Keys.onBacktabPressed: (okBtn.activeFocus ? cancelBtn : okBtn).forceActiveFocus()
  Keys.onLeftPressed: cancelBtn.forceActiveFocus()
  Keys.onRightPressed: okBtn.forceActiveFocus()
}
