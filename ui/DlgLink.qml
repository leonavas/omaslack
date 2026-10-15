import QtQuick

// Slack's "Add link": the words to show and the address. Slack's markup
// has no labelled links, so Save hands back the address, after the words
// when they say something else.
DialogFrame {
  id: d
  title: app.tr("Add link", "Adicionar link")
  cardWidth: t.sp(460)
  initialFocus: String(args.text || "").trim() !== "" ? linkField : textField

  readonly property bool ready: linkField.text.trim() !== ""

  // "acme.com/x" → "https://acme.com/x"; addresses with a scheme and email
  // addresses stay as typed (Slack links those by itself).
  function address(raw) {
    var u = String(raw || "").trim()
    if (!u) return ""
    if (/^[a-z][a-z0-9+.-]*:/i.test(u)) return u
    if (u.indexOf("@") > 0 && u.indexOf("/") < 0) return u
    return "https://" + u
  }

  function save() {
    if (!d.ready) return
    var typed = linkField.text.trim()
    var url = d.address(typed)
    var words = textField.text.trim()
    var out = words === "" || words === url || words === typed ? url : words + " " + url
    var done = d.args.onDone
    d.closed()
    if (done) done(out)
  }

  Column {
    width: parent.width
    spacing: d.t.sp(6)

    Text { text: d.app.tr("Text", "Texto"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
    SField {
      id: textField
      app: d.app
      width: parent.width
      text: d.args.text || ""
      placeholderText: d.app.tr("What the link says", "O que o link diz")
      onAccepted: d.ready ? d.save() : linkField.forceActiveFocus()
    }

    Item { width: 1; height: d.t.sp(8) }

    Text { text: d.app.tr("Link", "Link"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
    SField {
      id: linkField
      app: d.app
      width: parent.width
      icon: "󰌹"
      placeholderText: "https://"
      onAccepted: d.save()
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton { app: d.app; kind: "primary"; text: d.app.tr("Save", "Salvar"); enabled2: d.ready; onClicked: d.save() }
  }
}
