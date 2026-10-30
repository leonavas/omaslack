import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Registry.js" as Reg

// The sidebar: the workspace's name and the compose button, then Threads,
// Drafts & sent and Slack's sections as the user arranged them. Narrow, it
// folds into a column of photos and icons.
Rectangle {
  id: side
  property var app: Reg.service
  property var win
  property var ws
  property bool narrow: false
  readonly property var t: app.theme
  color: t.sidebar

  // Off screen (Service.onScreen) the rows stay as they were: the list and
  // its pills don't follow events nobody sees, and catch up once it shows.
  property var rows: []
  Binding {
    target: side
    property: "rows"
    when: side.app.onScreen
    value: side.ws ? side.ws.sidebarRows : []
    restoreMode: Binding.RestoreNone
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: side.t.sp(50)

    Rectangle {
      id: teamBtn
      visible: !side.narrow
      x: side.t.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      height: side.t.sp(34)
      width: Math.min(parent.width - side.t.sp(56), teamName.implicitWidth + side.t.sp(34))
      radius: Math.max(6, side.t.radiusSmall)
      color: teamMa.containsMouse ? side.t.hover : "transparent"
      Text {
        id: teamName
        x: side.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - side.t.sp(30))
        text: side.ws ? side.ws.team.name : ""
        textFormat: Text.PlainText
        color: side.t.fgBright
        font.family: side.t.font
        font.pixelSize: side.t.fsHeader
        font.bold: true
        elide: Text.ElideRight
      }
      Glyph {
        app: side.app
        anchors.left: teamName.right
        anchors.leftMargin: side.t.sp(4)
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰅀"
        size: side.t.fsSmall
        color: side.t.fgBright
      }
      MouseArea {
        id: teamMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: side.workspaceMenu()
      }
    }

    IconButton {
      app: side.app
      anchors.right: parent.right
      anchors.rightMargin: side.narrow ? (parent.width - width) / 2 : side.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      size: side.t.sp(32)
      icon: "󰤌"
      tip: side.app.tr("New message", "Nova mensagem") + "  Ctrl+N"
      color: side.t.fgBright
      hoverColor: side.t.hoverStrong
      onClicked: side.win.dialog("newMessage")
    }
  }

  Rectangle { y: header.height; width: parent.width; height: 1; color: side.t.line }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    y: header.height + 1
    width: parent.width
    height: parent.height - y
    clip: true
    topMargin: side.t.sp(8)
    bottomMargin: side.t.sp(12)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: side.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: side.app }

    delegate: SidebarRow {
      required property var modelData
      required property int index
      row: modelData
      app: side.app
      win: side.win
      ws: side.ws
      narrow: side.narrow
      width: list.width
      sidebar: side
    }

    // The wheel / touchpad (further than Qt's) takes over from a pill's glide.
    WheelScroll { view: list; step: side.t.sp(118); touch: 1.8; onWheeled: glide.stop() }
  }

  Glide { id: glide; view: list }

  // ---------------------------------------------------------------- drag
  // A conversation dragged onto a section moves there (in Slack too); a
  // section header dragged onto another goes before it.
  property var dragRow: null
  property real dragY: 0
  property real dragX: 0
  readonly property var dropRow: {
    if (!side.dragRow) return null
    var idx = list.indexAt(10, side.dragY - list.y + list.contentY)
    var rows = side.rows
    var r = idx >= 0 ? rows[idx] : null
    if (!r) return null
    return r
  }
  readonly property string dropSection: {
    var r = side.dropRow
    if (!r || !side.dragRow) return ""
    var sec = r.kind === "section" ? r.id : (r.section || (r.kind === "add" ? r.id : ""))
    var target = side.ws ? side.ws.sections.filter(function(x) { return x.id === sec })[0] : null
    if (!target) return ""
    if (side.dragRow.kind === "conv") {
      if (["stars", "channels", "direct_messages", "standard", "custom"].indexOf(target.type) < 0) return ""
      if (target.type === "direct_messages" && side.dragRow.convKind !== "im" && side.dragRow.convKind !== "mpim") return ""
      if (target.type === "channels" && (side.dragRow.convKind === "im" || side.dragRow.convKind === "mpim")) return ""
      if (sec === side.dragRow.section) return ""
    } else if (sec === side.dragRow.id) return ""
    return sec
  }
  function dragStart(row, x, y) { side.dragRow = row; side.dragX = x; side.dragY = y }
  function dragMove(x, y) {
    side.dragX = x
    side.dragY = y
    // Near the edges the list scrolls.
    if (y < list.y + side.t.sp(30)) list.contentY = Math.max(list.originY - list.topMargin, list.contentY - side.t.sp(12))
    else if (y > list.y + list.height - side.t.sp(30)) list.contentY = Math.min(list.contentHeight - list.height + list.bottomMargin, list.contentY + side.t.sp(12))
  }
  function dragEnd() {
    var row = side.dragRow, target = side.dropSection
    side.dragRow = null
    if (!row || !target) return
    if (row.kind === "conv") side.ws.dropConversation(row.id, target)
    else if (row.kind === "section" && !row.silenced) side.ws.moveSectionBefore(row.id, target)
  }

  Rectangle {
    visible: !!side.dragRow
    z: 20
    x: Math.min(side.width - width - side.t.sp(4), Math.max(side.t.sp(4), side.dragX - width / 2))
    y: side.dragY - height / 2
    width: Math.min(side.width - side.t.sp(16), ghostText.implicitWidth + side.t.sp(24))
    height: side.t.sp(28)
    radius: Math.max(6, side.t.radiusSmall)
    color: side.t.selected
    opacity: 0.92
    Text {
      id: ghostText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - side.t.sp(16))
      elide: Text.ElideRight
      text: side.dragRow ? (side.dragRow.kind === "section" ? side.dragRow.label : (side.dragRow.convKind === "channel" ? "# " : "") + side.dragRow.label) : ""
      textFormat: Text.PlainText
      color: side.t.selectedText
      font.family: side.t.font
      font.pixelSize: side.t.fsSidebar
      font.bold: true
    }
  }

  // Unread rows out of sight: Slack's "Unread mentions" pill.
  readonly property var pills: {
    list.contentY; list.height
    var rows = side.rows
    var first = list.indexAt(10, list.contentY + 4)
    var last = list.indexAt(10, list.contentY + list.height - 4)
    if (first < 0) first = 0
    if (last < 0) last = rows.length - 1
    var up = { mention: -1, unread: -1 }, down = { mention: -1, unread: -1 }
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.kind !== "conv" || r.active) continue
      if (i < first) { if (r.mentions > 0) up.mention = i; if (r.unread) up.unread = i }
      if (i > last) { if (r.mentions > 0 && down.mention < 0) down.mention = i; if (r.unread && down.unread < 0) down.unread = i }
    }
    return { up: up, down: down }
  }

  // A pill glides to the row (found by key on each step: rows come and go).
  function reveal(i, mode) {
    var rows = side.rows
    var key = rows[i] ? rows[i].key : ""
    if (!key) return
    glide.to(function() {
      var rs = side.rows
      for (var j = 0; j < rs.length; j++) if (rs[j].key === key) { list.positionViewAtIndex(j, mode); return }
    })
  }

  EdgePill {
    app: side.app
    visible: !side.narrow && (side.pills.up.mention >= 0 || side.pills.up.unread >= 0)
    anchors.top: list.top
    anchors.topMargin: side.t.sp(6)
    anchors.horizontalCenter: parent.horizontalCenter
    mention: side.pills.up.mention >= 0
    text: (mention ? side.app.tr("Unread mentions", "Menções não lidas") : side.app.tr("More unreads", "Mais não lidas"))
    arrow: "󰁝"
    onClicked: side.reveal(mention ? side.pills.up.mention : side.pills.up.unread, ListView.Beginning)
  }
  EdgePill {
    app: side.app
    visible: !side.narrow && (side.pills.down.mention >= 0 || side.pills.down.unread >= 0)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: side.t.sp(10)
    anchors.horizontalCenter: parent.horizontalCenter
    mention: side.pills.down.mention >= 0
    text: (mention ? side.app.tr("Unread mentions", "Menções não lidas") : side.app.tr("More unreads", "Mais não lidas"))
    arrow: "󰁅"
    onClicked: side.reveal(mention ? side.pills.down.mention : side.pills.down.unread, ListView.End)
  }

  // ---------------------------------------------------------------- menus
  function workspaceMenu() {
    var w = side.ws
    var paused = w.dnd !== null
    side.win.menuAt(teamBtn, [
      { header: w.team.name + (w.team.domain ? "  ·  " + w.team.domain + ".slack.com" : "") },
      { label: side.app.tr("Invite people to ", "Convidar pessoas para ") + w.team.name, icon: "󰠁", action: function() { side.win.dialog("invite") } },
      { separator: true },
      { label: side.app.tr("Set a status", "Definir um status"), icon: "󰇵", hint: "Ctrl+Shift+Y", action: function() { side.win.dialog("status") } },
      { label: w.away ? side.app.tr("Set yourself as active", "Ficar ativo") : side.app.tr("Set yourself as away", "Ficar ausente"), icon: w.away ? "󰄯" : "󰄰", action: function() { w.setAway(!w.away) } },
      { label: paused ? side.app.tr("Resume notifications", "Retomar notificações") : side.app.tr("Pause notifications", "Pausar notificações"), icon: paused ? "󰂚" : "󰂛",
        sub: paused ? null : side.pauseItems(), action: paused ? function() { side.app.resumeAll() } : null },
      { separator: true },
      { label: side.app.tr("Profile", "Perfil"), icon: "󰀄", action: function() { w.profileUser = w.me.id; w.thread = null } },
      { label: side.app.tr("Preferences", "Preferências"), icon: "󰒓", hint: "Ctrl+,", action: function() { side.win.dialog("preferences") } },
      // Slack's Tools & settings › Customize workspace, on its emoji page in the browser.
      { label: side.app.tr("Customize workspace", "Personalizar workspace"), icon: "󰏘", hint: "󰏌", enabled: !!w.team.domain,
        action: function() { Qt.openUrlExternally("https://" + w.team.domain + ".slack.com/customize/emoji") } },
      { label: side.app.tr("Browse channels", "Navegar pelos canais"), icon: "󰐣", action: function() { side.win.dialog("browse") } },
      { label: side.app.tr("Create a section", "Criar uma seção"), icon: "󰉋", action: function() { side.win.dialog("newSection") } },
      { label: side.app.tr("Mark all as read", "Marcar tudo como lido"), icon: "󰄬", hint: "Shift+Esc", action: function() { w.markAllRead() } },
      { label: side.app.tr("Reload", "Recarregar"), icon: "󰑓", hint: "Ctrl+R", action: function() { w.start(); w.loadDirectory(true) } },
      { separator: true },
      { label: side.app.tr("Sign out of ", "Sair de ") + w.team.name, icon: "󰍃", danger: true, action: function() { side.win.dialog("confirm", {
        title: side.app.tr("Sign out of ", "Sair de ") + w.team.name + "?",
        text: side.app.tr("This app forgets the session, with this workspace's drafts and cached files. Slack in your browser stays signed in.", "Este app esquece a sessão, com os rascunhos e arquivos em cache deste workspace. O Slack no navegador continua conectado."),
        confirm: side.app.tr("Sign out", "Sair"), danger: true, action: function() { side.app.signOut(w.teamId) } }) } }
    ], 0, teamBtn.height + side.t.sp(4))
  }

  function pauseItems() {
    var U2 = U
    return [
      { header: side.app.tr("Pause notifications…", "Pausar notificações…") },
      { label: side.app.tr("For 30 minutes", "Por 30 minutos"), action: function() { side.app.pauseAll(30) } },
      { label: side.app.tr("For 1 hour", "Por 1 hora"), action: function() { side.app.pauseAll(60) } },
      { label: side.app.tr("For 2 hours", "Por 2 horas"), action: function() { side.app.pauseAll(120) } },
      { label: side.app.tr("Until tomorrow", "Até amanhã"), action: function() { side.app.pauseAll(U2.minutesUntilTomorrow9()) } },
      { label: side.app.tr("Until next week", "Até a próxima semana"), action: function() { side.app.pauseAll(U2.minutesUntilNextWeek9()) } },
      { label: side.app.tr("Custom…", "Personalizado…"), action: function() { side.win.dialog("pause") } }
    ]
  }

  function convMenu(item, row, x, y) {
    var w = side.ws
    var c = w.conv(row.id)
    if (!c) return
    var dm = c.kind === "im" || c.kind === "mpim"
    var items = []
    items.push({ label: side.app.tr("Mark as read", "Marcar como lida"), icon: "󰄬", enabled: row.unread || row.mentions > 0, action: function() { w.markRead(row.id) } })
    items.push(w.isStarred(row.id)
      ? { label: side.app.tr("Remove from starred", "Remover dos favoritos"), icon: "󰓒", action: function() { w.setStar(row.id, false) } }
      : { label: side.app.tr("Star conversation", "Adicionar aos favoritos"), icon: "󰓎", action: function() { w.setStar(row.id, true) } })
    var targets = w.sections.filter(function(s) { return ["stars", "channels", "direct_messages", "standard", "custom"].indexOf(s.type) >= 0 })
    if (targets.length) items.push({ label: side.app.tr("Move conversation", "Mover conversa"), icon: "󰁔", sub: targets.map(function(s) {
      var name = s.type === "stars" ? side.app.tr("Starred", "Favoritos") : s.type === "channels" ? side.app.tr("Channels", "Canais") : s.type === "direct_messages" ? side.app.tr("Direct messages", "Mensagens diretas") : s.name
      return { label: name, action: function() {
        if (s.type === "stars") w.setStar(row.id, true)
        else if (s.type === "channels" || s.type === "direct_messages") w.moveToSection(row.id, "", false)
        else w.moveToSection(row.id, s.id, false)
      } }
    }) })
    if (!dm) {
      var level = w.notifyLevel(row.id)
      items.push({ label: side.app.tr("Notifications", "Notificações"), icon: "󰂚", sub: [
        { label: side.app.tr("All new messages", "Todas as novas mensagens"), checked: level === "all", action: function() { w.setNotify(row.id, "all") } },
        { label: side.app.tr("Mentions", "Menções"), checked: level === "mentions", action: function() { w.setNotify(row.id, "mentions") } },
        { label: side.app.tr("Mute", "Silenciar"), checked: level === "mute", action: function() { w.setNotify(row.id, "mute") } }
      ] })
    }
    items.push({ separator: true })
    items.push({ label: dm ? side.app.tr("View profile", "Ver perfil") : side.app.tr("View channel details", "Ver detalhes do canal"), icon: "󰋼",
                 action: function() { if (c.kind === "im") { w.profileUser = c.user; w.thread = null } else side.win.dialog("details", { conv: row.id }) } })
    items.push({ label: side.app.tr("Copy name", "Copiar nome"), icon: "󰆏", action: function() { side.app.copy(row.label); side.win.toast(side.app.tr("Copied", "Copiado")) } })
    items.push({ label: side.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() { side.app.copy(U.convUrl(w.team.domain, row.id)); side.win.toast(side.app.tr("Link copied", "Link copiado")) } })
    items.push({ label: side.app.tr("Open in browser", "Abrir no navegador"), icon: "󰖟", action: function() { Qt.openUrlExternally(U.convUrl(w.team.domain, row.id)) } })
    if (dm) {
      items.push({ separator: true })
      items.push({ label: side.app.tr("Close conversation", "Fechar conversa"), icon: "󰅖", action: function() { w.closeDm(row.id) } })
    } else if (!c.general) {
      items.push({ separator: true })
      items.push({ label: side.app.tr("Leave channel", "Sair do canal"), icon: "󰍃", danger: true, action: function() { w.leave(row.id) } })
    }
    side.win.menu(items, x, y)
  }

  // Slack's section menu: its name on top, what goes into it, then
  // "Manage section" (rename and delete only for the user's own sections;
  // moving and collapsing are ours).
  function sectionMenu(row, x, y) {
    var w = side.ws
    var own = row.type === "standard" || row.type === "custom"
    var items = [{ title: row.label }]
    if (own) items.push({ label: side.app.tr("Create a channel", "Criar um canal"), icon: "󰐕", action: function() { side.win.dialog("newChannel", { section: row.id }) } })
    if (row.type === "channels") {
      items.push({ label: side.app.tr("Create a channel", "Criar um canal"), icon: "󰐕", action: function() { side.win.dialog("newChannel") } })
      items.push({ label: side.app.tr("Browse channels", "Navegar pelos canais"), icon: "󰐣", action: function() { side.win.dialog("browse") } })
    }
    if (row.type === "direct_messages")
      items.push({ label: side.app.tr("New message", "Nova mensagem"), icon: "󰏫", action: function() { side.win.dialog("newMessage") } })
    if (items.length > 1) items.push({ separator: true })
    items.push({ header: side.app.tr("Manage section", "Gerenciar seção") })
    if (own) items.push({ label: side.app.tr("Rename", "Renomear"), icon: "󰏫", action: function() { side.win.dialog("renameSection", { section: row.id, name: row.label, emoji: row.emoji }) } })
    items.push({ label: side.app.tr("Create a new section", "Criar uma nova seção"), icon: "󰉋", action: function() { side.win.dialog("newSection") } })
    if (!row.silenced) {
      var i = w.sections.findIndex(function(s) { return s.id === row.id })
      items.push({ label: side.app.tr("Move section up", "Mover seção para cima"), icon: "󰁝", enabled: i > 0, action: function() { w.moveSection(row.id, -1) } })
      items.push({ label: side.app.tr("Move section down", "Mover seção para baixo"), icon: "󰁅", enabled: i >= 0 && i < w.sections.length - 1, action: function() { w.moveSection(row.id, 1) } })
    }
    items.push({ label: row.collapsed ? side.app.tr("Expand", "Expandir") : side.app.tr("Collapse", "Recolher"), icon: row.collapsed ? "󰅀" : "󰅂", action: function() { w.toggleCollapsed(row.id) } })
    // "Section settings": Slack's Filter, a paid team's, for its own sections.
    if (w.sidebarRules.paidTeam && w.sections.some(function(s) { return s.id === row.id }) && row.type !== "priority") {
      var show = w.sectionFilter(row.id, row.type)
      var names = { active: side.app.tr("Active only", "Somente ativas"), hid: side.app.tr("Unreads", "Não lidas"),
                    mentions: side.app.tr("Mentions", "Menções"), all: side.app.tr("All", "Todas") }
      var opts = ["active", "hid"].concat(row.type === "direct_messages" ? [] : ["mentions"], ["all"])
      items.push({ separator: true })
      items.push({ header: side.app.tr("Section settings", "Configurações da seção") })
      items.push({ label: side.app.tr("Filter", "Filtro"), icon: "󰈲", hint: names[show], sub: opts.map(function(v) {
        return { label: names[v], checked: show === v, desc: v === "active" ? side.app.tr("New activity within the last 30 days", "Nova atividade nos últimos 30 dias") : "",
                 action: function() { w.setSectionFilter(row.id, v) } }
      }) })
    }
    if (own) {
      items.push({ separator: true })
      items.push({ label: side.app.tr("Delete section…", "Excluir seção…"), icon: "󰧧", danger: true, action: function() { side.win.dialog("confirm", {
        title: side.app.tr("Delete this section?", "Excluir esta seção?"),
        text: side.app.tr("Its channels and conversations go back to Channels and Direct messages.", "Os canais e conversas dela voltam para Canais e Mensagens diretas."),
        quote: row.label,
        confirm: side.app.tr("Delete", "Excluir"), danger: true, action: function() { w.deleteSection(row.id) } }) } })
    }
    side.win.menu(items, x, y)
  }
}
