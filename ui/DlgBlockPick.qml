import QtQuick
import "../lib/Util.js" as U

// What an app's select or picker asks for (Block Kit), picked here instead
// of on Slack's web page: a person, a conversation or a channel (one or
// several), a date on a month's calendar, a time, or both.
// args: {kind: users | conversations | channels | date | time | datetime,
//        multi, title, date ("YYYY-MM-DD"), time ("HH:MM"), onPick(value)}
// value: [ids] for the lists; "YYYY-MM-DD"; "HH:MM"; epoch seconds.
DialogFrame {
  id: d
  title: String(args.title || "") || (d.isList ? app.tr("Select", "Selecionar") : app.tr("Pick a date", "Escolha uma data"))
  cardWidth: t.sp(440)
  initialFocus: d.isList ? filter : (d.kind === "time" ? timeField : null)

  readonly property string kind: String(args.kind || "users")
  readonly property bool isList: ["users", "conversations", "channels"].indexOf(d.kind) >= 0
  readonly property bool hasDate: d.kind === "date" || d.kind === "datetime"
  readonly property bool hasTime: d.kind === "time" || d.kind === "datetime"
  property var chosen: []

  // ---------------------------------------------------------------- lists
  readonly property var entries: {
    if (!d.isList || !d.ws) return []
    var w = d.ws, out = []
    if (d.kind === "users") {
      for (var uid in w.users) {
        var u = w.users[uid]
        if (!u || u.deleted || uid === "USLACKBOT") continue
        out.push({ id: uid, label: u.name || u.real || uid, sub: u.real && u.real !== u.name ? u.real : "", user: uid, self: uid === w.me.id })
      }
    } else {
      var seen = {}
      for (var cid in w.convs) {
        var c = w.convs[cid]
        if (!c || c.archived) continue
        var chan = c.kind === "channel" || c.kind === "private"
        if (d.kind === "channels" && c.kind !== "channel") continue
        seen[cid] = true
        out.push({ id: cid, label: w.convLabel(cid), sub: "", user: c.kind === "im" ? (c.user || "") : "", glyph: c.kind === "private" ? "󰌾" : chan ? "#" : c.kind === "mpim" ? "󰡉" : "", self: false })
      }
      if (d.kind === "channels" || d.kind === "conversations")
        (w.directory.chans || []).forEach(function(x) { if (!seen[x.id] && !x.archived) out.push({ id: x.id, label: x.name, sub: "", user: "", glyph: "#", self: false }) })
    }
    return out
  }
  readonly property var shown: {
    var q = U.fold(filter.text).trim()
    var list = d.entries.filter(function(e) { return !q || U.fold(e.label + " " + e.sub).indexOf(q) >= 0 })
    list.sort(function(a, b) {
      if (q) {
        var sa = U.fold(a.label).indexOf(q) === 0, sb = U.fold(b.label).indexOf(q) === 0
        if (sa !== sb) return sa ? -1 : 1
      }
      if (a.self !== b.self) return a.self ? -1 : 1
      return a.label.localeCompare(b.label)
    })
    return list.slice(0, 200)
  }
  function toggle(id) {
    if (!d.args.multi) { d.done([id]); return }
    var c = d.chosen.slice(), i = c.indexOf(id)
    if (i >= 0) c.splice(i, 1); else c.push(id)
    d.chosen = c
  }

  // ---------------------------------------------------------------- date / time
  function ymd(dt) { return dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0") }
  property var day: {
    var m = String(d.args.date || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
    return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())
  }
  property var month: new Date(d.day.getFullYear(), d.day.getMonth(), 1)
  // "17:30", "1730", "17h30", "5pm" → minutes of the day; -1 if not a time.
  function parseTime(s) {
    var m = String(s).trim().toLowerCase().match(/^(\d{1,2})(?:[:h.]?(\d{2}))?\s*(?:(a|p)\.?\s*m?\.?)?$/)
    if (!m) return -1
    var h = Number(m[1]), mi = m[2] ? Number(m[2]) : 0
    if (mi > 59) return -1
    if (m[3]) { if (h < 1 || h > 12) return -1; h = h % 12 + (m[3] === "p" ? 12 : 0) }
    else if (h > 23) return -1
    return h * 60 + mi
  }
  readonly property int minutes: d.hasTime ? d.parseTime(timeField.text) : 0
  readonly property bool ready: d.isList ? d.chosen.length > 0 : (!d.hasTime || d.minutes >= 0)

  function done(value) {
    var f = d.args.onPick
    d.closed()
    if (f) f(value)
  }
  function confirm() {
    if (!d.ready) return
    if (d.isList) { d.done(d.chosen); return }
    var hm = String(Math.floor(d.minutes / 60)).padStart(2, "0") + ":" + String(d.minutes % 60).padStart(2, "0")
    if (d.kind === "date") d.done(d.ymd(d.day))
    else if (d.kind === "time") d.done(hm)
    else d.done(Math.floor(new Date(d.day.getFullYear(), d.day.getMonth(), d.day.getDate(), Math.floor(d.minutes / 60), d.minutes % 60).getTime() / 1000))
  }

  Column {
    width: parent.width
    spacing: d.t.sp(10)

    // A list to pick from, filtered as you type.
    SField {
      id: filter
      visible: d.isList
      app: d.app
      width: parent.width
      icon: "󰍉"
      placeholderText: d.kind === "users" ? d.app.tr("Search people", "Buscar pessoas") : d.app.tr("Search conversations", "Buscar conversas")
      onAccepted: if (d.shown.length) d.toggle(d.shown[0].id)
    }
    ListView {
      visible: d.isList
      width: parent.width
      height: Math.min(contentHeight, d.t.sp(320))
      clip: true
      model: d.shown
      boundsBehavior: Flickable.StopAtBounds
      delegate: Rectangle {
        required property var modelData
        width: ListView.view.width
        height: d.t.sp(36)
        radius: Math.max(4, d.t.radiusSmall)
        color: rowMa.containsMouse ? d.t.hover : "transparent"
        Row {
          x: d.t.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: d.t.sp(10)
          Avatar { visible: !!parent.parent.modelData.user; app: d.app; ws: d.ws; user: parent.parent.modelData.user; size: d.t.sp(24); anchors.verticalCenter: parent.verticalCenter }
          Text { visible: !parent.parent.modelData.user; width: d.t.sp(24); horizontalAlignment: Text.AlignHCenter; text: parent.parent.modelData.glyph || "#"; color: d.t.fgSoft; font.family: d.t.font; font.pixelSize: d.t.fsText; anchors.verticalCenter: parent.verticalCenter }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.modelData.label + (parent.parent.modelData.self ? d.app.tr(" (you)", " (você)") : "")
            textFormat: Text.PlainText
            color: d.t.fgBright
            font.family: d.t.font
            font.pixelSize: d.t.fsText
          }
          Text { anchors.verticalCenter: parent.verticalCenter; visible: parent.parent.modelData.sub !== ""; text: parent.parent.modelData.sub; textFormat: Text.PlainText; color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall }
        }
        Glyph { visible: d.chosen.indexOf(parent.modelData.id) >= 0; app: d.app; anchors.right: parent.right; anchors.rightMargin: d.t.sp(10); anchors.verticalCenter: parent.verticalCenter; icon: "󰄬"; size: d.t.fsText; color: d.t.accent }
        MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: d.toggle(parent.modelData.id) }
      }
    }
    Text {
      visible: d.isList && d.shown.length === 0
      text: d.app.tr("No matches", "Nenhum resultado")
      color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall
    }

    // A month: ‹ November 2026 ›, the weekdays, the days.
    Column {
      visible: d.hasDate
      width: parent.width
      spacing: d.t.sp(6)
      Item {
        width: parent.width
        height: d.t.sp(28)
        IconButton { app: d.app; anchors.left: parent.left; icon: "󰅁"; tip: d.app.tr("Previous month", "Mês anterior"); onClicked: d.month = new Date(d.month.getFullYear(), d.month.getMonth() - 1, 1) }
        Text {
          anchors.centerIn: parent
          text: { var s = d.month.toLocaleDateString(d.app.lang === "pt-BR" ? Qt.locale("pt_BR") : Qt.locale("en_US"), "MMMM yyyy"); return s.charAt(0).toUpperCase() + s.slice(1) }
          color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true
        }
        IconButton { app: d.app; anchors.right: parent.right; icon: "󰅂"; tip: d.app.tr("Next month", "Próximo mês"); onClicked: d.month = new Date(d.month.getFullYear(), d.month.getMonth() + 1, 1) }
      }
      Grid {
        id: cal
        columns: 7
        readonly property real cell: Math.floor(parent.width / 7)
        readonly property int lead: d.month.getDay()
        readonly property int days: new Date(d.month.getFullYear(), d.month.getMonth() + 1, 0).getDate()
        Repeater {
          model: d.app.lang === "pt-BR" ? ["D", "S", "T", "Q", "Q", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"]
          delegate: Text { required property var modelData; width: cal.cell; height: d.t.sp(22); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: modelData; color: d.t.fgDim; font.family: d.t.font; font.pixelSize: d.t.fsSmall }
        }
        Repeater {
          model: cal.lead + cal.days
          delegate: Item {
            required property int index
            readonly property int n: index - cal.lead + 1
            readonly property var date: new Date(d.month.getFullYear(), d.month.getMonth(), n)
            readonly property bool picked: n > 0 && d.ymd(date) === d.ymd(d.day)
            readonly property bool today: n > 0 && d.ymd(date) === d.ymd(new Date())
            width: cal.cell
            height: d.t.sp(32)
            Rectangle {
              visible: parent.n > 0
              anchors.centerIn: parent
              width: d.t.sp(30); height: width; radius: width / 2
              color: parent.picked ? d.t.accent : dayMa.containsMouse ? d.t.hover : "transparent"
              border.width: parent.today && !parent.picked ? 1 : 0
              border.color: d.t.accent
              Text { anchors.centerIn: parent; text: parent.parent.n; color: parent.parent.picked ? d.t.onColor(d.t.accent) : d.t.fg; font.family: d.t.font; font.pixelSize: d.t.fsSmall }
            }
            MouseArea { id: dayMa; anchors.fill: parent; enabled: parent.n > 0; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { d.day = parent.date; if (d.kind === "date") d.confirm() } }
          }
        }
      }
    }

    Column {
      visible: d.hasTime
      width: parent.width
      spacing: d.t.sp(6)
      Text { text: d.app.tr("Time", "Horário"); color: d.t.fgBright; font.family: d.t.font; font.pixelSize: d.t.fsText; font.bold: true }
      SField {
        id: timeField
        app: d.app
        width: d.t.sp(160)
        icon: "󰥔"
        text: { var m = String(d.args.time || "").match(/^(\d{1,2}):(\d{2})$/); return m ? U.time(new Date(2000, 0, 1, +m[1], +m[2]), d.app.clock24) : "" }
        placeholderText: d.app.clock24 ? "17:30" : "5:30 PM"
        onAccepted: d.confirm()
      }
    }
  }

  footer: Row {
    anchors.right: parent.right
    spacing: d.t.sp(10)
    visible: d.args.multi || !d.isList
    SButton { app: d.app; text: d.app.tr("Cancel", "Cancelar"); onClicked: d.closed() }
    SButton { app: d.app; kind: "primary"; text: d.app.tr("Done", "Concluído"); enabled2: d.ready; onClicked: d.confirm() }
  }
}
