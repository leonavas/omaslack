import QtQuick
import "../lib/Registry.js" as Reg

// Slack's bubble over an emoji in a message: the picture large on a light
// square and its :name:, what typing it takes. Declared in an item the
// emoji's size, where it is (RichText's `emojiSpot`).
BubbleTip {
  id: tip
  property string name: ""
  property string src: ""
  property bool hovered: false

  padX: t.sp(14)
  padY: t.sp(12)
  visible: hovered && name !== "" && src !== ""
  text: ":" + name + ":"

  contentItem: Column {
    spacing: tip.t.sp(8)
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: tip.t.sp(80)
      height: width
      radius: tip.t.sp(6)
      color: "#f8f8f8"
      AnimatedImage {
        anchors.centerIn: parent
        width: tip.t.sp(60)
        height: width
        source: tip.src
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        playing: tip.visible
        smooth: true
        mipmap: true
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, tip.t.sp(220))
      text: ":" + tip.name + ":"
      textFormat: Text.PlainText
      wrapMode: Text.WrapAnywhere
      horizontalAlignment: Text.AlignHCenter
      color: tip.ink
      font.family: tip.t.font
      font.pixelSize: tip.t.px(13)
      font.bold: true
    }
  }
}
