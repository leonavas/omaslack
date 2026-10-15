import QtQuick
import QtQuick.Controls
import qs.Ui
import "../lib/Registry.js" as Reg

// The conversation's pinned messages, newest pin first.
Item {
  id: pl
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  readonly property var t: app.theme
  readonly property var pins: ws ? (ws.pinsOf(conv) || []) : []
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    topMargin: pl.t.sp(10)
    bottomMargin: pl.t.sp(10)
    model: pl.pins
    spacing: pl.t.sp(8)
    ScrollBar.vertical: ThinScroll { app: pl.app }
    delegate: Rectangle {
      required property var modelData
      x: pl.t.sp(16)
      width: list.width - pl.t.sp(32)
      height: inner.implicitHeight + pl.t.sp(32)
      radius: Math.max(8, pl.t.radiusCard)
      color: pl.t.pane
      border.width: 1
      border.color: pl.t.lineStrong
      Text {
        x: pl.t.sp(16)
        y: pl.t.sp(8)
        text: "󰐃  " + (parent.modelData.by === pl.ws.me.id ? pl.app.tr("Pinned by you", "Fixada por você") : pl.app.tr("Pinned by ", "Fixada por ") + (pl.ws.userName(parent.modelData.by) || "?"))
        textFormat: Text.PlainText
        color: pl.t.fgDim
        font.family: pl.t.font
        font.pixelSize: pl.t.fsTiny + 1
      }
      MessageItem {
        id: inner
        y: pl.t.sp(24)
        width: parent.width
        app: pl.app
        win: pl.win
        ws: pl.ws
        conv: pl.conv
        ctx: pl.ctx
        row: ({ key: parent.modelData.msg.ts, kind: "msg", msg: parent.modelData.msg, header: true, day: null, isNew: false, pinned: false })
      }
      MouseArea {
        anchors.fill: parent
        z: -1
        onDoubleClicked: pl.ws.open(pl.conv, { ts: parent.modelData.msg.threadTs && parent.modelData.msg.threadTs !== parent.modelData.msg.ts ? parent.modelData.msg.threadTs : parent.modelData.msg.ts })
      }
    }
  }

  Text {
    visible: pl.pins.length === 0
    anchors.centerIn: parent
    text: pl.app.tr("Nothing is pinned here yet.", "Nada fixado aqui ainda.")
    color: pl.t.fgDim
    font.family: pl.t.font
    font.pixelSize: pl.t.fsText
  }
}
