import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji

// "Set a status": the emoji button and the text (100 characters), Slack's
// five suggestions, when it clears itself (a preset or a day and time you
// pick), Save; "Clear status" while one is set. Opens with your current
// status filled in.
DialogFrame {
  id: d
  title: app.tr("Set a status", "Definir um status")
  cardWidth: t.sp(540)
  initialFocus: field

  readonly property var current: d.ws ? d.ws.statusOf(d.ws.me.id) : null
  property string emoji: ""        // Slack name, no colons
  property string unicodeGlyph: "" // a status set elsewhere with a unicode emoji only
  property string clearAfter: "never"
  // "custom": a day (0 = today … 13) and a time of day in minutes.
  property int customDay: 0
  property int customMin: -1
  property bool customTimeOk: true
  property real now: Date.now()
  readonly property int customExp: d.customMin < 0 ? 0 : Math.floor(d.customDate(d.customDay, d.customMin).getTime() / 1000)
  readonly property bool customOk: d.customTimeOk && d.customExp * 1000 > d.now
  readonly property bool canSave: d.clearAfter !== "custom" || d.customOk

  Timer { interval: 30000; running: d.clearAfter === "custom"; repeat: true; onTriggered: d.now = Date.now() }

  readonly property var presets: [
    { emoji: "date", en: "In a meeting", pt: "Em reunião", after: "1h" },
    { emoji: "bus", en: "Commuting", pt: "Em trânsito", after: "30m" },
    { emoji: "face_with_thermometer", en: "Out sick", pt: "Doente", after: "today" },
    { emoji: "palm_tree", en: "Vacationing", pt: "De férias", after: "never" },
    { emoji: "house_with_garden", en: "Working remotely", pt: "Trabalhando remotamente", after: "today" }
  ]
  readonly property var afterOptions: {
    var out = []
    if (d.current && d.current.exp > 0) out.push({ value: "keep", label: d.cap(U.untilLabel(d.current.exp, d.app.lang, d.app.clock24)) })
    out.push({ value: "never", label: d.app.tr("Don't clear", "Não limpar") })
    out.push({ value: "30m", label: d.app.tr("30 minutes", "30 minutos") })
    out.push({ value: "1h", label: d.app.tr("1 hour", "1 hora") })
    out.push({ value: "4h", label: d.app.tr("4 hours", "4 horas") })
    out.push({ value: "today", label: d.app.tr("Today", "Hoje") })
    out.push({ value: "week", label: d.app.tr("This week", "Esta semana") })
    out.push({ value: "custom", label: d.app.tr("Date and time", "Data e hora"), menu: d.app.tr("Choose date and time…", "Escolher data e hora…") })
    return out
  }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
  function afterLabel(v) {
    var o = d.afterOptions.filter(function(x) { return x.value === v })[0]
    return o ? o.label : ""
  }
  function expiry(v) {
    var now = Math.floor(Date.now() / 1000)
    if (v === "keep") return d.current ? d.current.exp : 0
    if (v === "30m") return now + 30 * 60
    if (v === "1h") return now + 3600
    if (v === "4h") return now + 4 * 3600
    if (v === "today") return U.endOfToday()
    if (v === "week") return U.endOfWeek()
    if (v === "custom") return d.customExp
    return 0
  }

  function customDate(day, min) {
    var n = new Date()
    return new Date(n.getFullYear(), n.getMonth(), n.getDate() + day, Math.floor(min / 60), min % 60, 0)
  }
  function dayName(i) {
    if (i === 0) return d.app.tr("Today", "Hoje")
    if (i === 1) return d.app.tr("Tomorrow", "Amanhã")
    var x = d.customDate(i, 0), pt = d.app.lang === "pt-BR"
    var wd = d.cap((pt ? U.DAYS_PT : U.DAYS_EN)[x.getDay()].slice(0, 3))
    return pt ? wd + ", " + String(x.getDate()).padStart(2, "0") + "/" + String(x.getMonth() + 1).padStart(2, "0")
              : wd + ", " + U.MON_EN[x.getMonth()] + " " + x.getDate()
  }
  function timeText(min) { return U.time(new Date(2000, 0, 1, Math.floor(min / 60), min % 60), d.app.clock24) }
  // "17:30", "1730", "17h30", "9", "5:30 pm", "5pm" → minutes of the day; -1 if not a time.
  function parseTime(s) {
    var m = String(s).trim().toLowerCase().match(/^(\d{1,2})(?:[:h.]?(\d{2}))?\s*(?:(a|p)\.?\s*m?\.?)?$/)
    if (!m) return -1
    var h = Number(m[1]), mi = m[2] ? Number(m[2]) : 0
    if (mi > 59) return -1
    if (m[3]) { if (h < 1 || h > 12) return -1; h = h % 12 + (m[3] === "p" ? 12 : 0) }
    else if (h > 23) return -1
    return h * 60 + mi
  }
  // First time "custom" is picked: the current status' expiry if it's within
  // two weeks, else the next full hour.
  function startCustom() {
    if (d.customMin < 0) {
      var exp = d.current && d.current.exp > 0 ? new Date(d.current.exp * 1000) : null
      var ahead = exp ? -U.dayDiff(exp, new Date()) : -1
      if (exp && ahead >= 0 && ahead <= 13) { d.customDay = ahead; d.customMin = exp.getHours() * 60 + exp.getMinutes() }
      else {
        var n = new Date(), next = n.getHours() + 1
        d.customDay = next >= 24 ? 1 : 0
        d.customMin = (next % 24) * 60
      }
      timeField.text = d.timeText(d.customMin)
      d.customTimeOk = true
    }
    d.now = Date.now()
    d.clearAfter = "custom"
    Qt.callLater(function() { timeField.forceActiveFocus(); timeField.selectAll() })
  }
  function stepTime(delta) {
    var base = d.customTimeOk ? d.customMin : 0
    var m = Math.floor(base / 15) * 15 + (base % 15 && delta < 0 ? 15 : 0) + delta
    if (m < 0) { if (d.customDay > 0) { d.customDay--; m += 1440 } else m = 0 }
    if (m >= 1440) { if (d.customDay < 13) { d.customDay++; m -= 1440 } else m = 1439 }
    d.customMin = m
    d.customTimeOk = true
    timeField.text = d.timeText(m)
  }
  function dayMenu() {
    var items = []
    for (var i = 0; i < 14; i++) (function(i) {
      items.push({ label: d.dayName(i), checked: i === d.customDay, action: function() { d.customDay = i } })
    })(i)
    d.win.menuAt(dayBtn, items, 0, dayBtn.height + d.t.sp(4))
  }

  Component.onCompleted: {
    var s = d.current
    if (!s) return
    d.emoji = s.emoji ? s.emoji.replace(/^:|:$/g, "") : ""
    d.unicodeGlyph = !s.emoji && s.unicode ? Emoji.fromHex(s.unicode) : ""
    field.text = s.text || ""
    d.clearAfter = s.exp > 0 ? "keep" : "never"
  }

  function applyPreset(p) {
    d.emoji = p.emoji
    d.unicodeGlyph = ""
    field.text = d.app.tr(p.en, p.pt)
    d.clearAfter = p.after
    field.forceActiveFocus()
    field.cursorPosition = field.length
  }
  function save() {
    if (!d.ws || !d.canSave) return
    var text = field.text.trim().slice(0, 100)
    var name = d.emoji || (d.unicodeGlyph ? Emoji.shortcodeOf(d.unicodeGlyph) : "")
    if (!name && !text) d.ws.setStatus("", "", 0)
    else d.ws.setStatus(name ? ":" + name + ":" : "", text, d.expiry(d.clearAfter))
    d.closed()
  }
  function clearStatus() { if (d.ws) d.ws.setStatus("", "", 0); d.closed() }
  function afterMenu() {
    d.win.menuAt(afterBtn, d.afterOptions.map(function(o) {
      return { label: o.menu || o.label, checked: o.value === d.clearAfter,
               action: function() { if (o.value === "custom") d.startCustom(); else d.clearAfter = o.value } }
    }), 0, afterBtn.height + d.t.sp(4))
  }
  function pickEmoji() {
    d.win.emojiPicker(emojiBtn, function(name) { d.emoji = name; d.unicodeGlyph = ""; field.forceActiveFocus() }, {})
  }

  Keys.onPressed: event => {
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { d.save(); event.accepted = true }
  }

  Column {
    width: parent.width
    spacing: d.t.sp(14)

    // The emoji and the text, one field.
    Item {
      width: parent.width
      height: field.implicitHeight

      SField {
        id: field
        app: d.app
        anchors.fill: parent
        leftPadding: d.t.sp(48)
        rightPadding: d.t.sp(field.text !== "" || d.emoji !== "" ? 64 : 12)
        topPadding: d.t.sp(11)
        bottomPadding: d.t.sp(11)
        maximumLength: 100
        placeholderText: d.app.tr("What's your status?", "O que você está fazendo?")
        onAccepted: d.save()
        Keys.onPressed: event => {
          if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { field.text = ""; event.accepted = true }
        }
      }

      Rectangle {
        id: emojiBtn
        x: d.t.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        width: d.t.sp(34)
        height: d.t.sp(30)
        radius: Math.max(4, d.t.radiusSmall)
        color: ema.containsMouse ? d.t.hoverStrong : d.t.hover
        // Made anew for each emoji (EmojiIcon's name isn't meant to go from empty to set).
        Loader {
          anchors.centerIn: parent
          active: d.emoji !== "" || d.unicodeGlyph !== ""
          sourceComponent: EmojiIcon { app: d.app; ws: d.ws; name: d.emoji; glyph: d.unicodeGlyph; size: d.t.sp(20) }
        }
        Glyph {
          anchors.centerIn: parent
          app: d.app
          visible: d.emoji === "" && d.unicodeGlyph === ""
          icon: "󰞅"
          size: d.t.fsTitle + 3
          color: d.t.fgDim
        }
        MouseArea {
          id: ema
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: mouse => { if (mouse.button === Qt.RightButton) { d.emoji = ""; d.unicodeGlyph = "" } else d.pickEmoji() }
        }
        PanelToolTip { visible: ema.containsMouse; text: d.app.tr("Change emoji (right click removes it)", "Trocar emoji (clique direito remove)") }
      }

      Text {
        anchors.right: clearField.left
        anchors.rightMargin: d.t.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        visible: field.length >= 80
        text: String(100 - field.length)
        color: field.length >= 100 ? d.t.red : d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
      IconButton {
        id: clearField
        app: d.app
        visible: field.text !== "" || d.emoji !== "" || d.unicodeGlyph !== ""
        anchors.right: parent.right
        anchors.rightMargin: d.t.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        size: d.t.sp(24)
        icon: "󰅙"
        iconSize: d.t.fsTitle
        tip: d.app.tr("Clear", "Limpar")
        onClicked: { field.text = ""; d.emoji = ""; d.unicodeGlyph = ""; d.clearAfter = "never"; field.forceActiveFocus() }
      }
    }

    // When it goes away.
    Row {
      spacing: d.t.sp(10)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: d.app.tr("Clear after", "Limpar após")
        color: d.t.fg
        font.family: d.t.font
        font.pixelSize: d.t.fsText - 1
        font.bold: true
      }
      Rectangle {
        id: afterBtn
        anchors.verticalCenter: parent.verticalCenter
        width: afterRow.implicitWidth + d.t.sp(24)
        height: d.t.sp(32)
        radius: Math.max(4, d.t.radiusSmall)
        color: ama.containsMouse ? d.t.hover : "transparent"
        border.width: 1
        border.color: d.t.lineStrong
        Row {
          id: afterRow
          anchors.centerIn: parent
          spacing: d.t.sp(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: d.afterLabel(d.clearAfter)
            color: d.t.fg
            font.family: d.t.font
            font.pixelSize: d.t.fsText - 1
          }
          Glyph { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰅀"; size: d.t.fsSmall; color: d.t.fgDim }
        }
        MouseArea {
          id: ama
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: d.afterMenu()
        }
      }
    }

    // A day and time of your own.
    Row {
      visible: d.clearAfter === "custom"
      spacing: d.t.sp(10)
      Rectangle {
        id: dayBtn
        anchors.verticalCenter: parent.verticalCenter
        width: dayRow.implicitWidth + d.t.sp(24)
        height: d.t.sp(32)
        radius: Math.max(4, d.t.radiusSmall)
        color: dma.containsMouse ? d.t.hover : "transparent"
        border.width: 1
        border.color: d.t.lineStrong
        Row {
          id: dayRow
          anchors.centerIn: parent
          spacing: d.t.sp(8)
          Glyph { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰃭"; size: d.t.fsSmall; color: d.t.fgDim }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: d.dayName(d.customDay)
            color: d.t.fg
            font.family: d.t.font
            font.pixelSize: d.t.fsText - 1
          }
          Glyph { app: d.app; anchors.verticalCenter: parent.verticalCenter; icon: "󰅀"; size: d.t.fsSmall; color: d.t.fgDim }
        }
        MouseArea {
          id: dma
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: d.dayMenu()
        }
      }
      SField {
        id: timeField
        app: d.app
        anchors.verticalCenter: parent.verticalCenter
        width: d.t.sp(d.app.clock24 ? 84 : 110)
        height: d.t.sp(32)
        topPadding: 0
        bottomPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        font.pixelSize: d.t.fsText - 1
        maximumLength: 10
        placeholderText: d.app.clock24 ? "17:30" : "5:30 PM"
        onTextEdited: {
          var m = d.parseTime(text)
          d.customTimeOk = m >= 0
          if (m >= 0) d.customMin = m
          d.now = Date.now()
        }
        onEditingFinished: if (d.customTimeOk) text = d.timeText(d.customMin)
        onAccepted: d.save()
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Up) d.stepTime(15)
          else if (event.key === Qt.Key_Down) d.stepTime(-15)
          else return
          event.accepted = true
        }
        PanelToolTip { visible: timeField.hovered && !timeField.activeFocus; text: d.app.tr("Type a time (↑ ↓ change it by 15 minutes)", "Digite um horário (↑ ↓ mudam de 15 em 15 minutos)") }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: !d.customTimeOk ? d.app.tr("Not a valid time", "Horário inválido")
              : !d.customOk ? d.app.tr("Pick a time in the future", "Escolha um horário no futuro")
              : d.cap(U.untilLabel(d.customExp, d.app.lang, d.app.clock24))
        color: d.customOk ? d.t.fgDim : d.t.red
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }

    // Slack's suggestions.
    Column {
      width: parent.width
      spacing: d.t.sp(2)
      Text {
        text: d.ws ? d.app.tr("For ", "Para ") + (d.ws.team.name || "") + ":" : d.app.tr("Suggestions", "Sugestões")
        textFormat: Text.PlainText
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
        font.bold: true
        bottomPadding: d.t.sp(4)
      }
      Repeater {
        model: d.presets
        delegate: Rectangle {
          required property var modelData
          width: parent.width
          height: d.t.sp(36)
          radius: Math.max(4, d.t.radiusSmall)
          color: pma.containsMouse ? d.t.hover : "transparent"
          Row {
            x: d.t.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: d.t.sp(12)
            EmojiIcon { app: d.app; ws: d.ws; name: modelData.emoji; size: d.t.sp(20); anchors.verticalCenter: parent.verticalCenter }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: d.app.tr(modelData.en, modelData.pt)
              color: d.t.fg
              font.family: d.t.font
              font.pixelSize: d.t.fsText - 1
              font.bold: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "— " + d.afterLabel(modelData.after)
              color: d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsText - 1
            }
          }
          MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.applyPreset(modelData) }
        }
      }
    }
  }

  footer: Item {
    width: parent.width
    height: buttons.height
    SButton {
      visible: !!d.current
      app: d.app
      text: d.app.tr("Clear status", "Limpar status")
      anchors.verticalCenter: parent.verticalCenter
      onClicked: d.clearStatus()
    }
    Row {
      id: buttons
      anchors.right: parent.right
      spacing: d.t.sp(10)
      SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
      SButton { app: d.app; kind: "primary"; text: d.app.tr("Save", "Salvar"); enabled2: d.canSave; onClicked: d.save() }
    }
  }
}
