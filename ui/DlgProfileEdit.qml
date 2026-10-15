import QtQuick
import Quickshell.Io
import "../lib/Util.js" as U

// "Edit your profile": full name, display name, title and the photo (picked
// with the system's file chooser, or dropped on it). Saving uploads the
// photo first, then the names (ws.saveProfile).
DialogFrame {
  id: d
  title: app.tr("Edit your profile", "Editar seu perfil")
  cardWidth: t.sp(720)
  initialFocus: realField

  readonly property var u: d.ws ? d.ws.user(d.ws.me.id) : null
  property string photo: ""      // a local file chosen to upload
  property bool busy: false
  property string error: ""

  Component.onCompleted: {
    if (!d.u) return
    realField.text = d.u.real || ""
    displayField.text = d.u.display || ""
    titleField.text = d.u.title || ""
  }

  // The desktop's file chooser (Omarchy's, else zenity: U.filePicker), images only.
  Process {
    id: chooser
    command: U.filePicker(d.app.tr("Choose a profile photo", "Escolha uma foto de perfil"), false, "png jpg jpeg gif", d.app.tr("Images", "Imagens"))
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text).trim()
        if (p) { d.photo = p; d.error = "" }
      }
    }
    onExited: (code, status) => {
      var why = U.filePickerError(code, d.app.lang)
      if (why) d.error = why + " " + d.app.tr("You can also drop a picture on the photo.", "Você também pode soltar uma imagem sobre a foto.")
    }
  }
  function choose() { if (!chooser.running) chooser.running = true }

  function save() {
    if (d.busy || !d.ws) return
    var real = realField.text.trim()
    if (!real) { d.error = d.app.tr("Your full name can't be empty.", "Seu nome completo não pode ficar vazio."); realField.forceActiveFocus(); return }
    d.busy = true
    d.error = ""
    var a = d.app, w = d.win
    d.ws.saveProfile({ real_name: real, display_name: displayField.text.trim(), title: titleField.text.trim() }, d.photo, function(err) {
      if (!d || !d.ws) return
      d.busy = false
      if (err) { d.error = err; return }
      w.toast(a.tr("Profile updated", "Perfil atualizado"))
      d.closed()
    })
  }

  Keys.onPressed: event => {
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { d.save(); event.accepted = true }
  }

  Column {
    width: parent.width
    spacing: d.t.sp(14)

    Row {
      width: parent.width
      spacing: d.t.sp(28)

      // ------------------------------------------------------------ the names
      Column {
        id: fields
        width: parent.width - photoCol.width - parent.spacing
        spacing: d.t.sp(6)

        Text { text: d.app.tr("Full name", "Nome completo"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true }
        SField {
          id: realField
          app: d.app
          width: parent.width
          maximumLength: 80
          placeholderText: d.app.tr("Full name", "Nome completo")
          onAccepted: d.save()
          KeyNavigation.tab: displayField
        }
        Item { width: 1; height: d.t.sp(8) }

        Text { text: d.app.tr("Display name", "Nome exibido"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true }
        SField {
          id: displayField
          app: d.app
          width: parent.width
          maximumLength: 80
          placeholderText: d.app.tr("Display name", "Nome exibido")
          onAccepted: d.save()
          KeyNavigation.tab: titleField
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: d.app.tr("This could be your first name or a nickname, however you'd like people to refer to you in Slack.",
                         "Pode ser seu nome ou um apelido, pense em como você quiser que as pessoas chamem você no Slack.")
          color: d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
        }
        Item { width: 1; height: d.t.sp(8) }

        Text { text: d.app.tr("Title", "Cargo"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true }
        SField {
          id: titleField
          app: d.app
          width: parent.width
          maximumLength: 120
          placeholderText: d.app.tr("Title", "Cargo")
          onAccepted: d.save()
          KeyNavigation.tab: realField
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: d.app.tr("Let people know what you do at ", "Deixe as pessoas verem o que você faz em ") + (d.ws ? d.ws.team.name || "" : "") + "."
          textFormat: Text.PlainText
          color: d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
        }

        Item { width: 1; height: d.t.sp(8); visible: !!d.u && !!d.u.tzLabel }
        Text { visible: !!d.u && !!d.u.tzLabel; text: d.app.tr("Time zone", "Fuso horário"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true }
        Text {
          visible: !!d.u && !!d.u.tzLabel
          width: parent.width
          wrapMode: Text.Wrap
          text: d.u ? (d.u.tzLabel || "") + (d.u.tzOffset !== undefined ? "  (UTC" + (d.u.tzOffset >= 0 ? "+" : "−") + Math.floor(Math.abs(d.u.tzOffset) / 3600) + (Math.abs(d.u.tzOffset) % 3600 ? ":" + String(Math.floor(Math.abs(d.u.tzOffset) % 3600 / 60)).padStart(2, "0") : "") + ")" : "") : ""
          textFormat: Text.PlainText
          color: d.t.fgSoft
          font.family: d.t.font
          font.pixelSize: d.t.fsText - 1
        }
      }

      // ------------------------------------------------------------ the photo
      Column {
        id: photoCol
        width: d.t.sp(192)
        spacing: d.t.sp(10)
        Text { text: d.app.tr("Profile photo", "Foto do perfil"); color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true }
        Item {
          width: parent.width
          height: width
          Avatar {
            anchors.fill: parent
            app: d.app
            ws: d.ws
            user: d.ws ? d.ws.me.id : ""
            url: d.photo ? "file://" + d.photo : (d.u ? (d.u.avatar512 || d.u.avatar192 || d.u.avatar || "") : "")
            size: parent.width
            round: 0.06
            onClicked: d.choose()
          }
          Rectangle {
            anchors.fill: parent
            radius: Math.round(width * 0.06)
            color: drop.containsDrag ? d.t.alpha(d.t.accent, 0.35) : "transparent"
            border.width: drop.containsDrag ? 2 : 0
            border.color: d.t.accent
          }
          DropArea {
            id: drop
            anchors.fill: parent
            onDropped: drop => {
              if (!drop.hasUrls || !drop.urls.length) return
              var p = decodeURIComponent(String(drop.urls[0]).replace(/^file:\/\//, ""))
              if (/\.(png|jpe?g|gif)$/i.test(p)) { d.photo = p; d.error = "" }
              else d.error = d.app.tr("Use a JPG, PNG or GIF picture.", "Use uma imagem JPG, PNG ou GIF.")
            }
          }
        }
        SButton {
          app: d.app
          width: parent.width
          icon: "󰕒"
          text: d.app.tr("Upload photo", "Fazer upload de foto")
          enabled2: !d.busy
          onClicked: d.choose()
        }
        Text {
          visible: d.photo !== ""
          width: parent.width
          elide: Text.ElideMiddle
          text: d.photo.split("/").pop()
          textFormat: Text.PlainText
          color: d.t.fgSoft
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          visible: d.photo !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          text: d.app.tr("Keep the current photo", "Manter a foto atual")
          color: keepMa.containsMouse ? d.t.fgBright : d.t.link
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
          font.underline: keepMa.containsMouse
          MouseArea { id: keepMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.photo = "" }
        }
        Text {
          visible: d.photo === ""
          width: parent.width
          wrapMode: Text.Wrap
          text: d.app.tr("JPG, PNG or GIF. You can also drop a picture here.", "JPG, PNG ou GIF. Você também pode soltar uma imagem aqui.")
          color: d.t.fgDim
          font.family: d.t.font
          font.pixelSize: d.t.fsTiny
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    Text {
      visible: d.error !== ""
      width: parent.width
      wrapMode: Text.Wrap
      text: d.error
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
      text: d.busy ? d.app.tr("Saving…", "Salvando…") : d.app.tr("Save changes", "Salvar alterações")
      enabled2: !d.busy
      onClicked: d.save()
    }
  }
}
