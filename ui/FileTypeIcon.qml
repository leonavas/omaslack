import QtQuick
import QtQuick.Shapes
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A file's type as Slack's Files draws it: a rounded square in the type's
// color with its mark (a canvas, Acrobat's ribbon for PDFs, X for Excel and
// CSV, a grid for Google Sheets, P for PowerPoint), or a neutral one with
// the file's glyph. The colors are the theme's.
Rectangle {
  id: fi
  property var app: Reg.service
  readonly property var t: app.theme
  property var file: null
  property int size: t.sp(36)
  readonly property string kind: file ? (file.kind || U.fileKind(file)) : "other"
  readonly property var look: {
    var t = fi.t
    switch (fi.kind) {
    case "canvas": return { bg: Qt.tint(t.blue, Qt.rgba(1, 1, 1, 0.3)), glyph: "󰈙", letter: "" }
    case "pdf": return { bg: t.mix(t.red, t.magenta, 0.2), glyph: "", letter: "" }
    case "excel": return { bg: t.green, glyph: "", letter: "X" }
    case "sheet": return { bg: t.green, glyph: "󰋁", letter: "" }
    case "ppt": return { bg: t.orange, glyph: "", letter: "P" }
    case "slides": return { bg: t.yellow, glyph: "󰐨", letter: "" }
    case "word": return { bg: t.blue, glyph: "", letter: "W" }
    case "gdoc": return { bg: t.blue, glyph: "󰈙", letter: "" }
    case "list": return { bg: t.magenta, glyph: "󰝖", letter: "" }
    }
    return { bg: t.alpha(t.fg, 0.10), glyph: U.fileIcon(fi.file), letter: "", neutral: true }
  }
  readonly property color ink: look.neutral ? t.fgSoft : t.onColor(look.bg)
  width: size
  height: size
  radius: Math.max(4, Math.round(size * 0.24))
  color: look.bg

  Glyph {
    app: fi.app
    visible: fi.look.glyph !== ""
    anchors.centerIn: parent
    icon: fi.look.glyph
    size: Math.round(fi.size * 0.56)
    color: fi.ink
  }
  Text {
    visible: fi.look.letter !== ""
    anchors.centerIn: parent
    text: fi.look.letter
    color: fi.ink
    font.family: fi.t.font
    font.pixelSize: Math.round(fi.size * 0.5)
    font.bold: true
  }
  // Acrobat's ribbon, drawn (no font has it), on a 24-unit grid.
  Shape {
    visible: fi.kind === "pdf"
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: fi.size * 0.79 / 24
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: fi.ink
      strokeWidth: 1.9
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: "M11.2 3.2 C9.6 3.2 9.8 6.6 12.1 11.2 C14.6 16 18.4 19.2 20.3 18.4 C21.9 17.7 19.2 15.4 12.6 16.2 C6.4 17 3.4 20.8 4.6 21.4 C6 22.1 9.6 16.4 11.3 11.4 C12.6 7.4 12.8 3.2 11.2 3.2 Z" }
    }
  }
}
