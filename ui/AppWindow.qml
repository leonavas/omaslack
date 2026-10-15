import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Registry.js" as Reg

// The Slack window: the aubergine frame (top bar with search, rail of
// workspaces and tabs), and inside it the rounded panel with the sidebar,
// the conversation and the side pane. Menus, dialogs, search and the image
// viewer float over it.
FloatingWindow {
  id: appWin
  property var app: Reg.service
  readonly property var t: app.theme
  readonly property var ws: app.current
  property string railTab: "home"   // home | dms | activity | later
  readonly property bool menusShown: menus.shown
  readonly property Item rootItem: root
  readonly property string dialogName: dialogs.name

  // "<conversation> - <workspace> - Slack", which is also how the service
  // tells this window from the others (with the app id: the Slack desktop
  // app's title ends the same way). While a launch maps it, the one-time
  // title its window rule looks for (Service.launchWindow).
  title: {
    if (app.launchTitle) return app.launchTitle
    var parts = []
    if (appWin.ws && appWin.ws.current && appWin.ws.view === "conv") parts.push(appWin.ws.convLabel(appWin.ws.current))
    if (appWin.ws) parts.push(appWin.ws.team.name || "")
    parts.push("Slack")
    return parts.filter(function(p) { return p }).join(" - ")
  }
  visible: app.windowOpen
  implicitWidth: Math.round(app.setting("windowWidth", 1320))
  implicitHeight: Math.round(app.setting("windowHeight", 860))
  minimumSize: Qt.size(760, 480)
  color: t.frame

  onClosed: app.hideWindow()
  onVisibleChanged: if (!visible) app.windowFocused = false

  // ---------------------------------------------------------------- api
  function menu(items, x, y) { menus.open(items, x, y) }
  function menuAt(item, items, dx, dy) {
    var p = item.mapToItem(root, dx || 0, dy || item.height)
    menus.open(items, p.x, p.y)
  }
  function dialog(name, args) { dialogs.show(name, args || {}) }
  function closeDialog() { dialogs.hide() }
  function search(query) { searchLoader.query = query || ""; searchLoader.active = true }
  function emojiPicker(item, onPick, opts) { picker.openAt(item, onPick, opts || {}) }
  function viewImage(file) { viewer.file = file; viewer.active = true }
  function toast(text) { toastBox.show(text) }
  function focusComposer() { if (content.item && content.item.focusComposer) content.item.focusComposer() }

  Connections {
    target: appWin.app
    function onDialogRequested(name, args) { appWin.dialog(name, args) }
  }

  Connections {
    target: appWin.ws
    ignoreUnknownSignals: true
    function onToastSerialChanged() { if (appWin.ws.toast) toastBox.show(appWin.ws.toast) }
  }

  Item {
    id: root
    anchors.fill: parent
    focus: true

    Rectangle { anchors.fill: parent; color: appWin.t.frame }

    readonly property bool active: Window.active
    // A window on its way into the scratchpad (a background launch) has the
    // focus for a moment: that is not you looking at it.
    onActiveChanged: appWin.app.windowFocused = active && appWin.visible && !appWin.app.stowing

    // ------------------------------------------------------------ top bar
    TopBar {
      id: topBar
      app: appWin.app
      win: appWin
      ws: appWin.ws
      x: 0
      y: 0
      width: parent.width
      height: appWin.t.sp(40)
      railWidth: rail.width
    }

    // ------------------------------------------------------------ rail
    Rail {
      id: rail
      app: appWin.app
      win: appWin
      ws: appWin.ws
      y: topBar.height
      width: appWin.t.sp(72)
      height: parent.height - topBar.height
      visible: appWin.app.signedIn
    }

    // ------------------------------------------------------------ panel
    Clip {
      id: panel
      x: rail.visible ? rail.width : appWin.t.sp(8)
      y: topBar.height
      width: parent.width - x - appWin.t.sp(6)
      height: parent.height - y - appWin.t.sp(6)
      radius: Math.max(6, appWin.t.radiusCard)
      color: appWin.t.pane
      borderWidth: 1
      borderColor: appWin.t.alpha(appWin.t.fg, 0.07)

      // Not signed in (or every session expired): Slack's sign-in page.
      Loader {
        anchors.fill: parent
        active: !appWin.app.signedIn
        sourceComponent: LoginView { app: appWin.app }
      }

      Item {
        anchors.fill: parent
        visible: appWin.app.signedIn && appWin.ws !== null

        Loader {
          id: sidebarLoader
          x: 0
          y: 0
          width: sidebarWidth.value
          height: parent.height
          sourceComponent: appWin.railTab === "dms" ? dmsC : (appWin.railTab === "activity" ? activityC : (appWin.railTab === "later" ? laterC : sidebarC))
        }
        Component { id: sidebarC; Sidebar { app: appWin.app; win: appWin; ws: appWin.ws; narrow: sidebarWidth.value < appWin.t.sp(140) } }
        Component { id: dmsC; DmsList { app: appWin.app; win: appWin; ws: appWin.ws } }
        Component { id: activityC; ActivityList { app: appWin.app; win: appWin; ws: appWin.ws } }
        Component { id: laterC; LaterList { app: appWin.app; win: appWin; ws: appWin.ws } }

        QtObject {
          id: sidebarWidth
          property int value: Math.round(appWin.app.setting("sidebarWidth", appWin.t.sp(260)))
        }

        // The sidebar's edge: drag to resize, narrower than a name folds it
        // into a rail of photos.
        Rectangle {
          id: grip
          x: sidebarLoader.width - 2
          width: 5
          height: parent.height
          color: gripMa.containsMouse || gripMa.pressed ? appWin.t.alpha(appWin.t.accent, 0.5) : "transparent"
          z: 5
          MouseArea {
            id: gripMa
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            cursorShape: Qt.SplitHCursor
            property real startX: 0
            property int startW: 0
            onPressed: mouse => { startX = mapToItem(panel, mouse.x, 0).x; startW = sidebarWidth.value }
            onPositionChanged: mouse => {
              if (!pressed) return
              var nx = mapToItem(panel, mouse.x, 0).x
              var w = startW + (nx - startX)
              if (w < appWin.t.sp(150)) w = appWin.t.sp(68)
              sidebarWidth.value = Math.round(Math.max(appWin.t.sp(68), Math.min(w, panel.width * 0.45)))
            }
            onReleased: appWin.app.setSetting("sidebarWidth", sidebarWidth.value)
          }
        }

        Rectangle { x: sidebarLoader.width; width: 1; height: parent.height; color: appWin.t.line }

        // The conversation (or Threads / Drafts) and the side pane.
        Item {
          id: main
          x: sidebarLoader.width + 1
          width: parent.width - x
          height: parent.height

          Loader {
            id: content
            x: 0
            width: parent.width - (side.active ? side.width + 1 : 0)
            height: parent.height
            sourceComponent: !appWin.ws ? null : (appWin.ws.view === "threads" ? threadsC : (appWin.ws.view === "drafts" ? draftsC : convC))
          }
          Component { id: convC; ConversationView { app: appWin.app; win: appWin; ws: appWin.ws } }
          Component { id: threadsC; ThreadsView { app: appWin.app; win: appWin; ws: appWin.ws } }
          Component { id: draftsC; DraftsView { app: appWin.app; win: appWin; ws: appWin.ws } }

          Rectangle { visible: side.active; x: content.width; width: 1; height: parent.height; color: appWin.t.line }

          Loader {
            id: side
            active: !!appWin.ws && (appWin.ws.thread !== null || appWin.ws.profileUser !== "")
            x: parent.width - width
            width: Math.round(Math.min(Math.max(appWin.t.sp(360), main.width * 0.36), appWin.t.sp(560)))
            height: parent.height
            sourceComponent: appWin.ws && appWin.ws.profileUser !== "" ? profileC : threadC
          }
          Component { id: threadC; ThreadPane { app: appWin.app; win: appWin; ws: appWin.ws } }
          Component { id: profileC; ProfilePane { app: appWin.app; win: appWin; ws: appWin.ws } }
        }
      }
    }

    // ------------------------------------------------------------ overlays
    Loader {
      id: searchLoader
      property string query: ""
      anchors.fill: parent
      active: false
      z: 700
      sourceComponent: SearchOverlay {
        app: appWin.app
        win: appWin
        ws: appWin.ws
        initialQuery: searchLoader.query
        topOffset: topBar.height
        onClosed: searchLoader.active = false
      }
    }

    DialogHost {
      id: dialogs
      app: appWin.app
      win: appWin
      ws: appWin.ws
      anchors.fill: parent
    }

    EmojiPicker {
      id: picker
      app: appWin.app
      win: appWin
      ws: appWin.ws
      anchors.fill: parent
    }

    Loader {
      id: viewer
      property var file: null
      anchors.fill: parent
      active: false
      z: 850
      sourceComponent: ImageViewer {
        app: appWin.app
        ws: appWin.ws
        file: viewer.file
        onClosed: viewer.active = false
      }
    }

    MenuLayer {
      id: menus
      app: appWin.app
      anchors.fill: parent
    }

    Rectangle {
      id: toastBox
      property string text: ""
      function show(s) { toastBox.text = s; toastBox.opacity = 1; toastTimer.restart() }
      z: 950
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: appWin.t.sp(28)
      width: Math.min(parent.width - appWin.t.sp(80), toastText.implicitWidth + appWin.t.sp(32))
      height: toastText.implicitHeight + appWin.t.sp(18)
      radius: Math.max(6, appWin.t.radiusCard)
      color: appWin.t.alpha(appWin.t.bgDarker, 0.95)
      border.width: 1
      border.color: appWin.t.lineStrong
      opacity: 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      Text {
        id: toastText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, toastBox.parent.width - appWin.t.sp(112))
        text: toastBox.text
        color: appWin.t.fgBright
        font.family: appWin.t.font
        font.pixelSize: appWin.t.fsSmall + 1
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
      }
      Timer { id: toastTimer; interval: 3800; onTriggered: toastBox.opacity = 0 }
    }

    // ------------------------------------------------------------ keys
    Shortcuts {
      app: appWin.app
      win: appWin
      ws: appWin.ws
    }
  }

  // The window's size is remembered.
  onWidthChanged: sizeSave.restart()
  onHeightChanged: sizeSave.restart()
  Timer {
    id: sizeSave
    interval: 1200
    onTriggered: if (appWin.visible && appWin.width > 400) { appWin.app.setSetting("windowWidth", appWin.width); appWin.app.setSetting("windowHeight", appWin.height) }
  }
}
