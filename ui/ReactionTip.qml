import QtQuick
import "../lib/Model.js" as Model
import "../lib/Util.js" as U

// Slack's bubble over a reaction: the emoji large on a light square, then
// who reacted, the names in bold ("Ana, You and 3 others reacted with
// :tada:"), centered, with an arrow at the reaction. Declared inside it.
BubbleTip {
  id: tip
  property var ws
  property var reaction: null   // { name, users, count }
  property bool hovered: false

  padX: t.sp(14)
  padY: t.sp(12)
  visible: hovered && !!reaction && !!ws && !!parent && parent.visible
  text: who(false)

  // "You, Ana and 3 others reacted with :tada:"; in rich text the names in
  // bold and the tooltip's ink, the rest softer.
  function who(rich) {
    var r = tip.reaction
    if (!r || !tip.ws) return ""
    var name = function(s) { return rich ? "<b><font color=\"" + tip.ink + "\">" + U.escapeHtml(s) + "</font></b>" : s }
    var names = []
    var me = tip.ws.me.id
    if (r.users.indexOf(me) >= 0) names.push(name(tip.app.tr("You", "Você")))
    r.users.forEach(function(u) { if (u !== me) names.push(name(tip.ws.userName(u) || "?")) })
    var extra = Math.max(0, r.count - r.users.length)
    var rest = tip.app.tr(" reacted with :", " reagiu com :") + r.name + ":"
    return Model.people(names, extra, tip.app.lang) + (rich ? U.escapeHtml(rest) : rest)
  }

  contentItem: Column {
    spacing: tip.t.sp(8)
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: tip.t.sp(80)
      height: width
      radius: tip.t.sp(6)
      color: "#f8f8f8"
      EmojiIcon {
        anchors.centerIn: parent
        app: tip.app
        ws: tip.ws
        name: tip.reaction ? tip.reaction.name : ""
        size: tip.t.sp(60)
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, tip.t.sp(220))
      text: tip.who(true)
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      color: tip.soft
      font.family: tip.t.font
      font.pixelSize: tip.t.px(13)
    }
  }
}
