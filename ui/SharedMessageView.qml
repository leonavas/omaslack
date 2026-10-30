import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg
import "../lib/Util.js" as U
import "../lib/Model.js" as Model

// A shared message, as Slack draws it: a card with the author's photo and
// name, its day, where it was posted ("Thread in 🔒 sellout"), its text and
// its files. A click anywhere on it opens the original (openOriginal),
// except on what answers a click itself: a link, a picture, a file, the photo.
Rectangle {
  id: sv
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  property var att: null
  property var linkHandler: null
  property var imageSource: null
  property var msg: null
  property var pressHandler: null
  readonly property var t: app ? app.theme : null
  readonly property var c: ws && att && att.channelId ? ws.conv(att.channelId) : null
  readonly property var files: att ? att.files.filter(function(f) { return f && f.mode !== "tombstone" }).map(Model.parseFile) : []

  implicitHeight: col.implicitHeight + 2 * t.sp(12)
  height: implicitHeight
  radius: Math.max(6, t.radiusCard)
  color: "transparent"
  border.width: 1
  border.color: t.lineStrong

  // The original's place, "Thread in" · lock or # · its name, when it's a
  // conversation we know; else Slack's own footer ("Slack Conversation"
  // for a channel we're not in).
  readonly property string lead: !att ? "" : (att.thread ? app.tr("Thread in ", "Conversa em ") : app.tr("Posted in ", "Publicada em "))
  readonly property string where: !c ? "" : (c.kind === "im" ? app.tr("direct message with ", "mensagem direta com ") : "") + ws.convLabel(att.channelId)

  // The channel at the thread's first message, with the thread open; a
  // message outside a thread: the channel at it.
  function openOriginal() {
    if (!att.channelId || !att.ts) { linkHandler(att.titleLink); return }
    var root = att.thread ? (att.threadTs || att.ts) : ""
    ws.open(att.channelId, root ? { ts: root, threadTs: root } : { ts: att.ts })
  }

  // Whether something inside answers the click at (x, y) itself: the
  // deepest item there, or one above it, with a click of its own (a
  // MouseArea that takes buttons) or a link under the point.
  function ownsClick(x, y) {
    var it = col, p = sv.mapToItem(col, x, y)
    while (true) {
      var next = it.childAt(p.x, p.y)
      if (!next) return false
      p = it.mapToItem(next, p.x, p.y)
      it = next
      if (it.pressAndHoldInterval !== undefined && it.enabled && it.acceptedButtons !== Qt.NoButton) return true
      if (typeof it.linkAt === "function" && it.linkAt(p.x, p.y) !== "") return true
      if (it.emojiHover) return true
    }
  }

  Column {
    id: col
    x: sv.t.sp(12); y: sv.t.sp(12)
    width: sv.width - 2 * sv.t.sp(12)
    spacing: sv.t.sp(8)

    Row {
      spacing: sv.t.sp(8)
      Avatar {
        app: sv.app
        ws: sv.ws
        user: sv.att ? sv.att.authorId : ""
        url: sv.att && !sv.att.authorId ? sv.att.authorIcon : ""
        name: sv.att && !sv.att.authorId ? sv.att.author : ""
        size: sv.t.avatar
        onClicked: if (sv.att.authorId) { sv.ws.profileUser = sv.att.authorId; sv.ws.thread = null }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: sv.t.sp(2)
        Row {
          spacing: sv.t.sp(6)
          Text {
            id: who
            text: !sv.att ? "" : ((sv.att.authorId && sv.ws ? sv.ws.userName(sv.att.authorId) : "") || sv.att.author)
            textFormat: Text.PlainText
            color: sv.t.fgBright
            font.family: sv.t.font
            font.pixelSize: sv.t.fsName
            font.bold: true
          }
          Text {
            visible: !!sv.att && sv.att.ts !== ""
            text: visible ? U.dateStamp(sv.att.ts, sv.app.lang) : ""
            textFormat: Text.PlainText
            color: sv.t.fgDim
            font.family: sv.t.font
            font.pixelSize: sv.t.fsSmall
            anchors.baseline: who.baseline
          }
        }
        // The whole line opens the original (Slack's footer too, when the
        // channel isn't one we know).
        Item {
          visible: sv.where !== "" || (!!sv.att && sv.att.footer !== "")
          width: placeRow.width
          height: placeRow.height
          Row {
            id: placeRow
            spacing: sv.t.sp(3)
            Text {
              visible: sv.where !== ""
              text: sv.lead
              textFormat: Text.PlainText
              color: sv.t.fgDim
              font.family: sv.t.font
              font.pixelSize: sv.t.fsSmall
              anchors.verticalCenter: parent.verticalCenter
            }
            Glyph {
              visible: !!sv.c && sv.c.kind !== "im"
              app: sv.app
              icon: !sv.c ? "" : (sv.c.kind === "private" ? "󰌾" : sv.c.kind === "mpim" ? "󰀏" : "#")
              size: sv.t.fsSmall
              color: sv.t.fgDim
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              visible: sv.where !== ""
              text: sv.where
              textFormat: Text.PlainText
              color: placeHover.containsMouse ? sv.t.fg : sv.t.fgDim
              font.family: sv.t.font
              font.pixelSize: sv.t.fsSmall
              font.underline: placeHover.containsMouse
              anchors.verticalCenter: parent.verticalCenter
            }
            RichText {
              visible: sv.where === ""
              width: Math.min(implicitWidth, col.width - sv.t.avatar - sv.t.sp(8))
              app: sv.app
              html: sv.att ? sv.att.footer : ""
              size: sv.t.fsSmall
              color: sv.t.fgDim
            }
          }
          MouseArea {
            id: placeHover
            anchors.fill: parent
            enabled: !!sv.att && ((sv.att.channelId !== "" && sv.att.ts !== "") || sv.att.titleLink !== "")
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sv.openOriginal()
          }
        }
      }
    }

    MessageBody {
      visible: parts.length > 0
      width: parent.width
      app: sv.app
      win: sv.win
      ws: sv.ws
      conv: sv.conv
      msg: sv.msg
      parts: sv.att ? sv.att.parts : []
    }

    FileList {
      visible: sv.files.length > 0
      width: parent.width
      app: sv.app
      win: sv.win
      ws: sv.ws
      files: sv.files
      user: sv.att ? sv.att.authorId : ""
      conv: sv.att ? sv.att.channelId : ""
      ts: sv.att ? sv.att.ts : ""
    }
  }

  // Over everything, so a click on the text opens the original too; what
  // answers a click itself gets it (ownsClick).
  MouseArea {
    id: tap
    anchors.fill: parent
    z: 1
    // On top, so the hand shows over the text too (not the text's I-beam).
    cursorShape: Qt.PointingHandCursor
    onPressed: mouse => mouse.accepted = !sv.ownsClick(mouse.x, mouse.y)
    onClicked: sv.openOriginal()
  }
}
