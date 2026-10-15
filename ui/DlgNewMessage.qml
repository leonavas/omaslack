import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Mrkdwn.js" as Md

// Slack's "New message": a To: field gathering up to 8 people as chips,
// then Go opens the DM or group DM with them. Starting with # lists the
// channels to jump to instead.
DialogFrame {
  id: d
  title: app.tr("New message", "Nova mensagem")
  cardWidth: t.sp(580)
  initialFocus: input

  readonly property int most: 8
  property var picked: []
  property int sel: 0
  property string error: ""
  readonly property string query: input.text.trim()
  readonly property bool channelMode: query.charAt(0) === "#"
  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null

  onQueryChanged: { d.sel = 0; d.error = "" }
  onChannelModeChanged: if (d.channelMode && d.ws) d.ws.loadDirectory(false)

  readonly property var results: {
    if (!d.ws) return []
    d.ws.usersRev; d.ws.convsRev; d.ws.directoryRev
    return d.channelMode ? d.channels(d.query.slice(1)) : d.people(d.query)
  }

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

  // Everyone but bots, deactivated accounts, you and the people picked;
  // with nothing typed, the people you talked to lately come first.
  function people(q) {
    var w = d.ws, me = w.me.id, out = [], recent = {}, Q = d.needle(q)
    for (var cid in w.convs) {
      var c = w.convs[cid]
      if (c.kind !== "im" || !c.user) continue
      var k = w.counts[cid]
      recent[c.user] = k && k.latest ? U.tsNum(k.latest) : (c.updated || 0) / 1000
    }
    for (var id in w.users) {
      var u = w.users[id]
      if (!u || u.bot || u.deleted || id === me || d.picked.indexOf(id) >= 0) continue
      var r = q ? d.score(id, [u.name || "", u.real || "", u.handle || ""], Q) : 0
      if (r < 0) continue
      out.push({ key: id, kind: "user", id: id, rank: r, recent: recent[id] || 0, name: (u.name || "").toLowerCase() })
    }
    out.sort(function(a, b) {
      return a.rank - b.rank || (q ? 0 : b.recent - a.recent) || (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0))
    })
    return out.slice(0, 60)
  }

  // Your channels first, then the public ones you could join.
  function channels(q) {
    var w = d.ws, out = [], seen = {}, Q = d.needle(q)
    for (var id in w.convs) {
      var c = w.convs[id]
      if ((c.kind !== "channel" && c.kind !== "private") || c.guest) continue
      seen[id] = true
      var r = q ? d.score(id, [c.name || ""], Q) : 5
      if (r < 0) continue
      out.push({ key: id, kind: "conv", id: id, name: c.name || "", rank: r, mine: true, private: c.kind === "private", archived: !!c.archived,
                 detail: c.purpose || c.topic || "" })
    }
    ;(w.directory.chans || []).forEach(function(x) {
      if (seen[x.id]) return
      var r = q ? d.score(x.id, [x.name || ""], Q) : 5
      if (r < 0) return
      out.push({ key: x.id, kind: "conv", id: x.id, name: x.name || "", rank: r, mine: false, private: false, archived: !!x.archived, detail: "", members: x.members || 0 })
    })
    out.sort(function(a, b) { return a.rank - b.rank || (a.archived - b.archived) || (b.mine - a.mine) || (a.name < b.name ? -1 : 1) })
    return out.slice(0, 60)
  }

  function add(uid) {
    if (!uid || d.picked.indexOf(uid) >= 0) return
    if (d.picked.length >= d.most) {
      d.error = d.app.tr("At most 8 people in a conversation.", "No máximo 8 pessoas numa conversa.")
      return
    }
    d.picked = d.picked.concat([uid])
    input.text = ""
    d.error = ""
  }
  function drop(uid) { d.picked = d.picked.filter(function(x) { return x !== uid }); d.error = ""; input.forceActiveFocus() }

  function choose(i) {
    var r = d.results[i]
    if (!r) return
    if (r.kind === "conv") { var w = d.ws; d.closed(); w.open(r.id); return }
    d.add(r.id)
  }

  function go() {
    if (d.channelMode) { d.choose(d.sel); return }
    if (d.query !== "" && d.results.length) d.add(d.results[d.sel].id)
    if (!d.picked.length) { d.error = d.app.tr("Pick at least one person.", "Escolha pelo menos uma pessoa."); return }
    var w = d.ws, ids = d.picked.slice()
    d.closed()
    w.openDm(ids)
  }

  function move(delta) {
    var n = d.results.length
    if (!n) return
    d.sel = Math.max(0, Math.min(n - 1, d.sel + delta))
    list.positionViewAtIndex(d.sel, ListView.Contain)
  }

  Column {
    width: parent.width
    spacing: d.t.sp(10)

    // ------------------------------------------------------------ To:
    Rectangle {
      id: box
      width: parent.width
      height: Math.max(d.t.sp(40), flow.implicitHeight + d.t.sp(12))
      radius: Math.max(4, d.t.radiusSmall)
      color: d.t.alpha(d.t.bg, 0.6)
      border.width: input.activeFocus ? 2 : 1
      border.color: input.activeFocus ? d.t.accent : d.t.lineStrong

      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: input.forceActiveFocus() }

      Text {
        id: toLabel
        x: d.t.sp(12)
        y: d.t.sp(6) + (d.t.sp(28) - height) / 2
        text: d.app.tr("To:", "Para:")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsText
      }

      Flow {
        id: flow
        x: toLabel.x + toLabel.implicitWidth + d.t.sp(8)
        y: d.t.sp(6)
        width: parent.width - x - d.t.sp(8)
        spacing: d.t.sp(4)

        Repeater {
          model: d.picked
          delegate: Rectangle {
            required property var modelData
            height: d.t.sp(28)
            width: chipRow.implicitWidth + d.t.sp(10)
            radius: Math.max(4, d.t.radiusSmall)
            color: chipMa.containsMouse ? d.t.alpha(d.t.accent, 0.28) : d.t.alpha(d.t.accent, 0.16)
            Row {
              id: chipRow
              x: d.t.sp(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: d.t.sp(6)
              Avatar { app: d.app; ws: d.ws; user: modelData; size: d.t.sp(20); anchors.verticalCenter: parent.verticalCenter }
              Text {
                text: d.ws ? d.ws.userName(modelData) : ""
                color: d.t.fgBright
                font.family: d.t.font
                font.pixelSize: d.t.fsText - 1
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: Math.min(implicitWidth, d.t.sp(180))
              }
              Glyph { app: d.app; icon: "󰅖"; size: d.t.fsSmall; color: chipMa.containsMouse ? d.t.fgBright : d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.drop(parent.modelData) }
          }
        }

        TextField {
          id: input
          width: d.picked.length ? Math.max(d.t.sp(140), Math.min(flow.width, contentWidth + d.t.sp(24))) : flow.width
          height: d.t.sp(28)
          padding: 0
          leftPadding: d.t.sp(2)
          verticalAlignment: TextInput.AlignVCenter
          background: null
          color: d.t.fg
          placeholderText: d.picked.length ? "" : d.app.tr("@somebody or #a-channel", "@alguém ou #um-canal")
          placeholderTextColor: d.t.fgDim
          selectionColor: d.t.alpha(d.t.accent, 0.35)
          selectedTextColor: d.t.fgBright
          selectByMouse: true
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          Keys.onPressed: event => {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            if (event.key === Qt.Key_Down) { d.move(1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { d.move(-1); event.accepted = true }
            else if (event.key === Qt.Key_PageDown) { d.move(6); event.accepted = true }
            else if (event.key === Qt.Key_PageUp) { d.move(-6); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              event.accepted = true
              if (ctrl || d.channelMode || d.query === "") d.go()
              else d.choose(d.sel)
            } else if (event.key === Qt.Key_Tab && d.query !== "" && !d.channelMode) {
              d.choose(d.sel); event.accepted = true
            } else if (event.key === Qt.Key_Backspace && input.text === "" && d.picked.length) {
              d.drop(d.picked[d.picked.length - 1]); event.accepted = true
            } else if (event.key === Qt.Key_U && ctrl) { input.text = ""; event.accepted = true }
          }
        }
      }
    }

    // ------------------------------------------------------------ results
    Item {
      width: parent.width
      height: Math.max(d.t.sp(130), Math.min(d.t.sp(320), d.maxHeight - d.t.sp(230)))

      ListView {
        id: list
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: d.results; objectProp: "key" }
        ScrollBar.vertical: ThinScroll { app: d.app }

        delegate: Rectangle {
          id: rowItem
          required property var modelData
          required property int index
          readonly property bool hot: index === d.sel
          readonly property color ink: hot ? d.t.onColor(d.t.accent) : d.t.fg
          readonly property color dim: hot ? d.t.alpha(d.t.onColor(d.t.accent), 0.75) : d.t.fgDim
          readonly property var u: modelData.kind === "user" && d.ws ? d.ws.user(modelData.id) : null
          readonly property var status: modelData.kind === "user" && d.ws ? d.ws.statusOf(modelData.id) : null
          width: list.width
          height: d.t.sp(42)
          radius: Math.max(4, d.t.radiusSmall)
          color: hot ? d.t.accent : (rowMa.containsMouse ? d.t.hover : "transparent")

          Row {
            x: d.t.sp(10)
            width: parent.width - d.t.sp(20)
            anchors.verticalCenter: parent.verticalCenter
            spacing: d.t.sp(10)

            Item {
              width: d.t.sp(26)
              height: width
              anchors.verticalCenter: parent.verticalCenter
              Avatar {
                visible: rowItem.modelData.kind === "user"
                app: d.app
                ws: d.ws
                user: rowItem.modelData.kind === "user" ? rowItem.modelData.id : ""
                size: parent.width
                showPresence: true
                ring: rowItem.hot ? d.t.accent : d.t.popup
              }
              Glyph {
                visible: rowItem.modelData.kind === "conv"
                anchors.centerIn: parent
                app: d.app
                icon: rowItem.modelData.private ? "󰌾" : (rowItem.modelData.archived ? "󱈎" : "#")
                size: d.t.fsTitle
                color: rowItem.dim
              }
            }
            Text {
              id: nameText
              anchors.verticalCenter: parent.verticalCenter
              text: rowItem.modelData.kind === "user" ? (rowItem.u ? rowItem.u.name : "") : rowItem.modelData.name
              color: rowItem.ink
              font.family: d.t.font
              font.pixelSize: d.t.fsText
              font.bold: true
              elide: Text.ElideRight
              width: Math.min(implicitWidth, parent.width * 0.5)
            }
            EmojiIcon {
              visible: !!rowItem.status && !!rowItem.status.emoji
              anchors.verticalCenter: parent.verticalCenter
              app: d.app
              ws: d.ws
              name: rowItem.status ? String(rowItem.status.emoji || "").replace(/^:|:$/g, "") : ""
              size: d.t.sp(16)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: {
                var m = rowItem.modelData
                if (m.kind === "conv") {
                  if (m.archived) return d.app.tr("Archived", "Arquivado")
                  if (!m.mine) return d.app.tr("You're not a member", "Você não é membro") + (m.members ? "  ·  " + m.members + d.app.tr(" members", " membros") : "")
                  return m.detail && d.ctx ? Md.flatMrkdwn(m.detail, d.ctx) : ""
                }
                var u = rowItem.u
                if (!u) return ""
                var parts = []
                if (u.real && u.real !== u.name) parts.push(u.real)
                else if (u.handle && u.handle !== u.name) parts.push("@" + u.handle)
                if (u.title) parts.push(u.title)
                return parts.join("  ·  ")
              }
              color: rowItem.dim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              elide: Text.ElideRight
              width: Math.max(0, parent.width - x)
            }
          }

          MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { d.sel = rowItem.index; d.choose(rowItem.index); input.forceActiveFocus() }
          }
        }
      }

      Text {
        visible: d.results.length === 0
        anchors.centerIn: parent
        width: parent.width - d.t.sp(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: d.ws && Object.keys(d.ws.users).length === 0 ? d.app.tr("Loading people…", "Carregando pessoas…")
            : d.channelMode ? d.app.tr("No channel found", "Nenhum canal encontrado")
            : (d.query === "" && d.picked.length ? d.app.tr("Everyone is already here", "Todo mundo já está aqui") : d.app.tr("No one found", "Ninguém encontrado"))
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsText
      }
    }

    Text {
      visible: d.error !== ""
      width: parent.width
      wrapMode: Text.Wrap
      text: "󰗖  " + d.error
      color: d.t.red
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }
  }

  footer: Item {
    width: parent.width
    height: goBtn.height
    Text {
      anchors.left: parent.left
      anchors.right: goBtn.left
      anchors.rightMargin: d.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: d.channelMode ? d.app.tr("Enter opens the channel · Esc closes", "Enter abre o canal · Esc fecha")
          : d.picked.length ? d.app.tr("Enter adds · Enter on empty opens · Esc closes", "Enter adiciona · Enter vazio abre · Esc fecha")
          : d.app.tr("Enter adds · # for channels · Esc closes", "Enter adiciona · # para canais · Esc fecha")
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }
    SButton {
      id: goBtn
      app: d.app
      anchors.right: parent.right
      kind: "primary"
      icon: d.channelMode ? "#" : ""
      text: d.app.tr("Go", "Ir")
      enabled2: d.channelMode ? d.results.length > 0 : (d.picked.length > 0 || (d.query !== "" && d.results.length > 0))
      onClicked: d.go()
    }
  }
}
