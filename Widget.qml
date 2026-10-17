import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Registry.js" as Registry
import "lib/Bar.js" as Bar

// The bar's door into the Slack client: Slack's mark in white with a faint
// outline, a red badge for DMs and a blue one for channels, a preview of
// what is waiting on hover, the reactions to your messages floating out of
// the icon, and a menu on right click. The app itself is the plugin's
// service (Service.qml); lib/Bar.js folds its workspaces into what the
// badges and the card show.
BarWidget {
  id: root
  moduleName: "omaslack"

  // ---------------------------------------------------------------- settings
  readonly property string iconStyle: String(setting("iconStyle", "Outline"))
  readonly property string glyph: String(setting("glyph", "󰒱"))
  readonly property int glyphSize: Math.max(0, Number(setting("glyphSize", 0)))
  readonly property real glyphOffsetY: Number(setting("glyphOffsetY", 0))
  readonly property string badgeStyle: String(setting("badge", "Count"))
  // The older true/false "channelBadge" (a dot for channels) reads as
  // Unread or None.
  readonly property string channelBadgeMode: {
    var v = setting("channelBadge", "Unread")
    return v === false ? "None" : v === true ? "Unread" : String(v)
  }
  readonly property bool combinedBadge: String(setting("badgeLayout", "Split")) === "Combined"
  readonly property string dmColorSetting: String(setting("dmColor", "#b65f4e"))
  readonly property string channelColorSetting: String(setting("channelColor", "#467996"))
  readonly property real badgeScale: Math.max(0.2, Math.min(0.9, Number(setting("badgeScale", 0.45))))
  readonly property bool tintWhenUnread: setting("tintWhenUnread", false) === true
  readonly property string hideMode: String(setting("hideMode", "Special workspace"))
  readonly property string specialName: String(setting("specialWorkspace", "scratchpad"))
  readonly property bool openInSpecial: setting("openInSpecial", false) === true
  readonly property bool autoStart: setting("autoStart", false) === true
  readonly property bool launchForeground: setting("launchForeground", true) !== false
  readonly property bool dimWhenClosed: setting("dimWhenClosed", true) !== false
  readonly property bool hideWhenNotRunning: setting("hideWhenNotRunning", false) === true
  readonly property bool closeOnMiddle: setting("middleClickCloses", true) !== false
  readonly property bool hoverPreview: setting("hoverPreview", true) !== false
  readonly property int previewRows: Math.max(1, Number(setting("previewRows", 6)))
  readonly property int previewMessages: Math.max(1, Math.min(5, Number(setting("previewMessages", 3))))
  readonly property bool previewChannels: setting("previewChannels", false) === true
  readonly property bool showReactions: setting("showReactions", true) !== false
  // Threads you follow: their new replies count in the badges (mentions red,
  // the rest blue) and the unread ones get a section in the card.
  readonly property bool showThreads: setting("showThreads", true) !== false
  // Channels count only when they mention you: no blue badge or row for the
  // channels that notify you, all of them in the footer.
  readonly property bool channelMentionsOnly: setting("channelMentionsOnly", false) === true
  // Desktop notifications and their text. Absent from the bar's entry, the
  // app's own switches (Preferences, before they moved here) still count.
  readonly property bool desktopNotifications: setting("notifications",
    root.service ? root.service.setting("notifications", true) !== false : true) !== false
  readonly property bool notificationText: setting("notificationText",
    root.service ? root.service.setting("notificationPreview", true) !== false : true) !== false
  readonly property string mutedIndicator: String(setting("mutedIndicator", "Bell"))

  // ------------------------------------------------------------------- theme
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  // A red for DMs and group DMs, a blue for channels. An empty DM color
  // falls back to the theme's urgent color, an empty channel color to the
  // DM one.
  readonly property color directColor: root.dmColorSetting.length > 0 ? root.dmColorSetting : root.urgentColor
  readonly property color channelColor: root.channelColorSetting.length > 0 ? root.channelColorSetting : root.directColor
  readonly property color badgeDigitColor: "#ffffff"
  readonly property color badgeTextColor: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- service
  property var service: null
  function findService() {
    var s = null
    try { if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function") s = root.bar.shell.serviceFor("omaslack") } catch (e) { s = null }
    if (!s) s = Registry.service
    root.service = s
  }
  Timer { interval: 400; repeat: true; running: !root.service; triggeredOnStart: true; onTriggered: root.findService() }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onDestroyed() { root.service = null }
  }

  function tr(en, pt) { return root.service ? root.service.tr(en, pt) : en }
  readonly property string lang: root.service ? root.service.lang : "en"
  readonly property bool clock24: root.service ? root.service.clock24 : true

  // ------------------------------------------------------------------ window
  // The app's window: open (mapped), parked in the special workspace,
  // focused. The service moves it and sends the notifications; these
  // settings go to it, and it writes the app's toggles of the
  // notifications back here (writeSetting).
  readonly property bool running: !!root.service && root.service.windowOpen
  readonly property bool focused: !!root.service && root.service.windowFocused
  readonly property bool parked: !!root.service && root.service.parked
  readonly property bool specialShown: !!root.service && root.service.specialShown
  readonly property var windowOptions: ({ specialName: root.specialName, openInSpecial: root.openInSpecial,
                                          hideMode: root.hideMode, launchForeground: root.launchForeground,
                                          notifications: root.desktopNotifications, notificationText: root.notificationText })
  onWindowOptionsChanged: root.pushOptions()
  onServiceChanged: root.pushOptions()
  function pushOptions() {
    if (!root.service) return
    root.service.barOptions = root.windowOptions
    root.service.barWidget = root
  }
  // Gone (a bar rebuilt, a monitor unplugged): a copy on another monitor
  // takes over; with none left, the app's own switches count again.
  Component.onDestruction: {
    var s = root.service
    if (!s || s.barWidget !== root) return
    var peers = []
    try { if (root.bar && typeof root.bar.moduleWidgets === "function") peers = root.bar.moduleWidgets(root.moduleName) } catch (e) { peers = [] }
    var next = peers.filter(function(p) { return p && p !== root })[0] || null
    s.barWidget = next
    if (next) return
    var options = JSON.parse(JSON.stringify(s.barOptions || {}))
    delete options.notifications
    delete options.notificationText
    s.barOptions = options
  }

  // Signed out: a dimmed mark, and a card that leads to the sign-in.
  readonly property bool signedIn: !!root.service && root.service.signedIn
  readonly property bool notSignedIn: !!root.service && !root.service.signedIn

  // ------------------------------------------------------------- slack state
  // Wall clock for relative times and DND expiry, coarse on purpose.
  property real nowSec: Date.now() / 1000
  Timer {
    interval: 20000
    repeat: true
    running: true
    onTriggered: root.nowSec = Date.now() / 1000
  }

  readonly property var slackState: root.signedIn ? Bar.snapshot(root.service.workspaces, root.service.current, root.nowSec) : null
  readonly property bool stateLive: !!root.slackState && root.slackState.live

  readonly property int attention: Bar.attention(root.slackState)
  readonly property var totals: Bar.totals(root.slackState, root.channelMentionsOnly)
  readonly property bool muted: Bar.snoozed(root.slackState, root.nowSec)
  readonly property bool dndActive: Bar.dndActive(root.slackState, root.nowSec)
  // The card's rows, worked out only while it is open: the messages are
  // rendered for them.
  readonly property var emptyRows: ({ rows: [], hidden: 0 })
  readonly property var htmlColors: root.service ? root.service.theme.html : ({})
  readonly property int emojiPx: Math.round(Style.font.bodySmall * 1.1)
  readonly property var preview: root.popupOpen && root.slackState
    ? Bar.previewRows(root.slackState, root.previewRows, root.previewMessages, root.previewChannels, root.channelMentionsOnly,
                      root.htmlColors, root.emojiPx) : root.emptyRows
  // Reactions to your messages: listed in the card, never counted in a badge.
  readonly property var reactions: root.showReactions && root.popupOpen && root.slackState
    ? Bar.reactionRows(root.slackState, root.previewRows, root.htmlColors, root.emojiPx, root.lang) : root.emptyRows
  // Threads you follow with new replies.
  readonly property var threads: root.showThreads && root.popupOpen && root.slackState
    ? Bar.threadRows(root.slackState, root.previewRows, root.htmlColors, root.emojiPx) : root.emptyRows

  // While the card is open, the conversations it lists get their unread
  // messages, fetched again once their newest one moves.
  readonly property var previewTargets: root.popupOpen && root.slackState
    ? Bar.previewTargets(root.slackState, root.previewRows, root.previewChannels, root.channelMentionsOnly) : []
  onPreviewTargetsChanged: root.previewTargets.forEach(function(c) {
    if (typeof c.ws.fetchUnreadPreview === "function") c.ws.fetchUnreadPreview(c.id)
  })

  // A reaction whose key the last snapshot did not have just happened: it
  // floats up out of the icon. The first snapshot (shell start, a new
  // widget) only sets the baseline. A pause you set keeps it still, as it
  // does the badges.
  property var seenReactions: null
  onSlackStateChanged: root.noteReactions()
  function noteReactions() {
    if (!root.slackState) { root.seenReactions = null; return }
    var found = Bar.newReactions(root.slackState, root.seenReactions)
    root.seenReactions = found.keys
    if (!root.showReactions || root.muted || !root.visible) return
    // Oldest of the batch first, a few at most.
    var fresh = found.fresh.slice(0, 5).reverse()
    for (var i = 0; i < fresh.length; i++) root.floatReaction(fresh[i], i)
  }

  // ----------------------------------------------------------------- actions
  // Left click: open the window, bring it back, put it away (Service).
  function toggle() { if (root.service) root.service.toggleWindow() }

  // "Quit": the window closes; the app keeps counting and notifying.
  function quit() { if (root.service) root.service.hideWindow() }

  function openConversation(row) {
    root.popupOpen = false
    if (root.service) root.service.openConversation(row.team, row.id, row.ts, row.threadTs)
  }

  function pause(minutes) { if (root.service) root.service.pauseAll(Math.max(1, Math.round(minutes))) }
  function resume() { if (root.service) root.service.resumeAll() }

  // "Until a date and time…": a day and an hour:minute picked in the menu,
  // `pickerDay` days from today. The pause is the minutes from the moment of
  // the click to that time, rounded up.
  readonly property int pickerMaxDays: 30
  readonly property int pickerMinuteStep: 15
  property bool pickerOpen: false
  property int pickerDay: 0
  property int pickerHour: 0
  property int pickerMinute: 0
  readonly property real pickerTarget: Bar.pickerTarget(root.pickerDay, root.pickerHour, root.pickerMinute, root.nowSec)
  readonly property bool pickerValid: Bar.minutesUntil(root.pickerTarget, root.nowSec) > 0

  function resetPicker() {
    root.nowSec = Date.now() / 1000
    var start = Bar.pickerDefault(root.nowSec)
    root.pickerDay = start.day
    root.pickerHour = start.hour
    root.pickerMinute = start.minute
  }

  function stepPickerDay(delta) {
    root.pickerDay = Math.max(0, Math.min(root.pickerMaxDays, root.pickerDay + delta))
  }
  function stepPickerHour(delta) { root.pickerHour = (root.pickerHour + delta + 24) % 24 }
  function stepPickerMinute(delta) {
    root.pickerMinute = (root.pickerMinute + delta * root.pickerMinuteStep + 60) % 60
  }

  // Measured again at the click: the clock the label follows ticks every 20 s.
  function pauseUntilPicked() {
    var now = Date.now() / 1000
    var minutes = Bar.minutesUntil(Bar.pickerTarget(root.pickerDay, root.pickerHour, root.pickerMinute, now), now)
    if (minutes <= 0) { root.nowSec = now; return }
    root.close()
    root.pause(minutes)
  }

  function writeSetting(key, value) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.updateEntryInline !== "function") return
    var merged = JSON.parse(JSON.stringify(root.settings || {}))
    merged[key] = value
    shell.updateEntryInline(root.moduleName, merged)
  }

  // One bar surface per monitor means N copies of this widget; only the first
  // may act on the session as a whole.
  function isPrimaryInstance() {
    var peers = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    return peers.length === 0 || peers[0] === root
  }

  // Launch on Login: the window opens once the shell is up, once per shell
  // (a bar rebuilt later doesn't reopen a window you closed).
  Timer {
    interval: 2500
    repeat: false
    running: root.autoStart
    onTriggered: {
      var s = root.service
      if (!s || s.autoStarted || !root.isPrimaryInstance()) return
      s.autoStarted = true
      if (!s.windowOpen) s.launchWindow(root.launchForeground)
    }
  }

  // ----------------------------------------------------------- hover preview
  property bool popupOpen: false
  property bool menuOpen: false
  function close() {
    root.popupOpen = false
    root.menuOpen = false
  }

  onMenuOpenChanged: {
    if (!menuOpen) return
    root.popupOpen = false
    root.pickerOpen = false
    root.nowSec = Date.now() / 1000
  }

  // Available whenever the workspaces are in, empty or not, muted or not:
  // "nothing waiting" is an answer worth hovering for. Signed out, the card
  // leads to the sign-in.
  readonly property bool previewAvailable: ((root.hoverPreview && root.stateLive) || root.notSignedIn)
    && !root.menuOpen
  readonly property bool previewHovered: button.tooltipHovered || popup.containsMouse

  onPreviewAvailableChanged: if (!previewAvailable) root.popupOpen = false
  onPreviewHoveredChanged: {
    if (root.previewHovered && root.previewAvailable) {
      closePreviewTimer.stop()
      if (!root.popupOpen) openPreviewTimer.restart()
    } else {
      openPreviewTimer.stop()
      if (root.popupOpen) closePreviewTimer.restart()
    }
  }
  onPopupOpenChanged: if (popupOpen) root.nowSec = Date.now() / 1000

  Timer {
    id: openPreviewTimer
    interval: 350
    repeat: false
    onTriggered: if (root.previewHovered && root.previewAvailable) root.popupOpen = true
  }

  Timer {
    id: closePreviewTimer
    interval: 250
    repeat: false
    onTriggered: if (!root.previewHovered) root.popupOpen = false
  }

  // ------------------------------------------------------------------ layout
  visible: root.signedIn || !root.hideWhenNotRunning
  implicitWidth: root.visible ? button.implicitWidth : 0
  implicitHeight: root.visible ? button.implicitHeight : 0

  readonly property string pauseLabel: {
    var until = Bar.clockLabel(Bar.dndUntil(root.slackState), root.nowSec, root.lang, root.clock24)
    var head = root.muted ? root.tr("Notifications paused", "Notificações pausadas") : root.tr("Do not disturb", "Não perturbe")
    return until.length > 0 ? head + root.tr(" until ", " até ") + until : head
  }

  readonly property string tooltip: {
    if (!root.service) return "Slack"
    if (!root.signedIn) return root.tr("Slack: click to sign in", "Slack: clique para entrar")
    var text = "Slack"
    if (root.attention > 0) text += ": " + root.attention + root.tr(" waiting", " aguardando")
    if (root.muted) text += root.tr(" (notifications paused)", " (notificações pausadas)")
    else if (root.parked) text += root.attention > 0 ? "" : root.tr(", hidden", ", escondido")
    return text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: root.iconStyle === "Glyph" ? glyphIcon
      : root.iconStyle === "Mono" ? monoIcon
      : root.iconStyle === "Color" ? colorIcon : outlineIcon
    active: root.anyBadge
    useActiveColor: root.tintWhenUnread
    dimmed: ((root.notSignedIn || !root.running) && root.dimWhenClosed) || (root.muted && root.mutedIndicator === "Dim")
    tooltipText: root.previewAvailable ? "" : root.tooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        if (root.closeOnMiddle && !root.notSignedIn) root.quit()
      } else if (mouseButton === Qt.RightButton) {
        root.menuOpen = !root.menuOpen
      } else {
        // Signed out too: the window is where the sign-in is.
        root.menuOpen = false
        root.toggle()
      }
    }
  }

  // ------------------------------------------------------------------- icons
  // Outline (default) is Slack's white mark with a faint dark edge, so it
  // reads on light and dark bars without the colored mark's loudness. Color
  // is the mark in Slack's colors; Mono is the white one tinted like a
  // glyph; Glyph is any Nerd Font character.
  readonly property url monoIconSource: Qt.resolvedUrl("assets/slack-mono.svg")
  readonly property url colorIconSource: Qt.resolvedUrl("assets/slack.svg")
  // Tinted: red while a DM waits, blue while only channels do.
  readonly property color tintColor: root.dmCount > 0 ? root.directColor : root.channelColor
  readonly property color glyphColor: root.anyBadge && root.tintWhenUnread ? root.tintColor : root.foreground
  readonly property int glyphPixelSize: root.glyphSize > 0 ? root.glyphSize : Math.max(8, Style.bar.iconFont)
  // A pause you set fades the mark under the bell-off.
  readonly property real markOpacity: root.muted && root.mutedIndicator === "Bell" ? 0.45 : 1

  // Two counts, two corners. A manual pause hides both; Slack's scheduled
  // DND does not.
  readonly property bool badgesOn: !root.muted && root.badgeStyle !== "None" && root.signedIn
  // Thread replies split like Slack's: the ones that mention you join the
  // red count, the other new replies the blue one.
  readonly property bool threadBadges: root.badgesOn && root.showThreads
  readonly property int dmCount: root.badgesOn
    ? Bar.directMessages(root.slackState) + (root.threadBadges ? Bar.threadMentions(root.slackState) : 0) : 0
  readonly property int channelCount: root.badgesOn
    ? Bar.channelBadgeCount(root.slackState, root.channelBadgeMode, root.channelMentionsOnly)
      + (root.threadBadges ? Bar.threadBadgeCount(root.slackState, root.channelBadgeMode) : 0) : 0
  readonly property bool anyBadge: root.dmCount > 0 || root.channelCount > 0
  // "Combined" folds both into one badge in the DM corner: red while a DM
  // waits, blue when only channels do.
  readonly property int combinedCount: root.dmCount + root.channelCount
  readonly property color combinedColor: root.dmCount > 0 ? root.directColor : root.channelColor

  // Which corner each badge takes. Change these two to move them.
  readonly property string dmCorner: "bottom-right"
  readonly property string channelCorner: "top-right"

  Component {
    id: glyphIcon

    Item {
      opacity: root.markOpacity

      TextMetrics {
        id: metrics
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        text: root.glyph
      }

      Text {
        id: painted
        textFormat: Text.PlainText
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: painted.implicitWidth / 2
          - (metrics.tightBoundingRect.x + Math.max(1, metrics.tightBoundingRect.width) / 2)
        anchors.verticalCenterOffset: root.glyphOffsetY
        text: root.glyph
        color: root.glyphColor
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }

  // The white mark over its own silhouette, darkened and blurred a little:
  // the faint edge that keeps it readable on a light bar.
  Component {
    id: outlineIcon

    Item {
      opacity: root.markOpacity

      Image {
        id: outlineImage
        anchors.fill: parent
        anchors.margins: Math.round(parent.width * 0.04)
        fillMode: Image.PreserveAspectFit
        // Decode at physical pixels: the logical size leaves it blurry on HiDPI.
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: root.monoIconSource
        smooth: true
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: outlineImage
        source: outlineImage
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.7
        shadowBlur: 0.2
        blurMax: 6
        shadowScale: 1.05
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
      }
    }
  }

  Component {
    id: colorIcon

    Image {
      anchors.fill: parent
      anchors.margins: parent ? Math.round(parent.width * 0.04) : 0
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      source: root.colorIconSource
      opacity: root.markOpacity
      smooth: true
    }
  }

  Component {
    id: monoIcon

    Item {
      opacity: root.markOpacity

      Image {
        id: monoImage
        anchors.fill: parent
        anchors.margins: Math.round(parent.width * 0.04)
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: root.monoIconSource
        smooth: true
        // Hidden layer so the effect can sample it, the way the tray tints
        // symbolic icons.
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: monoImage
        source: monoImage
        colorization: 1.0
        colorizationColor: root.glyphColor
      }
    }
  }

  // A count centred on its pill by the ink of its digits, not by their
  // advance: in a monospace font a digit sits off-centre in its cell, and at
  // badge size the pixel or so that leaves shows.
  component CountText: Text {
    id: countText
    TextMetrics {
      id: ink
      font: countText.font
      text: countText.text
    }
    readonly property rect inkBox: ink.tightBoundingRect
    textFormat: Text.PlainText
    x: Math.round((parent.width - inkBox.width) / 2 - inkBox.x)
    y: Math.round((parent.height - inkBox.height) / 2 - (baselineOffset + inkBox.y))
  }

  // A small count pill on one corner of the icon canvas. A dot fits inside
  // the canvas; a count is nearly as tall as the canvas, so it is centred on
  // the corner instead, out into the slot's padding, like a tray badge.
  component CornerBadge: Rectangle {
    id: cornerBadge

    property int count: 0
    property string corner: "bottom-right"
    readonly property bool dotOnly: root.badgeStyle === "Dot"
    readonly property int sx: corner.indexOf("left") >= 0 ? -1 : 1
    readonly property int sy: corner.indexOf("top") === 0 ? -1 : 1

    visible: count > 0
    z: 2
    height: dotOnly ? Math.round(Style.bar.iconCanvas * root.badgeScale)
                    : Math.round(digits.implicitHeight + Style.space(1))
    width: dotOnly ? height : Math.max(height, Math.round(digits.implicitWidth + Style.space(5)))
    radius: height / 2

    // Vertically a little past the corner: with a badge on each right-hand
    // corner, that keeps the two off each other and off most of the mark.
    readonly property int reachX: dotOnly ? Math.round((Style.bar.iconCanvas - height) / 2)
                                          : Math.round(Style.bar.iconCanvas / 2)
    readonly property int reachY: dotOnly ? reachX : Math.round(Style.bar.iconCanvas / 2 + 1)
    readonly property int maxX: Math.max(0, Math.round((root.width - width) / 2))
    readonly property int maxY: Math.max(0, Math.round((root.height - height) / 2))

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: sx * Math.min(reachX, maxX)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: sy * Math.min(reachY, maxY)

    CountText {
      id: digits
      visible: !cornerBadge.dotOnly
      text: Bar.badgeLabel(cornerBadge.count)
      color: root.badgeDigitColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.85))
      font.bold: true
      renderType: Text.NativeRendering
    }
  }

  CornerBadge {
    count: root.combinedBadge ? root.combinedCount : root.dmCount
    corner: root.dmCorner
    color: root.combinedBadge ? root.combinedColor : root.directColor
  }

  CornerBadge {
    count: root.combinedBadge ? 0 : root.channelCount
    corner: root.channelCorner
    color: root.channelColor
  }

  // Paused by hand: no badge. The mark fades and a bell-off takes the
  // badge's corner, outlined in the background color so it stays its own
  // shape where it overlaps the mark.
  Text {
    id: mutedMark
    textFormat: Text.PlainText
    readonly property int size: Math.max(8, Math.round(Style.bar.iconCanvas * 0.6))
    readonly property int corner: Math.round(Style.bar.iconCanvas / 2 - 1)
    visible: root.muted && root.mutedIndicator === "Bell"
    z: 2
    text: "󰂛"
    color: root.foreground
    style: Text.Outline
    styleColor: root.badgeTextColor
    font.family: root.fontFamily
    font.pixelSize: size
    renderType: Text.NativeRendering
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: Math.min(corner, Math.max(0, Math.round((root.width - implicitWidth) / 2)))
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: Math.min(corner, Math.max(0, Math.round((root.height - implicitHeight) / 2)))
  }

  // A reaction's emoji: Slack's picture of it (animated when it is a GIF),
  // or its character. `size` is the font size it sits next to. A picture
  // that doesn't come gives way to the character (or :name:), and so does
  // one still loading when `textOnly` is set.
  component EmojiGlyph: Item {
    id: emojiGlyph

    property var visual: null
    property int size: Style.font.bodySmall
    property color color: root.foreground
    property bool textOnly: false
    readonly property bool hasImage: !!emojiGlyph.visual && String(emojiGlyph.visual.image || "").length > 0
    readonly property bool isAnimated: emojiGlyph.hasImage && emojiGlyph.visual.animated === true
    readonly property int imageStatus: emojiGlyph.isAnimated ? animatedPicture.status : picture.status
    // The picture is in, or it didn't come (nothing to wait for then).
    readonly property bool settled: !emojiGlyph.hasImage || emojiGlyph.imageStatus === Image.Ready
      || emojiGlyph.imageStatus === Image.Error
    readonly property bool isImage: emojiGlyph.hasImage && !emojiGlyph.textOnly && emojiGlyph.imageStatus !== Image.Error
    readonly property int box: Math.round(emojiGlyph.size * 1.25)

    implicitWidth: emojiGlyph.isImage ? emojiGlyph.box : emojiText.implicitWidth
    implicitHeight: emojiGlyph.isImage ? emojiGlyph.box : emojiText.implicitHeight
    width: implicitWidth
    height: implicitHeight

    AnimatedImage {
      id: animatedPicture
      anchors.fill: parent
      visible: emojiGlyph.isImage && emojiGlyph.isAnimated
      source: emojiGlyph.isAnimated ? emojiGlyph.visual.image : ""
      playing: visible
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    Image {
      id: picture
      anchors.fill: parent
      visible: emojiGlyph.isImage && !emojiGlyph.isAnimated
      source: emojiGlyph.hasImage && !emojiGlyph.isAnimated ? emojiGlyph.visual.image : ""
      sourceSize.width: Math.round(emojiGlyph.box * Screen.devicePixelRatio)
      sourceSize.height: Math.round(emojiGlyph.box * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectFit
      smooth: true
      asynchronous: true
    }

    Text {
      id: emojiText
      anchors.centerIn: parent
      visible: !emojiGlyph.isImage
      text: emojiGlyph.visual && !emojiGlyph.isImage ? String(emojiGlyph.visual.text || "") : ""
      textFormat: Text.PlainText
      color: emojiGlyph.color
      font.family: root.fontFamily
      font.pixelSize: emojiGlyph.size
    }
  }

  // ------------------------------------------------------- reaction bubbles
  //
  // The bar's own surface is only as tall as the bar, so the bubbles fly in a
  // popup of their own anchored to it: transparent, with an empty input mask
  // so it never takes a click, and shown only while one is in the air. It
  // starts on the icon and runs away from the screen edge the bar sits on.
  property int floatingReactions: 0

  function floatReaction(visual, index) {
    var bubble = bubbleComponent.createObject(bubbleLayer, { visual: visual, delay: index * 220 })
    if (bubble) root.floatingReactions += 1
  }

  PopupWindow {
    id: bubbles

    readonly property string edge: root.bar ? String(root.bar.position || "top") : "top"
    readonly property bool horizontal: bubbles.edge === "left" || bubbles.edge === "right"
    // -1: away from a bottom or right bar, toward smaller coordinates.
    readonly property int direction: bubbles.edge === "bottom" || bubbles.edge === "right" ? -1 : 1
    readonly property int size: Math.round(Math.max(18, Style.bar.iconCanvas * 1.35))
    readonly property int pad: Math.round(bubbles.size * 0.25)
    readonly property int travel: Math.round(root.barSize / 2 + Style.space(34))
    readonly property int along: bubbles.travel + bubbles.size + bubbles.pad * 2
    readonly property int across: bubbles.size * 2
    readonly property int start: bubbles.direction < 0 ? bubbles.along - bubbles.size - bubbles.pad : bubbles.pad

    visible: root.floatingReactions > 0
    color: "transparent"
    implicitWidth: bubbles.horizontal ? bubbles.along : bubbles.across
    implicitHeight: bubbles.horizontal ? bubbles.across : bubbles.along
    mask: Region {}

    anchor {
      id: bubbleAnchor
      window: root.QsWindow.window
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      // The bubble's first position sits on the icon's centre.
      onAnchoring: {
        var window = root.QsWindow.window
        if (!window) return
        var center = window.contentItem.mapFromItem(root, root.width / 2, root.height / 2)
        var offset = bubbles.start + bubbles.size / 2
        bubbleAnchor.rect.x = Math.round(bubbles.horizontal ? center.x - offset : center.x - bubbles.across / 2)
        bubbleAnchor.rect.y = Math.round(bubbles.horizontal ? center.y - bubbles.across / 2 : center.y - offset)
      }
    }

    Item {
      id: bubbleLayer
      anchors.fill: parent
    }
  }

  Component {
    id: bubbleComponent

    Item {
      id: bubble

      property var visual: null
      property int delay: 0
      readonly property real from: bubbles.start
      readonly property real to: bubbles.start + bubbles.direction * bubbles.travel
      // Slack's picture comes over the network: the bubble rises once it
      // is in (or didn't come), and after a couple of seconds as the
      // character (or :name:) instead, so it never flies empty.
      property bool gaveUp: false
      readonly property bool ready: bubbleGlyph.settled || bubble.gaveUp

      width: bubbles.size
      height: bubbles.size
      x: bubbles.horizontal ? bubble.from : (bubbles.across - bubbles.size) / 2
      y: bubbles.horizontal ? (bubbles.across - bubbles.size) / 2 : bubble.from
      opacity: 0
      scale: 0.8

      EmojiGlyph {
        id: bubbleGlyph
        anchors.centerIn: parent
        visual: bubble.visual
        size: Math.round(bubbles.size / 1.25)
        textOnly: bubble.gaveUp
      }

      Timer {
        interval: 2500
        running: !bubbleGlyph.settled
        onTriggered: bubble.gaveUp = true
      }

      SequentialAnimation {
        running: bubble.ready
        PauseAnimation { duration: bubble.delay }
        PropertyAction { target: bubble; property: "opacity"; value: 1 }
        ParallelAnimation {
          NumberAnimation {
            target: bubble
            property: bubbles.horizontal ? "x" : "y"
            to: bubble.to
            duration: 1400
            easing.type: Easing.OutCubic
          }
          NumberAnimation {
            target: bubble
            property: "scale"
            to: 1.35
            duration: 1400
            easing.type: Easing.OutCubic
          }
          NumberAnimation {
            target: bubble
            property: "opacity"
            to: 0
            duration: 1400
            easing.type: Easing.InQuad
          }
        }
        onFinished: {
          root.floatingReactions = Math.max(0, root.floatingReactions - 1)
          bubble.destroy()
        }
      }
    }
  }

  // ----------------------------------------------------------- preview card
  FontMetrics {
    id: messageMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // A word of a message in the preview (see Bar.messageTokens).
  Component {
    id: messageWord

    Text {
      text: parent ? parent.token.html : ""
      textFormat: Text.StyledText
      color: Qt.darker(popup.fg, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // An emoji in a message: Slack's picture of it, the workspace's own
  // animated when it is a GIF.
  Component {
    id: messageEmoji

    AnimatedImage {
      readonly property int box: Math.round(messageMetrics.height * 1.1)
      width: box
      height: messageMetrics.height
      source: parent ? parent.token.src : ""
      playing: parent ? parent.token.animated : false
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: true
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    triggerMode: "hover"
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(root.notSignedIn ? signInColumn.implicitHeight
                                                              : previewColumn.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.6)
    // Several workspaces: each row says which one it is from.
    readonly property bool manyTeams: !!root.service && root.service.workspaces.length > 1

    // Signed out: what is missing and the way to it.
    Column {
      id: signInColumn
      anchors.fill: parent
      spacing: Style.space(8)
      visible: root.notSignedIn

      Text {
        textFormat: Text.PlainText
        text: root.tr("Not signed in", "Sem sessão")
        color: popup.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.tr("Sign in to a Slack workspace and what waits there shows up here.",
                      "Entre num workspace do Slack e o que estiver esperando aparece aqui.")
        color: popup.dim
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        text: root.tr("Sign in", "Entrar")
        color: signInArea.containsMouse ? popup.fg : popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.underline: true

        MouseArea {
          id: signInArea
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.popupOpen = false
            if (root.service) root.service.showWindow()
          }
        }
      }
    }

    Column {
      id: previewColumn
      anchors.fill: parent
      spacing: Style.space(6)
      visible: !root.notSignedIn

      Row {
        width: parent.width
        spacing: Style.space(6)

        Image {
          id: headerMark
          readonly property int box: Math.round(Style.font.bodySmall * 1.2)
          width: box
          height: box
          anchors.verticalCenter: parent.verticalCenter
          source: root.colorIconSource
          sourceSize.width: Math.round(box * Screen.devicePixelRatio)
          sourceSize.height: Math.round(box * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          smooth: true
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width - headerMark.width - parent.spacing
          // A workspace's socket down: reconnecting, the counts are the last
          // known.
          text: {
            var team = root.slackState && root.slackState.team ? root.slackState.team : "Slack"
            return (root.attention > 0 ? team + " · " + root.attention + root.tr(" waiting", " aguardando") : team)
              + (root.slackState && root.slackState.connecting ? root.tr(" · connecting…", " · conectando…") : "")
          }
          color: popup.fg
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      // Paused (or in Slack's scheduled DND): when it ends, and a way out.
      Row {
        visible: root.dndActive
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "󰂛"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: root.pauseLabel + " ·"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: root.tr("Resume", "Retomar")
          color: popup.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.underline: resumeArea.containsMouse

          MouseArea {
            id: resumeArea
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resume()
          }
        }
      }

      PanelSeparator {
        foreground: popup.fg
      }

      Text {
        textFormat: Text.PlainText
        visible: root.preview.rows.length === 0
        text: root.totals.channelsQuiet > 0 && !root.previewChannels
          ? (root.totals.quietKnown ? root.tr("Nothing that notifies you", "Nada que notifique você")
                                    : root.tr("No unread DMs or mentions", "Nenhuma DM ou menção não lida"))
          : root.threads.rows.length > 0 ? root.tr("No unread conversations", "Nenhuma conversa não lida")
                                         : root.tr("No unread messages", "Nenhuma mensagem não lida")
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.preview.rows

        Rectangle {
          id: convRow
          required property var modelData

          width: previewColumn.width
          height: convInner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: rowArea.containsMouse
            ? Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.08) : "transparent"

          readonly property int indent: Math.round(Style.font.bodySmall * 1.5)

          Column {
            id: convInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)

            Item {
              width: parent.width
              height: nameText.implicitHeight

              Text {
                id: kindText
                textFormat: Text.PlainText
                width: convRow.indent
                text: convRow.modelData.glyph
                color: convRow.modelData.kind === "dm" || convRow.modelData.kind === "group"
                  ? root.directColor : root.channelColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.left: parent.left
                anchors.baseline: nameText.baseline
              }

              Text {
                id: nameText
                textFormat: Text.PlainText
                text: convRow.modelData.name
                color: popup.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                anchors.left: kindText.right
                anchors.right: marker.left
                anchors.rightMargin: Style.space(8)
              }

              // Mention count as a pill; a plain unread conversation gets a dot.
              Rectangle {
                id: marker
                readonly property bool hasCount: convRow.modelData.mentions > 0
                visible: hasCount || convRow.modelData.unread
                width: hasCount ? Math.max(height, mentionText.implicitWidth + Style.space(8))
                                : Math.round(Style.font.bodySmall * 0.45)
                height: hasCount ? mentionText.implicitHeight + Style.space(2)
                                 : width
                radius: height / 2
                readonly property bool direct: convRow.modelData.kind === "dm" || convRow.modelData.kind === "group"
                color: direct ? root.directColor : hasCount ? root.channelColor : popup.dim
                anchors.right: timeText.left
                anchors.rightMargin: timeText.text !== "" ? Style.space(8) : 0
                anchors.verticalCenter: nameText.verticalCenter

                CountText {
                  id: mentionText
                  visible: marker.hasCount
                  text: Bar.badgeLabel(convRow.modelData.mentions)
                  color: root.badgeDigitColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                id: timeText
                textFormat: Text.PlainText
                text: (popup.manyTeams ? convRow.modelData.teamName + " · " : "")
                  + Bar.relativeTime(convRow.modelData.latest, root.nowSec, root.lang)
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.baseline: nameText.baseline
              }
            }

            // Every unread message, up to two lines each, word by word so the
            // workspace's emoji (GIFs animated) sit inline. Words come from
            // Bar.messageTokens: escaped, with only bold, italic and
            // strikethrough as markup, and images only for emoji.
            Column {
              visible: convRow.modelData.messages.length > 0
              x: convRow.indent
              width: convInner.width - x
              spacing: Style.space(2)

              Repeater {
                model: convRow.modelData.messages

                Flow {
                  id: messageFlow
                  required property var modelData
                  width: parent.width
                  height: Math.min(implicitHeight, Math.ceil(messageMetrics.height * 2))
                  clip: true

                  Repeater {
                    model: messageFlow.modelData.tokens

                    Loader {
                      required property var modelData
                      readonly property var token: modelData
                      sourceComponent: modelData.kind === "img" ? messageEmoji : messageWord
                    }
                  }
                }
              }
            }
          }

          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openConversation(convRow.modelData)
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.preview.hidden > 0
        text: "+" + root.preview.hidden + root.tr(" more", " mais")
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Threads you follow with new replies, newest activity first: where,
      // the thread's first message, and its latest reply. A click opens the
      // thread at that reply.
      PanelSeparator {
        visible: root.threads.rows.length > 0
        foreground: popup.fg
      }

      PanelSectionHeader {
        visible: root.threads.rows.length > 0
        text: root.tr("Threads", "Conversas")
        foreground: popup.fg
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.threads.rows

        Rectangle {
          id: threadRow
          required property var modelData

          width: previewColumn.width
          height: threadInner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: threadArea.containsMouse
            ? Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.08) : "transparent"

          readonly property int indent: Math.round(Style.font.bodySmall * 1.5)

          Column {
            id: threadInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)

            Item {
              width: parent.width
              height: threadName.implicitHeight

              Text {
                id: threadKind
                textFormat: Text.PlainText
                width: threadRow.indent
                text: threadRow.modelData.glyph
                color: threadRow.modelData.mention ? root.directColor : root.channelColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.left: parent.left
                anchors.baseline: threadName.baseline
              }

              Text {
                id: threadName
                textFormat: Text.PlainText
                text: threadRow.modelData.name
                color: popup.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                anchors.left: threadKind.right
                anchors.right: threadMarker.left
                anchors.rightMargin: Style.space(8)
              }

              // New replies as a pill: red when one mentions you, blue
              // otherwise, the badges' colors.
              Rectangle {
                id: threadMarker
                readonly property bool hasCount: threadRow.modelData.count > 0
                width: hasCount ? Math.max(height, threadCount.implicitWidth + Style.space(8))
                                : Math.round(Style.font.bodySmall * 0.45)
                height: hasCount ? threadCount.implicitHeight + Style.space(2) : width
                radius: height / 2
                color: threadRow.modelData.mention ? root.directColor : root.channelColor
                anchors.right: threadTime.left
                anchors.rightMargin: threadTime.text !== "" ? Style.space(8) : 0
                anchors.verticalCenter: threadName.verticalCenter

                CountText {
                  id: threadCount
                  visible: threadMarker.hasCount
                  text: Bar.badgeLabel(threadRow.modelData.count)
                  color: root.badgeDigitColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                id: threadTime
                textFormat: Text.PlainText
                text: (popup.manyTeams ? threadRow.modelData.teamName + " · " : "")
                  + Bar.relativeTime(threadRow.modelData.latest, root.nowSec, root.lang)
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.baseline: threadName.baseline
              }
            }

            // The thread's first message, one line.
            Text {
              visible: text !== ""
              text: threadRow.modelData.root
              textFormat: Text.PlainText
              x: threadRow.indent
              width: threadInner.width - x
              color: popup.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            // Its latest new reply, up to two lines, word by word like the
            // conversations' messages.
            Flow {
              id: replyFlow
              visible: threadRow.modelData.reply.length > 0
              x: threadRow.indent
              width: threadInner.width - x
              height: visible ? Math.min(implicitHeight, Math.ceil(messageMetrics.height * 2)) : 0
              clip: true

              Repeater {
                model: threadRow.modelData.reply

                Loader {
                  required property var modelData
                  readonly property var token: modelData
                  sourceComponent: modelData.kind === "img" ? messageEmoji : messageWord
                }
              }
            }
          }

          MouseArea {
            id: threadArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openConversation(threadRow.modelData)
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.threads.hidden > 0
        text: "+" + root.threads.hidden + (root.threads.hidden === 1 ? root.tr(" more thread", " conversa a mais")
                                                                      : root.tr(" more threads", " conversas a mais"))
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Muted or mentions-only channels with unread messages: counted, not
      // listed. After the threads, so those come first.
      Text {
        textFormat: Text.PlainText
        readonly property int quiet: root.previewChannels ? 0 : root.totals.channelsQuiet
        visible: quiet > 0
        text: root.totals.quietKnown
          ? "+" + quiet + (quiet === 1 ? root.tr(" muted or mentions-only channel unread", " canal silenciado ou só de menções não lido")
                                       : root.tr(" muted or mentions-only channels unread", " canais silenciados ou só de menções não lidos"))
          : "+" + quiet + (quiet === 1 ? root.tr(" channel with unread messages, no mentions", " canal com mensagens não lidas, sem menções")
                                       : root.tr(" channels with unread messages, no mentions", " canais com mensagens não lidas, sem menções"))
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Reactions other people put on your messages, newest first, after the
      // unread conversations. A click jumps to the message.
      PanelSeparator {
        visible: root.reactions.rows.length > 0
        foreground: popup.fg
      }

      PanelSectionHeader {
        visible: root.reactions.rows.length > 0
        text: root.tr("Reactions", "Reações")
        foreground: popup.fg
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.reactions.rows

        Rectangle {
          id: reactionRow
          required property var modelData

          width: previewColumn.width
          height: reactionInner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: reactionArea.containsMouse
            ? Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.08) : "transparent"

          readonly property int indent: Math.round(Style.font.bodySmall * 1.5)

          Column {
            id: reactionInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)

            // "Ana reacted 🎉 to your message": the name gives way first, so
            // the emoji always shows.
            Item {
              width: parent.width
              height: Math.max(reactionLead.implicitHeight, reactionEmoji.height)

              Text {
                id: reactionKind
                textFormat: Text.PlainText
                width: reactionRow.indent
                text: reactionRow.modelData.glyph
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.left: parent.left
                anchors.baseline: reactionLead.baseline
              }

              Text {
                id: reactionLead
                readonly property real room: parent.width - reactionKind.width - reactionTime.width
                  - reactionEmoji.width - Style.space(56)
                width: Math.max(0, Math.min(implicitWidth, room))
                text: reactionRow.modelData.who + root.tr(" reacted", " reagiu com")
                textFormat: Text.PlainText
                color: popup.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                anchors.left: reactionKind.right
                anchors.verticalCenter: parent.verticalCenter
              }

              EmojiGlyph {
                id: reactionEmoji
                visual: reactionRow.modelData.emoji
                size: Style.font.bodySmall
                color: popup.fg
                anchors.left: reactionLead.right
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: reactionLead.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: root.tr("to your message", "à sua mensagem")
                color: popup.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                anchors.left: reactionEmoji.right
                anchors.leftMargin: Style.space(4)
                anchors.right: reactionTime.left
                anchors.rightMargin: Style.space(8)
                anchors.baseline: reactionLead.baseline
              }

              Text {
                id: reactionTime
                textFormat: Text.PlainText
                text: Bar.relativeTime(reactionRow.modelData.latest, root.nowSec, root.lang)
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.baseline: reactionLead.baseline
              }
            }

            Text {
              visible: text !== ""
              text: reactionRow.modelData.line
              textFormat: Text.PlainText
              x: reactionRow.indent
              width: reactionInner.width - x
              color: popup.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: reactionArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openConversation(reactionRow.modelData)
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.reactions.hidden > 0
        text: "+" + root.reactions.hidden + (root.reactions.hidden === 1 ? root.tr(" more reaction", " reação a mais")
                                                                          : root.tr(" more reactions", " reações a mais"))
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ------------------------------------------------------------------- menu
  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(220))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property var s: root.service
    readonly property var cur: menu.s ? menu.s.current : null

    component MenuEntry: Rectangle {
      id: entry

      property string label: ""
      property bool showCheck: false
      property bool checked: false
      property bool clickable: true
      property int indent: 0

      signal activated()

      width: menuColumn.width
      height: entryText.implicitHeight + Style.space(12)
      radius: Style.spacing.labelGap
      color: entry.clickable && entryArea.containsMouse && entry.enabled
        ? Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.08) : "transparent"
      opacity: !entry.enabled ? 0.4 : (entry.clickable ? 1 : 0.6)

      Text {
        id: entryText
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8) + entry.indent
        anchors.verticalCenter: parent.verticalCenter
        text: entry.label
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        visible: entry.showCheck
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: entry.checked ? "✓" : ""
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: entryArea
        anchors.fill: parent
        enabled: entry.clickable
        hoverEnabled: true
        cursorShape: entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: entry.activated()
      }
    }

    // ‹ value ›, for the pause picker. Clicks on the chevrons or the wheel
    // over it step the value.
    component Stepper: Item {
      id: stepper

      property string label: ""
      property int valueWidth: 0
      property bool canBack: true
      property bool canForward: true

      signal stepped(int delta)

      implicitWidth: backChevron.implicitWidth + stepper.valueWidth + forwardChevron.implicitWidth + Style.space(8)
      implicitHeight: valueText.implicitHeight + Style.space(8)

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
          if (event.angleDelta.y > 0 && stepper.canForward) stepper.stepped(1)
          else if (event.angleDelta.y < 0 && stepper.canBack) stepper.stepped(-1)
        }
      }

      Text {
        id: backChevron
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅁"
        color: menu.fg
        opacity: !stepper.canBack ? 0.25 : backArea.containsMouse ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall

        MouseArea {
          id: backArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          enabled: stepper.canBack
          cursorShape: Qt.PointingHandCursor
          onClicked: stepper.stepped(-1)
        }
      }

      Text {
        id: valueText
        textFormat: Text.PlainText
        anchors.left: backChevron.right
        anchors.right: forwardChevron.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: stepper.label
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        id: forwardChevron
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅂"
        color: menu.fg
        opacity: !stepper.canForward ? 0.25 : forwardArea.containsMouse ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall

        MouseArea {
          id: forwardArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          enabled: stepper.canForward
          cursorShape: Qt.PointingHandCursor
          onClicked: stepper.stepped(1)
        }
      }
    }

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(2)

      // Signed out: only the way in.
      MenuEntry {
        visible: root.notSignedIn
        label: root.tr("Sign in to Slack…", "Entrar no Slack…")
        onActivated: {
          root.close()
          if (menu.s) menu.s.showWindow()
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: !root.notSignedIn

        MenuEntry {
          label: !root.running ? root.tr("Open Slack", "Abrir o Slack")
            : root.parked && !root.specialShown ? root.tr("Show Slack", "Mostrar o Slack")
            : (root.focused && root.hideMode === "Special workspace") ? root.tr("Hide Slack", "Esconder o Slack")
            : root.tr("Focus Slack", "Focar o Slack")
          onActivated: {
            root.close()
            root.toggle()
          }
        }

        PanelSeparator { foreground: menu.fg }

        // Closed before the write: saving shell.json can rebuild the bar's
        // widgets, and a menu owned by a destroyed widget dies mid-click.
        MenuEntry {
          label: root.tr("Launch on Login", "Abrir ao iniciar a sessão")
          showCheck: true
          checked: root.autoStart
          onActivated: {
            root.close()
            root.writeSetting("autoStart", !root.autoStart)
          }
        }

        MenuEntry {
          label: root.tr("Launch in Foreground", "Abrir em primeiro plano")
          showCheck: true
          checked: root.launchForeground
          onActivated: {
            root.close()
            root.writeSetting("launchForeground", !root.launchForeground)
          }
        }

        MenuEntry {
          label: root.tr("Open in Scratchpad", "Abrir no scratchpad")
          showCheck: true
          checked: root.openInSpecial
          onActivated: {
            root.close()
            root.writeSetting("openInSpecial", !root.openInSpecial)
          }
        }

        MenuEntry {
          label: root.tr("Group notifications", "Agrupar notificações")
          showCheck: true
          checked: root.combinedBadge
          onActivated: {
            root.close()
            root.writeSetting("badgeLayout", root.combinedBadge ? "Split" : "Combined")
          }
        }

        MenuEntry {
          label: root.tr("Channel mentions only", "Só menções nos canais")
          showCheck: true
          checked: root.channelMentionsOnly
          onActivated: {
            root.close()
            root.writeSetting("channelMentionsOnly", !root.channelMentionsOnly)
          }
        }

        MenuEntry {
          label: root.tr("Show threads", "Mostrar conversas")
          showCheck: true
          checked: root.showThreads
          onActivated: {
            root.close()
            root.writeSetting("showThreads", !root.showThreads)
          }
        }

        MenuEntry {
          label: root.tr("Show reactions", "Mostrar reações")
          showCheck: true
          checked: root.showReactions
          onActivated: {
            root.close()
            root.writeSetting("showReactions", !root.showReactions)
          }
        }

        // The bar's setting, which the app's Preferences switch also writes.
        MenuEntry {
          label: root.tr("Desktop notifications", "Notificações na área de trabalho")
          showCheck: true
          checked: root.desktopNotifications
          onActivated: {
            root.close()
            if (menu.s) menu.s.setNotifySetting("notifications", !root.desktopNotifications)
            else root.writeSetting("notifications", !root.desktopNotifications)
          }
        }

        PanelSeparator { foreground: menu.fg }

        MenuEntry {
          visible: root.dndActive
          label: root.tr("Resume notifications", "Retomar notificações")
          onActivated: {
            root.close()
            root.resume()
          }
        }

        MenuEntry {
          label: root.tr("Pause notifications", "Pausar notificações")
          clickable: false
        }

        Repeater {
          model: [
            { label: root.tr("30 minutes", "30 minutos"), minutes: 30 },
            { label: root.tr("1 hour", "1 hora"), minutes: 60 },
            { label: root.tr("2 hours", "2 horas"), minutes: 120 },
            { label: root.tr("Until tomorrow", "Até amanhã"), minutes: -1 },
          ]

          MenuEntry {
            required property var modelData
            label: modelData.label
            indent: Style.space(10)
            onActivated: {
              root.close()
              root.pause(modelData.minutes > 0 ? modelData.minutes
                                               : Bar.minutesUntilTomorrow(Date.now() / 1000))
            }
          }
        }

        MenuEntry {
          label: root.tr("Until a date and time…", "Até uma data e hora…")
          indent: Style.space(10)
          onActivated: {
            if (!root.pickerOpen) root.resetPicker()
            root.pickerOpen = !root.pickerOpen
          }
        }

        // The picker: a day, an hour and a minute, then the pause itself,
        // labelled with when it would end.
        Column {
          visible: root.pickerOpen
          width: parent.width
          spacing: Style.space(2)

          Stepper {
            x: Style.space(18)
            width: parent.width - x - Style.space(8)
            label: Bar.pickerDayLabel(root.pickerDay, root.nowSec, root.lang)
            canBack: root.pickerDay > 0
            canForward: root.pickerDay < root.pickerMaxDays
            onStepped: function (delta) { root.stepPickerDay(delta) }
          }

          Row {
            x: Style.space(18)
            spacing: Style.space(4)

            Stepper {
              valueWidth: Math.round(Style.font.bodySmall * 2)
              label: Bar.pad(root.pickerHour)
              onStepped: function (delta) { root.stepPickerHour(delta) }
            }
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: ":"
              color: menu.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Stepper {
              valueWidth: Math.round(Style.font.bodySmall * 2)
              label: Bar.pad(root.pickerMinute)
              onStepped: function (delta) { root.stepPickerMinute(delta) }
            }
          }

          MenuEntry {
            indent: Style.space(10)
            enabled: root.pickerValid
            label: root.pickerValid
              ? root.tr("Pause until ", "Pausar até ") + Bar.clockLabel(root.pickerTarget, root.nowSec, root.lang, root.clock24)
              : root.tr("Pick a time in the future", "Escolha um horário no futuro")
            onActivated: root.pauseUntilPicked()
          }
        }

        PanelSeparator { foreground: menu.fg }

        // The app's own: presence, status, read state, preferences.
        MenuEntry {
          label: menu.cur && menu.cur.away ? root.tr("Set yourself as active", "Ficar ativo")
                                           : root.tr("Set yourself as away", "Ficar ausente")
          onActivated: {
            root.close()
            var away = !(menu.cur && menu.cur.away)
            if (menu.s) menu.s.workspaces.forEach(function(w) { w.setAway(away) })
          }
        }

        MenuEntry {
          label: root.tr("Set a status…", "Definir um status…")
          onActivated: {
            root.close()
            if (menu.s) menu.s.openDialog("status")
          }
        }

        MenuEntry {
          label: root.tr("Mark all as read", "Marcar tudo como lido")
          onActivated: {
            root.close()
            if (menu.s) menu.s.workspaces.forEach(function(w) { w.markAllRead() })
          }
        }

        MenuEntry {
          label: root.tr("Preferences…", "Preferências…")
          onActivated: {
            root.close()
            if (menu.s) menu.s.openDialog("preferences")
          }
        }

        PanelSeparator { foreground: menu.fg }

        MenuEntry {
          label: root.tr("Close Slack", "Fechar o Slack")
          enabled: root.running
          onActivated: {
            root.close()
            root.quit()
          }
        }
      }
    }
  }
}
