import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Slack's surfaces in the Omarchy theme's colors. The base palette is the
// shell's own (it follows theme switches live); the theme's colors.toml adds
// the named colors (green for presence, yellow for mentions of you, blue for
// links…). Sizes follow the shell's type scale and the app's zoom.
QtObject {
  id: t

  property real zoom: 1.0
  property var pal: ({})

  function mix(a, b, f) {
    return Qt.rgba(a.r * (1 - f) + b.r * f, a.g * (1 - f) + b.g * f, a.b * (1 - f) + b.b * f, a.a * (1 - f) + b.a * f)
  }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function hex(c) {
    function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }
  function pick(key, fallback) { var v = t.pal[key]; return v ? v : fallback }
  function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function onColor(c) { return t.luma(c) > 0.55 ? "#1a1d21" : "#ffffff" }

  // ---------------------------------------------------------------- palette
  readonly property color bg: Color.background
  readonly property color fg: Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property bool dark: luma(bg) < 0.5

  readonly property color bgDark: pick("dark_background", Qt.darker(bg, 1.18))
  readonly property color bgDarker: pick("darker_background", Qt.darker(bg, 1.4))
  readonly property color bgLight: pick("lighter_background", dark ? Qt.lighter(bg, 1.35) : Qt.darker(bg, 1.05))
  readonly property color fgDim: pick("dark_foreground", mix(fg, bg, 0.45))
  readonly property color fgSoft: pick("light_foreground", mix(fg, bg, 0.18))
  readonly property color fgBright: pick("bright_foreground", fg)
  readonly property color red: pick("red", pick("color1", urgent))
  readonly property color green: pick("green", pick("color2", "#2bac76"))
  readonly property color yellow: pick("yellow", pick("color3", "#e8a33d"))
  readonly property color blue: pick("blue", pick("color4", "#1d9bd1"))
  readonly property color magenta: pick("magenta", pick("color5", "#a9829f"))
  readonly property color cyan: pick("cyan", pick("color6", "#7fa98a"))
  readonly property color orange: pick("orange", pick("bright_red", "#e8912d"))

  // ---------------------------------------------------------------- surfaces
  // Slack: an aubergine frame (rail + top bar), a tinted sidebar and the
  // message pane. Here the frame is the theme's deepest tone with a breath
  // of its accent, so every theme gets its own "aubergine".
  readonly property color frame: mix(bgDarker, accent, dark ? 0.07 : 0.10)
  readonly property color sidebar: mix(bgDark, accent, dark ? 0.045 : 0.06)
  readonly property color pane: bg
  readonly property color raised: bgLight
  // Cards and menus float over the window's own content: opaque, a step
  // above the pane (the shell's popup alpha is meant for the desktop).
  readonly property color popup: mix(bgLight, bg, 0.25)
  readonly property color line: alpha(fg, 0.10)
  readonly property color lineStrong: alpha(fg, 0.17)
  readonly property color hover: alpha(fg, 0.055)
  readonly property color hoverStrong: alpha(fg, 0.10)
  readonly property color press: alpha(fg, 0.14)
  readonly property color scrim: alpha(bgDarker, 0.55)

  // The accent fill of a chosen tile, chip or menu item, and its text.
  readonly property color selected: accent
  readonly property color selectedText: onColor(accent)
  // Slack's open item of a list (the sidebar's current conversation): a
  // neutral veil of the text color, clearly above hover and press, with the
  // text kept bright.
  readonly property color rowSelected: alpha(fg, 0.15)
  readonly property color rowSelectedText: fgBright
  readonly property color unreadText: fgBright
  readonly property color readText: alpha(fg, 0.68)
  readonly property color badge: red
  readonly property color badgeText: onColor(red)
  readonly property color link: blue
  readonly property color mention: blue
  readonly property color mentionBg: alpha(blue, 0.16)
  readonly property color meText: yellow
  readonly property color meBg: alpha(yellow, 0.22)
  readonly property color mentionRow: alpha(yellow, 0.07)
  readonly property color code: orange
  readonly property color codeBg: alpha(fg, 0.065)
  readonly property color codeBorder: alpha(fg, 0.14)
  readonly property color presence: green
  readonly property color flash: alpha(yellow, 0.16)
  readonly property color newLine: red
  readonly property color threadBlue: blue

  // Colors as strings, for the rich text the renderer writes.
  readonly property var html: ({
    link: hex(link), mention: hex(mention), mentionBg: "rgba(" + Math.round(blue.r * 255) + "," + Math.round(blue.g * 255) + "," + Math.round(blue.b * 255) + ",0.18)",
    meText: hex(yellow), meBg: "rgba(" + Math.round(yellow.r * 255) + "," + Math.round(yellow.g * 255) + "," + Math.round(yellow.b * 255) + ",0.24)",
    code: hex(code), codeBg: hex(mix(bg, fg, 0.08)), dim: hex(fgDim), text: hex(fg)
  })

  // ---------------------------------------------------------------- type
  readonly property string font: Style.font.family
  readonly property int base: Style.font.baseSize
  function px(n) { return Math.max(8, Math.round(n * t.zoom * (t.base / 12))) }
  readonly property int fsText: px(14)
  readonly property int fsSmall: px(12)
  readonly property int fsTiny: px(11)
  readonly property int fsSidebar: px(14)
  readonly property int fsName: px(14)
  readonly property int fsTitle: px(16)
  readonly property int fsHeader: px(18)
  readonly property int fsHuge: px(24)
  readonly property int fsIcon: px(15)
  readonly property int emojiPx: px(18)

  // ---------------------------------------------------------------- shape
  readonly property int radius: Style.cornerRadius
  readonly property int radiusSmall: Math.min(Style.cornerRadius, 6)
  readonly property int radiusCard: Math.max(4, Math.min(Style.cornerRadius, 10))
  function sp(n) { return Math.round(n * t.zoom) }
  readonly property int avatar: sp(36)
  readonly property int avatarSmall: sp(20)
  readonly property var popupBorder: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))

  // ---------------------------------------------------------------- the theme file
  readonly property string themeDir: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme"

  property FileView paletteFile: FileView {
    path: t.themeDir + "/colors.toml"
    printErrors: false
    onLoaded: t.parsePalette(text())
    onLoadFailed: t.pal = ({})
  }

  function parsePalette(raw) {
    var out = {}
    String(raw || "").split("\n").forEach(function(line) {
      var m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) out[m[1]] = m[2]
    })
    t.pal = out
  }

  // A theme switch pushes new colors into the shell: read the file again.
  property Connections themeWatch: Connections {
    target: Color
    function onBackgroundChanged() { t.paletteFile.reload() }
    function onAccentChanged() { t.paletteFile.reload() }
  }
}
