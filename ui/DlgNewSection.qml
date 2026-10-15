import QtQuick
import qs.Ui

// Slack's "Create a section": a name, an optional emoji before it.
DialogFrame {
  id: d
  title: app.tr("Create a section", "Criar uma seção")
  cardWidth: t.sp(480)
  initialFocus: nameField

  property bool busy: false
  property string error: ""
  // Callbacks may land after the dialog closed: they check this first.
  property var life: ({ on: true })
  Component.onDestruction: d.life.on = false

  readonly property string name: nameField.text.trim()
  readonly property bool ready: d.name !== "" && !d.busy

  function create() {
    if (d.busy) return
    if (d.name === "") { d.error = d.app.tr("Give the section a name.", "Dê um nome à seção."); return }
    d.busy = true
    d.error = ""
    var life = d.life
    var w = d.ws
    function done(err) {
      if (!life.on) return
      d.busy = false
      if (err) d.error = err
      else d.closed()
    }
    w.createSection(d.name, done, nameField.emoji)
  }

  Column {
    width: parent.width
    spacing: d.t.sp(8)

    Text { text: d.app.tr("Name", "Nome"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }

    SectionField {
      id: nameField
      app: d.app
      win: d.win
      ws: d.ws
      width: parent.width
      placeholderText: d.app.tr("e.g. Project Unicorn", "ex.: Projeto Unicórnio")
      onEdited: d.error = ""
      onAccepted: d.create()
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: d.app.tr("Sections are only visible to you. Use them to keep channels and conversations in order; the emoji is optional.",
                     "As seções só aparecem para você. Use-as para organizar canais e conversas; o emoji é opcional.")
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
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
    height: buttons.height
    SButton {
      visible: nameField.emoji !== ""
      app: d.app
      kind: "ghost"
      icon: "󰅖"
      text: d.app.tr("Remove emoji", "Remover emoji")
      anchors.verticalCenter: parent.verticalCenter
      onClicked: nameField.removeEmoji()
    }
    Row {
      id: buttons
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
}
