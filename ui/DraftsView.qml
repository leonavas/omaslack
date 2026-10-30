import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Registry.js" as Reg

// Slack's "Drafts & sent": the messages you started and didn't send (a
// conversation's box or a thread's), and the ones you sent from here.
Rectangle {
  id: dv
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  property string tab: "drafts"
  color: t.pane

  // [{key, conv, threadTs, text, label}] by conversation (drafts carry no
  // time), a conversation's own box before its threads.
  readonly property var drafts: {
    if (!ws) return []
    ws.draftsRev; ws.draftTextRev; ws.convsRev; ws.usersRev
    var out = []
    for (var key in ws.drafts) {
      var text = ws.drafts[key]
      if (!text || !String(text).trim()) continue
      var i = key.indexOf("/")
      var conv = i >= 0 ? key.slice(0, i) : key
      out.push({ key: key, conv: conv, threadTs: i >= 0 ? key.slice(i + 1) : "", text: String(text), label: ws.convLabel(conv) || conv })
    }
    out.sort(function(a, b) { return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : (a.label.toLowerCase() > b.label.toLowerCase() ? 1 : U.cmpTs(a.threadTs, b.threadTs)) })
    return out
  }
  readonly property var sent: {
    if (!ws) return []
    return ws.sentLog.map(function(e) { return { key: e.conv + "/" + e.ts, conv: e.conv, ts: e.ts, threadTs: e.threadTs || "", text: e.text } })
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: dv.t.sp(52)
    Row {
      x: dv.t.sp(20)
      anchors.verticalCenter: parent.verticalCenter
      spacing: dv.t.sp(10)
      Glyph { app: dv.app; icon: "󰒊"; size: dv.t.fsHeader; color: dv.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
      Text {
        text: dv.app.tr("Drafts & sent", "Rascunhos e enviados")
        color: dv.t.fgBright
        font.family: dv.t.font
        font.pixelSize: dv.t.fsHeader
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    IconButton {
      anchors.right: parent.right
      anchors.rightMargin: dv.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      app: dv.app
      icon: "󰏫"
      tip: dv.app.tr("New message", "Nova mensagem") + "  Ctrl+N"
      onClicked: dv.win.dialog("newMessage")
    }
  }

  Item {
    id: tabs
    y: header.height
    width: parent.width
    height: dv.t.sp(36)
    Row {
      x: dv.t.sp(14)
      height: parent.height
      spacing: dv.t.sp(4)
      HeaderTab {
        app: dv.app; icon: "󰏫"
        label: dv.app.tr("Drafts", "Rascunhos") + (dv.drafts.length ? " " + dv.drafts.length : "")
        active: dv.tab === "drafts"
        onClicked: dv.tab = "drafts"
      }
      HeaderTab {
        app: dv.app; icon: "󰒊"
        label: dv.app.tr("Sent", "Enviados")
        active: dv.tab === "sent"
        onClicked: dv.tab = "sent"
      }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: dv.t.line }
  }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    anchors.top: tabs.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    topMargin: dv.t.sp(8)
    bottomMargin: dv.t.sp(16)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: dv.tab === "drafts" ? dv.drafts : dv.sent; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: dv.app }

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      readonly property var c: dv.ws.conv(modelData.conv)
      readonly property bool isDraft: dv.tab === "drafts"
      readonly property bool hot: rowMa.containsMouse || actions.hovered
      width: list.width
      height: content.implicitHeight + dv.t.sp(24)

      Rectangle {
        x: dv.t.sp(12)
        width: parent.width - dv.t.sp(24)
        height: parent.height
        radius: Math.max(6, dv.t.radiusSmall)
        color: rowMa.pressed ? dv.t.hoverStrong : (row.hot ? dv.t.hover : "transparent")
      }
      Rectangle {
        visible: row.index > 0 && !row.hot
        x: dv.t.sp(24)
        width: parent.width - dv.t.sp(48)
        height: 1
        color: dv.t.line
      }

      MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
          if (mouse.button === Qt.RightButton) { var p = rowMa.mapToItem(dv.win.contentItem, mouse.x, mouse.y); dv.rowMenu(row.modelData, row.isDraft, p.x, p.y); return }
          if (row.isDraft) dv.edit(row.modelData)
          else dv.openSent(row.modelData)
        }
      }

      // Who or where: the photo of a DM, the channel's mark otherwise.
      Item {
        id: lead
        x: dv.t.sp(24)
        y: dv.t.sp(12)
        width: dv.t.sp(36)
        height: width
        Avatar {
          visible: !!row.c && row.c.kind === "im"
          anchors.fill: parent
          app: dv.app
          ws: dv.ws
          user: row.c ? (row.c.user || "") : ""
          size: parent.width
          showPresence: true
          ring: row.hot ? Qt.tint(dv.t.pane, dv.t.hover) : dv.t.pane
          onClicked: row.isDraft ? dv.edit(row.modelData) : dv.openSent(row.modelData)
        }
        Rectangle {
          visible: !row.c || row.c.kind !== "im"
          anchors.fill: parent
          radius: Math.round(width * 0.22)
          color: dv.t.alpha(dv.t.fg, 0.09)
          Glyph {
            app: dv.app
            anchors.centerIn: parent
            icon: !row.c ? "#" : (row.c.kind === "private" ? "󰌾" : (row.c.kind === "mpim" ? "󰀏" : "#"))
            size: dv.t.fsTitle + 1
            font.bold: true
            color: dv.t.fgSoft
          }
        }
      }

      Column {
        id: content
        anchors.left: lead.right
        anchors.leftMargin: dv.t.sp(12)
        anchors.right: parent.right
        anchors.rightMargin: dv.t.sp(28)
        y: dv.t.sp(12)
        spacing: dv.t.sp(3)

        Item {
          width: parent.width
          height: titleRow.implicitHeight
          Row {
            id: titleRow
            width: parent.width - stamp.width - dv.t.sp(8)
            spacing: dv.t.sp(6)
            Text {
              id: title
              text: (row.c && (row.c.kind === "channel" || row.c.kind === "private") ? "#" : "") + (dv.ws.convLabel(row.modelData.conv) || row.modelData.conv)
              textFormat: Text.PlainText
              color: dv.t.fgBright
              font.family: dv.t.font
              font.pixelSize: dv.t.fsText
              font.bold: true
              elide: Text.ElideRight
              width: Math.min(implicitWidth, titleRow.width - (thr.visible ? thr.implicitWidth + dv.t.sp(6) : 0))
            }
            Text {
              id: thr
              visible: row.modelData.threadTs !== ""
              text: dv.app.tr("in a thread", "numa conversa")
              color: dv.t.fgDim
              font.family: dv.t.font
              font.pixelSize: dv.t.fsSmall
              anchors.baseline: title.baseline
            }
          }
          Text {
            id: stamp
            visible: !row.isDraft && !row.hot
            anchors.right: parent.right
            y: title.baselineOffset - baselineOffset
            text: row.modelData.ts ? U.shortStamp(row.modelData.ts, dv.app.lang, dv.app.clock24) : ""
            color: dv.t.fgDim
            font.family: dv.t.font
            font.pixelSize: dv.t.fsSmall
          }
        }
        Text {
          width: parent.width
          // Drafts and sent alike are box markup: pills, emoji and links as words.
          text: Md.flat(Model.parseMessage({ text: row.modelData.text }), dv.ctx, 400)
          color: dv.t.fg
          font.family: dv.t.font
          font.pixelSize: dv.t.fsText - 1
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      // Hover: Edit / Delete (drafts), Open / Copy (sent).
      Rectangle {
        id: actions
        readonly property bool hovered: actHover.hovered
        visible: row.hot
        anchors.right: parent.right
        anchors.rightMargin: dv.t.sp(22)
        y: dv.t.sp(8)
        height: dv.t.sp(32)
        width: actRow.implicitWidth + dv.t.sp(6)
        radius: Math.max(6, dv.t.radiusSmall)
        color: dv.t.popup
        border.width: 1
        border.color: dv.t.lineStrong
        HoverHandler { id: actHover }
        Row {
          id: actRow
          anchors.centerIn: parent
          spacing: dv.t.sp(1)
          IconButton {
            app: dv.app; size: dv.t.sp(28)
            icon: row.isDraft ? "󰏫" : "󰁔"
            tip: row.isDraft ? dv.app.tr("Edit message", "Editar mensagem") : dv.app.tr("Go to message", "Ir para a mensagem")
            onClicked: row.isDraft ? dv.edit(row.modelData) : dv.openSent(row.modelData)
          }
          IconButton {
            app: dv.app; size: dv.t.sp(28)
            icon: row.isDraft ? "󰆴" : "󰆏"
            color: row.isDraft && hovered ? dv.t.red : dv.t.fgSoft
            tip: row.isDraft ? dv.app.tr("Delete draft", "Excluir rascunho") : dv.app.tr("Copy text", "Copiar texto")
            onClicked: row.isDraft ? dv.remove(row.modelData) : dv.copySent(row.modelData)
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: (dv.tab === "drafts" ? dv.drafts.length : dv.sent.length) === 0
    anchors.centerIn: list
    width: Math.min(parent.width - dv.t.sp(60), dv.t.sp(400))
    spacing: dv.t.sp(10)
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: dv.t.sp(72); height: width
      radius: Math.max(12, dv.t.radiusCard + 6)
      color: dv.t.alpha(dv.t.accent, 0.16)
      Glyph { app: dv.app; anchors.centerIn: parent; icon: dv.tab === "drafts" ? "󰏫" : "󰒊"; size: dv.t.sp(32); color: dv.t.accent }
    }
    Item { width: 1; height: dv.t.sp(4) }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: dv.tab === "drafts" ? dv.app.tr("No drafts", "Nenhum rascunho") : dv.app.tr("Nothing sent yet", "Nada enviado ainda")
      color: dv.t.fgBright
      font.family: dv.t.font
      font.pixelSize: dv.t.fsHeader
      font.bold: true
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: dv.tab === "drafts"
            ? dv.app.tr("Messages you start writing and don't send are kept here, in every conversation and thread.", "As mensagens que você começa a escrever e não envia ficam guardadas aqui, de cada conversa e de cada thread.")
            : dv.app.tr("Messages you send from this app show up here, so you can find them again.", "As mensagens que você envia por este app aparecem aqui, para achá-las de novo.")
      color: dv.t.fgDim
      font.family: dv.t.font
      font.pixelSize: dv.t.fsText
      lineHeight: 1.15
    }
  }

  // ---------------------------------------------------------------- actions
  function edit(d) {
    dv.ws.open(d.conv, d.threadTs ? { threadTs: d.threadTs } : {})
    if (!d.threadTs) Qt.callLater(function() { dv.win.focusComposer() })
  }

  function remove(d) {
    dv.ws.setDraft(d.key, "")
    dv.app.setTeamSetting(dv.ws.teamId, "drafts", dv.ws.drafts)
    dv.win.toast(dv.app.tr("Draft deleted", "Rascunho excluído"))
  }

  function openSent(s) {
    if (s.threadTs) dv.ws.open(s.conv, { ts: s.threadTs, threadTs: s.threadTs })
    else dv.ws.open(s.conv, { ts: s.ts })
  }

  function copySent(s) {
    dv.app.copy(Md.flat(Model.parseMessage({ text: s.text }), dv.ctx, 0))
    dv.win.toast(dv.app.tr("Message copied", "Mensagem copiada"))
  }

  function rowMenu(d, isDraft, x, y) {
    var items = []
    if (isDraft) {
      items.push({ label: dv.app.tr("Edit message", "Editar mensagem"), icon: "󰏫", action: function() { dv.edit(d) } })
      items.push({ label: dv.app.tr("Copy text", "Copiar texto"), icon: "󰆏", action: function() { dv.app.copy(d.text); dv.win.toast(dv.app.tr("Copied", "Copiado")) } })
      items.push({ separator: true })
      items.push({ label: dv.app.tr("Delete draft", "Excluir rascunho"), icon: "󰆴", danger: true, action: function() { dv.remove(d) } })
    } else {
      items.push({ label: dv.app.tr("Go to message", "Ir para a mensagem"), icon: "󰁔", action: function() { dv.openSent(d) } })
      items.push({ label: dv.app.tr("Copy text", "Copiar texto"), icon: "󰆏", action: function() { dv.copySent(d) } })
      items.push({ label: dv.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() {
        dv.app.copy(dv.ws.permalink(d.conv, { ts: d.ts, threadTs: d.threadTs })); dv.win.toast(dv.app.tr("Link copied", "Link copiado")) } })
    }
    dv.win.menu(items, x, y)
  }
}
