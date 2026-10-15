.pragma library

// A pretend workspace for trying the app without signing in
// (SLACKQS_DEMO=1): the Web API methods the store calls, answered from
// here. Writes are accepted and echoed back.

var ME = "U0ME"
var now = Math.floor(Date.now() / 1000)
function ts(secAgo, n) { return String(now - secAgo) + "." + String(n || 100).padStart(6, "0") }
function ava(n) { return "https://a.slack-edge.com/80588/img/avatars/ava_00" + (n < 10 ? "0" + n : n) + "-72.png" }

var users = [
  { id: ME, name: "you", profile: { display_name: "Leo", real_name: "Leonardo Navas", title: "Staff Engineer", image_72: ava(1), image_192: ava(1).replace("-72", "-192"), status_emoji: ":house_with_garden:", status_text: "Working remotely", email: "leo@acme.test" }, tz_label: "Brasília Standard Time", tz_offset: -10800 },
  { id: "U0ANA", name: "ana", profile: { display_name: "Ana Souza", real_name: "Ana Souza", title: "Product Designer", image_72: ava(2), status_emoji: ":palm_tree:", status_text: "Vacationing" }, tz_label: "Brasília Standard Time", tz_offset: -10800 },
  { id: "U0BRUNO", name: "bruno.silva", profile: { display_name: "Bruno", real_name: "Bruno Silva", title: "Backend Engineer", image_72: ava(3) } },
  { id: "U0CAIO", name: "caio", profile: { display_name: "Caio Mendes", real_name: "Caio Mendes", title: "Engineering Manager", image_72: ava(4), status_emoji: ":date:", status_text: "In a meeting" } },
  { id: "U0DANI", name: "dani", profile: { display_name: "Dani", real_name: "Daniela Rocha", title: "Data Scientist", image_72: ava(5) } },
  { id: "U0EDU", name: "edu", profile: { display_name: "Eduardo Lima", real_name: "Eduardo Lima", title: "SRE", image_72: ava(6) } },
  { id: "U0FER", name: "fernanda", profile: { display_name: "Fernanda", real_name: "Fernanda Alves", title: "QA", image_72: ava(7) } },
  { id: "U0GITHUB", name: "github", is_bot: true, profile: { display_name: "GitHub", real_name: "GitHub", image_72: "https://a.slack-edge.com/80588/img/plugins/github/service_72.png" } },
  { id: "USLACKBOT", name: "slackbot", is_bot: true, profile: { display_name: "Slackbot", real_name: "Slackbot", image_72: "https://a.slack-edge.com/80588/img/slackbot_72.png" } }
]

var convs = [
  { id: "C0GENERAL", name: "general", is_channel: true, is_general: true, is_member: true, num_members: 42, topic: { value: "Company-wide announcements and work-based matters" }, purpose: { value: "This channel is for workspace-wide communication and announcements." }, created: now - 86400 * 400, creator: "U0CAIO" },
  { id: "C0RANDOM", name: "random", is_channel: true, is_member: true, num_members: 40, topic: { value: "Non-work banter and water cooler conversation" } },
  { id: "C0ENG", name: "engineering", is_channel: true, is_member: true, num_members: 18, topic: { value: "Deploys on Tuesdays and Thursdays · <https://status.acme.test|status page>" } },
  { id: "C0DESIGN", name: "design", is_channel: true, is_member: true, num_members: 9 },
  { id: "C0RELEASES", name: "releases", is_channel: true, is_member: true, num_members: 30 },
  { id: "G0LEADS", name: "leadership", is_channel: true, is_private: true, is_member: true, num_members: 5 },
  { id: "C0ALERTS", name: "alerts-prod", is_channel: true, is_member: true, num_members: 12 },
  { id: "C0OLD", name: "old-project", is_channel: true, is_member: true, is_archived: true },
  { id: "D0ANA", is_im: true, user: "U0ANA" },
  { id: "D0BRUNO", is_im: true, user: "U0BRUNO" },
  { id: "D0CAIO", is_im: true, user: "U0CAIO" },
  { id: "D0ME", is_im: true, user: ME },
  { id: "D0GITHUB", is_im: true, user: "U0GITHUB" },
  { id: "G0MPIM", name: "mpdm-ana--bruno.silva--you-1", is_mpim: true, is_private: true }
]

