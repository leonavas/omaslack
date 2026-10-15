import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Mrkdwn.js" as Md

// Slack's channel browser: every public channel of the workspace (Slack's
// directory) and the private ones you're in, searchable and sorted. A row
// opens the channel (a preview when you're not in it); Join joins in place.
DialogFrame {
  id: d
  title: app.tr("Browse channels", "Navegar pelos canais")
  cardWidth: t.sp(760)
  initialFocus: field

  property string query: ""
  property string sort: ["name", "members", "newest"].indexOf(app.setting("browseSort", "name")) >= 0 ? app.setting("browseSort", "name") : "name"
  property bool archived: false
  property int sel: 0

  Component.onCompleted: if (d.ws) d.ws.loadDirectory(false)

  function member(id) {
    d.ws.convsRev
    var c = d.ws.convs[id]
    return !!c && !c.guest && c.member !== false
  }

  // Every channel once: the directory's public ones, then private (and any
  // public the directory doesn't know yet) from your conversations.
  readonly property var all: {
    if (!d.ws) return []
    d.ws.directoryRev; d.ws.convsRev
    var w = d.ws, out = [], seen = {}
    var dir = w.directory.chans || []
    for (var i = 0; i < dir.length; i++) {
      var c = dir[i], mine = w.convs[c.id]
      if (seen[c.id]) continue
      seen[c.id] = true
      out.push({ id: c.id, name: c.name, private: !!(mine && mine.kind === "private"), general: !!(mine && mine.general), archived: mine ? !!mine.archived : !!c.archived,
                 members: c.members || (mine && mine.numMembers) || 0, purpose: c.purpose || (mine && mine.purpose) || "",
                 when: (mine && mine.created) || (c.created || 0) || Math.floor((c.updated || 0) / 1000), f: U.fold(c.name + "\n" + (c.purpose || "")) })
    }
    for (var id in w.convs) {
      var m = w.convs[id]
      if (seen[id] || m.guest || (m.kind !== "channel" && m.kind !== "private")) continue
      out.push({ id: id, name: m.name || id, private: m.kind === "private", general: !!m.general, archived: !!m.archived, members: m.numMembers || 0,
                 purpose: m.purpose || "", when: m.created || Math.floor((m.updated || 0) / 1000), f: U.fold((m.name || "") + "\n" + (m.purpose || "")) })
    }
    return out
  }

  readonly property var shown: {
    var q = U.fold(d.query).trim().replace(/^#/, "")
    var list = d.all.filter(function(c) { return (d.archived || !c.archived) && (!q || c.f.indexOf(q) >= 0) })
    var byName = function(a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0) }
    if (d.sort === "members") list.sort(function(a, b) { return b.members - a.members || byName(a, b) })
    else if (d.sort === "newest") list.sort(function(a, b) { return b.when - a.when || byName(a, b) })
    else list.sort(byName)
    return list
  }
  onShownChanged: if (d.sel >= d.shown.length) d.sel = Math.max(0, d.shown.length - 1)

  // The view holds a page of the list and grows as it scrolls: Slack's
  // directories run to thousands, and models diff slowly at that size.
  property int limit: 240
  readonly property var page: d.shown.length > d.limit ? d.shown.slice(0, d.limit) : d.shown
  function more() { if (d.limit < d.shown.length) d.limit += 240 }

  function open(c) {
    if (!c) return
    var w = d.ws
    d.closed()
    w.open(c.id)
  }

  function move(delta) {
    if (!d.shown.length) return
    d.sel = Math.max(0, Math.min(d.shown.length - 1, d.sel + delta))
    if (d.sel >= d.limit - 12) d.more()
    list.positionViewAtIndex(d.sel, ListView.Contain)
  }

  function sortLabel(v) {
    return v === "members" ? d.app.tr("Most members", "Mais membros") : (v === "newest" ? d.app.tr("Newest", "Mais novos") : d.app.tr("A to Z", "De A a Z"))
  }

  Timer { id: typing; interval: 120; onTriggered: { d.limit = 240; d.query = field.text; d.sel = 0; list.positionViewAtBeginning() } }

  Column {
    width: parent.width
    spacing: d.t.sp(12)

    Item {
      width: parent.width
      height: Math.max(field.implicitHeight, createBtn.height)
      SField {
        id: field
        app: d.app
        width: parent.width - createBtn.width - d.t.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰍉"
        placeholderText: d.app.tr("Search for channels", "Buscar canais")
        onTextChanged: typing.restart()
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Down) { d.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { d.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_PageDown) { d.move(8); event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { d.move(-8); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { typing.stop(); d.query = field.text; d.open(d.shown[d.sel]); event.accepted = true }
        }
      }
      SButton {
        id: createBtn
        app: d.app
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰐕"
        text: d.app.tr("Create channel", "Criar canal")
        onClicked: { var win = d.win; d.closed(); win.dialog("newChannel") }
      }
    }

    Item {
      width: parent.width
      height: d.t.sp(28)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          var n = d.shown.length
          if (!n && d.ws && !d.ws.directory.at) return d.app.tr("Loading channels…", "Carregando canais…")
          return n === 1 ? d.app.tr("1 channel", "1 canal") : n + d.app.tr(" channels", " canais")
        }
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
      Rectangle {
        id: sortBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: d.t.sp(28)
        width: sortRow.implicitWidth + d.t.sp(20)
        radius: Math.max(6, d.t.radiusSmall)
        color: sortMa.containsMouse ? d.t.hover : "transparent"
        border.width: 1
        border.color: d.t.lineStrong
        Row {
          id: sortRow
          anchors.centerIn: parent
          spacing: d.t.sp(6)
          Glyph { app: d.app; icon: "󰒺"; size: d.t.fsSmall + 1; color: d.t.fgSoft; anchors.verticalCenter: parent.verticalCenter }
          Text {
            text: d.app.tr("Sort: ", "Ordem: ") + d.sortLabel(d.sort) + (d.archived ? d.app.tr(" · with archived", " · com arquivados") : "")
            color: d.t.fg
            font.family: d.t.font
            font.pixelSize: d.t.fsSmall
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Glyph { app: d.app; icon: "󰅀"; size: d.t.fsSmall; color: d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
          id: sortMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            function pick(v) { return function() { d.limit = 240; d.sort = v; d.app.setSetting("browseSort", v); list.positionViewAtBeginning() } }
            d.win.menuAt(sortBtn, [
              { header: d.app.tr("Sort", "Ordenar") },
              { label: d.sortLabel("name"), checked: d.sort === "name", action: pick("name") },
              { label: d.sortLabel("members"), checked: d.sort === "members", action: pick("members") },
              { label: d.sortLabel("newest"), checked: d.sort === "newest", action: pick("newest") },
              { separator: true },
              { label: d.app.tr("Show archived channels", "Mostrar canais arquivados"), checked: d.archived, action: function() { d.limit = 240; d.archived = !d.archived } }
            ], sortBtn.width - d.t.sp(240), sortBtn.height + d.t.sp(4))
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(d.t.sp(220), Math.min(d.t.sp(620), d.maxHeight - d.t.sp(184)))
      radius: Math.max(6, d.t.radiusSmall)
      color: "transparent"
      border.width: 1
      border.color: d.t.line

      ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: d.page; objectProp: "id" }
        onContentYChanged: if (contentHeight > 0 && contentY + height > contentHeight - height) d.more()
        ScrollBar.vertical: ThinScroll { app: d.app }

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          readonly property var c: modelData
          readonly property bool joined: d.member(c.id)
          readonly property bool hot: rowMa.containsMouse || viewBtn.hovered || index === d.sel
          width: list.width
          height: d.t.sp(66)

          Rectangle {
            anchors.fill: parent
            color: row.index === d.sel ? d.t.alpha(d.t.accent, 0.12) : (rowMa.containsMouse ? d.t.hover : "transparent")
          }
          Rectangle { visible: row.index > 0; width: parent.width; height: 1; color: d.t.line }

          MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: d.open(row.c)
          }

          Column {
            x: d.t.sp(18)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - (actions.visible ? actions.width + d.t.sp(30) : d.t.sp(18))
            spacing: d.t.sp(3)
            Row {
              width: parent.width
              spacing: d.t.sp(6)
              Glyph {
                app: d.app
                anchors.verticalCenter: parent.verticalCenter
                icon: row.c.archived ? "󰀼" : (row.c.private ? "󰌾" : "#")
                size: row.c.private || row.c.archived ? d.t.fsText - 1 : d.t.fsText + 1
                font.bold: !row.c.private
                color: row.c.archived ? d.t.fgDim : d.t.fgBright
              }
              Text {
                width: Math.min(implicitWidth, parent.width - d.t.sp(24))
                anchors.verticalCenter: parent.verticalCenter
                text: row.c.name + (row.c.archived ? d.app.tr(" (archived)", " (arquivado)") : "")
                color: row.c.archived ? d.t.fgDim : d.t.fgBright
                font.family: d.t.font
                font.pixelSize: d.t.fsText
                font.bold: true
                elide: Text.ElideRight
              }
            }
            Row {
              width: parent.width
              spacing: d.t.sp(6)
              Glyph {
                visible: row.joined
                app: d.app
                anchors.verticalCenter: parent.verticalCenter
                icon: "󰄬"
                size: d.t.fsSmall
                color: d.t.green
              }
              Text {
                id: meta
                width: Math.min(implicitWidth, parent.width - (row.joined ? d.t.sp(18) : 0))
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  var bits = []
                  if (row.joined) bits.push(d.app.tr("Joined", "Participando"))
                  if (row.c.members) bits.push(row.c.members === 1 ? d.app.tr("1 member", "1 membro") : row.c.members + d.app.tr(" members", " membros"))
                  if (row.c.purpose) bits.push(Md.flat({ text: row.c.purpose, blocks: [], files: [], attachments: [] }, d.ctx, 160))
                  return bits.join("  ·  ")
                }
                color: d.t.fgDim
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
                elide: Text.ElideRight
              }
            }
          }

          Row {
            id: actions
            visible: row.hot
            anchors.right: parent.right
            anchors.rightMargin: d.t.sp(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: d.t.sp(8)
            HoverHandler { id: viewBtn }
            SButton {
              app: d.app
              small: true
              text: d.app.tr("View", "Ver")
              onClicked: d.open(row.c)
            }
            SButton {
              visible: !row.joined && !row.c.private && !row.c.archived
              app: d.app
              small: true
              kind: "primary"
              text: d.app.tr("Join", "Entrar")
              onClicked: d.ws.join(row.c.id)
            }
            SButton {
              visible: row.joined && !row.c.private && !row.c.general && !row.c.archived
              app: d.app
              small: true
              text: d.app.tr("Leave", "Sair")
              onClicked: d.ws.leave(row.c.id)
            }
          }
        }
      }

      Column {
        visible: d.shown.length === 0
        anchors.centerIn: parent
        width: parent.width - d.t.sp(60)
        spacing: d.t.sp(12)
        Glyph { anchors.horizontalCenter: parent.horizontalCenter; app: d.app; icon: "󰐣"; size: d.t.px(34); color: d.t.alpha(d.t.fgDim, 0.6) }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: d.ws && !d.ws.directory.at && d.all.length === 0 ? d.app.tr("Loading channels…", "Carregando canais…")
              : (d.query.trim() ? d.app.tr("No channels match “", "Nenhum canal encontrado para “") + d.query.trim() + "”" : d.app.tr("No channels here yet", "Nenhum canal por aqui ainda"))
          color: d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          wrapMode: Text.Wrap
        }
        SButton {
          visible: d.query.trim() !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          app: d.app
          small: true
          icon: "󰐕"
          text: d.app.tr("Create a channel", "Criar um canal")
          onClicked: { var win = d.win; d.closed(); win.dialog("newChannel") }
        }
      }
    }
  }

  readonly property var ctx: ws ? ws.renderCtx(t.html, t.emojiPx) : null
}
