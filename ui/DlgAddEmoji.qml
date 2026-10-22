import QtQuick
import Quickshell.Io
import "../lib/Util.js" as U
import "../lib/Emoji.js" as Emoji

// Slack's "Add emoji": a picture (chosen with the system's file chooser, or
// dropped on the previews, shown on light and on dark) and its :name:,
// taken from the file's name until one is typed. Saving uploads it
// (ws.addEmoji) and it shows up in the picker's custom tab.
DialogFrame {
  id: d
  title: app.tr("Add emoji", "Adicionar emoji")
  cardWidth: t.sp(560)
  initialFocus: nameField

  property string image: ""      // the local picture to upload
  property bool busy: false
  property string error: ""
  property bool named: false     // a name was typed: the file's no longer fills it
  // Callbacks may land after the dialog closed: they check this first.
  property var life: ({ on: true })
  Component.onDestruction: d.life.on = false

  readonly property string name: nameField.text
  readonly property bool ready: d.image !== "" && d.name !== "" && !d.busy

  // "My Cat.png" → "my_cat"
  function nameOf(s) { return String(s || "").toLowerCase().replace(/[:\s]+/g, "_").replace(/[^a-z0-9_\-]+/g, "").replace(/^[_\-]+|[_\-]+$/g, "") }

  function setImage(p) {
    if (!/\.(png|jpe?g|gif)$/i.test(p)) { d.error = d.app.tr("Use a JPG, PNG or GIF picture.", "Use uma imagem JPG, PNG ou GIF."); return }
    d.image = p
    d.error = ""
    if (!d.named) nameField.text = d.nameOf(p.split("/").pop().replace(/\.[^.]*$/, ""))
  }

  // The desktop's file chooser (Omarchy's, else zenity: U.filePicker), images only.
  Process {
    id: chooser
    command: U.filePicker(d.app.tr("Choose an image", "Escolha uma imagem"), false, "png jpg jpeg gif", d.app.tr("Images", "Imagens"))
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text).trim()
        if (p) d.setImage(p)
      }
    }
    onExited: (code, status) => {
      var why = U.filePickerError(code, d.app.lang)
      if (why) d.error = why + " " + d.app.tr("You can also drop a picture on the previews.", "Você também pode soltar uma imagem sobre as prévias.")
    }
  }
  function choose() { if (!chooser.running) chooser.running = true }

  function save() {
    if (!d.ready || !d.ws) return
    var n = d.name
    if (!/^[a-z0-9_\-]+$/.test(n)) { d.error = d.app.tr("Names can only have lowercase letters, numbers, - and _.", "Nomes só podem ter letras minúsculas, números, - e _."); return }
    if (d.ws.customEmoji[n] || d.ws.emojiAliases[n] || Emoji.standard(n)) { d.error = d.app.tr("There's already an emoji with that name.", "Já existe um emoji com esse nome."); return }
    d.busy = true
    d.error = ""
    var life = d.life, a = d.app, w = d.win
    d.ws.addEmoji(n, d.image, function(err) {
      if (!life.on) return
      d.busy = false
      if (err) { d.error = err; return }
      w.toast(a.tr("Added :", "Adicionado :") + n + ":")
      d.closed()
    })
  }

  Column {
    width: parent.width
    spacing: d.t.sp(14)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: d.app.tr("Your custom emoji will be available to everyone in your workspace. You'll find it in the custom tab of the emoji picker (the one with Slack's icon).",
                     "Seu emoji personalizado ficará disponível para todos no workspace. Ele aparece na aba de personalizados do seletor de emoji (a do ícone do Slack).")
      color: d.t.fg
      font.family: d.t.font
      font.pixelSize: d.t.fsText - 1
    }

    // ------------------------------------------------------------ the picture
    Column {
      width: parent.width
      spacing: d.t.sp(4)
      Text { text: d.app.tr("1. Upload an image", "1. Envie uma imagem"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("Square images under 128KB and with transparent backgrounds work best. If your image is too large, Slack will try to resize it.",
                       "Imagens quadradas com menos de 128KB e fundo transparente funcionam melhor. Se a imagem for grande demais, o Slack tenta redimensioná-la.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }

    Row {
      spacing: d.t.sp(10)
      Repeater {
        model: ["#f8f8f8", "#1d1d1d"]
        delegate: Rectangle {
          id: box
          required property string modelData
          width: d.t.sp(84)
          height: width
          radius: Math.max(4, d.t.radiusSmall)
          color: modelData
          border.width: drop.containsDrag ? 2 : 1
          border.color: drop.containsDrag ? d.t.accent : d.t.alpha("#808080", 0.35)
          AnimatedImage {
            anchors.centerIn: parent
            width: d.t.sp(48)
            height: width
            visible: d.image !== ""
            source: d.image ? "file://" + d.image : ""
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            playing: visible
            smooth: true
            mipmap: true
          }
          Glyph {
            app: d.app
            visible: d.image === ""
            anchors.centerIn: parent
            icon: "󰋩"
            size: d.t.sp(26)
            color: box.modelData === "#1d1d1d" ? "#e8e8e8" : "#1d1d1d"
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: d.choose() }
          DropArea {
            id: drop
            anchors.fill: parent
            onDropped: drop => {
              if (drop.hasUrls && drop.urls.length) d.setImage(decodeURIComponent(String(drop.urls[0]).replace(/^file:\/\//, "")))
            }
          }
        }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: d.t.sp(8)
        leftPadding: d.t.sp(6)
        Text {
          width: d.t.sp(220)
          elide: Text.ElideMiddle
          text: d.image ? d.image.split("/").pop() : d.app.tr("Select an image", "Selecione uma imagem")
          textFormat: Text.PlainText
          color: d.image ? d.t.fg : d.t.fgSoft
          font.family: d.t.font
          font.pixelSize: d.t.fsText - 1
        }
        SButton {
          app: d.app
          icon: "󰕒"
          text: d.image ? d.app.tr("Change image", "Trocar imagem") : d.app.tr("Upload image", "Enviar imagem")
          enabled2: !d.busy
          onClicked: d.choose()
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: d.t.line }

    // ------------------------------------------------------------ the name
    Column {
      width: parent.width
      spacing: d.t.sp(4)
      Text { text: d.app.tr("2. Give it a name", "2. Dê um nome a ele"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: d.app.tr("This is also what you'll type to add this emoji to your messages.", "É também o que você digita para usar este emoji nas mensagens.")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }

    // The name between colons, as Slack writes it: typed in lowercase,
    // spaces become _ and the colons themselves stay out of the text.
    SField {
      id: nameField
      app: d.app
      width: parent.width
      maximumLength: 100
      leftPadding: d.t.sp(10) + (text !== "" ? colon.advanceWidth : 0)
      placeholderText: ":" + d.app.tr("avocado", "abacate") + ":"
      onTextEdited: {
        d.named = text !== ""
        d.error = ""
        var s = text.toLowerCase().replace(/:/g, "").replace(/\s/g, "_")
        if (s !== text) { var c = cursorPosition; text = s; cursorPosition = Math.min(c, s.length) }
      }
      onAccepted: d.save()
      TextMetrics { id: colon; font: nameField.font; text: ":" }
      Text {
        visible: nameField.text !== ""
        x: d.t.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        text: ":"
        color: d.t.fgDim
        font: nameField.font
      }
      Text {
        visible: nameField.text !== ""
        x: Math.min(nameField.leftPadding + nameField.contentWidth, nameField.width - nameField.rightPadding)
        anchors.verticalCenter: parent.verticalCenter
        text: ":"
        color: d.t.fgDim
        font: nameField.font
      }
    }

    Text {
      visible: d.error !== ""
      width: parent.width
      wrapMode: Text.Wrap
      text: "󰗖  " + d.error
      textFormat: Text.PlainText
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
      text: d.busy ? d.app.tr("Saving…", "Salvando…") : d.app.tr("Save", "Salvar")
      enabled2: d.ready
      onClicked: d.save()
    }
  }
}
