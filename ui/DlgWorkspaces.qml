import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Registry.js" as Reg

// Slack's workspace switcher (a click on the stacked workspace at the top
// of the rail): every signed-in workspace with its icon, domain, what's
// unread in it and its Ctrl+1…9, ✓ on the one you're in, then "Add a
// workspace". A card beside the rail, placed at args.x / args.y. Same API as
// DialogFrame (app, win, ws, args, closed()).
Item {
  id: d
  property var app: Reg.service
  property var win
  property var ws
  property var args: ({})
  readonly property var t: app.theme
  // The theme's popup color, made opaque over the pane (Omarchy's is see-through).
  readonly property color cardColor: t.mix(t.pane, t.alpha(t.popup, 1), t.popup.a)
  signal closed()
  anchors.fill: parent
  z: 800

  // The rows: the workspaces, then "Add a workspace" (index list.length).
  readonly property var list: d.app.workspaces
  readonly property int count: d.list.length + 1
  readonly property int rowH: d.t.sp(52)
  property int hot: -1

  function pick(i) {
    var a = d.app, w = d.win
    if (i === d.list.length) { d.closed(); w.dialog("addWorkspace", {}); return }
    var o = d.list[i]
    if (!o) return
    var team = o.teamId, same = o === a.current
    d.closed()
    if (!same) a.switchTo(team)
  }

  // Ctrl+1…9 (Shortcuts) switches from under it: then it closes.
  Connections { target: d.app; function onCurrentChanged() { d.closed() } }

  // The keyboard row stays in sight when the list scrolls.
  onHotChanged: {
    if (d.hot < 0 || d.hot >= d.list.length) return
    var y = d.hot * d.rowH
    if (y < rows.contentY) rows.contentY = y
    else if (y + d.rowH > rows.contentY + rows.height) rows.contentY = y + d.rowH - rows.height
  }

  focus: true
  Keys.onPressed: event => {
    var k = event.key
    if (k === Qt.Key_Escape) d.closed()
    else if (k === Qt.Key_Up || k === Qt.Key_Backtab) d.hot = d.hot <= 0 ? d.count - 1 : d.hot - 1
    else if (k === Qt.Key_Down || k === Qt.Key_Tab) d.hot = (d.hot + 1) % d.count
    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (d.hot >= 0) d.pick(d.hot) }
    else if (k >= Qt.Key_1 && k <= Qt.Key_9) { if (k - Qt.Key_1 < d.list.length) d.pick(k - Qt.Key_1) }
    else return
    event.accepted = true
  }

  // Clicks outside close it, like any menu.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: d.closed()
    onWheel: wheel => {}
  }

  // ---------------------------------------------------------------- the card
  BorderSurface {
    id: card
    x: d.args.x !== undefined ? Math.max(d.t.sp(6), Math.min(d.args.x, d.width - width - d.t.sp(6))) : d.t.sp(78)
    y: d.args.y !== undefined ? Math.max(d.t.sp(6), Math.min(d.args.y, d.height - height - d.t.sp(6))) : d.t.sp(48)
    width: d.t.sp(320)
    height: col.implicitHeight + d.t.sp(12)
    color: d.cardColor
    borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, 1)
    radius: Math.max(6, d.t.radiusCard)

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      id: col
      x: d.t.sp(6)
      y: d.t.sp(6)
      width: card.width - d.t.sp(12)

      Text {
        width: parent.width
        text: d.app.tr("Workspaces", "Workspaces")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
        font.bold: true
        leftPadding: d.t.sp(12)
        topPadding: d.t.sp(4)
        bottomPadding: d.t.sp(6)
        elide: Text.ElideRight
      }

      // The workspaces (scrolling when there are more than fit).
      Flickable {
        id: rows
        width: parent.width
        height: Math.min(rowsCol.implicitHeight, Math.max(d.rowH, d.height - d.t.sp(150)))
        contentHeight: rowsCol.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: rowsCol
          width: rows.width
          Repeater {
            model: d.list
            delegate: Rectangle {
              id: r
              required property var modelData
              required property int index
              readonly property var w: modelData
              readonly property bool cur: w === d.app.current
              readonly property bool hot: d.hot === index
              readonly property color ink: hot ? d.t.onColor(d.t.accent) : d.t.fgBright
              width: rowsCol.width
              height: d.rowH
              radius: Math.max(4, d.t.radiusSmall)
              color: hot ? d.t.accent : "transparent"

              WorkspaceIcon {
                id: icon
                app: d.app
                w: r.w
                size: d.t.sp(36)
                x: d.t.sp(8)
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                anchors.left: icon.right
                anchors.leftMargin: d.t.sp(12)
                anchors.right: side.left
                anchors.rightMargin: d.t.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: r.w.team.name || r.w.team.domain || r.w.teamId
                  color: r.ink
                  font.family: d.t.font
                  font.pixelSize: d.t.fsText - 1
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: r.w.team.domain ? r.w.team.domain + ".slack.com" : ""
                  color: r.hot ? d.t.alpha(r.ink, 0.8) : d.t.fgDim
                  font.family: d.t.font
                  font.pixelSize: d.t.fsTiny
                  elide: Text.ElideRight
                }
              }
              // What's unread there, its shortcut, ✓ where you are.
              Row {
                id: side
                anchors.right: parent.right
                anchors.rightMargin: d.t.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: d.t.sp(10)
                Badge {
                  app: d.app
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !r.cur && r.w.attention.total > 0
                  count: r.w.attention.total
                }
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !r.cur && r.w.attention.total === 0 && r.w.attention.channels > 0
                  width: d.t.sp(8); height: width; radius: width / 2
                  color: r.ink
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: r.index < 9
                  text: "Ctrl+" + (r.index + 1)
                  color: r.hot ? r.ink : d.t.fgDim
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall
                }
                Glyph {
                  app: d.app
                  anchors.verticalCenter: parent.verticalCenter
                  width: d.t.sp(16)
                  icon: r.cur ? "󰄬" : ""
                  color: r.hot ? r.ink : d.t.accent
                  size: d.t.fsIcon
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: d.hot = r.index
                onExited: if (d.hot === r.index) d.hot = -1
                onClicked: d.pick(r.index)
              }
            }
          }
        }
      }

      Item { width: parent.width; height: d.t.sp(11); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: d.t.line } }

      // Add a workspace.
      Rectangle {
        id: addRow
        readonly property int index: d.list.length
        readonly property bool hot: d.hot === index
        readonly property color ink: hot ? d.t.onColor(d.t.accent) : d.t.fg
        width: parent.width
        height: d.t.sp(30)
        radius: Math.max(4, d.t.radiusSmall)
        color: hot ? d.t.accent : "transparent"
        Row {
          anchors.left: parent.left
          anchors.leftMargin: d.t.sp(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: d.t.sp(10)
          Glyph {
            app: d.app
            anchors.verticalCenter: parent.verticalCenter
            width: d.t.sp(16)
            icon: "󰐕"
            color: addRow.ink
            size: d.t.fsIcon - 1
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: d.app.tr("Add a workspace", "Adicionar um workspace")
            color: addRow.ink
            font.family: d.t.font
            font.pixelSize: d.t.fsText - 1
          }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: d.hot = addRow.index
          onExited: if (d.hot === addRow.index) d.hot = -1
          onClicked: d.pick(addRow.index)
        }
      }
    }
  }
}
