.pragma library

// Pretend workspaces for trying the app without signing in
// (SLACKQS_DEMO=1): the Web API methods the store calls, answered from
// here. Writes are accepted and echoed back. Everything in them is made up:
// the companies, the people, what they say, and the pictures, which are
// drawn here (SVG) so nothing real is pictured and nothing is fetched for
// them.

var ME = "U0ME"
var now = Math.floor(Date.now() / 1000)
function ts(secAgo, n) { return String(now - secAgo) + "." + String(n || 100).padStart(6, "0") }

// ---------------------------------------------------------------- pictures

function svg(w, h, body) {
  return "data:image/svg+xml;utf8," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h
                                                         + '" viewBox="0 0 ' + w + " " + h + '">' + body + "</svg>")
}

// A drawn face: head, hair, eyes, a smile and shoulders, over a color.
// look: { bg, skin, hair, shirt, style (short|long|bun|curly|none), glasses }
function face(look) {
  var ink = "#24212b"
  var hair = look.hair, style = look.style || "short"
  var back = style === "long" ? '<rect x="8.6" y="7" width="18.8" height="22" rx="8.5" fill="' + hair + '"/>'
           : style === "bun" ? '<circle cx="18" cy="5.4" r="3.4" fill="' + hair + '"/>' : ""
  var cap = style === "none" ? '<path d="M11.4 11.6c1.3-3 3.7-4.4 6.6-4.4s5.3 1.4 6.6 4.4c-2-1.2-4.2-1.7-6.6-1.7s-4.6.5-6.6 1.7z" fill="' + hair + '"/>'
          : style === "curly" ? '<path d="M10 16.5c-1.6-6.3 2-10.8 8-10.8s9.6 4.5 8 10.8c-.9-2-1.9-3.3-3-4 .1 1.1-.4 1.9-1.4 2.2.2-1.4-.5-2.6-1.6-3.2-.3 1.2-1.1 2-2.2 2.1.3-1.1-.1-2.2-.9-2.8-1 1.4-2.6 2.2-4.4 2.4-1 .7-1.8 1.8-2.5 3.3z" fill="' + hair + '"/>'
          : '<path d="M10.4 15.8c-.8-6 2.6-9.9 7.6-9.9s8.4 3.9 7.6 9.9c-1-2.9-3.7-5-7.6-5.4-1.4 1.6-4.2 2.6-7.6 5.4z" fill="' + hair + '"/>'
  var glasses = look.glasses
    ? '<g fill="none" stroke="' + ink + '" stroke-width=".9"><circle cx="15.1" cy="16.6" r="2.3"/><circle cx="20.9" cy="16.6" r="2.3"/><path d="M17.4 16.4h1.2"/></g>' : ""
  return svg(72, 72, '<g transform="scale(2)"><rect width="36" height="36" fill="' + look.bg + '"/>'
    + '<path d="M3.5 37c.6-6.4 6.3-9.9 14.5-9.9s13.9 3.5 14.5 9.9z" fill="' + look.shirt + '"/>'
    + '<rect x="15.6" y="21" width="4.8" height="7" rx="2.2" fill="' + look.skin + '"/>'
    + back
    + '<rect x="10.6" y="7.6" width="14.8" height="17.6" rx="7.2" fill="' + look.skin + '"/>'
    + cap
    + '<circle cx="15.1" cy="16.7" r="1.05" fill="' + ink + '"/><circle cx="20.9" cy="16.7" r="1.05" fill="' + ink + '"/>'
    + '<path d="M15.9 20.4c1.2 1.15 3 1.15 4.2 0" fill="none" stroke="' + ink + '" stroke-width="1" stroke-linecap="round"/>'
    + glasses + "</g>")
}

// An app's or a workspace's mark: a white shape on a gradient.
function mark(from, to, shape) {
  return svg(132, 132, '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="' + from
    + '"/><stop offset="1" stop-color="' + to + '"/></linearGradient></defs><rect width="132" height="132" fill="url(#g)"/>' + shape)
}

