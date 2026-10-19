import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/Util.js" as U

// The wire to Slack for one workspace: lib/transport.py, spoken to in JSON
// lines. Calls come back to their callback, the socket's frames to
// `frameHandler`; its opening and closing arrive as signals. The process
// restarts itself if it ever dies.
Item {
  id: root

  property string token: ""
  property string cookie: ""
  property bool enabled: true

  readonly property string script: String(Qt.resolvedUrl("../lib/transport.py")).replace(/^file:\/\//, "")
  property bool started: false
  property bool socketOpen: false

  // A frame as parsed, called directly: through a signal's `var` its
  // arrays would arrive as lists Array.isArray doesn't take.
  property var frameHandler: null

  signal socketOpened()
  signal socketClosed(string reason)

  property int _seq: 0
  property var _pending: ({})
  property var _queue: []

  function _write(obj) {
    var line = JSON.stringify(obj) + "\n"
    if (root.started && proc.running) proc.write(line)
    else root._queue.push(line)
  }

  function _sendCreds() { _write({ op: "creds", token: root.token, cookie: root.cookie }) }
  onTokenChanged: _sendCreds()
  onCookieChanged: _sendCreds()

  function _request(obj, cb) {
    var id = ++root._seq
    obj.id = id
    if (cb) root._pending[id] = cb
    _write(obj)
    return id
  }

  // Web API: cb({ok, status, body, error}).
  function call(method, params, cb) { return _request({ op: "call", method: method, params: params || {} }, cb) }
  // `reuse`: a file already at `dest` is kept (and marked as just used).
  // `noClobber`: one already there stays; this one gets "name (1).ext"…
  function download(url, dest, cb, htmlOk, reuse, noClobber) {
    return _request({ op: "download", url: url, dest: dest, html_ok: !!htmlOk, reuse: !!reuse, no_clobber: !!noClobber }, cb)
  }
  function postFile(url, path, cb) { return _request({ op: "post_file", url: url, path: path }, cb) }
  function multipart(method, fields, path, field, mime, cb) {
    return _request({ op: "multipart", method: method, fields: fields || {}, path: path || "", field: field || "file", mime: mime || "" }, cb)
  }
  function readCookie(db, cb) { return _request({ op: "read_cookie", db: db }, cb) }
  // A file of the config dir, 0600 from the start and replaced in one step.
  function writePrivate(name, text, cb) { return _request({ op: "write_private", name: name, text: text }, cb) }
  function openSocket(url) { _write({ op: "ws_open", url: url }) }
  function sendSocket(data) { if (root.socketOpen) _write({ op: "ws_send", data: data }) }
  function closeSocket() { _write({ op: "ws_close" }) }

  function _line(text) {
    if (!text) return
    var msg
    try { msg = JSON.parse(text) } catch (e) { console.warn("omaslack: bad transport line", text.slice(0, 200)); return }
    if (msg.ws) {
      if (msg.ws === "msg") { if (root.frameHandler) root.frameHandler(msg.data) }
      else if (msg.ws === "open") { root.socketOpen = true; root.socketOpened() }
      else if (msg.ws === "closed") { root.socketOpen = false; root.socketClosed(msg.reason || "") }
      return
    }
    var cb = root._pending[msg.id]
    if (cb) {
      delete root._pending[msg.id]
      try { cb(msg) } catch (e) { console.warn("omaslack: callback failed:", e, e.stack) }
    }
  }

  Process {
    id: proc
    command: ["python3", "-u", "-I", root.script]
    // The user agent it sends (lib/Util.js chromeUa).
    environment: ({ OMASLACK_UA: U.chromeUa() })
    running: root.enabled
    stdinEnabled: true
    stdout: SplitParser { onRead: data => root._line(data) }
    stderr: SplitParser { onRead: data => console.warn("omaslack transport:", data) }
    onStarted: {
      root.started = true
      root._sendCreds()
      var q = root._queue
      root._queue = []
      for (var i = 0; i < q.length; i++) proc.write(q[i])
    }
    onExited: (code, status) => {
      root.started = false
      if (root.socketOpen) { root.socketOpen = false; root.socketClosed("transport exited") }
      var pending = root._pending
      root._pending = ({})
      for (var id in pending) {
        try { pending[id]({ ok: false, error: "transport exited" }) } catch (e) {}
      }
      if (root.enabled) restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 1500
    onTriggered: if (root.enabled && !proc.running) proc.running = true
  }

  Component.onDestruction: {
    root.enabled = false
    if (proc.running) proc.signal(15)
  }
}
