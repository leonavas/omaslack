import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji

// Slack's People directory: everyone in the workspace as photo cards
// (name, title, presence, status), searchable. A card opens the person's
// profile; Message opens the conversation with them.
DialogFrame {
  id: d
  title: app.tr("People", "Pessoas")
  cardWidth: t.sp(880)
  initialFocus: field

  property string query: ""
  property int sel: 0

  // Everyone but deactivated accounts and apps, A to Z; one folded string
  // each to search names, handles and titles.
  readonly property var all: {
    if (!d.ws) return []
    d.ws.usersRev
    var out = []
    for (var id in d.ws.users) {
      var u = d.ws.users[id]
      if (!u || u.deleted || u.bot || id === "USLACKBOT") continue
      out.push({ id: id, name: u.name || "", key: U.fold(u.name || ""), f: U.fold([u.name, u.real, u.handle, u.title].filter(function(x) { return x }).join("\n")) })
    }
    out.sort(function(a, b) { return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0) })
    return out
  }

  readonly property var shown: {
    var q = U.fold(d.query).trim().replace(/^@/, "")
    if (!q) return d.all
    var words = q.split(/\s+/)
    return d.all.filter(function(p) { return words.every(function(w) { return p.f.indexOf(w) >= 0 }) })
  }
  onShownChanged: if (d.sel >= d.shown.length) d.sel = Math.max(0, d.shown.length - 1)

  // The view holds a page of the list and grows as it scrolls: Slack's
  // directories run to thousands, and models diff slowly at that size.
  property int limit: 240
  readonly property var page: d.shown.length > d.limit ? d.shown.slice(0, d.limit) : d.shown
  function more() { if (d.limit < d.shown.length) d.limit += 240 }

  function profile(uid) {
    var w = d.ws
    d.closed()
    w.profileUser = uid
    w.thread = null
  }

  function message(uid) {
    var w = d.ws
    d.closed()
    w.openDm([uid])
  }

  function move(delta) {
    if (!d.shown.length) return
    d.sel = Math.max(0, Math.min(d.shown.length - 1, d.sel + delta))
    if (d.sel >= d.limit - 12) d.more()
    grid.positionViewAtIndex(d.sel, GridView.Contain)
  }

  Timer { id: typing; interval: 120; onTriggered: { d.limit = 240; d.query = field.text; d.sel = 0; grid.positionViewAtBeginning() } }

  Column {
    width: parent.width
    spacing: d.t.sp(12)

    SField {
      id: field
      app: d.app
      width: parent.width
      icon: "󰍉"
      placeholderText: d.app.tr("Search by name, username or title", "Buscar por nome, usuário ou cargo")
      onTextChanged: typing.restart()
      Keys.onPressed: event => {
        var cols = Math.max(1, grid.cols)
        if (event.key === Qt.Key_Right && field.cursorPosition === field.text.length) { d.move(1); event.accepted = true }
        else if (event.key === Qt.Key_Left && field.cursorPosition === 0 && field.text === "") { d.move(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { d.move(cols); event.accepted = true }
        else if (event.key === Qt.Key_Up) { d.move(-cols); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          typing.stop()
          d.query = field.text
          var p = d.shown[d.sel]
          if (p) { if (event.modifiers & Qt.ControlModifier) d.message(p.id); else d.profile(p.id) }
          event.accepted = true
        }
      }
    }

    Text {
      text: {
        var n = d.shown.length
        return n === 1 ? d.app.tr("1 person", "1 pessoa") : n + d.app.tr(" people", " pessoas")
      }
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }

    Item {
      width: parent.width
      height: Math.max(d.t.sp(260), Math.min(d.t.sp(660), d.maxHeight - d.t.sp(176)))

      GridView {
        id: grid
        readonly property int cols: Math.max(2, Math.floor(width / d.t.sp(168)))
        anchors.fill: parent
        clip: true
        cellWidth: Math.floor(width / cols)
        cellHeight: cellWidth - d.t.sp(14) + d.t.sp(70)
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: cellHeight * 2
        model: ScriptModel { values: d.page; objectProp: "id" }
        onContentYChanged: if (contentHeight > 0 && contentY + height > contentHeight - height) d.more()
        ScrollBar.vertical: ThinScroll { app: d.app }

        delegate: Item {
          id: cell
          required property var modelData
          required property int index
          readonly property string uid: modelData.id
          readonly property var u: d.ws.user(cell.uid)
          readonly property var st: d.ws.statusOf(cell.uid)
          readonly property bool self: cell.uid === d.ws.me.id
          readonly property bool hot: cellHover.hovered || cell.index === d.sel
          width: grid.cellWidth
          height: grid.cellHeight

          HoverHandler { id: cellHover }

          Rectangle {
            anchors.fill: parent
            anchors.margins: d.t.sp(5)
            radius: Math.max(8, d.t.radiusCard)
            color: cell.index === d.sel ? d.t.alpha(d.t.accent, 0.12) : (cellHover.hovered ? d.t.hover : "transparent")
            border.width: cell.index === d.sel ? 1 : 0
            border.color: d.t.alpha(d.t.accent, 0.5)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: d.profile(cell.uid)
          }

          Column {
            x: d.t.sp(12)
            y: d.t.sp(12)
            width: parent.width - d.t.sp(24)
            spacing: d.t.sp(4)

            Item {
              width: parent.width
              height: width
              Avatar {
                app: d.app
                ws: d.ws
                user: cell.uid
                url: cell.u ? (cell.u.avatar192 || cell.u.avatar || "") : ""
                size: parent.width
                round: 0.08
                big: true
                enabled: false
              }
              // Message, on hover.
              Rectangle {
                visible: cell.hot && !cell.self
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: d.t.sp(8)
                width: msgRow.implicitWidth + d.t.sp(16)
                height: d.t.sp(28)
                radius: Math.max(6, d.t.radiusSmall)
                color: msgMa.containsMouse ? Qt.lighter(d.t.popup, 1.25) : d.t.popup
                border.width: 1
                border.color: d.t.lineStrong
                Row {
                  id: msgRow
                  anchors.centerIn: parent
                  spacing: d.t.sp(6)
                  Glyph { app: d.app; icon: "󰍥"; size: d.t.fsSmall + 1; color: d.t.fgBright; anchors.verticalCenter: parent.verticalCenter }
                  Text { text: d.app.tr("Message", "Mensagem"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsSmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: msgMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.message(cell.uid) }
                PanelToolTip { visible: msgMa.containsMouse; text: d.app.tr("Open a direct message", "Abrir uma mensagem direta") }
              }
            }

            Item { width: 1; height: d.t.sp(4) }

            Row {
              width: parent.width
              spacing: d.t.sp(6)
              PresenceDot {
                anchors.verticalCenter: nameText.verticalCenter
                app: d.app
                size: d.t.sp(9)
                ring: "transparent"
                active: d.ws.isActive(cell.uid)
                paused: d.ws.isPaused(cell.uid)
              }
              Text {
                id: nameText
                width: Math.min(implicitWidth, parent.width - d.t.sp(15) - (emoji.visible ? emoji.width + d.t.sp(6) : 0))
                text: cell.u ? cell.u.name + (cell.self ? d.app.tr(" (you)", " (você)") : "") : ""
                color: d.t.fgBright
                font.family: d.t.font
                font.pixelSize: d.t.fsText
                font.bold: true
                elide: Text.ElideRight
              }
              EmojiIcon {
                id: emoji
                visible: !!cell.st && (cell.st.emoji !== "" || cell.st.unicode !== "")
                anchors.verticalCenter: nameText.verticalCenter
                app: d.app
                ws: d.ws
                name: cell.st ? cell.st.emoji.replace(/:/g, "") : ""
                glyph: cell.st && cell.st.unicode ? Emoji.fromHex(cell.st.unicode) : ""
                size: d.t.sp(16)
                MouseArea { id: emojiMa; anchors.fill: parent; hoverEnabled: true }
                PanelToolTip { visible: emojiMa.containsMouse && !!cell.st && cell.st.text !== ""; text: cell.st ? cell.st.text : "" }
              }
            }
            Text {
              width: parent.width
              text: cell.u ? (cell.u.title || (cell.u.real && cell.u.real !== cell.u.name ? cell.u.real : (cell.u.handle ? "@" + cell.u.handle : ""))) : ""
              color: d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              elide: Text.ElideRight
            }
          }
        }
      }

      Column {
        visible: d.shown.length === 0
        anchors.centerIn: parent
        width: parent.width - d.t.sp(60)
        spacing: d.t.sp(12)
        Glyph { anchors.horizontalCenter: parent.horizontalCenter; app: d.app; icon: "󰀏"; size: d.t.px(34); color: d.t.alpha(d.t.fgDim, 0.6) }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: d.query.trim() ? d.app.tr("No one matches “", "Ninguém encontrado para “") + d.query.trim() + "”" : d.app.tr("No one here yet", "Ninguém por aqui ainda")
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
          icon: "󰠁"
          text: d.app.tr("Invite people", "Convidar pessoas")
          onClicked: { var win = d.win; d.closed(); win.dialog("invite") }
        }
      }
    }
  }
}
