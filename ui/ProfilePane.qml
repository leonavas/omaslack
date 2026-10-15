import QtQuick
import QtQuick.Controls
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// Someone's profile beside the conversation: the big photo, name, title,
// presence, status and local time, Message / VIP / more, and how to reach
// them. Your own adds Edit profile and Set a status. An app's is Slack's
// "App" panel: its icon, name, description, Open app.
Rectangle {
  id: pp
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property string uid: ws ? ws.profileUser : ""
  // "bot:B…": an app opened from its message before its bot user is known
  // (and for good, for those without one: webhooks).
  readonly property bool botKey: uid.indexOf("bot:") === 0
  readonly property string shownId: botKey ? uid.slice(4) : uid
  // The app behind it (Workspace.appProfile): {name, desc, icon, big, photo, bot, app, user}.
  property var appInfo: null
  // A fresh copy on every change: the store also edits users in place.
  readonly property var u: {
    if (!ws || !uid) return null
    ws.usersRev
    // An app without a bot user: what its profile says, shaped as a user.
    if (botKey) return appInfo ? { id: uid, name: appInfo.name || "bot", avatar: appInfo.icon, avatar192: appInfo.big,
                                   avatar512: appInfo.big, photo: appInfo.photo, bot: true } : null
    var x = ws.user(uid)
    return x ? Object.assign({}, x) : null
  }
  readonly property bool self: !!ws && uid !== "" && uid === ws.me.id
  readonly property bool bot: !!u && !!u.bot
  readonly property bool isApp: botKey || (bot && uid !== "USLACKBOT")
  // As Slack shows an app: the name and pictures of its app profile.
  readonly property string shownName: isApp && appInfo && appInfo.name ? appInfo.name : (u ? u.name : "")
  readonly property string bigPhoto: isApp && appInfo && appInfo.big ? appInfo.big : (u ? (u.avatar512 || u.photo || u.avatar192 || "") : "")
  readonly property string fullPhoto: isApp && appInfo && appInfo.photo ? appInfo.photo : (u ? (u.photo || u.avatar512 || u.avatar192 || u.avatar || "") : "")
  readonly property bool gone: !!u && !!u.deleted
  readonly property var status: ws && uid ? ws.statusOf(uid) : null
  readonly property bool vip: { if (!ws) return false; ws.usersRev; return !!ws.vips[uid] }
  property bool loading: false
  property real now: Date.now()
  color: t.pane

  onUidChanged: refresh()
  Component.onCompleted: refresh()

  function refresh() {
    if (!pp.ws || !pp.uid) return
    var asked = pp.uid
    // Kept when the app's panel moves on to its bot user.
    if (!(pp.appInfo && pp.appInfo.user === asked)) pp.appInfo = null
    pp.loading = !pp.u
    if (pp.botKey) {
      pp.ws.appProfile({ bot: asked.slice(4) }, function(info) {
        try {
          if (!pp || pp.uid !== asked) return
          pp.loading = false
          // Slack told nothing about it: no panel.
          if (!info.name && !info.icon && !info.user) {
            var w = pp.ws
            w.say(pp.app.tr("Couldn't load this app's profile.", "Não foi possível carregar o perfil deste app."))
            w.profileUser = ""
            return
          }
          pp.appInfo = info
          // With a bot user the panel is theirs: its DM and VIP work.
          if (info.user) pp.ws.profileUser = info.user
        } catch (e) {}
      })
      return
    }
    pp.ws.profile(asked, function(x) {
      try {
        if (!pp || pp.uid !== asked) return
        pp.loading = false
        // A bot user: its app's name, description and icon.
        if (x && x.bot && asked !== "USLACKBOT" && (x.botId || x.appId) && !pp.appInfo)
          pp.ws.appProfile({ bot: x.botId || "", app: x.appId || "" }, function(info) {
            try { if (pp && pp.uid === asked) pp.appInfo = info } catch (e2) {}
          })
      } catch (e) {}
    })
  }

  Timer { interval: 30000; repeat: true; running: pp.visible; onTriggered: pp.now = Date.now() }

  // Their clock, from the offset Slack gives (seconds east of UTC).
  readonly property string localTime: {
    if (!u || typeof u.tzOffset !== "number") return ""
    var here = new Date(pp.now)
    var there = new Date(pp.now + (u.tzOffset + here.getTimezoneOffset() * 60) * 1000)
    return U.time(there, app.clock24)
  }
  readonly property string tzDiff: {
    if (!u || typeof u.tzOffset !== "number" || self) return ""
    var mine = -new Date(pp.now).getTimezoneOffset() * 60
    var h = Math.round((u.tzOffset - mine) / 360) / 10
    if (h === 0) return ""
    var n = Math.abs(h)
    var unit = n === 1 ? app.tr(" hour", " hora") : app.tr(" hours", " horas")
    return h > 0 ? n + unit + app.tr(" ahead", " à frente") : n + unit + app.tr(" behind", " atrás")
  }

  readonly property string profileUrl: (ws && ws.team.domain ? "https://" + ws.team.domain + ".slack.com/team/" : "https://app.slack.com/team/") + uid

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: pp.t.sp(52)
    Text {
      x: pp.t.sp(18)
      anchors.verticalCenter: parent.verticalCenter
      text: pp.isApp ? "App" : pp.app.tr("Profile", "Perfil")
      color: pp.t.fgBright
      font.family: pp.t.font
      font.pixelSize: pp.t.fsTitle + 1
      font.bold: true
    }
    IconButton {
      anchors.right: parent.right
      anchors.rightMargin: pp.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      app: pp.app
      icon: "󰅖"
      tip: pp.app.tr("Close", "Fechar") + "  Ctrl+."
      onClicked: pp.ws.profileUser = ""
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pp.t.line }
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight + pp.t.sp(40)
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ThinScroll { app: pp.app }

    Column {
      id: body
      x: pp.t.sp(24)
      y: pp.t.sp(24)
      width: flick.width - pp.t.sp(48)
      spacing: pp.t.sp(6)

      // ------------------------------------------------------------ photo
      Item {
        width: parent.width
        height: photo.height + pp.t.sp(14)
        Avatar {
          id: photo
          anchors.horizontalCenter: parent.horizontalCenter
          app: pp.app
          ws: pp.ws
          user: pp.botKey ? "" : pp.uid
          url: pp.bigPhoto
          name: pp.botKey ? pp.shownName : ""
          size: Math.max(pp.t.sp(96), Math.min(parent.width, pp.t.sp(280), Math.round(pp.height * 0.42)))
          round: 0.05
          onClicked: {
            if (!pp.u) return
            var full = pp.fullPhoto
            if (!full) return
            pp.win.viewImage({ name: pp.shownName, full: full, thumb: pp.bigPhoto || full, w: 0, h: 0,
                               permalink: pp.botKey ? full : pp.profileUrl, external: true })
          }
        }
      }

      Rectangle {
        visible: pp.gone
        width: parent.width
        height: goneText.implicitHeight + pp.t.sp(12)
        radius: Math.max(6, pp.t.radiusSmall)
        color: pp.t.alpha(pp.t.fg, 0.08)
        Text {
          id: goneText
          anchors.centerIn: parent
          text: "󰀒  " + pp.app.tr("Deactivated account", "Conta desativada")
          color: pp.t.fgDim
          font.family: pp.t.font
          font.pixelSize: pp.t.fsSmall + 1
          font.bold: true
        }
      }

      // ------------------------------------------------------------ name
      Row {
        id: nameRow
        width: parent.width
        spacing: pp.t.sp(8)
        readonly property int extras: (statusIcon.visible ? statusIcon.width + spacing : 0) + (appTagBox.visible ? appTagBox.width + spacing : 0)
        Text {
          id: nameText
          width: Math.min(implicitWidth, nameRow.width - nameRow.extras)
          text: pp.u ? pp.shownName : (pp.loading ? pp.app.tr("Loading…", "Carregando…") : "")
          color: pp.t.fgBright
          font.family: pp.t.font
          font.pixelSize: pp.t.fsHuge
          font.bold: true
          wrapMode: Text.Wrap
        }
        EmojiIcon {
          id: statusIcon
          visible: !!pp.status && (pp.status.emoji !== "" || pp.status.unicode !== "")
          app: pp.app
          ws: pp.ws
          name: pp.status ? pp.status.emoji.replace(/:/g, "") : ""
          glyph: pp.status && pp.status.unicode ? Emoji.fromHex(pp.status.unicode) : ""
          size: pp.t.sp(22)
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          id: appTagBox
          visible: pp.bot
          width: appTag.implicitWidth + pp.t.sp(10)
          height: appTag.implicitHeight + pp.t.sp(4)
          anchors.verticalCenter: parent.verticalCenter
          radius: 3
          color: pp.t.alpha(pp.t.fg, 0.12)
          Text { id: appTag; anchors.centerIn: parent; text: "APP"; color: pp.t.fgDim; font.family: pp.t.font; font.pixelSize: pp.t.fsTiny; font.bold: true }
        }
      }

      Text {
        visible: !!pp.u && !!pp.u.real && pp.u.real !== pp.u.name && !pp.isApp
        width: parent.width
        text: pp.u ? (pp.u.real || "") : ""
        color: pp.t.fgDim
        font.family: pp.t.font
        font.pixelSize: pp.t.fsText
        wrapMode: Text.Wrap
      }

      Text {
        visible: !!pp.u && !!pp.u.title
        width: parent.width
        text: pp.u ? (pp.u.title || "") : ""
        color: pp.t.fg
        font.family: pp.t.font
        font.pixelSize: pp.t.fsText + 1
        wrapMode: Text.Wrap
      }

      // An app: what it says it does.
      Text {
        visible: pp.isApp && !!pp.appInfo && !!pp.appInfo.desc
        width: parent.width
        text: pp.appInfo ? (pp.appInfo.desc || "") : ""
        color: pp.t.fg
        font.family: pp.t.font
        font.pixelSize: pp.t.fsText
        wrapMode: Text.Wrap
      }

      Item { width: 1; height: pp.t.sp(4) }

      // ------------------------------------------------------------ presence
      Row {
        visible: !!pp.u && !pp.bot && !pp.gone
        spacing: pp.t.sp(8)
        height: pp.t.sp(22)
        PresenceDot {
          app: pp.app
          anchors.verticalCenter: parent.verticalCenter
          size: pp.t.sp(11)
          ring: "transparent"
          active: pp.ws ? pp.ws.isActive(pp.uid) : false
          paused: pp.ws ? pp.ws.isPaused(pp.uid) : false
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: pp.ws && pp.ws.isActive(pp.uid) ? pp.app.tr("Active", "Ativo") : pp.app.tr("Away", "Ausente")
          color: pp.t.fg
          font.family: pp.t.font
          font.pixelSize: pp.t.fsText
        }
      }

      // Notifications paused.
      Row {
        visible: !!pp.u && !pp.bot && !pp.gone && !!pp.ws && pp.ws.isPaused(pp.uid)
        spacing: pp.t.sp(8)
        height: pp.t.sp(22)
        Glyph { app: pp.app; icon: "󰂛"; size: pp.t.fsText; color: pp.t.fgDim; width: pp.t.sp(11); anchors.verticalCenter: parent.verticalCenter }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            var s = pp.app.tr("Notifications paused", "Notificações pausadas")
            if (pp.self && pp.ws && pp.ws.dnd && pp.ws.dnd.until) s += " " + U.untilLabel(pp.ws.dnd.until, pp.app.lang, pp.app.clock24)
            return s
          }
          color: pp.t.fgDim
          font.family: pp.t.font
          font.pixelSize: pp.t.fsText
        }
      }

      // Status.
      Row {
        visible: !!pp.status
        spacing: pp.t.sp(8)
        width: parent.width
        EmojiIcon {
          app: pp.app
          ws: pp.ws
          name: pp.status ? pp.status.emoji.replace(/:/g, "") : ""
          glyph: pp.status && pp.status.unicode ? Emoji.fromHex(pp.status.unicode) : ""
          size: pp.t.sp(18)
          visible: !!pp.status && (pp.status.emoji !== "" || pp.status.unicode !== "")
        }
        Text {
          width: parent.width - pp.t.sp(28)
          text: {
            if (!pp.status) return ""
            var s = pp.status.text
            if (pp.status.exp) s += (s ? "  ·  " : "") + "<font color=\"" + pp.t.hex(pp.t.fgDim) + "\">" + U.untilLabel(pp.status.exp, pp.app.lang, pp.app.clock24) + "</font>"
            return s
          }
          textFormat: Text.StyledText
          color: pp.t.fg
          font.family: pp.t.font
          font.pixelSize: pp.t.fsText
          wrapMode: Text.Wrap
        }
      }

      // Local time.
      Row {
        visible: pp.localTime !== "" && !pp.bot
        spacing: pp.t.sp(8)
        height: pp.t.sp(22)
        Glyph { app: pp.app; icon: "󰥔"; size: pp.t.fsText; color: pp.t.fgDim; width: pp.t.sp(11); anchors.verticalCenter: parent.verticalCenter }
        Text {
          id: clockText
          anchors.verticalCenter: parent.verticalCenter
          text: pp.localTime + pp.app.tr(" local time", " hora local") + (pp.tzDiff ? "  ·  " + pp.tzDiff : "")
          color: pp.t.fg
          font.family: pp.t.font
          font.pixelSize: pp.t.fsText
          MouseArea { id: clockMa; anchors.fill: parent; hoverEnabled: true }
          PanelToolTip { visible: clockMa.containsMouse && !!pp.u && !!pp.u.tzLabel; text: pp.u ? (pp.u.tzLabel || "") : "" }
        }
      }

      Item { width: 1; height: pp.t.sp(10) }

      // ------------------------------------------------------------ buttons
      Flow {
        width: parent.width
        spacing: pp.t.sp(8)
        visible: !!pp.u

        // An app's "Open app": its DM, as in Slack. Without a bot user
        // (a webhook) there is no DM, VIP or page to open.
        ActionButton {
          visible: !pp.self && !pp.gone && !pp.botKey
          icon: pp.isApp ? "󰀻" : "󰍥"
          text: pp.isApp ? pp.app.tr("Open app", "Abrir app") : pp.app.tr("Message", "Mensagem")
          onClicked: pp.ws.openDm([pp.uid], function(id) { pp.ws.open(id) })
        }
        ActionButton {
          visible: pp.self
          icon: "󰏫"
          text: pp.app.tr("Edit profile", "Editar perfil")
          onClicked: pp.win.dialog("profileEdit", {})
        }
        ActionButton {
          visible: pp.self
          icon: "󰇵"
          text: pp.app.tr("Set a status", "Definir status")
          onClicked: pp.win.dialog("status", {})
        }
        ActionButton {
          visible: !pp.self && (!pp.bot || pp.isApp) && !pp.botKey && !pp.gone
          icon: pp.vip ? "󰓎" : "󰓒"
          iconColor: pp.vip ? pp.t.yellow : pp.t.fg
          text: "VIP"
          on: pp.vip
          tip: pp.vip ? pp.app.tr("Remove from VIPs", "Remover dos VIPs") : pp.app.tr("Add to VIPs: their messages notify you even when notifications are paused", "Adicionar aos VIPs: as mensagens notificam mesmo com as notificações pausadas")
          onClicked: pp.ws.setVip(pp.uid, !pp.vip)
        }
        ActionButton {
          id: moreBtn
          icon: "󰇙"
          text: ""
          tip: pp.app.tr("More actions", "Mais ações")
          onClicked: pp.moreMenu(moreBtn)
        }
      }

      Item { width: 1; height: pp.t.sp(16) }

      // ------------------------------------------------------------ contact
      Rectangle {
        visible: contact.visible
        width: parent.width
        height: 1
        color: pp.t.line
      }
      Column {
        id: contact
        visible: !!pp.u && (!!pp.u.email || !!pp.u.phone)
        width: parent.width
        topPadding: pp.t.sp(14)
        spacing: pp.t.sp(12)
        Text {
          text: pp.app.tr("Contact information", "Informações de contato")
          color: pp.t.fgBright
          font.family: pp.t.font
          font.pixelSize: pp.t.fsTitle
          font.bold: true
          bottomPadding: pp.t.sp(2)
        }
        ContactRow {
          visible: !!pp.u && !!pp.u.email
          icon: "󰇮"
          label: pp.app.tr("Email address", "Endereço de e-mail")
          value: pp.u ? (pp.u.email || "") : ""
          onClicked: { pp.app.copy(value); pp.win.toast(pp.app.tr("Email copied", "E-mail copiado")) }
        }
        ContactRow {
          visible: !!pp.u && !!pp.u.phone
          icon: "󰏲"
          label: pp.app.tr("Phone", "Telefone")
          value: pp.u ? (pp.u.phone || "") : ""
          onClicked: { pp.app.copy(value); pp.win.toast(pp.app.tr("Phone number copied", "Telefone copiado")) }
        }
      }

      // ------------------------------------------------------------ about
      Rectangle {
        visible: about.visible
        width: parent.width
        height: 1
        color: pp.t.line
      }
      // An app's: only its ID.
      Column {
        id: about
        visible: !!pp.u && (!pp.bot || pp.isApp)
        width: parent.width
        topPadding: pp.t.sp(14)
        spacing: pp.t.sp(10)
        Text {
          text: pp.app.tr("About", "Sobre")
          color: pp.t.fgBright
          font.family: pp.t.font
          font.pixelSize: pp.t.fsTitle
          font.bold: true
        }
        ContactRow {
          visible: !!pp.u && !!pp.u.handle && !pp.bot
          icon: "󰁥"
          label: pp.app.tr("Username", "Nome de usuário")
          value: pp.u && pp.u.handle ? "@" + pp.u.handle : ""
          link: false
          onClicked: { pp.app.copy(value); pp.win.toast(pp.app.tr("Copied", "Copiado")) }
        }
        ContactRow {
          visible: !!pp.u && !!pp.u.tzLabel && !pp.bot
          icon: "󰥔"
          label: pp.app.tr("Time zone", "Fuso horário")
          value: pp.u ? (pp.u.tzLabel || "") : ""
          link: false
        }
        ContactRow {
          icon: "󰻾"
          label: pp.botKey ? pp.app.tr("Bot ID", "ID do bot") : pp.app.tr("Member ID", "ID de membro")
          value: pp.shownId
          link: false
          onClicked: { pp.app.copy(pp.shownId); pp.win.toast(pp.app.tr("ID ", "ID ") + pp.shownId + pp.app.tr(" copied", " copiado")) }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces
  component ActionButton: Rectangle {
    id: ab
    property var app: Reg.service
    readonly property var t: app.theme
    property string icon: ""
    property string text: ""
    property string tip: ""
    property bool on: false
    property color iconColor: t.fg
    signal clicked()
    height: ab.t.sp(32)
    width: abRow.implicitWidth + (text !== "" ? ab.t.sp(26) : ab.t.sp(16))
    radius: Math.max(6, ab.t.radiusSmall)
    color: abMa.pressed ? ab.t.press : (abMa.containsMouse ? ab.t.hover : (on ? ab.t.alpha(ab.t.yellow, 0.10) : "transparent"))
    border.width: 1
    border.color: on ? ab.t.alpha(ab.t.yellow, 0.45) : ab.t.lineStrong
    Row {
      id: abRow
      anchors.centerIn: parent
      spacing: ab.t.sp(7)
      Glyph { app: ab.app; icon: ab.icon; size: ab.t.fsIcon; color: ab.iconColor; anchors.verticalCenter: parent.verticalCenter }
      Text {
        visible: ab.text !== ""
        text: ab.text
        color: ab.t.fgBright
        font.family: ab.t.font
        font.pixelSize: ab.t.fsSmall + 1
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.clicked() }
    PanelToolTip { visible: abMa.containsMouse && ab.tip !== ""; text: ab.tip }
  }

  component ContactRow: Item {
    id: cr
    property var app: Reg.service
    readonly property var t: app.theme
    property string icon: ""
    property string label: ""
    property string value: ""
    property bool link: true
    signal clicked()
    width: parent ? parent.width : 200
    height: Math.max(cr.t.sp(38), crCol.implicitHeight)
    Rectangle {
      id: crIcon
      width: cr.t.sp(36); height: width
      anchors.verticalCenter: parent.verticalCenter
      radius: Math.max(6, cr.t.radiusSmall)
      color: cr.t.alpha(cr.t.fg, 0.07)
      Glyph { app: cr.app; anchors.centerIn: parent; icon: cr.icon; size: cr.t.fsIcon + 1; color: cr.t.fgSoft }
    }
    Column {
      id: crCol
      anchors.left: crIcon.right
      anchors.leftMargin: cr.t.sp(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text { text: cr.label; color: cr.t.fgDim; font.family: cr.t.font; font.pixelSize: cr.t.fsSmall; font.bold: true }
      Text {
        width: parent.width
        text: cr.value
        color: cr.link ? cr.t.link : cr.t.fg
        font.family: cr.t.font
        font.pixelSize: cr.t.fsText
        font.underline: cr.link && crMa.containsMouse
        elide: Text.ElideRight
        MouseArea {
          id: crMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: cr.clicked()
        }
        PanelToolTip { visible: crMa.containsMouse; text: cr.app.tr("Click to copy", "Clique para copiar") }
      }
    }
  }

  // ---------------------------------------------------------------- menu
  function moreMenu(anchor) {
    var w = pp.ws, uid = pp.uid, u = pp.u
    if (!u) return
    var items = []
    var shown = pp.shownId
    if (!pp.self && !pp.gone && !pp.botKey) items.push({ label: pp.isApp ? pp.app.tr("Open app", "Abrir app") : pp.app.tr("Message", "Mensagem"), icon: pp.isApp ? "󰀻" : "󰍥",
                                                         action: function() { w.openDm([uid], function(id) { w.open(id) }) } })
    if (pp.self) items.push({ label: pp.app.tr("Edit profile", "Editar perfil"), icon: "󰏫", action: function() { pp.win.dialog("profileEdit", {}) } })
    if (!pp.bot) items.push({ label: pp.app.tr("View messages from ", "Ver mensagens de ") + (pp.self ? pp.app.tr("you", "você") : u.name), icon: "󰍉",
                              action: function() { pp.win.search("from:@" + (u.handle || u.name) + " ") } })
    items.push({ separator: true })
    items.push({ label: pp.botKey ? pp.app.tr("Copy bot ID", "Copiar ID do bot") : pp.app.tr("Copy member ID", "Copiar ID de membro"), icon: "󰆏",
                 action: function() { pp.app.copy(shown); pp.win.toast(pp.app.tr("ID ", "ID ") + shown + pp.app.tr(" copied", " copiado")) } })
    if (!pp.bot) items.push({ label: pp.app.tr("Copy email address", "Copiar endereço de e-mail"), icon: "󰇮", enabled: !!u.email,
                              action: function() { pp.app.copy(u.email); pp.win.toast(pp.app.tr("Email copied", "E-mail copiado")) } })
    // A webhook has no page of its own.
    if (!pp.botKey) {
      items.push({ label: pp.app.tr("Copy link to profile", "Copiar link do perfil"), icon: "󰌷", action: function() { pp.app.copy(pp.profileUrl); pp.win.toast(pp.app.tr("Link copied", "Link copiado")) } })
      items.push({ label: pp.app.tr("View in browser", "Ver no navegador"), icon: "󰖟", action: function() { pp.app.openUrl(pp.profileUrl) } })
    }
    pp.win.menuAt(anchor, items, 0, anchor.height + pp.t.sp(4))
  }
}
