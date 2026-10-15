import QtQuick
import Quickshell.Widgets
import "../lib/Registry.js" as Reg

// An image in a message, sized like Slack does (at most ~480×360, aspect
// kept), rounded, with a placeholder while it loads; a click enlarges it.
Item {
  id: si
  property var app: Reg.service
  readonly property var t: app.theme
  property string source: ""
  property int natW: 0
  property int natH: 0
  property int maxW: t.sp(480)
  property int maxH: t.sp(360)
  property string name: ""
  signal open()

  readonly property real ratio: natW > 0 && natH > 0 ? natW / natH : (img.status === Image.Ready && img.implicitHeight > 0 ? img.implicitWidth / img.implicitHeight : 1.6)
  readonly property real fitW: Math.min(maxW, natW > 0 ? natW : maxW, maxH * ratio)
  width: Math.max(t.sp(60), fitW)
  height: Math.max(t.sp(40), width / ratio)

  Clip {
    anchors.fill: parent
    radius: Math.max(6, si.t.radiusSmall)
    color: si.t.codeBg
    borderWidth: 1
    borderColor: si.t.line
    Image {
      id: img
      anchors.fill: parent
      source: si.source
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      sourceSize.width: si.width * 2
      smooth: true
      mipmap: true
    }
    Text {
      anchors.centerIn: parent
      visible: img.status !== Image.Ready
      text: img.status === Image.Error ? "󰋩  " + si.app.tr("didn't load", "não carregou") : "󰋩"
      color: si.t.fgDim
      font.family: si.t.font
      font.pixelSize: si.t.fsSmall
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: si.open()
  }
}
