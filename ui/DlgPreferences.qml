import QtQuick
import QtQuick.Controls
import qs.Ui
import "../lib/Util.js" as U

// Slack's Preferences: the sections on the left, their options on the
// right. Every change applies at once and is saved (app.setSetting).
// args.section opens a given section ("notifications", "sidebar",
// "messages", "language", "accessibility", "advanced").
DialogFrame {
  id: d
  title: app.tr("Preferences", "Preferências")
  cardWidth: t.sp(860)

  property string section: args.section || "notifications"
  readonly property var sections: [
    { id: "notifications", icon: "󰂚", label: d.app.tr("Notifications", "Notificações") },
    { id: "sidebar", icon: "󰛽", label: d.app.tr("Sidebar", "Barra lateral") },
    { id: "messages", icon: "󰍪", label: d.app.tr("Messages & media", "Mensagens e mídia") },
    { id: "language", icon: "󰗊", label: d.app.tr("Language", "Idioma") },
    { id: "accessibility", icon: "󰖤", label: d.app.tr("Accessibility", "Acessibilidade") },
    { id: "advanced", icon: "󰢻", label: d.app.tr("Advanced", "Avançado") }
  ]
  function go(delta) {
    var i = d.sections.findIndex(function(s) { return s.id === d.section })
    d.section = d.sections[(i + delta + d.sections.length) % d.sections.length].id
  }
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { d.go(-1); event.accepted = true }
    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { d.go(1); event.accepted = true }
  }

  // ---------------------------------------------------------------- helpers
  readonly property var pausedUntil: {
    var list = d.app.workspaces
    for (var i = 0; i < list.length; i++) if (list[i].dnd) return list[i].dnd.until || 0
    return null
  }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
  function levelLabel(w) {
    var g = w ? w.globalNotify : "everything"
    if (g === "everything" || g === "all") return d.app.tr("All new messages", "Todas as novas mensagens")
    if (g === "mentions" || g === "mentions_dms") return d.app.tr("Direct messages, mentions and keywords", "Mensagens diretas, menções e palavras-chave")
    return w && Object.keys(w.vips || {}).length ? d.app.tr("Only VIPs", "Somente VIPs") : d.app.tr("Nothing", "Nada")
  }
  function teamUrl(w, path) { return "https://" + (w.team.domain ? w.team.domain + ".slack.com" : "app.slack.com") + path }
  function pauseMenu(item) {
    var a = d.app, w = d.win
    function p(min) { a.pauseAll(min); w.toast(a.tr("Notifications paused ", "Notificações pausadas ") + U.untilLabel(Math.floor(Date.now() / 1000) + min * 60, a.lang, a.clock24)) }
    w.menuAt(item, [
      { header: a.tr("Pause notifications for…", "Pausar notificações por…") },
      { label: a.tr("30 minutes", "30 minutos"), action: function() { p(30) } },
      { label: a.tr("1 hour", "1 hora"), action: function() { p(60) } },
      { label: a.tr("2 hours", "2 horas"), action: function() { p(120) } },
      { label: a.tr("Until tomorrow", "Até amanhã"), action: function() { p(U.minutesUntilTomorrow9()) } },
      { label: a.tr("Until next week", "Até a próxima semana"), action: function() { p(U.minutesUntilNextWeek9()) } },
      { label: a.tr("Custom…", "Personalizado…"), action: function() { w.dialog("pause", {}) } }
    ], 0, item.height + d.t.sp(4))
  }
  function signOut(w) {
    var a = d.app, win = d.win, team = w.teamId, name = w.team.name || w.team.domain || team
    d.closed()
    win.dialog("confirm", {
      title: a.tr("Sign out of ", "Sair de ") + name + "?",
      text: a.tr("This app forgets the session, with this workspace's drafts and cached files. Slack in your browser stays signed in.", "Este app esquece a sessão, com os rascunhos e arquivos em cache deste workspace. O Slack no navegador continua conectado."),
      confirm: a.tr("Sign out", "Sair"), danger: true,
      action: function() { a.signOut(team) }
    })
  }
  function setAvatars(on) {
    d.app.setSetting("sidebarAvatars", on)
    d.app.workspaces.forEach(function(w) { w.sidebarAvatars = on })
  }

  Column {
    width: parent.width

    Item {
      width: parent.width
      height: Math.max(d.t.sp(300), Math.min(d.t.sp(580), d.maxHeight - d.t.sp(110)))

      // ------------------------------------------------------------ sections
      Column {
        id: nav
        width: d.t.sp(210)
        spacing: d.t.sp(2)
        Repeater {
          model: d.sections
          delegate: Rectangle {
            required property var modelData
            readonly property bool on: d.section === modelData.id
            width: nav.width
            height: d.t.sp(34)
            radius: Math.max(6, d.t.radiusSmall)
            color: on ? d.t.accent : (nma.containsMouse ? d.t.hover : "transparent")
            Row {
              x: d.t.sp(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: d.t.sp(12)
              Glyph {
                app: d.app
                anchors.verticalCenter: parent.verticalCenter
                width: d.t.sp(18)
                icon: modelData.icon
                size: d.t.fsIcon + 1
                color: parent.parent.on ? d.t.selectedText : d.t.fgSoft
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: parent.parent.on ? d.t.selectedText : d.t.fg
                font.family: d.t.font
                font.pixelSize: d.t.fsText - 1
                font.bold: parent.parent.on
              }
            }
            MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.section = modelData.id }
          }
        }
      }

      Rectangle { x: nav.width + d.t.sp(16); width: 1; height: parent.height; color: d.t.line }

      // ------------------------------------------------------------ the page
      Flickable {
        id: pageView
        x: nav.width + d.t.sp(40)
        width: parent.width - x
        height: parent.height
        contentHeight: page.implicitHeight + d.t.sp(12)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThinScroll { app: d.app }
        Loader {
          id: page
          width: pageView.width - d.t.sp(16)
          sourceComponent: ({ notifications: notifC, sidebar: sidebarC, messages: messagesC, language: languageC, accessibility: accessC, advanced: advancedC })[d.section] || notifC
          onLoaded: pageView.contentY = 0
        }
      }
    }
  }

  // ---------------------------------------------------------------- Notifications
  Component {
    id: notifC
    Column {
      spacing: d.t.sp(16)
      Text { text: d.app.tr("Desktop notifications", "Notificações na área de trabalho"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Show desktop notifications", "Mostrar notificações na área de trabalho")
        hint: d.app.tr("For direct messages, mentions and keywords, following each workspace's notification settings on Slack.",
                       "Para mensagens diretas, menções e palavras-chave, seguindo as configurações de notificação de cada workspace no Slack.")
        // The bar icon's setting too (its menu's "Desktop notifications").
        checked: d.app.notificationsOn
        onToggled: on => d.app.setNotifySetting("notifications", on)
      }
      // The sound with each notification (app.notifySound); picking one, or
      // its play button, plays it once.
      Column {
        width: parent.width
        spacing: d.t.sp(8)
        opacity: d.app.notificationsOn ? 1 : 0.45
        Column {
          width: parent.width
          spacing: 2
          Text { text: d.app.tr("Notification sound", "Som de notificação"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText; width: parent.width; wrapMode: Text.Wrap }
          Text { text: d.app.tr("Played with each notification.", "Tocado a cada notificação."); color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall; width: parent.width; wrapMode: Text.Wrap }
        }
        Choice {
          app: d.app
          width: parent.width
          value: d.app.notifySound
          actionIcon: "󰐊"
          actionTip: d.app.tr("Play", "Tocar")
          options: [
            { value: "none", label: d.app.tr("None", "Nenhum") },
            { value: "glass-chime", label: d.app.tr("Glass chime", "Sino de vidro"), action: true },
            { value: "synth-pluck", label: d.app.tr("Synth pluck", "Sintetizador"), action: true },
            { value: "kalimba-tap", label: d.app.tr("Kalimba tap", "Kalimba"), action: true },
            { value: "crystal-ping", label: d.app.tr("Crystal ping", "Ping de cristal"), action: true },
            { value: "mention", label: d.app.tr("Mention", "Menção"), action: true },
            { value: "droplet", label: d.app.tr("Droplet", "Gota"), action: true },
            { value: "vibraphone", label: d.app.tr("Vibraphone", "Vibrafone"), action: true },
            { value: "wood-blocks", label: d.app.tr("Wood blocks", "Blocos de madeira"), action: true },
            { value: "retro-blip", label: d.app.tr("Retro blip", "Blip retrô"), action: true },
            { value: "paper-chime", label: d.app.tr("Paper chime", "Sino de papel"), action: true }
          ]
          onPicked: v => { d.app.setSetting("notifySound", v); d.app.playSound(v) }
          onAction: v => d.app.playSound(v)
        }
      }
      Switch2 {
        app: d.app
        width: parent.width
        opacity: d.app.notificationsOn ? 1 : 0.45
        text: d.app.tr("Show message preview", "Mostrar prévia da mensagem")
        hint: d.app.tr("The text of the message in the notification. Off, it only says who wrote and where.",
                       "O texto da mensagem na notificação. Desligado, diz só quem escreveu e onde.")
        checked: d.app.previewOn
        onToggled: on => d.app.setNotifySetting("notificationPreview", on)
      }

      Rectangle { width: parent.width; height: 1; color: d.t.line }

      Text { text: d.app.tr("Pause notifications", "Pausar notificações"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Item {
        width: parent.width
        height: Math.max(pauseText.implicitHeight, pauseBtn.height)
        Text {
          id: pauseText
          anchors.left: parent.left
          anchors.right: pauseBtn.left
          anchors.rightMargin: d.t.sp(16)
          anchors.verticalCenter: parent.verticalCenter
          wrapMode: Text.Wrap
          text: d.pausedUntil !== null
                ? d.app.tr("Notifications are paused ", "As notificações estão pausadas ") + (d.pausedUntil ? U.untilLabel(d.pausedUntil, d.app.lang, d.app.clock24) : "") + "."
                : d.app.tr("Silence notifications for a while, in every workspace.", "Silencie as notificações por um tempo, em todos os workspaces.")
          color: d.pausedUntil !== null ? d.t.yellow : d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall + 1
        }
        SButton {
          id: pauseBtn
          app: d.app
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          small: true
          icon: d.pausedUntil !== null ? "󰂚" : "󰂛"
          text: d.pausedUntil !== null ? d.app.tr("Resume", "Retomar") : d.app.tr("Pause…", "Pausar…")
          onClicked: {
            if (d.pausedUntil !== null) { d.app.resumeAll(); d.win.toast(d.app.tr("Notifications resumed", "Notificações retomadas")) }
            else d.pauseMenu(pauseBtn)
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: d.t.line }

      Text { text: d.app.tr("Notify me about", "Notificar sobre"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Repeater {
        model: d.app.workspaces
        delegate: Item {
          required property var modelData
          width: parent.width
          height: d.t.sp(36)
          Column {
            anchors.left: parent.left
            anchors.right: link.left
            anchors.rightMargin: d.t.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { width: parent.width; text: modelData.team.name || modelData.team.domain || ""; textFormat: Text.PlainText; color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; elide: Text.ElideRight }
            Text { width: parent.width; text: d.levelLabel(modelData); color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall; elide: Text.ElideRight }
          }
          SButton {
            id: link
            app: d.app
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            small: true
            icon: "󰏌"
            text: d.app.tr("Change on Slack", "Mudar no Slack")
            onClicked: Qt.openUrlExternally(d.teamUrl(modelData, "/account/notifications"))
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- Sidebar
  Component {
    id: sidebarC
    Column {
      spacing: d.t.sp(16)
      Text { text: d.app.tr("Sidebar", "Barra lateral"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Show profile photos", "Mostrar fotos de perfil")
        hint: d.app.tr("Photos instead of presence dots next to direct messages, in the sidebar and in its folded rail.",
                       "Fotos em vez dos pontos de presença ao lado das mensagens diretas, na barra lateral e no trilho recolhido.")
        checked: d.app.setting("sidebarAvatars", d.ws ? d.ws.sidebarAvatars : true) !== false
        onToggled: on => d.setAvatars(on)
      }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Bar beside unread conversations", "Barra ao lado das conversas não lidas")
        hint: d.app.tr("A short bar at the left edge of each unread row.", "Uma barrinha na borda esquerda de cada linha não lida.")
        checked: d.app.unreadBar
        onToggled: on => d.app.setSetting("unreadBar", on)
      }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Tint unread conversations", "Fundo nas conversas não lidas")
        hint: d.app.tr("A soft background behind unread rows.", "Um fundo suave atrás das linhas não lidas.")
        checked: d.app.unreadBackground
        onToggled: on => d.app.setSetting("unreadBackground", on)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("Unread conversations are always in bold. Drag the sidebar's edge to resize it; narrower than a name, it folds into a rail of photos.",
                       "Conversas não lidas ficam sempre em negrito. Arraste a borda da barra lateral para mudar a largura; mais estreita que um nome, ela vira um trilho de fotos.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }

      Rectangle { width: parent.width; height: 1; color: d.t.line }

      Text { text: d.app.tr("Workspaces in the sidebar", "Workspaces na barra lateral"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Choice {
        app: d.app
        width: parent.width
        value: d.app.setting("railWorkspaces", "stacked") === "expanded" ? "expanded" : "stacked"
        options: [
          { value: "stacked", label: d.app.tr("Stacked", "Empilhados"), hint: d.app.tr("Only the workspace you're in, the others behind it; a click opens the switcher. Like Slack.", "Só o workspace em que você está, os outros atrás dele; um clique abre o seletor. Como no Slack.") },
          { value: "expanded", label: d.app.tr("Expanded", "Expandidos"), hint: d.app.tr("Every workspace in the rail, one under the other.", "Todos os workspaces no trilho, um embaixo do outro.") }
        ]
        onPicked: v => d.app.setSetting("railWorkspaces", v)
      }
    }
  }

  // ---------------------------------------------------------------- Messages & media
  Component {
    id: messagesC
    Column {
      spacing: d.t.sp(12)
      readonly property date sample: new Date(2026, 0, 1, 21, 29)
      Text { text: d.app.tr("Clock", "Relógio"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Choice {
        app: d.app
        width: parent.width
        value: d.app.clock24 ? "24h" : "12h"
        options: [
          { value: "24h", label: d.app.tr("24-hour", "24 horas") + "  (" + U.time(parent.sample, true) + ")" },
          { value: "12h", label: d.app.tr("12-hour", "12 horas") + "  (" + U.time(parent.sample, false) + ")" }
        ]
        onPicked: v => d.app.setSetting("clock", v)
      }
      Item { width: 1; height: d.t.sp(4) }
      Text { text: d.app.tr("Message spacing", "Espaçamento das mensagens"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Choice {
        app: d.app
        width: parent.width
        value: d.app.compact ? "compact" : "comfortable"
        options: [
          { value: "comfortable", label: d.app.tr("Comfortable", "Confortável"), hint: d.app.tr("Room between messages, like Slack.", "Espaço entre as mensagens, como no Slack.") },
          { value: "compact", label: d.app.tr("Compact", "Compacto"), hint: d.app.tr("Messages closer together, more of them on screen.", "Mensagens mais juntas, mais delas na tela.") }
        ]
        onPicked: v => d.app.setSetting("spacing", v)
      }
      Item { width: 1; height: d.t.sp(4) }
      Text { text: d.app.tr("Emoji", "Emoji"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Choice {
        app: d.app
        width: parent.width
        value: d.app.slackEmoji ? "slack" : "system"
        options: [
          { value: "slack", label: d.app.tr("Slack's emoji", "Emoji do Slack"), hint: d.app.tr("The same pictures as the Slack app (downloaded once, then cached).", "As mesmas imagens do app do Slack (baixadas uma vez, depois em cache).") },
          { value: "system", label: d.app.tr("System emoji", "Emoji do sistema"), hint: d.app.tr("Your system's emoji font. Custom emoji stay pictures.", "A fonte de emoji do seu sistema. Emoji personalizados continuam imagens.") }
        ]
        onPicked: v => d.app.setSetting("emojiStyle", v)
      }
      Row {
        x: d.t.sp(36)
        spacing: d.t.sp(8)
        Repeater {
          model: ["+1", "joy", "tada", "eyes", "rocket", "white_check_mark", "heart", "fire"]
          delegate: EmojiIcon { required property var modelData; app: d.app; ws: d.ws; name: modelData; size: d.t.sp(22) }
        }
      }
      Item { width: 1; height: d.t.sp(4) }
      Text { text: d.app.tr("Message box", "Caixa de mensagem"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Show the formatting toolbar", "Mostrar a barra de formatação")
        hint: d.app.tr("Bold, italic, lists, code… above what you type. The Aa button in the box shows and hides it too.",
                       "Negrito, itálico, listas, código… acima do que você digita. O botão Aa na caixa também mostra e esconde.")
        checked: d.app.setting("composerToolbar", true) !== false
        onToggled: on => d.app.setSetting("composerToolbar", on)
      }
      Item { width: 1; height: d.t.sp(4) }
      // Third-party pictures in messages (MessageBody.shows), as Slack's
      // "Show images and files from linked websites".
      Text { text: d.app.tr("Link previews", "Prévias de links"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Load images from link previews", "Carregar imagens de prévias de links")
        hint: d.app.tr("Pictures in link previews and apps' messages come straight from other sites, which see your connection. Off, previews show without them; Slack's own pictures still load.",
                       "As imagens de prévias de links e de mensagens de apps vêm direto de outros sites, que veem sua conexão. Desligado, as prévias aparecem sem elas; as imagens do próprio Slack continuam.")
        checked: d.app.previewImages
        onToggled: on => d.app.setSetting("previewImages", on)
      }
    }
  }

  // ---------------------------------------------------------------- Language
  Component {
    id: languageC
    Column {
      spacing: d.t.sp(12)
      Text { text: d.app.tr("Language", "Idioma"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("The language of this app's menus, buttons and dates. Messages are shown as they were written.",
                       "O idioma dos menus, botões e datas deste app. As mensagens aparecem como foram escritas.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
      Choice {
        app: d.app
        width: parent.width
        value: d.app.lang
        options: [
          { value: "en", label: "English (US)" },
          { value: "pt-BR", label: "Português (Brasil)" }
        ]
        onPicked: v => d.app.setSetting("lang", v)
      }
    }
  }

  // ---------------------------------------------------------------- Accessibility
  Component {
    id: accessC
    Column {
      id: acc
      spacing: d.t.sp(14)
      property real shown: d.app.zoom
      function apply(z) {
        z = Math.round(Math.max(0.7, Math.min(1.6, z)) * 10) / 10
        acc.shown = z
        d.app.setSetting("zoom", z)
      }
      Text { text: d.app.tr("Zoom", "Zoom"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("Makes everything in the window bigger or smaller: text, photos, spacing.", "Aumenta ou diminui tudo na janela: texto, fotos, espaçamento.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
      Row {
        spacing: d.t.sp(12)
        IconButton { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰍴"; tip: d.app.tr("Zoom out", "Diminuir"); enabled2: acc.shown > 0.7; onClicked: acc.apply(acc.shown - 0.1) }
        Slider {
          id: slider
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(d.t.sp(320), acc.width - d.t.sp(200))
          height: d.t.sp(28)
          from: 0.7
          to: 1.6
          stepSize: 0.1
          snapMode: Slider.SnapAlways
          value: acc.shown
          onMoved: acc.shown = Math.round(value * 10) / 10
          onPressedChanged: if (!pressed) acc.apply(value)
          background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: d.t.sp(4)
            radius: height / 2
            color: d.t.lineStrong
            Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: height / 2; color: d.t.accent }
          }
          handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: d.t.sp(18)
            implicitHeight: d.t.sp(18)
            radius: width / 2
            color: slider.pressed ? Qt.lighter(d.t.accent, 1.1) : d.t.accent
            border.width: 2
            border.color: d.t.bg
          }
        }
        IconButton { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰐕"; tip: d.app.tr("Zoom in", "Aumentar"); enabled2: acc.shown < 1.6; onClicked: acc.apply(acc.shown + 0.1) }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: d.t.sp(48)
          text: Math.round(acc.shown * 100) + "%"
          color: d.t.fgBright
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          font.bold: true
        }
      }
      SButton {
        app: d.app
        small: true
        icon: "󰦛"
        text: d.app.tr("Reset to 100%", "Voltar a 100%")
        enabled2: Math.abs(d.app.zoom - 1) > 0.01
        onClicked: acc.apply(1)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("Shortcuts: Ctrl+= zooms in, Ctrl+- zooms out, Ctrl+0 resets.", "Atalhos: Ctrl+= aumenta, Ctrl+- diminui, Ctrl+0 volta ao normal.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }
  }

  // ---------------------------------------------------------------- Advanced
  Component {
    id: advancedC
    Column {
      spacing: d.t.sp(12)
      Text { text: d.app.tr("Workspaces", "Workspaces"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("The workspaces signed in here. Signing out only forgets the session on this computer.",
                       "Os workspaces conectados aqui. Sair só esquece a sessão neste computador.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
      Repeater {
        model: d.app.workspaces
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property var w: modelData
          width: parent.width
          height: d.t.sp(96)
          radius: Math.max(6, d.t.radiusSmall)
          color: d.t.alpha(d.t.fg, 0.03)
          border.width: 1
          border.color: d.t.line
          Clip {
            id: icon
            x: d.t.sp(14)
            y: d.t.sp(14)
            width: d.t.sp(36)
            height: width
            radius: Math.round(width * 0.24)
            color: Qt.hsla(U.hue(w.teamId), 0.45, 0.42, 1)
            Text {
              anchors.centerIn: parent
              visible: teamImg.status !== Image.Ready
              text: U.initials(w.team.name || "?")
              textFormat: Text.PlainText
              color: "white"
              font.family: d.t.font
              font.pixelSize: d.t.fsText
              font.bold: true
            }
            Image {
              id: teamImg
              anchors.fill: parent
              source: w.team.icon || ""
              asynchronous: true
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: 96
              sourceSize.height: 96
            }
          }
          Column {
            anchors.left: icon.right
            anchors.leftMargin: d.t.sp(12)
            anchors.right: parent.right
            anchors.rightMargin: d.t.sp(14)
            y: d.t.sp(14)
            spacing: 2
            Row {
              spacing: d.t.sp(8)
              Text { text: w.team.name || w.team.domain || w.teamId; textFormat: Text.PlainText; color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
              Rectangle {
                visible: w === d.app.current
                anchors.verticalCenter: parent.verticalCenter
                width: curText.implicitWidth + d.t.sp(12)
                height: curText.implicitHeight + d.t.sp(4)
                radius: height / 2
                color: d.t.alpha(d.t.accent, 0.18)
                Text { id: curText; anchors.centerIn: parent; text: d.app.tr("current", "atual"); color: d.t.accent; font.family: d.t.font; font.pixelSize: d.t.fsTiny; font.bold: true }
              }
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: (w.team.domain ? w.team.domain + ".slack.com" : "") + (w.me && w.me.name ? "  ·  @" + (w.me.handle || w.me.name) : "") + (index < 9 ? "  ·  Ctrl+" + (index + 1) : "")
              textFormat: Text.PlainText
              color: d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
            }
          }
          Row {
            anchors.left: icon.right
            anchors.leftMargin: d.t.sp(12)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: d.t.sp(12)
            spacing: d.t.sp(8)
            SButton { app: d.app; small: true; icon: "󰏌"; text: d.app.tr("Notification preferences on slack.com", "Preferências de notificação no slack.com"); onClicked: Qt.openUrlExternally(d.teamUrl(w, "/account/notifications")) }
            SButton { app: d.app; small: true; kind: "danger"; icon: "󰍃"; text: d.app.tr("Sign out", "Sair"); onClicked: d.signOut(w) }
          }
        }
      }
      SButton {
        app: d.app
        small: true
        icon: "󰐕"
        text: d.app.tr("Add a workspace", "Adicionar um workspace")
        onClicked: { var w = d.win; d.closed(); w.dialog("addWorkspace", {}) }
      }

      Item { width: 1; height: d.t.sp(6) }
      Rectangle { width: parent.width; height: 1; color: d.t.line }
      Item { width: 1; height: d.t.sp(2) }

      Text { text: d.app.tr("On this computer", "Neste computador"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Repeater {
        model: [
          { label: d.app.tr("Settings and sessions", "Configurações e sessões"), path: d.app.configDir },
          { label: d.app.tr("Cache (photos, files)", "Cache (fotos, arquivos)"), path: d.app.cacheDir }
        ]
        delegate: Item {
          required property var modelData
          width: parent.width
          height: d.t.sp(38)
          Column {
            anchors.left: parent.left
            anchors.right: openBtn.left
            anchors.rightMargin: d.t.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { width: parent.width; text: modelData.label; color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1 }
            Text { width: parent.width; text: modelData.path; color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall; elide: Text.ElideMiddle }
          }
          SButton { id: openBtn; app: d.app; small: true; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: "󰉋"; text: d.app.tr("Open", "Abrir"); onClicked: Qt.openUrlExternally("file://" + modelData.path) }
        }
      }

      Item { width: 1; height: d.t.sp(6) }
      Rectangle { width: parent.width; height: 1; color: d.t.line }
      Item { width: 1; height: d.t.sp(2) }

      // New versions of the plugin (core/Updater.qml); the menu's check works either way.
      Text { text: d.app.tr("Updates", "Atualizações"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsTitle; font.bold: true }
      Switch2 {
        app: d.app
        width: parent.width
        text: d.app.tr("Check for updates", "Verificar atualizações")
        hint: d.app.tr("Looks on GitHub for a new version of Omaslack a little after start-up and every six hours. Off, it only looks when you ask, from your menu.",
                       "Procura no GitHub uma versão nova do Omaslack logo depois de iniciar e a cada seis horas. Desligado, só procura quando você pede, pelo seu menu.")
        checked: d.app.setting("checkUpdates", true) !== false
        onToggled: on => d.app.setSetting("checkUpdates", on)
      }
    }
  }
}
