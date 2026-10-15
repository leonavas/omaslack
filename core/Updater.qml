import QtQuick
import Quickshell
import Quickshell.Io

// New versions of the plugin, looked for a little after start-up and every
// six hours in the manifest on GitHub's main branch (raw.githubusercontent:
// a plain file, no API and no rate limit; curl sends nothing of yours, the
// Slack session only ever goes to Slack). Shown as the green button over
// your photo (Rail.qml) and in your menu (DlgAccount.qml), as slick does by
// your name. A click updates it when Omarchy installed it from git
// (`omarchy plugin add`): `omarchy plugin update`, after which the shell
// reloads its plugins, this one with them, and the new copy brings the
// window back and says how it went. A checkout of your own (a symlink in
// Omarchy's plugin folder, or a copy anywhere else) is left alone: the click
// only tells how to update it, as slick does when something else owns its
// binary. Background checks are quiet; only the menu's check reports errors.
Item {
  id: u
  property var app: null

  readonly property string repo: "https://github.com/leonavas/omaslack"
  readonly property string manifestUrl: "https://raw.githubusercontent.com/leonavas/omaslack/main/manifest.json"
  // `SLACKQS_UPDATE_DEV=1` takes whatever GitHub has as newer, to see the button.
  readonly property bool dev: Quickshell.env("SLACKQS_UPDATE_DEV") === "1"
  // Where an update leaves its note (.json), output (.log) and exit code
  // (.rc) for whichever copy of us is running once it's done: the reload
  // replaces this one in the middle of it.
  readonly property string base: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omaslack-update"
  readonly property string folderIn: { try { return u.app ? decodeURIComponent(u.app.pluginDir) : "" } catch (e) { return u.app.pluginDir } }

  // This copy's version: what the shell loaded, else the manifest on disk.
  FileView {
    id: manifestFile
    path: u.folderIn ? u.folderIn + "/manifest.json" : ""
    printErrors: false
    blockLoading: true
  }
  readonly property string version: {
    if (u.app && u.app.manifest && u.app.manifest.version) return String(u.app.manifest.version)
    try { return String(JSON.parse(manifestFile.text()).version || "") } catch (e) { return "" }
  }

  // ---------------------------------------------------------------- state
  property string latest: ""     // the newer version found
  // "" (nothing to do), "available", "updating", or "updated": on disk but
  // not loaded (the shell didn't reload; the button reloads it).
  property string phase: ""
  property bool checking: false  // a check asked for from the menu

  // How this copy was installed: "omarchy" (a git clone in Omarchy's plugin
  // folder, what `omarchy plugin add` makes and `omarchy plugin update`
  // pulls), "checkout" (a symlink there, or a copy in a git repo elsewhere:
  // yours to pull) or "other"; with the plugin's id (its folder's name, as
  // Omarchy names it) and the folder to pull in.
  property string mode: ""
  property string pluginId: ""
  property string folder: ""

  // Empty when a click can update; else how to, for the toast and the menu.
  readonly property string how: {
    if (!u.app || u.mode === "omarchy") return ""
    var home = u.app.home
    var at = home && u.folder.indexOf(home + "/") === 0 ? "~" + u.folder.slice(home.length) : u.folder
    if (u.mode === "checkout") return u.app.tr("a checkout of your own: run git pull in " + at, "um checkout seu: rode git pull em " + at)
    return u.app.tr("not installed from git: get the new version at " + u.repo, "não instalado pelo git: pegue a versão nova em " + u.repo)
  }

  // "1.10.0" > "1.9.2"; whatever follows the digits of a part ("0-rc1") is ignored.
  function newer(a, b) {
    function parts(v) { return String(v || "").replace(/^v/, "").split(".").map(function(p) { return parseInt(p, 10) || 0 }) }
    var x = parts(a), y = parts(b)
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
      if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0)
    }
    return false
  }

  // A toast in the window, or a desktop notification while it's closed.
  function say(text) {
    var w = u.app.window
    if (u.app.windowOpen && w && w.toast) w.toast(text)
    else Quickshell.execDetached(["notify-send", "-a", "Slack", "-i", u.app.appIcon, "Slack", text])
  }

  // ---------------------------------------------------------------- where
  // A clone Omarchy made is a real folder in ~/.config/omarchy/plugins with
  // its .git (the test `omarchy plugin update` makes); a symlink there is a
  // working copy of your own, even when it's a git repo.
  Process {
    id: where
    command: ["sh", "-c",
      'd=${1%/}; id=${d##*/}; real=$(readlink -f -- "$d"); plugins=$(readlink -f -- "$HOME/.config/omarchy/plugins")\n' +
      'if [ ! -L "$d" ] && [ -d "$d/.git" ] && [ "$real" = "$plugins/$id" ]; then printf "omarchy\\t%s\\t%s\\n" "$id" "$real"\n' +
      'elif top=$(git -C "$real" rev-parse --show-toplevel 2>/dev/null); then printf "checkout\\t%s\\t%s\\n" "$id" "$top"\n' +
      'else printf "other\\t%s\\t%s\\n" "$id" "$real"; fi',
      "where", u.folderIn]
    stdout: StdioCollector { id: whereOut; waitForEnd: true }
    onExited: {
      var f = String(whereOut.text).trim().split("\t")
      u.mode = f[0] || "other"
      u.pluginId = f[1] || ""
      u.folder = f[2] || u.folderIn
    }
  }

  // ---------------------------------------------------------------- checking
  Process {
    id: fetch
    command: ["curl", "-fsSL", "--max-time", "20", "-H", "Cache-Control: no-cache", u.manifestUrl]
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    stderr: StdioCollector { id: fetchErr; waitForEnd: true }
    onExited: code => u.fetched(code, String(fetchOut.text), String(fetchErr.text))
  }

  // The first look once the app has settled, then every six hours.
  Timer { interval: 20000; running: !!u.app; onTriggered: u.check(false) }
  Timer { interval: 6 * 3600 * 1000; running: !!u.app; repeat: true; onTriggered: u.check(false) }

  // `manual`: from the menu, which hears back even when nothing is new.
  function check(manual) {
    if (manual) u.checking = true
    if (!fetch.running) fetch.running = true
  }

  function fetched(code, out, err) {
    var manual = u.checking
    u.checking = false
    var ver = ""
    try { ver = String(JSON.parse(out).version || "") } catch (e) { ver = "" }
    if (code !== 0 || !ver) {
      // No manifest to show: a made-up version, so the button still shows.
      if (u.dev) { u.found(u.version + "-dev", manual); return }
      if (!manual) return
      var why = code === 127 ? u.app.tr("curl is missing", "falta o curl")
              : (String(err).trim().split("\n").pop().replace(/^curl: \(\d+\)\s*/, "") || u.app.tr("the manifest has no version", "o manifest não tem versão"))
      u.say(u.app.tr("Couldn't check for updates: ", "Não foi possível procurar atualizações: ") + why)
      return
    }
    if (u.dev || u.newer(ver, u.version)) u.found(ver, manual)
    else if (manual) u.say(u.app.tr("Slack is up to date (" + u.version + ")", "O Slack está atualizado (" + u.version + ")"))
  }

  // Kept while it updates, and once on disk unless this is newer still.
  function found(ver, manual) {
    if (manual) u.say(u.app.tr("Slack " + ver + " is available", "Slack " + ver + " disponível"))
    if (u.phase === "updating" || (u.phase === "updated" && !u.newer(ver, u.latest))) return
    u.latest = ver
    u.phase = "available"
  }

  // ---------------------------------------------------------------- updating
  // The button and the menu's row: update, or reload once it's on disk; or
  // how to, when the copy isn't Omarchy's to update.
  function update() {
    if (u.phase === "updated") { u.reload(); return }
    if (u.phase !== "available") return
    if (u.how || !u.pluginId) { u.say(u.how || u.app.tr("Couldn't find where the plugin is installed", "Não foi possível achar onde o plugin está instalado")); return }
    u.phase = "updating"
    u.say(u.app.tr("Updating Slack to " + u.latest + "… the shell then reloads its plugins and the window comes back",
                   "Atualizando o Slack para " + u.latest + "… depois o shell recarrega os plugins e a janela volta"))
    run.command = ["setsid", "-f", "-w", "sh", "-c",
      'b=$2; printf "%s\\n" "$3" >"$b.json"; rm -f "$b.rc"\n' +
      'command -v omarchy >/dev/null 2>&1 || PATH=$PATH:${OMARCHY_PATH:-/usr/share/omarchy}/bin\n' +
      'omarchy plugin update "$1" --yes >"$b.log" 2>&1; echo $? >"$b.rc"',
      "omaslack-update", u.pluginId, u.base, u.note(u.latest)]
    run.running = true
    pickupTimer.restart()
  }
  function note(to) { return JSON.stringify({ from: u.version, to: to, open: !!u.app.windowOpen }) }

  // In a session of its own: the reload that comes with the update (the
  // shell watches its plugin folder, and the script rescans at the end)
  // ends this Process, and must not end the update with it.
  Process {
    id: run
    onExited: if (!pickup.running) pickup.running = true
  }

  // On disk but not loaded: the shell reloads its plugins, and the new copy
  // says so, as after an update.
  function reload() {
    Quickshell.execDetached(["sh", "-c",
      'printf "%s\\n" "$2" >"$1.json"; : >"$1.log"; echo 0 >"$1.rc"\n' +
      'command -v omarchy-shell >/dev/null 2>&1 || PATH=$PATH:${OMARCHY_PATH:-/usr/share/omarchy}/bin\n' +
      'omarchy-shell shell rescanPlugins',
      "omaslack-reload", u.base, u.note(u.latest)])
  }

  // ---------------------------------------------------------------- the outcome
  // Whoever is running once the update is done reads how it went: this copy
  // when nothing reloaded (it failed, or was up to date already), else the
  // new one. Taken once its exit code is two seconds old, so a reload it set
  // off has replaced this copy by then. 3: nothing pending; 4: just done;
  // 5: still running (a stale note is dropped after ten minutes).
  Process {
    id: pickup
    command: ["sh", "-c",
      'b=$1; [ -f "$b.json" ] || exit 3; now=$(date +%s)\n' +
      'if [ ! -f "$b.rc" ]; then [ $((now - $(stat -c %Y "$b.json"))) -lt 600 ] && exit 5; rm -f "$b.json" "$b.log"; exit 3; fi\n' +
      '[ $((now - $(stat -c %Y "$b.rc"))) -ge 2 ] || exit 4\n' +
      'head -n 1 "$b.json"; head -n 1 "$b.rc"; tail -n 20 "$b.log" 2>/dev/null; rm -f "$b.json" "$b.rc" "$b.log"',
      "pickup", u.base]
    stdout: StdioCollector { id: pickupOut; waitForEnd: true }
    onExited: code => {
      if (code === 0) { pickupTimer.stop(); u.outcome(String(pickupOut.text)); return }
      if (code === 4 || code === 5 || (code === 3 && run.running)) return
      pickupTimer.stop()
      if (u.phase !== "updating") return
      // Updating, with no note left: it never started.
      u.phase = "available"
      u.say(u.app.tr("Didn't update: couldn't run omarchy plugin update", "Não atualizou: não foi possível rodar omarchy plugin update"))
    }
  }
  Timer { id: pickupTimer; interval: 1000; repeat: true; onTriggered: if (!pickup.running) pickup.running = true }

  function outcome(text) {
    var lines = text.split("\n")
    var n = {}
    try { n = JSON.parse(lines[0]) } catch (e) { n = {} }
    var rc = parseInt(lines[1], 10)
    var log = lines.slice(2).map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
    var mine = u.phase === "updating"
    var msg
    if (rc === 0 && log.some(function(l) { return / is up to date\.$/.test(l) })) {
      u.phase = ""
      u.latest = ""
      msg = u.app.tr("Slack is already the latest", "O Slack já é a versão mais recente")
    } else if (rc === 0 && n.from && u.newer(u.version, n.from)) {
      u.phase = ""
      u.latest = ""
      msg = u.app.tr("Updated to " + u.version, "Atualizado para " + u.version)
    } else if (rc === 0) {
      // On disk, but this is still the old copy: the shell didn't reload.
      u.latest = n.to || u.latest
      u.phase = "updated"
      msg = u.app.tr("Updated to " + u.latest + " · click reload to use it", "Atualizado para " + u.latest + " · clique em recarregar para usar")
    } else {
      u.phase = u.latest ? "available" : ""
      var why = log.length ? log[log.length - 1].replace(/^omarchy-plugin-update:\s*/, "") : "exit " + rc
      msg = u.app.tr("Didn't update: ", "Não atualizou: ") + why
    }
    if (mine || !n.open) { u.say(msg); return }
    // A new copy after the reload: the window comes back first.
    u._later = msg
    comeBack.restart()
  }

  property string _later: ""
  // Once the bar widget has handed over its options (where the window goes).
  Timer { id: comeBack; interval: 1500; onTriggered: { u.app.showWindow(); sayLater.restart() } }
  Timer { id: sayLater; interval: 900; onTriggered: { u.say(u._later); u._later = "" } }

  Component.onCompleted: {
    where.running = true
    pickupTimer.start()
  }
}
