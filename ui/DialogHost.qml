import QtQuick
import QtQuick.Window
import "../lib/Registry.js" as Reg

// Loads the dialog asked for ("details" → DlgDetails.qml) over the window.
// Closed, the keyboard goes back where it was (the message box, a selected
// message).
Item {
  id: host
  property var app: Reg.service
  property var win
  property var ws
  property string name: ""
  property var prevFocus: null
  z: 800
  visible: name !== ""

  function show(n, args) {
    var file = "Dlg" + n.charAt(0).toUpperCase() + n.slice(1) + ".qml"
    // One dialog opening another keeps what had the keyboard before the first.
    if (host.name === "") { var w = host.Window.window; host.prevFocus = w ? w.activeFocusItem : null }
    host.name = ""
    loader.setSource(file, { app: host.app, win: host.win, ws: host.ws, args: args || {} })
    host.name = n
  }
  function hide() {
    host.name = ""
    loader.source = ""
    var f = host.prevFocus
    host.prevFocus = null
    try { if (f && f.visible) f.forceActiveFocus() } catch (e) {}
  }

  Loader {
    id: loader
    anchors.fill: parent
    focus: true
    onLoaded: { item.closed.connect(host.hide); item.forceActiveFocus() }
    onStatusChanged: if (status === Loader.Error) { console.warn("omaslack: dialog failed to load:", source); host.name = "" }
  }
}
