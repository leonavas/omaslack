import QtQuick
import qs.Ui

// Slack's "Rename this section": the name and its emoji in one field, Save
// once either changed. args: {section: id}.
DialogFrame {
  id: d
  title: app.tr("Rename this section", "Renomear esta seção")
  cardWidth: t.sp(480)
  initialFocus: nameField

  property string origName: ""
  property string origEmoji: ""
  property bool busy: false
  property string error: ""
  // Callbacks may land after the dialog closed: they check this first.
  property var life: ({ on: true })
  Component.onDestruction: d.life.on = false

  readonly property string name: nameField.text.trim()
  readonly property bool changed: d.name !== d.origName || nameField.emoji !== d.origEmoji
  readonly property bool ready: d.name !== "" && d.changed && !d.busy

  Component.onCompleted: {
    var s = d.ws ? d.ws.sections.filter(function(x) { return x.id === d.args.section })[0] : null
    d.origName = s ? s.name : (d.args.name || "")
    d.origEmoji = s ? s.emoji : (d.args.emoji || "")
    nameField.text = d.origName
    nameField.emoji = d.origEmoji
  }

  function save() {
    if (!d.ready) return
    d.busy = true
    d.error = ""
    var life = d.life
    d.ws.renameSection(d.args.section, d.name, nameField.emoji, function(err) {
      if (!life.on) return
      d.busy = false
      if (err) d.error = err
      else d.closed()
    })
  }

  Column {
    width: parent.width
    spacing: d.t.sp(8)

    SectionField {
      id: nameField
      app: d.app
      win: d.win
      ws: d.ws
      width: parent.width
      placeholderText: d.app.tr("Section name", "Nome da seção")
      onEdited: d.error = ""
      onAccepted: d.save()
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
        text: d.busy ? d.app.tr("Saving…", "Salvando…") : d.app.tr("Save", "Salvar")
        enabled2: d.ready
        onClicked: d.save()
      }
    }
  }
}
