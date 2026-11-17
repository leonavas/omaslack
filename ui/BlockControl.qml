import QtQuick
import "../lib/Registry.js" as Reg

// One of an app's Block Kit elements, drawn as Slack draws it (from
// Mrkdwn.control): a button in its style, the ⋯ overflow, a select or
// date / time picker as a box with its value or hint and a chevron, a date
// and time pair, checkboxes and radio buttons with their choices, a text
// field. `pressed(ctl, option)`: clicked (option: the choice picked from an
// overflow or a select, or the checkbox / radio clicked).
Item {
  id: bc
  property var app: Reg.service
  property var win
  property var ctl: null
  readonly property var t: app.theme
  readonly property string kind: ctl ? ctl.kind : ""
  // A field or select in an input block takes the width it's given.
  property real fill: 0
  signal pressed(var ctl, var option)

  implicitWidth: loader.item ? loader.item.implicitWidth : 0
  implicitHeight: loader.item ? loader.item.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight

  Loader {
    id: loader
    sourceComponent: ({ button: buttonC, overflow: overflowC, select: selectC, datetime: datetimeC, checks: choicesC, radios: choicesC, field: fieldC })[bc.kind] || null
  }

  function label(html, color) {
    return "<span style=\"color:" + color + ";\">" + html + "</span>"
  }

  function menu(item) {
    var opts = bc.ctl.options || []
    if (!opts.length || !bc.win) { bc.pressed(bc.ctl, null); return }
    bc.win.menuAt(item, opts.map(function(o) {
      return { label: String(o.html).replace(/<img [^>]*alt="([^"]*)"[^>]*>/g, "$1").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">"),
               icon: o.url ? "󰏌" : "", action: function() { bc.pressed(bc.ctl, o) } }
    }), 0, item.height + bc.t.sp(4))
  }

  Component {
    id: buttonC
    Rectangle {
      readonly property string st: bc.ctl.style
      readonly property color fill: st === "primary" ? bc.t.green : st === "danger" ? bc.t.red : "transparent"
      implicitHeight: bc.t.sp(28)
      implicitWidth: Math.max(bc.t.sp(56), btnText.implicitWidth + bc.t.sp(24))
      radius: Math.max(4, bc.t.radiusSmall)
      color: btnMa.pressed ? Qt.darker(fill.a > 0 ? fill : bc.t.hoverStrong, 1.15) : btnMa.containsMouse ? (fill.a > 0 ? Qt.lighter(fill, 1.08) : bc.t.hover) : fill
      border.width: fill.a > 0 ? 0 : 1
      border.color: bc.t.lineStrong
      Text {
        id: btnText
        anchors.centerIn: parent
        text: bc.label(bc.ctl.html, parent.fill.a > 0 ? bc.t.hex(bc.t.onColor(parent.fill)) : bc.t.hex(bc.t.fgBright))
        textFormat: Text.RichText
        font.family: bc.t.font
        font.pixelSize: bc.t.fsSmall
        font.bold: true
      }
      MouseArea { id: btnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bc.pressed(bc.ctl, null) }
    }
  }

  Component {
    id: overflowC
    Rectangle {
      id: ov
      implicitWidth: bc.t.sp(28)
      implicitHeight: bc.t.sp(28)
      radius: Math.max(4, bc.t.radiusSmall)
      color: ovMa.containsMouse ? bc.t.hover : "transparent"
      border.width: 1
      border.color: bc.t.lineStrong
      Glyph { app: bc.app; anchors.centerIn: parent; inkCentered: true; icon: "󰇘"; size: bc.t.fsIcon; color: bc.t.fgBright }
      MouseArea { id: ovMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bc.menu(ov) }
    }
  }

  Component {
    id: selectC
    BlockBox {
      id: sel
      app: bc.app
      fill: bc.fill
      html: bc.ctl.html
      hint: bc.ctl.placeholder
      icon: bc.ctl.icon === "date" ? "󰃭" : bc.ctl.icon === "time" ? "󰥔" : ""
      onHit: (bc.ctl.options || []).length ? bc.menu(sel) : bc.pressed(bc.ctl, null)
    }
  }

  Component {
    id: datetimeC
    Row {
      spacing: bc.t.sp(8)
      BlockBox { app: bc.app; html: bc.ctl.date; hint: bc.ctl.placeholder; icon: "󰃭"; minW: bc.t.sp(170); onHit: bc.pressed(bc.ctl, null) }
      BlockBox { app: bc.app; html: bc.ctl.time; hint: bc.ctl.placeholder; icon: "󰥔"; minW: bc.t.sp(130); onHit: bc.pressed(bc.ctl, null) }
    }
  }

  Component {
    id: fieldC
    BlockBox {
      app: bc.app
      fill: bc.fill
      html: bc.ctl.html
      hint: bc.ctl.placeholder
      icon: bc.ctl.icon === "file" ? "󰋊" : ""
      chevron: false
      minW: bc.t.sp(260)
      maxW: bc.t.sp(480)
      implicitHeight: bc.ctl.multi ? bc.t.sp(72) : bc.t.sp(32)
      onHit: bc.pressed(bc.ctl, null)
    }
  }

  // Checkboxes / radio buttons: each choice with its mark, words and
  // description under them.
  Component {
    id: choicesC
    Column {
      spacing: bc.t.sp(6)
      Repeater {
        model: bc.ctl.options
        delegate: Item {
          required property var modelData
          readonly property bool radio: bc.kind === "radios"
          implicitWidth: mark.width + bc.t.sp(8) + Math.max(optText.implicitWidth, optDesc.visible ? optDesc.implicitWidth : 0)
          implicitHeight: Math.max(mark.height, optCol.implicitHeight)
          width: implicitWidth
          height: implicitHeight
          Rectangle {
            id: mark
            y: Math.max(0, (optText.implicitHeight - height) / 2)
            width: bc.t.sp(14); height: width
            radius: parent.radio ? width / 2 : 3
            color: parent.modelData.on && !parent.radio ? bc.t.accent : "transparent"
            border.width: parent.modelData.on && !parent.radio ? 0 : 1
            border.color: parent.modelData.on ? bc.t.accent : bc.t.lineStrong
            Glyph { visible: parent.parent.modelData.on && !parent.parent.radio; app: bc.app; anchors.centerIn: parent; icon: "󰄬"; size: bc.t.fsTiny; color: bc.t.onColor(bc.t.accent) }
            Rectangle { visible: parent.parent.modelData.on && parent.parent.radio; anchors.centerIn: parent; width: parent.width - bc.t.sp(6); height: width; radius: width / 2; color: bc.t.accent }
          }
          Column {
            id: optCol
            x: mark.width + bc.t.sp(8)
            spacing: 2
            Text { id: optText; text: bc.label(parent.parent.modelData.html, bc.t.hex(bc.t.fg)); textFormat: Text.RichText; font.family: bc.t.font; font.pixelSize: bc.t.fsText }
            Text { id: optDesc; visible: parent.parent.modelData.desc !== ""; text: bc.label(parent.parent.modelData.desc, bc.t.hex(bc.t.fgDim)); textFormat: Text.RichText; font.family: bc.t.font; font.pixelSize: bc.t.fsSmall }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bc.pressed(bc.ctl, parent.modelData) }
        }
      }
    }
  }
}
