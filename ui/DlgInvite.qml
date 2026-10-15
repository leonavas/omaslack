import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U

// Slack's "Invite people to <workspace>": email addresses as chips (typos
// marked in red), the channels they start in and a note. Addresses Slack
// refuses stay in the field with the reason.
DialogFrame {
  id: d
  title: app.tr("Invite people to ", "Convidar pessoas para ") + (ws ? ws.team.name : "")
  cardWidth: t.sp(600)
  initialFocus: emailInput

  property var emails: []            // [{email, ok, why, refused}]
  property var chosen: []            // channel ids
  property int sel: 0
  property bool busy: false
  property string error: ""
  property var life: ({ on: true })
  Component.onDestruction: d.life.on = false
  // Your own address gives the placeholder its domain.
  Component.onCompleted: { var me = d.ws.user(d.ws.me.id); if (!me || !me.email) d.ws.profile(d.ws.me.id, function() {}) }

  readonly property string domain: {
    var me = d.ws ? d.ws.user(d.ws.me.id) : null
    var mail = me && me.email ? String(me.email) : ""
    return mail.indexOf("@") > 0 ? mail.split("@")[1] : "example.com"
  }
  // Typos block sending; addresses Slack refused may be tried again.
  readonly property int badCount: d.emails.filter(function(e) { return !e.ok && !e.refused }).length
  readonly property bool ready: !d.busy && (d.emails.length > 0 || emailInput.text.trim() !== "")

  // ------------------------------------------------------------ addresses
  function plausible(e) {
    var m = String(e).match(/^[^\s@<>(),;:"\[\]]+@([^\s@<>(),;:"\[\]]+)$/)
    if (!m) return false
    var host = m[1]
    return host.indexOf(".") > 0 && host.charAt(host.length - 1) !== "." && host.indexOf("..") < 0
  }

  // Splits typed text on commas, semicolons and spaces; complete pieces
  // become chips. `all` takes the last piece too.
  function absorb(all) {
    var raw = emailInput.text
    var pieces = raw.split(/[\s,;]+/)
    var rest = all ? "" : pieces.pop()
    var list = d.emails.slice()
    pieces.forEach(function(p) {
      var e = p.replace(/^[<("']+|[>)"'.]+$/g, "").replace(/^mailto:/i, "").trim()
      if (!e) return
      if (list.some(function(x) { return x.email.toLowerCase() === e.toLowerCase() })) return
      var ok = d.plausible(e)
      list.push({ email: e, ok: ok, why: ok ? "" : d.app.tr("isn't a valid email address", "não é um e-mail válido") })
    })
    if (list.length !== d.emails.length) d.emails = list
    if (rest !== raw) emailInput.text = rest
    d.error = ""
  }
  function dropEmail(i) { var l = d.emails.slice(); l.splice(i, 1); d.emails = l; d.error = ""; emailInput.forceActiveFocus() }

  // Slack's codes (ws hands them back with "_" turned to spaces) in words.
  function reason(text) {
    var code = String(text || "").trim().replace(/ /g, "_")
    var map = {
      already_in_team: d.app.tr("is already in this workspace", "já está neste workspace"),
      already_invited: d.app.tr("was already invited", "já foi convidado"),
      already_in_team_invited_user: d.app.tr("was already invited", "já foi convidado"),
      already_pending: d.app.tr("was already invited", "já foi convidado"),
      invalid_email: d.app.tr("isn't a valid email address", "não é um e-mail válido"),
      bad_email: d.app.tr("isn't a valid email address", "não é um e-mail válido"),
      sent_recently: d.app.tr("was invited recently", "foi convidado há pouco"),
      user_disabled: d.app.tr("belongs to a deactivated account", "é de uma conta desativada"),
      account_disabled: d.app.tr("belongs to a deactivated account", "é de uma conta desativada"),
      domain_not_allowed: d.app.tr("is from a domain this workspace doesn't allow", "é de um domínio que o workspace não permite"),
      email_domain_not_allowed: d.app.tr("is from a domain this workspace doesn't allow", "é de um domínio que o workspace não permite"),
      invite_limit_reached: d.app.tr("hit the invitation limit", "atingiu o limite de convites"),
      not_allowed: d.app.tr("can't be invited: you don't have permission", "não pode ser convidado: você não tem permissão"),
      no_perms: d.app.tr("can't be invited: you don't have permission", "não pode ser convidado: você não tem permissão"),
      team_invites_disabled: d.app.tr("can't be invited: invitations are turned off", "não pode ser convidado: os convites estão desligados"),
      invites_disabled: d.app.tr("can't be invited: invitations are turned off", "não pode ser convidado: os convites estão desligados"),
      admin_approval_required: d.app.tr("needs an admin's approval", "precisa da aprovação de um admin")
    }
    return map[code] || text
  }

  // ------------------------------------------------------------ channels
  readonly property string chanQuery: chanInput.text.trim().replace(/^#/, "")
  onChanQueryChanged: d.sel = 0

  readonly property var chanOptions: {
    var w = d.ws
    if (!w) return []
    w.convsRev
    var q = d.chanQuery, out = [], seen = {}
    function ok(c) { return !!c && (c.kind === "channel" || c.kind === "private") && !c.archived && !c.guest && c.member !== false && d.chosen.indexOf(c.id) < 0 }
    if (!q) {
      var trail = [w.current].concat(w.backStack.map(function(e) { return e.view === "conv" ? e.conv : "" }).reverse())
      trail.forEach(function(id) { var c = w.convs[id]; if (id && !seen[id] && ok(c)) { seen[id] = true; out.push(c) } })
    }
    var rest = []
    for (var id in w.convs) {
      var c = w.convs[id]
      if (seen[id] || !ok(c)) continue
      var r = q ? U.rank(c.name || "", q) : 5
      if (r < 0) continue
      var k = w.counts[id]
      rest.push({ c: c, r: r, at: k && k.latest ? U.tsNum(k.latest) : (c.updated || 0) / 1000 })
    }
    rest.sort(function(a, b) { return a.r - b.r || b.at - a.at || (a.c.name < b.c.name ? -1 : 1) })
    out = out.concat(rest.map(function(x) { return x.c }))
    return out.slice(0, 6).map(function(c) { return { key: c.id, id: c.id, name: c.name || "", private: c.kind === "private", members: c.numMembers || 0 } })
  }

  function addChannel(i) {
    var o = d.chanOptions[i]
    if (!o) return
    d.chosen = d.chosen.concat([o.id])
    chanInput.text = ""
  }
  function dropChannel(id) { d.chosen = d.chosen.filter(function(x) { return x !== id }); chanInput.forceActiveFocus() }
  function moveChan(delta) { var n = Math.min(4, d.chanOptions.length); if (n) d.sel = Math.max(0, Math.min(n - 1, d.sel + delta)) }

  // ------------------------------------------------------------ send
  function send() {
    if (d.busy) return
    d.absorb(true)
    if (!d.emails.length) { d.error = d.app.tr("Type at least one email address.", "Digite ao menos um e-mail."); emailInput.forceActiveFocus(); return }
    if (d.badCount) { d.error = d.app.tr("Fix or remove the addresses marked in red.", "Corrija ou remova os endereços marcados em vermelho."); emailInput.forceActiveFocus(); return }
    var list = d.emails.map(function(e) { return e.email })
    var team = d.ws.team.name
    var win = d.win, app = d.app, life = d.life
    d.busy = true
    d.error = ""
    d.ws.inviteToTeam(list, d.chosen.slice(), note.text.trim(), function(failed, err) {
      if (!life.on) return
      d.busy = false
      if (err) { d.error = err; return }
      failed = failed || {}
      var sent = list.filter(function(e) { return !failed[e] })
      if (sent.length) win.toast("󰄬  " + (sent.length === 1 ? app.tr("Invitation sent to ", "Convite enviado para ") + team
                                                              : sent.length + app.tr(" invitations sent to ", " convites enviados para ") + team))
      var left = list.filter(function(e) { return !!failed[e] })
      if (!left.length) { d.closed(); return }
      d.emails = left.map(function(e) { return { email: e, ok: false, refused: true, why: d.reason(failed[e]) } })
      var whys = U.uniq(d.emails.map(function(e) { return e.why }))
      d.error = !sent.length && whys.length === 1 && left.length > 1
        ? app.tr("No invitation was sent: ", "Nenhum convite foi enviado: ") + whys[0]
        : app.tr("Some addresses weren't invited (in red).", "Alguns endereços não foram convidados (em vermelho).")
      emailInput.forceActiveFocus()
    })
  }

  Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter", "Ctrl+S"]; onActivated: d.send() }

  // ------------------------------------------------------------ layout
  Column {
    id: col
    width: parent.width
    spacing: d.t.sp(8)

    Text { text: d.app.tr("To:", "Para:"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }

    Rectangle {
      id: emailBox
      width: parent.width
      height: Math.max(d.t.sp(64), emailFlow.implicitHeight + d.t.sp(14))
      radius: Math.max(4, d.t.radiusSmall)
      color: d.t.alpha(d.t.bg, 0.6)
      border.width: emailInput.activeFocus ? 2 : 1
      border.color: emailInput.activeFocus ? d.t.accent : d.t.lineStrong

      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: emailInput.forceActiveFocus() }

      Flow {
        id: emailFlow
        x: d.t.sp(8)
        y: d.t.sp(7)
        width: parent.width - d.t.sp(16)
        spacing: d.t.sp(4)

        Repeater {
          model: d.emails
          delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index
            height: d.t.sp(28)
            width: Math.min(emailFlow.width, chipRow.implicitWidth + d.t.sp(14))
            radius: Math.max(4, d.t.radiusSmall)
            color: modelData.ok ? (chipMa.containsMouse ? d.t.alpha(d.t.accent, 0.28) : d.t.alpha(d.t.accent, 0.16))
                                : (chipMa.containsMouse ? d.t.alpha(d.t.red, 0.3) : d.t.alpha(d.t.red, 0.18))
            border.width: modelData.ok ? 0 : 1
            border.color: d.t.alpha(d.t.red, 0.6)
            Row {
              id: chipRow
              x: d.t.sp(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: d.t.sp(6)
              Glyph { app: d.app; icon: chip.modelData.ok ? "󰇰" : "󰗖"; size: d.t.fsSmall + 1; color: chip.modelData.ok ? d.t.fgDim : d.t.red; anchors.verticalCenter: parent.verticalCenter }
              Text {
                text: chip.modelData.email
                textFormat: Text.PlainText
                color: chip.modelData.ok ? d.t.fgBright : d.t.red
                font.family: d.t.font
                font.pixelSize: d.t.fsText - 1
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, emailFlow.width - d.t.sp(60))
              }
              Glyph { app: d.app; icon: "󰅖"; size: d.t.fsSmall; color: chipMa.containsMouse ? d.t.fgBright : d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.dropEmail(chip.index) }
          }
        }

        TextField {
          id: emailInput
          width: d.emails.length ? Math.max(d.t.sp(180), Math.min(emailFlow.width, contentWidth + d.t.sp(24))) : emailFlow.width
          height: d.t.sp(28)
          padding: 0
          leftPadding: d.t.sp(4)
          verticalAlignment: TextInput.AlignVCenter
          background: null
          color: d.t.fg
          placeholderText: d.emails.length ? "" : d.app.tr("name@", "nome@") + d.domain + ", " + d.app.tr("other@", "outro@") + d.domain
          placeholderTextColor: d.t.fgDim
          selectionColor: d.t.alpha(d.t.accent, 0.35)
          selectedTextColor: d.t.fgBright
          selectByMouse: true
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          onTextEdited: if (/[\s,;]/.test(text)) d.absorb(false)
          onActiveFocusChanged: if (!activeFocus && text.trim() !== "") d.absorb(true)
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              event.accepted = true
              if (emailInput.text.trim() !== "") d.absorb(true)
              else if (d.emails.length) chanInput.forceActiveFocus()
            } else if (event.key === Qt.Key_Backspace && emailInput.text === "" && d.emails.length) {
              d.dropEmail(d.emails.length - 1); event.accepted = true
            }
          }
        }
      }
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: d.app.tr("Separate addresses with commas or spaces. They join as full members.", "Separe os endereços com vírgulas ou espaços. Entram como membros completos.")
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }

    // The addresses Slack refused, and why.
    Column {
      width: parent.width
      spacing: d.t.sp(2)
      visible: d.emails.some(function(e) { return !e.ok })
      Repeater {
        model: d.emails.filter(function(e) { return !e.ok })
        delegate: Text {
          required property var modelData
          width: parent.width
          wrapMode: Text.Wrap
          text: "󰗖  " + modelData.email + " " + modelData.why
          textFormat: Text.PlainText
          color: d.t.red
          font.family: d.t.font
          font.pixelSize: d.t.fsSmall
        }
      }
    }

    Item { width: 1; height: d.t.sp(4) }

    Row {
      spacing: d.t.sp(6)
      Text { text: d.app.tr("Add to channels", "Adicionar aos canais"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
      Text { text: d.app.tr("(optional)", "(opcional)"); color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsText }
    }

    Rectangle {
      id: chanBox
      width: parent.width
      height: Math.max(d.t.sp(40), chanFlow.implicitHeight + d.t.sp(12))
      radius: Math.max(4, d.t.radiusSmall)
      color: d.t.alpha(d.t.bg, 0.6)
      border.width: chanInput.activeFocus ? 2 : 1
      border.color: chanInput.activeFocus ? d.t.accent : d.t.lineStrong

      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: chanInput.forceActiveFocus() }

      Flow {
        id: chanFlow
        x: d.t.sp(8)
        y: d.t.sp(6)
        width: parent.width - d.t.sp(16)
        spacing: d.t.sp(4)

        Repeater {
          model: d.chosen
          delegate: Rectangle {
            id: cchip
            required property var modelData
            readonly property var c: d.ws ? d.ws.conv(modelData) : null
            height: d.t.sp(28)
            width: cchipRow.implicitWidth + d.t.sp(14)
            radius: Math.max(4, d.t.radiusSmall)
            color: cchipMa.containsMouse ? d.t.alpha(d.t.accent, 0.28) : d.t.alpha(d.t.accent, 0.16)
            Row {
              id: cchipRow
              x: d.t.sp(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: d.t.sp(5)
              Glyph { app: d.app; icon: cchip.c && cchip.c.kind === "private" ? "󰌾" : "#"; size: d.t.fsSmall + 1; color: d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
              Text { text: cchip.c ? cchip.c.name : cchip.modelData; textFormat: Text.PlainText; color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText - 1; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
              Glyph { app: d.app; icon: "󰅖"; size: d.t.fsSmall; color: cchipMa.containsMouse ? d.t.fgBright : d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: cchipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.dropChannel(cchip.modelData) }
          }
        }

        TextField {
          id: chanInput
          width: d.chosen.length ? Math.max(d.t.sp(160), Math.min(chanFlow.width, contentWidth + d.t.sp(24))) : chanFlow.width
          height: d.t.sp(28)
          padding: 0
          leftPadding: d.t.sp(4)
          verticalAlignment: TextInput.AlignVCenter
          background: null
          color: d.t.fg
          placeholderText: d.chosen.length ? "" : d.app.tr("Search channels", "Buscar canais")
          placeholderTextColor: d.t.fgDim
          selectionColor: d.t.alpha(d.t.accent, 0.35)
          selectedTextColor: d.t.fgBright
          selectByMouse: true
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) { d.moveChan(1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { d.moveChan(-1); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              event.accepted = true
              if (chanInput.text.trim() !== "" && d.chanOptions.length) d.addChannel(d.sel)
              else note.area.forceActiveFocus()
            } else if (event.key === Qt.Key_Backspace && chanInput.text === "" && d.chosen.length) {
              d.dropChannel(d.chosen[d.chosen.length - 1]); event.accepted = true
            }
          }
        }
      }
    }

    // With nothing typed: a few channels to add with a click.
    Flow {
      visible: d.chanQuery === "" && d.chanOptions.length > 0
      width: parent.width
      spacing: d.t.sp(6)
      Text {
        height: d.t.sp(26)
        verticalAlignment: Text.AlignVCenter
        text: d.app.tr("Suggested:", "Sugeridos:")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
      Repeater {
        model: d.chanOptions.slice(0, 4)
        delegate: Rectangle {
          id: pill
          required property var modelData
          required property int index
          height: d.t.sp(26)
          width: pillRow.implicitWidth + d.t.sp(16)
          radius: height / 2
          color: pillMa.containsMouse ? d.t.hoverStrong : "transparent"
          border.width: 1
          border.color: d.t.lineStrong
          Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: d.t.sp(4)
            Glyph { app: d.app; icon: "󰐕"; size: d.t.fsSmall; color: d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
            Glyph { app: d.app; icon: pill.modelData.private ? "󰌾" : "#"; size: d.t.fsSmall; color: d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
            Text { text: pill.modelData.name; textFormat: Text.PlainText; color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsSmall; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { id: pillMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.addChannel(pill.index) }
        }
      }
    }

    // Typing: the channels of yours that match.
    Column {
      id: chanCol
      visible: d.chanQuery !== ""
      width: parent.width
      Repeater {
        model: d.chanQuery !== "" ? d.chanOptions.slice(0, 4) : []
        delegate: Rectangle {
          id: copt
          required property var modelData
          required property int index
          readonly property bool hot: index === d.sel
          width: chanCol.width
          height: d.t.sp(32)
          radius: Math.max(4, d.t.radiusSmall)
          color: hot ? d.t.accent : (coptMa.containsMouse ? d.t.hover : "transparent")
          Row {
            x: d.t.sp(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: d.t.sp(10)
            Glyph { app: d.app; width: d.t.sp(16); icon: copt.modelData.private ? "󰌾" : "#"; color: copt.hot ? d.t.onColor(d.t.accent) : d.t.fgDim; anchors.verticalCenter: parent.verticalCenter }
            Text { text: copt.modelData.name; textFormat: Text.PlainText; color: copt.hot ? d.t.onColor(d.t.accent) : d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Text {
              visible: copt.modelData.members > 0
              text: copt.modelData.members + d.app.tr(" members", " membros")
              color: copt.hot ? d.t.alpha(d.t.onColor(d.t.accent), 0.75) : d.t.fgDim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          MouseArea { id: coptMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { d.addChannel(copt.index); chanInput.forceActiveFocus() } }
        }
      }
      Text {
        visible: d.chanOptions.length === 0
        leftPadding: d.t.sp(10)
        height: d.t.sp(30)
        verticalAlignment: Text.AlignVCenter
        text: d.app.tr("No channel of yours matches.", "Nenhum canal seu corresponde.")
        color: d.t.red
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }

    Item { width: 1; height: d.t.sp(4) }

    Row {
      spacing: d.t.sp(6)
      Text { text: d.app.tr("Message", "Mensagem"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
      Text { text: d.app.tr("(optional)", "(opcional)"); color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsText }
    }
    SArea {
      id: note
      app: d.app
      width: parent.width
      implicitHeight: Math.max(d.t.sp(44), Math.min(d.t.sp(84), d.maxHeight - d.t.sp(470)))
      placeholderText: d.app.tr("Add a personalized message to the invitation", "Adicione uma mensagem personalizada ao convite")
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

  footer: Item {
    width: parent.width
    height: sendBtn.height
    Text {
      anchors.left: parent.left
      anchors.right: buttons.left
      anchors.rightMargin: d.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: d.app.tr("Ctrl+Enter sends · Esc closes", "Ctrl+Enter envia · Esc fecha")
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }
    Row {
      id: buttons
      anchors.right: parent.right
      spacing: d.t.sp(10)
      SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
      SButton {
        id: sendBtn
        app: d.app
        kind: "primary"
        text: d.busy ? d.app.tr("Sending…", "Enviando…") : d.app.tr("Send", "Enviar")
        enabled2: d.ready
        onClicked: d.send()
      }
    }
  }
}