var sections = [
  { channel_section_id: "L0STARS", type: "stars", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L0PROJ", type: "standard", name: "Projects", emoji: "rocket", channel_ids_page: { channel_ids: ["C0ENG", "C0RELEASES"] } },
  { channel_section_id: "L0CHAN", type: "channels", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L0DMS", type: "direct_messages", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L0APPS", type: "recent_apps", name: "", channel_ids_page: { channel_ids: [] } }
]

function rt(parts) { return [{ type: "rich_text", elements: parts }] }
function sec(els) { return { type: "rich_text_section", elements: els } }
function tx(t, style) { var e = { type: "text", text: t }; if (style) e.style = style; return e }

var history = {
  C0GENERAL: [
    { user: "U0CAIO", ts: ts(86400 * 2 + 3000), text: "Bom dia, pessoal! :wave: Lembrete: a all-hands é amanhã às 15h." },
    { user: "U0DANI", subtype: "channel_join", ts: ts(86400 * 2 + 2000), text: "<@U0DANI> has joined the channel" },
    { user: "U0FER", subtype: "channel_join", ts: ts(86400 * 2 + 1900), text: "<@U0FER> has joined the channel" },
    { user: "U0EDU", subtype: "channel_join", ts: ts(86400 * 2 + 1800), text: "<@U0EDU> has joined the channel" },
    { user: "U0ANA", ts: ts(86400 + 500), text: "Novo guia de marca publicado! Deem uma olhada e comentem :art:",
      reactions: [{ name: "heart", users: ["U0BRUNO", "U0CAIO", ME], count: 3 }, { name: "tada", users: ["U0DANI"], count: 1 }],
      reply_count: 4, reply_users: ["U0BRUNO", "U0CAIO", ME], latest_reply: ts(3600 * 5), thread_ts: ts(86400 + 500) },
    { user: "U0BRUNO", ts: ts(7200), text: "Alguém sabe se o escritório abre no feriado?" },
    { user: "U0CAIO", ts: ts(7100), text: "Não abre :sweat_smile: aproveitem o descanso" },
    { user: "U0CAIO", ts: ts(7050), text: "e lembrem de atualizar o *status* no Slack", edited: { user: "U0CAIO", ts: ts(7000) } },
    { user: "U0ANA", ts: ts(1800), text: "<!here> o novo café chegou na copa :coffee:",
      reactions: [{ name: "coffee", users: ["U0BRUNO", "U0EDU", "U0FER", "U0DANI"], count: 7 }, { name: "+1::skin-tone-3", users: [ME], count: 1 }] }
  ],
  C0ENG: [
    { user: "U0EDU", ts: ts(86400 * 3), text: "Deploy da API terminado sem incidentes :rocket:" },
    { user: "U0BRUNO", ts: ts(5400), text: "Alguém pode revisar meu PR? <https://github.com/acme/api/pull/482|acme/api#482> mexe no cache de sessão", reply_count: 2, reply_users: ["U0EDU", ME], latest_reply: ts(4000), thread_ts: ts(5400), subscribed: true },
    { user: "U0EDU", ts: ts(5000), blocks: rt([sec([tx("Achei o problema. O "), tx("TTL", { code: true }), tx(" estava em segundos, não em ms:")]),
        { type: "rich_text_preformatted", elements: [tx("const ttl = config.session.ttl * 1000\ncache.set(key, value, { ttl })")] },
        sec([tx("Quem puder, dá uma olhada em "), { type: "channel", channel_id: "C0RELEASES" }, tx(" depois.")])]),
      text: "Achei o problema..." },
    { user: ME, ts: ts(4800), text: "Boa! Vou aprovar :white_check_mark:", reactions: [{ name: "raised_hands", users: ["U0EDU", "U0BRUNO"], count: 2 }] },
    { user: "U0GITHUB", bot_id: "B0GH", username: "GitHub", ts: ts(4500), text: "",
      attachments: [{ color: "#2eb886", pretext: "Pull request merged", author_name: "bruno.silva", title: "acme/api#482 Fix session cache TTL", title_link: "https://github.com/acme/api/pull/482", text: "Session cache entries now expire after the configured TTL in milliseconds.", fields: [{ title: "Reviewers", value: "edu, leo", short: true }, { title: "Checks", value: "12 passed", short: true }], footer: "GitHub", ts: now - 4500 }] },
    { user: "U0CAIO", ts: ts(600), text: "<@U0ME> consegue olhar o alerta de latência no _alerts-prod_? Parece relacionado ao deploy de ontem.",
      reactions: [{ name: "eyes", users: [ME], count: 1 }] }
  ],
  C0RANDOM: [
    { user: "U0DANI", ts: ts(86400 + 9000), text: "Qual o melhor lugar pra almoçar aqui perto? :thinking_face:" },
    { user: "U0FER", ts: ts(86400 + 8000), text: "o japonês da esquina é :100:", reactions: [{ name: "100", users: ["U0DANI", "U0ANA"], count: 2 }] },
    { user: "U0ANA", ts: ts(3000), text: ":tada::tada::tada:" },
    { user: "U0BRUNO", ts: ts(2900), text: "Olha que foto incrível do pôr do sol de ontem", files: [{ id: "F0SUNSET", name: "sunset.jpg", mimetype: "image/jpeg", filetype: "jpg", pretty_type: "JPEG", size: 482113,
        thumb_720: "https://upload.wikimedia.org/wikipedia/commons/thumb/5/58/Sunset_2007-1.jpg/500px-Sunset_2007-1.jpg", thumb_720_w: 500, thumb_720_h: 333,
        url_private: "https://upload.wikimedia.org/wikipedia/commons/5/58/Sunset_2007-1.jpg", permalink: "https://acme.slack.com/files/U0BRUNO/F0SUNSET/sunset.jpg" }] }
  ],
  C0DESIGN: [
    { user: "U0ANA", ts: ts(86400 * 5), text: "Moodboard da nova landing:", files: [{ id: "F0PDF", name: "landing-moodboard.pdf", mimetype: "application/pdf", filetype: "pdf", pretty_type: "PDF", size: 2400000, url_private: "https://example.com/moodboard.pdf", permalink: "https://acme.slack.com/files/U0ANA/F0PDF" }] }
  ],
  C0RELEASES: [
    { user: "U0EDU", ts: ts(86400 * 6), blocks: [{ type: "header", text: { type: "plain_text", text: "Release 4.12.0" } }, { type: "section", text: { type: "mrkdwn", text: "*Highlights*\n• Faster search\n• Dark mode for reports\n• Bug fixes" } }, { type: "divider" }, { type: "context", elements: [{ type: "mrkdwn", text: "Shipped by <@U0EDU> · <https://acme.test/changelog|changelog>" }] }, { type: "actions", elements: [{ type: "button", text: { type: "plain_text", text: "View changelog" }, url: "https://acme.test/changelog", style: "primary" }, { type: "button", text: { type: "plain_text", text: "Report a bug" }, url: "https://acme.test/bugs" }] }], text: "Release 4.12.0" }
  ],
  G0LEADS: [
    { user: "U0CAIO", ts: ts(86400 * 1 + 200), text: "Pauta da reunião de quinta:\n1. Planejamento do Q4\n2. Contratações\n3. Offsite" },
    { user: ME, ts: ts(86400 * 1 + 100), text: "> 2. Contratações\nTenho dois candidatos ótimos pra backend." }
  ],
  C0ALERTS: [
    { user: "U0GITHUB", bot_id: "B0AL", username: "Alertmanager", ts: ts(700), text: "", attachments: [{ color: "danger", title: "[FIRING:1] HighLatency api-gateway", text: "p99 latency above 800ms for 10 minutes", footer: "Alertmanager" }] },
    { user: "U0GITHUB", bot_id: "B0AL", username: "Alertmanager", ts: ts(300), text: "", attachments: [{ color: "good", title: "[RESOLVED] HighLatency api-gateway", text: "p99 latency back to normal", footer: "Alertmanager" }] }
  ],
  D0ANA: [
    { user: "U0ANA", ts: ts(86400 + 300), text: "Oi! Viu o protótipo que mandei? :eyes:" },
    { user: ME, ts: ts(86400 + 200), text: "Vi sim, ficou ótimo! Só ajustaria o contraste dos botões" },
    { user: "U0ANA", ts: ts(900), text: "Ajustei! Dá uma olhada quando puder :pray:" },
    { user: "U0ANA", ts: ts(880), text: "e me avisa se precisar de algo antes das férias :palm_tree:" }
  ],
  D0BRUNO: [
    { user: "U0BRUNO", ts: ts(86400 * 2), text: "valeu pela review ontem!" },
    { user: ME, ts: ts(86400 * 2 - 100), text: "Tamo junto :muscle:" }
  ],
  D0CAIO: [
    { user: "U0CAIO", ts: ts(400), text: "Tem 5 min pra uma call rápida sobre o incidente?" }
  ],
  D0ME: [
    { user: ME, ts: ts(86400 * 8), text: "Lembrar: renovar certificado TLS até sexta" }
  ],
  D0GITHUB: [
    { user: "U0GITHUB", bot_id: "B0GH", ts: ts(86400 * 4), text: "You have 2 review requests waiting." }
  ],
  G0MPIM: [
    { user: "U0ANA", ts: ts(86400 * 3), text: "Bora marcar o happy hour?" },
    { user: "U0BRUNO", ts: ts(86400 * 3 - 60), text: "sexta? :beers:" }
  ]
}

var replies = {}
replies["C0GENERAL/" + ts(86400 + 500)] = [
  { user: "U0BRUNO", ts: ts(86000), text: "Ficou lindo! :star-struck:" },
  { user: "U0CAIO", ts: ts(80000), text: "Parabéns, Ana. Vamos divulgar na all-hands." },
  { user: ME, ts: ts(20000), text: "Muito bom! Só faltou a versão em PDF?" },
  { user: "U0ANA", ts: ts(3600 * 5), text: "<@U0ME> subi agora na pasta compartilhada :+1:" }
]
replies["C0ENG/" + ts(5400)] = [
  { user: "U0EDU", ts: ts(5000), text: "Olhando agora" },
  { user: ME, ts: ts(4000), text: "Aprovado :white_check_mark:", subtype: "thread_broadcast" }
]

var counts = {
  C0GENERAL: { unread: true, mentions: 0, last_read: ts(7000) },
  C0ENG: { unread: true, mentions: 1, last_read: ts(4700) },
  C0RANDOM: { unread: true, mentions: 0, last_read: ts(86400 + 8000) },
  C0ALERTS: { unread: true, mentions: 0, last_read: ts(800) },
  D0ANA: { unread: true, mentions: 2, last_read: ts(86400 + 200) },
  D0CAIO: { unread: true, mentions: 1, last_read: ts(500) }
}

var custom = {
  partyparrot: "https://cultofthepartyparrot.com/parrots/hd/parrot.gif",
  shipit: "alias:rocket"
}

function latestOf(id) {
  var h = history[id] || []
  return h.length ? h[h.length - 1].ts : ""
}

function respond(method, p, me) {
  switch (method) {
  case "auth.test": return { ok: true, url: "https://acme.slack.com/", team: "Acme", user: "you", team_id: "T0DEMO", user_id: ME }
  case "team.info": return { ok: true, team: { name: "Acme", icon: {} } }
  case "users.list": return { ok: true, members: users }
  case "users.info": return { ok: true, user: users.filter(function(u) { return u.id === p.user })[0] || users[0] }
  case "users.conversations": return { ok: true, channels: convs }
  case "users.channelSections.list": return { ok: true, channel_sections: sections }
  case "stars.list": return { ok: true, items: [{ type: "channel", channel: "C0GENERAL" }, { type: "im", channel: "D0ME" }] }
  case "client.userBoot": return { ok: true, is_open: ["D0ANA", "D0BRUNO", "D0CAIO", "D0ME", "D0GITHUB", "G0MPIM"], prefs: { show_sidebar_avatars: true } }
  case "client.counts": {
    var out = { ok: true, channels: [], ims: [], mpims: [], threads: { has_unreads: true, mention_count: 1 } }
    convs.forEach(function(c) {
      var k = counts[c.id] || { unread: false, mentions: 0, last_read: latestOf(c.id) }
      var row = { id: c.id, latest: latestOf(c.id), last_read: k.last_read, has_unreads: k.unread, mention_count: k.mentions }
      ;(c.is_im ? out.ims : c.is_mpim ? out.mpims : out.channels).push(row)
    })
    return out
  }
  case "users.prefs.get": return { ok: true, prefs: { all_notifications_prefs: JSON.stringify({ channels: { C0ALERTS: { muted: true } }, global: { global_desktop: "mentions_dms" } }) } }
  case "users.getPresence": return { ok: true, presence: ["U0ANA", "U0CAIO", ME].indexOf(p.user || ME) >= 0 ? "active" : "away" }
  case "dnd.info": return { ok: true, snooze_enabled: false, dnd_enabled: false }
  case "dnd.teamInfo": return { ok: true, users: { U0ANA: { snooze_enabled: true, snooze_endtime: now + 3600 } } }
  case "emoji.list": return { ok: true, emoji: custom }
  case "commands.list": return { ok: true, commands: [{ name: "/remind", type: "core", desc: "Set a reminder", usage: "[@someone or #channel] [what] [when]" }, { name: "/giphy", type: "app", desc: "Post a random GIF", usage: "[text]", app_name: "Giphy" }] }
  case "saved.list": return { ok: true, saved_items: [{ item_type: "message", item_id: "C0ENG", ts: history.C0ENG[1].ts, state: "in_progress", date_created: now - 3600 }] }
  case "users.priority.list": return { ok: true, users: { vip: ["U0CAIO"] } }
  case "subscriptions.thread.getView": {
    var root = history.C0ENG[1]
    var r = replies["C0ENG/" + root.ts]
    var rm = JSON.parse(JSON.stringify(root)); rm.channel = "C0ENG"; rm.last_read = r[0].ts
    var rg = JSON.parse(JSON.stringify(history.C0GENERAL[4])); rg.channel = "C0GENERAL"; rg.last_read = replies["C0GENERAL/" + rg.ts][3].ts
    return { ok: true, total_unread_replies: 1, has_more: false, threads: [
      { root_msg: rm, latest_replies: r },
      { root_msg: rg, latest_replies: replies["C0GENERAL/" + rg.ts].slice(-2) }
    ] }
  }
  case "conversations.history": {
    var h = (history[p.channel] || []).slice()
    if (p.latest) h = h.filter(function(m) { return parseFloat(m.ts) < parseFloat(p.latest) || (p.inclusive && m.ts === p.latest) })
    if (p.oldest) h = h.filter(function(m) { return parseFloat(m.ts) > parseFloat(p.oldest) })
    h = h.reverse().slice(0, p.limit || 60)
    return { ok: true, messages: h, has_more: false }
  }
  case "conversations.replies": {
    var parent = (history[p.channel] || []).filter(function(m) { return m.ts === p.ts })[0]
    var rs = replies[p.channel + "/" + p.ts] || []
    return { ok: true, messages: (parent ? [parent] : []).concat(rs), has_more: false }
  }
  case "conversations.info": {
    var c = convs.filter(function(x) { return x.id === p.channel })[0]
    return c ? { ok: true, channel: c } : { ok: false, error: "channel_not_found" }
  }
  case "conversations.members": return { ok: true, members: users.filter(function(u) { return !u.is_bot }).map(function(u) { return u.id }) }
  case "conversations.list": return { ok: true, channels: convs.filter(function(c) { return c.is_channel }).concat([{ id: "C0BOOK", name: "book-club", num_members: 7, purpose: { value: "Monthly reads" } }, { id: "C0MUSIC", name: "music", num_members: 15 }]) }
  case "pins.list": return { ok: true, items: p.channel === "C0GENERAL" ? [{ type: "message", created: now - 3000, created_by: "U0CAIO", message: history.C0GENERAL[0] }] : [] }
  case "search.messages": {
    var q = String(p.query || "").toLowerCase().replace(/\*$/, "")
    var hits = []
    Object.keys(history).forEach(function(cid) {
      history[cid].forEach(function(m) {
        if ((m.text || "").toLowerCase().indexOf(q) >= 0 && q) {
          var c = convs.filter(function(x) { return x.id === cid })[0]
          hits.push({ ts: m.ts, user: m.user, text: (m.text || "").replace(new RegExp("(" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig"), "$1"),
                      channel: { id: cid, name: c.name || "", is_im: !!c.is_im, is_mpim: !!c.is_mpim, is_private: !!c.is_private }, permalink: "https://acme.slack.com/archives/" + cid + "/p" + m.ts.replace(".", "") })
        }
      })
    })
    return { ok: true, messages: { total: hits.length, paging: { pages: 1, total: hits.length }, matches: hits } }
  }
  case "chat.postMessage": {
    var m = { user: me, ts: String(Math.floor(Date.now() / 1000)) + ".000" + String(Math.floor(Math.random() * 900) + 100), text: p.text || "", blocks: p.blocks ? JSON.parse(p.blocks) : [] }
    if (p.thread_ts) m.thread_ts = p.thread_ts
    if (p.thread_ts && p.reply_broadcast) m.subtype = "thread_broadcast"
    if (p.thread_ts) (replies[p.channel + "/" + p.thread_ts] = replies[p.channel + "/" + p.thread_ts] || []).push(m)
    if (!p.thread_ts || p.reply_broadcast) (history[p.channel] = history[p.channel] || []).push(m)
    return { ok: true, ts: m.ts, message: m }
  }
  case "conversations.create": {
    var made = { id: "C0NEW" + String(Math.floor(Math.random() * 1e6)), name: p.name, is_channel: true, is_private: String(p.is_private) === "true",
                 is_member: true, created: Math.floor(Date.now() / 1000), creator: me }
    convs.push(made)
    return { ok: true, channel: made }
  }
  case "conversations.open": {
    var who = String(p.users || "").split(",").filter(function(x) { return x })
    var handle = function(id) { var u = users.filter(function(x) { return x.id === id })[0]; return u ? u.name : id }
    var found = who.length === 1 ? convs.filter(function(c) { return c.is_im && c.user === who[0] })[0] : null
    if (!found) {
      found = who.length === 1 ? { id: "D0" + who[0].slice(1), is_im: true, user: who[0] }
        : { id: "G0" + String(Math.floor(Math.random() * 1e6)), name: "mpdm-" + who.concat([me]).map(handle).join("--") + "-1", is_mpim: true, is_private: true }
      convs.push(found)
    }
    return { ok: true, channel: found }
  }
  case "chat.update": return { ok: true, ts: p.ts }
  case "client.getWebSocketURL": return { ok: false, error: "demo" }
  case "rtm.connect": return { ok: false, error: "demo" }
  default: return { ok: true }
  }
}
