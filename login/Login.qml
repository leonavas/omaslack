import QtQuick
import QtQuick.Window
import QtWebEngine

// The sign-in window: Slack's own sign-in page in Qt WebEngine, run by Qt's
// `qml` runtime in a process of its own (WebEngine can't live inside the
// shell). Once the person is in, it prints the session it found and quits;
// the browser profile (in the session's runtime dir, a tmpfs) keeps the
// HttpOnly `d` cookie for the plugin.
//
//   qml Login.qml -- <profile dir> <known team ids,…> <lang> <workspace or ""> [cache dir] [user agent]
//
// The HTTP cache goes to <cache dir> (Qt's default is under
// ~/.cache/<app>/QtWebEngine/), which the plugin empties once the window
// is gone; the profile keeps cookies and storage. <user agent> is the
// plugin's (lib/Util.js chromeUa); plain QML has no way to read the
// environment.
Window {
  id: win
  width: 540
  height: 800
  visible: true
  color: "#1a1d21"

  readonly property var args: {
    var a = Qt.application.arguments
    var i = a.indexOf("--")
    return i >= 0 ? a.slice(i + 1) : []
  }
  readonly property string profileDir: args[0] || ""
  readonly property var known: String(args[1] || "").split(",").filter(function(x) { return x.length > 0 })
  readonly property bool pt: String(args[2] || "").indexOf("pt") === 0
  readonly property string workspace: String(args[3] || "").replace(/[^A-Za-z0-9-]/g, "")
  readonly property string cacheDir: String(args[4] || "")
  readonly property string givenUa: String(args[5] || "").replace(/[^\x20-\x7e]/g, "").trim()
  property bool done: false

  title: pt ? "Entrar no Slack" : "Sign in to Slack"

  readonly property string startUrl: workspace ? "https://" + workspace + ".slack.com/sign_in_with_password"
                                   : (known.length ? "https://slack.com/signin" : "https://app.slack.com/client")

  function status(s) { console.log("SLACKQS-STATUS " + s) }

  function chromeMajor(ua) { var m = String(ua).match(/Chrome\/(\d+)/); return m ? parseInt(m[1], 10) : 0 }
  // A current desktop Chrome, since Slack's sign-in page turns away
  // browsers it thinks are old (QtWebEngine's own says Chrome 140 and
  // QtWebEngine/x.y.z): the plugin's, never older than the engine itself;
  // without one, the engine's own less its QtWebEngine token.
  function userAgent(engine) {
    var own = String(engine).replace(/QtWebEngine\/\S+\s*/, "")
    if (!win.givenUa) return own
    var major = win.chromeMajor(own)
    return win.chromeMajor(win.givenUa) >= major ? win.givenUa : win.givenUa.replace(/Chrome\/\d+/, "Chrome/" + major)
  }

  WebEngineProfilePrototype {
    id: proto
    storageName: "omaslack"
    persistentStoragePath: win.profileDir
    // Empty: Qt's default.
    cachePath: win.cacheDir
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    Component.onCompleted: {
      // Before the page exists, so its first request already says so.
      var p = proto.instance()
      p.httpUserAgent = win.userAgent(p.httpUserAgent)
      // The client hints (Sec-CH-UA-Full-Version*, userAgentData) tell the
      // same version.
      var major = win.chromeMajor(p.httpUserAgent)
      if (major > 0) {
        var v = major + ".0.0.0"
        p.clientHints.fullVersion = v
        p.clientHints.fullVersionList = { "Google Chrome": v, "Chromium": v, "Not_A Brand": "24.0.0.0" }
      }
      loader.active = true
    }
  }

  Loader {
    id: loader
    anchors.fill: parent
    active: false
    sourceComponent: WebEngineView {
      id: view
      profile: proto.instance()
      url: win.startUrl

      // slack:// would launch the desktop app: that workspace opens in the
      // web client here instead, where its session is taken.
      onNavigationRequested: function(request) {
        var u = String(request.url)
        if (u.indexOf("slack://") !== 0) return
        if (typeof request.reject === "function") request.reject()
        else request.action = WebEngineNavigationRequest.IgnoreRequest
        var m = u.match(/team=(T[A-Z0-9]+)/)
        view.url = m ? "https://app.slack.com/client/" + m[1] : "https://app.slack.com/client"
      }
      // A popup opens here instead, and only a web page (no file:, data: or
      // other schemes).
      onNewWindowRequested: function(request) {
        var u = String(request.requestedUrl)
        if (/^https?:\/\//i.test(u)) view.url = u
      }
      onUrlChanged: {
        var u = String(view.url)
        // After signing in Slack lands on /ssb/redirect, which wants the
        // desktop app; go on to the web client.
        if (/^https:\/\/[^\/]*slack\.com\/ssb\/redirect/.test(u)) {
          view.runJavaScript("(function(){var a=document.querySelector('a[href*=\"app.slack.com/client\"]');return a?a.href:''})()", function(href) {
            view.url = href || "https://app.slack.com/client"
          })
        }
        if (/^https:\/\/app\.slack\.com\/client\/T/.test(u)) win.status(win.pt ? "Lendo a sessão…" : "Reading the session…")
      }
      onLoadingChanged: function(info) {
        if (info.status === WebEngineView.LoadFailedStatus) win.status((win.pt ? "A página não carregou: " : "The page didn't load: ") + info.errorString)
      }
    }
  }

  // On the web client, the session is in localStorage (localConfig_v2).
  // Only the one taken is printed: its token and team, no other team's.
  Timer {
    interval: 1000
    repeat: true
    running: loader.item !== null && !win.done
    onTriggered: {
      var view = loader.item
      if (String(view.url).indexOf("https://app.slack.com/") !== 0) return
      var known = JSON.stringify(win.known)
      view.runJavaScript("(function(){try{var known=" + known + ";var cfg=JSON.parse(localStorage.getItem('localConfig_v2')||'null');" +
        "if(!cfg||!cfg.teams)return '';var m=location.pathname.match(/\\/client\\/(T[A-Z0-9]+)/);" +
        "var all=Object.keys(cfg.teams).map(function(k){return cfg.teams[k]}).filter(function(t){return t&&t.id&&t.token});" +
        "var fresh=all.filter(function(t){return known.indexOf(t.id)<0});var named=m&&cfg.teams[m[1]];" +
        "var team=(named&&known.indexOf(named.id)<0?named:null)||(fresh.length===1?fresh[0]:null);if(!team||!team.token)return '';" +
        "return JSON.stringify({token:team.token,team:team.id})}catch(e){return ''}})()",
        function(result) {
          if (!result || win.done) return
          win.done = true
          console.log("SLACKQS-RESULT " + result)
          // The browser writes its cookies when the profile closes.
          quit.start()
        })
    }
  }

  Timer { id: quit; interval: 1200; onTriggered: Qt.quit() }
}