var pics = {
  acme: mark("#6d5dfc", "#c050d8", '<path d="M66 24 L104 104 H86 L78 86 H54 L46 104 H28 Z M60 72 H72 L66 58 Z" fill="#fff"/>'),
  side: mark("#ff9f43", "#ee5a6f", '<g fill="#fff"><rect x="30" y="34" width="72" height="14" rx="7"/><rect x="30" y="59" width="50" height="14" rx="7"/><rect x="30" y="84" width="62" height="14" rx="7"/></g>'),
  shipyard: mark("#1f6f5c", "#2bb58a", '<path d="M66 22 L92 70 H72 V96 H60 V70 H40 Z" fill="#fff"/><path d="M30 100 Q48 90 66 100 T102 100 V110 Q84 100 66 110 T30 110 Z" fill="#fff" opacity=".85"/>'),
  watchtower: mark("#b4232f", "#f05a5a", '<path d="M66 26c-15 0-24 11-24 26v20l-8 12v6h64v-6l-8-12V52c0-15-9-26-24-26z" fill="#fff"/><circle cx="66" cy="102" r="9" fill="#fff"/>'),
  // A dashboard mockup: a sidebar, three numbers and a chart.
  dashboard: svg(960, 600, '<defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7c6cff" stop-opacity=".55"/>'
    + '<stop offset="1" stop-color="#7c6cff" stop-opacity="0"/></linearGradient></defs>'
    + '<rect width="960" height="600" fill="#11131f"/><rect width="190" height="600" fill="#181b2b"/>'
    + '<rect x="28" y="30" width="34" height="34" rx="9" fill="#7c6cff"/><rect x="74" y="40" width="80" height="12" rx="6" fill="#3a3f5c"/>'
    + '<g fill="#2a2f48"><rect x="28" y="104" width="130" height="12" rx="6"/><rect x="28" y="140" width="104" height="12" rx="6"/><rect x="28" y="176" width="118" height="12" rx="6"/><rect x="28" y="212" width="90" height="12" rx="6"/></g>'
    + '<rect x="20" y="96" width="150" height="28" rx="8" fill="#7c6cff" opacity=".25"/>'
    + '<rect x="222" y="34" width="210" height="18" rx="9" fill="#e9e9f4"/><rect x="222" y="62" width="140" height="10" rx="5" fill="#4a4f6e"/>'
    + '<g fill="#1c2033"><rect x="222" y="100" width="222" height="110" rx="14"/><rect x="462" y="100" width="222" height="110" rx="14"/><rect x="702" y="100" width="222" height="110" rx="14"/></g>'
    + '<g fill="#5b6080"><rect x="244" y="122" width="90" height="10" rx="5"/><rect x="484" y="122" width="70" height="10" rx="5"/><rect x="724" y="122" width="100" height="10" rx="5"/></g>'
    + '<g fill="#f2f2fa"><rect x="244" y="146" width="110" height="26" rx="8"/><rect x="484" y="146" width="84" height="26" rx="8"/><rect x="724" y="146" width="124" height="26" rx="8"/></g>'
    + '<polyline points="364,186 380,176 396,182 412,166 428,170" fill="none" stroke="#2fd39a" stroke-width="4" stroke-linecap="round"/>'
    + '<polyline points="588,170 604,178 620,172 636,184 652,188" fill="none" stroke="#ff6b81" stroke-width="4" stroke-linecap="round"/>'
    + '<polyline points="858,184 874,174 890,178 906,162" fill="none" stroke="#2fd39a" stroke-width="4" stroke-linecap="round"/>'
    + '<rect x="222" y="232" width="702" height="340" rx="16" fill="#1c2033"/>'
    + '<rect x="248" y="256" width="150" height="14" rx="7" fill="#c9cbe0"/><rect x="784" y="254" width="112" height="22" rx="11" fill="#2a2f48"/>'
    + '<g stroke="#2a2f48" stroke-width="2"><line x1="248" y1="330" x2="898" y2="330"/><line x1="248" y1="400" x2="898" y2="400"/><line x1="248" y1="470" x2="898" y2="470"/><line x1="248" y1="540" x2="898" y2="540"/></g>'
    + '<path d="M248 470 L300 452 L352 462 L404 420 L456 432 L508 380 L560 396 L612 344 L664 362 L716 318 L768 336 L820 300 L872 312 L898 296 V540 H248 Z" fill="url(#a)"/>'
    + '<polyline points="248,470 300,452 352,462 404,420 456,432 508,380 560,396 612,344 664,362 716,318 768,336 820,300 872,312 898,296" fill="none" stroke="#9d90ff" stroke-width="5" stroke-linejoin="round"/>'
    + '<polyline points="248,512 300,506 352,514 404,496 456,500 508,486 560,492 612,476 664,482 716,470 768,474 820,462 872,466 898,458" fill="none" stroke="#2fd39a" stroke-width="4" stroke-linejoin="round" stroke-dasharray="2 10" stroke-linecap="round"/>'
    + '<circle cx="820" cy="300" r="9" fill="#11131f" stroke="#fff" stroke-width="4"/>'),
  // A sunset over the hills, for #random.
  sunset: svg(960, 600, '<defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b1d5c"/><stop offset=".45" stop-color="#b8487a"/>'
    + '<stop offset=".75" stop-color="#f59a5b"/><stop offset="1" stop-color="#ffd59a"/></linearGradient>'
    + '<linearGradient id="w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3a06a"/><stop offset="1" stop-color="#3a2357"/></linearGradient></defs>'
    + '<rect width="960" height="600" fill="url(#s)"/><circle cx="600" cy="352" r="70" fill="#ffe2a8"/>'
    + '<path d="M0 360 L120 290 L230 330 L360 250 L470 320 L560 280 L690 340 L800 270 L960 330 V430 H0 Z" fill="#7a3f78"/>'
    + '<path d="M0 400 L150 340 L280 380 L420 320 L560 380 L700 330 L840 380 L960 350 V460 H0 Z" fill="#552f66"/>'
    + '<rect y="440" width="960" height="160" fill="url(#w)"/>'
    + '<g fill="#ffe2a8" opacity=".55"><rect x="540" y="458" width="120" height="5" rx="2.5"/><rect x="560" y="478" width="80" height="4" rx="2"/><rect x="575" y="496" width="50" height="3" rx="1.5"/></g>'
    + '<path d="M0 520 L90 470 L170 500 L260 456 L330 520 Z" fill="#24163a"/><path d="M700 520 L800 462 L880 490 L960 450 V520 Z" fill="#24163a"/>'
    + '<rect y="516" width="960" height="84" fill="#24163a"/>')
}

function person(id, handle, name, title, look, extra) {
  var picture = face(look)
  var u = { id: id, name: handle, profile: { display_name: name, real_name: name, title: title, image_72: picture, image_192: picture, image_512: picture },
            tz_label: "Central European Summer Time", tz_offset: 7200 }
  for (var k in extra || {}) {
    if (k === "profile") for (var p in extra.profile) u.profile[p] = extra.profile[p]
    else u[k] = extra[k]
  }
  return u
}
function app(id, name, picture) {
  return { id: id, name: name.toLowerCase(), is_bot: true, profile: { display_name: name, real_name: name, image_72: picture, image_192: picture, bot_id: "B" + id.slice(1) } }
}
var slackbot = { id: "USLACKBOT", name: "slackbot", is_bot: true, profile: { display_name: "Slackbot", real_name: "Slackbot", image_72: "https://a.slack-edge.com/80588/img/slackbot_72.png" } }
var alex = { bg: "#4f7cf0", skin: "#f1c9a5", hair: "#3b2a20", shirt: "#1e2a4a", style: "short", glasses: true }

function rt(parts) { return [{ type: "rich_text", elements: parts }] }
function sec(els) { return { type: "rich_text_section", elements: els } }
function tx(t, style) { var e = { type: "text", text: t }; if (style) e.style = style; return e }
function demoFile(team, id, title, filetype, pretty, user, daysAgo, extra) {
  var f = { id: id, name: title, title: title, filetype: filetype, pretty_type: pretty, user: user,
            created: now - daysAgo * 86400, timestamp: now - daysAgo * 86400, size: 48000 + daysAgo * 900,
            permalink: "https://" + team.domain + ".slack.com/files/" + user + "/" + id + "/" + title.toLowerCase().replace(/[^a-z0-9]+/g, "_"),
            url_private: "https://files.slack.com/files-pri/" + team.id + "-" + id + "/" + title, url_private_download: "https://files.slack.com/files-pri/" + team.id + "-" + id + "/download/" + title }
  for (var k in extra || {}) f[k] = extra[k]
  return f
}
function image(id, name, user, picture, w, h, team) {
  return { id: id, name: name, title: name, mimetype: "image/png", filetype: "png", pretty_type: "PNG", size: 482113, user: user,
           thumb_720: picture, thumb_720_w: w, thumb_720_h: h, thumb_360: picture, thumb_360_w: Math.round(w / 2), thumb_360_h: Math.round(h / 2),
           url_private: picture, permalink: "https://" + team.domain + ".slack.com/files/" + user + "/" + id + "/" + name }
}

