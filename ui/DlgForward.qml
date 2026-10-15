import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Model.js" as Model

// Slack's "Forward message": where to (a channel, a DM, a group DM or
// anyone else), an optional note, and the message as it will be quoted.
// Forwarding posts the message's link, which Slack unfurls as a quote.
DialogFrame {
  id: d
  title: app.tr("Forward message", "Encaminhar mensagem")
  cardWidth: t.sp(580)
  initialFocus: input

  readonly property string conv: args.conv || ""
  readonly property var msg: args.msg || null
  property var dest: null            // {kind: "conv"|"user", id}
  property int sel: 0

  readonly property string query: input.text.trim()
  readonly property bool picking: d.dest === null && input.activeFocus
  onQueryChanged: d.sel = 0

  // ------------------------------------------------------------ fast search
  // U.rank's tiers over names folded once per person or channel (folding
  // is what costs with thousands of them).
  property var _folds: ({})
  function index(id, names) {
    var key = names.join("\u0001")
    var f = d._folds[id]
    if (f && f.key === key) return f
    f = { key: key, parts: names.filter(function(s) { return !!s }).map(function(s) {
      var n = U.fold(s), toks = U.tokens(s)
      return { n: n, sep: n.replace(/[\s._-]+/g, " "), toks: toks, ini: toks.map(function(w) { return w[0] }).join("") }
    }) }
    d._folds[id] = f
    return f
  }
  function needle(q) {
    var f = U.fold(q).replace(/^[#@]/, "").trim()
    return { q: f, sep: f.replace(/[\s._-]+/g, " "), toks: U.tokens(f) }
  }
  function rankPart(p, Q) {
    if (!Q.q) return 5
    if (p.n === Q.q) return 0
    if (p.sep.indexOf(Q.sep) === 0) return 1
    var qt = Q.toks, nt = p.toks, i, k
    if (!qt.length) return -1
    var j = 0
    for (i = 0; i < nt.length && j < qt.length; i++) if (nt[i].indexOf(qt[j]) === 0) j++
    if (j === qt.length) return 2
    var all = true
    for (k = 0; k < qt.length && all; k++) {
      var hit = false
      for (i = 0; i < nt.length && !hit; i++) hit = nt[i].indexOf(qt[k]) === 0
      all = hit
    }
    if (all) return 3
    if (qt.length > 1) return -1
    var t0 = qt[0]
    if (t0.length >= 2 && t0.length <= 12 && nt.length >= 2 && p.ini.indexOf(t0) === 0) return 4
    if (p.n.indexOf(t0) >= 0) return 5
    if (t0.length >= 4) {
      for (k = 0; k < nt.length; k++) {
        var w = nt[k]
        // One edit leaves one of these letters in place; skip the rest.
        if (w[0] !== t0[0] && w[1] !== t0[1] && w[0] !== t0[1] && w[1] !== t0[0]) continue
        if (U.oneTypo(w.slice(0, t0.length + 1), t0)) return 6
      }
    }
    return -1
  }
  // Best tier over the names (-1: no match).
  function score(id, names, Q) {
    var f = d.index(id, names), r = -1
    for (var i = 0; i < f.parts.length; i++) { var x = d.rankPart(f.parts[i], Q); if (x >= 0 && (r < 0 || x < r)) r = x }
    return r
  }
  // Folds everyone's names ahead, a slice at a time, so the first
  // keystroke in a big workspace doesn't stall.
  Timer {
    property var ids: null
    property int at: 0
    interval: 1
    repeat: true
    running: !!d.ws
    onTriggered: {
      var users = d.ws.users
      if (!ids) ids = Object.keys(users)
      var end = Math.min(ids.length, at + 600)
      for (; at < end; at++) { var u = users[ids[at]]; if (u) d.index(ids[at], [u.name || "", u.real || "", u.handle || ""]) }
      if (at >= ids.length) stop()
    }
  }

  // ------------------------------------------------------------ options
  function usable(c) {
    return !!c && !c.archived && !c.guest && c.member !== false && !(c.kind === "im" && d.ws.user(c.user) && d.ws.user(c.user).deleted)
  }

  function option(c, recent) {
    var w = d.ws
    var u = c.kind === "im" ? w.users[c.user] : null
    var hint = ""
    if (u) hint = u.title || (u.real && u.real !== u.name ? u.real : "")
    else if (c.kind === "mpim") hint = d.app.tr("Group conversation", "Conversa em grupo")
    return { key: c.id, kind: "conv", id: c.id, conv: c.kind, user: c.user || "", label: w.convLabel(c.id), hint: hint, recent: recent }
  }

  readonly property var options: {
    var w = d.ws
    if (!w) return []
    w.convsRev; w.usersRev
    var q = d.query, out = [], seen = {}
    if (!q) {
      // The conversations visited lately, newest first, then the busiest.
      var trail = [w.current].concat(w.backStack.map(function(e) { return e.view === "conv" ? e.conv : "" }).reverse())
      trail.forEach(function(id) {
        if (!id || seen[id]) return
        var c = w.convs[id]
        if (!d.usable(c)) return
        seen[id] = true
        out.push(d.option(c, true))
      })
      var rest = []
      for (var id in w.convs) {
        var c = w.convs[id]
        if (seen[id] || !d.usable(c)) continue
        var k = w.counts[id]
        rest.push({ c: c, at: k && k.latest ? U.tsNum(k.latest) : (c.updated || 0) / 1000 })
      }
      rest.sort(function(a, b) { return b.at - a.at })
      rest.slice(0, 40).forEach(function(x) { out.push(d.option(x.c, false)) })
      return out
    }
    var ranked = [], dmWith = {}, Q = d.needle(q)
    for (var cid in w.convs) {
      var cc = w.convs[cid]
      if (cc.kind === "im" && cc.user) dmWith[cc.user] = true
      if (!d.usable(cc)) continue
      var label = w.convLabel(cid)
      var uu = cc.kind === "im" ? w.users[cc.user] : null
      var r = d.score(cid, uu ? [label, uu.real || "", uu.handle || ""] : [label], Q)
      if (r < 0) continue
      var kk = w.counts[cid]
      ranked.push({ o: d.option(cc, false), r: r, at: kk && kk.latest ? U.tsNum(kk.latest) : 0, l: "" })
    }
    // People without a DM yet: picking one opens it.
    for (var uid in w.users) {
      var p = w.users[uid]
      if (!p || p.deleted || dmWith[uid] || (p.bot && uid !== "USLACKBOT")) continue
      var best = d.score(uid, [p.name || "", p.real || "", p.handle || ""], Q)
      if (best < 0) continue
      ranked.push({ id: uid, r: best, at: 0, l: (p.name || "").toLowerCase() })
    }
    ranked.forEach(function(x) { if (!x.l) x.l = x.o.label.toLowerCase() })
    ranked.sort(function(a, b) { return a.r - b.r || b.at - a.at || (a.l < b.l ? -1 : (a.l > b.l ? 1 : 0)) })
    // Only the rows shown get their full description.
    return ranked.slice(0, 40).map(function(x) {
      if (x.o) return x.o
      var p = w.users[x.id]
      return { key: "user:" + x.id, kind: "user", id: x.id, conv: "im", user: x.id, label: p.name, hint: p.title || "", recent: false }
    })
  }

  function pick(i) {
    var o = d.options[i]
    if (!o) return
    d.dest = o
    input.text = ""
    comment.area.forceActiveFocus()
  }
  function unpick() { d.dest = null; input.forceActiveFocus() }

  function move(delta) {
    var n = d.options.length
    if (!n) return
    d.sel = Math.max(0, Math.min(n - 1, d.sel + delta))
    list.positionViewAtIndex(d.sel, ListView.Contain)
  }

  function forward() {
    if (!d.dest || !d.msg) return
    var w = d.ws, from = d.conv, m = d.msg, note = comment.text.trim(), to = d.dest
    if (to.kind === "conv") {
      d.closed()
      w.forward(from, m, to.id, note)
      return
    }
    // Someone without a DM yet: open it first (errors come as a toast).
    d.closed()
    w.openDm([to.id], function(id) { w.forward(from, m, id, note) })
  }

  Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; onActivated: d.forward() }

  // ------------------------------------------------------------ layout
  Column {
    id: col
    width: parent.width
    spacing: d.t.sp(12)

    Rectangle {
      id: box
      width: parent.width
      height: d.t.sp(42)
      radius: Math.max(4, d.t.radiusSmall)
      color: d.t.alpha(d.t.bg, 0.6)
      border.width: input.activeFocus ? 2 : 1
      border.color: input.activeFocus ? d.t.accent : d.t.lineStrong
      z: 2

      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: if (!d.dest) input.forceActiveFocus() }

      Text {
        id: toLabel
        x: d.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        text: d.app.tr("To:", "Para:")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsText
      }

      // The destination, once picked.
      Rectangle {
        id: chip
        visible: d.dest !== null
        x: toLabel.x + toLabel.implicitWidth + d.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        height: d.t.sp(28)
        width: Math.min(box.width - x - d.t.sp(8), chipRow.implicitWidth + d.t.sp(12))
        radius: Math.max(4, d.t.radiusSmall)
        color: chipMa.containsMouse ? d.t.alpha(d.t.accent, 0.28) : d.t.alpha(d.t.accent, 0.16)
        Row {
          id: chipRow
          x: d.t.sp(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: d.t.sp(6)
          Loader {
            anchors.verticalCenter: parent.verticalCenter
            property var it: d.dest
            sourceComponent: lead
          }
          Text {
            text: d.dest ? d.dest.label : ""
            textFormat: Text.PlainText
            color: d.t.fgBright
            font.family: d.t.font
            font.pixelSize: d.t.fsText - 1
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: Math.min(implicitWidth, box.width - d.t.sp(140))
          }
          Glyph { app: d.app; icon: "󰅖"; size: d.t.fsSmall; color: chipMa.containsMouse ? d.t.fgBright : d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.unpick() }
      }

      TextField {
        id: input
        visible: d.dest === null
        x: toLabel.x + toLabel.implicitWidth + d.t.sp(6)
        width: box.width - x - d.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        padding: 0
        leftPadding: d.t.sp(2)
        background: null
        color: d.t.fg
        placeholderText: d.app.tr("Add a channel, person or group", "Adicione um canal, pessoa ou grupo")
        placeholderTextColor: d.t.fgDim
        selectionColor: d.t.alpha(d.t.accent, 0.35)
        selectedTextColor: d.t.fgBright
        selectByMouse: true
        font.family: d.t.font
        font.pixelSize: d.t.fsText
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Down) { d.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { d.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_PageDown) { d.move(5); event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { d.move(-5); event.accepted = true }
          else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) && d.options.length) { d.pick(d.sel); event.accepted = true }
          else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { input.text = ""; event.accepted = true }
        }
      }

      // The choices, over the note and the preview.
      Rectangle {
        id: drop
        visible: d.picking
        y: box.height + d.t.sp(4)
        width: box.width
        height: Math.min(Math.max(list.contentHeight, d.t.sp(40)), Math.max(d.t.sp(120), col.height - box.height - d.t.sp(8))) + d.t.sp(12)
        radius: Math.max(6, d.t.radiusCard)
        color: d.t.mix(d.t.bg, d.t.fg, 0.04)
        border.width: 1
        border.color: d.t.lineStrong

        ListView {
          id: list
          x: d.t.sp(6)
          y: d.t.sp(6)
          width: parent.width - d.t.sp(12)
          height: parent.height - d.t.sp(12)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: ScriptModel { values: d.options; objectProp: "key" }
          ScrollBar.vertical: ThinScroll { app: d.app }
          delegate: Item {
            id: opt
            required property var modelData
            required property int index
            readonly property bool hot: index === d.sel
            // "Recent" over the first recent one, "Conversations" where the rest start.
            readonly property bool heading: d.query === "" && (index === 0 || (!!d.options[index - 1] && d.options[index - 1].recent !== modelData.recent))
            width: list.width
            height: (heading ? d.t.sp(26) : 0) + d.t.sp(36)
            Text {
              visible: opt.heading
              height: d.t.sp(26)
              leftPadding: d.t.sp(10)
              verticalAlignment: Text.AlignVCenter
              text: opt.modelData.recent ? d.app.tr("Recent", "Recentes") : d.app.tr("Conversations", "Conversas")
              color: d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              font.bold: true
            }
            Rectangle {
              id: optBg
              y: opt.heading ? d.t.sp(26) : 0
              width: parent.width
              height: d.t.sp(36)
              radius: Math.max(4, d.t.radiusSmall)
              color: opt.hot ? d.t.accent : (optMa.containsMouse ? d.t.hover : "transparent")
            }
            Row {
              x: d.t.sp(10)
              width: parent.width - d.t.sp(20)
              anchors.verticalCenter: optBg.verticalCenter
              spacing: d.t.sp(10)
              Loader {
                anchors.verticalCenter: parent.verticalCenter
                property var it: opt.modelData
                property bool hot: opt.hot
                sourceComponent: lead
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: opt.modelData.label
                textFormat: Text.PlainText
                color: opt.hot ? d.t.onColor(d.t.accent) : d.t.fg
                font.family: d.t.font
                font.pixelSize: d.t.fsText
                font.bold: true
                elide: Text.ElideRight
                width: Math.min(implicitWidth, parent.width * 0.55)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: opt.modelData.hint
                textFormat: Text.PlainText
                color: opt.hot ? d.t.alpha(d.t.onColor(d.t.accent), 0.75) : d.t.fgDim
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
                elide: Text.ElideRight
                width: Math.max(0, parent.width - x)
              }
            }
            MouseArea {
              id: optMa
              anchors.fill: optBg
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { d.sel = opt.index; d.pick(opt.index) }
            }
          }
        }
        Text {
          visible: d.options.length === 0
          anchors.centerIn: parent
          text: d.app.tr("No conversation found", "Nenhuma conversa encontrada")
          color: d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsText
        }
      }
    }

    SArea {
      id: comment
      app: d.app
      width: parent.width
      implicitHeight: d.t.sp(76)
      placeholderText: d.app.tr("Add a message, if you'd like.", "Adicione uma mensagem, se quiser.")
    }

    // ------------------------------------------------------------ preview
    Rectangle {
      id: preview
      width: parent.width
      readonly property int most: Math.max(d.t.sp(70), Math.min(d.t.sp(230), d.maxHeight - d.t.sp(330)))
      height: Math.min(item.implicitHeight, most) + foot.height + d.t.sp(14)
      radius: Math.max(6, d.t.radiusCard)
      color: "transparent"
      border.width: 1
      border.color: d.t.lineStrong
      clip: true

      Rectangle { x: d.t.sp(10); y: d.t.sp(10); width: d.t.sp(3); height: parent.height - d.t.sp(20); radius: 1; color: d.t.lineStrong }

      MessageItem {
        id: item
        x: d.t.sp(6)
        y: d.t.sp(4)
        width: parent.width - d.t.sp(12)
        height: Math.min(implicitHeight, preview.most)
        clip: true
        enabled: false
        app: d.app
        win: d.win
        ws: d.ws
        conv: d.conv
        inThread: true
        ctx: d.ws ? d.ws.renderCtx(d.t.html, d.t.emojiPx) : null
        row: d.msg ? { key: d.msg.ts, kind: "msg", msg: Model.patch(d.msg, { reactions: [], replyCount: 0, replyUsers: [], pinnedTo: [] }), header: true, day: null, isNew: false, pinned: false } : null
      }

      Text {
        id: foot
        x: d.t.sp(34) + d.t.avatar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: d.t.sp(10)
        width: parent.width - x - d.t.sp(12)
        elide: Text.ElideRight
        text: {
          if (!d.msg || !d.ws) return ""
          var c = d.ws.conv(d.conv)
          var where = c && (c.kind === "channel" || c.kind === "private") ? "#" + c.name : d.ws.convLabel(d.conv)
          var parts = []
          if (where) parts.push(d.app.tr("Posted in ", "Publicada em ") + where)
          parts.push(U.shortStamp(d.msg.ts, d.app.lang, d.app.clock24))
          return parts.join("  ·  ")
        }
        textFormat: Text.PlainText
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }

    // Room for the list of choices under a short message.
    Item { width: 1; height: Math.max(0, Math.min(d.t.sp(280), d.maxHeight - d.t.sp(150)) - box.height - comment.height - preview.height - 3 * col.spacing) }
  }

  // A conversation's mark: a photo for people, # or a lock for channels.
  Component {
    id: lead
    Item {
      readonly property var it: parent ? parent.it : null
      readonly property bool hot: parent && parent.hot === true
      width: d.t.sp(22)
      height: width
      Avatar {
        visible: !!parent.it && parent.it.conv === "im"
        app: d.app
        ws: d.ws
        user: parent.it && parent.it.conv === "im" ? parent.it.user : ""
        size: parent.width
      }
      Glyph {
        visible: !!parent.it && parent.it.conv !== "im"
        anchors.centerIn: parent
        app: d.app
        icon: !parent.it ? "" : (parent.it.conv === "private" ? "󰌾" : (parent.it.conv === "mpim" ? "󰀏" : "#"))
        size: d.t.fsTitle
        color: parent.hot ? d.t.onColor(d.t.accent) : d.t.fgDim
      }
    }
  }

  footer: Item {
    width: parent.width
    height: fwdBtn.height
    SButton {
      app: d.app
      anchors.left: parent.left
      icon: "󰌹"
      text: d.app.tr("Copy link", "Copiar link")
      enabled2: !!d.msg
      onClicked: { d.app.copy(d.ws.permalink(d.conv, d.msg)); d.win.toast(d.app.tr("Link copied", "Link copiado")) }
    }
    SButton {
      id: fwdBtn
      app: d.app
      anchors.right: parent.right
      kind: "primary"
      text: d.app.tr("Forward", "Encaminhar")
      enabled2: d.dest !== null
      onClicked: d.forward()
    }
  }
}
