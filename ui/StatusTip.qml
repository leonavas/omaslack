import QtQuick
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji

// Slack's bubble over someone's status emoji: the emoji and the status in
// bold ("⛔ Out of Office • Google Calendar": an app's status already ends
// with its name), then when it clears ("Until tomorrow, 12:00 AM"), all
// centered, with an arrow at the emoji. Declared inside the emoji.
// `hovered` is the emoji's HoverHandler; `area` a MouseArea lying over the
// emoji (a row's own), which only counts while the mouse is on the emoji.
BubbleTip {
  id: tip
  property var ws
  property var status: null     // Model.status
  property bool hovered: false
  property var area: null

  readonly property bool hasEmoji: !!status && (status.emoji !== "" || status.unicode !== "" || status.url !== "")
  readonly property bool overArea: !!area && area.containsMouse && !!parent
                                   && parent.contains(parent.mapFromItem(area, area.mouseX, area.mouseY))
  readonly property string until: { tip.shownAt; return status && status.exp ? U.statusUntil(status.exp, app.lang, app.clock24) : "" }

  visible: (hovered || overArea) && !!parent && parent.visible && (hasEmoji || (!!status && status.text !== ""))
  text: status ? [status.text, until].filter(function(x) { return x }).join("  ·  ") : ""

  contentItem: Column {
    spacing: tip.t.sp(2)
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: tip.t.sp(5)
      EmojiIcon {
        id: face
        visible: tip.hasEmoji
        // Level with the first line when the status wraps.
        y: line.visible ? Math.max(0, Math.round((line.implicitHeight / Math.max(1, line.lineCount) - height) / 2)) : 0
        app: tip.app
        ws: tip.ws
        name: tip.status ? tip.status.emoji.replace(/:/g, "") : ""
        glyph: tip.status && tip.status.unicode ? Emoji.fromHex(tip.status.unicode) : ""
        url: tip.status ? tip.status.url : ""
        size: tip.t.px(13) + 3
      }
      Text {
        id: line
        visible: text !== ""
        width: Math.min(implicitWidth, tip.t.sp(260))
        text: tip.status ? tip.status.text : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        color: tip.ink
        font.family: tip.t.font
        font.pixelSize: tip.t.px(13)
        font.bold: true
      }
    }
    Text {
      visible: text !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      text: tip.until
      textFormat: Text.PlainText
      color: tip.soft
      font.family: tip.t.font
      font.pixelSize: tip.t.px(13)
    }
  }
}
