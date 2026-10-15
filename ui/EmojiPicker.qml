import QtQuick
import QtQuick.Controls
import QtQuick.Window
import qs.Ui
import "../lib/Emoji.js" as Emoji
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Slack's emoji picker: a card beside the button that opened it (or in the
// middle of the window), with the search field, the category bar, the grid
// of every emoji in sections whose headers stay on top while scrolling, the
// skin tone choice and a preview of the emoji under the mouse. Picking calls
// back with the Slack name ("+1::skin-tone-3") and closes.
Item {
  id: p
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme

  property bool shown: false
  visible: shown
  z: 860

  // ---------------------------------------------------------------- state
  property var pickCb: null
  property var opts: ({})
  property bool centered: true
  property rect anchorRect: Qt.rect(0, 0, 0, 0)   // in this item's coordinates
  property var prevFocus: null
  property string query: ""
  property var rows: []          // [{header, label, sec} | {items, start, sec}]
  property var flat: []          // every emoji shown, in order
  property var flatRow: []       // flat index -> row
  property var sections: []      // [{key, label, icon, row}]
  property int sel: -1           // selected index in `flat`
  property int curSec: 0         // section at the top of the grid
  property int jumpSec: -1       // section picked in the bar that can't reach the top (the last ones)
  readonly property int tabSec: jumpSec >= 0 ? jumpSec : curSec
  property real stickyY: 0
  property bool toneOpen: false
  property point lastHover: Qt.point(-1, -1)
  readonly property int tone: Math.max(0, Math.min(5, Number(app.setting("skinTone", 0)) || 0))
  readonly property bool searching: query !== ""
  readonly property var selItem: sel >= 0 && sel < flat.length ? flat[sel] : null

  // ---------------------------------------------------------------- metrics
  readonly property int cell: t.sp(36)
  readonly property int emojiSize: t.sp(24)
  readonly property int headerH: t.sp(30)
  readonly property int cols: Math.max(5, Math.floor((list.width - t.sp(4)) / cell))
  readonly property real gridX: Math.max(0, Math.floor((list.width - cols * cell) / 2))

  onColsChanged: if (p.shown) p.rebuild(false)
  onToneChanged: p.toneOpen = false
  onWidthChanged: if (p.shown) p.place()
  onHeightChanged: if (p.shown) p.place()

  Connections {
    target: p.ws
    ignoreUnknownSignals: true
    function onEmojiRevChanged() { if (p.shown) p.rebuild(false) }
  }

  // ---------------------------------------------------------------- api
  function openAt(anchorItem, onPick, opts) {
    p.pickCb = onPick || null
    p.opts = opts || {}
    p.centered = !anchorItem
    if (anchorItem) {
      var pt = anchorItem.mapToItem(p, 0, 0)
      p.anchorRect = Qt.rect(pt.x, pt.y, anchorItem.width, anchorItem.height)
    }
    var w = p.Window.window
    p.prevFocus = w ? w.activeFocusItem : null
    p.toneOpen = false
    p.sel = -1
    p.lastHover = Qt.point(-1, -1)
    p.query = ""
    field.text = ""
    p.shown = true
    p.place()
    p.rebuild(true)
    field.forceActiveFocus()
  }

  function close() {
    if (!p.shown) return
    p.shown = false
    p.toneOpen = false
    p.pickCb = null
    var f = p.prevFocus
    p.prevFocus = null
    try { if (f && f.visible) f.forceActiveFocus() } catch (e) {}
  }

  function pick(item) {
    if (!item) return
    var name = p.shownName(item)
    var cb = p.pickCb
    p.bump(item.name)
    p.close()
    if (cb) Qt.callLater(function() { cb(name) })
  }

  // ---------------------------------------------------------------- placement
  // Beside the anchor like Slack: above it and growing to the left, below
  // when there's no room above, kept inside the window.
  function place() {
    var m = t.sp(8), gap = t.sp(6)
    var cw = card.width, ch = card.height
    var W = p.width, H = p.height
    var a = p.anchorRect
    var x, y
    if (p.centered) {
      x = (W - cw) / 2
      y = (H - ch) / 2
    } else {
      x = a.x + a.width - cw
      if (x < m) x = a.x
      y = a.y - ch - gap
      if (y < m) {
        y = a.y + a.height + gap
        if (y + ch > H - m) {
          // Neither above nor below: beside it, to the left if possible.
          y = a.y + a.height / 2 - ch / 2
          x = a.x - cw - gap
          if (x < m) x = a.x + a.width + gap
        }
      }
    }
    card.x = Math.round(Math.max(m, Math.min(x, W - cw - m)))
    card.y = Math.round(Math.max(m, Math.min(y, H - ch - m)))
  }

  // ---------------------------------------------------------------- data
  // Slack's set stops at Unicode 15.0: newer emoji have no picture there and
  // can't be used as reactions, and a few gained skin tones Slack lacks.
  readonly property var notInSlack: ({
    head_shaking_horizontally: 1, head_shaking_vertically: 1, face_with_bags_under_eyes: 1, distorted_face: 1, fight_cloud: 1,
    hairy_creature: 1, person_walking_facing_right: 1, woman_walking_facing_right: 1, man_walking_facing_right: 1,
    person_kneeling_facing_right: 1, woman_kneeling_facing_right: 1, man_kneeling_facing_right: 1,
    person_with_white_cane_facing_right: 1, man_with_white_cane_facing_right: 1, woman_with_white_cane_facing_right: 1,
    person_in_motorized_wheelchair_facing_right: 1, man_in_motorized_wheelchair_facing_right: 1,
    woman_in_motorized_wheelchair_facing_right: 1, person_in_manual_wheelchair_facing_right: 1,
    man_in_manual_wheelchair_facing_right: 1, woman_in_manual_wheelchair_facing_right: 1, person_running_facing_right: 1,
    woman_running_facing_right: 1, man_running_facing_right: 1, ballet_dancer: 1, family_adult_adult_child: 1,
    family_adult_adult_child_child: 1, family_adult_child: 1, family_adult_child_child: 1, fingerprint: 1, phoenix: 1,
    orca: 1, leafless_tree: 1, lime: 1, brown_mushroom: 1, root_vegetable: 1, landslide: 1, trombone: 1, harp: 1,
    treasure_chest: 1, broken_chain: 1, shovel: 1, splatter: 1, "flag-sark": 1
  })
  readonly property var noTonesInSlack: ({
    dancers: 1, "men-with-bunny-ears-partying": 1, "women-with-bunny-ears-partying": 1, wrestlers: 1, "man-wrestling": 1, "woman-wrestling": 1
  })
  readonly property var icons: ({
    frequent: "󰅐", smileys: "󰇲", people: "󱠢", nature: "󰌪", food: "󰲄", travel: "󱓭", activities: "󰒸",
    objects: "󰌶", symbols: "󰋕", flags: "󰈽", custom: "󰒱"
  })
  function usable(it) {
    if (!it || p.notInSlack[it.name]) return false
    if (it.tones && p.noTonesInSlack[it.name]) it.tones = false
    return true
  }

  property var _cat: null
  property string _catKey: ""
  function catalogue() {
    var key = (p.app ? p.app.lang : "en") + "|" + (p.ws ? p.ws.teamId + "|" + p.ws.emojiRev : "")
    if (!p._cat || p._catKey !== key) {
      var cat = Emoji.catalogue(p.ws ? p.ws.customEmoji : {}, p.app.lang)
      for (var i = 0; i < cat.length; i++) {
        cat[i].items = cat[i].items.filter(p.usable)
        cat[i].icon = p.icons[cat[i].key] || cat[i].icon
      }
      p._cat = cat
      p._catKey = key
    }
    return p._cat
  }

  function usage() {
    var u = p.app.setting("emojiUsage", {})
    return u && typeof u === "object" ? u : {}
  }

  // name -> {n: times picked, t: last pick (unix s)}; bare numbers read as counts.
  function used(u, name) {
    var e = u[name]
    if (typeof e === "number") return { n: e, t: 0 }
    return e && typeof e === "object" ? { n: Number(e.n) || 0, t: Number(e.t) || 0 } : { n: 0, t: 0 }
  }

  function bump(base) {
    base = String(base || "").split("::")[0]
    if (!base) return
    var u = U.copy(p.usage())
    u[base] = { n: p.used(u, base).n + 1, t: Math.floor(Date.now() / 1000) }
    var keys = Object.keys(u)
    if (keys.length > 150) {
      keys.sort(function(a, b) { var x = p.used(u, a), y = p.used(u, b); return x.n - y.n || x.t - y.t })
      for (var i = 0; i < keys.length - 150; i++) delete u[keys[i]]
    }
    p.app.setSetting("emojiUsage", u)
  }

  function itemFor(name) {
    var r = Emoji.resolve(name, p.ws ? p.ws.customEmoji : null, p.ws ? p.ws.emojiAliases : null)
    if (!r) return null
    if (r.url) return { name: name, url: r.url }
    var it = { name: name, glyph: r.glyph, tones: Emoji.hasTones(name) }
    return p.usable(it) ? it : null
  }

  // The most used ones (counted on every pick, the latest first among
  // equals), topped up with Slack's usual suspects: two full rows.
  function frequent() {
    var u = p.usage()
    var max = Math.max(16, p.cols * 2)
    var names = Object.keys(u).sort(function(a, b) {
      var x = p.used(u, a), y = p.used(u, b)
      if (x.n !== y.n) return y.n - x.n
      if (x.t !== y.t) return y.t - x.t
      var fa = Emoji.FREQUENT.indexOf(a), fb = Emoji.FREQUENT.indexOf(b)
      if (fa !== fb) return (fa < 0 ? 999 : fa) - (fb < 0 ? 999 : fb)
      return a < b ? -1 : 1
    })
    var out = [], seen = {}
    function add(n) {
      if (out.length >= max || seen[n]) return
      var it = p.itemFor(n)
      if (!it) return
      seen[n] = true
      out.push(it)
    }
    names.forEach(add)
    Emoji.FREQUENT.forEach(add)
    return out
  }

  function shownName(it) {
    return it && it.tones && p.tone > 0 ? it.name + "::skin-tone-" + (p.tone + 1) : (it ? it.name : "")
  }

  // Lays the emoji out in rows of `cols`, with a header row per section
  // (none while searching).
  function rebuild(resetScroll) {
    var rows = [], flat = [], flatRow = [], secs = []
    var cols = p.cols
    function addItems(items, sec) {
      for (var i = 0; i < items.length; i += cols) {
        var chunk = items.slice(i, i + cols)
        var r = { key: "r" + rows.length, items: chunk, start: flat.length, sec: sec }
        for (var j = 0; j < chunk.length; j++) { flat.push(chunk[j]); flatRow.push(rows.length) }
        rows.push(r)
      }
    }
    if (p.searching) {
      var found = Emoji.search(p.query, p.ws ? p.ws.customEmoji : null, p.ws ? p.ws.emojiAliases : null, 90).filter(p.usable).slice(0, 60)
      addItems(found, 0)
    } else {
      var cat = p.catalogue()
      for (var g = 0; g < cat.length; g++) {
        var items = cat[g].key === "frequent" ? p.frequent() : cat[g].items
        if (!items.length) continue
        secs.push({ key: cat[g].key, label: cat[g].label, icon: cat[g].icon, row: rows.length })
        rows.push({ key: "h" + cat[g].key, header: true, label: cat[g].label, sec: secs.length - 1 })
        addItems(items, secs.length - 1)
      }
    }
    if (!p.searching) p.sections = secs
    p.flat = flat
    p.flatRow = flatRow
    p.rows = rows
    p.sel = p.searching && flat.length ? 0 : -1
    p.jumpSec = -1
    if (resetScroll !== false || p.searching) list.positionViewAtBeginning()
    Qt.callLater(p.syncSticky)
  }

  function jumpTo(i) {
    if (p.searching) { field.text = "" }
    var s = p.sections[i]
    if (!s || s.row < 0) return
    list.positionViewAtIndex(s.row, ListView.Beginning)
    p.curSec = i
    p.jumpSec = list.atYEnd ? i : -1
    Qt.callLater(p.syncSticky)
  }

  // The section header pinned on top, pushed up by the next one.
  function syncSticky() {
    if (!list.atYEnd) p.jumpSec = -1
    if (p.searching || !p.rows.length) { p.stickyY = 0; return }
    var top = list.indexAt(p.gridX + 2, list.contentY + 1)
    if (top < 0) return
    var r = p.rows[top]
    if (r) p.curSec = r.sec
    var y = 0
    for (var i = top + 1; i < Math.min(p.rows.length, top + 3); i++) {
      if (!p.rows[i].header) continue
      var it = list.itemAtIndex(i)
      if (it) {
        var d = it.y - list.contentY
        if (d < p.headerH) y = d - p.headerH
      }
      break
    }
    p.stickyY = y
  }

  // ---------------------------------------------------------------- keyboard
  function move(dx, dy, wrap) {
    var n = p.flat.length
    if (!n) return
    if (p.sel < 0) { p.sel = 0; p.reveal(); return }
    if (dx) {
      var s = p.sel + dx
      p.sel = wrap ? (s + n) % n : Math.max(0, Math.min(n - 1, s))
    } else {
      var r = p.flatRow[p.sel]
      var col = p.sel - p.rows[r].start
      var tr = r + dy
      while (tr >= 0 && tr < p.rows.length && p.rows[tr].header) tr += dy
      if (tr < 0 || tr >= p.rows.length) return
      var row = p.rows[tr]
      p.sel = row.start + Math.min(col, row.items.length - 1)
    }
    p.reveal()
  }

  function reveal() {
    var r = p.flatRow[p.sel]
    if (r === undefined) return
    list.positionViewAtIndex(r, ListView.Contain)
    var it = list.itemAtIndex(r)
    var cover = p.searching ? 0 : p.headerH
    if (it && it.y < list.contentY + cover) {
      if (r > 0 && p.rows[r - 1].header) list.positionViewAtIndex(r - 1, ListView.Beginning)
      else list.contentY = Math.max(list.originY, it.y - cover)
    }
    Qt.callLater(p.syncSticky)
  }

  function hoverCell(row, item, mx, my) {
    var g = item.mapToItem(p, mx, my)
    if (g.x === p.lastHover.x && g.y === p.lastHover.y) return
    p.lastHover = Qt.point(g.x, g.y)
    var col = Math.floor((mx - p.gridX) / p.cell)
    if (col >= 0 && col < row.items.length) p.sel = row.start + col
  }

  // ---------------------------------------------------------------- outside
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: p.close()
    onWheel: wheel => {}
  }

  // ---------------------------------------------------------------- card
  BorderSurface {
    id: card
    width: Math.min(p.t.sp(360), p.width - p.t.sp(16))
    height: Math.min(p.t.sp(424), p.height - p.t.sp(16))
    color: p.t.popup
    borderSpec: p.t.popupBorder
    radius: Math.max(8, p.t.radiusCard)
    clip: true

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: p.toneOpen = false
      onWheel: wheel => {}
    }

    // ------------------------------------------------ search + skin tone
    Item {
      id: head
      x: p.t.sp(10)
      y: p.t.sp(10)
      width: card.width - p.t.sp(20)
      height: field.implicitHeight

      SField {
        id: field
        app: p.app
        icon: "󰍉"
        width: parent.width - toneBtn.width - p.t.sp(8)
        placeholderText: p.app.tr("Search all emoji", "Buscar todos os emoji")
        onTextChanged: {
          var q = text.replace(/:/g, "").trim().toLowerCase()
          if (q === p.query) return
          p.query = q
          p.rebuild(true)
        }
        Keys.onPressed: event => {
          var k = event.key
          if (k === Qt.Key_Escape) { if (p.toneOpen) p.toneOpen = false; else p.close() }
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) p.pick(p.selItem || p.flat[0])
          else if (k === Qt.Key_Up) p.move(0, -1)
          else if (k === Qt.Key_Down) p.move(0, 1)
          else if (k === Qt.Key_Left) p.move(-1, 0)
          else if (k === Qt.Key_Right) p.move(1, 0)
          else if (k === Qt.Key_Tab) p.move(1, 0, true)
          else if (k === Qt.Key_Backtab) p.move(-1, 0, true)
          else if (k === Qt.Key_PageDown) { list.flick(0, -p.t.sp(2400)) }
          else if (k === Qt.Key_PageUp) { list.flick(0, p.t.sp(2400)) }
          else if (k === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) field.text = ""
          else return
          event.accepted = true
        }
      }

      Rectangle {
        id: toneBtn
        anchors.right: parent.right
        width: field.height
        height: field.height
        radius: Math.max(4, p.t.radiusSmall)
        color: toneMa.pressed ? p.t.press : (toneMa.containsMouse || p.toneOpen ? p.t.hoverStrong : "transparent")
        border.width: 1
        border.color: p.toneOpen ? p.t.accent : p.t.lineStrong
        EmojiIcon {
          app: p.app
          anchors.centerIn: parent
          name: p.tone > 0 ? "hand::skin-tone-" + (p.tone + 1) : "hand"
          size: p.t.sp(20)
        }
        MouseArea {
          id: toneMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: p.toneOpen = !p.toneOpen
        }
        PanelToolTip { visible: toneMa.containsMouse && !p.toneOpen; text: p.app.tr("Skin tone", "Tom de pele") }
      }
    }

    // ------------------------------------------------ categories
    Item {
      id: tabs
      x: p.t.sp(6)
      anchors.top: head.bottom
      anchors.topMargin: p.t.sp(8)
      width: card.width - p.t.sp(12)
      height: p.t.sp(34)

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        height: parent.height
        Repeater {
          model: p.sections
          delegate: Item {
            id: tab
            required property var modelData
            required property int index
            readonly property bool current: !p.searching && p.tabSec === index
            width: Math.floor(tabs.width / Math.max(1, p.sections.length))
            height: tabs.height
            Rectangle {
              anchors.centerIn: parent
              width: Math.min(parent.width - p.t.sp(2), p.t.sp(30))
              height: p.t.sp(28)
              radius: Math.max(4, p.t.radiusSmall)
              color: tabMa.pressed ? p.t.press : (tabMa.containsMouse ? p.t.hover : "transparent")
            }
            Glyph {
              app: p.app
              anchors.centerIn: parent
              icon: tab.modelData.icon || ""
              size: p.t.fsIcon + 1
              color: tab.current || tabMa.containsMouse ? p.t.fgBright : p.t.fgDim
            }
            Rectangle {
              visible: tab.current
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width - p.t.sp(6), p.t.sp(24))
              height: 2
              radius: 1
              color: p.t.accent
            }
            MouseArea {
              id: tabMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: p.jumpTo(tab.index)
            }
            PanelToolTip { visible: tabMa.containsMouse; text: tab.modelData.label }
          }
        }
      }
      Rectangle { anchors.bottom: parent.bottom; x: -p.t.sp(6); width: card.width; height: 1; color: p.t.line }
    }

    // ------------------------------------------------ grid
    ListView {
      id: list
      x: p.t.sp(6)
      anchors.top: tabs.bottom
      anchors.bottom: foot.top
      width: card.width - p.t.sp(12)
      clip: true
      model: p.rows
      topMargin: p.searching ? p.t.sp(6) : 0
      bottomMargin: p.t.sp(6)
      boundsBehavior: Flickable.StopAtBounds
      cacheBuffer: p.t.sp(240)
      flickDeceleration: 3000
      maximumFlickVelocity: 5000
      ScrollBar.vertical: ThinScroll { app: p.app }
      onContentYChanged: p.syncSticky()
      onHeightChanged: Qt.callLater(p.syncSticky)

      delegate: Item {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool header: modelData.header === true
        readonly property int at: header ? -1 : p.sel - modelData.start
        width: list.width
        height: header ? p.headerH : p.cell

        Text {
          visible: rowItem.header
          x: p.gridX + p.t.sp(6)
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: rowItem.header ? rowItem.modelData.label : ""
          color: p.t.fgSoft
          font.family: p.t.font
          font.pixelSize: p.t.fsSmall
          font.bold: true
        }

        Rectangle {
          visible: !rowItem.header && rowItem.at >= 0 && rowItem.at < rowItem.modelData.items.length
          x: p.gridX + Math.max(0, rowItem.at) * p.cell
          width: p.cell
          height: p.cell
          radius: Math.max(6, p.t.radiusSmall)
          color: p.t.hoverStrong
        }

        Repeater {
          model: rowItem.header ? [] : rowItem.modelData.items
          delegate: EmojiIcon {
            required property var modelData
            required property int index
            app: p.app
            ws: p.ws
            name: p.shownName(modelData)
            size: p.emojiSize
            x: p.gridX + index * p.cell + (p.cell - p.emojiSize) / 2
            y: (p.cell - p.emojiSize) / 2
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: !rowItem.header
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: mouse => p.hoverCell(rowItem.modelData, rowItem, mouse.x, mouse.y)
          onClicked: mouse => {
            var col = Math.floor((mouse.x - p.gridX) / p.cell)
            if (col >= 0 && col < rowItem.modelData.items.length) p.pick(rowItem.modelData.items[col])
          }
        }
      }
    }

    // Nothing matches the search.
    Column {
      anchors.centerIn: list
      width: list.width - p.t.sp(40)
      spacing: p.t.sp(10)
      visible: p.searching && p.flat.length === 0
      EmojiIcon { app: p.app; name: "face_with_monocle"; size: p.t.sp(40); anchors.horizontalCenter: parent.horizontalCenter }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: p.app.tr("No emoji found for “", "Nenhum emoji encontrado para “") + p.query + "”"
        color: p.t.fgDim
        font.family: p.t.font
        font.pixelSize: p.t.fsSmall + 1
      }
    }

    // The current section's header, pinned on top of the grid.
    Item {
      x: list.x
      y: list.y
      width: list.width - p.t.sp(8)
      height: p.headerH
      clip: true
      visible: !p.searching && p.sections.length > 0 && list.contentY > list.originY + 0.5
      Rectangle {
        y: p.stickyY
        width: parent.width
        height: p.headerH
        color: p.t.popup
        Text {
          x: p.gridX + p.t.sp(6)
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: p.sections[p.curSec] ? p.sections[p.curSec].label : ""
          color: p.t.fgSoft
          font.family: p.t.font
          font.pixelSize: p.t.fsSmall
          font.bold: true
        }
      }
    }

    // ------------------------------------------------ preview footer
    Item {
      id: foot
      anchors.bottom: parent.bottom
      width: card.width
      height: p.t.sp(58)
      Rectangle { width: parent.width; height: 1; color: p.t.line }

      readonly property var it: p.selItem
      readonly property var std: it && it.glyph ? Emoji.entry(it.name) : null

      EmojiIcon {
        id: big
        visible: !!foot.it
        app: p.app
        ws: p.ws
        x: p.t.sp(14)
        anchors.verticalCenter: parent.verticalCenter
        name: foot.it ? p.shownName(foot.it) : "grinning"
        size: p.t.sp(34)
      }
      Column {
        anchors.left: foot.it ? big.right : parent.left
        anchors.leftMargin: p.t.sp(foot.it ? 12 : 16)
        anchors.right: parent.right
        anchors.rightMargin: p.t.sp(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: p.t.sp(2)
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: foot.it ? ":" + foot.it.name + ":" : p.app.tr("Pick an emoji", "Escolha um emoji")
          color: foot.it ? p.t.fgBright : p.t.fgSoft
          font.family: p.t.font
          font.pixelSize: p.t.fsText
          font.bold: true
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: {
            var it = foot.it
            if (!it) return p.app.tr("Arrows move · Enter picks · Esc closes", "Setas movem · Enter escolhe · Esc fecha")
            if (it.url) return p.app.tr("Custom emoji", "Emoji personalizado")
            var e = foot.std
            if (!e) {
              var of = Emoji.shortcodeOf(it.glyph)
              return of ? p.app.tr("Alias of :", "Apelido de :") + of + ":" : ""
            }
            var others = e[1].split(" ").filter(function(n) { return n !== it.name }).map(function(n) { return ":" + n + ":" })
            return (others.length ? others.join(" ") + "  ·  " : "") + e[3]
          }
          color: p.t.fgDim
          font.family: p.t.font
          font.pixelSize: p.t.fsSmall
        }
      }
    }

    // ------------------------------------------------ skin tone choice
    BorderSurface {
      id: toneCard
      visible: p.toneOpen
      z: 5
      anchors.right: head.right
      y: head.y + head.height + p.t.sp(4)
      width: toneRow.implicitWidth + p.t.sp(12)
      height: toneRow.implicitHeight + p.t.sp(12)
      color: p.t.popup
      borderSpec: p.t.popupBorder
      radius: Math.max(6, p.t.radiusCard)
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
      Row {
        id: toneRow
        anchors.centerIn: parent
        spacing: p.t.sp(2)
        Repeater {
          model: 6
          delegate: Rectangle {
            id: toneOpt
            required property int index
            width: p.t.sp(34)
            height: width
            radius: Math.max(6, p.t.radiusSmall)
            color: optMa.containsMouse ? p.t.hoverStrong : (p.tone === index ? p.t.alpha(p.t.accent, 0.22) : "transparent")
            border.width: p.tone === index ? 1 : 0
            border.color: p.t.accent
            EmojiIcon {
              app: p.app
              anchors.centerIn: parent
              name: toneOpt.index > 0 ? "hand::skin-tone-" + (toneOpt.index + 1) : "hand"
              size: p.t.sp(22)
            }
            MouseArea {
              id: optMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { p.app.setSetting("skinTone", toneOpt.index); p.toneOpen = false; field.forceActiveFocus() }
            }
            PanelToolTip {
              visible: optMa.containsMouse
              text: [p.app.tr("Default", "Padrão"), p.app.tr("Light", "Clara"), p.app.tr("Medium-light", "Média-clara"),
                     p.app.tr("Medium", "Média"), p.app.tr("Medium-dark", "Média-escura"), p.app.tr("Dark", "Escura")][toneOpt.index]
            }
          }
        }
      }
    }
  }
}
