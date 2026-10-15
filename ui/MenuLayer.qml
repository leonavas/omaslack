import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
import "../lib/Registry.js" as Reg

// Context menus over the whole window: a stack of cards, submenus opening
// beside their row. Items: {label, icon, hint, action(), danger, checked,
// enabled, sub: [items]}, {separator: true}, {header: "…"} (a group's
// label), {title: "…"} (the menu's name, on top),
// {reactions: ["white_check_mark", …], ws, action(name)} (`ws` draws the
// workspace's custom ones). Closed, the keyboard
// goes back where it was.
Item {
  id: menuLayer
  property var app: Reg.service
  readonly property var t: app.theme
  property var stack: []        // [{items, x, y, w}]
  property int hot: -1          // keyboard row in the last card
  property var prevFocus: null
  readonly property bool shown: stack.length > 0
  visible: shown
  z: 900

  function open(items, x, y) {
    if (!menuLayer.shown) { var w = menuLayer.Window.window; menuLayer.prevFocus = w ? w.activeFocusItem : null }
    menuLayer.stack = [{ items: items, x: x, y: y }]
    menuLayer.hot = -1
    menuLayer.forceActiveFocus()
  }
  function close() {
    var f = menuLayer.prevFocus
    menuLayer.prevFocus = null
    menuLayer.stack = []
    menuLayer.hot = -1
    try { if (f && f !== menuLayer && f.visible) f.forceActiveFocus() } catch (e) {}
  }
  function openSub(level, items, x, y) {
    var s = menuLayer.stack.slice(0, level + 1)
    s.push({ items: items, x: x, y: y })
    menuLayer.stack = s
  }
  function trim(level) { if (menuLayer.stack.length > level + 1) menuLayer.stack = menuLayer.stack.slice(0, level + 1) }
  function run(item) {
    if (!item || item.enabled === false || item.sub) return
    menuLayer.close()
    if (item.action) Qt.callLater(item.action)
  }

  // The card's width: its longest row.
  FontMetrics { id: labelMetrics; font.family: menuLayer.t.font; font.pixelSize: menuLayer.t.fsText - 1 }
  FontMetrics { id: hintMetrics; font.family: menuLayer.t.font; font.pixelSize: menuLayer.t.fsSmall }
  function measure(items) {
    var w = menuLayer.t.sp(200)
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it.reactions) { w = Math.max(w, it.reactions.length * menuLayer.t.sp(38) + menuLayer.t.sp(20)); continue }
      var label = labelMetrics.advanceWidth(it.label || it.header || it.title || "")
      var hint = hintMetrics.advanceWidth(it.sub ? "›" : (it.hint || ""))
      w = Math.max(w, label + hint + menuLayer.t.sp(it.header !== undefined || it.title !== undefined ? 40 : 80))
    }
    return Math.min(Math.round(w), menuLayer.t.sp(420))
  }

  Keys.onEscapePressed: menuLayer.close()
  Keys.onUpPressed: menuLayer.move(-1)
  Keys.onDownPressed: menuLayer.move(1)
  Keys.onReturnPressed: { var s = menuLayer.stack[menuLayer.stack.length - 1]; if (s && menuLayer.hot >= 0) menuLayer.run(s.items[menuLayer.hot]) }
  function move(d) {
    var s = menuLayer.stack[menuLayer.stack.length - 1]
    if (!s) return
    var n = s.items.length
    for (var k = 0; k < n; k++) {
      menuLayer.hot = (menuLayer.hot + d + n) % n
      var it = s.items[menuLayer.hot]
      if (!it.separator && it.header === undefined && it.title === undefined && !it.reactions && it.enabled !== false) return
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: menuLayer.close()
    onWheel: wheel => menuLayer.close()
  }

  Repeater {
    model: menuLayer.stack
    delegate: BorderSurface {
      id: card
      required property var modelData
      required property int index
      readonly property int level: index
      color: menuLayer.t.popup
      borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, 1)
      radius: Math.max(6, menuLayer.t.radiusCard)
      width: menuLayer.measure(modelData.items)
      height: col.implicitHeight + menuLayer.t.sp(12)
      x: Math.max(4, Math.min(modelData.x, menuLayer.width - width - 4))
      y: Math.max(4, Math.min(modelData.y, menuLayer.height - height - 4))

      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

      Column {
        id: col
        x: menuLayer.t.sp(6)
        y: menuLayer.t.sp(6)
        width: card.width - menuLayer.t.sp(12)

        Repeater {
          model: card.modelData.items
          delegate: Loader {
            id: row
            required property var modelData
            required property int index
            width: col.width
            sourceComponent: modelData.separator ? sepC : (modelData.title !== undefined ? titleC : (modelData.header !== undefined ? headC : (modelData.reactions ? reactC : itemC)))

            Component {
              id: sepC
              Item { height: menuLayer.t.sp(9); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: menuLayer.t.line } }
            }
            Component {
              id: headC
              Text {
                text: row.modelData.header
                textFormat: Text.PlainText
                color: menuLayer.t.fgDim
                font.family: menuLayer.t.font
                font.pixelSize: menuLayer.t.fsSmall
                font.bold: true
                leftPadding: menuLayer.t.sp(12)
                topPadding: menuLayer.t.sp(4)
                bottomPadding: menuLayer.t.sp(4)
                elide: Text.ElideRight
                width: col.width
              }
            }
            Component {
              id: titleC
              Text {
                text: row.modelData.title
                textFormat: Text.PlainText
                color: menuLayer.t.fgBright
                font.family: menuLayer.t.font
                font.pixelSize: menuLayer.t.fsText
                font.bold: true
                leftPadding: menuLayer.t.sp(12)
                rightPadding: menuLayer.t.sp(12)
                topPadding: menuLayer.t.sp(6)
                bottomPadding: menuLayer.t.sp(6)
                elide: Text.ElideRight
                width: col.width
              }
            }
            Component {
              id: reactC
              Row {
                spacing: menuLayer.t.sp(4)
                leftPadding: menuLayer.t.sp(6)
                bottomPadding: menuLayer.t.sp(4)
                Repeater {
                  model: row.modelData.reactions
                  delegate: Rectangle {
                    required property var modelData
                    width: menuLayer.t.sp(34); height: width; radius: width / 2
                    color: rma.containsMouse ? menuLayer.t.hoverStrong : menuLayer.t.hover
                    EmojiIcon { anchors.centerIn: parent; app: menuLayer.app; ws: row.modelData.ws || null; name: parent.modelData; size: menuLayer.t.sp(18) }
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: { var f = row.modelData.action; var n = parent.modelData; menuLayer.close(); Qt.callLater(function() { f(n) }) } }
                  }
                }
              }
            }
            Component {
              id: itemC
              Rectangle {
                readonly property var it: row.modelData
                readonly property bool hot: ima.containsMouse || (menuLayer.hot === row.index && card.level === menuLayer.stack.length - 1)
                readonly property bool on: it.enabled !== false
                height: menuLayer.t.sp(30)
                radius: Math.max(4, menuLayer.t.radiusSmall)
                color: hot && on ? (it.danger ? menuLayer.t.red : menuLayer.t.accent) : "transparent"
                readonly property color ink: hot && on ? menuLayer.t.onColor(it.danger ? menuLayer.t.red : menuLayer.t.accent) : (it.danger ? menuLayer.t.red : menuLayer.t.fg)
                opacity: on ? 1 : 0.45
                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: menuLayer.t.sp(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: menuLayer.t.sp(10)
                  Glyph {
                    app: menuLayer.app
                    width: menuLayer.t.sp(16)
                    visible: !!parent.parent.it.icon || parent.parent.it.checked !== undefined
                    icon: parent.parent.it.checked !== undefined ? (parent.parent.it.checked ? "󰄬" : "") : (parent.parent.it.icon || "")
                    color: parent.parent.ink
                    size: menuLayer.t.fsIcon - 1
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: parent.parent.it.label
                    textFormat: Text.PlainText
                    color: parent.parent.ink
                    font.family: menuLayer.t.font
                    font.pixelSize: menuLayer.t.fsText - 1
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: menuLayer.t.sp(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: parent.it.sub ? "›" : (parent.it.hint || "")
                  textFormat: Text.PlainText
                  color: parent.hot && parent.on ? parent.ink : menuLayer.t.fgDim
                  font.family: menuLayer.t.font
                  font.pixelSize: parent.it.sub ? menuLayer.t.fsTitle : menuLayer.t.fsSmall
                }
                MouseArea {
                  id: ima
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onEntered: {
                    menuLayer.hot = -1
                    if (parent.it.sub && parent.on) {
                      var p = parent.mapToItem(menuLayer, parent.width + menuLayer.t.sp(10), -menuLayer.t.sp(6))
                      menuLayer.openSub(card.level, parent.it.sub, p.x, p.y)
                    } else menuLayer.trim(card.level)
                  }
                  onClicked: menuLayer.run(parent.it)
                }
              }
            }
          }
        }
      }
    }
  }
}
