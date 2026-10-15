import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// Slack's sign-in page, the plugin's way: Slack's own sign-in in a window
// (the session it creates is kept here). A token and cookie pasted by hand
// are a fallback, folded behind a small link.
Rectangle {
  id: lv
  property var app: Reg.service
  property bool adding: false        // "Add a workspace" (a dialog), not the first sign-in
  signal finished()
  readonly property var t: app.theme
  color: t.pane

  property bool showToken: false
  property string error: ""
  property bool busy: false

  onShowTokenChanged: if (showToken) Qt.callLater(function() { tokenField.forceActiveFocus() })

  Connections {
    target: lv.app
    function onAccountsChanged() { if (lv.adding && !lv.app.loginRunning) lv.finished() }
  }

  Flickable {
    anchors.fill: parent
    contentHeight: Math.max(height, col.implicitHeight + lv.t.sp(80))
    clip: true

    Column {
      id: col
      width: Math.min(lv.t.sp(400), lv.width - lv.t.sp(40))
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(lv.t.sp(40), (parent.height - implicitHeight) / 2 - lv.t.sp(20))
      spacing: lv.t.sp(14)

      Image {
        anchors.horizontalCenter: parent.horizontalCenter
        source: Qt.resolvedUrl("../assets/slack.svg")
        width: lv.t.sp(52)
        height: width
        sourceSize.width: width * 2
        sourceSize.height: height * 2
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: lv.adding ? lv.app.tr("Add a workspace", "Adicionar um workspace") : lv.app.tr("Sign in to Slack", "Entre no Slack")
        color: lv.t.fgBright
        font.family: lv.t.font
        font.pixelSize: lv.t.px(30)
        font.bold: true
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: lv.app.tr("Slack's sign-in page opens in a window. Your session stays on this computer.",
                        "A página de login do Slack abre numa janela. A sua sessão fica neste computador.")
        color: lv.t.fgSoft
        font.family: lv.t.font
        font.pixelSize: lv.t.fsText
      }

      // Expired sessions.
      Repeater {
        model: Object.keys(lv.app.expired)
        delegate: Rectangle {
          required property var modelData
          width: col.width
          height: exp.implicitHeight + lv.t.sp(16)
          radius: Math.max(6, lv.t.radiusSmall)
          color: lv.t.alpha(lv.t.yellow, 0.12)
          border.width: 1
          border.color: lv.t.alpha(lv.t.yellow, 0.4)
          Text {
            id: exp
            anchors.centerIn: parent
            width: parent.width - lv.t.sp(20)
            wrapMode: Text.Wrap
            text: lv.app.tr("The session for ", "A sessão de ") + lv.teamName(parent.modelData) + lv.app.tr(" expired. Sign in again.", " expirou. Entre de novo.")
            textFormat: Text.PlainText
            color: lv.t.fg
            font.family: lv.t.font
            font.pixelSize: lv.t.fsSmall
          }
        }
      }

      SField {
        id: wsField
        app: lv.app
        width: parent.width
        icon: "󰖟"
        placeholderText: lv.app.tr("your-workspace.slack.com (optional)", "seu-workspace.slack.com (opcional)")
        onAccepted: lv.signIn()
      }

      SButton {
        app: lv.app
        width: parent.width
        kind: "primary"
        text: lv.app.loginRunning ? lv.app.tr("Waiting for Slack…", "Esperando o Slack…") : lv.app.tr("Sign in with Slack", "Entrar com o Slack")
        enabled2: !lv.app.loginRunning && !lv.busy
        onClicked: lv.signIn()
      }

      Text {
        visible: lv.app.loginStatus !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: lv.app.loginStatus
        textFormat: Text.PlainText
        color: lv.t.fgDim
        font.family: lv.t.font
        font.pixelSize: lv.t.fsSmall
      }
      SButton {
        visible: lv.app.loginRunning
        anchors.horizontalCenter: parent.horizontalCenter
        app: lv.app
        small: true
        text: lv.app.tr("Cancel", "Cancelar")
        onClicked: lv.app.cancelLogin()
      }

      Text {
        visible: lv.app.loginError !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: lv.app.loginError
        textFormat: Text.PlainText
        color: lv.t.red
        font.family: lv.t.font
        font.pixelSize: lv.t.fsSmall
      }

      // The fallback: a token pasted by hand, out of the way until asked for.
      Item { width: 1; height: lv.t.sp(4) }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: lv.showToken ? lv.app.tr("Hide the token form", "Esconder o formulário de token") : lv.app.tr("Sign in with a token", "Entrar com um token")
        color: tokenLink.containsMouse ? lv.t.link : lv.t.fgDim
        font.family: lv.t.font
        font.pixelSize: lv.t.fsSmall
        font.underline: tokenLink.containsMouse
        MouseArea {
          id: tokenLink
          anchors.fill: parent
          anchors.margins: -lv.t.sp(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: lv.showToken = !lv.showToken
        }
      }

      Column {
        visible: lv.showToken
        width: parent.width
        spacing: lv.t.sp(8)
        SField {
          id: tokenField
          app: lv.app
          width: parent.width
          placeholderText: "xoxc-… / xoxp-…"
          echoMode: TextInput.Password
          onAccepted: cookieField.forceActiveFocus()
        }
        SField {
          id: cookieField
          app: lv.app
          width: parent.width
          placeholderText: lv.app.tr("d cookie: xoxd-… (only for xoxc tokens)", "cookie d: xoxd-… (só para tokens xoxc)")
          echoMode: TextInput.Password
          onAccepted: lv.withToken()
        }
        SButton {
          app: lv.app
          width: parent.width
          text: lv.app.tr("Sign in with the token", "Entrar com o token")
          enabled2: !lv.busy && tokenField.text.trim() !== ""
          onClicked: lv.withToken()
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: lv.app.tr("A browser session's token (xoxc-) is in Slack's web app (localStorage localConfig_v2) and needs its d cookie; a user token (xoxp-) from your own Slack app needs nothing else.",
                          "O token de uma sessão do navegador (xoxc-) fica no app web do Slack (localStorage localConfig_v2) e precisa do cookie d; um token de usuário (xoxp-) do seu próprio app do Slack não precisa de mais nada.")
          color: lv.t.fgDim
          font.family: lv.t.font
          font.pixelSize: lv.t.fsTiny + 1
        }
        Text {
          visible: lv.error !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: lv.error
          textFormat: Text.PlainText
          color: lv.t.red
          font.family: lv.t.font
          font.pixelSize: lv.t.fsSmall
        }
      }
    }
  }

  function teamName(id) {
    var a = lv.app.accounts.filter(function(x) { return x.teamId === id })[0]
    return a ? (a.name || a.domain || id) : id
  }

  function signIn() {
    lv.error = ""
    var ws = wsField.text.trim().replace(/^https?:\/\//, "").replace(/\.slack\.com.*$/, "").replace(/\/.*$/, "")
    lv.app.startLogin(ws)
  }

  function withToken() {
    lv.busy = true
    lv.error = ""
    lv.app.checkSession(tokenField.text, cookieField.text, function(err) {
      lv.busy = false
      lv.error = err
      if (!err) { tokenField.text = ""; cookieField.text = ""; lv.finished() }
    })
  }
}
