import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The rail's Files tab, filling the panel, as Slack's list of files: the
// ones you can see (canvases, lists, PDFs, sheets, whatever was shared where
// you are) with All / Created by you / Shared with you, the types and the
// sort, and on each row download (or open in the browser), star and more.
// Search files on top: the same list, of what Slack's search finds, with
// the filters on it. A click opens the file the best way there is (openFile). `peek`: the card
// hovering the rail's Files shows (AppWindow), with Starred instead of the
// filters. The list is files.list's (Workspace.loadFiles): Slack only says
// when you last viewed some files, so "Recently viewed" goes by when the
// others changed.
Rectangle {
  id: fl
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  property bool peek: false
  property string who: "all"             // all | mine | shared
  property string typeFilter: ""         // "" (all types) or a typeGroups id
  property string sort: app.setting("filesSort", "viewed")   // viewed | updated | created | name
  property bool starredOnly: peek && app.setting("filesPeekStarred", false) === true
  color: peek ? t.sidebar : t.pane
  function setSort(s) { fl.sort = s; fl.app.setSetting("filesSort", s) }
  function toggleStarred() { fl.starredOnly = !fl.starredOnly; fl.app.setSetting("filesPeekStarred", fl.starredOnly) }

  // ---------------------------------------------------------------- data
  // Created by you is its own query (files.list by you); All and Shared
  // with you are one list, Shared the part someone else made.
  readonly property string query: who === "mine" ? "mine" : "all"
  readonly property var src: ws ? ws.fileList(query) : null
  Component.onCompleted: fl.refresh(false)
  onWsChanged: fl.refresh(false)
  onQueryChanged: if (fl.ws) { fl.ws.refreshFiles(fl.query); fl.runSearch(false) }
  function refresh(force) {
    if (!fl.ws) return
    if (force) fl.ws.loadFiles(fl.query, true)
    else fl.ws.refreshFiles(fl.query)
    fl.runSearch(force)
    if (!fl.peek || fl.starredOnly) fl.ws.loadStars()
  }
  onStarredOnlyChanged: if (fl.starredOnly && fl.ws) fl.ws.loadStars()

  readonly property var typeGroups: [
    { id: "", label: app.tr("All types", "Todos os tipos") },
    { id: "canvas", label: app.tr("Canvases", "Canvas"), kinds: ["canvas"] },
    { id: "list", label: app.tr("Lists", "Listas"), kinds: ["list"] },
    { id: "doc", label: app.tr("Documents", "Documentos"), kinds: ["word", "gdoc", "code"] },
    { id: "pdf", label: "PDFs", kinds: ["pdf"] },
    { id: "sheet", label: app.tr("Spreadsheets", "Planilhas"), kinds: ["excel", "sheet"] },
    { id: "slides", label: app.tr("Presentations", "Apresentações"), kinds: ["ppt", "slides"] },
    { id: "image", label: app.tr("Images", "Imagens"), kinds: ["image"] },
    { id: "media", label: app.tr("Audio and video", "Áudio e vídeo"), kinds: ["audio", "video"] },
    { id: "other", label: app.tr("Other", "Outros"), kinds: ["zip", "other"] }
  ]
  readonly property var typeGroup: typeGroups.filter(function(g) { return g.id === fl.typeFilter })[0] || typeGroups[0]
  readonly property var sorts: [
    { id: "viewed", label: app.tr("Recently viewed", "Vistos recentemente") },
    { id: "updated", label: app.tr("Recently updated", "Atualizados recentemente") },
    { id: "created", label: app.tr("Recently created", "Criados recentemente") },
    { id: "name", label: app.tr("Name", "Nome") }
  ]
  readonly property var sortItem: sorts.filter(function(s) { return s.id === fl.sort })[0] || sorts[0]

  readonly property var items: {
    if (!ws) return []
    ws.fileStarsRev
    var all = fl.starredOnly ? Object.keys(ws.fileStars).map(function(k) { return ws.fileStars[k] })
            : (fl.searching ? fl.matches() : (fl.src ? fl.src.files : []))
    var me = ws.me.id, kinds = fl.peek ? null : fl.typeGroup.kinds
    var out = all.filter(function(f) {
      if (!fl.peek && fl.who === "shared" && f.user === me) return false
      if (fl.searching && fl.who === "mine" && f.user !== me) return false
      return !kinds || kinds.indexOf(f.kind) >= 0
    })
    var by = fl.peek ? "viewed" : fl.sort
    out.sort(function(a, b) {
      if (by === "name") return String(a.title || a.name).toLowerCase().localeCompare(String(b.title || b.name).toLowerCase())
      if (by === "created") return b.created - a.created
      if (by === "updated") return b.updated - a.updated
      return (b.viewed || b.updated) - (a.viewed || a.updated)
    })
    return fl.peek ? out.slice(0, 30) : out
  }
  // What the list comes from (the search's answer while there's one) and
  // whether it's still on its way.
  readonly property var pending: searching ? found : src
  readonly property bool busy: !fl.starredOnly && (!fl.pending || !fl.pending.loaded || fl.pending.loading)

  // A filter that leaves little of what's loaded: the next pages, a few.
  onItemsChanged: if (!fl.peek) Qt.callLater(fl.fill)
  function fill() {
    var s = fl.pending
    if (!fl.ws || !s || !s.loaded || s.loading || s.error || s.page >= s.pages || s.page >= 10) return
    if (fl.items.length < 30) fl.more()
  }
  function more() {
    if (!fl.ws || fl.peek || fl.starredOnly) return
    if (fl.searching) { if (fl.found) fl.ws.searchFiles(fl.typed, fl.query, true, false) }
    else fl.ws.loadFiles(fl.query, false)
  }

  // ---------------------------------------------------------------- search
  // What's loaded with the words in its title shows at once; Slack's search
  // (Workspace.searchFiles: files outside the loaded pages too) after a
  // pause in the typing, both in the one list.
  property string typed: ""              // the search box, trimmed
  readonly property bool searching: !peek && typed !== ""
  // Slack's answer for what's typed (and the chip's who), once asked.
  readonly property var found: searching && ws ? ws.fileSearchOf(typed, query) : null
  // The words to light up in the titles, as the search overlay does (U.nameHtml).
  readonly property var marks: searching ? U.markTokens(typed) : []
  onTypedChanged: { searchTimer.restart(); list.positionViewAtBeginning() }
  Timer { id: searchTimer; interval: 300; onTriggered: fl.runSearch(false) }
  function runSearch(fresh) { if (fl.searching && fl.ws) fl.ws.searchFiles(fl.typed, fl.query, false, fresh) }
  function clearSearch() { searchField.text = "" }
  function matches() {
    var hits = fl.found ? fl.found.files : [], seen = {}, out = hits.slice()
    hits.forEach(function(f) { seen[f.id] = true })
    var words = U.tokens(fl.typed)
    if (!words.length) return out
    var loaded = fl.src ? fl.src.files : []
    var starred = Object.keys(fl.ws.fileStars).map(function(k) { return fl.ws.fileStars[k] })
    loaded.concat(starred).forEach(function(f) {
      if (seen[f.id]) return
      var name = U.fold(fl.title(f) + " " + (f.name || ""))
      if (words.every(function(w) { return name.indexOf(w) >= 0 })) { seen[f.id] = true; out.push(f) }
    })
    return out
  }

  // ---------------------------------------------------------------- labels
  function title(f) { return f.title || f.name || "" }
  // "Ana Souza · Last viewed on October 12th · 2 min read".
  function subtitle(f) {
    var parts = []
    var who = f.user ? fl.ws.userName(f.user) : ""
    if (who) parts.push(who)
    var lang = fl.app.lang, c24 = fl.app.clock24
    if ((fl.sort === "viewed" || fl.sort === "name") && f.viewed) parts.push(fl.app.tr("Last viewed ", "Visto pela última vez ") + U.whenLabel(String(f.viewed), lang, c24))
    else if (fl.sort === "created" && f.created) parts.push(fl.app.tr("Created ", "Criado ") + U.whenLabel(String(f.created), lang, c24))
    else if (f.updated) parts.push(fl.app.tr("Updated ", "Atualizado ") + U.whenLabel(String(f.updated), lang, c24))
    if (f.readtime > 0) parts.push(f.readtime + fl.app.tr(" min read", " min de leitura"))
    return parts.join(" · ")
  }
  // Canvases, lists and Google's files only live in the browser.
  function webOnly(f) { return f.kind === "canvas" || f.kind === "list" || f.external }
  function downloadable(f) { return !!f.download && !fl.webOnly(f) }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: fl.peek ? fl.t.sp(50) : fl.t.sp(56)
    Text {
      x: fl.peek ? fl.t.sp(16) : fl.t.sp(24)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - (fl.peek ? starredSwitch.width : refreshBtn.width) - fl.t.sp(24)
      text: fl.app.tr("Files", "Arquivos")
      color: fl.t.fgBright
      font.family: fl.t.font
      font.pixelSize: fl.peek ? fl.t.fsText + 1 : fl.t.fsHeader
      font.bold: true
      elide: Text.ElideRight
    }
    UnreadsSwitch {
      id: starredSwitch
      app: fl.app
      visible: fl.peek
      anchors.right: parent.right
      anchors.rightMargin: fl.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      text: fl.app.tr("Starred", "Com estrela")
      checked: fl.starredOnly
      onToggled: fl.toggleStarred()
    }
    IconButton {
      id: refreshBtn
      visible: !fl.peek
      app: fl.app
      anchors.right: parent.right
      anchors.rightMargin: fl.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      size: fl.t.sp(32)
      icon: "󰑓"
      tip: fl.app.tr("Refresh", "Atualizar")
      color: fl.t.fgBright
      hoverColor: fl.t.hoverStrong
      onClicked: fl.refresh(true)
    }
  }

  // Search files, with ✕ (or Esc) back to the whole list.
  Item {
    id: searchBar
    visible: !fl.peek
    y: header.height
    width: parent.width
    height: visible ? fl.t.sp(44) : 0
    SField {
      id: searchField
      app: fl.app
      x: fl.t.sp(20)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - fl.t.sp(40)
      height: fl.t.sp(34)
      icon: "󰍉"
      placeholderText: fl.app.tr("Search files", "Buscar arquivos")
      font.pixelSize: fl.t.fsSmall + 1
      topPadding: 0
      bottomPadding: 0
      rightPadding: fl.t.sp(text !== "" ? 38 : 10)
      onTextChanged: fl.typed = text.trim()
      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && text !== "") { fl.clearSearch(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { searchTimer.stop(); fl.runSearch(false); event.accepted = true }
      }
    }
    IconButton {
      app: fl.app
      visible: searchField.text !== ""
      anchors.right: searchField.right
      anchors.rightMargin: fl.t.sp(6)
      anchors.verticalCenter: searchField.verticalCenter
      size: fl.t.sp(24)
      icon: "󰅙"
      iconSize: fl.t.fsTitle
      tip: fl.app.tr("Clear", "Limpar") + "  Esc"
      onClicked: { fl.clearSearch(); searchField.forceActiveFocus() }
    }
  }

  // All · Created by you · Shared with you · types, and the sort.
  Item {
    id: filters
    visible: !fl.peek
    y: searchBar.y + searchBar.height
    width: parent.width
    height: visible ? fl.t.sp(46) : 0

    Row {
      x: fl.t.sp(20)
      anchors.verticalCenter: parent.verticalCenter
      spacing: fl.t.sp(8)
      Repeater {
        model: [
          { id: "all", label: fl.app.tr("All", "Todos") },
          { id: "mine", label: fl.app.tr("Created by you", "Criados por você") },
          { id: "shared", label: fl.app.tr("Shared with you", "Compartilhados com você") }
        ]
        delegate: Chip {
          required property var modelData
          label: modelData.label
          on: fl.who === modelData.id
          onClicked: { fl.who = modelData.id; list.positionViewAtBeginning() }
        }
      }
      Rectangle { width: 1; height: fl.t.sp(20); color: fl.t.line; anchors.verticalCenter: parent.verticalCenter }
      Chip {
        id: typeChip
        label: fl.typeFilter ? fl.typeGroup.label : fl.app.tr("Types", "Tipos")
        on: fl.typeFilter !== ""
        menu: true
        onClicked: fl.win.menuAt(typeChip, fl.typeGroups.map(function(g) {
          return { label: g.label, checked: fl.typeFilter === g.id, action: function() { fl.typeFilter = g.id; list.positionViewAtBeginning() } }
        }), 0, typeChip.height + fl.t.sp(4))
      }
    }

    // The sort, at the right.
    Rectangle {
      id: sortBtn
      anchors.right: parent.right
      anchors.rightMargin: fl.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      height: fl.t.sp(30)
      width: sortRow.implicitWidth + fl.t.sp(16)
      radius: Math.max(6, fl.t.radiusSmall)
      color: sortMa.containsMouse ? fl.t.hover : "transparent"
      Row {
        id: sortRow
        anchors.centerIn: parent
        spacing: fl.t.sp(5)
        Glyph { app: fl.app; icon: "󰒺"; size: fl.t.fsSmall + 1; color: fl.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: fl.sortItem.label
          color: fl.t.fg
          font.family: fl.t.font
          font.pixelSize: fl.t.fsSmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Glyph { app: fl.app; icon: "󰅀"; size: fl.t.fsSmall; color: fl.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
      }
      MouseArea {
        id: sortMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var items = [{ header: fl.app.tr("Sort by", "Ordenar por") }]
          fl.sorts.forEach(function(s) { items.push({ label: s.label, checked: fl.sort === s.id, action: function() { fl.setSort(s.id) } }) })
          fl.win.menuAt(sortBtn, items, sortBtn.width - fl.t.sp(220), sortBtn.height + fl.t.sp(4))
        }
      }
    }
  }

  Rectangle { y: filters.y + filters.height; width: parent.width; height: 1; color: fl.t.line }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    y: filters.y + filters.height + 1
    width: parent.width
    height: parent.height - y
    clip: true
    topMargin: fl.t.sp(6)
    bottomMargin: fl.t.sp(12)
    spacing: fl.t.sp(2)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: fl.items; objectProp: "id" }
    ScrollBar.vertical: ThinScroll { app: fl.app }
    onAtYEndChanged: if (atYEnd) fl.more()

    // The next page on its way, or the search (what's shown so far being
    // what's loaded that matches).
    footer: Item {
      width: list.width
      height: !fl.peek && fl.busy && fl.items.length > 0 ? fl.t.sp(36) : 0
      Text {
        visible: parent.height > 0
        anchors.centerIn: parent
        text: fl.searching ? fl.app.tr("Searching…", "Buscando…") : fl.app.tr("Loading…", "Carregando…")
        color: fl.t.fgDim
        font.family: fl.t.font
        font.pixelSize: fl.t.fsSmall
      }
    }

    delegate: Item {
      id: row
      required property var modelData
      readonly property var f: modelData
      readonly property bool starred: fl.ws.isFileStarred(f.id)
      readonly property bool hot: ma.containsMouse || actHover.hovered
      width: list.width
      height: fl.peek ? fl.t.sp(52) : fl.t.sp(60)

      Rectangle {
        x: fl.t.sp(8)
        width: parent.width - fl.t.sp(16)
        height: parent.height
        radius: Math.max(6, fl.t.radiusSmall)
        color: ma.pressed ? fl.t.hoverStrong : (row.hot ? fl.t.hover : "transparent")
      }

      FileTypeIcon {
        id: typeIcon
        app: fl.app
        file: row.f
        size: fl.peek ? fl.t.sp(34) : fl.t.sp(40)
        x: fl.peek ? fl.t.sp(16) : fl.t.sp(20)
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        anchors.left: typeIcon.right
        anchors.leftMargin: fl.t.sp(12)
        anchors.right: parent.right
        anchors.rightMargin: fl.peek ? fl.t.sp(16) : fl.t.sp(132)
        anchors.verticalCenter: parent.verticalCenter
        spacing: fl.t.sp(2)
        Text {
          width: parent.width
          text: fl.marks.length ? U.nameHtml(fl.title(row.f), fl.marks, fl.t.html.meText) : fl.title(row.f)
          textFormat: fl.marks.length ? Text.StyledText : Text.PlainText
          color: fl.t.fgBright
          font.family: fl.t.font
          font.pixelSize: fl.peek ? fl.t.fsSmall + 1 : fl.t.fsText
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: fl.peek ? fl.app.tr("Updated ", "Atualizado ") + U.ago(row.f.updated, fl.app.lang) : fl.subtitle(row.f)
          textFormat: Text.PlainText
          color: fl.t.fgDim
          font.family: fl.t.font
          font.pixelSize: fl.peek ? fl.t.fsTiny + 1 : fl.t.fsSmall
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        z: -1
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: fl.peek ? Qt.LeftButton : Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
          if (mouse.button === Qt.RightButton) { var p = ma.mapToItem(fl.win.contentItem, mouse.x, mouse.y); fl.rowMenu(row.f, p.x, p.y); return }
          fl.openFile(row.f)
        }
      }

      // Download (or open in the browser) · star · more, on hover; a
      // starred file keeps its star.
      Row {
        id: acts
        visible: !fl.peek
        anchors.right: parent.right
        anchors.rightMargin: fl.t.sp(18)
        anchors.verticalCenter: parent.verticalCenter
        spacing: fl.t.sp(2)
        HoverHandler { id: actHover }
        IconButton {
          app: fl.app; size: fl.t.sp(30)
          visible: row.hot
          icon: fl.downloadable(row.f) ? "󰇚" : "󰏌"
          tip: fl.downloadable(row.f) ? fl.app.tr("Download", "Baixar") : fl.app.tr("Open in browser", "Abrir no navegador")
          onClicked: fl.downloadable(row.f) ? fl.ws.saveFile(row.f) : fl.openInBrowser(row.f)
        }
        IconButton {
          app: fl.app; size: fl.t.sp(30)
          visible: row.hot || row.starred
          icon: row.starred ? "󰓎" : "󰓒"
          color: row.starred ? fl.t.yellow : fl.t.fgSoft
          tip: row.starred ? fl.app.tr("Unstar", "Remover estrela") : fl.app.tr("Star", "Marcar com estrela")
          onClicked: fl.ws.setFileStar(row.f, !row.starred)
        }
        IconButton {
          id: moreBtn
          app: fl.app; size: fl.t.sp(30)
          visible: row.hot
          icon: "󰇙"
          tip: fl.app.tr("More actions", "Mais ações")
          onClicked: { var p = moreBtn.mapToItem(fl.win.contentItem, moreBtn.width - fl.t.sp(220), moreBtn.height + 4); fl.rowMenu(row.f, p.x, p.y) }
        }
      }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: fl.items.length === 0
    anchors.horizontalCenter: parent.horizontalCenter
    y: list.y + fl.t.sp(fl.peek ? 36 : 64)
    width: Math.min(parent.width - fl.t.sp(40), fl.t.sp(420))
    spacing: fl.t.sp(8)
    readonly property string error: !fl.starredOnly && fl.pending ? fl.pending.error || "" : ""
    readonly property bool busy: fl.busy
    Glyph { app: fl.app; anchors.horizontalCenter: parent.horizontalCenter; icon: fl.starredOnly ? "󰓒" : (fl.searching ? "󰍉" : "󰈢"); size: fl.t.sp(30); color: fl.t.fgDim }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: parent.busy ? (fl.searching ? fl.app.tr("Searching…", "Buscando…") : fl.app.tr("Loading…", "Carregando…"))
          : (parent.error ? parent.error
          : (fl.searching ? fl.app.tr("No files match “", "Nenhum arquivo encontrado para “") + fl.typed + "”"
          : (fl.starredOnly ? fl.app.tr("No starred files", "Nenhum arquivo com estrela")
          : (fl.typeFilter ? fl.app.tr("No files of this type", "Nenhum arquivo deste tipo")
          : (fl.who === "mine" ? fl.app.tr("You haven't created any files yet", "Você ainda não criou nenhum arquivo")
          : (fl.who === "shared" ? fl.app.tr("Nothing shared with you yet", "Nada compartilhado com você ainda")
          : fl.app.tr("No files yet", "Nenhum arquivo ainda")))))))
      color: fl.t.fgBright
      font.family: fl.t.font
      font.pixelSize: fl.t.fsText
      font.bold: true
    }
    Text {
      visible: !parent.busy && !parent.error
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: fl.starredOnly ? fl.app.tr("Star a file in Files to keep it at hand here.", "Marque um arquivo com estrela em Arquivos para tê-lo à mão aqui.")
          : fl.searching ? (fl.who !== "all" || fl.typeFilter ? fl.app.tr("Try other words, or other filters.", "Tente outras palavras ou outros filtros.")
                                                                : fl.app.tr("Try other words.", "Tente outras palavras."))
          : fl.app.tr("Canvases, lists and files shared in your conversations show up here.", "Canvas, listas e arquivos compartilhados nas suas conversas aparecem aqui.")
      color: fl.t.fgDim
      font.family: fl.t.font
      font.pixelSize: fl.t.fsSmall
    }
  }

  // ---------------------------------------------------------------- pieces
  // A filter as a pill: filled while on, a chevron when it opens a menu.
  component Chip: Rectangle {
    id: chip
    property var app: Reg.service
    readonly property var t: app.theme
    property string label: ""
    property bool on: false
    property bool menu: false
    signal clicked()
    height: chip.t.sp(30)
    width: chipRow.implicitWidth + chip.t.sp(22)
    radius: height / 2
    color: chip.on ? chip.t.accent : (chipMa.containsMouse ? chip.t.hover : "transparent")
    border.width: chip.on ? 0 : 1
    border.color: chip.t.lineStrong
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: chip.t.sp(5)
      Text {
        text: chip.label
        color: chip.on ? chip.t.selectedText : chip.t.fg
        font.family: chip.t.font
        font.pixelSize: chip.t.fsSmall
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Glyph { app: chip.app; visible: chip.menu; icon: "󰅀"; size: chip.t.fsSmall; color: chip.on ? chip.t.selectedText : chip.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
  }

  // ---------------------------------------------------------------- actions
  function openInBrowser(f) {
    var url = f.externalUrl || f.permalink
    if (url) fl.app.openUrl(url)
  }

  // Canvases, lists and Google's files in the browser, images in the
  // viewer, PDFs and the rest fetched with the session and opened with the
  // desktop's app (Workspace.openFile). From the card, the card goes after
  // (and this list with it).
  function openFile(f) {
    var w = fl.win, ws = fl.ws, peek = fl.peek
    if (fl.webOnly(f)) fl.openInBrowser(f)
    else if (f.image && (f.full || f.thumb)) w.viewImage(f)
    else ws.openFile(f)
    if (peek) w.closePeek()
  }

  function rowMenu(f, x, y) {
    var ws = fl.ws, starred = ws.isFileStarred(f.id)
    var items = [
      { label: fl.app.tr("Open", "Abrir"), icon: "󰁔", action: function() { fl.openFile(f) } }
    ]
    if (f.permalink || f.externalUrl) items.push({ label: fl.app.tr("Open in browser", "Abrir no navegador"), icon: "󰖟", action: function() { fl.openInBrowser(f) } })
    items.push({ separator: true })
    if (f.permalink) items.push({ label: fl.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() { fl.app.copy(f.permalink); fl.win.toast(fl.app.tr("Link copied", "Link copiado")) } })
    if (fl.downloadable(f)) items.push({ label: fl.app.tr("Download", "Baixar"), icon: "󰇚", action: function() { ws.saveFile(f) } })
    items.push({ separator: true })
    items.push({ label: starred ? fl.app.tr("Unstar", "Remover estrela") : fl.app.tr("Star", "Marcar com estrela"), icon: starred ? "󰓎" : "󰓒",
                 action: function() { ws.setFileStar(f, !starred) } })
    fl.win.menu(items, x, y)
  }
}
