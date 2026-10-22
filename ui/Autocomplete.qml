import QtQuick
import QtQuick.Controls
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// The suggestions over the message box: `:emoji`, `@people`, `#channels`,
// `/commands`, picked with ↑ ↓ and Enter/Tab. `text` is the box's plain
// text (the rich text box hands it in, pills masked so a name already
// picked doesn't match again); positions are the input's.
Rectangle {
  id: ac
  property var app: Reg.service
  property var ws
  property var input
  property string text: input ? input.text : ""
  property string conv: ""
  property string threadTs: ""
  property var kinds: ["command", "emoji", "user", "channel"]   // what it suggests
  readonly property var t: app.theme
  property var items: []
  property int sel: 0
  property string kind: ""
  property int start: -1
  property string dismissedFor: ""
  signal chose(int start, int end, string label, string wire)

  visible: items.length > 0
  height: Math.min(list.contentHeight, t.sp(300)) + t.sp(36)
  radius: Math.max(8, t.radiusCard)
  color: t.popup
  border.width: 1
  border.color: t.lineStrong
  z: 50

  function dismiss() { ac.dismissedFor = ac.kind + ac.start; ac.items = [] }
  function move(d) { if (ac.items.length) ac.sel = (ac.sel + d + ac.items.length) % ac.items.length }

  function pick() {
    var it = ac.items[ac.sel]
    if (!it) return false
    var end = ac.input.cursorPosition
    if (ac.kind === "emoji") ac.chose(ac.start, end, ":" + it.name + ":", "")
    else if (ac.kind === "user") ac.chose(ac.start, end, it.label, it.wire)
    else if (ac.kind === "channel") ac.chose(ac.start, end, "#" + it.name, "<#" + it.id + ">")
    else if (ac.kind === "command") ac.chose(ac.start, end, it.name, "")
    ac.items = []
    return true
  }

  function update() {
    if (!ac.input || !ac.ws) return
    var text = ac.text
    var p = ac.input.cursorPosition
    var before = text.slice(0, p)
    var m
    // /command at the very start.
    if ((m = before.match(/^\/([a-z0-9_\-]*)$/i))) return ac.show("command", 0, m[1])
    if ((m = before.match(/(^|\s):([A-Za-z0-9_+'\-]{2,})$/))) return ac.show("emoji", p - m[2].length - 1, m[2])
    if ((m = before.match(/(^|\s)@([^\s@]{0,30}(?: [^\s@]{1,30}){0,2})$/))) return ac.show("user", p - m[2].length - 1, m[2])
    if ((m = before.match(/(^|\s)#([^\s#]{0,40})$/))) return ac.show("channel", p - m[2].length - 1, m[2])
    ac.items = []
  }

  function show(kind, start, q) {
    if (ac.kinds.indexOf(kind) < 0) { ac.items = []; return }
    if (ac.dismissedFor === kind + start) { ac.items = []; return }
    ac.kind = kind
    ac.start = start
    ac.sel = 0
    var w = ac.ws
    var out = []
    if (kind === "emoji") {
      out = Emoji.search(q, w.customEmoji, w.emojiAliases, 20, w.frequentEmoji)
    } else if (kind === "user") {
      var users = w.users
      var ranked = []
      for (var id in users) {
        var u = users[id]
        if (u.deleted) continue
        var r = Math.min.apply(null, [U.rank(u.name || "", q), U.rank(u.real || "", q), U.rank(u.handle || "", q)].map(function(x) { return x < 0 ? 99 : x }))
        if (q && r === 99) continue
        ranked.push({ id: id, rank: q ? r : 0, bot: !!u.bot, name: u.name })
      }
      ranked.sort(function(a, b) { return a.rank - b.rank || (a.bot - b.bot) || (a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1) })
      out = ranked.slice(0, 8).map(function(x) {
        var u = users[x.id]
        return { kind: "user", id: x.id, label: "@" + u.name, wire: "<@" + x.id + ">", name: u.name, detail: u.real && u.real !== u.name ? u.real : (u.handle || "") }
      })
      var c = w.conv(ac.conv)
      if (c && c.kind !== "im" && c.kind !== "mpim" && q) {
        ["here", "channel", "everyone"].forEach(function(b) {
          if (b.indexOf(q.toLowerCase()) === 0) out.push({ kind: "broadcast", id: b, label: "@" + b, wire: "<!" + b + ">", name: "@" + b,
            detail: b === "here" ? ac.app.tr("Notify every online member", "Notifica quem está online") : ac.app.tr("Notify everyone in this channel", "Notifica todos no canal") })
        })
      }
    } else if (kind === "channel") {
      var list = []
      for (var cid in w.convs) {
        var cc = w.convs[cid]
        if ((cc.kind !== "channel" && cc.kind !== "private") || cc.archived) continue
        var rr = q ? U.rank(cc.name, q) : 5
        if (rr < 0) continue
        list.push({ id: cid, name: cc.name, private: cc.kind === "private", rank: rr })
      }
      list.sort(function(a, b) { return a.rank - b.rank || (a.name < b.name ? -1 : 1) })
      out = list.slice(0, 8)
    } else if (kind === "command") {
      var cmds = w.commands.filter(function(cmd) { return !cmd.aliasOf && (!ac.threadTs || cmd.inThread) && cmd.name.indexOf("/" + q.toLowerCase()) === 0 })
      if (!cmds.length && !w.commands.length) cmds = ["/away", "/active", "/dnd", "/me", "/msg", "/shrug", "/status", "/topic", "/open"].filter(function(n) { return n.indexOf("/" + q) === 0 }).map(function(n) { return { name: n, usage: "", desc: "" } })
      out = cmds.slice(0, 10)
    }
    ac.items = out
  }

  // An emoji's :name: with what matched lit, as Slack does: yellow on the
  // list, bold and underlined on the chosen row (the yellow would vanish
  // into its color).
  function litName(it, chosen) {
    var name = String(it.name || ""), hl = it.hl || [], out = "", at = 0
    var on = chosen ? "<b><u>" : "<span style=\"color:" + ac.t.html.meText + ";background-color:" + ac.t.html.meBg + ";\">"
    var off = chosen ? "</u></b>" : "</span>"
    hl.forEach(function(r) {
      if (r[0] < at) return
      out += U.escapeHtml(name.slice(at, r[0])) + on + U.escapeHtml(name.slice(r[0], r[1])) + off
      at = r[1]
    })
    return ":" + out + U.escapeHtml(name.slice(at)) + ":"
  }

  Text {
    id: title
    x: ac.t.sp(14)
    y: ac.t.sp(8)
    text: ac.kind === "emoji" ? ac.app.tr("Emoji matching ", "Emoji com ") + ":" + ac.text.slice(ac.start + 1, ac.input.cursorPosition)
        : ac.kind === "user" ? ac.app.tr("People", "Pessoas")
        : ac.kind === "channel" ? ac.app.tr("Channels", "Canais") : ac.app.tr("Shortcuts", "Atalhos")
    textFormat: Text.PlainText
    color: ac.t.fgDim
    font.family: ac.t.font
    font.pixelSize: ac.t.fsSmall
    font.bold: true
  }

  ListView {
    id: list
    x: ac.t.sp(6)
    y: ac.t.sp(30)
    width: ac.width - ac.t.sp(12)
    height: ac.height - ac.t.sp(36)
    clip: true
    model: ac.items
    ScrollBar.vertical: ThinScroll { app: ac.app }
    currentIndex: ac.sel
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    delegate: Rectangle {
      required property var modelData
      required property int index
      width: list.width
      height: ac.t.sp(32)
      radius: Math.max(4, ac.t.radiusSmall)
      color: index === ac.sel ? ac.t.accent : (rma.containsMouse ? ac.t.hover : "transparent")
      readonly property color ink: index === ac.sel ? ac.t.onColor(ac.t.accent) : ac.t.fg
      Row {
        x: ac.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: ac.t.sp(10)
        Loader {
          anchors.verticalCenter: parent.verticalCenter
          sourceComponent: ac.kind === "emoji" ? emojiLead : (ac.kind === "user" ? userLead : iconLead)
          property var it: modelData
        }
        Text {
          text: ac.kind === "emoji" ? ac.litName(modelData, index === ac.sel) : (ac.kind === "channel" ? modelData.name : (modelData.name || ""))
          textFormat: ac.kind === "emoji" ? Text.RichText : Text.PlainText
          color: parent.parent.ink
          font.family: ac.t.font
          font.pixelSize: ac.t.fsText - 1
          font.bold: ac.kind !== "emoji"
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: ac.kind === "command" ? ((modelData.usage ? modelData.usage + "  " : "") + (modelData.desc || "")) : (modelData.detail || "")
          textFormat: Text.PlainText
          color: index === ac.sel ? parent.parent.ink : ac.t.fgDim
          font.family: ac.t.font
          font.pixelSize: ac.t.fsSmall
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          width: Math.min(implicitWidth, list.width - ac.t.sp(220))
        }
      }
      Text {
        visible: index === ac.sel
        anchors.right: parent.right
        anchors.rightMargin: ac.t.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "Enter"
        textFormat: Text.PlainText
        color: ac.t.alpha(parent.ink, 0.75)
        font.family: ac.t.font
        font.pixelSize: ac.t.fsTiny
      }
      MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { ac.sel = index; ac.pick(); ac.input.forceActiveFocus() } }
    }
  }

  Component { id: emojiLead; EmojiIcon { app: ac.app; ws: ac.ws; name: parent.it.name; glyph: parent.it.glyph || ""; size: ac.t.sp(20) } }
  Component {
    id: userLead
    Item {
      width: ac.t.sp(22); height: width
      Avatar { visible: parent.parent.it.kind === "user"; app: ac.app; ws: ac.ws; user: parent.parent.it.id; size: parent.width; showPresence: true; ring: ac.t.popup }
      Glyph { visible: parent.parent.it.kind === "broadcast"; anchors.centerIn: parent; app: ac.app; icon: "󰀏"; color: ac.t.fgDim }
    }
  }
  Component { id: iconLead; Glyph { app: ac.app; width: ac.t.sp(22); icon: ac.kind === "channel" ? (parent.it.private ? "󰌾" : "#") : "󰿟"; color: ac.t.fgDim } }
}
