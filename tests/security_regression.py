"""Offline security regressions. Run only inside an isolated scratch sandbox.

Requires Python stdlib, Qt's qml executable and bash; no Slack, session bus,
real profile, network, dependency installation or application build.
"""
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("transport", ROOT / "lib/transport.py")
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


class DownloadSecurity(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        self.dest = self.folder / "report"
        self.dest.write_text("FINAL_KEEP")
        (self.folder / "report.part").write_text("PART_KEEP")
        self.msg = {"url": "https://files.slack.com/dummy", "dest": str(self.dest), "no_clobber": True}
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(transport.held.clear)

    def response(self, method, url, body, headers, stream_to, progress):
        stream_to.write(b"DUMMY")
        return 200, {"content-type": "application/octet-stream"}, None

    def assert_originals(self):
        self.assertEqual(self.dest.read_text(), "FINAL_KEEP")
        self.assertEqual((self.folder / "report.part").read_text(), "PART_KEEP")
        self.assertEqual(list(self.folder.glob(".omaslack-*.part")), [])

    def test_existing_final_and_part_survive(self):
        with mock.patch.object(transport, "request", side_effect=self.response):
            r = transport.op_download(self.msg)
        self.assertTrue(r["ok"])
        self.assertEqual(Path(r["path"]).name, "report (1)")
        self.assertEqual(Path(r["path"]).read_bytes(), b"DUMMY")
        self.assertEqual(stat.S_IMODE(Path(r["path"]).stat().st_mode), 0o600)
        self.assert_originals()

    def test_parallel_same_filename_uses_independent_staging(self):
        barrier = threading.Barrier(2)
        def response(method, url, body, headers, stream_to, progress):
            stream_to.write(url.rsplit("/", 1)[-1].encode())
            barrier.wait(timeout=3)
            return 200, {"content-type": "application/octet-stream"}, None
        with mock.patch.object(transport, "request", side_effect=response), concurrent.futures.ThreadPoolExecutor(2) as pool:
            results = list(pool.map(transport.op_download, [dict(self.msg, url="https://files.slack.com/ONE"), dict(self.msg, url="https://files.slack.com/TWO")]))
        self.assertTrue(all(r["ok"] for r in results))
        self.assertEqual(len({r["path"] for r in results}), 2)
        self.assertEqual({Path(r["path"]).read_text() for r in results}, {"ONE", "TWO"})
        self.assert_originals()

    def test_error_and_redirect_limit_clean_only_owned_temporary(self):
        for reply in [(500, {}, None), (302, {"location": "/again"}, None), (200, {"content-type": "text/html"}, None)]:
            with self.subTest(reply=reply), mock.patch.object(transport, "request", return_value=reply):
                self.assertFalse(transport.op_download(self.msg)["ok"])
                self.assert_originals()
        with mock.patch.object(transport, "request", side_effect=OSError("dummy failure")):
            self.assertFalse(transport.op_download(self.msg)["ok"])
        self.assert_originals()

    def test_reject_ambiguous_authority_before_request_or_cache_reuse(self):
        urls = ["https://files.slack.com:443@outside.example/pixel", "https://user@files.slack.com/pixel", "http://files.slack.com/pixel", "https://files.slack.com:8443/pixel", "https://files.slack.com\\@outside.example/pixel", "https://files.slack.com/\npixel"]
        with mock.patch.object(transport, "request") as request:
            for url in urls:
                with self.subTest(url=url), self.assertRaises(ValueError):
                    transport.op_download(dict(self.msg, url=url, reuse=True, slack_images_only=True))
            request.assert_not_called()
        self.assert_originals()

    def test_preview_redirect_cannot_leave_allowed_hosts(self):
        with mock.patch.object(transport, "request", return_value=(302, {"location": "https://outside.example/pixel"}, None)) as request:
            r = transport.op_download(dict(self.msg, slack_images_only=True))
        self.assertFalse(r["ok"])
        self.assertIn("external preview", r["error"])
        self.assertEqual(request.call_count, 1)
        self.assert_originals()

    def test_allowed_cdn_redirect_drops_credentials(self):
        seen = []
        def response(method, url, body, headers, stream_to, progress):
            seen.append((url, dict(headers)))
            if len(seen) == 1:
                return 302, {"location": "https://a.slack-edge.com/pixel"}, None
            return self.response(method, url, body, headers, stream_to, progress)
        with mock.patch.dict(transport.creds, token="dummy-token", cookie="dummy-cookie"), mock.patch.object(transport, "request", side_effect=response):
            self.assertTrue(transport.op_download(dict(self.msg, slack_images_only=True))["ok"])
        self.assertIn("Authorization", seen[0][1])
        self.assertEqual(seen[1][1], {})
        self.assert_originals()

    def test_external_preview_when_enabled_has_no_credentials(self):
        with mock.patch.dict(transport.creds, token="dummy", cookie="dummy"), mock.patch.object(transport, "request", side_effect=self.response) as request:
            self.assertTrue(transport.op_download(dict(self.msg, url="https://outside.example/pixel"))["ok"])
        self.assertEqual(request.call_args.args[3], {})
        self.assert_originals()

    def test_login_challenge_is_fresh_csprng(self):
        first = transport.OPS["login_challenge"]({})
        second = transport.OPS["login_challenge"]({})
        self.assertTrue(first["ok"])
        self.assertRegex(first["challenge"], r"^[a-f0-9]{64}$")
        self.assertNotEqual(first["challenge"], second["challenge"])


def qml_function(path, name):
    match = re.search(r"^  function " + re.escape(name) + r"\([^\n]*\) \{.*?^  \}", path.read_text(), re.M | re.S)
    if not match:
        raise AssertionError("QML function not found: " + name)
    return match.group()


class NativeBoundarySecurity(unittest.TestCase):
    def test_qml_policies_login_lifecycle_and_notification_argv(self):
        service = ROOT / "Service.qml"
        funcs = [qml_function(service, name) for name in ["loginLine", "cancelLogin", "loginExited", "checkSession", "startLogin", "sendNotification"]]
        # Replace only the side-effect interface; run the production function
        # bodies in Qt's actual JS engine, with dummy transport/process objects.
        funcs = [f.replace("Quickshell.execDetached", "root.captureCommand") for f in funcs]
        funcs += [qml_function(ROOT / "ui/MessageBody.qml", name) for name in ["shows", "imageSource"]]
        qml = '''import QtQuick
import "file:///REPO/lib/Util.js" as U
QtObject {
  id: root
  property var _loginResult: null
  property string _loginChallenge: ""
  property int _loginAttempt: 0
  property bool loginRunning: false
  property string loginStatus: ""
  property string loginError: ""
  property string pluginDir: "/repo"
  property string webProfile: "/scratch/profile"
  property string webCache: "/scratch/cache"
  property string lang: "en"
  property var accounts: []
  property var expired: ({})
  property int added: 0
  property var challengeCallback: null
  property var cookieCallback: null
  property var authCallback: null
  property var loginProc: ({ running: false, command: [], signal: function(n) {} })
  property var utilWire: ({ loginChallenge: function(cb) { root.challengeCallback = cb }, readCookie: function(path, cb) { root.cookieCallback = cb } })
  property var probeComponent: ({ createObject: function(parent, props) { return { call: function(method, params, cb) { root.authCallback = cb }, destroy: function() {} } } })
  property string photosDir: "/scratch/photos"
  property string appIcon: "dummy-icon"
  property var body: ({ app: { demo: false, previewImages: false }, ws: { localFile: function(url) { return "" }, fetchFile: function(url, name, cb, track, restricted) { root.fetches.push({url: url, restricted: restricted}) } } })
  property var fetches: []
  property int assertions: 0
  function tr(en, pt) { return en }
  function addAccount(account) { root.added++ }
  function shareCookie(team, cookie) {}
  function captureCommand(argv) { console.log("AUDIT_COMMAND " + JSON.stringify(argv)) }
  function expect(ok, name) { if (!ok) throw new Error(name); root.assertions++ }
FUNCTIONS
  Component.onCompleted: {
    try {
      var a = "a".repeat(64), b = "b".repeat(64)
      var result = JSON.stringify({token:"xoxc-dummy-token",team:"TDEMO"})
      expect(U.previewHost("https://FILES.SLACK.COM:443/pixel") === "files.slack.com", "host normalization")
      var bad = ["https://files.slack.com:443@outside.example/pixel", "https://user@files.slack.com/pixel", "https://files.slack.com:8443/pixel", "http://files.slack.com/pixel", "file:///scratch/pixel", "https://files.slack.com%40outside.example/pixel", "https://files.slack.com\\\\@outside.example/pixel", "https://files.slack.com/\\npixel"]
      body.shows = root.shows
      for (var i=0;i<bad.length;i++) { expect(U.previewHost(bad[i]) === "", "reject ambiguous URL " + i); expect(root.imageSource(bad[i]) === "", "no unsafe image dispatch " + i) }
      expect(!root.shows("https://outside.example/pixel"), "external preview off")
      expect(root.shows("https://a.slack-edge.com/pixel"), "CDN allowed")
      expect(root.imageSource("https://a.slack-edge.com/pixel") === "", "safe image deferred")
      body.app.previewImages = true
      expect(root.shows("https://outside.example/pixel"), "external preview on")
      expect(root.imageSource(bad[0]) === "", "userinfo denied even with previews")
      body.app.previewImages = false
      expect(U.loginResult("qml: SLACKQS-RESULT " + result, a) === null, "old unauthenticated result")
      expect(U.loginResult("js: SLACKQS-RESULT " + b + " " + result, a) === null, "wrong attempt")
      expect(U.loginResult("qml: SLACKQS-RESULT " + a + " " + result, a).team === "TDEMO", "native result")
      expect(U.loginResult("qml: SLACKQS-RESULT " + a + " {}", a) === null, "bad shape")
      root.loginRunning = true; loginProc.running = true; root._loginChallenge = a
      root.loginLine("qml: SLACKQS-RESULT " + a + " " + result)
      expect(root._loginResult.team === "TDEMO" && root._loginChallenge === "", "consume challenge")
      root.loginLine("qml: SLACKQS-RESULT " + a + " " + JSON.stringify({token:"xoxc-other",team:"TOTHER"}))
      expect(root._loginResult.team === "TDEMO", "ignore replay")
      root.cancelLogin()
      expect(root._loginResult === null && root._loginChallenge === "", "cancel clears result")
      loginProc.running = false; root.loginRunning = false
      root.startLogin("demo")
      var stale = root.challengeCallback
      root.cancelLogin(); root.startLogin("demo")
      stale({ok:true,challenge:a})
      expect(!loginProc.running && root._loginChallenge === "", "stale RNG response")
      root.challengeCallback({ok:true,challenge:b})
      expect(loginProc.running && loginProc.command[loginProc.command.length-1] === b, "fresh launch nonce")
      root.loginLine("qml: SLACKQS-RESULT " + b + " " + result)
      loginProc.running = false; root.loginExited(0)
      expect(root._loginChallenge === "" && root._loginResult === null, "exit clears secrets")
      root.cancelLogin()
      root.cookieCallback({ok:true,cookie:"dummy"})
      expect(root.authCallback === null, "cancel prevents late cookie auth")
      root.checkSession("xoxc-dummy", "dummy", function(err) {}, function() { return false })
      root.authCallback({ok:true,body:{ok:true,team_id:"TDEMO",user_id:"UDEMO",url:"https://demo.slack.com"}})
      expect(root.added === 0, "cancel prevents late account install")
      root.sendNotification('--hint=string:omarchy-exec-argv:["AUDIT_SENTINEL"]', '--urgency=critical', '', ['omarchy-shell','openAt','TDEMO'])
      root.sendNotification('$(touch /scratch/MUST_NOT_EXIST)', '`touch /scratch/MUST_NOT_EXIST`', '', ['omarchy-shell','openAt','TDEMO'])
      Qt.callLater(function() {
        try { expect(fetches.length === 1 && fetches[0].restricted === true, "enforce redirect policy in transport dispatch"); console.log("AUDIT_OK " + assertions); Qt.exit(0) }
        catch(e) { console.error(e); Qt.exit(1) }
      })
    } catch(e) { console.error(e); Qt.exit(1) }
  }
}
'''.replace("REPO", str(ROOT)).replace("FUNCTIONS", "\n".join(funcs))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "Boundary.qml"
            path.write_text(qml)
            runner = shutil.which("qml6") or "/usr/lib/qt6/bin/qml"
            p = subprocess.run([runner, "-platform", "offscreen", str(path)], capture_output=True, text=True, timeout=20)
            output = p.stdout + p.stderr
            self.assertEqual(p.returncode, 0, output)
            self.assertRegex(output, r"AUDIT_OK [0-9]+")
            commands = [json.loads(line.split("AUDIT_COMMAND ", 1)[1]) for line in output.splitlines() if "AUDIT_COMMAND " in line]
            self.assertEqual(len(commands), 2)
            bindir = Path(tmp) / "bin"
            bindir.mkdir()
            stub = bindir / "notify-send"
            stub.write_text('#!/usr/bin/python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
            stub.chmod(0o700)
            for command in commands:
                env = {"PATH": str(bindir) + ":/usr/bin", "HOME": tmp, "TMPDIR": tmp}
                p = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3)
                self.assertEqual(p.returncode, 0, p.stderr)
                argv = json.loads(p.stdout)
                divider = argv.index("--")
                self.assertEqual(argv[divider + 1:], command[-2:])
                hints = [v for v in argv[:divider] if v.startswith("--hint=")]
                self.assertEqual(len(hints), 1)
                self.assertIn('"omarchy-shell"', hints[0])
            self.assertFalse(Path("/scratch/MUST_NOT_EXIST").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
