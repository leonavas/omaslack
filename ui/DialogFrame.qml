import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Registry.js" as Reg

// A modal card over a dimmed window: title, ✕, content, footer.
Item {
  id: d
  property var app: Reg.service
  property var win
  property var ws
  property var args: ({})
  readonly property var t: app.theme
  property string title: ""
  property string subtitle: ""
  property int cardWidth: t.sp(520)
  property int maxHeight: parent ? parent.height - t.sp(80) : 600
  property bool dismissable: true
  default property alias content: body.data
  property alias footer: foot.data
  property Item initialFocus: null
  signal closed()
  anchors.fill: parent
  z: 800

  Keys.onEscapePressed: if (d.dismissable) d.closed()
  Component.onCompleted: Qt.callLater(function() { if (d.initialFocus) d.initialFocus.forceActiveFocus(); else d.forceActiveFocus() })

  Rectangle {
    anchors.fill: parent
    color: d.t.scrim
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: if (d.dismissable) d.closed(); onWheel: wheel => {} }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(d.cardWidth, d.width - d.t.sp(40))
    height: Math.min(d.maxHeight, head.height + body.childrenRect.height + foot.childrenRect.height + d.t.sp(48) + (foot.children.length ? d.t.sp(16) : 0))
    color: d.t.popup
    borderSpec: d.t.popupBorder
    radius: Math.max(8, d.t.radiusCard)
    clip: true

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Item {
      id: head
      x: d.t.sp(24)
      y: d.t.sp(18)
      width: card.width - d.t.sp(48)
      height: titleCol.implicitHeight
      Column {
        id: titleCol
        width: parent.width - d.t.sp(40)
        spacing: d.t.sp(4)
        Text { text: d.title; textFormat: Text.PlainText; color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsHuge - 2; font.bold: true; width: parent.width; elide: Text.ElideRight }
        Text { visible: d.subtitle !== ""; text: d.subtitle; textFormat: Text.PlainText; color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall; width: parent.width; wrapMode: Text.Wrap }
      }
      IconButton {
        app: d.app
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -d.t.sp(4)
        icon: "󰅖"
        tip: d.app.tr("Close", "Fechar")
        visible: d.dismissable
        onClicked: d.closed()
      }
    }

    Item {
      id: body
      x: d.t.sp(24)
      anchors.top: head.bottom
      anchors.topMargin: d.t.sp(16)
      width: card.width - d.t.sp(48)
      height: card.height - head.height - d.t.sp(34) - (foot.children.length ? foot.childrenRect.height + d.t.sp(32) : d.t.sp(16))
    }

    Item {
      id: foot
      x: d.t.sp(24)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: d.t.sp(18)
      width: card.width - d.t.sp(48)
      height: childrenRect.height
    }
  }
}
