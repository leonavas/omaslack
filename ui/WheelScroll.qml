import QtQuick

// The wheel and the touchpad for a list, further than Qt's own: a notch
// goes `step` pixels, the touchpad `touch` times the distance it moved.
// Every event moves a target and the list eases toward it frame by frame,
// so notches in a row (or a touchpad's stream of small moves) add up into
// one smooth motion instead of restarting it. It takes the event (the
// list scrolling too would add its own); `wheeled` comes before the move,
// so whoever watches the list knows it's the reader.
WheelHandler {
  id: w
  property Flickable view: null
  property real step: 200
  property real touch: 2
  signal wheeled()
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  target: null

  property real dest: 0
  property real _set: 0            // the contentY last set here

  function bounds() {
    var v = w.view
    var lo = v.originY - v.topMargin
    return [lo, Math.max(lo, v.originY + v.contentHeight + v.bottomMargin - v.height)]
  }

  property FrameAnimation ease: FrameAnimation {
    running: false
    onTriggered: {
      var v = w.view
      // Moved by someone else on the way (a glide, the list's own
      // keeping in place): stop, from there.
      if (!v || Math.abs(v.contentY - w._set) > 1) { stop(); return }
      var b = w.bounds()
      w.dest = Math.max(b[0], Math.min(b[1], w.dest))
      var diff = w.dest - v.contentY
      if (Math.abs(diff) < 0.5) { v.contentY = w.dest; stop(); return }
      v.contentY += diff * Math.min(1, frameTime * 16)
      w._set = v.contentY
    }
  }

  onWheel: event => {
    var v = w.view
    if (!v) return
    // A touchpad's events come in phases; a wheel's have none (Wayland
    // still gives them a pixelDelta, 15 a notch, which isn't the distance).
    var pad = event.phase !== Qt.NoScrollPhase && event.pixelDelta.y !== 0
    var d = pad ? event.pixelDelta.y * w.touch : event.angleDelta.y / 120 * w.step
    if (!d) return
    w.wheeled()
    if (!w.ease.running) { w.dest = v.contentY; w._set = v.contentY }
    var b = w.bounds()
    w.dest = Math.max(b[0], Math.min(b[1], w.dest - d))
    if (!w.ease.running) w.ease.start()
  }
}
