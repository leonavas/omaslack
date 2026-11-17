import QtQuick
import Quickshell.Io
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A snippet in a message, as Slack draws it: its title and type, then the
// code with line numbers, the first lines only, fading out, with "Show
// more (N lines)" over them. Expanded, the whole text comes (fetched once
// with the session) and "Show less" folds it back. On hover: copy, open,
// download, copy link.
Column {
  id: sv
  property var app: Reg.service
  property var win
  property var ws
  property var file: ({})
  property real maxW: 600
  readonly property var t: app.theme
  readonly property int collapsedLines: 5
  property bool expanded: false
  property string full: ""
  property bool loading: false
  property var _then: null

  readonly property string shown: (sv.expanded && sv.full !== "" ? sv.full : String(sv.file.preview || "")).replace(/\r\n?/g, "\n").replace(/\n+$/, "")
  readonly property var allLines: sv.shown.split("\n")
  readonly property var lines: sv.expanded ? sv.allLines : sv.allLines.slice(0, sv.collapsedLines)
  readonly property int total: Math.max(sv.file.lines || 0, sv.allLines.length + (sv.expanded && sv.full !== "" ? 0 : (sv.file.linesMore || 0)))
  readonly property bool more: !sv.expanded && sv.total > sv.lines.length
  readonly property bool hovered: hover.hovered

  width: Math.min(sv.maxW, sv.t.sp(720))
  spacing: sv.t.sp(4)

  HoverHandler { id: hover }

  // The whole text, once: from the cache or fetched (Workspace.fetchFile).
  function fetchFull(then) {
    if (sv.full !== "") { if (then) then(); return }
    if (then) sv._then = then
    if (sv.loading) return
    var url = sv.file.full || sv.file.download
    if (!url || !sv.ws) return
    sv.loading = true
    var have = sv.ws.fetchFile(url, (sv.file.id || "snippet") + "-" + (sv.file.name || "snippet.txt"), function(path) {
      if (path) reader.path = path
      else { sv.loading = false; sv._then = null; if (sv.win) sv.win.toast(sv.app.tr("Couldn't load the snippet", "Não carregou o snippet")) }
    })
    if (have) reader.path = have
  }
  FileView {
    id: reader
    printErrors: false
    onLoaded: {
      sv.full = String(reader.text() || "")
      sv.loading = false
      var f = sv._then
      sv._then = null
      if (f) f()
    }
    onLoadFailed: { sv.loading = false; sv._then = null; if (sv.win) sv.win.toast(sv.app.tr("Couldn't load the snippet", "Não carregou o snippet")) }
  }
  function toggle() {
    if (sv.expanded) { sv.expanded = false; return }
    if (sv.total > sv.allLines.length && sv.full === "") sv.fetchFull(function() { sv.expanded = true })
    else sv.expanded = true
  }
  function copyText() {
    sv.fetchFull(function() {
      sv.app.copy(sv.full)
      if (sv.win) sv.win.toast(sv.app.tr("Snippet copied", "Snippet copiado"))
    })
  }

  // Title · type
  Row {
    spacing: sv.t.sp(8)
    width: parent.width
    Text {
      id: titleText
      text: sv.file.title || sv.file.name || sv.app.tr("Untitled", "Sem título")
      textFormat: Text.PlainText
      color: titleMa.containsMouse ? sv.t.link : sv.t.fgBright
      font.family: sv.t.font
      font.pixelSize: sv.t.fsSmall
      font.bold: true
      font.underline: titleMa.containsMouse
      width: Math.min(implicitWidth, parent.width - typeText.width - sv.t.sp(8))
      elide: Text.ElideMiddle
      MouseArea { id: titleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sv.ws.openFile(sv.file) }
    }
    Text {
      id: typeText
      anchors.baseline: titleText.baseline
      text: (sv.file.prettyType || (sv.file.filetype || "").toUpperCase()) + (sv.total ? "  ·  " + sv.total + " " + (sv.total === 1 ? sv.app.tr("line", "linha") : sv.app.tr("lines", "linhas")) : "")
      textFormat: Text.PlainText
      color: sv.t.fgDim
      font.family: sv.t.font
      font.pixelSize: sv.t.fsTiny
    }
  }

  Rectangle {
    id: box
    width: parent.width
    height: code.height + sv.t.sp(16) + (sv.expanded && sv.total > sv.collapsedLines ? lessBar.height : 0)
    radius: Math.max(6, sv.t.radiusCard)
    color: sv.t.alpha(sv.t.fg, 0.035)
    border.width: 1
    border.color: sv.t.lineStrong
    clip: true

    readonly property int lineH: Math.ceil(codeMetrics.height * 1.35)
    TextMetrics { id: codeMetrics; font.family: "monospace"; font.pixelSize: sv.t.fsSmall; text: "Mg" }

    // Line numbers
    Text {
      id: gutter
      x: sv.t.sp(10)
      y: sv.t.sp(8)
      width: Math.max(sv.t.sp(16), gutterMetrics.width)
      horizontalAlignment: Text.AlignRight
      text: sv.lines.map(function(_, i) { return i + 1 }).join("\n")
      textFormat: Text.PlainText
      color: sv.t.alpha(sv.t.fgDim, 0.7)
      font.family: "monospace"
      font.pixelSize: sv.t.fsSmall
      lineHeightMode: Text.FixedHeight
      lineHeight: box.lineH
      TextMetrics { id: gutterMetrics; font: gutter.font; text: String(sv.total || sv.lines.length).replace(/./g, "0") }
    }
    Rectangle { x: gutter.x + gutter.width + sv.t.sp(8); y: 0; width: 1; height: parent.height; color: sv.t.alpha(sv.t.lineStrong, 0.6) }

    // The code: wide lines scroll sideways.
    Flickable {
      id: code
      x: gutter.x + gutter.width + sv.t.sp(17)
      y: sv.t.sp(8)
      width: box.width - x - sv.t.sp(10)
      height: codeText.implicitHeight
      contentWidth: codeText.implicitWidth
      contentHeight: codeText.implicitHeight
      flickableDirection: Flickable.HorizontalFlick
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentWidth > width
      clip: true
      TextEdit {
        id: codeText
        text: sv.lines.join("\n")
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        color: sv.t.fg
        selectionColor: sv.t.alpha(sv.t.accent, 0.35)
        font.family: "monospace"
        font.pixelSize: sv.t.fsSmall
        wrapMode: TextEdit.NoWrap
        // TextEdit has no lineHeight: the gutter follows its own lines.
        Component.onCompleted: gutter.lineHeight = Qt.binding(function() { return codeText.lineCount > 0 ? codeText.contentHeight / codeText.lineCount : box.lineH })
      }
    }

    // Folded: the last lines fade out under "Show more".
    Rectangle {
      visible: sv.more
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 1
      height: Math.min(parent.height - 2, sv.t.sp(56))
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.85; color: sv.t.bg }
      }
    }
    Rectangle {
      id: morePill
      visible: sv.more
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: sv.t.sp(8)
      width: moreRow.implicitWidth + sv.t.sp(20)
      height: sv.t.sp(24)
      radius: height / 2
      color: moreMa.containsMouse ? sv.t.hoverStrong : sv.t.popup
      border.width: 1
      border.color: sv.t.lineStrong
      Row {
        id: moreRow
        anchors.centerIn: parent
        spacing: sv.t.sp(6)
        Spinner { app: sv.app; visible: sv.loading; size: sv.t.sp(12); color: sv.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
        Glyph { app: sv.app; visible: !sv.loading; icon: "󰁌"; size: sv.t.fsSmall; color: sv.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: sv.app.tr("Show more", "Mostrar mais") + " (" + (sv.total - sv.lines.length) + " " + (sv.total - sv.lines.length === 1 ? sv.app.tr("line", "linha") : sv.app.tr("lines", "linhas")) + ")"
          textFormat: Text.PlainText
          color: sv.t.fgBright
          font.family: sv.t.font
          font.pixelSize: sv.t.fsSmall
        }
      }
      MouseArea { id: moreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sv.toggle() }
    }

    // Expanded: fold back.
    Item {
      id: lessBar
      visible: sv.expanded && sv.total > sv.collapsedLines
      anchors.bottom: parent.bottom
      width: parent.width
      height: sv.t.sp(32)
      Rectangle { width: parent.width; height: 1; color: sv.t.alpha(sv.t.lineStrong, 0.6) }
      Text {
        anchors.centerIn: parent
        text: "󰁝  " + sv.app.tr("Show less", "Mostrar menos")
        textFormat: Text.PlainText
        color: lessMa.containsMouse ? sv.t.fgBright : sv.t.fgSoft
        font.family: sv.t.font
        font.pixelSize: sv.t.fsSmall
      }
      MouseArea { id: lessMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sv.toggle() }
    }

    // On hover: what Slack offers over a snippet.
    Rectangle {
      visible: sv.hovered
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: sv.t.sp(6)
      width: acts.implicitWidth + sv.t.sp(8)
      height: acts.implicitHeight + sv.t.sp(4)
      radius: Math.max(6, sv.t.radiusSmall)
      color: sv.t.popup
      border.width: 1
      border.color: sv.t.lineStrong
      Row {
        id: acts
        anchors.centerIn: parent
        IconButton { app: sv.app; icon: "󰆏"; tip: sv.app.tr("Copy snippet", "Copiar snippet"); onClicked: sv.copyText() }
        IconButton { app: sv.app; icon: "󰏌"; tip: sv.app.tr("Open", "Abrir"); onClicked: sv.ws.openFile(sv.file) }
        IconButton { app: sv.app; visible: !!sv.file.download; icon: "󰇚"; tip: sv.app.tr("Download", "Baixar"); onClicked: sv.ws.saveFile(sv.file) }
        IconButton { app: sv.app; visible: !!sv.file.permalink; icon: "󰌷"; tip: sv.app.tr("Copy link to file", "Copiar link do arquivo")
                     onClicked: { sv.app.copy(sv.file.permalink); if (sv.win) sv.win.toast(sv.app.tr("Link copied", "Link copiado")) } }
      }
    }
  }
}
