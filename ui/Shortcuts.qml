import QtQuick
import "../lib/Registry.js" as Reg

// Slack's keyboard shortcuts, window-wide.
Item {
  id: keys
  property var app: Reg.service
  property var win
  property var ws

  function rows() { return keys.ws ? keys.ws.sidebarRows : [] }
  function zoom(d) {
    var z = d === 0 ? 1.0 : Math.max(0.7, Math.min(1.6, Math.round((keys.app.zoom + d) * 10) / 10))
    keys.app.setSetting("zoom", z)
    keys.win.toast(Math.round(z * 100) + "%")
  }

  Shortcut { sequences: ["Ctrl+K", "Ctrl+T", "Ctrl+G"]; onActivated: keys.win.search("") }
  Shortcut { sequence: "Ctrl+Shift+K"; onActivated: keys.win.railTab = keys.win.railTab === "dms" ? "home" : "dms" }
  Shortcut { sequence: "Ctrl+Shift+M"; onActivated: keys.win.railTab = keys.win.railTab === "activity" ? "home" : "activity" }
  Shortcut { sequence: "Ctrl+Shift+S"; onActivated: keys.win.railTab = keys.win.railTab === "later" ? "home" : "later" }
  Shortcut { sequence: "Ctrl+Shift+T"; onActivated: { keys.win.railTab = "home"; keys.ws.showView("threads") } }
  Shortcut { sequence: "Alt+Up"; onActivated: keys.ws.step(keys.rows(), -1, false) }
  Shortcut { sequence: "Alt+Down"; onActivated: keys.ws.step(keys.rows(), 1, false) }
  Shortcut { sequences: ["Alt+Shift+Up", "Ctrl+Shift+A"]; onActivated: keys.ws.step(keys.rows(), -1, true) }
  Shortcut { sequence: "Alt+Shift+Down"; onActivated: keys.ws.step(keys.rows(), 1, true) }
  Shortcut { sequences: ["Alt+Left", "Ctrl+["]; onActivated: keys.ws.goBack() }
  Shortcut { sequences: ["Alt+Right", "Ctrl+]"]; onActivated: keys.ws.goForward() }
  Shortcut { sequence: "Shift+Esc"; onActivated: keys.ws.markAllRead() }
  Shortcut { sequence: "Ctrl+N"; onActivated: keys.win.dialog("newMessage") }
  Shortcut { sequence: "Ctrl+Shift+L"; onActivated: keys.win.dialog("browse") }
  Shortcut { sequence: "Ctrl+,"; onActivated: keys.win.dialog("preferences") }
  Shortcut { sequences: ["Ctrl+/", "F1"]; onActivated: keys.win.dialogName === "shortcuts" ? keys.win.closeDialog() : keys.win.dialog("shortcuts") }
  Shortcut { sequence: "Ctrl+Shift+Y"; onActivated: keys.win.dialog("status") }
  Shortcut { sequence: "Ctrl+P"; onActivated: keys.win.dialogName === "account" ? keys.win.closeDialog() : keys.win.dialog("account") }
  Shortcut { sequence: "Ctrl+."; onActivated: { keys.ws.thread = null; keys.ws.profileUser = "" } }
  Shortcut { sequences: ["Ctrl+Shift+I", "Alt+I"]; onActivated: { var c = keys.ws.conv(keys.ws.current); if (!c) return; if (c.kind === "im") { keys.ws.profileUser = c.user; keys.ws.thread = null } else keys.win.dialog("details", { conv: keys.ws.current }) } }
  Shortcut { sequence: "Ctrl+Tab"; onActivated: keys.app.switchBy(1) }
  Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: keys.app.switchBy(-1) }
  Shortcut { sequence: "Ctrl+PgDown"; onActivated: keys.app.switchBy(1) }
  Shortcut { sequence: "Ctrl+PgUp"; onActivated: keys.app.switchBy(-1) }
  Repeater {
    model: 9
    delegate: Item {
      required property int index
      Shortcut { sequence: "Ctrl+" + (parent.index + 1); onActivated: { var a = keys.app.accounts[parent.index]; if (a) keys.app.switchTo(a.teamId) } }
    }
  }
  Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: keys.zoom(0.1) }
  Shortcut { sequence: "Ctrl+-"; onActivated: keys.zoom(-0.1) }
  Shortcut { sequence: "Ctrl+0"; onActivated: keys.zoom(0) }
  Shortcut {
    sequences: ["Ctrl+Shift+\\", "Ctrl+|"]
    onActivated: {
      var h = keys.ws.history(keys.ws.current)
      if (!h) return
      var list = h.msgs.filter(function(m) { return !m.subtype || m.subtype === "thread_broadcast" || m.subtype === "bot_message" })
      var m = list[list.length - 1]
      if (m) keys.win.emojiPicker(null, function(name) { keys.ws.react(keys.ws.current, m.ts, name) }, {})
    }
  }
  Shortcut { sequence: "Ctrl+R"; onActivated: { keys.ws.start(); keys.ws.loadDirectory(true); keys.win.toast(keys.app.tr("Reloading…", "Recarregando…")) } }
  Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: keys.app.hideWindow() }
}
