![Omaslack](docs/cover.png)

This is the app I use every day for work. My company adopted Slack as its main communication tool, so for every little detail I see out of tune, expect a fix.

# Omaslack

**An unofficial Slack client that lives inside the Omarchy shell, drawn in your theme's colors, with a bar widget that badges what's waiting.**

Omaslack is an [Omarchy](https://omarchy.org) shell plugin written in QML (Quickshell), with a small Python helper for the network. It shows up as Slack's mark in the Omarchy bar. Click it and a window opens with Slack's familiar layout: the workspace rail, sidebar sections, conversations, threads and profiles, all in the current Omarchy theme. Inside the app it's simply called "Slack". It is not affiliated with or endorsed by Slack (see [Credits and disclaimer](#credits-and-disclaimer)).

## Features

### The client
- **Sidebar like Slack's**: starred, custom sections with their emoji, Silenced, Channels, DMs and Apps. You can rename, create and delete sections and drag conversations between them. Unread bars and mention badges are shown, and an *Unreads* switch filters the lists.
- **Real time** over Slack's websocket: messages, edits, reactions, typing, presence and read state.
- **WYSIWYG composer** with a formatting toolbar (bold, italic, underline, strike, code, links, lists, quotes, code blocks). Slack markdown turns into formatting as you type. Mentions appear as pills and emoji as pictures. Autocomplete covers `:emoji:`, `@people`, `#channels` and `/commands`. You can attach files or paste images. Messages go out as Slack rich text, and you can edit them in place.
- **Animated custom emoji** play in messages, in reactions and inside the composer. Slack's emoji set is included, with skin tones and the workspace's custom emoji. You can switch to your system emoji font instead.
- **Threads**: a side pane, "also send to channel", and a Threads view of the threads you follow.
- **Ctrl+K search**: a quick switcher for conversations and people, plus Slack's message search with previews and its modifiers (`in:`, `from:`, `has:`, `before:`, `after:`). Deactivated people show up too, and opening one shows the **archives of the deactivated account** (their DM, read-only).
- **Files**: a rail item with a hover card of recent and starred files, and a full page with All / Created by you / Shared with you, type filters, sorting, search, download and star.
- **DMs, Activity and Later** tabs in the rail, each with a hover card, plus Drafts.
- **Message actions**: edit, delete, forward, save for later, remind, mark unread, pin, copy link, and turning reply notifications on or off for a thread.
- **Rich content**: Block Kit, attachments, apps and bots with their names and pictures, inline images and an image viewer.
- **Channels**: details (topic, description, members, notifications), rename, archive, convert, delete, invite, browse channels, and new channel or new message.
- **You**: status, away or active, pausing notifications (Slack's do-not-disturb), and editing your profile.
- **Multiple workspaces**, stacked or expanded in the rail. Ctrl+Tab and Ctrl+1…9 switch between them.
- **English and Portuguese (Brazil) UI**, chosen from your `LANG` or set in Preferences.
- Keyboard shortcuts close to Slack's (Ctrl+/ shows them all), zoom (Ctrl+= / Ctrl+- / Ctrl+0), compact or comfortable spacing, and a 12h or 24h clock.
- **In-app updater**: a green button over your photo when a new version is out (see [Updates](#updates)).

### The bar widget

![Reactions floating up from the bar icon](docs/bar-reactions.gif)

- **Icon**: Slack's mark, white with a faint outline by default. Color, Mono or any Nerd Font glyph are also available. It's dimmed while you're signed out.
- **Badges**: the red one (bottom-right) counts unread DMs and group DMs, plus thread replies that mention you. The blue one (top-right) counts channel mentions, unread channels that notify you, and new replies in threads you follow. *Group notifications* folds both into one badge.
- **Hover preview**: unread conversations with their newest messages (rendered with Slack's formatting and emoji), followed threads with new replies, and the reactions people put on your messages. Click a row to jump there.
- **Desktop notifications**: one for each message that notifies you in Slack and for each reaction to your messages, with the sender's photo. They're skipped while you're paused, and for the conversation you have on screen. Clicking one opens the conversation at that message, through Omarchy's notification center.
- **Reaction emoji float up** out of the bar icon whenever someone reacts to one of your messages.
- **Scratchpad parking**: the window lives in a Hyprland special workspace (Omarchy's scratchpad by default). One click shows it and another puts it away.
- **Right-click menu**: Launch on Login, Launch in Foreground, Open in Scratchpad, Group notifications, Channel mentions only, Show threads, Show reactions, Desktop notifications, pause or resume notifications, away or active, status, Mark all as read, Preferences, and Close Slack.

| Mouse | Action |
|---|---|
| Left click | Show the window, or put it away |
| Middle click | Close the window |
| Right click | The menu |
| Hover | Preview of what's unread |

## Screenshots

| | |
|---|---|
| ![Main window](docs/screenshots/main-window.png) | ![Ctrl+K search](docs/screenshots/search.png) |
| **Main window**: channels, threads, reactions, the rich composer | **Ctrl+K search** with highlighted matches and a preview |
| ![Files](docs/screenshots/files.png) | ![Bar hover card](docs/screenshots/bar-hover-card.png) |
| **Files**: everything shared with you, searchable | **Bar preview**: what's waiting, without opening the app |
| ![DMs hover card](docs/screenshots/dms-hover-card.png) | ![Activity hover card](docs/screenshots/activity-hover-card.png) |
| **DMs** at a glance from the rail | **Activity**: mentions, replies and reactions |

![Notification](docs/screenshots/notification.png)

*All screenshots use the built-in demo workspace (`SLACKQS_DEMO=1`); every name and message is made up.*

## Install

```sh
omarchy plugin add https://github.com/leonavas/omaslack --enable
```

That's all. On a stock Omarchy it works right after install, with no extra packages and no manual setup: Slack's mark shows up in the bar, and you sign in from inside the app (see [How sign-in works](#how-sign-in-works)). To add more workspaces, click the workspace icon in the rail and choose **Add a workspace**.

The window opens in the scratchpad by default, a layer over your current workspace; a click on the bar icon shows or hides it. To have it open as a normal window instead, turn off **Open in Scratchpad** in the bar icon's right-click menu.

### Requirements

Nothing beyond what ships with Omarchy. The network helper is Python using only its standard library, and everything else it calls is already on the system:

| Tool | What it's for |
|---|---|
| `python3` | HTTPS and the websocket to Slack (`lib/transport.py`, standard library only) |
| Qt's QML runtime, with QtWebEngine | The app itself, and the sign-in window |
| `curl` | Profile photos and the update check |
| `jq` | Reading Hyprland's state in a small shell helper |
| `notify-send` | Desktop notifications |
| `wl-clipboard` | Copying, and pasting images into the composer |
| `xdg-open` | Opening links and downloaded files |
| `omarchy-file-select` | Choosing files to attach and a profile photo |
| `pw-play` | The notification sound |
| `hyprctl` | Parking the window in the scratchpad and bringing it back |

If the sign-in window can't open, **Sign in with a token** works without it. Files are chosen with Omarchy's own chooser (`omarchy-file-select`); `zenity` is an optional fallback for when that one is missing or can't open.

### Remove

```sh
omarchy plugin remove omaslack
```

That removes the plugin but leaves your data. To delete that too (your sessions, preferences, drafts, caches and the sign-in window's profile):

```sh
rm -rf ~/.config/omaslack ~/.cache/omaslack ~/.local/share/omaslack
```

If you set `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` or `XDG_DATA_HOME`, the folders are under those instead. Removing the files doesn't end your sessions on Slack's servers (see [Signing out](#signing-out)).

## How sign-in works

- **Sign in with Slack** opens Slack's own sign-in page (`slack.com`, `<workspace>.slack.com`, `app.slack.com`) in a dedicated browser window with its own profile, kept in `~/.local/share/omaslack/webview`. You sign in there as you would in a browser, single sign-on included. Once you're in, Omaslack reads the session token (`xoxc-…`) from that window's local storage and the `d` cookie from that profile's own cookie database. It never looks at your browsers or at the Slack desktop app. The window's web cache is deleted when it closes; its cookies stay, so the next sign-in skips the password. The window runs with Chromium's sandbox on (`QTWEBENGINE_DISABLE_SANDBOX` is cleared for it); if it can't start on your system, sign in with a token instead.
- **Sign in with a token** (the small link below the button) takes a `xoxc-…` token with its `xoxd-…` cookie, or a `xoxp-…` user token, pasted in by hand.

Either way, the credentials are saved to `~/.config/omaslack/accounts.json` with mode 600, written in one step (a private temporary file renamed over it), so the file is never readable by others or left half-written. When the app starts, its config, cache and data folders are set to mode 700. The credentials are only ever sent to `slack.com` hosts.

The sign-in window and the backend identify themselves to Slack as a current desktop Chrome (the version is computed from today's date), because Slack's pages refuse browsers it considers outdated.

Omaslack acts as Slack's web client: it talks to Slack with your own session, through the internal APIs Slack's web app uses, not the public bot API. Your workspace's policy may not allow third-party clients, so check with your admin before using it on a work account. Omaslack is not affiliated with or endorsed by Slack.

## Network

Every host Omaslack connects to:

| Host | Why |
|---|---|
| `slack.com/api` | Slack's Web API, with your session |
| `slack.com`, `<workspace>.slack.com`, `app.slack.com` | Sign-in (the sign-in window only) |
| `wss-*.slack.com` | Slack's websocket, for real-time updates |
| `files.slack.com` and Slack's upload URLs | Files and images you open, download, upload or paste |
| `a.slack-edge.com`, `emoji.slack-edge.com` and Slack's avatar CDNs (`*.slack-edge.com`, `secure.gravatar.com`) | Emoji images, custom emoji, profile photos and workspace icons |
| Your SSO provider | Only if your workspace signs in through one, inside the sign-in window |
| Third-party hosts in messages | Images in link previews, Block Kit and attachments load straight from their own sites, which see your connection. Turn off **Load images from link previews** (Preferences → Messages & media) and only Slack's own images load (`slack.com`, `slack-edge.com` and its image proxy `slack-imgs.com`) |
| `raw.githubusercontent.com/leonavas/omaslack` | The update check (one plain file; **Check for updates** in Preferences → Advanced turns it off) |
| `github.com` | Only when you start an update: Omarchy fetches the new version and shows its changes before you confirm |

Your credentials only go to `slack.com` and its subdomains; requests to every other host carry none. There's no telemetry and no analytics, and nothing is downloaded to run: no binaries, no packages.

## Data stored

| Path | Contents |
|---|---|
| `~/.config/omaslack/accounts.json` | Your credentials (tokens and cookies), mode 600, replaced in one step on every save |
| `~/.config/omaslack/settings.json` | Preferences, drafts, recently sent messages and the last conversation you had open |
| `~/.cache/omaslack/team-<id>.json` | Per workspace: recent messages of your recent conversations and the user directory, so the app starts fast |
| `~/.cache/omaslack/files/<team>/` | Images and files fetched with your session |
| `~/.cache/omaslack/files/avatars/` | Profile photos and workspace icons |
| `~/.cache/omaslack/paste/` | Images you pasted into the composer |
| `~/.cache/omaslack/webview/` | The sign-in window's web cache, deleted when the window closes |
| `~/.local/share/omaslack/webview/` | The sign-in window's browser profile (cookies and storage, so the next sign-in skips the password) |
| `$XDG_RUNTIME_DIR/omaslack-update.*` | How the last update went, read back once the shell restarts |
| `~/Downloads` (or `$XDG_DOWNLOAD_DIR`) | Files you download. Nothing there is overwritten: a name already taken becomes `name (1).ext`, `name (2).ext`… |

Cached files and photos unused for 7 days, and pasted images older than 7 days, are deleted. The config, cache and data folders are set to mode 700 when the app starts. The XDG variables (`XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`) are respected. Preferences → Advanced opens these folders.

## Links and files

- Links in messages open in your browser only when they're web pages or mail (`http`, `https`, `mailto`). Slack permalinks to the workspace you're in open in the app. Any other kind of link (`file:`, other apps' schemes) isn't opened.
- A received file opens in its default app, except one that could run programs (scripts, `.desktop` launchers, executables, or anything marked executable): for those, its folder opens instead.
- Downloads never overwrite a file already in your downloads folder (see [Data stored](#data-stored)).

## Signing out

Signing out of a workspace deletes, on this computer:

- that account's credentials, from `accounts.json`;
- its cache file (`~/.cache/omaslack/team-<id>.json`) and its cached files (`~/.cache/omaslack/files/<team>/`);
- its drafts, recently sent messages, last conversation and collapsed sections, from `settings.json`.

Signing out of the last workspace also deletes the sign-in window's browser profile (`~/.local/share/omaslack/webview`) and its cache (`~/.cache/omaslack/webview`), so the next sign-in starts from scratch.

It does not end the session on Slack's servers: do that from your account settings in Slack.

## Settings

- **App preferences** (Ctrl+, or the menu): notifications, the notification sound (none or one of ten bundled sounds, each with a play button to preview it) and message preview, sidebar look, workspaces stacked or expanded, clock, spacing, emoji style, the formatting toolbar, images from link previews, language, zoom, update checks, your workspaces, and where the app keeps its data.
- **Bar widget settings** are in the shell's widget settings panel. You can also set them inline on the widget's entry in `~/.config/omarchy/shell.json`, for example:

  ```json
  { "id": "omaslack", "badgeLayout": "Combined", "previewMessages": 5 }
  ```

  The available keys are listed in [`manifest.json`](manifest.json) (`barWidget.schema`): icon style, badge layout and colors, what the channel badge counts, hide mode and special workspace, auto start, hover preview size, threads, reactions, notifications, and the paused indicator.

## IPC

```sh
quickshell ipc -p "$OMARCHY_PATH/shell" call omaslack <command> [args]
```

| Command | What it does |
|---|---|
| `toggle` | Show the window, or put it away |
| `show` / `hide` | Show or hide the window |
| `open <url>` | Open a Slack permalink in the app (anything else goes to the browser) |
| `openAt <team> <conv> <ts>` | Open a conversation at a message |
| `openThread <team> <conv> <ts> <threadTs>` | Open a thread at a reply |
| `pause <minutes>` | Pause notifications in every workspace |
| `resume` | Resume notifications |
| `status` | Print JSON: signed in, what's waiting, paused, workspaces |
| `demoEvent reaction\|message` | Demo mode only: play a pretend reaction or message |

## Updates

Omaslack checks the `manifest.json` on GitHub's `main` branch (`raw.githubusercontent.com/leonavas/omaslack`) a little after start-up and every 6 hours. Only that plain file is fetched, and nothing of yours is sent. The automatic check is on by default; **Check for updates** in Preferences → Advanced turns it off. **Check for updates** in your account menu checks on demand either way. When a newer version exists, a green button shows over your photo in the rail.

Nothing is updated until you confirm. Clicking the button (or **Update to …** in your account menu or in About) opens the same floating terminal Omarchy uses for its own update. It shows the current and the new version, a **What's new** link to the [releases page](https://github.com/leonavas/omaslack/releases), and the exact command it will run: `omarchy plugin update omaslack`, Omarchy's own plugin update, which shows the changes and asks you to confirm. Say no (or close the terminal) and nothing changes. Say yes and it runs with its output in view, followed by a line saying whether it worked; a failure changes nothing. Once it updated, the whole shell restarts with `omarchy-restart-shell`, as Omarchy's own update ends; the new copy brings the window back and tells you how it went. Press any key to close the terminal.

Installed before 0.5.0? The plugin was then called `leonavas.omaslack`, and after updating its bar icon disappears because the id is now `omaslack`. Move it to the new id once, keeping your bar settings:

```
mv ~/.config/omarchy/plugins/leonavas.omaslack ~/.config/omarchy/plugins/omaslack
sed -i 's/"leonavas.omaslack"/"omaslack"/' ~/.config/omarchy/shell.json
omarchy-restart-shell
```

The screen is `lib/update.sh`. It falls back to `xdg-terminal-exec` or `$TERMINAL` when Omarchy's terminal helper is missing. A development checkout updates with `git pull --ff-only` instead, after a confirm of its own (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)).

## Environment variables

| Variable | What it does |
|---|---|
| `SLACKQS_DEMO=1` | Demo mode: the app runs against a pretend workspace with made-up data (`lib/Demo.js`), and nothing reaches Slack |
| `SLACKQS_OPEN=1` | Opens the window as soon as the shell starts |
| `SLACKQS_READONLY=1` | Only lets read methods reach Slack, for development against a real workspace |
| `SLACKQS_UPDATE_DEV=1` | Treats whatever is on GitHub as newer, to see the update button |

Working on Omaslack itself is described in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Notes

- The window belongs to Quickshell (app id `org.quickshell`, shared by every window of the shell), so docks and taskbars show Quickshell's icon for it. It also tags itself in Hyprland with `icon:<plugin>/assets/slack.svg`, for widgets that read that tag.
- Not supported yet: huddles and calls, and keyword notifications (Slack's "My keywords").

## Credits and disclaimer

Made by [leonavas](https://github.com/leonavas). Licensed under the [Apache License 2.0](LICENSE).

Emoji images are loaded from Slack's CDN at runtime; none are bundled. The emoji metadata in `lib/EmojiData.js` (names, aliases, groups, order and skin tones) comes from [iamcal/emoji-data](https://github.com/iamcal/emoji-data), the set Slack uses, and [github/gemoji](https://github.com/github/gemoji), both under the MIT license (see [NOTICE](NOTICE)).

Notification sounds generated with ElevenLabs Sound Effects and edited for Omaslack; distributed under the project license.

Omaslack is an **unofficial** Slack client. It is not affiliated with, endorsed by or sponsored by Slack Technologies, LLC or Salesforce, Inc. "Slack" and the Slack logo are trademarks of Slack Technologies, LLC. Use it in line with your workspace's policies.
