import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Registry.js" as Reg

// The rail's Activity tab (in the sidebar's place), as Slack's own: its
// activity.feed (DMs, mentions, thread replies, reactions to your messages,
// apps, invitations), newest first and by day, with All / DMs / Mentions /
// Threads and Unreads. The feed only points at messages; they come one by
// one (Workspace.fetchOne). A click opens the message. `peek`: the card
// hovering the rail's Activity shows (AppWindow), no tabs, its own Unreads.
Rectangle {
  id: al
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  readonly property bool narrow: width < t.sp(150)
  property bool peek: false
  property string filter: "all"          // all | dms | mentions | threads
  readonly property string unreadsSetting: peek ? "activityPeekUnreads" : "activityUnreadsOnly"
  property bool unreadsOnly: app.setting(unreadsSetting, false) === true
  readonly property string selectedKey: win && !peek ? win.activityKey : ""
  color: t.sidebar
  function toggleUnreads() { al.unreadsOnly = !al.unreadsOnly; al.app.setSetting(al.unreadsSetting, al.unreadsOnly) }

  // ---------------------------------------------------------------- data
  // What each tab asks for, as the web client does.
  readonly property string mentionTypes: "at_user,at_user_group,at_channel,at_everyone,keyword,unjoined_channel_mention"
  readonly property var typesOf: ({
    all: mentionTypes + ",thread_v2,message_reaction,bot_dm_bundle,dm,internal_channel_invite,external_channel_invite",
    dms: "dm",
    mentions: mentionTypes,
    threads: "thread_v2"
  })

  property var refs: []                  // [{key, type, when, unread, conv, ts, threadTs, by, reaction, count}]
  property string cursor: ""
  property int pages: 0
  property bool loading: false
  property bool loaded: false
  property string error: ""
  property int serial: 0
  // Entries marked read or unread here (key → unread) until the feed says so.
  property var marks: ({})
  property int marksRev: 0

  function load(more) {
    if (!al.ws || (more && (!al.cursor || al.loading))) return
    var n = more ? al.serial : ++al.serial
    al.loading = true
    al.ws.activityFeed(al.typesOf[al.filter], more ? al.cursor : "", al.unreadsOnly, function(r) {
      try { if (n !== al.serial) return } catch (e) { return }
      var got = r.items.map(al.refOf).filter(function(x) { return x })
      if (more) {
        var have = {}
        al.refs.forEach(function(x) { have[x.key] = true })
        got = al.refs.concat(got.filter(function(x) { return !have[x.key] }))
      }
      al.refs = got
      if (!more) { al.marks = {}; al.marksRev++ }
      al.cursor = r.cursor
      al.pages = more ? al.pages + 1 : 1
      al.error = r.error || ""
      al.loading = false
      al.loaded = true
      got.forEach(function(x) { if (!al.ws.knownMessage(x.conv, x.ts)) al.ws.fetchOne(x.conv, x.ts, x.threadTs) })
    })
  }
  function reset() { al.serial++; al.refs = []; al.cursor = ""; al.pages = 0; al.loaded = false; al.error = ""; al.load(false) }
  onFilterChanged: al.reset()
  onUnreadsOnlyChanged: al.reset()
  Component.onCompleted: al.load(false)

  // New messages and reads move the feed: the first page again, quietly,
  // unless more pages are showing.
  Timer { id: live; interval: 3000; onTriggered: if (!al.loading && al.pages <= 1) al.load(false) }
  Connections {
    target: al.ws
    function onCountsRevChanged() { live.restart() }
  }

  // One feed entry → where its message is and what it says about it.
  function refOf(it) {
    var i = it.item || {}, b = i.bundle_info || {}, p = b.payload || {}, m = i.message || {}
    var r = { key: it.key, type: i.type, when: it.feed_ts, unread: !!it.is_unread, conv: m.channel || "", ts: m.ts || "",
              threadTs: m.thread_ts || "", by: m.author_user_id || "", reaction: i.reaction || null, count: 0 }
    if (i.type === "dm") {
      // Its newest message from the other side (feed_ts), not the newest one.
      r.conv = ((p.dm_entry || {}).latest_message || {}).channel || ""
      r.ts = it.feed_ts
    } else if (i.type === "thread_v2") {
      var e = p.thread_entry || {}
      r.conv = e.channel_id || ""; r.ts = e.latest_ts || ""; r.threadTs = e.thread_ts || ""; r.count = e.unread_msg_count || 0
    } else if (i.type === "bot_dm_bundle") {
      r.conv = (p.message || {}).channel || ""; r.ts = (p.message || {}).ts || ""; r.count = b.unread_count || 0
    }
    return r.conv && r.ts ? r : null
  }

  // undefined/null: not here yet; false: gone (deleted or out of reach).
  function messageOf(r) {
    var m = al.ws.knownMessage(r.conv, r.ts)
    return m ? m : al.ws.oneMsgs[r.conv + "/" + r.ts]
  }
  function nameOf(uid) { return uid ? (al.ws.author({ user: uid }).name || "") : "" }

  function rowOf(r, m) {
    var ws = al.ws
    var c = ws.conv(r.conv)
    var kind = c ? c.kind : (r.conv.charAt(0) === "D" ? "im" : "channel")
    var invite = r.type === "internal_channel_invite" || r.type === "external_channel_invite"
    var threadTs = r.threadTs || (m && m.threadTs) || ""
    var inThread = !!threadTs && threadTs !== r.ts
    var user = "", who = "", icon = ""
    if (r.type === "message_reaction") { user = r.reaction.user || ""; who = al.nameOf(user) }
    else if (invite) { user = r.by || (m && m.inviter) || ""; who = al.nameOf(user) }
    else if (m) { var a = ws.author(m); user = m.user || ""; who = a.name; icon = a.app ? a.icon : "" }
    else { user = r.by; who = al.nameOf(r.by) }

    var label = ws.convLabel(r.conv)
    var place = kind === "im" ? al.app.tr("Direct message", "Mensagem direta") : label
    var where = "", whereIcon = ""
    if (r.type === "bot_dm_bundle") { where = al.app.tr("App", "App"); whereIcon = "󰚩" }
    else if (invite) { where = al.app.tr("Invitation", "Convite"); whereIcon = kind === "private" ? "󰌾" : "#" }
    else if (r.type === "thread_v2" || inThread) {
      where = al.app.tr("Thread in ", "Conversa em ") + (kind === "channel" || kind === "private" ? "#" + label : place)
      whereIcon = "󰍪"
    } else { where = place; whereIcon = kind === "im" || kind === "mpim" ? "󰍥" : (kind === "private" ? "󰌾" : "#") }
    if (r.count > 1) where += "  ·  " + r.count + al.app.tr(" new", " novas")

    var text = invite ? al.app.tr("invited you to ", "convidou você para ") + "#" + (label || r.conv)
             : (m ? Md.flat(m, al.ctx, 220) : "")
    // Unread messages it stands for: a DM's, a thread's new replies, an app's.
    var k = ws.counts[r.conv]
    var news = r.type === "dm" ? (k ? Math.max(k.mentions || 0, k.unread ? 1 : 0) : 0) : r.count
    return { key: r.key, type: r.type, conv: r.conv, ts: r.ts, threadTs: inThread ? threadTs : "", when: r.when, news: news,
             unread: al.marks[r.key] !== undefined ? al.marks[r.key] : r.unread, user: user, who: who || "…", icon: icon, text: text,
             where: where, whereIcon: whereIcon, emoji: r.reaction ? r.reaction.name : "" }
  }

  // Rows by day, the day's name over all but today's.
  readonly property var items: {
    if (!ws) return []
    ws.oneRev; ws.historyRev; ws.repliesRev; ws.lastRev; ws.previewRev; ws.usersRev; ws.convsRev; ws.botsRev; ws.countsRev; al.marksRev
    var out = [], lastDay = "", now = new Date()
    al.refs.forEach(function(r) {
      var m = al.messageOf(r)
      if (m === false) return
      var d = U.tsDate(r.when), day = d.toDateString()
      if (day !== lastDay) {
        lastDay = day
        if (U.dayDiff(d, now) !== 0) out.push({ key: "d/" + day, header: true, label: U.dayLabel(d, al.app.lang) })
      }
      out.push(al.rowOf(r, m || null))
    })
    return out
  }
  readonly property int rowCount: items.filter(function(i) { return !i.header }).length

  // "45 mins", "3 hours", then "Yesterday", "Mon", "Oct 3".
  function ago(ts) {
    var d = U.tsDate(ts), secs = Math.max(0, (Date.now() - d) / 1000), pt = al.app.lang === "pt-BR"
    if (secs < 60) return al.app.tr("just now", "agora")
    if (secs < 3600) { var mins = Math.floor(secs / 60); return mins + (pt ? " min" : (mins === 1 ? " min" : " mins")) }
    if (U.dayDiff(d, new Date()) === 0) { var h = Math.floor(secs / 3600); return h + (pt ? " h" : (h === 1 ? " hour" : " hours")) }
    return U.shortStamp(ts, al.app.lang, al.app.clock24)
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
      width: parent.width - x - (al.peek ? peekUnreads.width : refreshBtn.width) - al.t.sp(20)
      text: al.app.tr("Activity", "Atividade")
      color: al.t.fgBright
      font.family: al.t.font
      font.pixelSize: al.peek ? al.t.fsText + 1 : al.t.fsHeader
      font.bold: true
      elide: Text.ElideRight
    }
    UnreadsSwitch {
      id: peekUnreads
      app: al.app
      visible: al.peek
      anchors.right: parent.right
      anchors.rightMargin: al.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      checked: al.unreadsOnly
      onToggled: al.toggleUnreads()
    }
    IconButton {
      id: refreshBtn
      visible: !al.peek
      app: al.app
      anchors.right: parent.right
      anchors.rightMargin: al.narrow ? (parent.width - width) / 2 : al.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      size: al.t.sp(32)
      icon: al.narrow ? "󰂚" : "󰑓"
      tip: al.app.tr("Refresh", "Atualizar")
      color: al.t.fgBright
      hoverColor: al.t.hoverStrong
      onClicked: al.load(false)
    }
  }

  // All · DMs · Mentions · Threads. When they don't fit, the ones not
  // chosen fold to their icon.
  readonly property var tabList: [
    { id: "all", icon: "󰂚", label: al.app.tr("All", "Tudo") },
    { id: "dms", icon: "󰍥", label: "DMs" },
    { id: "mentions", icon: "󰁥", label: al.app.tr("Mentions", "Menções") },
    { id: "threads", icon: "󰍪", label: al.app.tr("Threads", "Conversas") }
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
    visible: !al.narrow && !al.peek
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
          readonly property bool news: !!al.ws && al.ws.activityUnread(modelData.id === "all" ? null : al.typesOf[modelData.id].split(",")) > 0
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
            // Something unread there.
            Rectangle {
              visible: tab.news
              width: al.t.sp(6); height: width; radius: width / 2
              color: al.t.badge
              anchors.verticalCenter: parent.verticalCenter
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
              if (al.filter === tab.modelData.id) al.load(false)
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

  // Unreads.
  Item {
    id: tools
    visible: !al.narrow && !al.peek
    y: tabs.y + tabs.height + 1
    width: parent.width
    height: visible ? al.t.sp(44) : 0
    Rectangle {
      id: unreadChip
      x: al.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      height: al.t.sp(30)
      width: chipRow.implicitWidth + al.t.sp(16)
      radius: height / 2
      color: al.unreadsOnly ? al.t.accent : (chipMa.containsMouse ? al.t.hover : "transparent")
      border.width: al.unreadsOnly ? 0 : 1
      border.color: al.t.lineStrong
      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: al.t.sp(5)
        Glyph { app: al.app; icon: al.unreadsOnly ? "󰄬" : "󰇮"; size: al.t.fsSmall; color: al.unreadsOnly ? al.t.selectedText : al.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: al.app.tr("Unreads", "Não lidas")
          color: al.unreadsOnly ? al.t.selectedText : al.t.fg
          font.family: al.t.font
          font.pixelSize: al.t.fsSmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      MouseArea {
        id: chipMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: al.toggleUnreads()
      }
      PanelToolTip { visible: chipMa.containsMouse; text: al.app.tr("Show only unread activity", "Mostrar só atividade não lida") }
    }
  }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    y: tools.y + tools.height
    width: parent.width
    height: parent.height - y
    clip: true
    topMargin: al.t.sp(2)
    bottomMargin: al.t.sp(12)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: al.items; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: al.app }
    onAtYEndChanged: if (atYEnd && al.loaded) al.load(true)

    footer: Item {
      width: list.width
      height: al.loading && al.loaded && al.pages > 0 && al.cursor ? al.t.sp(36) : 0
      Text {
        visible: parent.height > 0
        anchors.centerIn: parent
        text: al.app.tr("Loading…", "Carregando…")
        color: al.t.fgDim
        font.family: al.t.font
        font.pixelSize: al.t.fsSmall
      }
    }

    delegate: Item {
      id: row
      required property var modelData
      readonly property bool head: !!modelData.header
      readonly property bool selected: al.selectedKey === modelData.key
      readonly property bool hot: ma.containsMouse
      readonly property color ink: selected ? al.t.rowSelectedText : (modelData.unread ? al.t.fgBright : al.t.fg)
      readonly property color soft: selected ? al.t.alpha(al.t.rowSelectedText, 0.78) : al.t.fgDim
      // The row's fill, and the color it makes over the list: the corner
      // badge's ring matches it on every state.
      readonly property color fill: selected ? al.t.rowSelected : (ma.pressed ? al.t.hoverStrong : (hot ? al.t.hover : "transparent"))
      readonly property color under: Qt.tint(al.t.sidebar, fill)
      width: list.width
      height: head ? (al.narrow ? 0 : al.t.sp(36)) : (al.narrow ? al.t.sp(52) : Math.max(al.t.sp(64), body.implicitHeight + al.t.sp(20)))

      // A day.
      Rectangle {
        visible: row.head && !al.narrow
        y: al.t.sp(6)
        width: parent.width
        height: 1
        color: al.t.line
      }
      Text {
        visible: row.head && !al.narrow
        x: al.t.sp(16)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: al.t.sp(4)
        text: row.modelData.label || ""
        color: al.t.fgBright
        font.family: al.t.font
        font.pixelSize: al.t.fsSmall + 1
        font.bold: true
      }

      Rectangle {
        visible: !row.head
        x: al.t.sp(8)
        width: parent.width - al.t.sp(16)
        height: parent.height - al.t.sp(2)
        y: 1
        radius: Math.max(6, al.t.radiusSmall)
        color: row.fill
      }
      // Unread: a dot at the edge.
      Rectangle {
        visible: !row.head && row.modelData.unread && !row.selected && !al.narrow
        x: al.t.sp(12) - width / 2 + al.t.sp(2)
        y: al.t.sp(18)
        width: al.t.sp(6); height: width; radius: width / 2
        color: al.t.blue
      }

      // Who, with the reaction on the corner.
      Item {
        id: lead
        visible: !row.head
        x: al.narrow ? (row.width - width) / 2 : al.t.sp(20)
        y: al.narrow ? (row.height - height) / 2 : al.t.sp(10)
        width: al.t.sp(36)
        height: width
        Avatar {
          anchors.fill: parent
          app: al.app
          ws: al.ws
          user: row.modelData.user || ""
          url: row.modelData.icon || ""
          name: row.modelData.user ? "" : (row.modelData.who || "")
          size: parent.width
          onClicked: al.openItem(row.modelData)
        }
        Rectangle {
          visible: !!row.modelData.emoji
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -al.t.sp(5)
          anchors.bottomMargin: -al.t.sp(5)
          width: al.t.sp(20); height: width; radius: width / 2
          color: al.t.popup
          border.width: 2
          border.color: row.under
          EmojiIcon {
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
        visible: !al.narrow && !row.head
        anchors.left: lead.right
        anchors.leftMargin: al.t.sp(12)
        anchors.right: parent.right
        anchors.rightMargin: al.t.sp(16) + (newsBadge.visible ? newsBadge.width + al.t.sp(10) : 0)
        y: al.t.sp(9)
        spacing: al.t.sp(3)

        // Name · when
        Item {
          width: parent.width
          height: whoText.implicitHeight
          Text {
            id: whoText
            width: Math.min(implicitWidth, parent.width - whenText.implicitWidth - al.t.sp(8))
            text: row.modelData.who || ""
            textFormat: Text.PlainText
            color: row.ink
            font.family: al.t.font
            font.pixelSize: al.t.fsSmall + 1
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            id: whenText
            x: whoText.width + al.t.sp(8)
            y: whoText.baselineOffset - baselineOffset
            text: row.head ? "" : al.ago(row.modelData.when)
            color: row.soft
            font.family: al.t.font
            font.pixelSize: al.t.fsTiny
          }
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: row.modelData.text || ""
          textFormat: Text.PlainText
          color: row.selected ? al.t.rowSelectedText : (row.modelData.unread ? al.t.fgBright : al.t.fg)
          font.family: al.t.font
          font.pixelSize: al.t.fsSmall + 1
          font.bold: !!row.modelData.unread
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
        // Where: Direct message · Thread in #eng · App · Invitation.
        Row {
          width: parent.width
          spacing: al.t.sp(5)
          Glyph {
            app: al.app
            icon: row.modelData.whereIcon || ""
            size: al.t.fsTiny
            color: row.soft
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            width: parent.width - al.t.sp(20)
            text: row.modelData.where || ""
            textFormat: Text.PlainText
            color: row.soft
            font.family: al.t.font
            font.pixelSize: al.t.fsTiny
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // How many unread messages it stands for.
      Badge {
        id: newsBadge
        app: al.app
        visible: !row.head && !al.narrow && !!row.modelData.unread && row.modelData.news > 0
        count: row.modelData.news || 0
        anchors.right: parent.right
        anchors.rightMargin: al.t.sp(20)
        y: al.t.sp(12)
      }

      MouseArea {
        id: ma
        visible: !row.head
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
      PanelToolTip { visible: ma.containsMouse && al.narrow && !row.head; text: (row.modelData.who || "") + ": " + (row.modelData.text || "") }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: al.rowCount === 0 && !al.narrow
    anchors.horizontalCenter: parent.horizontalCenter
    y: list.y + al.t.sp(48)
    width: parent.width - al.t.sp(40)
    spacing: al.t.sp(8)
    readonly property bool waiting: !al.loaded || (al.loading && al.refs.length === 0) || (al.refs.length > 0 && al.items.length === 0 && al.loading)
    Glyph {
      app: al.app
      anchors.horizontalCenter: parent.horizontalCenter
      icon: al.filter === "mentions" ? "󰁥" : (al.filter === "threads" ? "󰍪" : (al.filter === "dms" ? "󰍥" : "󰂚"))
      size: al.t.sp(30)
      color: al.t.fgDim
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: parent.waiting ? al.app.tr("Loading…", "Carregando…")
          : (al.error ? al.error
          : (al.unreadsOnly ? al.app.tr("You're all caught up", "Você está em dia")
          : (al.filter === "mentions" ? al.app.tr("No mentions yet", "Nenhuma menção ainda")
          : (al.filter === "threads" ? al.app.tr("No thread activity", "Nenhuma atividade em conversas")
          : (al.filter === "dms" ? al.app.tr("No direct messages", "Nenhuma mensagem direta")
          : al.app.tr("No activity yet", "Nenhuma atividade ainda"))))))
      color: al.t.fgBright
      font.family: al.t.font
      font.pixelSize: al.t.fsText
      font.bold: true
    }
    Text {
      visible: !parent.waiting && !al.error
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: al.filter === "mentions" ? al.app.tr("When someone @mentions you, it shows up here.", "Quando alguém @mencionar você, aparece aqui.")
          : (al.filter === "threads" ? al.app.tr("New replies in threads you follow show up here.", "Novas respostas nas conversas que você segue aparecem aqui.")
          : (al.filter === "dms" ? al.app.tr("Messages sent to you show up here.", "Mensagens enviadas para você aparecem aqui.")
          : al.app.tr("Mentions, DMs, thread replies and reactions to your messages show up here.", "Menções, DMs, respostas em conversas e reações às suas mensagens aparecem aqui.")))
      color: al.t.fgDim
      font.family: al.t.font
      font.pixelSize: al.t.fsSmall
    }
  }

  // ---------------------------------------------------------------- actions
  function mark(it, read) {
    al.ws.markActivity(it, read)
    al.marks[it.key] = !read
    al.marksRev++
  }

  // From the card, to the tab first (which drops the card, and this list
  // with it: only what's held here is used after).
  function openItem(it) {
    var w = al.win, ws = al.ws
    if (it.unread) al.mark(it, true)
    if (al.peek) w.railTab = "activity"
    w.activityOpen = true
    w.activityKey = it.key
    if (it.threadTs) ws.open(it.conv, { ts: it.ts, threadTs: it.threadTs })
    else ws.open(it.conv, { ts: it.ts })
  }

  function rowMenu(it, x, y) {
    var w = al.ws
    var items = [
      { label: al.app.tr("Open", "Abrir"), icon: "󰁔", action: function() { al.openItem(it) } }
    ]
    if (it.threadTs) items.push({ label: al.app.tr("Open thread", "Abrir conversa"), icon: "󰍪", action: function() { al.openItem(it); w.openThread(it.conv, it.threadTs) } })
    if (it.unread) items.push({ label: al.app.tr("Mark as read", "Marcar como lida"), icon: "󰄬", action: function() { al.mark(it, true) } })
    else items.push({ label: al.app.tr("Mark as unread", "Marcar como não lida"), icon: "󰇮", action: function() { al.mark(it, false) } })
    items.push({ separator: true })
    items.push({ label: al.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() {
      al.app.copy(w.permalink(it.conv, { ts: it.ts, threadTs: it.threadTs })); al.win.toast(al.app.tr("Link copied", "Link copiado")) } })
    al.win.menu(items, x, y)
  }
}
