import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg
import "../lib/Util.js" as U

// A legacy attachment (or link unfurl, or shared message): a colored bar
// and, beside it, the service, author, title, text, fields, image, footer.
Row {
  id: av
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  property var att: null
  property var linkHandler: null
  property var imageSource: null
  property var msg: null
  // MessageBody.press: what an app's button does.
  property var pressHandler: null
  readonly property var t: app ? app.theme : null
  spacing: t ? t.sp(12) : 12

  readonly property color barColor: !att || !t ? "transparent" : (att.color === "good" ? t.green : att.color === "warning" ? t.yellow : att.color === "danger" ? t.red : (att.color ? att.color : t.alpha(t.fg, 0.25)))

  Rectangle { width: av.t ? av.t.sp(4) : 4; height: col.height; radius: 2; color: av.barColor }

  Column {
    id: col
    width: av.width - (av.t ? av.t.sp(16) : 16)
    spacing: av.t ? av.t.sp(4) : 4
    visible: !!av.att && !!av.t

    RichText {
      visible: !!av.att && av.att.pretext !== ""
      width: parent.width
      app: av.app
      html: av.att ? av.att.pretext : ""
      onLink: url => av.linkHandler(url)
    }
    Row {
      visible: !!av.att && (av.att.service !== "" || av.att.author !== "")
      spacing: av.t ? av.t.sp(6) : 6
      // Pictures from other sites only while Preferences lets them (MessageBody.shows).
      Image {
        visible: !!av.att && (av.att.serviceIcon || av.att.authorIcon) !== "" && inner.shows(av.att.authorIcon || av.att.serviceIcon)
        source: visible ? (av.att.authorIcon || av.att.serviceIcon || "") : ""
        width: av.t ? av.t.sp(16) : 16; height: width
        asynchronous: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: av.att ? (av.att.author || av.att.service) : ""
        textFormat: Text.PlainText
        color: av.t ? av.t.fg : "white"
        font.family: av.t ? av.t.font : "monospace"
        font.pixelSize: av.t ? av.t.fsSmall + 1 : 12
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    RichText {
      visible: !!av.att && av.att.title !== ""
      width: parent.width
      app: av.app
      html: !av.att ? "" : (av.att.titleLink && av.att.title.indexOf("<a ") < 0 ? "<a href=\"" + U.escapeHtml(av.att.titleLink) + "\" style=\"color:" + av.t.html.link + ";text-decoration:none;\"><b>" + av.att.title + "</b></a>" : "<b>" + av.att.title + "</b>")
      onLink: url => av.linkHandler(url)
    }
    Item {
      width: parent.width
      height: Math.max(inner.implicitHeight, thumb.visible ? thumb.height : 0)
      visible: inner.parts.length > 0 || thumb.visible
      MessageBody {
        id: inner
        width: parent.width - (thumb.visible ? thumb.width + av.t.sp(10) : 0)
        app: av.app
        win: av.win
        ws: av.ws
        conv: av.conv
        msg: av.msg
        parts: av.att ? av.att.parts : []
      }
      Image {
        id: thumb
        visible: !!av.att && av.att.thumb !== "" && !av.att.image && inner.shows(av.att.thumb)
        anchors.right: parent.right
        width: av.t ? av.t.sp(72) : 72; height: width
        source: visible ? av.att.thumb : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
    }
    Grid {
      visible: !!av.att && av.att.fields.length > 0
      columns: 2
      columnSpacing: av.t ? av.t.sp(16) : 16
      rowSpacing: av.t ? av.t.sp(6) : 6
      width: parent.width
      Repeater {
        model: av.att ? av.att.fields : []
        delegate: Column {
          required property var modelData
          width: modelData.short ? (col.width - av.t.sp(16)) / 2 : col.width
          RichText { width: parent.width; app: av.app; html: "<b>" + modelData.title + "</b>"; size: av.t.fsSmall + 1; onLink: url => av.linkHandler(url) }
          RichText { width: parent.width; app: av.app; html: modelData.html; onLink: url => av.linkHandler(url) }
        }
      }
    }
    SlackImage {
      visible: !!av.att && !!av.att.image && inner.shows(av.att.image.url)
      app: av.app
      source: av.att && av.att.image ? av.imageSource(av.att.image.url) : ""
      natW: av.att && av.att.image ? av.att.image.w : 0
      natH: av.att && av.att.image ? av.att.image.h : 0
      maxW: Math.min(col.width, av.t.sp(400))
      onOpen: av.win.viewImage({ name: av.att.titleText || "image", full: av.att.image.url, thumb: av.att.image.url, w: av.att.image.w, h: av.att.image.h, external: true })
    }
    Flow {
      visible: !!av.att && av.att.actions.length > 0
      width: parent.width
      spacing: av.t ? av.t.sp(8) : 8
      Repeater {
        model: av.att ? av.att.actions : []
        delegate: SButton {
          required property var modelData
          app: av.app
          small: true
          text: modelData.label
          kind: modelData.style === "primary" ? "green" : (modelData.style === "danger" ? "danger" : "secondary")
          onClicked: if (av.pressHandler) av.pressHandler(modelData); else if (modelData.url) av.app.openUrl(modelData.url)
        }
      }
    }
    RichText {
      visible: !!av.att && av.att.footer !== ""
      width: parent.width
      app: av.app
      html: av.att ? av.att.footer : ""
      size: av.t ? av.t.fsTiny + 1 : 11
      color: av.t ? av.t.fgDim : "gray"
      onLink: url => av.linkHandler(url)
    }
  }
}
