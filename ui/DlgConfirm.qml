import QtQuick

// "Are you sure?": title, text, an optional quote, Cancel / confirm.
DialogFrame {
  id: d
  title: args.title || ""
  cardWidth: t.sp(460)

  Column {
    width: parent.width
    spacing: d.t.sp(12)
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
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton {
      app: d.app
      kind: d.args.danger ? "danger" : "primary"
      text: d.args.confirm || "OK"
      onClicked: { var f = d.args.action; d.closed(); if (f) f() }
    }
  }
  Keys.onReturnPressed: { var f = d.args.action; d.closed(); if (f) f() }
}
