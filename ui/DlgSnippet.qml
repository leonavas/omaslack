import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U

// Slack's "Create snippet": a title, the type (Auto Detect by default), the
// content in a monospace box with line numbers, wrap, and a message to go
// with it. Create Snippet (Ctrl+Enter) posts it to the conversation (or
// thread) the message box is in. args: {conv, threadTs, content, onDone}.
DialogFrame {
  id: d
  title: app.tr("Create snippet", "Criar snippet")
  subtitle: d.where
  cardWidth: t.sp(640)
  initialFocus: content.area

  property string type: ""
  property bool wrap: false
  readonly property bool ready: content.area.text.trim() !== ""
  readonly property string where: {
    if (!d.ws || !d.args.conv) return ""
    var c = d.ws.conv(d.args.conv)
    var name = d.ws.convLabel(d.args.conv)
    var to = c && (c.kind === "im" || c.kind === "mpim") ? name : "#" + name
    return d.args.threadTs ? d.app.tr("Shared in a thread in ", "Compartilhado numa conversa em ") + to
                           : d.app.tr("Shared in ", "Compartilhado em ") + to
  }

  function typeLabel(v) {
    var o = U.SNIPPET_TYPES.filter(function(x) { return x[0] === v })[0]
    return !o ? v : o[0] === "" ? d.app.tr("Auto Detect Type", "Detectar tipo") : o[0] === "text" ? d.app.tr("Plain Text", "Texto simples") : o[1]
  }
  function pickType() {
    function item(o) { return { label: d.typeLabel(o[0]), checked: d.type === o[0], action: function() { d.type = o[0] } } }
    var common = ["", "text", "json", "javascript", "typescript", "python", "shell", "sql", "yaml", "markdown"]
    var items = U.SNIPPET_TYPES.filter(function(o) { return common.indexOf(o[0]) >= 0 }).map(item)
    items.push({ separator: true })
    items.push({ label: d.app.tr("More types", "Mais tipos"), sub: U.SNIPPET_TYPES.filter(function(o) { return common.indexOf(o[0]) < 0 }).map(item) })
    d.win.menuAt(typeBtn, items, 0, typeBtn.height + d.t.sp(4))
  }

  function create() {
    if (!d.ready) return
    d.ws.sendSnippet(d.args.conv, d.args.threadTs || "", content.area.text, titleField.text, d.type, message.text)
    var done = d.args.onDone
    d.closed()
    if (done) done()
  }

  Column {
    width: parent.width
    spacing: d.t.sp(6)

    Row {
      width: parent.width
      spacing: d.t.sp(12)
      Column {
        width: parent.width - typeCol.width - parent.spacing
        spacing: d.t.sp(6)
        Text { text: d.app.tr("Title (optional)", "Título (opcional)"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
        SField {
          id: titleField
          app: d.app
          width: parent.width
          placeholderText: "snippet." + U.snippetExt(d.type)
          onAccepted: content.area.forceActiveFocus()
        }
      }
      Column {
        id: typeCol
        width: d.t.sp(190)
        spacing: d.t.sp(6)
        Text { text: d.app.tr("Type", "Tipo"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
        Rectangle {
          id: typeBtn
          width: parent.width
          height: titleField.height
          radius: Math.max(4, d.t.radiusSmall)
          color: typeMa.containsMouse ? d.t.hover : d.t.alpha(d.t.bg, 0.6)
          border.width: 1
          border.color: d.t.lineStrong
          Text {
            anchors.left: parent.left
            anchors.leftMargin: d.t.sp(10)
            anchors.right: chev.left
            anchors.rightMargin: d.t.sp(6)
            anchors.verticalCenter: parent.verticalCenter
            text: d.typeLabel(d.type)
            textFormat: Text.PlainText
            color: d.t.fg
            font.family: d.t.font
            font.pixelSize: d.t.fsText
            elide: Text.ElideRight
          }
          Glyph { id: chev; app: d.app; anchors.right: parent.right; anchors.rightMargin: d.t.sp(10); anchors.verticalCenter: parent.verticalCenter; icon: "󰅀"; size: d.t.fsSmall; color: d.t.fgDim }
          MouseArea { id: typeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.pickType() }
        }
      }
    }

    Item { width: 1; height: d.t.sp(6) }

    Text { text: d.app.tr("Content", "Conteúdo"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
    // The code: line numbers beside it (hidden while lines wrap, where
    // they would stop matching).
    ScrollView {
      id: content
      property alias area: area
      width: parent.width
      height: d.t.sp(220)
      clip: true
      background: Rectangle {
        radius: Math.max(4, d.t.radiusSmall)
        color: d.t.alpha(d.t.bg, 0.6)
        border.width: area.activeFocus ? 2 : 1
        border.color: area.activeFocus ? d.t.accent : d.t.lineStrong
      }
      TextArea {
        id: area
        text: d.args.content || ""
        color: d.t.fg
        placeholderTextColor: d.t.fgDim
        selectionColor: d.t.alpha(d.t.accent, 0.35)
        selectByMouse: true
        wrapMode: d.wrap ? TextEdit.Wrap : TextEdit.NoWrap
        font.family: "monospace"
        font.pixelSize: d.t.fsSmall
        topPadding: d.t.sp(10)
        bottomPadding: d.t.sp(10)
        rightPadding: d.t.sp(10)
        leftPadding: d.wrap ? d.t.sp(10) : lineNos.width + d.t.sp(20)
        background: null
        Keys.onPressed: event => {
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { d.create(); event.accepted = true }
          else if (event.key === Qt.Key_Tab && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) { area.insert(area.cursorPosition, "  "); event.accepted = true }
        }
        Text {
          id: lineNos
          visible: !d.wrap
          x: d.t.sp(10)
          y: area.topPadding
          width: Math.max(d.t.sp(14), noMetrics.width)
          horizontalAlignment: Text.AlignRight
          text: { var n = Math.max(1, area.lineCount), out = []; for (var i = 1; i <= n; i++) out.push(i); return out.join("\n") }
          textFormat: Text.PlainText
          color: d.t.alpha(d.t.fgDim, 0.7)
          font: area.font
          lineHeightMode: Text.FixedHeight
          lineHeight: area.lineCount > 0 ? area.contentHeight / area.lineCount : noMetrics.height
          TextMetrics { id: noMetrics; font: area.font; text: String(Math.max(1, area.lineCount)).replace(/./g, "0") }
        }
      }
    }
    Row {
      width: parent.width
      spacing: d.t.sp(8)
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: d.t.sp(14); height: width; radius: 3
        color: d.wrap ? d.t.accent : "transparent"
        border.width: d.wrap ? 0 : 1
        border.color: d.t.lineStrong
        Glyph { app: d.app; anchors.centerIn: parent; visible: d.wrap; icon: "󰄬"; size: d.t.fsTiny; color: d.t.onColor(d.t.accent) }
      }
      Text { anchors.verticalCenter: parent.verticalCenter; text: d.app.tr("Wrap", "Quebrar linhas"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsSmall
             MouseArea { anchors.fill: parent; anchors.leftMargin: -d.t.sp(22); cursorShape: Qt.PointingHandCursor; onClicked: d.wrap = !d.wrap } }
    }

    Item { width: 1; height: d.t.sp(6) }

    SArea {
      id: message
      app: d.app
      width: parent.width
      implicitHeight: d.t.sp(72)
      placeholderText: d.app.tr("Add a message, if you'd like.", "Adicione uma mensagem, se quiser.")
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton { app: d.app; kind: "primary"; text: d.app.tr("Create Snippet", "Criar snippet"); enabled2: d.ready; onClicked: d.create() }
  }
}
