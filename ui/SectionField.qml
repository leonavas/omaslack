import QtQuick
import qs.Ui
import "../lib/Registry.js" as Reg

// A section's name and its emoji in one field, as in Slack's "Create a
// section" and "Rename this section": the emoji at the start opens the
// picker (right click takes it off), the round ✕ at the end clears the name.
FocusScope {
  id: sf
  property var app: Reg.service
  property var win
  property var ws
  readonly property var t: app.theme
  property string emoji: ""          // Slack name, no colons
  property alias text: field.text
  property alias placeholderText: field.placeholderText
  readonly property int maxLength: 80
  signal accepted()
  signal edited()
  implicitHeight: field.implicitHeight

  function pickEmoji() {
    sf.win.emojiPicker(sf, function(name) { sf.emoji = name || ""; sf.edited(); field.forceActiveFocus() }, {})
  }
  function removeEmoji() { sf.emoji = ""; sf.edited(); field.forceActiveFocus() }

  SField {
    id: field
    app: sf.app
    anchors.fill: parent
    focus: true
    leftPadding: sf.t.sp(46)
    rightPadding: sf.t.sp(field.text !== "" ? (field.activeFocus ? 64 : 40) : 12)
    topPadding: sf.t.sp(10)
    bottomPadding: sf.t.sp(10)
    maximumLength: sf.maxLength
    onTextEdited: sf.edited()
    onAccepted: sf.accepted()
  }

  Rectangle {
    id: emojiBtn
    x: sf.t.sp(6)
    anchors.verticalCenter: parent.verticalCenter
    width: sf.t.sp(32)
    height: sf.t.sp(28)
    radius: Math.max(4, sf.t.radiusSmall)
    color: ema.containsMouse ? sf.t.hoverStrong : "transparent"
    // Made anew for each emoji (EmojiIcon's name isn't meant to go from empty to set).
    Loader {
      anchors.centerIn: parent
      active: sf.emoji !== ""
      sourceComponent: EmojiIcon { app: sf.app; ws: sf.ws; name: sf.emoji; size: sf.t.sp(20) }
    }
    Glyph {
      anchors.centerIn: parent
      app: sf.app
      visible: sf.emoji === ""
      icon: "󰞅"
      size: sf.t.fsTitle + 3
      color: ema.containsMouse ? sf.t.fgBright : sf.t.fgDim
    }
    MouseArea {
      id: ema
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: mouse => { if (mouse.button === Qt.RightButton) sf.removeEmoji(); else sf.pickEmoji() }
    }
    PanelToolTip {
      visible: ema.containsMouse
      text: sf.emoji ? sf.app.tr("Change emoji (right click removes it)", "Trocar emoji (clique direito remove)") : sf.app.tr("Add an emoji", "Adicionar um emoji")
    }
  }

  Text {
    anchors.right: clearBtn.left
    anchors.rightMargin: sf.t.sp(6)
    anchors.verticalCenter: parent.verticalCenter
    visible: field.activeFocus && field.text !== ""
    text: String(sf.maxLength - field.length)
    color: field.length >= sf.maxLength ? sf.t.red : sf.t.fgDim
    font.family: sf.t.font
    font.pixelSize: sf.t.fsSmall
  }
  IconButton {
    id: clearBtn
    app: sf.app
    visible: field.text !== ""
    anchors.right: parent.right
    anchors.rightMargin: sf.t.sp(8)
    anchors.verticalCenter: parent.verticalCenter
    size: sf.t.sp(24)
    icon: "󰅙"
    iconSize: sf.t.fsTitle
    tip: sf.app.tr("Clear", "Limpar")
    onClicked: { field.text = ""; sf.edited(); field.forceActiveFocus() }
  }
}
