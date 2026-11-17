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
  // The parts drawn: `parts` only when it says something else. A message
  // is rendered anew on any change to the people, conversations or emoji,
  // and a new list, the same, would build every part (and its text) again.
  property var shown: []
  property string _key: ""
  function keep() {
    var k = JSON.stringify(body.parts || [])
    if (k === body._key) return
    body._key = k
    body.shown = body.parts || []
  }
  onPartsChanged: body.keep()
  Component.onCompleted: body.keep()
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

  // Pictures from other sites (link previews, apps' images) load straight
  // from them, so they only show while Preferences lets them
  // (app.previewImages); Slack's own (files, emoji, its image proxy) always.
  function shows(url) {
    if (!url) return false
    if (body.app.demo && /^data:image\//.test(url)) return true
    var host = U.previewHost(url)
    return !!host && (body.app.previewImages || U.slackImageHost(host))
  }

  function imageSource(url) {
    if (!body.shows(url)) return ""
    if (body.app.demo && /^data:image\//.test(url)) return url
    var local = body.ws.localFile(url)
    if (!local) Qt.callLater(function() {
      if (body.shows(url)) body.ws.fetchFile(url, "image", null, false, !body.app.previewImages)
    })
    return local ? "file://" + local : ""
  }

  Repeater {
    model: body.shown
    delegate: Loader {
      id: part
      required property var modelData
      width: body.width
      sourceComponent: ({ text: textC, quote: quoteC, code: codeC, header: headerC, section: sectionC, context: contextC,
                          divider: dividerC, image: imageC, actions: actionsC, video: videoC, attachment: attachmentC,
                          input: inputC, table: tableC })[modelData.t] || null
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
      // Markdown's # … ######: smaller as they go down.
      size: [body.t.fsTitle + 1, body.t.fsTitle + 1, body.t.fsTitle, body.t.fsText + 1, body.t.fsText, body.t.fsText, body.t.fsText][parent.modelData.level || 0]
      onLink: url => body.link(url)
    }
  }

  // A section: its text (quotes and code blocks too) and fields in a
  // column, the accessory (picture, button, menu, choices) on the right.
  // At most Slack's width, so the accessory sits where Slack puts it.
  Component {
    id: sectionC
    Item {
      id: sec
      readonly property var p: parent.modelData
      readonly property var acc: p.accessory
      readonly property bool accImage: !!acc && acc.kind === "image"
      readonly property real room: Math.min(width, body.t.sp(640))
      readonly property real accW: !acc ? 0 : accImage ? (body.shows(acc.url) ? body.t.sp(88) : 0) : accCtl.width
      implicitHeight: Math.max(secCol.implicitHeight, accImage ? (accW > 0 ? body.t.sp(88) : 0) : (acc ? accCtl.height : 0))
      Column {
        id: secCol
        width: sec.room - (sec.accW > 0 ? sec.accW + body.t.sp(16) : 0)
        spacing: body.t.sp(6)
        RichText { visible: sec.p.html !== ""; width: parent.width; app: body.app; html: sec.p.html; onLink: url => body.link(url) }
        // By URL: a MessageBody can't hold one by name.
        Loader {
          visible: (sec.p.sub || []).length > 0
          width: parent.width
          Component.onCompleted: if (visible) setSource("MessageBody.qml", { app: body.app, win: body.win, ws: body.ws, conv: body.conv, parts: sec.p.sub })
          onLoaded: {
            item.width = Qt.binding(function() { return secCol.width })
            item.msg = Qt.binding(function() { return body.msg })
            item.parts = Qt.binding(function() { return sec.p.sub })
          }
        }
        Grid {
          visible: sec.p.fields.length > 0
          columns: 2
          columnSpacing: body.t.sp(16)
          rowSpacing: body.t.sp(8)
          width: parent.width
          Repeater {
            model: sec.p.fields
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
      Image {
        visible: sec.accImage && sec.accW > 0
        x: sec.room - width
        width: body.t.sp(88); height: width
        source: visible ? body.imageSource(sec.acc.url) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
      BlockControl {
        id: accCtl
        visible: !!sec.acc && !sec.accImage
        x: sec.room - width
        app: body.app
        win: body.win
        ctl: sec.accImage ? null : sec.acc
        pick: sec.accImage || !sec.acc ? null : body.pickOf(sec.acc)
        onPressed: (c, o) => body.press(c, o)
      }
    }
  }

  Component {
    id: contextC
    Flow {
      id: cx
      readonly property var p: parent.modelData
      // (Cached messages from before `bits`: the images, then the words.)
      readonly property var bits: p.bits || p.images.map(function(u) { return { image: u } }).concat([{ html: p.html }])
      spacing: body.t.sp(6)
      Repeater {
        model: cx.bits
        delegate: Loader {
          required property var modelData
          sourceComponent: modelData.image ? ctxImg : ctxText
          Component {
            id: ctxImg
            Image {
              visible: body.shows(parent.modelData.image)
              width: visible ? body.t.sp(18) : 0; height: body.t.sp(18)
              source: visible ? body.imageSource(parent.modelData.image) : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }
          }
          Component {
            id: ctxText
            RichText {
              width: Math.min(implicitWidth, body.width)
              app: body.app
              html: parent.modelData.html
              size: body.t.fsSmall
              color: body.t.fgDim
              onLink: url => body.link(url)
            }
          }
        }
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
      // Its title, emoji drawn, and its size when Slack says it.
      RichText {
        visible: parent.p.title !== ""
        width: parent.width
        app: body.app
        html: (parent.p.titleHtml || U.escapeHtml(parent.p.title)) + (parent.p.bytes ? " (" + U.humanSize(parent.p.bytes, body.app.lang) + ")" : "")
        size: body.t.fsSmall
        color: body.t.fgDim
      }
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
        delegate: BlockControl {
          required property var modelData
          app: body.app
          win: body.win
          ctl: modelData
          pick: body.pickOf(modelData)
          onPressed: (c, o) => body.press(c, o)
        }
      }
    }
  }

  // An input block: its label (and "(optional)"), the element, the hint.
  Component {
    id: inputC
    Column {
      readonly property var p: parent.modelData
      spacing: body.t.sp(6)
      RichText {
        visible: parent.p.label !== ""
        width: parent.width
        app: body.app
        html: "<b>" + parent.p.label + "</b>" + (parent.p.optional ? " <span style=\"color:" + body.t.hex(body.t.fgDim) + ";\">" + U.escapeHtml(body.app.tr("(optional)", "(opcional)")) + "</span>" : "")
      }
      BlockControl {
        visible: !!parent.p.ctl
        app: body.app
        win: body.win
        ctl: parent.p.ctl
        pick: body.pickOf(parent.p.ctl)
        fill: parent.p.ctl && parent.p.ctl.kind === "field" ? Math.min(parent.width, body.t.sp(480)) : 0
        onPressed: (c, o) => body.press(c, o)
      }
      RichText { visible: parent.p.hint !== ""; width: parent.width; app: body.app; html: parent.p.hint; size: body.t.fsSmall; color: body.t.fgDim }
    }
  }

  // A table (Block Kit's, or a Markdown one): bordered cells, the first
  // row bold on a tint, each column aligned as asked.
  Component {
    id: tableC
    Item {
      id: tb
      readonly property var p: parent.modelData
      readonly property int cols: p.rows.reduce(function(n, r) { return Math.max(n, r.length) }, 0)
      // Each column as wide as its widest cell, the whole at most the message.
      readonly property var widths: {
        var w = []
        for (var c = 0; c < tb.cols; c++) w.push(body.t.sp(40))
        for (var i = 0; i < measure.count; i++) {
          var it = measure.itemAt(i)
          if (it) w[it.col] = Math.max(w[it.col], Math.min(body.t.sp(320), it.implicitWidth + body.t.sp(20)))
        }
        var total = w.reduce(function(a, b) { return a + b }, 0)
        if (total > tb.width && total > 0) w = w.map(function(x) { return x * tb.width / total })
        return w
      }
      implicitHeight: grid.height
      // Measured once, off screen.
      Repeater {
        id: measure
        model: tb.p.rows.reduce(function(all, r, ri) { return all.concat(r.map(function(h, ci) { return { html: h, col: ci, head: ri === 0 && tb.p.header } })) }, [])
        delegate: Text {
          required property var modelData
          readonly property int col: modelData.col
          visible: false
          text: modelData.head ? "<b>" + modelData.html + "</b>" : modelData.html
          textFormat: Text.RichText
          font.family: body.t.font
          font.pixelSize: body.t.fsText
        }
      }
      Rectangle {
        id: grid
        width: col.width + 2
        height: col.height + 2
        radius: Math.max(4, body.t.radiusSmall)
        color: "transparent"
        border.width: 1
        border.color: body.t.lineStrong
        clip: true
        Column {
          id: col
          x: 1; y: 1
          Repeater {
            model: tb.p.rows
            delegate: Row {
              id: tr
              required property var modelData
              required property int index
              readonly property bool head: index === 0 && tb.p.header
              // The row as tall as its tallest cell.
              readonly property real h: {
                var m = body.t.sp(30)
                for (var i = 0; i < cells.count; i++) { var it = cells.itemAt(i); if (it) m = Math.max(m, it.need) }
                return m
              }
              Repeater {
                id: cells
                model: tb.cols
                delegate: Rectangle {
                  required property int index
                  readonly property string html: tr.modelData[index] || ""
                  readonly property string align: tb.p.align[index] || "left"
                  width: tb.widths[index] || body.t.sp(40)
                  readonly property real need: cell.implicitHeight + body.t.sp(12)
                  height: tr.h
                  color: tr.head ? body.t.alpha(body.t.fg, 0.06) : "transparent"
                  border.width: 0
                  Rectangle { visible: index > 0; width: 1; height: parent.height; color: body.t.lineStrong }
                  Rectangle { visible: tr.index > 0; width: parent.width; height: 1; color: body.t.lineStrong }
                  RichText {
                    id: cell
                    x: body.t.sp(10)
                    y: body.t.sp(6)
                    width: parent.width - body.t.sp(20)
                    app: body.app
                    html: tr.head ? "<b>" + parent.html + "</b>" : parent.html
                    horizontalAlignment: parent.align === "right" ? Text.AlignRight : parent.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                    onLink: url => body.link(url)
                  }
                }
              }
            }
          }
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
      Component.onCompleted: setSource(p.work ? "WorkObjectView.qml" : p.isMsg ? "SharedMessageView.qml" : "AttachmentView.qml",
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
  function press(ctl, option) {
    if (!ctl) return
    // A choice of an overflow or a select with its own link opens it.
    if (option && option.url) { if (/^https?:\/\//i.test(option.url)) body.app.openUrl(option.url); return }
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
    var el = ctl.el || {}, type = el.type || ""
    var key = body.pickKey(ctl)
    var send = function(fields, pick) {
      if (pick) body.ws.setBlockPick(key, pick)
      body.ws.blockAction(body.conv, m, ctl, null, fields ? { fields: fields } : null)
    }
    // A button with a confirm asks first, in the app's words.
    if (type === "button" || type === "workflow_button") {
      var cf = el.confirm
      if (!cf) { body.ws.blockAction(body.conv, m, ctl); return }
      var words = function(o, fb) { return o && o.text ? String(o.text).replace(/[*_~`]/g, "") : fb }
      body.win.dialog("confirm", { title: words(cf.title, body.app.tr("Are you sure?", "Tem certeza?")), text: words(cf.text, ""),
                                   confirm: words(cf.confirm, "OK"), cancel: words(cf.deny, ""), danger: cf.style === "danger",
                                   action: function() { body.ws.blockAction(body.conv, m, ctl) } })
      return
    }
    if (type === "overflow") { if (option) body.ws.blockAction(body.conv, m, ctl, null, option); return }
    // A choice from a select's own options.
    if (option && /select$/.test(type) && !/^multi_/.test(type)) {
      body.ws.setBlockPick(key, { html: option.html })
      body.ws.blockAction(body.conv, m, ctl, null, option)
      return
    }
    function originals() {
      var all = (el.options || []).slice()
      ;(el.option_groups || []).forEach(function(g) { all = all.concat(g.options || []) })
      return all
    }
    if (type === "checkboxes" && option) {
      var cur = body.pickOf(ctl)
      var on = cur && cur.on ? cur.on.slice() : ctl.options.filter(function(o) { return o.on }).map(function(o) { return o.value })
      var i = on.indexOf(option.value)
      if (i >= 0) on.splice(i, 1); else on.push(option.value)
      send({ selected_options: originals().filter(function(o) { return on.indexOf(o.value) >= 0 }) }, { on: on })
      return
    }
    if (type === "radio_buttons" && option) {
      send({ selected_option: originals().filter(function(o) { return o.value === option.value })[0] || null }, { on: [option.value] })
      return
    }
    var pk = type.match(/^(multi_)?(users|conversations|channels)_select$/)
    if (pk) {
      var multi = !!pk[1], what = pk[2]
      body.win.dialog("blockPick", { kind: what, multi: multi, title: el.placeholder ? el.placeholder.text : "", onPick: function(ids) {
        if (!ids.length) return
        var names = ids.map(function(id) { return what === "users" ? "@" + body.ws.userName(id) : (body.ws.conv(id) && (body.ws.conv(id).kind === "channel" || body.ws.conv(id).kind === "private") ? "#" : "") + body.ws.convLabel(id) })
        var one = what === "users" ? "selected_user" : what === "channels" ? "selected_channel" : "selected_conversation"
        var f = {}
        f[multi ? one + "s" : one] = multi ? ids : ids[0]
        send(f, { html: U.escapeHtml(names.join(", ")) })
      } })
      return
    }
    var cur2 = body.pickOf(ctl) || {}
    if (type === "datepicker") {
      body.win.dialog("blockPick", { kind: "date", title: el.placeholder ? el.placeholder.text : "", date: cur2.ymd || el.initial_date || "", onPick: function(ymd) {
        send({ selected_date: ymd }, { html: U.escapeHtml(body.dayText(ymd)), ymd: ymd })
      } })
      return
    }
    if (type === "timepicker") {
      body.win.dialog("blockPick", { kind: "time", title: el.placeholder ? el.placeholder.text : body.app.tr("Pick a time", "Escolha um horário"), time: cur2.hm || el.initial_time || "", onPick: function(hm) {
        var p = hm.split(":")
        send({ selected_time: hm }, { html: U.escapeHtml(U.time(new Date(2000, 0, 1, +p[0], +p[1]), body.app.clock24)), hm: hm })
      } })
      return
    }
    if (type === "datetimepicker") {
      var at = cur2.at || el.initial_date_time || 0
      var dt0 = at ? new Date(at * 1000) : null
      body.win.dialog("blockPick", { kind: "datetime", date: dt0 ? Qt.formatDate(dt0, "yyyy-MM-dd") : "", time: dt0 ? Qt.formatTime(dt0, "HH:mm") : "", onPick: function(epoch) {
        var dt = new Date(epoch * 1000)
        send({ selected_date_time: epoch }, { date: U.escapeHtml(body.dayText(Qt.formatDate(dt, "yyyy-MM-dd"))), time: U.escapeHtml(U.time(dt, body.app.clock24)), at: epoch })
      } })
      return
    }
    // What this app can't pick here (an external select's options come
    // from the app): the message on Slack.
    Qt.openUrlExternally(body.ws.permalink(body.conv, m))
  }

  // Where a control's pick is kept (Workspace.blockPick).
  function pickKey(ctl) {
    if (!ctl) return ""
    return body.conv + "/" + (body.msg ? body.msg.ts : "") + "/" + (ctl.blockId || "") + "/" + ((ctl.el && ctl.el.action_id) || "")
  }
  function pickOf(ctl) { return body.ws && ctl ? body.ws.blockPick(body.pickKey(ctl)) : null }
  // "2026-11-17" → Today / Yesterday / Tomorrow / Nov 17, 2026.
  function dayText(ymd) {
    var m = String(ymd).match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (!m) return ymd
    var dt = new Date(+m[1], +m[2] - 1, +m[3])
    var diff = U.dayDiff(dt, new Date())
    return diff === 0 ? body.app.tr("Today", "Hoje") : diff === 1 ? body.app.tr("Yesterday", "Ontem") : diff === -1 ? body.app.tr("Tomorrow", "Amanhã") : U.shortDate(dt, body.app.lang)
  }
}
