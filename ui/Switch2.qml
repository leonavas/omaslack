import QtQuick
import "../lib/Registry.js" as Reg

// An on/off switch with a label (preferences, dialogs).
Item {
  id: sw
  property var app: Reg.service
  readonly property var t: app.theme
  property bool checked: false
  property string text: ""
  property string hint: ""
  signal toggled(bool on)
  implicitHeight: Math.max(t.sp(26), col.implicitHeight)
  implicitWidth: 320

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: knob.left
    anchors.rightMargin: sw.t.sp(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text { text: sw.text; color: sw.t.fg; font.family: sw.t.font; font.pixelSize: sw.t.fsText; width: parent.width; wrapMode: Text.Wrap }
    Text { visible: sw.hint !== ""; text: sw.hint; color: sw.t.fgDim; font.family: sw.t.font; font.pixelSize: sw.t.fsSmall; width: parent.width; wrapMode: Text.Wrap }
  }
  Rectangle {
    id: knob
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: sw.t.sp(36); height: sw.t.sp(20); radius: height / 2
    color: sw.checked ? sw.t.accent : sw.t.lineStrong
    Behavior on color { ColorAnimation { duration: 120 } }
    Rectangle {
      width: parent.height - 4; height: width; radius: width / 2
      y: 2
      x: sw.checked ? parent.width - width - 2 : 2
      color: sw.checked ? sw.t.onColor(sw.t.accent) : sw.t.fg
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: { sw.checked = !sw.checked; sw.toggled(sw.checked) }
  }
}