// ---------------------------------------------------------------- Acme

var acme = { id: "T0DEMO", name: "Acme", domain: "acme" }
acme.users = [
  person(ME, "alex", "Alex Morgan", "Staff Engineer", alex, { profile: { status_emoji: ":house_with_garden:", status_text: "Working remotely", email: "alex@acme.example" } }),
  person("U0PRIYA", "priya", "Priya Raman", "Product Designer", { bg: "#f2a541", skin: "#c58b62", hair: "#1d1412", shirt: "#7b2f61", style: "long" },
         { profile: { status_emoji: ":palm_tree:", status_text: "Off Friday" } }),
  person("U0DIEGO", "diego", "Diego Alvarez", "Backend Engineer", { bg: "#2fa595", skin: "#dba67c", hair: "#3a2416", shirt: "#f4efe4", style: "short" }),
  person("U0SAM", "sam", "Sam Okafor", "Engineering Manager", { bg: "#8f63e0", skin: "#7b4e34", hair: "#161010", shirt: "#f2bd4b", style: "none" },
         { profile: { status_emoji: ":date:", status_text: "In a meeting" } }),
  person("U0LENA", "lena", "Lena Novak", "Data Scientist", { bg: "#e0646f", skin: "#f4d4bf", hair: "#c88a3e", shirt: "#22344f", style: "bun" }),
  person("U0TOMAS", "tomas", "Tomás Ribeiro", "Site Reliability Engineer", { bg: "#4f9d55", skin: "#e2b590", hair: "#5b3b22", shirt: "#26313f", style: "curly", glasses: true }),
  person("U0HANA", "hana", "Hana Sato", "QA Engineer", { bg: "#46a6dc", skin: "#f1d0b2", hair: "#202029", shirt: "#e46c50", style: "long" }),
  person("U0NOAH", "noah", "Noah Fischer", "Frontend Engineer", { bg: "#d9824b", skin: "#f0c7a2", hair: "#e3c16f", shirt: "#2c3d5c", style: "short" }),
  app("U0SHIP", "Shipyard", pics.shipyard),
  app("U0WATCH", "Watchtower", pics.watchtower),
  slackbot
]
acme.convs = [
  { id: "C0GENERAL", name: "general", is_channel: true, is_general: true, is_member: true, num_members: 48, topic: { value: "Company-wide announcements and work-based matters" }, purpose: { value: "This channel is for workspace-wide communication and announcements." }, created: now - 86400 * 400, creator: "U0SAM" },
  { id: "C0RANDOM", name: "random", is_channel: true, is_member: true, num_members: 45, topic: { value: "Non-work banter and water cooler conversation" } },
  { id: "C0ENG", name: "engineering", is_channel: true, is_member: true, num_members: 18, topic: { value: "Deploys on Tuesdays and Thursdays · <https://status.acme.example|status page>" }, purpose: { value: "Where the platform team builds, reviews and ships." }, created: now - 86400 * 380, creator: "U0SAM" },
  { id: "C0DESIGN", name: "design", is_channel: true, is_member: true, num_members: 9, topic: { value: "Critiques on Wednesdays" } },
  { id: "C0LAUNCH", name: "launch-q4", is_channel: true, is_member: true, num_members: 14, topic: { value: "Countdown to the Q4 launch :rocket:" } },
  { id: "C0RELEASES", name: "releases", is_channel: true, is_member: true, num_members: 30 },
  { id: "G0LEADS", name: "leadership", is_channel: true, is_private: true, is_member: true, num_members: 5 },
  { id: "C0ALERTS", name: "alerts-prod", is_channel: true, is_member: true, num_members: 12 },
  { id: "C0OLD", name: "old-website", is_channel: true, is_member: true, is_archived: true },
  { id: "D0PRIYA", is_im: true, user: "U0PRIYA" },
  { id: "D0DIEGO", is_im: true, user: "U0DIEGO" },
  { id: "D0SAM", is_im: true, user: "U0SAM" },
  { id: "D0LENA", is_im: true, user: "U0LENA" },
  { id: "D0ME", is_im: true, user: ME },
  { id: "D0SHIP", is_im: true, user: "U0SHIP" },
  { id: "G0MPIM", name: "mpdm-priya--diego--alex-1", is_mpim: true, is_private: true }
]
acme.open = ["D0PRIYA", "D0DIEGO", "D0SAM", "D0LENA", "D0ME", "D0SHIP", "G0MPIM"]
acme.sections = [
  { channel_section_id: "L0STARS", type: "stars", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L0PROJ", type: "standard", name: "Projects", emoji: "rocket", channel_ids_page: { channel_ids: ["C0LAUNCH", "C0RELEASES"] } },
  { channel_section_id: "L0CHAN", type: "channels", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L0DMS", type: "direct_messages", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L0APPS", type: "recent_apps", name: "", channel_ids_page: { channel_ids: [] } }
]
acme.history = {
  C0GENERAL: [
    { user: "U0SAM", ts: ts(86400 * 2 + 3000), text: "Morning everyone :wave: Reminder: the all-hands is tomorrow at 3pm in the atrium. Snacks are on us." },
    { user: "U0LENA", subtype: "channel_join", ts: ts(86400 * 2 + 2000), text: "<@U0LENA> has joined the channel" },
    { user: "U0HANA", subtype: "channel_join", ts: ts(86400 * 2 + 1900), text: "<@U0HANA> has joined the channel" },
    { user: "U0NOAH", subtype: "channel_join", ts: ts(86400 * 2 + 1800), text: "<@U0NOAH> has joined the channel" },
    { user: "U0PRIYA", ts: ts(86400 + 500), text: "The new brand guidelines are live! Have a look and leave your comments :art:",
      reactions: [{ name: "heart", users: ["U0DIEGO", "U0SAM", ME], count: 3 }, { name: "tada", users: ["U0LENA"], count: 1 }],
      reply_count: 4, reply_users: ["U0DIEGO", "U0SAM", ME], latest_reply: ts(3600 * 5), thread_ts: ts(86400 + 500) },
    { user: "U0DIEGO", ts: ts(7200), text: "Is the office open on Friday?" },
    { user: "U0SAM", ts: ts(7100), text: "Nope :sweat_smile: enjoy the long weekend" },
    { user: "U0SAM", ts: ts(7050), text: "and remember to set your *status* before you go", edited: { user: "U0SAM", ts: ts(7000) } },
    { user: "U0PRIYA", ts: ts(1800), text: "<!here> fresh coffee beans just landed in the kitchen :coffee:",
      reactions: [{ name: "coffee", users: ["U0DIEGO", "U0TOMAS", "U0HANA", "U0LENA"], count: 7 }, { name: "+1::skin-tone-3", users: [ME], count: 1 }] }
  ],
  C0ENG: [
    { user: "U0TOMAS", ts: ts(86400 + 4000), text: "Yesterday's deploy of the API went out without a hitch :rocket:" },
    { user: "U0PRIYA", ts: ts(9600), text: "Here's the new latency dashboard for on-call. Thoughts? :eyes:",
      files: [image("F0DASH", "latency-dashboard.png", "U0PRIYA", pics.dashboard, 960, 600, acme)],
      reactions: [{ name: "heart_eyes", users: ["U0NOAH", "U0SAM", "U0TOMAS", ME], count: 4 }, { name: "fire", users: ["U0DIEGO", "U0LENA"], count: 2 }] },
    { user: "U0DIEGO", ts: ts(9000), text: "Can someone review <https://git.acme.example/platform/api/pull/482|platform/api#482>? It fixes the session cache TTL :pray:",
      reply_count: 4, reply_users: ["U0LENA", "U0TOMAS", ME], latest_reply: ts(5200), thread_ts: ts(9000), subscribed: true },
    { user: "U0LENA", ts: ts(8400), blocks: rt([sec([tx("Found it. The "), tx("ttl", { code: true }), tx(" was in "), tx("seconds", { bold: true }), tx(", not milliseconds:")]),
        { type: "rich_text_preformatted", elements: [tx("const ttl = config.session.ttl * 1000\ncache.set(key, value, { ttl })")] },
        sec([tx("I'll write it up in "), { type: "channel", channel_id: "C0RELEASES" }, tx(" once it ships.")])]),
      text: "Found it..." },
    { user: ME, ts: ts(8100), text: "Nice catch! Approving now :white_check_mark:",
      reactions: [{ name: "raised_hands", users: ["U0DIEGO", "U0LENA"], count: 2 }, { name: "partyparrot", users: ["U0TOMAS", "U0NOAH", "U0HANA"], count: 3 }] },
    { user: "U0SHIP", ts: ts(5000), text: "",
      attachments: [{ color: "#2eb886", pretext: "Deployed to production", title: "api v2.14.0 · Fix session cache TTL", title_link: "https://ci.acme.example/deploys/2140",
                      text: "Session entries now expire after the configured TTL.", fields: [{ title: "Duration", value: "3m 12s", short: true }, { title: "Checks", value: "128 passed", short: true }],
                      footer: "Shipyard", ts: now - 5000 }] },
    { user: "U0SAM", ts: ts(600), text: "<@U0ME> can you look at the latency alert in <#C0ALERTS>? Probably related to this morning's deploy.",
      reactions: [{ name: "eyes", users: [ME], count: 1 }] }
  ],
  C0RANDOM: [
    { user: "U0LENA", ts: ts(86400 + 9000), text: "Best lunch spot around here? :thinking_face:" },
    { user: "U0HANA", ts: ts(86400 + 8000), text: "the ramen place on the corner is :100:", reactions: [{ name: "100", users: ["U0LENA", "U0PRIYA"], count: 2 }] },
    { user: "U0PRIYA", ts: ts(3300), text: ":tada::tada::tada:" },
    { user: "U0DIEGO", ts: ts(2900), text: "Sunset from yesterday's trail run :sunrise_over_mountains:",
      files: [image("F0SUNSET", "trail-sunset.png", "U0DIEGO", pics.sunset, 960, 600, acme)],
      reactions: [{ name: "star-struck", users: ["U0PRIYA", "U0HANA", ME], count: 3 }] }
  ],
  C0DESIGN: [
    { user: "U0PRIYA", ts: ts(86400 * 5), text: "Moodboard for the new landing page:", files: [{ id: "F0MOOD", name: "landing-moodboard.pdf", mimetype: "application/pdf", filetype: "pdf", pretty_type: "PDF", size: 2400000, url_private: "https://files.slack.com/files-pri/T0DEMO-F0MOOD/landing-moodboard.pdf", permalink: "https://acme.slack.com/files/U0PRIYA/F0MOOD" }] },
    { user: "U0NOAH", ts: ts(86400 * 5 - 600), text: "Love the type pairing. Can we try the darker variant for the hero?" }
  ],
  C0LAUNCH: [
    { user: "U0SAM", ts: ts(86400 * 2), text: "The launch checklist is pinned. Owners, please update your items by Friday :pray:" },
    { user: "U0NOAH", ts: ts(4000), text: "12 days to go :rocket: The new onboarding flow is behind the `onboarding_v2` flag in staging." }
  ],
  C0RELEASES: [
    { user: "U0TOMAS", ts: ts(86400 * 6), blocks: [{ type: "header", text: { type: "plain_text", text: "Release 4.12.0" } }, { type: "section", text: { type: "mrkdwn", text: "*Highlights*\n• Faster search\n• Dark mode for reports\n• Bug fixes" } }, { type: "divider" }, { type: "context", elements: [{ type: "mrkdwn", text: "Shipped by <@U0TOMAS> · <https://acme.example/changelog|changelog>" }] }, { type: "actions", elements: [{ type: "button", text: { type: "plain_text", text: "View changelog" }, url: "https://acme.example/changelog", style: "primary" }, { type: "button", text: { type: "plain_text", text: "Report a bug" }, url: "https://acme.example/bugs" }] }], text: "Release 4.12.0" }
  ],
  G0LEADS: [
    { user: "U0SAM", ts: ts(86400 + 200), text: "Agenda for Thursday:\n1. Q4 planning\n2. Hiring\n3. Offsite" },
    { user: ME, ts: ts(86400 + 100), text: "> 2. Hiring\nI have two great backend candidates lined up." }
  ],
  C0ALERTS: [
    { user: "U0WATCH", ts: ts(700), text: "", attachments: [{ color: "danger", title: "[FIRING:1] HighLatency api-gateway", text: "p99 latency above 800ms for 10 minutes", footer: "Watchtower" }] },
    { user: "U0WATCH", ts: ts(300), text: "", attachments: [{ color: "good", title: "[RESOLVED] HighLatency api-gateway", text: "p99 latency back to normal", footer: "Watchtower" }] }
  ],
  D0PRIYA: [
    { user: "U0PRIYA", ts: ts(86400 + 300), text: "Hey! Did you get a chance to look at the prototype? :eyes:" },
    { user: ME, ts: ts(86400 + 200), text: "I did, it looks great! I'd only bump the contrast on the buttons" },
    { user: "U0PRIYA", ts: ts(900), text: "Done! Have a look when you can :pray:" },
    { user: "U0PRIYA", ts: ts(880), text: "and ping me if you need anything before my day off :palm_tree:" }
  ],
  D0DIEGO: [
    { user: "U0DIEGO", ts: ts(86400 * 2), text: "thanks for the review yesterday!" },
    { user: ME, ts: ts(86400 * 2 - 100), text: "Anytime :muscle:" }
  ],
  D0SAM: [
    { user: "U0SAM", ts: ts(400), text: "Got 5 minutes for a quick call about the incident?" }
  ],
  D0LENA: [
    { user: "U0LENA", ts: ts(86400 * 3), text: "The churn model is retrained, numbers look much better :chart_with_upwards_trend:" },
    { user: ME, ts: ts(86400 * 3 - 300), text: "Amazing, let's demo it on Thursday" }
  ],
  D0ME: [
    { user: ME, ts: ts(86400 * 8), text: "Reminder: renew the TLS certificate by Friday" }
  ],
  D0SHIP: [
    { user: "U0SHIP", ts: ts(86400 * 4), text: "You have 2 review requests waiting." }
  ],
  G0MPIM: [
    { user: "U0PRIYA", ts: ts(86400 * 3), text: "Team dinner on Friday?" },
    { user: "U0DIEGO", ts: ts(86400 * 3 - 60), text: "I'm in :ramen:" }
  ]
}
acme.replies = {}
acme.replies["C0GENERAL/" + ts(86400 + 500)] = [
  { user: "U0DIEGO", ts: ts(86000), text: "Looks beautiful! :star-struck:" },
  { user: "U0SAM", ts: ts(80000), text: "Great work, Priya. Let's show it at the all-hands." },
  { user: ME, ts: ts(20000), text: "Love it! Is there a PDF version too?" },
  { user: "U0PRIYA", ts: ts(3600 * 5), text: "<@U0ME> just uploaded it to the shared folder :+1:" }
]
acme.replies["C0ENG/" + ts(9000)] = [
  { user: "U0LENA", ts: ts(8800), text: "Looking now :eyes:" },
  { user: "U0TOMAS", ts: ts(7400), text: "Left a couple of comments on the retry logic, otherwise LGTM :partyparrot:" },
  { user: ME, ts: ts(6200), text: "Approved :white_check_mark: ship it :shipit:" },
  { user: "U0DIEGO", ts: ts(5200), text: "Merged and deployed, thanks all! :tada:" }
]
acme.counts = {
  C0GENERAL: { unread: true, mentions: 0, last_read: ts(7000) },
  C0ENG: { unread: true, mentions: 1, last_read: ts(5100) },
  C0RANDOM: { unread: true, mentions: 0, last_read: ts(86400 + 8000) },
  C0LAUNCH: { unread: true, mentions: 0, last_read: ts(86400) },
  C0ALERTS: { unread: true, mentions: 0, last_read: ts(800) },
  D0PRIYA: { unread: true, mentions: 2, last_read: ts(86400 + 200) },
  D0SAM: { unread: true, mentions: 1, last_read: ts(500) }
}
acme.custom = {
  partyparrot: "https://cultofthepartyparrot.com/parrots/hd/parrot.gif",
  shipit: "alias:chipmunk"
}
acme.files = [
  demoFile(acme, "F0LAUNCH", "Q4 launch plan", "quip", "Canvas", "U0SAM", 2, { updated: now - 3600 * 5, last_read: now - 3600, canvas_readtime: 4, permalink: "https://acme.slack.com/docs/T0DEMO/F0LAUNCH" }),
  demoFile(acme, "F0ONCALL", "On-call rotation", "list", "List", "U0TOMAS", 3, { updated: now - 86400, permalink: "https://acme.slack.com/lists/T0DEMO/F0ONCALL" }),
  demoFile(acme, "F0INCIDENT", "Incident review: api latency.docx", "docx", "Word Document", "U0TOMAS", 6, { mimetype: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }),
  demoFile(acme, "F0CONTRACT", "Vendor contract.pdf", "pdf", "PDF", ME, 12, { mimetype: "application/pdf" }),
  demoFile(acme, "F0BUDGET", "Budget 2027.xlsx", "xlsx", "Excel Spreadsheet", "U0LENA", 21, { mimetype: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }),
  demoFile(acme, "F0METRICS", "Weekly metrics", "gsheet", "Google Sheets", "U0LENA", 30, { is_external: true, external_type: "gdrive", url_private: "https://docs.google.com/spreadsheets/d/demo" }),
  demoFile(acme, "F0KICKOFF", "Kickoff deck.pptx", "pptx", "PowerPoint Presentation", "U0PRIYA", 45, { mimetype: "application/vnd.openxmlformats-officedocument.presentationml.presentation" }),
  demoFile(acme, "F0API", "session-cache.ts", "typescript", "TypeScript", "U0DIEGO", 60, { mimetype: "text/plain", mode: "snippet" }),
  demoFile(acme, "F0DEMO", "Product walkthrough.mp4", "mp4", "MPEG 4 Video", "U0NOAH", 90, { mimetype: "video/mp4" }),
  demoFile(acme, "F0ONBOARD", "Onboarding guide", "quip", "Canvas", ME, 400, { updated: now - 86400 * 380, canvas_readtime: 2, permalink: "https://acme.slack.com/docs/T0DEMO/F0ONBOARD" }),
  demoFile(acme, "F0LOGS", "deploy-logs.zip", "zip", "Zip", "U0DIEGO", 800, { mimetype: "application/zip" })
]
acme.stars = [{ type: "channel", channel: "C0ENG" }, { type: "im", channel: "D0ME" }, { type: "file", file: acme.files[0] }, { type: "file", file: acme.files[4] }]
acme.saved = [{ item_type: "message", item_id: "C0ENG", ts: acme.history.C0ENG[1].ts, state: "in_progress", date_created: now - 3600 }]
acme.vips = ["U0SAM"]
acme.pins = { C0GENERAL: [0], C0LAUNCH: [0] }
acme.directory = [{ id: "C0BOOK", name: "book-club", num_members: 7, purpose: { value: "One book a month, no spoilers" } }, { id: "C0MUSIC", name: "music", num_members: 15, purpose: { value: "What's on your headphones" } }]
acme.snoozed = { U0PRIYA: now + 3600 }
acme.active = ["U0PRIYA", "U0SAM", "U0DIEGO", "U0NOAH", ME]
acme.threads = ["C0ENG/" + ts(9000), "C0GENERAL/" + ts(86400 + 500)]
// What happens live (demoEvents): reactions to your message in
// #engineering, and a DM.
acme.live = {
  react: { channel: "C0ENG", ts: ts(8100), by: [["U0PRIYA", "partyparrot"], ["U0SAM", "tada"], ["U0DIEGO", "heart"], ["U0NOAH", "rocket"], ["U0HANA", "fire"]] },
  message: { channel: "D0PRIYA", user: "U0PRIYA", text: "Could you take a look at the final mockups in <#C0DESIGN> before standup? :sparkles:" }
}

// ---------------------------------------------------------------- Side Projects

var side = { id: "T0SIDE", name: "Side Projects", domain: "sideprojects" }
side.users = [
  person(ME, "alex", "Alex Morgan", "Maker", alex),
  person("U0KAI", "kai", "Kai Jensen", "Hardware tinkerer", { bg: "#6c8cff", skin: "#f3d5c0", hair: "#9a5b2e", shirt: "#2e2e3a", style: "curly" }),
  person("U0ROSA", "rosa", "Rosa Delgado", "Game developer", { bg: "#ef7aa0", skin: "#b9805a", hair: "#2a1a14", shirt: "#26515f", style: "bun" }),
  person("U0IVY", "ivy", "Ivy Chen", "Illustrator", { bg: "#59b98a", skin: "#f2d2b6", hair: "#141418", shirt: "#f6d36b", style: "long", glasses: true }),
  slackbot
]
side.convs = [
  { id: "C1GENERAL", name: "general", is_channel: true, is_general: true, is_member: true, num_members: 23 },
  { id: "C1IDEAS", name: "ideas", is_channel: true, is_member: true, num_members: 19, topic: { value: "Half-baked is welcome" } },
  { id: "C1KEYBOARDS", name: "keyboards", is_channel: true, is_member: true, num_members: 11 },
  { id: "D1KAI", is_im: true, user: "U0KAI" },
  { id: "D1ROSA", is_im: true, user: "U0ROSA" }
]
side.open = ["D1KAI", "D1ROSA"]
side.sections = [
  { channel_section_id: "L1CHAN", type: "channels", name: "", channel_ids_page: { channel_ids: [] } },
  { channel_section_id: "L1DMS", type: "direct_messages", name: "", channel_ids_page: { channel_ids: [] } }
]
side.history = {
  C1GENERAL: [{ user: "U0ROSA", ts: ts(86400 * 2), text: "Game jam this weekend, who's in? :video_game:" }],
  C1IDEAS: [{ user: "U0IVY", ts: ts(5000), text: "What if the plant watering bot sent a photo every morning? :seedling:" }],
  C1KEYBOARDS: [{ user: "U0KAI", ts: ts(86400 * 4), text: "Lubed the switches, it sounds like rain now :keyboard:" }],
  D1KAI: [{ user: "U0KAI", ts: ts(2400), text: "<@U0ME> the new PCB arrived! Soldering tonight?" }],
  D1ROSA: [{ user: "U0ROSA", ts: ts(86400 * 3), text: "Thanks for the shader tips!" }, { user: ME, ts: ts(86400 * 3 - 100), text: "Anytime :sparkles:" }]
}
side.replies = {}
side.counts = {
  C1IDEAS: { unread: true, mentions: 0, last_read: ts(6000) },
  D1KAI: { unread: true, mentions: 1, last_read: ts(3000) }
}
side.custom = {}
side.files = []
side.stars = []
side.saved = []
side.vips = []
side.pins = {}
side.directory = []
side.snoozed = {}
side.active = ["U0KAI", ME]
side.threads = []
side.live = null

var spaces = { T0DEMO: acme, T0SIDE: side }

// The signed-in accounts the demo pretends to have (Service).
var accounts = [acme, side].map(function(t) {
  return { teamId: t.id, demo: true, token: "", cookie: "", domain: t.domain, name: t.name, userId: ME, icon: "" }
})

// ---------------------------------------------------------------- live

// What the pretend socket says when asked (Service's demoEvent, e.g.
// `omarchy-shell omaslack demoEvent reaction`): "reaction", a few people
// reacting to one of your messages; "message", a new DM. The demo's own
// data takes them in too, so a reload still has them.
function events(kind, team, me) {
  var d = spaces[team]
  if (!d || !d.live) return []
  var at = Date.now() / 1000
  var stamp = function(n) { return String(Math.floor(at)) + "." + String(n).padStart(6, "0") }
  if (kind === "reaction") {
    var r = d.live.react
    var msg = (d.history[r.channel] || []).filter(function(m) { return m.ts === r.ts })[0]
    return r.by.map(function(pair, i) {
      if (msg) {
        var list = msg.reactions = msg.reactions || []
        var e = list.filter(function(x) { return x.name === pair[1] })[0]
        if (!e) list.push({ name: pair[1], users: [pair[0]], count: 1 })
        else if (e.users.indexOf(pair[0]) < 0) { e.users.push(pair[0]); e.count++ }
      }
      return { type: "reaction_added", user: pair[0], reaction: pair[1], item_user: me, item: { type: "message", channel: r.channel, ts: r.ts }, event_ts: stamp(i + 1) }
    })
  }
  if (kind === "message") {
    var l = d.live.message
    var m = { type: "message", channel: l.channel, user: l.user, text: l.text, ts: stamp(500), event_ts: stamp(500) }
    ;(d.history[l.channel] = d.history[l.channel] || []).push({ user: l.user, ts: m.ts, text: l.text })
    var k = d.counts[l.channel] = d.counts[l.channel] || { unread: false, mentions: 0, last_read: "0" }
    k.unread = true
    k.mentions++
    return [m]
  }
  return []
}

// ---------------------------------------------------------------- answers

function latestOf(d, id) {
  var h = d.history[id] || []
  return h.length ? h[h.length - 1].ts : ""
}

function respond(method, p, me, team) {
  var d = spaces[team] || acme
  switch (method) {
  case "auth.test": return { ok: true, url: "https://" + d.domain + ".slack.com/", team: d.name, user: "alex", team_id: d.id, user_id: ME }
  case "team.info": return { ok: true, team: { name: d.name, icon: { image_132: d === acme ? pics.acme : pics.side } } }
  case "users.list": return { ok: true, members: d.users }
  case "users.info": return { ok: true, user: d.users.filter(function(u) { return u.id === p.user })[0] || d.users[0] }
  case "users.conversations": return { ok: true, channels: d.convs }
  case "users.channelSections.list": return { ok: true, channel_sections: d.sections }
  case "stars.list": return { ok: true, items: d.stars }
  case "bots.info": {
    var bot = d.users.filter(function(u) { return u.is_bot && u.profile.bot_id === p.bot })[0]
    return bot ? { ok: true, bot: { id: p.bot, name: bot.profile.real_name, user_id: bot.id, icons: {} } } : { ok: false, error: "bot_not_found" }
  }
  case "files.list": {
    var mine = d.files.filter(function(f) { return !p.user || f.user === p.user })
    return { ok: true, files: mine, paging: { count: 100, total: mine.length, page: 1, pages: 1 } }
  }
  case "search.files": {
    var fq = String(p.query || "")
    var owner = (fq.match(/from:<@(\w+)>/) || [])[1] || ""
    var fileWords = fq.replace(/from:<@\w+>/g, "").replace(/\*/g, "").toLowerCase().split(/\s+/).filter(function(w) { return w })
    var fileHits = d.files.filter(function(f) {
      var t = f.title.toLowerCase()
      return (!owner || f.user === owner) && fileWords.length > 0 && fileWords.every(function(w) { return t.indexOf(w) >= 0 })
    })
    return { ok: true, files: { total: fileHits.length, paging: { count: 50, total: fileHits.length, page: 1, pages: 1 }, matches: fileHits } }
  }
  case "client.userBoot": return { ok: true, is_open: d.open, prefs: { show_sidebar_avatars: true } }
  case "client.counts": {
    var mentions = 0
    var out = { ok: true, channels: [], ims: [], mpims: [], threads: { has_unreads: d.threads.length > 0, mention_count: d.threads.length > 0 ? 1 : 0 }, activity_v2: { dm: 0, at_user: 0 } }
    d.convs.forEach(function(c) {
      var k = d.counts[c.id] || { unread: false, mentions: 0, last_read: latestOf(d, c.id) }
      var row = { id: c.id, latest: latestOf(d, c.id), last_read: k.last_read, has_unreads: k.unread, mention_count: k.mentions }
      ;(c.is_im ? out.ims : c.is_mpim ? out.mpims : out.channels).push(row)
      if (c.is_im) out.activity_v2.dm += k.unread ? 1 : 0
      else mentions += k.mentions
    })
    out.activity_v2.at_user = mentions
    return out
  }
  case "conversations.mark": {
    var seen = d.counts[p.channel]
    if (seen) { seen.unread = false; seen.mentions = 0; seen.last_read = p.ts || latestOf(d, p.channel) }
    return { ok: true }
  }
  case "users.prefs.get": return { ok: true, prefs: { all_notifications_prefs: JSON.stringify({ channels: { C0ALERTS: { muted: true } }, global: { global_desktop: "mentions_dms" } }) } }
  case "users.getPresence": return { ok: true, presence: d.active.indexOf(p.user || ME) >= 0 ? "active" : "away" }
  case "dnd.info": return { ok: true, snooze_enabled: false, dnd_enabled: false }
  case "dnd.teamInfo": {
    var dnd = {}
    for (var uid in d.snoozed) dnd[uid] = { snooze_enabled: true, snooze_endtime: d.snoozed[uid] }
    return { ok: true, users: dnd }
  }
  case "emoji.list": return { ok: true, emoji: d.custom }
  case "commands.list": return { ok: true, commands: [{ name: "/remind", type: "core", desc: "Set a reminder", usage: "[@someone or #channel] [what] [when]" }, { name: "/poll", type: "app", desc: "Start a quick poll", usage: "\"question\" \"option\" \"option\"", app_name: "Polls" }] }
  case "saved.list": return { ok: true, saved_items: d.saved }
  case "users.priority.list": return { ok: true, users: { vip: d.vips } }
  case "subscriptions.thread.getView": {
    var views = d.threads.map(function(key, i) {
      var at = key.split("/")
      var root = (d.history[at[0]] || []).filter(function(m) { return m.ts === at[1] })[0]
      var rs = d.replies[key] || []
      // The first one has a reply you haven't read.
      var read = rs[Math.max(0, rs.length - (i === 0 ? 2 : 1))]
      var rm = JSON.parse(JSON.stringify(root)); rm.channel = at[0]; rm.last_read = read ? read.ts : root.ts
      return { root_msg: rm, latest_replies: rs.slice(-3) }
    })
    return { ok: true, total_unread_replies: views.length ? 1 : 0, has_more: false, threads: views }
  }
  // Shaped like Slack's: references only, the messages come apart.
  case "activity.feed": {
    var want = String(p.types || "").split(",")
    var feed = []
    var add = function(type, unread, feedTs, key, item) { if (want.indexOf(type) >= 0) { item.type = type; feed.push({ is_unread: unread, feed_ts: feedTs, key: key, item: item }) } }
    d.convs.forEach(function(c) {
      var h = d.history[c.id] || []
      var k = d.counts[c.id]
      var theirs = h.filter(function(m) { return m.user !== ME })
      if ((c.is_im || c.is_mpim) && theirs.length) {
        var last = theirs[theirs.length - 1]
        add("dm", !!k && k.unread, last.ts, "dm-" + c.id, { bundle_info: { payload: { dm_entry: { latest_message: { ts: latestOf(d, c.id), channel: c.id } } } } })
      }
      h.forEach(function(m) {
        var unread = !!k && parseFloat(m.ts) > parseFloat(k.last_read)
        if (!c.is_im && (m.text || "").indexOf("<@" + ME + ">") >= 0)
          add("at_user", unread, m.ts, "at_user-" + c.id + "-" + m.ts, { message: { ts: m.ts, channel: c.id, author_user_id: m.user } })
        if (m.user === ME) (m.reactions || []).forEach(function(r) {
          var by = r.users.filter(function(u) { return u !== ME })[0]
          if (by) add("message_reaction", false, m.ts, "message_reaction-" + c.id + "-" + m.ts + "-" + r.name, { message: { ts: m.ts, channel: c.id }, reaction: { user: by, name: r.name } })
        })
      })
    })
    Object.keys(d.replies).forEach(function(key) {
      var rs = d.replies[key], at = key.split("/"), last = rs[rs.length - 1]
      add("thread_v2", false, last.ts, "thread_v2-" + at[0] + "-" + at[1], { bundle_info: { payload: { thread_entry: { channel_id: at[0], latest_ts: last.ts, thread_ts: at[1], unread_msg_count: 0 } } } })
    })
    if (String(p.unread_only) === "true") feed = feed.filter(function(i) { return i.is_unread })
    feed.sort(function(a, b) { return parseFloat(b.feed_ts) - parseFloat(a.feed_ts) })
    return { ok: true, items: feed.slice(0, 40) }
  }
  case "conversations.history": {
    var h = (d.history[p.channel] || []).slice()
    if (p.latest) h = h.filter(function(m) { return parseFloat(m.ts) < parseFloat(p.latest) || (p.inclusive && m.ts === p.latest) })
    if (p.oldest) h = h.filter(function(m) { return parseFloat(m.ts) > parseFloat(p.oldest) })
    h = h.reverse().slice(0, p.limit || 60)
    return { ok: true, messages: h, has_more: false }
  }
  case "conversations.replies": {
    var parent = (d.history[p.channel] || []).filter(function(m) { return m.ts === p.ts })[0]
    var rs = d.replies[p.channel + "/" + p.ts] || []
    return { ok: true, messages: (parent ? [parent] : []).concat(rs), has_more: false }
  }
  case "conversations.info": {
    var c = d.convs.filter(function(x) { return x.id === p.channel })[0]
    return c ? { ok: true, channel: c } : { ok: false, error: "channel_not_found" }
  }
  case "conversations.members": return { ok: true, members: d.users.filter(function(u) { return !u.is_bot }).map(function(u) { return u.id }) }
  case "conversations.list": return { ok: true, channels: d.convs.filter(function(c) { return c.is_channel }).concat(d.directory) }
  case "pins.list": return { ok: true, items: (d.pins[p.channel] || []).map(function(i) { return { type: "message", created: now - 3000, created_by: d.history[p.channel][i].user, message: d.history[p.channel][i] } }) }
  case "search.messages": {
    // Every word of the query, lit the way Slack marks them.
    var words = String(p.query || "").toLowerCase().replace(/\*/g, "").split(/\s+/).filter(function(w) { return w })
    var lit = words.length ? new RegExp("(" + words.map(function(w) { return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }).join("|") + ")", "ig") : null
    var hits = []
    Object.keys(d.history).forEach(function(cid) {
      d.history[cid].forEach(function(m) {
        var text = m.text || ""
        if (!lit || m.subtype || !words.every(function(w) { return text.toLowerCase().indexOf(w) >= 0 })) return
        var c = d.convs.filter(function(x) { return x.id === cid })[0]
        hits.push({ ts: m.ts, user: m.user, text: text.replace(lit, "$1"), files: m.files || [],
                    channel: { id: cid, name: c.name || "", is_im: !!c.is_im, is_mpim: !!c.is_mpim, is_private: !!c.is_private }, permalink: "https://" + d.domain + ".slack.com/archives/" + cid + "/p" + m.ts.replace(".", "") })
      })
    })
    hits.sort(function(a, b) { return parseFloat(b.ts) - parseFloat(a.ts) })
    return { ok: true, messages: { total: hits.length, paging: { pages: 1, total: hits.length }, matches: hits } }
  }
  case "chat.postMessage": {
    var m = { user: me, ts: String(Math.floor(Date.now() / 1000)) + ".000" + String(Math.floor(Math.random() * 900) + 100), text: p.text || "", blocks: p.blocks ? JSON.parse(p.blocks) : [] }
    if (p.thread_ts) m.thread_ts = p.thread_ts
    if (p.thread_ts && p.reply_broadcast) m.subtype = "thread_broadcast"
    if (p.thread_ts) (d.replies[p.channel + "/" + p.thread_ts] = d.replies[p.channel + "/" + p.thread_ts] || []).push(m)
    if (!p.thread_ts || p.reply_broadcast) (d.history[p.channel] = d.history[p.channel] || []).push(m)
    return { ok: true, ts: m.ts, message: m }
  }
  case "conversations.create": {
    var made = { id: "C0NEW" + String(Math.floor(Math.random() * 1e6)), name: p.name, is_channel: true, is_private: String(p.is_private) === "true",
                 is_member: true, created: Math.floor(Date.now() / 1000), creator: me }
    d.convs.push(made)
    return { ok: true, channel: made }
  }
  case "conversations.open": {
    var who = String(p.users || "").split(",").filter(function(x) { return x })
    var handle = function(id) { var u = d.users.filter(function(x) { return x.id === id })[0]; return u ? u.name : id }
    var found = who.length === 1 ? d.convs.filter(function(c) { return c.is_im && c.user === who[0] })[0] : null
    if (!found) {
      found = who.length === 1 ? { id: "D0" + who[0].slice(1), is_im: true, user: who[0] }
        : { id: "G0" + String(Math.floor(Math.random() * 1e6)), name: "mpdm-" + who.concat([me]).map(handle).join("--") + "-1", is_mpim: true, is_private: true }
      d.convs.push(found)
    }
    return { ok: true, channel: found }
  }
  case "chat.update": return { ok: true, ts: p.ts }
  // No socket: Workspace pretends one is up (connectSocket).
  case "client.getWebSocketURL": return { ok: false, error: "demo" }
  case "rtm.connect": return { ok: false, error: "demo" }
  default: return { ok: true }
  }
}
