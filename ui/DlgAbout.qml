import QtQuick
import Quickshell.Io
import "../lib/Util.js" as U

// About this app: Slack's mark, the name and version (from the
// manifest), what it is, and the workspaces signed in with how they're
// connected.
DialogFrame {
  id: d
  title: ""
  cardWidth: t.sp(500)

  FileView {
    id: manifestFile
    path: d.app.pluginDir + "/manifest.json"
    printErrors: false
    blockLoading: true
  }
  readonly property string version: {
    if (d.app.manifest && d.app.manifest.version) return d.app.manifest.version
    try { return JSON.parse(manifestFile.text()).version || "" } catch (e) { return "" }
  }

  function state(w) {
    if (w.account && w.account.demo) return { color: d.t.blue, label: d.app.tr("Demo workspace", "Workspace de demonstração") }
    if (w.authError || d.app.expired[w.teamId]) return { color: d.t.red, label: d.app.tr("Session expired", "Sessão expirada") }
    if (w.live) return { color: d.t.green, label: d.app.tr("Connected · live", "Conectado · ao vivo") }
    if (w.booted) return { color: d.t.yellow, label: d.app.tr("Connected · reconnecting live updates", "Conectado · reconectando as atualizações ao vivo") }
    return { color: d.t.fgDim, label: d.app.tr("Connecting…", "Conectando…") }
  }

  Keys.onReturnPressed: d.closed()

  Column {
    width: parent.width
    spacing: d.t.sp(10)

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      source: Qt.resolvedUrl("../assets/slack.svg")
      width: d.t.sp(64)
      height: width
      sourceSize.width: width * 2
      sourceSize.height: height * 2
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Slack"
      color: d.t.fgBright
      font.family: d.t.font
      font.pixelSize: d.t.px(26)
      font.bold: true
    }
    Text {
      visible: d.version !== ""
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: d.app.tr("Version ", "Versão ") + d.version
      color: d.t.fgDim
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
    }
    // A newer one (core/Updater.qml): a click opens the update in a
    // terminal, as the button over your photo.
    Text {
      readonly property var up: d.app.updater
      readonly property bool busy: !!up && up.phase === "updating"
      visible: !!up && up.phase !== ""
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: !up ? "" : busy ? d.app.tr("Updating to ", "Atualizando para ") + up.latest + d.app.tr(" in the terminal…", " no terminal…")
            : up.phase === "updated" ? d.app.tr("Version ", "Versão ") + up.latest + d.app.tr(" is installed · reload to use it", " instalada · recarregue para usar")
            : d.app.tr("Version ", "Versão ") + up.latest + d.app.tr(" is available · update…", " disponível · atualizar…")
      color: busy ? d.t.fgDim : d.t.green
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
      font.underline: !busy && upMa.containsMouse
      MouseArea {
        id: upMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: parent.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: parent.up.update()
      }
    }
    Item { width: 1; height: d.t.sp(2) }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      lineHeight: 1.15
      text: d.app.tr("An unofficial Slack client for the Omarchy shell. It talks to Slack directly with your own session, which stays on this computer and is sent only to Slack. Not made or endorsed by Slack.",
                     "Um cliente não oficial do Slack para o shell do Omarchy. Ele fala direto com o Slack usando a sua sessão, que fica neste computador e só é enviada ao Slack. Não é feito nem endossado pelo Slack.")
      color: d.t.fgSoft
      font.family: d.t.font
      font.pixelSize: d.t.fsText - 1
    }
    Item { width: 1; height: d.t.sp(6) }
    Rectangle { width: parent.width; height: 1; color: d.t.line }
    Item { width: 1; height: d.t.sp(2) }

    Text {
      text: d.app.workspaces.length
            ? d.app.tr("Signed-in workspaces", "Workspaces conectados")
            : d.app.tr("No workspace signed in yet.", "Nenhum workspace conectado ainda.")
      color: d.app.workspaces.length ? d.t.fgDim : d.t.fgSoft
      font.family: d.t.font
      font.pixelSize: d.t.fsSmall
      font.bold: d.app.workspaces.length > 0
    }
    Repeater {
      model: d.app.workspaces
      delegate: Item {
        required property var modelData
        readonly property var w: modelData
        readonly property var st: d.state(w)
        width: parent.width
        height: d.t.sp(44)
        Clip {
          id: icon
          anchors.verticalCenter: parent.verticalCenter
          width: d.t.sp(32)
          height: width
          radius: Math.round(width * 0.24)
          color: Qt.hsla(U.hue(w.teamId), 0.45, 0.42, 1)
          Text {
            anchors.centerIn: parent
            visible: teamImg.status !== Image.Ready
            text: U.initials(w.team.name || "?")
            color: "white"
            font.family: d.t.font
            font.pixelSize: d.t.fsSmall
            font.bold: true
          }
          Image {
            id: teamImg
            anchors.fill: parent
            source: w.team.icon || ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 96
            sourceSize.height: 96
          }
        }
        Column {
          anchors.left: icon.right
          anchors.leftMargin: d.t.sp(12)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: (w.team.name || w.team.domain || w.teamId) + (w.team.domain ? "  ·  " + w.team.domain + ".slack.com" : "")
            color: d.t.fg
            font.family: d.t.font
            font.pixelSize: d.t.fsText - 1
          }
          Row {
            spacing: d.t.sp(6)
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: d.t.sp(8); height: width; radius: width / 2; color: st.color }
            Text { anchors.verticalCenter: parent.verticalCenter; text: st.label; color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall }
          }
        }
      }
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton {
      app: d.app
      icon: "󰌌"
      text: d.app.tr("Keyboard shortcuts", "Atalhos de teclado")
      onClicked: { var w = d.win; d.closed(); w.dialog("shortcuts", {}) }
    }
    SButton { app: d.app; kind: "primary"; text: d.app.tr("Close", "Fechar"); onClicked: d.closed() }
  }
}
