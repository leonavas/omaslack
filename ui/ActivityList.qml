import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Registry.js" as Reg

// The rail's Activity tab (in the sidebar's place): mentions of you,
// unread thread replies and reactions to your messages, newest first, with
// All / Mentions / Threads / Reactions filters. A click opens the message.
Rectangle {
  id: al
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  readonly property bool narrow: width < t.sp(150)
  property string filter: "all"          // all | mentions | threads | reactions
  property string selectedKey: ""
  color: t.sidebar

  // ---------------------------------------------------------------- data
  // Mentions: Slack's search for <@me> (or @handle when that finds nothing).
  property var hits: []
  property bool mentionsLoading: false
  property bool mentionsLoaded: false
  property string mentionsError: ""
  property int serial: 0

  function loadMentions() {
    if (!al.ws) return
    var n = ++al.serial
    al.mentionsLoading = true
    al.mentionsError = ""
    al.ws.searchMessages("<@" + al.ws.me.id + ">", "timestamp", 1, function(r) {
      try { if (n !== al.serial) return } catch (e) { return }
      if (!r.error && r.hits.length === 0 && al.ws.me.handle) {
        al.ws.searchMessages("@" + al.ws.me.handle, "timestamp", 1, function(r2) {
          try { if (n !== al.serial) return } catch (e) { return }
          al.done(r2)
        })
        return
      }
      al.done(r)
    })
  }
  function done(r) {
    al.hits = r.hits || []
    al.mentionsError = r.error || ""
    al.mentionsLoading = false
    al.mentionsLoaded = true
  }

  function refresh() { al.loadMentions(); if (al.ws) al.ws.loadThreads() }
  Component.onCompleted: { al.refresh(); al.keepUnread() }

  // Threads: the unread ones; a thread read while this list shows keeps its
  // row (now read) until the tab is opened again.
  property var kept: ({})
  property int keptRev: 0
  function keepUnread() {
    if (!al.ws) return
    var changed = false
    al.ws.threadsView.list.forEach(function(c) { if (c.unread && !al.kept[c.key]) { al.kept[c.key] = true; changed = true } })
    if (changed) al.keptRev++
  }
  Connections {
    target: al.ws
    function onThreadsRevChanged() { al.keepUnread() }
  }

  // An app's picture as its message has it (Workspace.author); a person's comes from `user`.
  function appIcon(m) { var a = al.ws.author(m); return a.app ? a.icon : "" }

  function where(conv, fallbackName, fallbackKind) {
    var c = al.ws.conv(conv)
    var kind = c ? c.kind : fallbackKind
    if (kind === "im") return { pre: al.app.tr(" in a direct message", " numa mensagem direta"), name: "" }
    if (kind === "mpim") return { pre: al.app.tr(" in ", " em "), name: al.ws.convLabel(conv) || fallbackName || "" }
    return { pre: al.app.tr(" in ", " em "), name: "#" + (al.ws.convLabel(conv) || fallbackName || conv) }
  }

  readonly property var mentionItems: {
    if (!ws) return []
    ws.countsRev; ws.usersRev; ws.convsRev
    return al.hits.map(function(h) {
      var k = ws.counts[h.conv]
      var clean = String(h.text || "").replace(/[]/g, "")
      var msg = Model.parseMessage({ text: clean, attachments: h.attachments || [], files: h.files || [] })
      return { key: "m/" + h.conv + "/" + h.ts, kind: "mention", conv: h.conv, ts: h.ts, threadTs: h.threadTs || "", user: h.user || "",
               who: ws.author(h).name || h.username || "?", icon: al.appIcon(h), where: al.where(h.conv, h.convName, h.convKind),
               text: Md.flat(msg, al.ctx, 220), when: h.ts,
               unread: !h.threadTs && !!k && !!k.lastRead && U.cmpTs(h.ts, k.lastRead) > 0, extra: "" }
    })
  }

  readonly property var threadItems: {
    if (!ws) return []
    ws.threadsRev; ws.usersRev; ws.convsRev; al.keptRev
    var me = ws.me.id
    var out = []
    ws.threadsView.list.forEach(function(c) {
      if (!c.unread && !al.kept[c.key]) return
      var others = c.replies.filter(function(r) { return r.user !== me })
      var last = others.length ? others[others.length - 1] : (c.replies.length ? c.replies[c.replies.length - 1] : c.root)
      out.push({ key: "t/" + c.key, kind: "thread", conv: c.conv, ts: c.root.ts, threadTs: c.root.ts, user: last.user || "",
                 who: ws.author(last).name || "?", icon: al.appIcon(last), where: al.where(c.conv, "", ""),
                 text: Md.flat(last, al.ctx, 220), when: c.latest || last.ts, unread: c.unread,
                 extra: c.unread && c.newCount > 1 ? (c.newCount + al.app.tr(" new replies", " novas respostas")) : "" })
    })
    return out
  }

  // Reactions by others to your messages, from what this app has loaded
  // (conversations and threads opened), newest message first.
  readonly property var reactionItems: {
    if (!ws) return []
    ws.historyRev; ws.repliesRev; ws.usersRev; ws.convsRev
    var me = ws.me.id
    var out = [], seen = {}
    function scan(conv, msgs) {
      for (var i = msgs.length - 1; i >= 0; i--) {
        var m = msgs[i]
        if (!m.reactions || !m.reactions.length || m.pending || !Model.isMine(m, me)) continue
        m.reactions.forEach(function(r) {
          var others = r.users.filter(function(u) { return u !== me })
          var count = Math.max(others.length, (r.count || 0) - (r.users.indexOf(me) >= 0 ? 1 : 0))
          if (count <= 0) return
          var key = "r/" + conv + "/" + m.ts + "/" + r.name
          if (seen[key]) return
          seen[key] = true
          var names = others.slice(0, 2).map(function(u) { return ws.userName(u) || "?" })
          var rest = count - names.length
          var who = !names.length ? count + al.app.tr(count === 1 ? " person" : " people", count === 1 ? " pessoa" : " pessoas")
                  : (rest > 0 ? names.join(", ") + al.app.tr(" and " + rest + (rest === 1 ? " other" : " others"), " e mais " + rest) : Model.people(names, 0, al.app.lang))
          out.push({ key: key, kind: "reaction", conv: conv, ts: m.ts, threadTs: m.threadTs && m.threadTs !== m.ts ? m.threadTs : "", user: others[0] || "",
                     who: who, where: al.where(conv, "", ""), emoji: r.name, text: Md.flat(m, al.ctx, 220), when: m.ts, unread: false, extra: "" })
        })
      }
    }
    for (var conv in ws.histories) { var h = ws.histories[conv]; if (h && h.msgs) scan(conv, h.msgs) }
    for (var k in ws.replies) { var r = ws.replies[k]; if (r && r.msgs) scan(k.split("/")[0], r.msgs) }
    out.sort(function(a, b) { return U.cmpTs(b.when, a.when) })
    return out.slice(0, 100)
  }

  readonly property var items: {
    if (al.filter === "mentions") return al.mentionItems
    if (al.filter === "threads") return al.threadItems
    if (al.filter === "reactions") return al.reactionItems
    var all = al.mentionItems.concat(al.threadItems, al.reactionItems)
    all.sort(function(a, b) { return U.cmpTs(b.when, a.when) })
    return all
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: al.t.sp(50)
    Text {
      visible: !al.narrow
      x: al.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - refreshBtn.width - al.t.sp(20)
      text: al.app.tr("Activity", "Atividade")
      color: al.t.fgBright
      font.family: al.t.font
      font.pixelSize: al.t.fsHeader
      font.bold: true
      elide: Text.ElideRight
    }
    IconButton {
      id: refreshBtn
      app: al.app
      anchors.right: parent.right
      anchors.rightMargin: al.narrow ? (parent.width - width) / 2 : al.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      size: al.t.sp(32)
      icon: al.narrow ? "󰂚" : "󰑓"
      tip: al.app.tr("Refresh", "Atualizar")
      color: al.t.fgBright
      hoverColor: al.t.hoverStrong
      onClicked: al.refresh()
    }
  }

  // All · Mentions · Threads · Reactions. When they don't fit, the ones
  // not chosen fold to their icon.
  readonly property var tabList: [
    { id: "all", icon: "󰂚", label: al.app.tr("All", "Tudo") },
    { id: "mentions", icon: "󰁥", label: al.app.tr("Mentions", "Menções") },
    { id: "threads", icon: "󰍪", label: al.app.tr("Threads", "Conversas") },
    { id: "reactions", icon: "󰇵", label: al.app.tr("Reactions", "Reações") }
  ]
  Row {
    id: measure
    visible: false
    spacing: al.t.sp(2)
    Repeater {
      model: al.tabList
      delegate: Text { required property var modelData; text: modelData.label; font.family: al.t.font; font.pixelSize: al.t.fsSmall + 1; font.bold: true; rightPadding: al.t.sp(16) + al.t.sp(18) }
    }
  }
  readonly property bool compactTabs: measure.implicitWidth + al.t.sp(44) > width

  Flickable {
    id: tabs
    visible: !al.narrow
    y: header.height
    width: parent.width
    height: visible ? al.t.sp(36) : 0
    contentWidth: tabRow.implicitWidth + al.t.sp(20)
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Row {
      id: tabRow
      x: al.t.sp(10)
      height: parent.height
      spacing: al.t.sp(2)
      Repeater {
        model: al.tabList
        delegate: Item {
          id: tab
          required property var modelData
          readonly property bool active: al.filter === modelData.id
          readonly property bool folded: al.compactTabs && !active
          readonly property int count: modelData.id === "threads" ? al.threadItems.filter(function(i) { return i.unread }).length
                                     : (modelData.id === "mentions" ? al.mentionItems.filter(function(i) { return i.unread }).length : 0)
          height: tabRow.height
          width: tabInner.implicitWidth + al.t.sp(16)
          Rectangle {
            anchors.fill: parent
            anchors.topMargin: al.t.sp(3)
            anchors.bottomMargin: al.t.sp(5)
            radius: Math.max(4, al.t.radiusSmall)
            color: tabMa.containsMouse && !tab.active ? al.t.hover : "transparent"
          }
          Row {
            id: tabInner
            x: al.t.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -al.t.sp(1)
            spacing: al.t.sp(5)
            Glyph {
              app: al.app
              visible: tab.folded || tab.active
              icon: tab.modelData.icon
              size: al.t.fsSmall + 1
              color: tab.active ? al.t.fgBright : al.t.fgDim
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              visible: !tab.folded
              text: tab.modelData.label
              color: tab.active ? al.t.fgBright : al.t.fgDim
              font.family: al.t.font
              font.pixelSize: al.t.fsSmall + 1
              font.bold: tab.active
              anchors.verticalCenter: parent.verticalCenter
            }
            Badge {
              app: al.app
              anchors.verticalCenter: parent.verticalCenter
              visible: tab.count > 0
              count: tab.count
              implicitHeight: al.t.sp(16)
            }
          }
          Rectangle {
            visible: tab.active
            anchors.bottom: parent.bottom
            x: al.t.sp(4)
            width: parent.width - al.t.sp(8)
            height: 2
            radius: 1
            color: al.t.fgBright
          }
          MouseArea {
            id: tabMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (al.filter === tab.modelData.id && tab.modelData.id === "mentions") al.loadMentions()
              al.filter = tab.modelData.id
              list.positionViewAtBeginning()
            }
          }
          PanelToolTip { visible: tabMa.containsMouse && tab.folded; text: tab.modelData.label }
        }
      }
    }
  }

  Rectangle { y: tabs.y + tabs.height; width: parent.width; height: 1; color: al.t.line }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    y: tabs.y + tabs.height + 1
    width: parent.width
    height: parent.height - y
    clip: true
    topMargin: al.t.sp(6)
    bottomMargin: al.t.sp(12)
    spacing: al.t.sp(2)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: al.items; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: al.app }

    delegate: Item {
      id: row
      required property var modelData
      readonly property bool selected: al.selectedKey === modelData.key
      readonly property bool hot: ma.containsMouse
      readonly property color ink: selected ? al.t.rowSelectedText : (modelData.unread ? al.t.fgBright : al.t.fg)
      readonly property color soft: selected ? al.t.alpha(al.t.rowSelectedText, 0.78) : al.t.fgDim
      // The row's fill, and the color it makes over the list: the corner
      // badge's ring matches it on every state.
      readonly property color fill: selected ? al.t.rowSelected : (ma.pressed ? al.t.hoverStrong : (hot ? al.t.hover
           : (modelData.unread ? al.t.alpha(al.t.blue, 0.08) : "transparent")))
      readonly property color under: Qt.tint(al.t.sidebar, fill)
      width: list.width
      height: al.narrow ? al.t.sp(52) : Math.max(al.t.sp(60), body.implicitHeight + al.t.sp(18))

      Rectangle {
        x: al.t.sp(8)
        width: parent.width - al.t.sp(16)
        height: parent.height
        radius: Math.max(6, al.t.radiusSmall)
        color: row.fill
      }
      // Unread: a dot at the edge.
      Rectangle {
        visible: row.modelData.unread && !row.selected && !al.narrow
        x: al.t.sp(12) - width / 2 + al.t.sp(2)
        y: al.t.sp(16)
        width: al.t.sp(6); height: width; radius: width / 2
        color: al.t.blue
      }

      // The person, with what happened on the corner.
      Item {
        id: lead
        x: al.narrow ? (row.width - width) / 2 : al.t.sp(20)
        y: al.narrow ? (row.height - height) / 2 : al.t.sp(10)
        width: al.t.sp(36)
        height: width
        Avatar {
          anchors.fill: parent
          app: al.app
          ws: al.ws
          user: row.modelData.user
          url: row.modelData.icon || ""
          name: row.modelData.user ? "" : row.modelData.who
          size: parent.width
          onClicked: al.openItem(row.modelData)
        }
        Rectangle {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -al.t.sp(5)
          anchors.bottomMargin: -al.t.sp(5)
          width: al.t.sp(20); height: width; radius: width / 2
          color: row.modelData.kind === "reaction" ? al.t.popup : (row.modelData.kind === "mention" ? al.t.badge : al.t.blue)
          border.width: 2
          border.color: row.under
          Glyph {
            visible: row.modelData.kind !== "reaction"
            app: al.app
            anchors.centerIn: parent
            icon: row.modelData.kind === "mention" ? "󰁥" : "󰍪"
            size: al.t.fsTiny
            color: al.t.onColor(parent.color)
          }
          EmojiIcon {
            visible: row.modelData.kind === "reaction"
            app: al.app
            ws: al.ws
            anchors.centerIn: parent
            name: row.modelData.emoji || ""
            size: al.t.sp(13)
          }
        }
      }

      Column {
        id: body
        visible: !al.narrow
        anchors.left: lead.right
        anchors.leftMargin: al.t.sp(12)
        anchors.right: parent.right
        anchors.rightMargin: al.t.sp(18)
        y: al.t.sp(9)
        spacing: al.t.sp(3)

        Text {
          width: parent.width
          text: al.titleOf(row.modelData)
          textFormat: Text.StyledText
          color: row.ink
          font.family: al.t.font
          font.pixelSize: al.t.fsSmall + 1
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: row.modelData.text
          textFormat: Text.PlainText
          color: row.selected ? al.t.rowSelectedText : (row.modelData.unread ? al.t.fg : al.t.alpha(al.t.fg, 0.75))
          font.family: al.t.font
          font.pixelSize: al.t.fsSmall
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: U.relative(row.modelData.when, al.app.lang, al.app.clock24) + (row.modelData.extra ? "  ·  " + row.modelData.extra : "")
          color: row.soft
          font.family: al.t.font
          font.pixelSize: al.t.fsTiny
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        z: -1
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
          if (mouse.button === Qt.RightButton) { var p = ma.mapToItem(al.win.contentItem, mouse.x, mouse.y); al.rowMenu(row.modelData, p.x, p.y); return }
          al.openItem(row.modelData)
        }
      }
      PanelToolTip { visible: ma.containsMouse && al.narrow; text: row.modelData.who + ": " + row.modelData.text }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: al.items.length === 0 && !al.narrow
    anchors.horizontalCenter: parent.horizontalCenter
    y: list.y + al.t.sp(48)
    width: parent.width - al.t.sp(40)
    spacing: al.t.sp(8)
    readonly property bool loading: (al.filter === "mentions" || al.filter === "all") && al.mentionsLoading && !al.mentionsLoaded
    Glyph {
      app: al.app
      anchors.horizontalCenter: parent.horizontalCenter
      icon: al.filter === "mentions" ? "󰁥" : (al.filter === "threads" ? "󰍪" : (al.filter === "reactions" ? "󰇵" : "󰂚"))
      size: al.t.sp(30)
      color: al.t.fgDim
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: parent.loading ? al.app.tr("Loading…", "Carregando…")
          : (al.filter === "mentions" && al.mentionsError ? al.mentionsError
          : (al.filter === "mentions" ? al.app.tr("No mentions yet", "Nenhuma menção ainda")
          : (al.filter === "threads" ? al.app.tr("No unread threads", "Nenhuma conversa não lida")
          : (al.filter === "reactions" ? al.app.tr("No reactions yet", "Nenhuma reação ainda")
          : al.app.tr("You're all caught up", "Você está em dia")))))
      color: al.t.fgBright
      font.family: al.t.font
      font.pixelSize: al.t.fsText
      font.bold: true
    }
    Text {
      visible: !parent.loading
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: al.filter === "mentions" ? al.app.tr("When someone @mentions you, it shows up here.", "Quando alguém @mencionar você, aparece aqui.")
          : (al.filter === "threads" ? al.app.tr("New replies in threads you follow show up here.", "Novas respostas nas conversas que você segue aparecem aqui.")
          : (al.filter === "reactions" ? al.app.tr("Reactions to your messages in the conversations you open show up here.", "Reações às suas mensagens nas conversas que você abre aparecem aqui.")
          : al.app.tr("Mentions, thread replies and reactions to your messages show up here.", "Menções, respostas em conversas e reações às suas mensagens aparecem aqui.")))
      color: al.t.fgDim
      font.family: al.t.font
      font.pixelSize: al.t.fsSmall
    }
  }

  // ---------------------------------------------------------------- actions
  // "<b>Ana</b> mentioned you in <b>#eng</b>"
  function titleOf(it) {
    var b = function(s) { return "<b>" + U.escapeHtml(s) + "</b>" }
    var w = it.where
    var place = w.pre + (w.name ? b(w.name) : "")
    if (it.kind === "mention") return b(it.who) + al.app.tr(" mentioned you", " mencionou você") + place
    if (it.kind === "thread") return b(it.who) + al.app.tr(" replied to a thread", " respondeu a uma conversa") + place
    return b(it.who) + al.app.tr(" reacted to your message", " reagiu à sua mensagem") + place
  }

  function openItem(it) {
    al.selectedKey = it.key
    if (it.kind === "thread") { al.ws.open(it.conv, { ts: it.ts, threadTs: it.ts }); return }
    if (it.threadTs && it.threadTs !== it.ts) al.ws.open(it.conv, { ts: it.ts, threadTs: it.threadTs })
    else al.ws.open(it.conv, { ts: it.ts })
  }

  function rowMenu(it, x, y) {
    var w = al.ws
    var items = [
      { label: al.app.tr("Open", "Abrir"), icon: "󰁔", action: function() { al.openItem(it) } }
    ]
    if (it.threadTs || it.kind === "thread") items.push({ label: al.app.tr("Open thread", "Abrir conversa"), icon: "󰍪", action: function() { al.selectedKey = it.key; w.openThread(it.conv, it.threadTs || it.ts) } })
    if (it.kind === "thread" && it.unread) items.push({ label: al.app.tr("Mark as read", "Marcar como lida"), icon: "󰄬", action: function() {
      var c = w.threadsView.list.filter(function(x) { return "t/" + x.key === it.key })[0]
      if (c) w.markThread(c.conv, c.root.ts, c.latest || c.root.ts)
    } })
    items.push({ separator: true })
    items.push({ label: al.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() {
      al.app.copy(w.permalink(it.conv, { ts: it.ts, threadTs: it.threadTs })); al.win.toast(al.app.tr("Link copied", "Link copiado")) } })
    al.win.menu(items, x, y)
  }
}
