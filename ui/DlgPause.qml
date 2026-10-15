import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U

// "Pause notifications" until a day and time you pick: the next seven days,
// then the half-hour slots of that day (past ones greyed out). Pausing
// applies to every signed-in workspace.
DialogFrame {
  id: d
  title: app.tr("Pause notifications", "Pausar notificações")
  subtitle: app.workspaces.length > 1
            ? app.tr("Applies to every signed-in workspace.", "Vale para todos os workspaces conectados.")
            : app.tr("You won't get notifications until then.", "Você não recebe notificações até lá.")
  cardWidth: t.sp(560)

  property int day: 0          // 0 = today … 6
  property int slot: 0         // 0 = 00:00 … 47 = 23:30
  property real now: Date.now()

  // Every half minute, so "past" slots and the summary stay true.
  Timer { interval: 30000; running: true; repeat: true; onTriggered: d.now = Date.now() }

  function dateOf(day) {
    var n = new Date(d.now)
    return new Date(n.getFullYear(), n.getMonth(), n.getDate() + day)
  }
  function at(day, slot) {
    var b = d.dateOf(day)
    return new Date(b.getFullYear(), b.getMonth(), b.getDate(), Math.floor(slot / 2), (slot % 2) * 30, 0)
  }
  function past(day, slot) { return d.at(day, slot).getTime() <= d.now }
  readonly property int minutes: Math.ceil((d.at(d.day, d.slot).getTime() - d.now) / 60000)
  function span(min) {
    var h = Math.floor(min / 60), m = min % 60
    var parts = []
    if (h >= 24) { var days = Math.floor(h / 24); h = h % 24; parts.push(days + (d.app.lang === "pt-BR" ? (days === 1 ? " dia" : " dias") : (days === 1 ? " day" : " days"))) }
    if (h) parts.push(h + " h")
    if (m && parts.length < 2) parts.push(m + " min")
    return parts.join(" ") || "1 min"
  }

  Component.onCompleted: {
    var n = new Date()
    var s = Math.floor((n.getHours() * 60 + n.getMinutes()) / 30) + 1
    if (s >= 48) { d.day = 1; d.slot = 0 } else { d.day = 0; d.slot = s }
    Qt.callLater(function() { times.reveal() })
  }

  function pickDay(i) {
    d.day = Math.max(0, Math.min(6, i))
    if (d.past(d.day, d.slot)) {
      for (var s = 0; s < 48; s++) if (!d.past(d.day, s)) { d.slot = s; break }
    }
    times.reveal()
  }
  function pickSlot(s) {
    if (s < 0 && d.day > 0) { d.day--; s = 47 }
    if (s > 47 && d.day < 6) { d.day++; s = 0 }
    s = Math.max(0, Math.min(47, s))
    if (d.past(d.day, s)) return
    d.slot = s
    times.reveal(true)
  }
  function save() {
    if (d.minutes <= 0) return
    var a = d.app, w = d.win, min = d.minutes
    var label = U.untilLabel(Math.floor(d.at(d.day, d.slot).getTime() / 1000), a.lang, a.clock24)
    d.closed()
    a.pauseAll(min)
    w.toast(a.tr("Notifications paused ", "Notificações pausadas ") + label)
  }

  Keys.onPressed: event => {
    var k = event.key
    if (k === Qt.Key_Left) d.pickDay(d.day - 1)
    else if (k === Qt.Key_Right) d.pickDay(d.day + 1)
    else if (k === Qt.Key_Up) d.pickSlot(d.slot - 1)
    else if (k === Qt.Key_Down) d.pickSlot(d.slot + 1)
    else if (k === Qt.Key_PageUp) d.pickSlot(d.slot - 6)
    else if (k === Qt.Key_PageDown) d.pickSlot(d.slot + 6)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) d.save()
    else return
    event.accepted = true
  }

  Column {
    width: parent.width
    spacing: d.t.sp(10)

    Text {
      id: dayLabel
      text: d.app.tr("Day", "Dia")
      color: d.t.fg
      font.family: d.t.font
      font.pixelSize: d.t.fsText - 1
      font.bold: true
    }

    // The next seven days, as calendar tiles.
    Row {
      id: days
      width: parent.width
      spacing: d.t.sp(6)
      readonly property int tileW: Math.floor((width - spacing * 6) / 7)
      Repeater {
        model: 7
        delegate: Rectangle {
          required property int index
          readonly property date date: d.dateOf(index)
          readonly property bool on: d.day === index
          width: days.tileW
          height: d.t.sp(66)
          radius: Math.max(6, d.t.radiusSmall)
          color: on ? d.t.accent : (dma.containsMouse ? d.t.hover : "transparent")
          border.width: on ? 0 : 1
          border.color: d.t.lineStrong
          Column {
            anchors.centerIn: parent
            spacing: 1
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: index === 0 ? d.app.tr("Today", "Hoje") : (index === 1 ? d.app.tr("Tomorrow", "Amanhã") : (d.app.lang === "pt-BR" ? U.DAYS_PT : U.DAYS_EN)[date.getDay()].slice(0, 3))
              color: parent.parent.on ? d.t.selectedText : d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsTiny
              font.bold: index < 2
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: String(date.getDate())
              color: parent.parent.on ? d.t.selectedText : d.t.fgBright
              font.family: d.t.font
              font.pixelSize: d.t.fsHeader
              font.bold: true
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: (d.app.lang === "pt-BR" ? U.MON_PT : U.MON_EN)[date.getMonth()]
              color: parent.parent.on ? d.t.selectedText : d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsTiny
            }
          }
          MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.pickDay(index) }
        }
      }
    }

    Item { width: 1; height: d.t.sp(2) }

    Text {
      id: timeLabel
      text: d.app.tr("Time", "Hora")
      color: d.t.fg
      font.family: d.t.font
      font.pixelSize: d.t.fsText - 1
      font.bold: true
    }

    // Half-hour slots of that day.
    Flickable {
      id: times
      width: parent.width
      // As tall as the window allows (zoom, small windows), up to 200.
      readonly property real room: d.maxHeight - d.t.sp(64) - d.t.sp(34) - d.t.px(24) * 1.35 - d.t.fsSmall * 1.4 - d.t.sp(4)
                                   - dayLabel.height - days.height - d.t.sp(2) - timeLabel.height - summaryBox.height - d.t.sp(10) * 5
      height: Math.max(d.t.sp(66), Math.min(grid.implicitHeight, d.t.sp(200), room))
      contentHeight: grid.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThinScroll { app: d.app }
      // The chosen slot's row near the top (follow = only scroll if it's out of view).
      function reveal(follow) {
        var it = slots.itemAt(d.slot)
        if (!it) return
        var top = Math.max(0, Math.min(times.contentHeight - times.height, it.y - it.height - grid.spacing))
        if (!follow) times.contentY = top
        else if (it.y < times.contentY) times.contentY = it.y
        else if (it.y + it.height > times.contentY + times.height) times.contentY = it.y + it.height - times.height
      }
      Flow {
        id: grid
        width: times.width - d.t.sp(10)
        spacing: d.t.sp(6)
        readonly property int cols: 6
        readonly property int cellW: Math.floor((width - spacing * (cols - 1)) / cols)
        Repeater {
          id: slots
          model: 48
          delegate: Rectangle {
            required property int index
            readonly property bool on: d.slot === index
            readonly property bool gone: d.past(d.day, index)
            width: grid.cellW
            height: d.t.sp(30)
            radius: Math.max(4, d.t.radiusSmall)
            color: on ? d.t.accent : (tma.containsMouse && !gone ? d.t.hover : "transparent")
            border.width: on ? 0 : 1
            border.color: d.t.line
            opacity: gone ? 0.35 : 1
            Text {
              anchors.centerIn: parent
              text: U.time(d.at(0, index), d.app.clock24)
              color: parent.on ? d.t.selectedText : d.t.fg
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              font.bold: parent.on
            }
            MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; enabled: !parent.gone; cursorShape: Qt.PointingHandCursor; onClicked: d.pickSlot(index) }
          }
        }
      }
    }

    // What it will do.
    Rectangle {
      id: summaryBox
      width: parent.width
      height: summary.implicitHeight + d.t.sp(18)
      radius: Math.max(6, d.t.radiusSmall)
      color: d.minutes > 0 ? d.t.alpha(d.t.yellow, 0.10) : d.t.alpha(d.t.red, 0.10)
      border.width: 1
      border.color: d.minutes > 0 ? d.t.alpha(d.t.yellow, 0.35) : d.t.alpha(d.t.red, 0.4)
      Glyph {
        id: bell
        app: d.app
        x: d.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰂛"
        size: d.t.fsTitle
        color: d.minutes > 0 ? d.t.yellow : d.t.red
      }
      Text {
        id: summary
        anchors.left: bell.right
        anchors.leftMargin: d.t.sp(10)
        anchors.right: parent.right
        anchors.rightMargin: d.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: d.minutes > 0
              ? d.app.tr("Notifications paused ", "Notificações pausadas ") + "<b>" + U.untilLabel(Math.floor(d.at(d.day, d.slot).getTime() / 1000), d.app.lang, d.app.clock24) + "</b>"
                + "<font color=\"" + d.t.hex(d.t.fgDim) + "\"> · " + d.app.tr("for ", "por ") + d.span(d.minutes) + "</font>"
              : d.app.tr("Pick a date and time in the future.", "Escolha uma data e hora no futuro.")
        color: d.t.fg
        font.family: d.t.font
        font.pixelSize: d.t.fsText - 1
      }
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton { app: d.app; kind: "primary"; icon: "󰂛"; text: d.app.tr("Pause", "Pausar"); enabled2: d.minutes > 0; onClicked: d.save() }
  }
}
