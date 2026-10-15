import QtQuick
import "../lib/Registry.js" as Reg

// Loads the dialog asked for ("details" → DlgDetails.qml) over the window.
Item {
  id: host
  property var app: Reg.service
  property var win
  property var ws
  property string name: ""
  z: 800
  visible: name !== ""

  function show(n, args) {
    var file = "Dlg" + n.charAt(0).toUpperCase() + n.slice(1) + ".qml"
    host.name = ""
    loader.setSource(file, { app: host.app, win: host.win, ws: host.ws, args: args || {} })
    host.name = n
  }
  function hide() { host.name = ""; loader.source = "" }

  Loader {
    id: loader
    anchors.fill: parent
    focus: true
    onLoaded: { item.closed.connect(host.hide); item.forceActiveFocus() }
    onStatusChanged: if (status === Loader.Error) { console.warn("omaslack: dialog failed to load:", source); host.name = "" }
  }
}
