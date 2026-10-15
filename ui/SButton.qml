import QtQuick
import "../lib/Registry.js" as Reg

// Slack's buttons: primary (filled), secondary (outlined), danger, ghost.
Rectangle {
  id: b
  property var app: Reg.service
  readonly property var t: app.theme
  property string text: ""
  property string icon: ""
  property string kind: "secondary"
  property bool enabled2: true
  property bool small: false
  signal clicked()

  readonly property color fill: kind === "primary" ? t.accent : (kind === "danger" ? t.red : "transparent")
  readonly property color ink: kind === "primary" || kind === "danger" ? t.onColor(fill) : t.fg

  implicitHeight: t.sp(small ? 28 : 34)
  implicitWidth: Math.max(t.sp(small ? 56 : 80), row.implicitWidth + t.sp(small ? 20 : 28))
  radius: Math.max(4, t.radiusSmall)
  color: ma.pressed ? Qt.darker(fill.a > 0 ? fill : t.hoverStrong, 1.15) : (ma.containsMouse ? (fill.a > 0 ? Qt.lighter(fill, 1.08) : t.hover) : fill)
  border.width: kind === "secondary" ? 1 : 0
  border.color: t.lineStrong
  opacity: enabled2 ? 1 : 0.45

  Row {
    id: row
    anchors.centerIn: parent
    spacing: b.t.sp(6)
    Glyph { app: b.app; icon: b.icon; visible: b.icon !== ""; color: b.ink; size: b.t.fsSmall + 2; anchors.verticalCenter: parent.verticalCenter }
    Text {
      text: b.text
      color: b.ink
      font.family: b.t.font
      font.pixelSize: b.small ? b.t.fsSmall : b.t.fsText - 1
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    enabled: b.enabled2
    cursorShape: Qt.PointingHandCursor
    onClicked: b.clicked()
  }
}
