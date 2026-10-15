import QtQuick

// Scrolls a list to a spot smoothly instead of jumping there, as Slack does
// ("Jump to recent", the sidebar's unread pills, a message from search).
// `place` puts the view there at once (positionViewAtIndex, …): Glide notes
// where that leaves contentY, puts it back and animates there, so the
// list's own layout (bottom-to-top, header, margins) decides the spot. Far
// off, or when measuring had to lay the rows out anew (those out of the
// cache are only estimated), it goes most of the way at once and glides the
// last stretch. Rows that grew on the way re-aim it at the end; the wheel,
// a drag or any other scroll on the way stops it.
Item {
  id: g
  property ListView view: null
  readonly property bool running: g._on || g._busy
  // Further than `far` it starts `lead` short of the spot.
  readonly property real far: view ? view.height * 1.5 : 0
  readonly property real lead: view ? view.height * 0.6 : 0

  property real pos: 0
  property real _at: 0            // the contentY last set here
  property bool _on: false
  property bool _busy: false      // measuring or placing: the moves are ours
  property int _gen: 0
  property int _tries: 0
  property var _place: null
  property var _done: null

  onPosChanged: {
    if (!g._on) return
    g._at = g.pos
    g.view.contentY = g.pos
  }

  // To where `place()` puts the view; `done()` once there (not if stopped).
  function to(place, done) {
    g.stop()
    if (!g.view) return
    var m = g.measure(place), d = m.to - m.from, spot = m.to, start = m.from
    if (m.kept && Math.abs(d) < 1) { if (done) done(); return }
    if (!m.kept || Math.abs(d) > g.far) {
      if (m.kept) { g.put(place); spot = g.view.contentY }
      start = g.backOff(spot, d < 0 ? -1 : 1, Math.abs(d))
    }
    g.run(start, spot, place, done)
  }

  // The rows were just replaced: in from `lead` short of the spot, on the
  // side the reader comes from (dir 1: down to it, -1: up to it).
  function enter(place, dir, done) {
    g.stop()
    if (!g.view) return
    g.put(place)
    var spot = g.view.contentY
    g.run(g.backOff(spot, dir, g.lead), spot, place, done)
  }

  function stop() {
    g._on = false
    g._gen++
    anim.stop()
    g._place = null
    g._done = null
  }

  // Where `place()` puts contentY. `kept`: what's on screen stayed put and
  // the view is back where it was; else the rows were laid out anew and
  // the view is left on the spot.
  function measure(place) {
    var v = g.view, from = v.contentY, x = v.width / 2
    var at = v.indexAt(x, from + v.height / 2)
    if (at < 0) at = v.indexAt(x, from + 1)
    if (at < 0) at = v.indexAt(x, from + v.height - 1)
    var probe = at >= 0 ? v.itemAtIndex(at) : null, py = probe ? probe.y : 0
    g._busy = true
    place()
    var spot = v.contentY
    var kept = !probe || (v.itemAtIndex(at) === probe && Math.abs(probe.y - py) < 1)
    if (kept) v.contentY = from
    g._busy = false
    return { from: from, to: spot, kept: kept }
  }

  function put(place) {
    g._busy = true
    place()
    g._busy = false
  }

  // On the spot: back `lead` (or `dist`, if nearer) towards the side the
  // reader comes from. The rows on the way are laid out from the spot's.
  function backOff(spot, dir, dist) {
    var v = g.view
    var top = v.originY - v.topMargin
    var bottom = Math.max(top, v.originY + v.contentHeight - v.height + v.bottomMargin)
    var start = Math.max(top, Math.min(bottom, spot - dir * Math.min(g.lead, dist)))
    g._busy = true
    v.contentY = start
    g._busy = false
    return start
  }

  function run(start, spot, place, done) {
    g._place = place
    g._done = done || null
    g._tries = 0
    g._on = true
    if (Math.abs(spot - start) < 1) { g.land(); return }
    g.animate(start, spot, Math.round(Math.min(340, 240 + Math.abs(spot - start) / 12)))
  }

  function animate(start, spot, ms) {
    g._at = start
    anim.stop()
    anim.from = start
    anim.to = spot
    anim.duration = ms
    anim.start()
  }

  // There: rows that grew (or came) on the way moved the spot? Once or
  // twice more, briefly, then straight on it.
  function land() {
    if (!g._on) return
    var m = g.measure(g._place)
    if (m.kept && Math.abs(m.to - m.from) >= 1) {
      if (g._tries < 2) { g._tries++; g.animate(m.from, m.to, 160); return }
      g.put(g._place)
    }
    var done = g._done
    g.stop()
    if (done) done()
  }

  NumberAnimation {
    id: anim
    target: g
    property: "pos"
    easing.type: Easing.OutCubic
    // A beat later: the rows reached on the last step are laid out by then.
    onFinished: { var gen = g._gen; Qt.callLater(function() { if (gen === g._gen) g.land() }) }
  }

  // The reader takes over: the wheel, a drag, the scroll bar, the keys.
  Connections {
    target: g.view
    enabled: g._on
    function onContentYChanged() { if (!g._busy && Math.abs(g.view.contentY - g._at) > 1) g.stop() }
    function onMovementStarted() { g.stop() }
    function onDraggingChanged() { if (g.view.dragging) g.stop() }
  }
}
