import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// Slack's top bar: history arrows on the left, the search box in the
// middle ("Search <workspace>"), help on the right.
Item {
  id: bar
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  property int railWidth: 72

  Row {
    x: bar.railWidth + bar.t.sp(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: bar.t.sp(2)
    visible: bar.app.signedIn
    IconButton {
      app: bar.app
      icon: "󰁍"
      tip: bar.app.tr("Back", "Voltar") + "  Alt+←"
      enabled2: !!bar.ws && bar.ws.backStack.length > 0
      color: bar.t.alpha(bar.t.fgBright, 0.85)
      onClicked: bar.ws.goBack()
    }
    IconButton {
      app: bar.app
      icon: "󰁔"
      tip: bar.app.tr("Forward", "Avançar") + "  Alt+→"
      enabled2: !!bar.ws && bar.ws.forwardStack.length > 0
      color: bar.t.alpha(bar.t.fgBright, 0.85)
      onClicked: bar.ws.goForward()
    }
    IconButton {
      id: histBtn
      app: bar.app
      icon: "󰋚"
      tip: bar.app.tr("History", "Histórico")
      color: bar.t.alpha(bar.t.fgBright, 0.85)
      onClicked: {
        var items = []
        var seen = {}
        var stack = bar.ws.backStack.slice().reverse()
        stack.forEach(function(e) {
          if (e.view !== "conv" || !e.conv || seen[e.conv]) return
          seen[e.conv] = true
          var c = bar.ws.conv(e.conv)
          var icon = c && c.kind === "private" ? "󰌾" : (c && (c.kind === "im" || c.kind === "mpim") ? "󰍥" : "󰻞")
          items.push({ label: bar.ws.convLabel(e.conv), icon: icon, action: function() { bar.ws.open(e.conv) } })
        })
        if (!items.length) items.push({ header: bar.app.tr("Nothing here yet", "Nada por aqui ainda") })
        bar.win.menuAt(histBtn, [{ header: bar.app.tr("Recent", "Recentes") }].concat(items.slice(0, 12)))
      }
    }
  }

  // The search box.
  Rectangle {
    id: box
    visible: bar.app.signedIn
    anchors.centerIn: parent
    width: Math.min(bar.t.sp(720), bar.width * 0.48)
    height: bar.t.sp(28)
    radius: Math.max(6, bar.t.radiusSmall)
    color: ma.containsMouse ? bar.t.alpha(bar.t.fgBright, 0.2) : bar.t.alpha(bar.t.fgBright, 0.13)
    border.width: 1
    border.color: bar.t.alpha(bar.t.fgBright, 0.12)
    Glyph {
      app: bar.app
      icon: "󰍉"
      color: bar.t.alpha(bar.t.fgBright, 0.8)
      size: bar.t.fsIcon - 1
      anchors.left: parent.left
      anchors.leftMargin: bar.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: bar.t.sp(32)
      anchors.right: parent.right
      anchors.rightMargin: bar.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      text: bar.app.tr("Search ", "Buscar em ") + (bar.ws ? bar.ws.team.name : "")
      textFormat: Text.PlainText
      color: bar.t.alpha(bar.t.fgBright, 0.8)
      font.family: bar.t.font
      font.pixelSize: bar.t.fsSmall + 1
      elide: Text.ElideRight
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: bar.win.search("")
    }
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: bar.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: bar.t.sp(4)
    IconButton {
      id: helpBtn
      app: bar.app
      visible: bar.app.signedIn
      icon: "󰘥"
      tip: bar.app.tr("Help", "Ajuda")
      color: bar.t.alpha(bar.t.fgBright, 0.85)
      onClicked: bar.win.menuAt(helpBtn, [
        { label: bar.app.tr("Keyboard shortcuts", "Atalhos de teclado"), icon: "󰌌", hint: "Ctrl+/", action: function() { bar.win.dialog("shortcuts") } },
        { label: bar.app.tr("Preferences", "Preferências"), icon: "󰒓", hint: "Ctrl+,", action: function() { bar.win.dialog("preferences") } },
        { separator: true },
        { label: bar.app.tr("About this app", "Sobre este app"), icon: "󰋼", action: function() { bar.win.dialog("about") } }
      ], -bar.t.sp(180), bar.t.sp(34))
    }
  }

  // Drag the frame to move a floating window.
  MouseArea {
    anchors.fill: parent
    z: -1
    onDoubleClicked: {}
  }
}
