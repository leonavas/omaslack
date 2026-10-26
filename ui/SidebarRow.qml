import QtQuick
import qs.Ui
import "../lib/Emoji.js" as EmojiLib
import "../lib/Registry.js" as Reg

// One row of the sidebar: Threads / Drafts, a section header, a
// conversation, or a section's "Add" row.
Item {
  id: r
  property var app: Reg.service
  property var win
  property var ws
  property var row
  property var sidebar
  property bool narrow: false
  readonly property var t: app.theme

  readonly property bool isConv: row.kind === "conv"
  readonly property bool isSection: row.kind === "section"
  readonly property bool hot: ma.containsMouse
  readonly property bool selected: (row.kind === "conv" || row.kind === "nav") && row.active
  readonly property color ink: selected ? t.rowSelectedText : ((row.unread || (row.kind === "nav" && row.unread)) ? t.unreadText : (row.muted ? t.alpha(t.fg, 0.45) : t.readText))
  readonly property var typingNames: isConv && ws ? ws.typingIn(row.id) : []
  // A DM's person: their status emoji goes right after the name.
  readonly property bool isIm: isConv && row.convKind === "im"
  readonly property var status: isIm && ws && row.user ? ws.statusOf(row.user) : null
  readonly property bool hasStatus: !!status && (status.emoji !== "" || status.unicode !== "" || status.url !== "")

  // The row's fill, and the color it makes over the sidebar: the presence
  // dot's ring is that color, so the dot reads on every state.
  readonly property color fill: selected ? t.rowSelected
       : (ma.pressed ? t.hoverStrong : (hot ? t.hover
       : (isConv && row.unread && app.unreadBackground ? t.alpha(t.blue, 0.10) : "transparent")))
  readonly property color under: Qt.tint(dropHere ? Qt.tint(t.sidebar, t.alpha(t.accent, 0.12)) : t.sidebar, fill)

  // Slack's spacer above a section header (all but the first): room on
  // top, outside the header's own height.
  readonly property real gap: isSection && row.gap && !narrow ? t.sp(10) : 0
  height: (isSection ? t.sp(narrow ? 14 : 32) : t.sp(narrow ? 40 : 28)) + gap

  // The unread bar at the left edge (Preferences → Sidebar).
  Rectangle {
    visible: r.isConv && r.row.unread && !r.selected && r.app.unreadBar && !r.narrow
    x: 0
    width: r.t.sp(3)
    height: parent.height - r.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    radius: width / 2
    color: r.t.fgBright
  }

  // The section a drag would drop into.
  readonly property bool dropHere: !!sidebar && sidebar.dropSection !== "" && (r.isSection ? r.row.id === sidebar.dropSection : r.row.section === sidebar.dropSection)
  Rectangle {
    visible: r.dropHere
    anchors.fill: parent
    anchors.topMargin: r.gap
    color: r.t.alpha(r.t.accent, 0.12)
  }
  Rectangle {
    visible: r.dropHere && r.isSection
    anchors.bottom: parent.bottom
    x: r.t.sp(10)
    width: parent.width - r.t.sp(20)
    height: 2
    color: r.t.accent
  }

  Rectangle {
    id: bg
    visible: !r.isSection
    x: r.t.sp(8)
    width: parent.width - r.t.sp(16)
    height: parent.height
    radius: Math.max(6, r.t.radiusSmall)
    color: r.fill
  }

  // ---------------------------------------------------------------- section
  Item {
    visible: r.isSection
    anchors.fill: parent
    anchors.topMargin: r.gap
    // The header hovered, its buttons too: the row's MouseArea loses the
    // hover to a button over it, which would hide them under the mouse.
    HoverHandler { id: secHover }
    Rectangle { visible: r.narrow; anchors.centerIn: parent; width: parent.width * 0.5; height: 1; color: r.t.line }
    Row {
      visible: !r.narrow
      x: r.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: r.t.sp(2)
      spacing: r.t.sp(6)
      // Slack: the section's own icon (its emoji, the star of Starred) where
      // the caret would be; the caret when it has none, and while anywhere
      // on the header is hovered (secHover sees past the buttons), so it
      // folds from there.
      Rectangle {
        id: secLead
        readonly property string icon: r.row.emoji && secEmoji.res ? "emoji" : (r.row.type === "stars" ? "star" : "")
        readonly property bool caret: icon === "" || secHover.hovered
        readonly property int iconSize: Math.min(width, Math.round(secLabel.implicitHeight))
        width: r.t.sp(20); height: width; radius: 4
        color: leadMa.containsMouse ? r.t.hoverStrong : "transparent"
        anchors.verticalCenter: parent.verticalCenter
        EmojiIcon {
          id: secEmoji
          // Hidden by opacity: hiding it would stop its image, which then
          // didn't always come back (after folding the section).
          visible: secLead.icon === "emoji"
          opacity: secLead.caret ? 0 : 1
          anchors.centerIn: parent
          app: r.app
          ws: r.ws
          name: r.row.emoji || ""
          size: secLead.iconSize
        }
        Glyph {
          visible: secLead.icon === "star" && !secLead.caret
          anchors.centerIn: parent
          app: r.app
          icon: "󰓒"
          size: secLead.iconSize - 1
          color: secLabel.color
        }
        Glyph {
          visible: secLead.caret
          anchors.centerIn: parent
          app: r.app
          icon: r.row.collapsed ? "󰍟" : "󰍝"
          size: r.t.fsSidebar + 4
          color: secLabel.color
        }
        MouseArea { id: leadMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r.ws.toggleCollapsed(r.row.id) }
      }
      Text {
        id: secLabel
        text: r.row.label || ""
        textFormat: Text.PlainText
        color: r.row.unread ? r.t.unreadText : r.t.readText
        font.family: r.t.font
        font.pixelSize: r.t.fsSidebar - 1
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        width: Math.min(implicitWidth, r.width - r.t.sp(110))
      }
    }
    Row {
      visible: !r.narrow && (ma.containsMouse || secHover.hovered)
      anchors.right: parent.right
      anchors.rightMargin: r.t.sp(11)
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: r.t.sp(2)
      spacing: 0
      IconButton {
        id: secMore
        app: r.app; size: r.t.sp(28); icon: "󰇙"; iconSize: r.t.fsSmall
        tip: r.app.tr("Section options", "Opções da seção")
        onClicked: { var p = secMore.mapToItem(r.win.contentItem, 0, secMore.height); r.sidebar.sectionMenu(r.row, p.x, p.y) }
      }
      IconButton {
        id: secAdd
        visible: r.row.type === "channels" || r.row.type === "direct_messages"
        app: r.app; size: r.t.sp(28); icon: "󰐕"; iconSize: r.t.fsSmall
        tip: r.row.type === "channels" ? r.app.tr("Add channels", "Adicionar canais") : r.app.tr("New message", "Nova mensagem")
        onClicked: r.row.type === "channels" ? r.win.dialog("browse") : r.win.dialog("newMessage")
      }
    }
  }

  // ---------------------------------------------------------------- leading
  Item {
    id: lead
    visible: !r.isSection
    x: r.narrow ? (r.width - width) / 2 : r.t.sp(18)
    width: r.narrow ? r.t.sp(30) : r.t.sp(20)
    height: width
    anchors.verticalCenter: parent.verticalCenter

    // Channel: # / lock / shared.
    Glyph {
      visible: r.typingNames.length === 0 && ((r.row.kind === "nav" && !r.row.user) || (r.isConv && (r.row.convKind === "channel" || r.row.convKind === "private")) || r.row.kind === "add")
      anchors.centerIn: parent
      app: r.app
      icon: r.row.kind === "nav" ? (r.row.icon || "") : (r.row.kind === "add" ? "󰐕" : (r.row.convKind === "private" ? "󰌾" : (r.row.ext ? "󰇧" : "#")))
      size: r.row.convKind === "channel" && !r.row.ext ? r.t.fsSidebar + 2 : r.t.fsSidebar
      font.bold: r.row.convKind === "channel"
      color: r.ink
      opacity: r.selected || r.row.unread ? 1 : 0.85
    }
    // DM: the photo, with presence.
    PresenceDot {
      visible: r.isConv && r.row.convKind === "im" && r.typingNames.length === 0 && !!r.ws && !r.ws.sidebarAvatars && !r.narrow
      anchors.centerIn: parent
      app: r.app
      size: r.t.sp(9)
      ring: r.under
      ink: r.selected ? r.t.rowSelectedText : "transparent"
      active: r.ws ? r.ws.isActive(r.row.user || "") : false
      paused: r.ws ? r.ws.isPaused(r.row.user || "") : false
    }
    Avatar {
      // A DM's photo, or a page's that is someone's (Slackbot's link).
      readonly property bool page: r.row.kind === "nav" && !!r.row.user
      visible: page || (r.isConv && r.row.convKind === "im" && r.typingNames.length === 0 && (!r.ws || r.ws.sidebarAvatars || r.narrow))
      anchors.centerIn: parent
      app: r.app
      ws: r.ws
      user: r.row.user || ""
      size: page ? Math.round(parent.width * 0.8) : parent.width
      showPresence: !page
      ring: r.under
      presenceInk: r.selected ? r.t.rowSelectedText : "transparent"
      round: 0.25
      onClicked: r.activate()
    }
    // Group DM: how many others.
    Rectangle {
      visible: r.isConv && r.row.convKind === "mpim" && r.typingNames.length === 0
      anchors.fill: parent
      radius: Math.round(width * 0.25)
      color: r.t.alpha(r.t.fg, r.selected ? 0.2 : 0.14)
      Text {
        anchors.centerIn: parent
        text: String(Math.max(2, r.row.members || 2))
        color: r.ink
        font.family: r.t.font
        font.pixelSize: r.t.fsSmall
        font.bold: true
      }
    }
    // Someone typing: Slack's three dots.
    TypingDots {
      visible: r.typingNames.length > 0
      anchors.centerIn: parent
      app: r.app
      color: r.ink
    }
  }

  // ---------------------------------------------------------------- label
  // The name; your own DM adds a dim "you" (Slack: "Ana  you"); a DM
  // then shows the person's status emoji right after.
  Item {
    id: labelBox
    visible: !r.isSection && !r.narrow
    anchors.left: lead.right
    anchors.leftMargin: r.t.sp(8)
    anchors.right: trail.left
    anchors.rightMargin: r.t.sp(6)
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    Row {
      id: labelRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: r.t.sp(5)
      Text {
        id: label
        width: Math.max(0, Math.min(implicitWidth, labelBox.width - (youTag.visible ? youTag.implicitWidth + labelRow.spacing : 0) - (statusIcon.visible ? statusIcon.width + labelRow.spacing : 0)))
        anchors.verticalCenter: parent.verticalCenter
        text: r.row.kind === "add" ? (r.row.sectionType === "channels" ? r.app.tr("Add channels", "Adicionar canais")
              : (r.row.invite ? r.app.tr("Invite people", "Convidar pessoas") : r.app.tr("Add coworkers", "Adicionar colegas")))
            : (r.row.self && r.ws && r.ws.user(r.row.user) ? r.ws.user(r.row.user).name : (r.row.label || ""))
        color: r.ink
        font.family: r.t.font
        font.pixelSize: r.t.fsSidebar
        font.bold: (r.row.unread || r.selected) && r.row.kind !== "add"
        elide: Text.ElideRight
      }
      Text {
        id: youTag
        visible: r.isIm && !!r.row.self
        anchors.verticalCenter: parent.verticalCenter
        text: r.app.tr("you", "você")
        color: r.t.alpha(r.ink, r.ink.a * 0.62)
        font.family: r.t.font
        font.pixelSize: r.t.fsSidebar
      }
      EmojiIcon {
        id: statusIcon
        visible: r.hasStatus && !!statusIcon.res
        anchors.verticalCenter: parent.verticalCenter
        app: r.app
        ws: r.ws
        name: r.status ? r.status.emoji.replace(/:/g, "") : ""
        glyph: r.status && r.status.unicode ? EmojiLib.fromHex(r.status.unicode) : ""
        url: r.status ? r.status.url : ""
        size: r.t.fsSidebar + 2
        HoverHandler { id: statusHover }
        StatusTip { app: r.app; ws: r.ws; status: r.status; hovered: statusHover.hovered }
      }
    }
  }

  // Draft, muted, mention badge: at the right edge.
  Row {
    id: trail
    visible: !r.isSection && !r.narrow
    anchors.right: parent.right
    anchors.rightMargin: r.t.sp(16)
    anchors.verticalCenter: parent.verticalCenter
    spacing: r.t.sp(6)
    Glyph {
      visible: r.isConv && !!r.row.draft
      app: r.app
      icon: "󰏫"
      size: r.t.fsSmall
      color: r.ink
    }
    Glyph {
      visible: r.isConv && r.row.muted && !(r.row.mentions > 0)
      app: r.app
      icon: "󰂛"
      size: r.t.fsSmall
      color: r.ink
      opacity: 0.7
    }
    Badge {
      app: r.app
      visible: (r.isConv || r.row.kind === "nav") && r.row.mentions > 0
      count: r.row.mentions || 0
    }
    Badge {
      app: r.app
      visible: r.row.kind === "nav" && r.row.id === "drafts" && (r.row.count || 0) > 0
      count: r.row.count || 0
      fill: r.t.alpha(r.t.fg, 0.16)
      ink: r.ink
    }
  }

  // Narrow: a dot or a badge over the icon.
  Badge {
    app: r.app
    visible: r.narrow && !r.isSection && (r.row.mentions || 0) > 0
    count: r.row.mentions || 0
    anchors.right: lead.right
    anchors.top: lead.top
    anchors.rightMargin: -r.t.sp(8)
    anchors.topMargin: -r.t.sp(6)
  }
  Rectangle {
    visible: r.narrow && r.isConv && r.row.unread && !(r.row.mentions > 0)
    width: r.t.sp(8); height: width; radius: width / 2
    color: r.t.fgBright
    anchors.right: lead.right
    anchors.top: lead.top
    anchors.rightMargin: -r.t.sp(4)
    anchors.topMargin: -r.t.sp(3)
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    anchors.topMargin: r.gap
    hoverEnabled: true
    z: -1
    cursorShape: r.isSection ? Qt.ArrowCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    property point pressAt
    property bool dragging: false
    preventStealing: true
    onPressed: mouse => { pressAt = Qt.point(mouse.x, mouse.y); dragging = false }
    onPositionChanged: mouse => {
      if (!(mouse.buttons & Qt.LeftButton) || r.narrow) return
      var draggable = r.isConv || (r.isSection && !r.row.silenced)
      if (!draggable) return
      var p = ma.mapToItem(r.sidebar, mouse.x, mouse.y)
      if (!dragging && Math.abs(mouse.y - pressAt.y) + Math.abs(mouse.x - pressAt.x) > 8) { dragging = true; r.sidebar.dragStart(r.row, p.x, p.y) }
      if (dragging) r.sidebar.dragMove(p.x, p.y)
    }
    onReleased: if (dragging) { r.sidebar.dragEnd(); Qt.callLater(function() { ma.dragging = false }) }
    onCanceled: if (dragging) { dragging = false; r.sidebar.dragRow = null }
    onClicked: mouse => {
      if (dragging) return
      var p = ma.mapToItem(r.win.contentItem, mouse.x, mouse.y)
      if (mouse.button === Qt.RightButton) {
        if (r.isConv) r.sidebar.convMenu(r, r.row, p.x, p.y)
        else if (r.isSection) r.sidebar.sectionMenu(r.row, p.x, p.y)
        return
      }
      if (mouse.button === Qt.MiddleButton && r.isConv) { r.ws.markRead(r.row.id); return }
      r.activate()
    }
  }

  PanelToolTip {
    visible: ma.containsMouse && (r.narrow || label.truncated) && !r.isSection && !statusHover.hovered
    text: r.row.kind === "add" ? label.text : (r.row.label || "") + (r.typingNames.length ? "  ·  " + r.typingNames.join(", ") + "…" : "")
  }

  function activate() {
    if (r.isSection) { r.ws.toggleCollapsed(r.row.id); return }
    if (r.row.kind === "nav" && r.row.user) { r.ws.openDm([r.row.user]); return }
    if (r.row.kind === "nav") { r.ws.showView(r.row.id); return }
    if (r.row.kind === "add") { r.row.sectionType === "channels" ? r.win.dialog("browse") : r.win.dialog("invite"); return }
    r.ws.open(r.row.id)
  }
}
