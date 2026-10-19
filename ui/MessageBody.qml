import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg
import "../lib/Util.js" as U

// A message's body parts (lib/Mrkdwn.js): rich text, quotes, code blocks,
// Block Kit (headers, sections, context, images, buttons, dividers) and
// legacy attachments, which hold parts of their own.
Column {
  id: body
  property var app: Reg.service
  property var win
  property var ws
  property var parts: []
  property string conv: ""
  property var msg: null
  readonly property var t: app.theme
  spacing: t.sp(4)

  function link(url) {
    if (!url) return
    var m = url.match(/^slackqs:\/\/(user|channel)\/([A-Z0-9]+)$/)
    if (m) {
      if (m[1] === "user") { body.ws.profileUser = m[2]; body.ws.thread = null }
      else body.ws.open(m[2])
      return
    }
    body.app.openUrl(url)
  }

  function hostOf(url) { return ((String(url || "").match(/^https?:\/\/([^\/:?#]+)/i) || [])[1] || "").toLowerCase() }
  // Pictures from other sites (link previews, apps' images) load straight
  // from them, so they only show while Preferences lets them
  // (app.previewImages); Slack's own (files, emoji, its image proxy) always.
  function shows(url) {
    if (!url) return false
    return body.app.previewImages || /(^|\.)(slack\.com|slack-edge\.com|slack-imgs\.com)$/.test(body.hostOf(url))
  }

  function imageSource(url) {
    if (!url) return ""
    var host = body.hostOf(url)
    if (host === "slack.com" || /\.slack\.com$/.test(host)) {
      var local = body.ws.localFile(url)
      if (!local) Qt.callLater(function() { body.ws.fetchFile(url, "image") })
      return local ? "file://" + local : ""
    }
    return body.shows(url) ? url : ""
  }

  Repeater {
    model: body.parts
    delegate: Loader {
      id: part
      required property var modelData
      width: body.width
      sourceComponent: ({ text: textC, quote: quoteC, code: codeC, header: headerC, section: sectionC, context: contextC,
                          divider: dividerC, image: imageC, actions: actionsC, video: videoC, attachment: attachmentC })[modelData.t] || null
    }
  }

  Component {
    id: textC
    RichText {
      app: body.app
      html: parent.modelData.html
      muted: !!parent.modelData.muted
      jumbo: !!parent.modelData.jumbo
      onLink: url => body.link(url)
    }
  }

  Component {
    id: quoteC
    Item {
      implicitHeight: qt.implicitHeight
      Rectangle { width: body.t.sp(4); height: parent.height; radius: 2; color: body.t.alpha(body.t.fg, 0.28) }
      RichText {
        id: qt
        x: body.t.sp(14)
        width: parent.width - x
        app: body.app
        html: parent.parent.modelData.html
        muted: !!parent.parent.modelData.muted
        onLink: url => body.link(url)
      }
    }
  }

  Component {
    id: codeC
    Rectangle {
      id: codeBox
      readonly property string code: parent.modelData.text
      implicitHeight: codeText.implicitHeight + body.t.sp(16)
      radius: Math.max(4, body.t.radiusSmall)
      color: body.t.codeBg
      border.width: 1
      border.color: body.t.codeBorder
      TextEdit {
        id: codeText
        x: body.t.sp(10)
        y: body.t.sp(8)
        width: parent.width - body.t.sp(20)
        text: codeBox.code.replace(/\t/g, "    ")
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        color: body.t.fg
        selectionColor: body.t.alpha(body.t.accent, 0.35)
        font.family: "monospace"
        font.pixelSize: body.t.fsText - 1
      }
      IconButton {
        visible: codeHover.hovered
        app: body.app
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: body.t.sp(4)
        size: body.t.sp(24)
        icon: "󰆏"
        iconSize: body.t.fsSmall
        tip: body.app.tr("Copy", "Copiar")
        onClicked: { body.app.copy(codeBox.code); body.win.toast(body.app.tr("Code copied", "Código copiado")) }
      }
      HoverHandler { id: codeHover }
    }
  }

  Component {
    id: headerC
    RichText {
      app: body.app
      html: "<b>" + parent.modelData.html + "</b>"
      size: body.t.fsTitle + 1
      onLink: url => body.link(url)
    }
  }

  Component {
    id: sectionC
    Item {
      readonly property var p: parent.modelData
      implicitHeight: Math.max(secCol.implicitHeight, acc.visible ? acc.height : 0)
      Column {
        id: secCol
        width: parent.width - (acc.visible ? acc.width + body.t.sp(12) : 0)
        spacing: body.t.sp(6)
        RichText { visible: parent.parent.p.html !== ""; width: parent.width; app: body.app; html: parent.parent.p.html; onLink: url => body.link(url) }
        Grid {
          visible: parent.parent.p.fields.length > 0
          columns: 2
          columnSpacing: body.t.sp(16)
          rowSpacing: body.t.sp(6)
          width: parent.width
          Repeater {
            model: secCol.parent.p.fields
            delegate: RichText {
              required property var modelData
              width: (secCol.width - body.t.sp(16)) / 2
              app: body.app
              html: modelData
              onLink: url => body.link(url)
            }
          }
        }
      }
      Loader {
        id: acc
        visible: !!parent.p.accessory && (parent.p.accessory.kind !== "image" || body.shows(parent.p.accessory.url))
        anchors.right: parent.right
        width: item ? item.width : 0
        height: item ? item.height : 0
        sourceComponent: !parent.p.accessory ? null : (parent.p.accessory.kind === "image" ? accImg : accBtn)
        Component {
          id: accImg
          Image {
            width: body.t.sp(88); height: width
            source: body.imageSource(acc.parent.p.accessory.url)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
        }
        Component {
          id: accBtn
          SButton {
            app: body.app
            small: true
            text: acc.parent.p.accessory.label
            kind: acc.parent.p.accessory.style === "primary" ? "green" : (acc.parent.p.accessory.style === "danger" ? "danger" : "secondary")
            onClicked: body.press(acc.parent.p.accessory)
          }
        }
      }
    }
  }

  Component {
    id: contextC
    Flow {
      readonly property var p: parent.modelData
      spacing: body.t.sp(6)
      Repeater {
        model: parent.p.images
        delegate: Image {
          required property var modelData
          visible: body.shows(modelData)
          width: body.t.sp(16); height: width
          source: body.imageSource(modelData)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
      }
      RichText {
        width: Math.min(implicitWidth, body.width)
        app: body.app
        html: parent.p.html
        size: body.t.fsSmall
        color: body.t.fgDim
        onLink: url => body.link(url)
      }
    }
  }

  Component {
    id: dividerC
    Item { implicitHeight: body.t.sp(12); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: body.t.line } }
  }

  Component {
    id: imageC
    Column {
      readonly property var p: parent.modelData
      spacing: body.t.sp(4)
      Text { visible: parent.p.title !== ""; text: parent.p.title; textFormat: Text.PlainText; color: body.t.fgDim; font.family: body.t.font; font.pixelSize: body.t.fsSmall; width: parent.width; elide: Text.ElideRight }
      SlackImage {
        visible: body.shows(parent.p.url)
        app: body.app
        source: body.imageSource(parent.p.url)
        natW: parent.p.w
        natH: parent.p.h
        maxW: Math.min(body.width, body.t.sp(480))
        onOpen: body.win.viewImage({ name: parent.parent.p.title || "image", full: parent.parent.p.url, thumb: parent.parent.p.url, w: parent.parent.p.w, h: parent.parent.p.h, external: true })
      }
    }
  }

  Component {
    id: actionsC
    Flow {
      readonly property var p: parent.modelData
      spacing: body.t.sp(8)
      Repeater {
        model: parent.p.items
        delegate: SButton {
          required property var modelData
          app: body.app
          small: true
          text: modelData.label
          kind: modelData.style === "primary" ? "green" : (modelData.style === "danger" ? "danger" : "secondary")
          onClicked: body.press(modelData)
        }
      }
    }
  }

  Component {
    id: videoC
    Row {
      readonly property var p: parent.modelData
      spacing: body.t.sp(8)
      Glyph { app: body.app; icon: "󰐊"; color: body.t.link; anchors.verticalCenter: parent.verticalCenter }
      RichText {
        app: body.app
        width: Math.min(implicitWidth, body.width - body.t.sp(30))
        html: "<a href=\"" + U.escapeHtml(parent.p.url) + "\">" + U.escapeHtml(parent.p.title || parent.p.url) + "</a>"
        onLink: url => body.link(url)
      }
    }
  }

  Component {
    id: attachmentC
    Loader {
      readonly property var p: parent.modelData
      // Handed in as it's made, so its bindings never see it without them.
      Component.onCompleted: setSource(p.work ? "WorkObjectView.qml" : "AttachmentView.qml",
                                       { app: body.app, win: body.win, ws: body.ws, conv: body.conv, att: p,
                                         linkHandler: body.link, imageSource: body.imageSource, pressHandler: body.press })
      onLoaded: {
        item.width = Qt.binding(function() { return body.width })
        item.msg = Qt.binding(function() { return body.msg })
      }
    }
  }

  // An app's buttons: one with a URL opens it; Slack's app install requests
  // open the approval window (DlgAppApproval); other buttons go to the app as
  // the official client sends them (Workspace.blockAction /
  // attachmentAction). Menus and pickers this app doesn't draw: the message
  // on Slack.
  function press(ctl) {
    if (!ctl) return
    if (ctl.url) { if (/^https?:\/\//i.test(ctl.url)) body.app.openUrl(ctl.url); return }
    var m = body.msg
    if (!m || !body.conv || !body.ws) return
    if (ctl.legacy) {
      var req = body.ws.appRequestOf(ctl)
      if (req) {
        var named = (m.attachments || []).filter(function(a) { return a.title && String(a.title_link || "").indexOf("/marketplace/" + req.appId) >= 0 })[0]
        req.appName = named ? named.title : ""
        body.win.dialog("appApproval", { req: req, approve: ctl.legacy.value === "approved" || ctl.legacy.value === "approved_child_app_auto_install" })
        return
      }
      body.ws.attachmentAction(body.conv, m, ctl)
      return
    }
    if (ctl.el && ctl.el.type === "button") { body.ws.blockAction(body.conv, m, ctl); return }
    Qt.openUrlExternally(body.ws.permalink(body.conv, m))
  }
}
