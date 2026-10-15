import QtQuick
import "../lib/Util.js" as U

// Slack's "Create a channel": the name, written the way Slack keeps it
// (lowercase, hyphens, at most 80 characters) as it is typed, an optional
// description and who can see it.
DialogFrame {
  id: d
  title: app.tr("Create a channel", "Criar um canal")
  cardWidth: t.sp(540)
  initialFocus: nameField

  property bool isPrivate: false
  property bool busy: false
  property string error: ""
  property var life: ({ on: true })
  Component.onDestruction: d.life.on = false

  readonly property string name: U.normalizeChannel(nameField.text).replace(/^[-_]+|[-_]+$/g, "")
  readonly property bool ready: d.name !== "" && !d.busy

  // What Slack does while you type: lowercase, spaces become hyphens,
  // anything but letters, digits, - and _ is dropped (not trimmed: the
  // hyphen you just typed stays).
  function tidy(s) {
    s = String(s || "").toLowerCase().replace(/\s/g, "-")
    var out = ""
    for (var i = 0; i < s.length; i++) {
      var c = s[i]
      if (/[a-z0-9_-]/.test(c) || U.isLetter(c)) out += c
    }
    return out
  }

  function retype() {
    var p = nameField.cursorPosition
    var before = d.tidy(nameField.text.slice(0, p))
    var after = d.tidy(nameField.text.slice(p))
    var next = (before + after).slice(0, 80)
    if (next !== nameField.text) {
      nameField.text = next
      nameField.cursorPosition = Math.min(before.length, next.length)
    }
  }

  function create() {
    if (d.busy) return
    if (d.name === "") { d.error = d.app.tr("Give the channel a name.", "Dê um nome ao canal."); nameField.forceActiveFocus(); return }
    d.busy = true
    d.error = ""
    var life = d.life
    d.ws.createChannel(d.name, d.isPrivate, purposeField.text.trim(), function(err) {
      if (!life.on) return
      d.busy = false
      if (err) { d.error = err; nameField.forceActiveFocus() }
      else d.closed()
    }, d.args.section || "")
  }

  Keys.onPressed: event => {
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { d.create(); event.accepted = true }
  }

  Column {
    width: parent.width
    spacing: d.t.sp(8)

    Text { text: d.app.tr("Name", "Nome"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }

    Item {
      width: parent.width
      height: nameField.implicitHeight
      SField {
        id: nameField
        app: d.app
        anchors.fill: parent
        leftPadding: d.t.sp(32)
        rightPadding: d.t.sp(44)
        maximumLength: 80
        placeholderText: d.app.tr("e.g. plan-budget", "ex.: plano-orcamento")
        onTextEdited: { d.retype(); d.error = "" }
        onAccepted: purposeField.forceActiveFocus()
      }
      Glyph {
        x: d.t.sp(11)
        anchors.verticalCenter: parent.verticalCenter
        app: d.app
        icon: d.isPrivate ? "󰌾" : "#"
        size: d.isPrivate ? d.t.fsText : d.t.fsTitle
        color: nameField.text !== "" ? d.t.fg : d.t.fgDim
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: d.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        text: String(80 - nameField.length)
        color: nameField.length >= 80 ? d.t.red : d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: d.app.tr("Channels are where conversations happen around a topic. Use a name that is easy to find and understand.",
                     "Canais são onde as conversas acontecem em torno de um tema. Use um nome fácil de achar e de entender.")
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }

    Item { width: 1; height: d.t.sp(6) }

    Row {
      spacing: d.t.sp(6)
      Text { text: d.app.tr("Description", "Descrição"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
      Text { text: d.app.tr("(optional)", "(opcional)"); color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsText }
    }
    SField {
      id: purposeField
      app: d.app
      width: parent.width
      maximumLength: 250
      placeholderText: d.app.tr("What is this channel about?", "Sobre o que é este canal?")
      onAccepted: d.create()
    }

    Item { width: 1; height: d.t.sp(6) }

    Text { text: d.app.tr("Visibility", "Visibilidade"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
    Choice {
      app: d.app
      width: parent.width
      value: d.isPrivate ? "private" : "public"
      options: [
        { value: "public", label: d.app.tr("Public — anyone in ", "Público — qualquer pessoa de ") + (d.ws ? d.ws.team.name : ""),
          hint: d.app.tr("Anyone in the workspace can find and join it", "Qualquer pessoa do workspace pode achar e entrar") },
        { value: "private", label: d.app.tr("Private — only specific people", "Privado — só pessoas específicas"),
          hint: d.app.tr("Can only be viewed or joined by invitation", "Só pode ser visto ou acessado com convite") }
      ]
      onPicked: v => d.isPrivate = v === "private"
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

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton {
      app: d.app
      kind: "primary"
      text: d.busy ? d.app.tr("Creating…", "Criando…") : d.app.tr("Create", "Criar")
      enabled2: d.ready
      onClicked: d.create()
    }
  }
}
