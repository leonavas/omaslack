import QtQuick
import QtQuick.Controls

// Slack's app install request, from its message's "Review and Approve /
// Restrict for Workspace" buttons, as the official client's
// AppAdminResolutionConfirmationModal: the app, the scopes it asks for, then
// Cancel / Approve (or Deny). The request (its app and scopes) comes from
// admin.apps.requests.list; the answer goes to admin.apps.approve or
// admin.apps.restrict (Workspace.resolveAppRequest).
// args: req { appId, requestId, teamId, appName }, approve.
DialogFrame {
  id: d
  readonly property var req: args.req || ({})
  readonly property bool approve: !!args.approve
  property var request: null
  property bool loading: true
  property bool busy: false
  property string error: ""
  readonly property var app2: request && request.app ? request.app : ({})
  readonly property string appName: app2.name || req.appName || req.appId || ""
  readonly property var scopes: request && request.scopes ? request.scopes : []
  readonly property var bot: scopes.filter(function(s) { return s.token_type === "bot" })
  readonly property var user: scopes.filter(function(s) { return s.token_type === "user" })

  title: approve ? app.tr("Approve this app for installation?", "Aprovar este app para instalação?")
                 : app.tr("Restrict this app from installation?", "Restringir a instalação deste app?")
  cardWidth: t.sp(560)
  initialFocus: okBtn

  Component.onCompleted: {
    if (!d.ws || !d.req.requestId) { d.loading = false; return }
    d.ws.fetchAppRequest(d.req, function(found, err) {
      d.loading = false
      d.request = found
      if (!found) d.error = err ? d.ws.errorText(err) : d.app.tr("This request has already been handled.", "Esta solicitação já foi atendida.")
    })
  }

  function confirm() {
    if (d.busy || d.loading || !d.request) return
    d.busy = true
    d.error = ""
    var name = d.appName
    d.ws.resolveAppRequest(d.req, d.approve, d.scopes, function(err) {
      d.busy = false
      if (err) { d.error = d.ws.errorText(err); return }
      d.ws.say(d.approve ? d.app.tr(name + " is approved for installation", name + " é aprovado para instalação")
                         : d.app.tr(name + " is now restricted from being installed", "Agora há uma restrição para instalar " + name))
      d.closed()
    })
  }

  Column {
    width: parent.width
    spacing: d.t.sp(14)

    Rectangle {
      visible: d.error !== ""
      width: parent.width
      height: errText.implicitHeight + d.t.sp(16)
      radius: Math.max(6, d.t.radiusSmall)
      color: d.t.alpha(d.t.red, 0.10)
      border.width: 1
      border.color: d.t.alpha(d.t.red, 0.4)
      Text { id: errText; anchors.centerIn: parent; width: parent.width - d.t.sp(20); wrapMode: Text.Wrap; text: d.error; textFormat: Text.PlainText; color: d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsSmall + 1 }
    }

    // The app: icon and name.
    Row {
      spacing: d.t.sp(12)
      Avatar {
        app: d.app
        ws: d.ws
        size: d.t.sp(40)
        url: (d.app2.icons && (d.app2.icons.image_48 || d.app2.icons.image_72 || d.app2.icons.image_36)) || ""
        name: d.appName
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: d.appName
        textFormat: Text.PlainText
        color: d.t.fgBright
        font.family: d.t.font
        font.pixelSize: d.t.fsText + 1
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: d.app.tr("This app requires permission to access the following resources:", "Este app exige permissão de acesso aos seguintes recursos:")
      textFormat: Text.PlainText
      color: d.t.fg
      font.family: d.t.font
      font.pixelSize: d.t.fsText
    }

    // Slack's tabs, here only Scopes.
    Column {
      width: parent.width
      spacing: 0
      Item {
        width: parent.width
        height: tabLabel.implicitHeight + d.t.sp(10)
        Text {
          id: tabLabel
          text: d.app.tr("Scopes", "Escopos")
          textFormat: Text.PlainText
          color: d.t.fgBright
          font.family: d.t.font
          font.pixelSize: d.t.fsText
          font.bold: true
        }
        Rectangle { anchors.bottom: parent.bottom; width: tabLabel.implicitWidth; height: Math.max(2, d.t.sp(2)); color: d.t.accent }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: d.t.line; z: -1 }
      }

      Flickable {
        id: list
        width: parent.width
        height: Math.min(listCol.implicitHeight + d.t.sp(12), Math.max(d.t.sp(120), d.maxHeight - d.t.sp(380)))
        contentHeight: listCol.implicitHeight + d.t.sp(12)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThinScroll { app: d.app }

        Column {
          id: listCol
          y: d.t.sp(12)
          width: list.width - d.t.sp(12)
          spacing: d.t.sp(12)

          Text {
            visible: d.loading || d.scopes.length === 0
            text: d.loading ? d.app.tr("Loading scopes", "Carregando escopos") : d.app.tr("No scopes", "Nenhum escopo")
            textFormat: Text.PlainText
            color: d.t.fgDim
            font.family: d.t.font
            font.pixelSize: d.t.fsSmall + 1
          }

          Repeater {
            model: [{ en: "Bot scopes", pt: "Escopos de bot", items: d.bot }, { en: "User scopes", pt: "Escopos de usuário", items: d.user }]
            delegate: Column {
              id: group
              required property var modelData
              visible: modelData.items.length > 0
              width: listCol.width
              spacing: d.t.sp(8)
              Text {
                text: d.app.tr(group.modelData.en, group.modelData.pt) + " (" + group.modelData.items.length + ")"
                textFormat: Text.PlainText
                color: d.t.fgDim
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
                font.bold: true
              }
              Repeater {
                model: group.modelData.items
                delegate: Column {
                  required property var modelData
                  width: group.width
                  spacing: d.t.sp(2)
                  Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: modelData.description || modelData.name || ""
                    textFormat: Text.PlainText
                    color: d.t.fg
                    font.family: d.t.font
                    font.pixelSize: d.t.fsText - 1
                  }
                  Text {
                    visible: !!modelData.description
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.name || ""
                    textFormat: Text.PlainText
                    color: d.t.fgDim
                    font.family: "monospace"
                    font.pixelSize: d.t.fsSmall
                  }
                }
              }
            }
          }
        }
      }
    }

    Text {
      visible: !d.approve
      width: parent.width
      wrapMode: Text.Wrap
      text: d.app.tr("Members will no longer be able to add or edit configurations.", "Os membros não poderão mais adicionar nem editar as configurações.")
      textFormat: Text.PlainText
      color: d.t.fg
      font.family: d.t.font
      font.pixelSize: d.t.fsText
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    SButton { id: cancelBtn; app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton {
      id: okBtn
      app: d.app
      kind: d.approve ? "green" : "danger"
      enabled2: !d.busy && !d.loading && !!d.request
      text: d.approve ? d.app.tr("Approve", "Aprovar") : d.app.tr("Deny", "Recusar")
      onClicked: d.confirm()
    }
  }
  Keys.onReturnPressed: d.confirm()
  Keys.onEnterPressed: d.confirm()
  Keys.onTabPressed: (okBtn.activeFocus ? cancelBtn : okBtn).forceActiveFocus()
  Keys.onBacktabPressed: (okBtn.activeFocus ? cancelBtn : okBtn).forceActiveFocus()
  Keys.onLeftPressed: cancelBtn.forceActiveFocus()
  Keys.onRightPressed: okBtn.forceActiveFocus()
}
