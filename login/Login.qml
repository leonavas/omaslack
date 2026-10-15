import QtQuick
import QtQuick.Window
import QtWebEngine

// The sign-in window: Slack's own sign-in page in Qt WebEngine, run by Qt's
// `qml` runtime in a process of its own (WebEngine can't live inside the
// shell). Once the person is in, it prints the session it found and quits;
// the browser profile keeps the HttpOnly `d` cookie on disk for the plugin.
//
//   qml Login.qml -- <profile dir> <known team ids,…> <lang> <workspace or ""> [cache dir]
//
// The HTTP cache goes to <cache dir> (Qt's default is under
// ~/.cache/<app>/QtWebEngine/), which the plugin empties once the window
// is gone; the profile keeps cookies and storage.
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
  property bool done: false

  title: pt ? "Entrar no Slack" : "Sign in to Slack"

  readonly property string startUrl: workspace ? "https://" + workspace + ".slack.com/sign_in_with_password"
                                   : (known.length ? "https://slack.com/signin" : "https://app.slack.com/client")

  function status(s) { console.log("SLACKQS-STATUS " + s) }

  WebEngineProfilePrototype {
    id: proto
    storageName: "omaslack"
    persistentStoragePath: win.profileDir
    // Empty: Qt's default.
    cachePath: win.cacheDir
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    Component.onCompleted: loader.active = true
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
      onNewWindowRequested: function(request) { view.url = request.requestedUrl }
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
        "return JSON.stringify({token:team.token,team:team.id,teams:all.map(function(t){return {id:t.id,name:t.name||'',domain:t.domain||'',token:t.token}})})}catch(e){return ''}})()",
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
