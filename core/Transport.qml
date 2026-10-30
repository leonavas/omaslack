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
  property var _progress: ({})   // id → onProgress(done, total) of a download
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
  // `onProgress(done, total)`: as it arrives (total 0 when not known).
  function download(url, dest, cb, htmlOk, reuse, noClobber, onProgress) {
    var id = _request({ op: "download", url: url, dest: dest, html_ok: !!htmlOk, reuse: !!reuse, no_clobber: !!noClobber, progress: !!onProgress }, cb)
    if (onProgress) root._progress[id] = onProgress
    return id
  }
  // A video's cover (a blurred frame of its first second) into `dest`,
  // from its start alone (transport.py's video_frame).
  function videoFrame(url, dest, cb) { return _request({ op: "video_frame", url: url, dest: dest }, cb) }
  // A local http URL that plays a Slack file as it comes (transport.py's
  // stream): cb({ok, url}).
  function stream(url, cb) { return _request({ op: "stream", url: url }, cb) }
  function postFile(url, path, cb) { return _request({ op: "post_file", url: url, path: path }, cb) }
  function multipart(method, fields, path, field, mime, cb) {
    return _request({ op: "multipart", method: method, fields: fields || {}, path: path || "", field: field || "file", mime: mime || "" }, cb)
  }
  function readCookie(db, cb) { return _request({ op: "read_cookie", db: db }, cb) }
  // A file of the config dir, 0600 from the start and replaced in one step.
  function writePrivate(name, text, cb) { return _request({ op: "write_private", name: name, text: text }, cb) }
  // A workspace's entry in the system keyring (secret-tool).
  function secretStore(team, label, secret, cb) { return _request({ op: "secret_store", team: team, label: label, secret: secret }, cb) }
  function secretLookup(team, cb) { return _request({ op: "secret_lookup", team: team }, cb) }
  function secretClear(team, cb) { return _request({ op: "secret_clear", team: team }, cb) }
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
    if (msg.progress !== undefined) {
      var p = root._progress[msg.id]
      if (p) { try { p(msg.progress, msg.total || 0) } catch (e) { console.warn("omaslack: progress failed:", e) } }
      return
    }
    delete root._progress[msg.id]
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
      root._progress = ({})
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
