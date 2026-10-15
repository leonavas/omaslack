import QtQuick
import qs.Ui
import "../lib/Util.js" as U
import "../lib/Mrkdwn.js" as Md
import "../lib/Model.js" as Model
import "../lib/Registry.js" as Reg

// The top of a conversation's history: Slack's "This is the very
// beginning of #channel" with its buttons, or the person you're talking to.
Column {
  id: intro
  property var app: Reg.service
  property var win
  property var ws
  property string conv: ""
  readonly property var t: app.theme
  readonly property var c: ws ? ws.conv(conv) : null
  readonly property var other: c && c.kind === "im" ? ws.user(c.user) : null
  readonly property bool self: !!c && c.kind === "im" && c.user === ws.me.id
  x: t.sp(20)
  width: parent ? parent.width - t.sp(40) : 400
  spacing: t.sp(10)
  topPadding: t.sp(24)
  bottomPadding: t.sp(10)

  Row {
    visible: !!intro.other
    spacing: intro.t.sp(14)
    Avatar { app: intro.app; ws: intro.ws; user: intro.c ? (intro.c.user || "") : ""; size: intro.t.sp(72); round: 0.18; big: true; onClicked: { intro.ws.profileUser = intro.c.user; intro.ws.thread = null } }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: intro.t.sp(4)
      Text { text: intro.other ? intro.other.name : ""; textFormat: Text.PlainText; color: intro.t.fgBright; font.family: intro.t.font; font.pixelSize: intro.t.fsHuge - 2; font.bold: true }
      Text { visible: !!intro.other && !!intro.other.title; text: intro.other ? (intro.other.title || "") : ""; textFormat: Text.PlainText; color: intro.t.fgDim; font.family: intro.t.font; font.pixelSize: intro.t.fsSmall + 1 }
    }
  }

  Text {
    visible: !intro.other
    text: !intro.c ? "" : (intro.c.kind === "mpim" ? intro.ws.convLabel(intro.conv) : (intro.c.kind === "private" ? "🔒 " : "# ") + intro.c.name)
    textFormat: Text.PlainText
    color: intro.t.fgBright
    font.family: intro.t.font
    font.pixelSize: intro.t.fsHuge + 2
    font.bold: true
    width: parent.width
    wrapMode: Text.Wrap
  }

  RichText {
    width: parent.width
    app: intro.app
    color: intro.t.fgSoft
    html: intro.introText()
    onLink: url => { var m = url.match(/user\/([A-Z0-9]+)/); if (m) { intro.ws.profileUser = m[1]; intro.ws.thread = null } }
  }

  Row {
    spacing: intro.t.sp(8)
    SButton {
      visible: !!intro.c && intro.c.kind !== "im" && intro.c.kind !== "mpim" && !intro.c.archived && intro.c.member !== false
      app: intro.app
      small: true
      icon: "󰠁"
      text: intro.app.tr("Add people", "Adicionar pessoas")
      onClicked: intro.win.dialog("details", { conv: intro.conv, tab: "members", add: true })
    }
    SButton {
      visible: !!intro.c && intro.c.kind !== "im" && intro.c.kind !== "mpim" && !intro.c.archived && intro.c.member !== false && !intro.c.purpose
      app: intro.app
      small: true
      icon: "󰏫"
      text: intro.app.tr("Add description", "Adicionar descrição")
      onClicked: intro.win.dialog("details", { conv: intro.conv, tab: "about", edit: "purpose" })
    }
    SButton {
      visible: !!intro.other && !intro.self
      app: intro.app
      small: true
      icon: "󰀄"
      text: intro.app.tr("View profile", "Ver perfil")
      onClicked: { intro.ws.profileUser = intro.c.user; intro.ws.thread = null }
    }
  }

  function introText() {
    var c = intro.c
    if (!c) return ""
    var tr = intro.app.tr
    var esc = U.escapeHtml
    if (c.kind === "im") {
      if (intro.self) return esc(tr("This is your space. Draft messages, list your to-dos, or keep links and files handy. You can also talk to yourself here, but please bear in mind you'll have to supply both sides of the conversation.",
                                    "Este é o seu espaço. Rascunhe mensagens, anote tarefas ou guarde links e arquivos à mão. Você também pode falar sozinho aqui, mas lembre-se de que vai ter de fazer os dois lados da conversa."))
      var tag = Md.pill("@" + (intro.other ? intro.other.name : ""), intro.t.html.mention, intro.t.html.mentionBg, "slackqs://user/" + c.user, intro.t.html)
      return esc(tr("This conversation is just between ", "Esta conversa é apenas entre ")) + tag + esc(tr(" and you. Check out their profile to learn more about them.", " e você. Veja o perfil para saber mais sobre essa pessoa."))
    }
    if (c.kind === "mpim") {
      var names = Model.mpimMembers(c, intro.ws.users, intro.ws.me.id, intro.ws.handles).map(function(u) { return "<b>" + esc(intro.ws.userName(u)) + "</b>" })
      return esc(tr("This is the very beginning of your direct message history with ", "Este é o início do seu histórico de mensagens diretas com ")) + names.join(", ") + "."
    }
    var who = c.creator ? intro.ws.userName(c.creator) : ""
    var when = c.created ? U.fullDate(new Date(c.created * 1000), intro.app.lang) : ""
    var head = intro.app.lang === "pt-BR"
      ? (who ? "<b>@" + esc(who) + "</b> criou este canal" + (when ? " em " + esc(when) : "") + ". " : "") + "Este é o início do canal <b>" + (c.kind === "private" ? "🔒" : "#") + esc(c.name) + "</b>."
      : (who ? "<b>@" + esc(who) + "</b> created this channel" + (when ? " on " + esc(when) : "") + ". " : "") + "This is the very beginning of the <b>" + (c.kind === "private" ? "🔒" : "#") + esc(c.name) + "</b> channel."
    if (c.purpose) head += "<br/>" + esc(c.purpose.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"))
    return head
  }
}
