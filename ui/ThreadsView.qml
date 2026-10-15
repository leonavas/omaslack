import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Registry.js" as Reg

// Slack's Threads view: one card per thread you follow — the conversation
// and who is in it, the parent message, "Show N more replies", the latest
// replies with a red New line before the unread ones, and a box to reply.
// Unread threads come first; a card read on screen is marked read in Slack.
Rectangle {
  id: tv
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  readonly property var view: { if (!ws) return null; ws.threadsRev; return ws.threadsView }
  color: t.pane

  // How each card looked when it first showed up here: the New line stays
  // where it was (and the card keeps its place) after it is marked read.
  property var seen: ({})
  property int seenRev: 0
  property var expanded: ({})
  property int expandedRev: 0

  function snapshot() {
    if (!tv.view) return
    var changed = false
    tv.view.list.forEach(function(c) {
      var s = tv.seen[c.key]
      if (!s || s.latest !== c.latest) { tv.seen[c.key] = { lastRead: c.lastRead, unread: c.unread, latest: c.latest }; changed = true }
    })
    if (changed) tv.seenRev++
  }

  Component.onCompleted: { tv.snapshot(); if (tv.ws) tv.ws.loadThreads() }
  onViewChanged: tv.snapshot()

  readonly property var cards: {
    tv.seenRev
    if (tv.ws) tv.ws.threadsRev   // marked read in place
    var list = (tv.view ? tv.view.list : []).slice()
    // Unread when first seen stays on top (Slack's list may have moved it).
    var first = function(c) { var s = tv.seen[c.key]; return s ? s.unread : c.unread }
    list = list.map(function(c, i) { return { c: c, i: i } }).sort(function(a, b) {
      var x = first(a.c), y = first(b.c)
      return x !== y ? (x ? -1 : 1) : a.i - b.i
    }).map(function(e) { return e.c })
    var out = [], sawUnread = false, divided = false
    list.forEach(function(c) {
      var s = tv.seen[c.key] || { lastRead: c.lastRead, unread: c.unread }
      var divider = false
      if (s.unread) sawUnread = true
      else if (sawUnread && !divided) { divider = true; divided = true }
      out.push({ key: c.key, card: c, lastRead: s.lastRead, wasUnread: s.unread, divider: divider, unread: c.unread })
    })
    return out
  }

  // A reply sent from a card's box: its thread is read again so the reply
  // shows in the card.
  Connections {
    target: tv.ws
    function onSentLogChanged() {
      var e = tv.ws.sentLog[0]
      if (!e || !e.threadTs || !tv.view) return
      var key = e.conv + "/" + e.threadTs
      if (tv.view.list.some(function(c) { return c.key === key })) tv.ws.fetchReplies(e.conv, e.threadTs)
    }
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: tv.t.sp(52)
    Row {
      x: tv.t.sp(20)
      anchors.verticalCenter: parent.verticalCenter
      spacing: tv.t.sp(10)
      Glyph { app: tv.app; icon: "󰍪"; size: tv.t.fsHeader; color: tv.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
      Text {
        text: tv.app.tr("Threads", "Conversas")
        color: tv.t.fgBright
        font.family: tv.t.font
        font.pixelSize: tv.t.fsHeader
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: tv.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: tv.t.sp(6)
      IconButton {
        app: tv.app
        icon: "󰑓"
        tip: tv.app.tr("Refresh", "Atualizar")
        onClicked: tv.ws.loadThreads()
      }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: tv.t.line }
  }

  // ---------------------------------------------------------------- cards
  ListView {
    id: list
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    topMargin: tv.t.sp(20)
    bottomMargin: tv.t.sp(28)
    spacing: tv.t.sp(20)
    cacheBuffer: 4000
    reuseItems: false
    boundsBehavior: Flickable.StopAtBounds
    model: ScriptModel { values: tv.cards; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: tv.app }

    delegate: Item {
      id: cardItem
      required property var modelData
      readonly property var card: modelData.card
      readonly property string conv: card.conv
      readonly property string rootTs: card.root.ts
      readonly property var c: tv.ws.conv(conv)
      readonly property var live: tv.ws.repliesOf(conv, rootTs)
      readonly property bool isExpanded: { tv.expandedRev; return !!tv.expanded[modelData.key] }
      readonly property bool liveReady: !!live && live.msgs.length > 0 && live.msgs[0].ts === rootTs
      readonly property var rootMsg: {
        if (liveReady) return live.msgs[0]
        tv.ws.historyRev
        return tv.ws.findAny(conv, rootTs) || card.root
      }
      readonly property int total: {
        var a = rootMsg ? (rootMsg._replyCount || rootMsg.replyCount || 0) : 0
        return Math.max(a, card.root.replyCount || 0, replies.length)
      }
      // The replies drawn: the latest few (as Slack sent them), or all of
      // them once expanded; once read again from Slack, the live copies.
      readonly property var replies: {
        var snap = card.replies
        if (!liveReady) return snap
        var all = live.msgs.slice(1)
        if (isExpanded || !snap.length) return all
        var from = snap[0].ts
        return all.filter(function(m) { return U.cmpTs(m.ts, from) >= 0 })
      }
      readonly property int hidden: Math.max(0, total - replies.length)
      readonly property var rows: {
        var out = [], prev = null, newDone = false
        for (var i = 0; i < replies.length; i++) {
          var m = replies[i]
          var isNew = modelData.wasUnread && !newDone && modelData.lastRead !== "" && U.cmpTs(m.ts, modelData.lastRead) > 0 && m.user !== tv.ws.me.id
          if (isNew) { newDone = true; out.push({ key: "new", kind: "new" }) }
          var header = !prev || isNew || Model.authorKey(prev) !== Model.authorKey(m) || U.tsNum(m.ts) - U.tsNum(prev.ts) > 600
          out.push({ key: m.ts, kind: "msg", msg: m, header: header, day: null, isNew: false, pinned: false })
          prev = m
        }
        return out
      }

      width: list.width
      height: col.implicitHeight

      // Marked read once its new replies were on screen for a moment.
      readonly property bool onScreen: y + height > list.contentY && y < list.contentY + list.height
      Timer {
        interval: 1200
        running: cardItem.onScreen && cardItem.modelData.unread && tv.ws.focused && tv.visible
        onTriggered: tv.ws.markThread(cardItem.conv, cardItem.rootTs, cardItem.card.latest || cardItem.rootTs)
      }

      Column {
        id: col
        width: parent.width

        // "You're up to date" between the unread cards and the rest.
        Item {
          visible: cardItem.modelData.divider
          width: parent.width
          height: visible ? tv.t.sp(44) : 0
          Rectangle { x: tv.t.sp(20); width: parent.width - tv.t.sp(40); height: 1; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -tv.t.sp(10); color: tv.t.line }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -tv.t.sp(10)
            width: upText.implicitWidth + tv.t.sp(24)
            height: tv.t.sp(24)
            radius: height / 2
            color: tv.t.pane
            border.width: 1
            border.color: tv.t.lineStrong
            Text {
              id: upText
              anchors.centerIn: parent
              text: "󰄬  " + tv.app.tr("You're up to date", "Você está em dia")
              color: tv.t.fgDim
              font.family: tv.t.font
              font.pixelSize: tv.t.fsSmall
              font.bold: true
            }
          }
        }

        Rectangle {
          id: frame
          x: tv.t.sp(20)
          width: parent.width - tv.t.sp(40)
          height: inner.implicitHeight
          radius: Math.max(8, tv.t.radiusCard)
          color: tv.t.pane
          border.width: 1
          border.color: cardItem.modelData.unread ? tv.t.alpha(tv.t.fg, 0.26) : tv.t.lineStrong

          Column {
            id: inner
            width: parent.width

            // -------------------------------------------------- title
            Item {
              width: parent.width
              height: titleCol.implicitHeight + tv.t.sp(24)
              Column {
                id: titleCol
                x: tv.t.sp(18)
                y: tv.t.sp(13)
                width: parent.width - x - openBtn.width - tv.t.sp(24)
                spacing: tv.t.sp(2)
                Row {
                  spacing: tv.t.sp(6)
                  width: parent.width
                  Glyph {
                    visible: !!cardItem.c && cardItem.c.kind !== "im"
                    app: tv.app
                    icon: !cardItem.c ? "#" : (cardItem.c.kind === "private" ? "󰌾" : (cardItem.c.kind === "mpim" ? "󰀏" : "#"))
                    size: tv.t.fsTitle - 1
                    font.bold: true
                    color: titleText.color
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Avatar {
                    visible: !!cardItem.c && cardItem.c.kind === "im"
                    app: tv.app
                    ws: tv.ws
                    user: cardItem.c ? (cardItem.c.user || "") : ""
                    size: tv.t.sp(18)
                    showPresence: true
                    ring: tv.t.pane
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    id: titleText
                    text: tv.ws.convLabel(cardItem.conv) || cardItem.conv
                    color: cardItem.modelData.unread ? tv.t.fgBright : tv.t.fg
                    font.family: tv.t.font
                    font.pixelSize: tv.t.fsTitle - 1
                    font.bold: true
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, titleCol.width - tv.t.sp(30))
                    anchors.verticalCenter: parent.verticalCenter
                    font.underline: titleMa.containsMouse
                    MouseArea {
                      id: titleMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: tv.ws.open(cardItem.conv, { ts: cardItem.rootTs })
                    }
                  }
                }
                Text {
                  width: parent.width
                  text: tv.peopleLine(cardItem.rootMsg || cardItem.card.root, cardItem.card.people)
                  color: tv.t.fgDim
                  font.family: tv.t.font
                  font.pixelSize: tv.t.fsSmall
                  elide: Text.ElideRight
                }
              }
              IconButton {
                id: openBtn
                app: tv.app
                anchors.right: parent.right
                anchors.rightMargin: tv.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                icon: "󰍪"
                tip: tv.app.tr("Open in thread", "Abrir na conversa")
                onClicked: tv.ws.openThread(cardItem.conv, cardItem.rootTs)
              }
            }

            // -------------------------------------------------- the parent
            MessageItem {
              x: 1
              width: parent.width - 2
              app: tv.app
              win: tv.win
              ws: tv.ws
              conv: cardItem.conv
              inThread: true
              isParent: true
              ctx: tv.ctx
              row: ({ key: "root", kind: "msg", msg: cardItem.rootMsg, header: true, day: null, isNew: false, pinned: false })
            }

            // -------------------------------------------------- more replies
            Item {
              visible: cardItem.hidden > 0 && !cardItem.isExpanded
              width: parent.width
              height: visible ? tv.t.sp(34) : 0
              Rectangle {
                x: tv.t.sp(20) + tv.t.avatar + tv.t.sp(8) - tv.t.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                height: tv.t.sp(28)
                width: moreText.implicitWidth + tv.t.sp(16)
                radius: Math.max(6, tv.t.radiusSmall)
                color: moreMa.containsMouse ? tv.t.hover : "transparent"
                Text {
                  id: moreText
                  anchors.centerIn: parent
                  text: cardItem.hidden === 1 ? tv.app.tr("Show 1 more reply", "Mostrar mais 1 resposta")
                        : tv.app.tr("Show " + cardItem.hidden + " more replies", "Mostrar mais " + cardItem.hidden + " respostas")
                  color: tv.t.link
                  font.family: tv.t.font
                  font.pixelSize: tv.t.fsSmall + 1
                  font.bold: true
                }
                MouseArea {
                  id: moreMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    tv.expanded[cardItem.modelData.key] = true
                    tv.expandedRev++
                    tv.ws.fetchReplies(cardItem.conv, cardItem.rootTs)
                  }
                }
              }
            }
            Text {
              visible: cardItem.isExpanded && !!cardItem.live && cardItem.live.loading && !cardItem.liveReady
              x: tv.t.sp(20) + tv.t.avatar + tv.t.sp(8)
              bottomPadding: tv.t.sp(10)
              text: tv.app.tr("Loading…", "Carregando…")
              color: tv.t.fgDim
              font.family: tv.t.font
              font.pixelSize: tv.t.fsSmall
            }

            // -------------------------------------------------- replies
            Repeater {
              model: ScriptModel { values: cardItem.rows; objectProp: "key" }
              delegate: Loader {
                required property var modelData
                x: 1
                width: inner.width - 2
                sourceComponent: modelData.kind === "new" ? newLineC : replyC
                property var rowData: modelData
              }
            }

            // -------------------------------------------------- reply box
            Item {
              width: parent.width
              height: box.visible ? box.height + tv.t.sp(30) : tv.t.sp(14)
              Composer {
                id: box
                x: tv.t.sp(18)
                y: tv.t.sp(10)
                width: parent.width - tv.t.sp(36)
                app: tv.app
                win: tv.win
                ws: tv.ws
                conv: cardItem.conv
                threadTs: cardItem.rootTs
                showFormatting: false
                visible: !!cardItem.c && !cardItem.c.archived && cardItem.c.member !== false
              }
            }
          }
        }
      }

      Component {
        id: replyC
        MessageItem {
          app: tv.app
          win: tv.win
          ws: tv.ws
          conv: cardItem.conv
          inThread: true
          ctx: tv.ctx
          row: parent ? parent.rowData : null
        }
      }
    }
  }

  // The red New line between the read replies and the unread ones.
  Component {
    id: newLineC
    Item {
      height: tv.t.sp(20)
      Rectangle { anchors.verticalCenter: parent.verticalCenter; x: tv.t.sp(12); width: parent.width - newTag.width - tv.t.sp(24); height: 1; color: tv.t.newLine }
      Rectangle {
        id: newTag
        anchors.right: parent.right
        anchors.rightMargin: tv.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        height: tv.t.sp(16)
        width: newText.implicitWidth + tv.t.sp(10)
        radius: 3
        color: tv.t.newLine
        Text { id: newText; anchors.centerIn: parent; text: tv.app.tr("New", "Novas"); color: tv.t.onColor(tv.t.newLine); font.family: tv.t.font; font.pixelSize: tv.t.fsTiny; font.bold: true }
      }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: !!tv.view && tv.cards.length === 0
    anchors.centerIn: parent
    anchors.verticalCenterOffset: tv.t.sp(10)
    width: Math.min(parent.width - tv.t.sp(60), tv.t.sp(420))
    spacing: tv.t.sp(10)
    Rectangle {
      visible: tv.view && tv.view.loaded && !tv.view.loading
      anchors.horizontalCenter: parent.horizontalCenter
      width: tv.t.sp(72); height: width
      radius: Math.max(12, tv.t.radiusCard + 6)
      color: tv.t.alpha(tv.t.accent, 0.16)
      Glyph { app: tv.app; anchors.centerIn: parent; icon: "󰍪"; size: tv.t.sp(34); color: tv.t.accent }
    }
    Item { width: 1; height: tv.t.sp(4) }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: tv.view && tv.view.loaded && !tv.view.loading ? tv.app.tr("Tend to your threads", "Cuide das suas conversas") : tv.app.tr("Loading threads…", "Carregando conversas…")
      color: tv.view && tv.view.loaded && !tv.view.loading ? tv.t.fgBright : tv.t.fgDim
      font.family: tv.t.font
      font.pixelSize: tv.view && tv.view.loaded && !tv.view.loading ? tv.t.fsHeader : tv.t.fsText
      font.bold: tv.view && tv.view.loaded && !tv.view.loading
    }
    Text {
      visible: tv.view && tv.view.loaded && !tv.view.loading
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: tv.app.tr("No threads yet. Threads you start, reply to or follow show up here, so you can keep up with them in one place.",
                      "Nenhuma conversa ainda. As conversas que você começa, responde ou segue aparecem aqui, para acompanhar tudo num só lugar.")
      color: tv.t.fgDim
      font.family: tv.t.font
      font.pixelSize: tv.t.fsText
      lineHeight: 1.15
    }
  }

  // "Ana, Bruno and you": the parent's author and the repliers (unnamed
  // ones counted).
  function peopleLine(root, count) {
    var me = tv.ws.me.id
    var ids = U.uniq([root.user].concat(root.replyUsers || []).filter(function(x) { return x }))
    var withMe = ids.indexOf(me) >= 0
    // An app among the repliers comes as its bot id: bots.info names it.
    var others = ids.filter(function(id) { return id !== me }).map(function(id) {
      return (/^B[A-Z0-9]+$/.test(id) ? (tv.ws.bot(id) || {}).name : tv.ws.userName(id)) || "?"
    })
    var extra = Math.max(0, (count || root.replyUsersCount || 0) - (root.replyUsers || []).length)
    var tr = tv.app.tr
    if (!others.length) {
      if (!extra) return withMe ? tr("You", "Você") : ""
      return withMe ? tr("You and ", "Você e mais ") + extra + (tr(extra === 1 ? " other" : " others", "")) : extra + tr(" people", " pessoas")
    }
    if (!extra) {
      if (withMe && others.length === 1) return others[0] + tr(" and you", " e você")
      if (withMe && others.length === 2) return others[0] + ", " + others[1] + tr(", and you", " e você")
      if (!withMe && others.length <= 3) return Model.people(others, 0, tv.app.lang)
    }
    var shown = others.slice(0, 2)
    var rest = others.length - shown.length + extra + (withMe ? 1 : 0)
    return shown.join(", ") + tr((shown.length > 1 ? ", and " : " and ") + rest + (rest === 1 ? " other" : " others"), " e mais " + rest)
  }
}
