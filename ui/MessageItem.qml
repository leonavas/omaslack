import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Markup.js" as Markup
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// One row of a conversation: a day divider and the New line when due, then
// the message — photo and name heading a group, the body, files, reactions,
// the thread's replies — with Slack's toolbar on hover. Runs of joins and
// leaves are one quiet line. Selected with the keyboard (MessageList) it
// is outlined and takes Slack's keys for a message (`keyAction`).
Item {
  id: m
  property var app: Reg.service
  property var win
  property var ws
  property var row
  property string conv: ""
  property bool inThread: false
  property bool isParent: false
  property var ctx: null
  property var marks: null   // {color, bg}: search highlights (U+E000…U+E001) lit in the body
  property bool selected: false   // the keyboard's message in its list: outlined
  property bool keyed: false      // a message is selected and the mouse hasn't moved since: only that one lights up
  property bool longTime: false   // "Today at 7:53 AM": shown on its own (Delete message)
  readonly property var t: app.theme
  readonly property var msg: row ? row.msg : null
  readonly property bool members: row && row.kind === "members"
  readonly property bool editing: !!ws && !!ws.editing && ws.editing.conv === conv && ws.editing.ts === (msg ? msg.ts : "")
  readonly property bool mine: msg && ws ? Model.isMine(msg, ws.me.id) : false
  // Under the mouse; while the keyboard selects (`keyed`), the selected one.
  readonly property bool hovered: keyed ? selected : (hover.hovered || toolbarHover.hovered)
  readonly property bool ringed: selected && !editing
  readonly property bool mentionsMe: !!msg && !!ws && Md.mentionsMe(msg, ws.me.id) && !mine
  readonly property bool flash: !!msg && !!ws && ws.flashTs === msg.ts
  readonly property int pad: app.compact ? t.sp(2) : t.sp(4)
  readonly property int sidePad: t.sp(20)

  implicitHeight: col.implicitHeight
  // The hover toolbar rises over the message above: this row goes on top.
  z: hovered ? 5 : 0

  Column {
    id: col
    width: parent.width

    // ------------------------------------------------------------ day divider
    Item {
      visible: !!m.row && !!m.row.day && !m.isParent
      width: parent.width
      height: m.t.sp(40)
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: m.t.line }
      Rectangle {
        anchors.centerIn: parent
        height: m.t.sp(26)
        width: dayText.implicitWidth + m.t.sp(28)
        radius: height / 2
        color: m.t.pane
        border.width: 1
        border.color: m.t.lineStrong
        Text {
          id: dayText
          anchors.centerIn: parent
          text: m.row && m.row.day ? U.dayLabel(m.row.day, m.app.lang) : ""
          color: m.t.fg
          font.family: m.t.font
          font.pixelSize: m.t.fsSmall
          font.bold: true
        }
      }
    }

    // ------------------------------------------------------------ New line
    Item {
      visible: !!m.row && m.row.isNew && !m.inThread
      width: parent.width
      height: m.t.sp(18)
      Rectangle { anchors.verticalCenter: parent.verticalCenter; x: m.t.sp(4); width: parent.width - newTag.width - m.t.sp(12); height: 1; color: m.t.newLine }
      Rectangle {
        id: newTag
        anchors.right: parent.right
        anchors.rightMargin: m.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        height: m.t.sp(16)
        width: newText.implicitWidth + m.t.sp(10)
        radius: 3
        color: m.t.newLine
        Text { id: newText; anchors.centerIn: parent; text: m.app.tr("New", "Novas"); color: m.t.onColor(m.t.newLine); font.family: m.t.font; font.pixelSize: m.t.fsTiny; font.bold: true }
      }
    }

    // ------------------------------------------------------------ joins/leaves
    Item {
      visible: m.members
      width: parent.width
      height: membersText.implicitHeight + m.t.sp(10)
      Glyph {
        app: m.app
        x: m.sidePad + (m.t.avatar - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰀄"
        color: m.t.fgDim
        size: m.t.fsText
      }
      RichText {
        id: membersText
        x: m.sidePad + m.t.avatar + m.t.sp(8)
        width: parent.width - x - m.sidePad
        anchors.verticalCenter: parent.verticalCenter
        app: m.app
        size: m.t.fsText - 1
        color: m.t.fgDim
        html: m.members ? m.membersHtml() : ""
        onLink: url => { var u = url.match(/user\/([A-Z0-9]+)/); if (u) { m.ws.profileUser = u[1]; m.ws.thread = null } }
      }
    }

    // ------------------------------------------------------------ the message
    Item {
      id: box
      visible: !m.members && !!m.msg
      width: parent.width
      height: inner.implicitHeight + (m.row && m.row.header ? m.t.sp(m.app.compact ? 6 : 10) : m.pad) + m.pad

      Rectangle {
        anchors.fill: parent
        // Selected, the row rounds into its focus ring.
        anchors.margins: m.ringed ? m.t.sp(2) : 0
        anchors.leftMargin: m.ringed ? m.t.sp(4) : 0
        anchors.rightMargin: m.ringed ? m.t.sp(4) : 0
        radius: m.ringed ? Math.max(6, m.t.radiusSmall) : 0
        color: m.flash ? m.t.flash : (m.editing ? m.t.alpha(m.t.yellow, 0.06) : (m.mentionsMe ? m.t.mentionRow : (m.hovered ? m.t.hover : "transparent")))
        Behavior on color { ColorAnimation { duration: 260 } }
      }
      Rectangle { visible: m.mentionsMe; width: m.t.sp(3); height: parent.height; color: m.t.yellow }
      // Selected with the keyboard: Slack's focus ring, a soft glow around it.
      Rectangle {
        visible: m.ringed
        anchors.fill: parent
        anchors.margins: -m.t.sp(1)
        anchors.leftMargin: m.t.sp(1)
        anchors.rightMargin: m.t.sp(1)
        radius: Math.max(6, m.t.radiusSmall) + m.t.sp(3)
        color: "transparent"
        border.width: m.t.sp(3)
        border.color: m.t.alpha(m.t.accent, 0.3)
      }
      Rectangle {
        visible: m.ringed
        anchors.fill: parent
        anchors.leftMargin: m.t.sp(4)
        anchors.rightMargin: m.t.sp(4)
        anchors.topMargin: m.t.sp(2)
        anchors.bottomMargin: m.t.sp(2)
        radius: Math.max(6, m.t.radiusSmall)
        color: "transparent"
        border.width: Math.max(2, m.t.sp(2))
        border.color: m.t.accent
      }

      HoverHandler { id: hover }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (ev, button) => { var p = box.mapToItem(m.win.contentItem, ev.position.x, ev.position.y); m.openMenu(p.x, p.y) }
      }

      Column {
        id: inner
        x: m.sidePad
        y: m.row && m.row.header ? m.t.sp(m.app.compact ? 4 : 8) : m.pad
        width: parent.width - m.sidePad * 2

        // Labels above: pinned, replied to a thread, only visible to you.
        Row {
          visible: !!m.row && !!m.row.pinned
          x: m.t.avatar + m.t.sp(8)
          spacing: m.t.sp(6)
          height: visible ? implicitHeight + m.t.sp(2) : 0
          Glyph { app: m.app; icon: "󰐃"; color: m.t.yellow; size: m.t.fsSmall }
          Text { text: m.pinnedLabel(); color: m.t.fgDim; font.family: m.t.font; font.pixelSize: m.t.fsSmall }
        }
        Row {
          visible: !!m.msg && (m.msg.subtype === "thread_broadcast" || m.msg.broadcast === true) && !m.inThread
          x: m.t.avatar + m.t.sp(8)
          spacing: m.t.sp(6)
          height: visible ? implicitHeight + m.t.sp(2) : 0
          Text {
            text: m.app.tr("replied to a thread", "respondeu a uma conversa")
            color: m.t.fgDim
            font.family: m.t.font
            font.pixelSize: m.t.fsSmall
            font.italic: true
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.ws.openThread(m.conv, m.msg.threadTs) }
          }
        }
        Row {
          visible: !!m.msg && (m.msg.ephemeral || m.msg.subtype === "ephemeral")
          x: m.t.avatar + m.t.sp(8)
          spacing: m.t.sp(6)
          height: visible ? implicitHeight + m.t.sp(2) : 0
          Glyph { app: m.app; icon: "󰛐"; color: m.t.fgDim; size: m.t.fsSmall }
          Text { text: m.app.tr("Only visible to you", "Visível só para você"); color: m.t.fgDim; font.family: m.t.font; font.pixelSize: m.t.fsSmall; font.italic: true }
        }

        Item {
          width: parent.width
          height: Math.max(content.implicitHeight, m.row && m.row.header ? m.t.avatar : 0)

          // Photo, or the time of a grouped message on hover. An app's is
          // the picture its message set, else its own (Workspace.author).
          Avatar {
            visible: !!m.row && m.row.header && !m.emojiFace
            app: m.app
            ws: m.ws
            user: m.msg ? m.msg.user : ""
            url: m.who && m.who.app ? m.who.icon : ""
            name: m.who && m.who.app ? m.who.name : ""
            size: m.t.avatar
            y: m.t.sp(2)
            onClicked: m.showProfile()
          }
          // An app that posts with an emoji for a face (icon_emoji).
          EmojiIcon {
            visible: !!m.row && m.row.header && m.emojiFace
            app: m.app
            ws: m.ws
            name: m.emojiFace ? m.who.emoji : ""
            size: m.t.avatar
            y: m.t.sp(2)
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.showProfile() }
          }
          Text {
            visible: !!m.row && !m.row.header && m.hovered
            width: m.t.avatar
            horizontalAlignment: Text.AlignRight
            y: m.t.sp(3)
            text: m.msg ? U.tsTime(m.msg.ts, m.app.clock24).replace(/ (AM|PM)$/, "") : ""
            color: m.t.fgDim
            font.family: m.t.font
            font.pixelSize: m.t.fsTiny
          }

          Column {
            id: content
            x: m.t.avatar + m.t.sp(8)
            width: parent.width - x
            spacing: m.t.sp(3)

            // Name · status · APP · time
            Row {
              visible: !!m.row && m.row.header
              spacing: m.t.sp(6)
              Text {
                id: nameText
                text: m.authorName()
                color: m.t.fgBright
                font.family: m.t.font
                font.pixelSize: m.t.fsName
                font.bold: true
                anchors.baseline: timeText.baseline
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true
                  onEntered: nameText.font.underline = true
                  onExited: nameText.font.underline = false
                  onClicked: m.showProfile()
                }
              }
              EmojiIcon {
                visible: !!m.statusOf
                app: m.app
                ws: m.ws
                name: m.statusOf ? m.statusOf.emoji.replace(/:/g, "") : ""
                glyph: m.statusOf && m.statusOf.unicode ? Emoji.fromHex(m.statusOf.unicode) : ""
                size: m.t.sp(16)
                anchors.verticalCenter: nameText.verticalCenter
              }
              Rectangle {
                visible: !!m.who && m.who.app
                width: appTag.implicitWidth + m.t.sp(8)
                height: appTag.implicitHeight + m.t.sp(2)
                radius: 3
                color: m.t.alpha(m.t.fg, 0.12)
                anchors.verticalCenter: nameText.verticalCenter
                Text { id: appTag; anchors.centerIn: parent; text: "APP"; color: m.t.fgDim; font.family: m.t.font; font.pixelSize: m.t.fsTiny - 1; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.showProfile() }
              }
              Text {
                id: timeText
                text: !m.msg ? "" : (m.longTime ? U.atLabel(m.msg.ts, m.app.lang, m.app.clock24) : U.tsTime(m.msg.ts, m.app.clock24))
                color: m.t.fgDim
                font.family: m.t.font
                font.pixelSize: m.t.fsTiny + 1
                MouseArea {
                  id: timeMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: m.app.openUrl(m.ws.permalink(m.conv, m.msg))
                }
                PanelToolTip { visible: timeMa.containsMouse; text: m.msg ? U.dayLabel(U.tsDate(m.msg.ts), m.app.lang) + "  " + U.tsTime(m.msg.ts, m.app.clock24) : "" }
              }
              Glyph {
                visible: !!m.msg && !!m.msg.pending
                app: m.app
                icon: "󰔟"
                size: m.t.fsSmall
                color: m.t.fgDim
                anchors.verticalCenter: nameText.verticalCenter
              }
            }

            // Body (or the edit box).
            MessageBody {
              id: bodyView
              visible: !m.editing
              width: parent.width
              app: m.app
              win: m.win
              ws: m.ws
              conv: m.conv
              msg: m.msg
              parts: {
                if (!m.msg || !m.ctx || m.editing) return []
                var ps = Md.render(m.msg, m.ctx)
                if (m.marks) ps = ps.map(function(p) { if (!p.html) return p; var c = U.copy(p); c.html = Md.highlight(p.html, m.marks.color, m.marks.bg); return c })
                // "(edited)" follows the last line of text, as in Slack.
                var last = ps[ps.length - 1]
                if (m.msg.edited && last && last.t === "text") {
                  ps = ps.slice()
                  ps[ps.length - 1] = { t: "text", html: last.html + "&nbsp;<span style=\"color:" + m.t.html.dim + ";font-size:" + (m.t.fsTiny + 1) + "px;\">" + m.app.tr("(edited)", "(editado)") + "</span>", muted: last.muted, jumbo: last.jumbo }
                }
                return ps
              }
              opacity: m.msg && m.msg.pending ? 0.6 : 1
            }
            Text {
              visible: !!m.msg && !!m.msg.edited && !m.editing && (bodyView.parts.length === 0 || bodyView.parts[bodyView.parts.length - 1].t !== "text")
              text: m.app.tr("(edited)", "(editado)")
              color: m.t.fgDim
              font.family: m.t.font
              font.pixelSize: m.t.fsTiny + 1
            }
            Loader {
              active: m.editing
              visible: active
              width: parent.width
              sourceComponent: Composer {
                app: m.app
                win: m.win
                ws: m.ws
                conv: m.conv
                editTs: m.msg ? m.msg.ts : ""
                threadTs: m.msg ? (m.msg.threadTs || "") : ""
                initialText: m.msg ? (Markup.markup(m.msg.blocks) || m.msg.text) : ""
                onDone: m.ws.editing = null
              }
            }

            // Files.
            FileList {
              visible: !!m.msg && m.msg.files.length > 0
              width: parent.width
              app: m.app
              win: m.win
              ws: m.ws
              files: m.msg ? m.msg.files : []
              user: m.msg ? m.msg.user : ""
              conv: m.conv
              ts: m.msg ? m.msg.ts : ""
            }

            // Reactions.
            Reactions {
              visible: !!m.msg && m.msg.reactions.length > 0
              width: parent.width
              app: m.app
              win: m.win
              ws: m.ws
              conv: m.conv
              msg: m.msg
            }

            // N replies · last reply.
            ThreadSummary {
              visible: !!m.msg && m.msg.replyCount > 0 && !m.inThread
              width: parent.width
              app: m.app
              ws: m.ws
              msg: m.msg
              onOpen: m.ws.openThread(m.conv, m.msg.ts)
            }
          }
        }
      }

      // ---------------------------------------------------------- toolbar
      Rectangle {
        id: toolbar
        visible: m.hovered && !m.editing && !!m.msg && !m.msg.pending && !m.win.menusShown
        anchors.right: parent.right
        anchors.rightMargin: m.t.sp(16)
        y: -m.t.sp(16)
        z: 20
        height: m.t.sp(34)
        width: tools.implicitWidth + m.t.sp(8)
        radius: Math.max(6, m.t.radiusSmall)
        color: m.t.popup
        border.width: 1
        border.color: m.t.lineStrong
        HoverHandler { id: toolbarHover }
        Row {
          id: tools
          anchors.centerIn: parent
          spacing: m.t.sp(1)
          Repeater {
            model: ["white_check_mark", "eyes", "raised_hands"]
            delegate: Rectangle {
              required property var modelData
              width: m.t.sp(30); height: width; radius: Math.max(4, m.t.radiusSmall)
              color: qma.containsMouse ? m.t.hoverStrong : "transparent"
              EmojiIcon { anchors.centerIn: parent; app: m.app; ws: m.ws; name: parent.modelData; size: m.t.sp(18) }
              MouseArea { id: qma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.ws.react(m.conv, m.msg.ts, parent.modelData) }
            }
          }
          Rectangle { width: 1; height: m.t.sp(20); color: m.t.line; anchors.verticalCenter: parent.verticalCenter }
          IconButton { id: reactBtn; app: m.app; size: m.t.sp(30); icon: "󰇵"; tip: m.app.tr("Add reaction", "Adicionar reação"); onClicked: m.pickReaction(reactBtn) }
          IconButton { visible: !m.inThread; app: m.app; size: m.t.sp(30); icon: "󰍪"; tip: m.app.tr("Reply in thread", "Responder na conversa"); onClicked: m.ws.openThread(m.conv, m.msg.threadTs || m.msg.ts) }
          IconButton { app: m.app; size: m.t.sp(30); icon: "󰒖"; tip: m.app.tr("Forward message", "Encaminhar mensagem"); onClicked: m.win.dialog("forward", { conv: m.conv, msg: m.msg }) }
          IconButton {
            app: m.app; size: m.t.sp(30)
            icon: m.ws && m.msg && m.ws.isSaved(m.conv, m.msg.ts) ? "󰃀" : "󰃃"
            color: m.ws && m.msg && m.ws.isSaved(m.conv, m.msg.ts) ? m.t.red : m.t.fgSoft
            tip: m.ws && m.msg && m.ws.isSaved(m.conv, m.msg.ts) ? m.app.tr("Remove from Later", "Remover de Depois") : m.app.tr("Save for later", "Salvar para depois")
            onClicked: m.ws.toggleSaved(m.conv, m.msg)
          }
          IconButton { id: moreBtn; app: m.app; size: m.t.sp(30); icon: "󰇙"; tip: m.app.tr("More actions", "Mais ações"); onClicked: { var p = moreBtn.mapToItem(m.win.contentItem, 0, moreBtn.height + 4); m.openMenu(p.x - m.t.sp(200), p.y) } }
        }
      }
    }
  }

  readonly property var statusOf: m.msg && m.msg.user && m.ws ? m.ws.statusOf(m.msg.user) : null
  // Who heads it: a person, or an app by the name and picture it posts with.
  readonly property var who: m.msg && m.ws ? m.ws.author(m.msg) : null
  readonly property bool emojiFace: !!m.who && m.who.app && m.who.icon === "" && m.who.emoji !== ""

  function authorName() {
    if (!m.msg || !m.who) return ""
    return m.who.name || m.msg.user
  }

  // A person's profile, or an app's ("bot:B…" until its bot user is known).
  function showProfile() {
    if (!m.who || !m.who.profile) return
    m.ws.profileUser = m.who.profile
    m.ws.thread = null
  }

  function pinnedLabel() {
    var pins = m.ws ? m.ws.pinsOf(m.conv) : null
    var p = pins ? pins.filter(function(x) { return m.msg && x.msg.ts === m.msg.ts })[0] : null
    if (p && p.by === m.ws.me.id) return m.app.tr("Pinned by you", "Fixada por você")
    if (p && p.by) return m.app.tr("Pinned by ", "Fixada por ") + m.ws.userName(p.by)
    return m.app.tr("Pinned", "Fixada")
  }

  function membersHtml() {
    var c = m.ws.conv(m.conv)
    var segs = Model.membershipSentence(m.row.run, { lang: m.app.lang, chanName: c && !Model.isDm(c) ? c.name : "", chanPrivate: c && c.kind === "private" })
    var html = segs.map(function(s) {
      if (s.user) return "<a href=\"slackqs://user/" + s.user + "\" style=\"color:" + m.t.html.dim + ";text-decoration:none;\"><b>" + U.escapeHtml((s.at ? "@" : "") + (m.ws.userName(s.user) || s.user)) + "</b></a>"
      return U.escapeHtml(s.text)
    }).join("")
    return html + "&nbsp;&nbsp;<span style=\"font-size:" + m.t.fsTiny + "px;\">" + U.tsTime(m.row.run[0].ts, m.app.clock24) + "</span>"
  }

  function pickReaction(anchor) {
    m.win.emojiPicker(anchor, function(name) { m.ws.react(m.conv, m.msg.ts, name) }, {})
  }

  // Remind me about this: when.
  function remindItems(w, conv, msg) {
    return [
      { label: m.app.tr("In 20 minutes", "Em 20 minutos"), action: function() { w.remind(conv, msg, 20) } },
      { label: m.app.tr("In 1 hour", "Em 1 hora"), action: function() { w.remind(conv, msg, 60) } },
      { label: m.app.tr("In 3 hours", "Em 3 horas"), action: function() { w.remind(conv, msg, 180) } },
      { label: m.app.tr("Tomorrow", "Amanhã"), action: function() { w.remind(conv, msg, U.minutesUntilTomorrow9()) } },
      { label: m.app.tr("Next week", "Na próxima semana"), action: function() { w.remind(conv, msg, U.minutesUntilNextWeek9()) } }
    ]
  }

  function copyLink(w, conv, msg) { m.app.copy(w.permalink(conv, msg)); m.win.toast(m.app.tr("Link copied", "Link copiado")) }

  // Slack's keys on a selected message (MessageList): E edit and Delete /
  // Backspace delete (yours only), R react, T or Enter the thread, A save,
  // P pin, S or F forward, U mark unread, M remind, L copy link. True when
  // the key is one of them.
  function keyAction(key) {
    if (!m.msg || m.members) return false
    var keys = [Qt.Key_E, Qt.Key_Delete, Qt.Key_Backspace, Qt.Key_R, Qt.Key_T, Qt.Key_Return, Qt.Key_Enter, Qt.Key_A, Qt.Key_P, Qt.Key_S, Qt.Key_F, Qt.Key_U, Qt.Key_M, Qt.Key_L]
    if (keys.indexOf(key) < 0) return false
    if (m.msg.pending || m.editing) return true
    var w = m.ws, msg = m.msg, conv = m.conv
    switch (key) {
    case Qt.Key_E: if (m.mine) w.editing = { conv: conv, ts: msg.ts }; break
    case Qt.Key_Delete:
    case Qt.Key_Backspace: if (m.mine) m.win.confirmDelete(conv, msg); break
    case Qt.Key_R: m.pickReaction(toolbar.visible ? reactBtn : box); break
    case Qt.Key_T:
    case Qt.Key_Return:
    case Qt.Key_Enter: if (!m.inThread) w.openThread(conv, msg.threadTs || msg.ts); break
    case Qt.Key_A: w.toggleSaved(conv, msg); break
    case Qt.Key_P: w.togglePin(conv, msg); break
    case Qt.Key_S:
    case Qt.Key_F: m.win.dialog("forward", { conv: conv, msg: msg }); break
    case Qt.Key_U: if (!m.inThread || msg.threadTs === msg.ts) w.markUnread(conv, msg.ts); break
    case Qt.Key_M: {
      // The reminder's times, where the ⋮ menu opens.
      var p = toolbar.visible ? moreBtn.mapToItem(m.win.contentItem, 0, moreBtn.height + 4) : box.mapToItem(m.win.contentItem, box.width - m.t.sp(40), m.t.sp(8))
      m.win.menu([{ title: m.app.tr("Remind me about this", "Lembrar-me disto") }].concat(m.remindItems(w, conv, msg)), p.x - m.t.sp(200), p.y)
      break
    }
    case Qt.Key_L: m.copyLink(w, conv, msg); break
    }
    return true
  }

  function openMenu(x, y) {
    if (!m.msg || m.msg.pending) return
    var w = m.ws, msg = m.msg, conv = m.conv
    var saved = w.isSaved(conv, msg.ts)
    var pinned = msg.pinnedTo && msg.pinnedTo.indexOf(conv) >= 0
    var items = [{ reactions: ["white_check_mark", "eyes", "raised_hands", "+1", "heart"], action: function(n) { w.react(conv, msg.ts, n) } }]
    items.push({ label: m.app.tr("Add reaction…", "Adicionar reação…"), icon: "󰇵", hint: "R", action: function() { m.pickReaction(toolbar.visible ? reactBtn : box) } })
    if (!m.inThread) items.push({ label: m.app.tr("Reply in thread", "Responder na conversa"), icon: "󰍪", hint: "T", action: function() { w.openThread(conv, msg.threadTs || msg.ts) } })
    items.push({ label: m.app.tr("Forward message…", "Encaminhar mensagem…"), icon: "󰒖", hint: "F", action: function() { m.win.dialog("forward", { conv: conv, msg: msg }) } })
    items.push({ label: saved ? m.app.tr("Remove from Later", "Remover de Depois") : m.app.tr("Save for later", "Salvar para depois"), icon: saved ? "󰃀" : "󰃃", hint: "A", action: function() { w.toggleSaved(conv, msg) } })
    if (m.mine) {
      items.push({ separator: true })
      items.push({ label: m.app.tr("Edit message", "Editar mensagem"), icon: "󰏫", hint: "E", action: function() { w.editing = { conv: conv, ts: msg.ts } } })
    }
    items.push({ separator: true })
    if (!m.inThread || msg.threadTs === msg.ts) items.push({ label: m.app.tr("Mark unread", "Marcar como não lida"), icon: "󰇰", hint: "U", action: function() { w.markUnread(conv, msg.ts) } })
    items.push({ label: m.app.tr("Remind me about this", "Lembrar-me disto"), icon: "󰀠", sub: m.remindItems(w, conv, msg) })
    if (msg.threadTs || msg.replyCount > 0) {
      var parent = msg.threadTs && msg.threadTs !== msg.ts ? (w.findAny(conv, msg.threadTs) || msg) : msg
      var on = !!parent.subscribed
      items.push({ label: on ? m.app.tr("Turn off notifications for replies", "Desativar notificações de respostas") : m.app.tr("Get notified about new replies", "Ativar notificações de respostas"),
                   icon: on ? "󰂛" : "󰂚", action: function() { w.setFollow(conv, parent, !on) } })
    }
    items.push({ separator: true })
    items.push({ label: pinned ? m.app.tr("Unpin from conversation", "Desafixar da conversa") : m.app.tr("Pin to conversation", "Fixar na conversa"), icon: "󰐃", hint: "P", action: function() { w.togglePin(conv, msg) } })
    items.push({ label: m.app.tr("Copy link", "Copiar link"), icon: "󰌷", hint: "L", action: function() { m.copyLink(w, conv, msg) } })
    items.push({ label: m.app.tr("Copy message", "Copiar mensagem"), icon: "󰆏", action: function() { m.app.copy(Md.flat(msg, m.ctx, 0)); m.win.toast(m.app.tr("Message copied", "Mensagem copiada")) } })
    if (m.mine) {
      items.push({ separator: true })
      items.push({ label: m.app.tr("Delete message…", "Excluir mensagem…"), icon: "󰧧", danger: true, hint: "Del", action: function() { m.win.confirmDelete(conv, msg) } })
    }
    m.win.menu(items, x, y)
  }
}
