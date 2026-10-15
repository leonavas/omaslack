import QtQuick
import Quickshell.Widgets

// Rounded clipping (Quickshell's ClippingRectangle). On the software
// renderer, which can't draw it, a plain clipped rectangle stands in. The
// content lives in `stash`, moved between the two and never destroyed.
Item {
  id: c
  property real radius: 0
  property color color: "transparent"
  property int borderWidth: 0
  property color borderColor: "transparent"
  default property alias content: stash.data
  readonly property bool soft: GraphicsInfo.api === GraphicsInfo.Software

  function place() {
    if (c.soft) {
      stash.parent = softRect
      hard.active = false
    } else if (hard.item) {
      stash.parent = hard.item.contentItem ? hard.item.contentItem : hard.item
    } else {
      stash.parent = c
      hard.active = true
    }
  }
  onSoftChanged: place()
  Component.onCompleted: place()

  Rectangle {
    id: softRect
    visible: c.soft
    anchors.fill: parent
    radius: c.radius
    color: c.color
    border.width: c.borderWidth
    border.color: c.borderColor
    clip: true
  }

  Loader {
    id: hard
    anchors.fill: parent
    active: false
    sourceComponent: ClippingRectangle {
      radius: c.radius
      color: c.color
      border.width: c.borderWidth
      border.color: c.borderColor
    }
    onLoaded: c.place()
  }

  Item {
    id: stash
    width: c.width
    height: c.height
  }
}
