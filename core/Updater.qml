import QtQuick
import Quickshell
import Quickshell.Io

// New versions of the plugin, looked for a little after start-up and every
// six hours in the manifest on GitHub's main branch (raw.githubusercontent:
// a plain file, no API and no rate limit; curl sends nothing of yours, the
// Slack session only ever goes to Slack), unless "Check for updates" is off
// in Preferences (setting "checkUpdates"; the menu's check still looks).
// Shown as the green button over your photo (Rail.qml) and in your menu
// (DlgAccount.qml). A click opens the update the way Omarchy shows its own,
// in its floating terminal (lib/update.sh): both versions and the exact
// command, `omarchy plugin update` for a git folder in Omarchy's plugin
// folder (what `omarchy plugin add` makes), which shows the changes and asks
// itself, or `git pull --ff-only` for a checkout of this repo of your own,
// after a confirm; then its output. Once it pulled, the whole shell
// restarts (as omarchy-update ends), and the new copy brings the window
// back and says how it went. A copy outside git only hears where to get it. Background checks are quiet; only the menu's
// check reports errors.
Item {
  id: u
  property var app: null

  readonly property string repo: "https://github.com/leonavas/omaslack"
  readonly property string manifestUrl: "https://raw.githubusercontent.com/leonavas/omaslack/main/manifest.json"
  // `SLACKQS_UPDATE_DEV=1` takes whatever GitHub has as newer, to see the button.
  readonly property bool dev: Quickshell.env("SLACKQS_UPDATE_DEV") === "1"
  // Where an update leaves its note (.json), the pid of its terminal's run
  // (.pid), its output (.log) and exit code (.rc) for whichever copy of us
  // is running once it's done: the restart replaces this one in the middle.
  // In the session's runtime folder, else the app's private cache
  // (~/.cache/omaslack, made 700 at start-up and by lib/update.sh).
  readonly property string base: (Quickshell.env("XDG_RUNTIME_DIR") || (u.app ? u.app.cacheDir : "")) + "/omaslack-update"
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
  // "" (nothing to do), "available", "updating" (its terminal is open), or
  // "updated": on disk but not loaded (the shell didn't restart; the button
  // restarts it).
  property string phase: ""
  property bool checking: false  // a check asked for from the menu

  // How this copy was installed: "omarchy" (a git folder in Omarchy's
  // plugin folder, what `omarchy plugin add` makes and `omarchy plugin
  // update` pulls), "checkout" (a clone of this repo of your own with the
  // plugin at its top, linked there: `git pull` in it) or "other"; with the
  // plugin's id (its folder's name, as Omarchy names it) and the folder to
  // pull in.
  property string mode: ""
  property string pluginId: ""
  property string folder: ""

  // Empty when a click can update (in git); else how to, for the toast and the menu.
  readonly property string how: {
    if (!u.app || u.mode === "omarchy" || u.mode === "checkout") return ""
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
  // its .git (the test `omarchy plugin update` makes). A working copy of
  // your own (a symlink there) is pulled by itself only when the plugin's
  // folder is the top of the repo and its origin is this repo on GitHub
  // (https or ssh); any other git folder there goes through Omarchy too.
  Process {
    id: where
    command: ["sh", "-c",
      'd=${1%/}; id=${d##*/}; real=$(readlink -f -- "$d"); plugins=$(readlink -f -- "$HOME/.config/omarchy/plugins")\n' +
      'origin=$(git -C "$real" remote get-url origin 2>/dev/null); origin=${origin%/}; origin=${origin%.git}\n' +
      'if [ ! -L "$d" ] && [ -d "$d/.git" ] && [ "$real" = "$plugins/$id" ]; then printf "omarchy\\t%s\\t%s\\n" "$id" "$real"\n' +
      'elif top=$(git -C "$real" rev-parse --show-toplevel 2>/dev/null) && [ "$(readlink -f -- "$top")" = "$real" ] &&\n' +
      '  case $origin in https://github.com/leonavas/omaslack | git@github.com:leonavas/omaslack | ssh://git@github.com/leonavas/omaslack) true ;; *) false ;; esac\n' +
      'then printf "checkout\\t%s\\t%s\\n" "$id" "$real"\n' +
      'elif [ -d "$plugins/$id/.git" ]; then printf "omarchy\\t%s\\t%s\\n" "$id" "$(readlink -f -- "$plugins/$id")"\n' +
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

  // The first look once the app has settled, then every six hours; none
  // while "Check for updates" is off in Preferences.
  readonly property bool autoCheck: !!u.app && u.app.settingsLoaded && u.app.setting("checkUpdates", true) !== false
  Timer { interval: 20000; running: u.autoCheck; onTriggered: u.check(false) }
  Timer { interval: 6 * 3600 * 1000; running: u.autoCheck; repeat: true; onTriggered: u.check(false) }

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
  // The button and the menu's row: open the update's terminal, or reload
  // once it's on disk; or how to, when the copy isn't in git.
  function update() {
    if (u.phase === "updated") { u.reload(); return }
    if (u.phase !== "available") return
    if (u.how || !u.pluginId) { u.say(u.how || u.app.tr("Couldn't find where the plugin is installed", "Não foi possível achar onde o plugin está instalado")); return }
    u.phase = "updating"
    u.say(u.app.tr("Confirm the update to " + u.latest + " in the terminal", "Confirme a atualização para " + u.latest + " no terminal"))
    run.command = ["bash", u.folderIn + "/lib/update.sh", "open", "--mode=" + u.mode, "--id=" + u.pluginId, "--folder=" + u.folder,
                   "--from=" + u.version, "--to=" + u.latest, "--base=" + u.base, "--note=" + u.note(u.latest),
                   "--lang=" + u.app.lang, "--repo=" + u.repo]
    run.running = true
    pickupTimer.restart()
  }
  function note(to) { return JSON.stringify({ from: u.version, to: to, open: !!u.app.windowOpen }) }

  // Leaves the note and opens the terminal, forked off in a session (and a
  // uwsm scope) of its own, so the shell restart that comes with the update
  // doesn't close it; done at once. Not 0: no terminal to open, and no note left.
  Process {
    id: run
    onExited: code => {
      if (code !== 0 && u.phase === "updating") {
        u.phase = "available"
        u.say(u.app.tr("Couldn't open a terminal for the update", "Não foi possível abrir um terminal para a atualização"))
      }
      if (!pickup.running) pickup.running = true
    }
  }

  // On disk but not loaded: the shell restarts (a rescan of its plugins
  // keeps the old QML; the rescan only without omarchy-restart-shell), in a
  // session of its own so it outlives this shell, and the new copy says so,
  // as after an update.
  function reload() {
    Quickshell.execDetached(["setsid", "-f", "sh", "-c",
      'mkdir -p -m 700 -- "${1%/*}"; printf "%s\\n" "$2" >"$1.json"; : >"$1.log"; echo 0 >"$1.rc"\n' +
      'command -v omarchy-shell >/dev/null 2>&1 || PATH=$PATH:${OMARCHY_PATH:-/usr/share/omarchy}/bin\n' +
      'if command -v omarchy-restart-shell >/dev/null 2>&1; then omarchy-restart-shell; else omarchy-shell shell rescanPlugins; fi',
      "omaslack-reload", u.base, u.note(u.latest)])
  }

  // ---------------------------------------------------------------- the outcome
  // Whoever is running once the update is done reads how it went: this copy
  // when nothing reloaded (it failed, was declined or up to date already),
  // else the new one. Taken once its exit code is two seconds old, so a
  // restart it set off has replaced this copy by then. 3: nothing pending;
  // 4: just done; 5: its terminal is still open (by the run's pid; one that
  // never started is given up on after thirty seconds).
  Process {
    id: pickup
    command: ["sh", "-c",
      'b=$1; [ -f "$b.json" ] || exit 3; now=$(date +%s)\n' +
      'if [ ! -f "$b.rc" ]; then pid=$(cat "$b.pid" 2>/dev/null)\n' +
      '  if [ -n "$pid" ]; then kill -0 "$pid" 2>/dev/null && exit 5\n' +
      '  elif [ $((now - $(stat -c %Y "$b.json"))) -lt 30 ]; then exit 5; fi\n' +
      '  [ -f "$b.rc" ] || { rm -f "$b.json" "$b.log" "$b.pid"; exit 3; }\n' +
      'fi\n' +
      '[ $((now - $(stat -c %Y "$b.rc"))) -ge 2 ] || exit 4\n' +
      'head -n 1 "$b.json"; head -n 1 "$b.rc"; tail -n 20 "$b.log" 2>/dev/null; rm -f "$b.json" "$b.rc" "$b.log" "$b.pid"',
      "pickup", u.base]
    stdout: StdioCollector { id: pickupOut; waitForEnd: true }
    onExited: code => {
      if (code === 0) { pickupTimer.stop(); u.outcome(String(pickupOut.text)); return }
      if (code === 4 || code === 5 || (code === 3 && run.running)) return
      pickupTimer.stop()
      if (u.phase !== "updating") return
      // Updating, with no note left: its terminal never started, or went
      // without a word (killed).
      u.phase = "available"
      u.say(u.app.tr("Didn't update: the terminal didn't open or was closed", "Não atualizou: o terminal não abriu ou foi fechado"))
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
    // Declined in the terminal, or it was closed: it said so there.
    if (rc === 130) {
      if (mine) u.phase = u.latest ? "available" : ""
      return
    }
    // "<id> is up to date." from Omarchy, "Already up to date." from git.
    if (rc === 0 && log.some(function(l) { return /up[ -]to[ -]date\.$/i.test(l) })) {
      u.phase = ""
      u.latest = ""
      msg = u.app.tr("Slack is already the latest", "O Slack já é a versão mais recente")
    } else if (rc === 0 && n.from && u.newer(u.version, n.from)) {
      u.phase = ""
      u.latest = ""
      msg = u.app.tr("Updated to " + u.version, "Atualizado para " + u.version)
    } else if (rc === 0) {
      // On disk, but this is still the old copy: the shell didn't restart.
      u.latest = n.to || u.latest
      u.phase = "updated"
      msg = u.app.tr("Updated to " + u.latest + " · click reload to use it", "Atualizado para " + u.latest + " · clique em recarregar para usar")
    } else {
      u.phase = u.latest ? "available" : ""
      // The first error git or Omarchy gave (git's last line is "Aborting"), else the last line.
      var bad = log.filter(function(l) { return /^(omarchy-plugin-update|error|fatal):/.test(l) })
      var why = (bad.length ? bad[0] : log.length ? log[log.length - 1] : "exit " + rc)
                .replace(/^(omarchy-plugin-update|error|fatal):\s*/, "").replace(/:$/, "")
      msg = u.app.tr("Didn't update: ", "Não atualizou: ") + why
    }
    if (mine || !n.open) { u.say(msg); return }
    // A new copy after the restart: the window comes back first.
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
