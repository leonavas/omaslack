import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Mrkdwn.js" as Md
import "../lib/Registry.js" as Reg

// The rail's Later tab (in the sidebar's place): the messages saved for
// later, newest saved first — where, who, what, when saved (and due) —
// with Mark complete and Open on hover. A click opens the message.
Rectangle {
  id: ll
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
  readonly property bool narrow: width < t.sp(150)
  property string tab: "progress"        // progress | archived
  property string selectedKey: ""
  color: t.sidebar

  Component.onCompleted: if (ll.ws) ll.ws.loadSaved()

  readonly property var saved: {
    if (!ws) return []
    ws.savedRev
    return ws.savedItems.filter(function(i) { return ws.saved[i.conv + "/" + i.ts] }).map(function(i) {
      return { key: i.conv + "/" + i.ts, conv: i.conv, ts: i.ts, created: i.created || 0, due: i.due || 0 }
    })
  }
  readonly property var items: tab === "progress" ? saved : []

  // ---------------------------------------------------------------- header
  Item {
    id: header
    width: parent.width
    height: ll.t.sp(50)
    Text {
      visible: !ll.narrow
      x: ll.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - refresh.width - ll.t.sp(20)
      text: ll.app.tr("Later", "Depois")
      color: ll.t.fgBright
      font.family: ll.t.font
      font.pixelSize: ll.t.fsHeader
      font.bold: true
      elide: Text.ElideRight
    }
    IconButton {
      id: refresh
      app: ll.app
      anchors.right: parent.right
      anchors.rightMargin: ll.narrow ? (parent.width - width) / 2 : ll.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      size: ll.t.sp(32)
      icon: ll.narrow ? "󰃀" : "󰑓"
      tip: ll.app.tr("Refresh", "Atualizar")
      color: ll.t.fgBright
      hoverColor: ll.t.hoverStrong
      onClicked: ll.ws.loadSaved()
    }
  }

  // In progress · Archived
  Item {
    id: tabs
    visible: !ll.narrow
    y: header.height
    width: parent.width
    height: visible ? ll.t.sp(36) : 0
    Row {
      x: ll.t.sp(10)
      height: parent.height
      spacing: ll.t.sp(2)
      Repeater {
        model: [
          { id: "progress", label: ll.app.tr("In progress", "Em andamento") },
          { id: "archived", label: ll.app.tr("Archived", "Arquivados") }
        ]
        delegate: Item {
          id: tabItem
          required property var modelData
          readonly property bool active: ll.tab === modelData.id
          readonly property int count: modelData.id === "progress" ? ll.saved.length : 0
          height: parent.height
          width: tabText.implicitWidth + (countText.visible ? countText.implicitWidth + ll.t.sp(5) : 0) + ll.t.sp(16)
          Rectangle {
            anchors.fill: parent
            anchors.topMargin: ll.t.sp(3)
            anchors.bottomMargin: ll.t.sp(5)
            radius: Math.max(4, ll.t.radiusSmall)
            color: tabMa.containsMouse && !tabItem.active ? ll.t.hover : "transparent"
          }
          Text {
            id: tabText
            x: ll.t.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -ll.t.sp(1)
            text: tabItem.modelData.label
            color: tabItem.active ? ll.t.fgBright : ll.t.fgDim
            font.family: ll.t.font
            font.pixelSize: ll.t.fsSmall + 1
            font.bold: tabItem.active
          }
          Text {
            id: countText
            visible: tabItem.count > 0
            anchors.left: tabText.right
            anchors.leftMargin: ll.t.sp(5)
            anchors.baseline: tabText.baseline
            text: String(tabItem.count)
            color: ll.t.fgDim
            font.family: ll.t.font
            font.pixelSize: ll.t.fsSmall
          }
          Rectangle {
            visible: tabItem.active
            anchors.bottom: parent.bottom
            x: ll.t.sp(4)
            width: parent.width - ll.t.sp(8)
            height: 2
            radius: 1
            color: ll.t.fgBright
          }
          MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ll.tab = tabItem.modelData.id }
        }
      }
    }
  }

  Rectangle { y: tabs.y + tabs.height; width: parent.width; height: 1; color: ll.t.line }

  // ---------------------------------------------------------------- rows
  ListView {
    id: list
    y: tabs.y + tabs.height + 1
    width: parent.width
    height: parent.height - y
    clip: true
    topMargin: ll.t.sp(6)
    bottomMargin: ll.t.sp(12)
    spacing: ll.t.sp(2)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: false
    model: ScriptModel { values: ll.items; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: ll.app }

    delegate: Item {
      id: row
      required property var modelData
      // undefined: not asked yet; null: loading; false: gone; else the message.
      readonly property var msg: { ll.ws.savedRev; return ll.ws.savedMsgs[modelData.key] }
      readonly property var c: ll.ws.conv(modelData.conv)
      readonly property bool selected: ll.selectedKey === modelData.key
      readonly property bool hot: ma.containsMouse || actHover.hovered
      readonly property color ink: selected ? ll.t.rowSelectedText : ll.t.fgBright
      readonly property color soft: selected ? ll.t.alpha(ll.t.rowSelectedText, 0.78) : ll.t.fgDim
      readonly property bool overdue: modelData.due > 0 && modelData.due * 1000 < Date.now()
      width: list.width
      height: ll.narrow ? ll.t.sp(52) : Math.max(ll.t.sp(60), body.implicitHeight + ll.t.sp(18))

      Component.onCompleted: ll.ws.fetchSaved(modelData.conv, modelData.ts)

      Rectangle {
        x: ll.t.sp(8)
        width: parent.width - ll.t.sp(16)
        height: parent.height
        radius: Math.max(6, ll.t.radiusSmall)
        color: row.selected ? ll.t.rowSelected : (ma.pressed ? ll.t.hoverStrong : (row.hot ? ll.t.hover : "transparent"))
      }

      Item {
        id: lead
        x: ll.narrow ? (row.width - width) / 2 : ll.t.sp(20)
        y: ll.narrow ? (row.height - height) / 2 : ll.t.sp(10)
        width: ll.t.sp(36)
        height: width
        Avatar {
          anchors.fill: parent
          app: ll.app
          ws: ll.ws
          // An app: the picture its message posts with (Workspace.author).
          readonly property var who: row.msg ? ll.ws.author(row.msg) : null
          user: row.msg ? (row.msg.user || "") : ""
          url: who && who.app ? who.icon : ""
          name: who && who.app ? who.name : (row.msg ? "" : "…")
          size: parent.width
          onClicked: ll.openItem(row.modelData, row.msg)
        }
      }

      Column {
        id: body
        visible: !ll.narrow
        anchors.left: lead.right
        anchors.leftMargin: ll.t.sp(12)
        anchors.right: parent.right
        anchors.rightMargin: ll.t.sp(18)
        y: ll.t.sp(8)
        spacing: ll.t.sp(2)

        // Where · when saved
        Item {
          width: parent.width
          height: whereText.implicitHeight
          Text {
            id: whereText
            width: parent.width - savedAt.implicitWidth - ll.t.sp(8)
            text: ll.whereOf(row.modelData.conv, row.c, row.msg)
            color: row.soft
            font.family: ll.t.font
            font.pixelSize: ll.t.fsTiny + 1
            elide: Text.ElideRight
          }
          Text {
            id: savedAt
            visible: !row.hot
            anchors.right: parent.right
            text: row.modelData.created ? U.shortStamp(String(row.modelData.created), ll.app.lang, ll.app.clock24) : ""
            color: row.soft
            font.family: ll.t.font
            font.pixelSize: ll.t.fsTiny
          }
        }
        Text {
          width: parent.width
          text: !row.msg ? "" : (ll.ws.author(row.msg).name || "?")
          visible: !!row.msg
          color: row.ink
          font.family: ll.t.font
          font.pixelSize: ll.t.fsSmall + 1
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: row.msg === false ? ll.app.tr("This message is no longer available.", "Esta mensagem não está mais disponível.")
              : (row.msg ? Md.flat(row.msg, ll.ctx, 240) : ll.app.tr("Loading…", "Carregando…"))
          textFormat: Text.PlainText
          color: row.selected ? ll.t.rowSelectedText : (row.msg ? ll.t.fg : ll.t.fgDim)
          font.family: ll.t.font
          font.pixelSize: ll.t.fsSmall
          font.italic: !row.msg
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
        // Due date (its own color reads on the gray selection too).
        Row {
          visible: row.modelData.due > 0
          spacing: ll.t.sp(5)
          topPadding: ll.t.sp(2)
          Glyph { app: ll.app; icon: "󰥔"; size: ll.t.fsTiny; color: row.overdue ? ll.t.red : ll.t.yellow; anchors.verticalCenter: parent.verticalCenter }
          Text {
            text: ll.dueLabel(row.modelData.due, row.overdue)
            color: row.overdue ? ll.t.red : ll.t.yellow
            font.family: ll.t.font
            font.pixelSize: ll.t.fsTiny
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
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
          if (mouse.button === Qt.RightButton) { var p = ma.mapToItem(ll.win.contentItem, mouse.x, mouse.y); ll.rowMenu(row.modelData, row.msg, p.x, p.y); return }
          ll.openItem(row.modelData, row.msg)
        }
      }
      PanelToolTip { visible: ma.containsMouse && ll.narrow; text: row.msg ? Md.flat(row.msg, ll.ctx, 120) : "" }

      // Hover: Mark complete · Open · more.
      Rectangle {
        visible: row.hot && !ll.narrow
        anchors.right: parent.right
        anchors.rightMargin: ll.t.sp(14)
        y: ll.t.sp(4)
        height: ll.t.sp(30)
        width: acts.implicitWidth + ll.t.sp(6)
        radius: Math.max(6, ll.t.radiusSmall)
        color: ll.t.popup
        border.width: 1
        border.color: ll.t.lineStrong
        HoverHandler { id: actHover }
        Row {
          id: acts
          anchors.centerIn: parent
          spacing: ll.t.sp(1)
          IconButton {
            app: ll.app; size: ll.t.sp(26); iconSize: ll.t.fsIcon - 1
            icon: "󰄬"
            color: hovered ? ll.t.green : ll.t.fgSoft
            tip: ll.app.tr("Mark complete", "Marcar como concluído")
            onClicked: ll.complete(row.modelData, row.msg)
          }
          IconButton {
            app: ll.app; size: ll.t.sp(26); iconSize: ll.t.fsIcon - 1
            icon: "󰁔"
            tip: ll.app.tr("Open", "Abrir")
            onClicked: ll.openItem(row.modelData, row.msg)
          }
          IconButton {
            id: moreBtn
            app: ll.app; size: ll.t.sp(26); iconSize: ll.t.fsIcon - 1
            icon: "󰇙"
            tip: ll.app.tr("More actions", "Mais ações")
            onClicked: { var p = moreBtn.mapToItem(ll.win.contentItem, 0, moreBtn.height + 4); ll.rowMenu(row.modelData, row.msg, p.x, p.y) }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- empty
  Column {
    visible: ll.items.length === 0 && !ll.narrow
    anchors.horizontalCenter: parent.horizontalCenter
    y: list.y + ll.t.sp(48)
    width: parent.width - ll.t.sp(40)
    spacing: ll.t.sp(8)
    Glyph { app: ll.app; anchors.horizontalCenter: parent.horizontalCenter; icon: ll.tab === "progress" ? "󰃀" : "󰀼"; size: ll.t.sp(30); color: ll.t.fgDim }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: ll.tab === "progress" ? ll.app.tr("Save it for later", "Salve para depois") : ll.app.tr("Nothing archived", "Nada arquivado")
      color: ll.t.fgBright
      font.family: ll.t.font
      font.pixelSize: ll.t.fsText
      font.bold: true
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: ll.tab === "progress"
            ? ll.app.tr("Messages you save for later show up here. Hover a message and click 󰃃 to save it.", "As mensagens que você salva para depois aparecem aqui. Passe o mouse numa mensagem e clique em 󰃃 para salvá-la.")
            : ll.app.tr("Items you archive show up here.", "Os itens que você arquiva aparecem aqui.")
      color: ll.t.fgDim
      font.family: ll.t.font
      font.pixelSize: ll.t.fsSmall
    }
  }

  // ---------------------------------------------------------------- actions
  function whereOf(conv, c, msg) {
    var thread = msg && msg.threadTs && msg.threadTs !== msg.ts
    var label = ll.ws.convLabel(conv) || conv
    var place = !c ? label : (c.kind === "im" ? ll.app.tr("Direct message", "Mensagem direta") + " · " + label : (c.kind === "mpim" ? label : "#" + label))
    return thread ? ll.app.tr("Thread in ", "Conversa em ") + place : place
  }

  // "Due tomorrow at 9:00", "Overdue · Yesterday at 17:00".
  function dueLabel(unix, overdue) {
    if (overdue) return ll.app.tr("Overdue · ", "Atrasado · ") + U.relative(String(unix), ll.app.lang, ll.app.clock24)
    var d = new Date(unix * 1000)
    var diff = U.dayDiff(d, new Date())
    var at = U.time(d, ll.app.clock24)
    if (diff === 0) return ll.app.tr("Due today at ", "Para hoje às ") + at
    if (diff === -1) return ll.app.tr("Due tomorrow at ", "Para amanhã às ") + at
    return ll.app.tr("Due ", "Para ") + U.shortStamp(String(unix), ll.app.lang, ll.app.clock24) + ll.app.tr(" at ", " às ") + at
  }

  function openItem(item, msg) {
    ll.selectedKey = item.key
    if (msg && msg.threadTs && msg.threadTs !== msg.ts) ll.ws.open(item.conv, { ts: item.ts, threadTs: msg.threadTs })
    else ll.ws.open(item.conv, { ts: item.ts })
  }

  function complete(item, msg) {
    ll.ws.toggleSaved(item.conv, msg || { ts: item.ts })
  }

  function rowMenu(item, msg, x, y) {
    var w = ll.ws
    var m = msg || { ts: item.ts }
    var items = [
      { label: ll.app.tr("Open", "Abrir"), icon: "󰁔", action: function() { ll.openItem(item, msg) } },
      { label: ll.app.tr("Mark complete", "Marcar como concluído"), icon: "󰄬", action: function() { ll.complete(item, msg) } }
    ]
    if (msg) items.push({ label: ll.app.tr("Remind me about this", "Lembrar-me disto"), icon: "󰀠", sub: [
      { label: ll.app.tr("In 20 minutes", "Em 20 minutos"), action: function() { w.remind(item.conv, m, 20) } },
      { label: ll.app.tr("In 1 hour", "Em 1 hora"), action: function() { w.remind(item.conv, m, 60) } },
      { label: ll.app.tr("In 3 hours", "Em 3 horas"), action: function() { w.remind(item.conv, m, 180) } },
      { label: ll.app.tr("Tomorrow", "Amanhã"), action: function() { w.remind(item.conv, m, U.minutesUntilTomorrow9()) } },
      { label: ll.app.tr("Next week", "Na próxima semana"), action: function() { w.remind(item.conv, m, U.minutesUntilNextWeek9()) } }
    ] })
    items.push({ separator: true })
    items.push({ label: ll.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() { ll.app.copy(w.permalink(item.conv, m)); ll.win.toast(ll.app.tr("Link copied", "Link copiado")) } })
    if (msg) items.push({ label: ll.app.tr("Copy message", "Copiar mensagem"), icon: "󰆏", action: function() { ll.app.copy(Md.flat(msg, ll.ctx, 0)); ll.win.toast(ll.app.tr("Message copied", "Mensagem copiada")) } })
    ll.win.menu(items, x, y)
  }
}
