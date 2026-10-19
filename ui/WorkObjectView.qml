import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg
import "../lib/Util.js" as U

// An app's card for a link (Slack's work object, e.g. a Jira issue), as
// Slack draws it: the app's name with its menu above, then a card with the
// item's icon, title and kind, its fields as label over value, and under a
// line when it was fetched and the app's buttons. Hovered, Refresh beside
// the time asks the app for the latest (Workspace.refreshUnfurl): it shows
// "Refreshing…" until the message changes, which makes a new card, or for
// 10 s, then "Failed to refresh" for 2. `att.work` is lib/Mrkdwn.js
// workObject.
Column {
  id: wo
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  property var att: null
  property var linkHandler: null
  property var imageSource: null
  property var msg: null
  // MessageBody.press: what an app's button does.
  property var pressHandler: null
  readonly property var t: app.theme
  readonly property var w: att ? att.work : null
  readonly property int pad: t.sp(16)
  spacing: t.sp(6)

  property bool refreshing: false
  property bool failed: false
  property int tick: 0
  // Not on a shared copy of the message, as Slack.
  readonly property bool canRefresh: !!w && w.entityId !== "" && !!ws && conv !== "" && !!msg && !!msg.ts && !att.isMsg

  // When the data is from: when the app says it changed ("Updated 5 min
  // ago"), else the message's time ("As of today at 3:58 PM").
  readonly property var stampDate: !w ? null : (w.updatedAt ? new Date(w.updatedAt) : (msg && msg.ts ? U.tsDate(msg.ts) : null))
  readonly property string stamp: {
    wo.tick
    if (!wo.stampDate) return ""
    return wo.w.updatedAt ? U.updatedLabel(wo.stampDate, wo.app.lang) : U.asOfLabel(wo.stampDate, wo.app.lang, wo.app.clock24)
  }

  function refresh() {
    if (!wo.canRefresh || wo.refreshing) return
    wo.refreshing = true
    wo.failed = false
    failTimer.stop()
    timeout.restart()
    wo.ws.refreshUnfurl(wo.conv, wo.msg.ts, wo.w.entityId, function(ok) { if (!ok && wo.refreshing) wo.fail() })
  }
  function fail() {
    timeout.stop()
    wo.refreshing = false
    wo.failed = true
    failTimer.restart()
  }
  Timer { id: timeout; interval: 10000; onTriggered: wo.fail() }
  Timer { id: failTimer; interval: 2000; onTriggered: wo.failed = false }
  Timer { interval: 30000; repeat: true; running: !!wo.w && wo.w.updatedAt > 0; onTriggered: wo.tick++ }

  function src(url) { return url && wo.imageSource ? wo.imageSource(url) : "" }
  function press(c) { if (wo.pressHandler) wo.pressHandler(c); else if (c.url) wo.app.openUrl(c.url) }
  function open() { if (wo.w && wo.w.url) wo.linkHandler(wo.w.url) }

  // The app's other actions, then the link's.
  function openMenu(anchor) {
    var items = wo.w.more.map(function(c) { return { label: c.label, action: function() { wo.press(c) } } })
    if (items.length) items.push({ separator: true })
    items.push({ label: wo.app.tr("Open link", "Abrir link"), icon: "󰏌", action: function() { wo.open() } })
    items.push({ label: wo.app.tr("Copy link", "Copiar link"), icon: "󰌷", action: function() {
      wo.app.copy(wo.w.link)
      wo.win.toast(wo.app.tr("Link copied", "Link copiado"))
    } })
    wo.win.menuAt(anchor, items, 0, anchor.height + wo.t.sp(4))
  }

  function tagColor(name) {
    var c = ({ green: wo.t.green, blue: wo.t.blue, red: wo.t.red, yellow: wo.t.yellow, orange: wo.t.orange, purple: wo.t.magenta })[name]
    return c ? wo.t.alpha(c, 0.18) : (name ? wo.t.alpha(wo.t.fg, 0.08) : "transparent")
  }

  Item {
    id: head
    visible: !!wo.w && wo.w.header !== ""
    width: headRow.implicitWidth
    height: headRow.implicitHeight
    Row {
      id: headRow
      spacing: wo.t.sp(4)
      Text {
        text: wo.w ? wo.w.header : ""
        textFormat: Text.PlainText
        color: headMa.containsMouse ? wo.t.fg : wo.t.fgDim
        font.family: wo.t.font
        font.pixelSize: wo.t.fsSmall + 1
        anchors.verticalCenter: parent.verticalCenter
      }
      Glyph { app: wo.app; icon: "󰅀"; size: wo.t.fsSmall; color: headMa.containsMouse ? wo.t.fg : wo.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea {
      id: headMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: wo.openMenu(head)
    }
  }

  Rectangle {
    id: box
    visible: !!wo.w
    width: Math.min(wo.width, wo.t.sp(480))
    height: card.implicitHeight
    radius: wo.t.radiusCard
    color: boxHover.hovered ? wo.t.hover : "transparent"
    border.width: 1
    border.color: wo.t.lineStrong
    HoverHandler { id: boxHover }

    Column {
      id: card
      width: parent.width

      Column {
        x: wo.pad
        width: parent.width - 2 * wo.pad
        topPadding: wo.pad
        bottomPadding: wo.pad
        spacing: wo.t.sp(14)

        Row {
          spacing: wo.t.sp(10)
          // The item's icon, the app's own at its corner.
          Item {
            width: wo.t.sp(38)
            height: width
            Image {
              width: wo.t.sp(32); height: width
              source: wo.w ? wo.src(wo.w.icon) : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }
            Clip {
              visible: badge.source !== ""
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              width: wo.t.sp(18); height: width
              radius: wo.t.sp(4)
              Image {
                id: badge
                anchors.fill: parent
                source: wo.w ? wo.src(wo.w.badge) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
            }
          }
          Column {
            width: card.width - 2 * wo.pad - wo.t.sp(48)
            spacing: wo.t.sp(2)
            Text {
              width: Math.min(implicitWidth, parent.width)
              text: wo.w ? wo.w.title : ""
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: wo.t.fgBright
              font.family: wo.t.font
              font.pixelSize: wo.t.fsText + 1
              font.bold: true
              font.underline: titleMa.containsMouse
              MouseArea { id: titleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wo.open() }
            }
            Text {
              visible: text !== ""
              width: parent.width
              // Hovered, what a click on the title does.
              text: !wo.w ? "" : (boxHover.hovered && wo.w.url ? wo.app.tr("Open in browser", "Abrir no navegador") : wo.w.subtitle)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: wo.t.fgDim
              font.family: wo.t.font
              font.pixelSize: wo.t.fsSmall + 1
            }
          }
        }

        Flow {
          visible: !!wo.w && wo.w.fields.length > 0
          x: wo.t.sp(48)
          width: parent.width - x
          spacing: wo.t.sp(28)
          Repeater {
            model: wo.w ? wo.w.fields : []
            delegate: Column {
              required property var modelData
              spacing: wo.t.sp(6)
              Text {
                text: modelData.label
                textFormat: Text.PlainText
                color: wo.t.fgDim
                font.family: wo.t.font
                font.pixelSize: wo.t.fsSmall + 1
              }
              Row {
                spacing: wo.t.sp(6)
                Repeater {
                  model: modelData.tags
                  delegate: Rectangle {
                    id: tag
                    required property var modelData
                    readonly property string iconSrc: wo.src(modelData.icon)
                    width: tagRow.implicitWidth + (iconSrc ? 0 : 2 * wo.t.sp(5))
                    height: wo.t.sp(24)
                    radius: wo.t.radiusSmall
                    color: wo.tagColor(modelData.color)
                    Row {
                      id: tagRow
                      anchors.centerIn: parent
                      spacing: wo.t.sp(6)
                      Clip {
                        visible: tag.iconSrc !== ""
                        width: wo.t.sp(20); height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        Image { anchors.fill: parent; source: tag.iconSrc; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                      }
                      Text {
                        text: tag.modelData.text
                        textFormat: Text.PlainText
                        color: wo.t.fg
                        font.family: wo.t.font
                        font.pixelSize: wo.t.fsText
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: wo.t.line }

      Item {
        width: parent.width
        height: Math.max(stampRow.implicitHeight, buttons.implicitHeight) + 2 * wo.t.sp(12)
        Row {
          id: stampRow
          x: wo.pad
          width: Math.min(implicitWidth, parent.width - 2 * wo.pad - buttons.implicitWidth - wo.t.sp(12))
          anchors.verticalCenter: parent.verticalCenter
          spacing: wo.t.sp(6)
          clip: true
          Spinner {
            visible: wo.refreshing
            app: wo.app
            size: wo.t.fsSmall + 2
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: wo.refreshing ? wo.app.tr("Refreshing…", "Atualizando…") : (wo.failed ? wo.app.tr("Failed to refresh", "Falha ao atualizar") : wo.stamp)
            textFormat: Text.PlainText
            color: wo.t.fgDim
            font.family: wo.t.font
            font.pixelSize: wo.t.fsSmall + 1
            anchors.verticalCenter: parent.verticalCenter
            MouseArea { id: stampMa; anchors.fill: parent; hoverEnabled: true }
            // The exact moment: "Oct 19th at 3:58:51 PM".
            PanelToolTip {
              visible: stampMa.containsMouse && !wo.refreshing && !wo.failed && !!wo.stampDate
              text: wo.stampDate ? U.cardDate(wo.stampDate, wo.app.lang) + wo.app.tr(" at ", " às ") + U.time(wo.stampDate, wo.app.clock24, true) : ""
            }
          }
          Text {
            visible: wo.canRefresh && !wo.refreshing && !wo.failed && boxHover.hovered && !barHover.hovered
            text: wo.app.tr("Refresh", "Atualizar")
            textFormat: Text.PlainText
            color: wo.t.link
            font.family: wo.t.font
            font.pixelSize: wo.t.fsSmall + 1
            font.underline: refreshMa.containsMouse
            anchors.verticalCenter: parent.verticalCenter
            MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wo.refresh() }
          }
        }
        Row {
          id: buttons
          anchors.right: parent.right
          anchors.rightMargin: wo.pad
          anchors.verticalCenter: parent.verticalCenter
          spacing: wo.t.sp(8)
          // Refreshing or just failed, Slack dims them.
          opacity: wo.refreshing || wo.failed ? 0.5 : 1
          Repeater {
            model: wo.w ? wo.w.actions : []
            delegate: SButton {
              required property var modelData
              app: wo.app
              small: true
              text: modelData.label
              kind: modelData.style === "primary" ? "green" : (modelData.style === "danger" ? "danger" : "secondary")
              enabled2: !wo.refreshing && !wo.failed
              onClicked: wo.press(modelData)
            }
          }
        }
      }
    }

    // Slack's bar over a hovered card: open the link, copy it, the menu.
    Rectangle {
      visible: boxHover.hovered
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: wo.t.sp(8)
      height: wo.t.sp(34)
      width: barRow.implicitWidth + wo.t.sp(8)
      radius: Math.max(6, wo.t.radiusSmall)
      color: wo.t.popup
      border.width: 1
      border.color: wo.t.lineStrong
      HoverHandler { id: barHover }
      Row {
        id: barRow
        anchors.centerIn: parent
        spacing: wo.t.sp(1)
        IconButton { app: wo.app; size: wo.t.sp(28); icon: "󰏌"; label: wo.app.tr("Open", "Abrir"); onClicked: wo.open() }
        Rectangle { width: 1; height: wo.t.sp(18); color: wo.t.lineStrong; anchors.verticalCenter: parent.verticalCenter }
        IconButton {
          app: wo.app
          size: wo.t.sp(28)
          icon: "󰌷"
          tip: wo.app.tr("Copy link", "Copiar link")
          onClicked: { wo.app.copy(wo.w.link); wo.win.toast(wo.app.tr("Link copied", "Link copiado")) }
        }
        IconButton { id: moreBtn; app: wo.app; size: wo.t.sp(28); icon: "󰇙"; tip: wo.app.tr("More actions", "Mais ações"); onClicked: wo.openMenu(moreBtn) }
      }
    }
  }
}
