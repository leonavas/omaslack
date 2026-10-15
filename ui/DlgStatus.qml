import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji

// "Set a status": the emoji button and the text (100 characters), Slack's
// five suggestions, when it clears itself, Save; "Clear status" while one is
// set. Opens with your current status filled in.
DialogFrame {
  id: d
  title: app.tr("Set a status", "Definir um status")
  cardWidth: t.sp(540)
  initialFocus: field

  readonly property var current: d.ws ? d.ws.statusOf(d.ws.me.id) : null
  property string emoji: ""        // Slack name, no colons
  property string unicodeGlyph: "" // a status set elsewhere with a unicode emoji only
  property string clearAfter: "never"

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
    return 0
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
    if (!d.ws) return
    var text = field.text.trim().slice(0, 100)
    var name = d.emoji || (d.unicodeGlyph ? Emoji.shortcodeOf(d.unicodeGlyph) : "")
    if (!name && !text) d.ws.setStatus("", "", 0)
    else d.ws.setStatus(name ? ":" + name + ":" : "", text, d.expiry(d.clearAfter))
    d.closed()
  }
  function clearStatus() { if (d.ws) d.ws.setStatus("", "", 0); d.closed() }
  function afterMenu() {
    d.win.menuAt(afterBtn, d.afterOptions.map(function(o) {
      return { label: o.label, checked: o.value === d.clearAfter, action: function() { d.clearAfter = o.value } }
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

    // Slack's suggestions.
    Column {
      width: parent.width
      spacing: d.t.sp(2)
      Text {
        text: d.ws ? d.app.tr("For ", "Para ") + (d.ws.team.name || "") + ":" : d.app.tr("Suggestions", "Sugestões")
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
      SButton { app: d.app; kind: "primary"; text: d.app.tr("Save", "Salvar"); onClicked: d.save() }
    }
  }
}
