# omaslack

A whole Slack client living inside the Omarchy shell, written as an Omarchy
plugin (QML, with a small Python helper for the network). The bar shows
Slack's mark with its badges; a click opens the window: Slack's layout (rail
of workspaces and tabs, sidebar sections, conversation, thread and profile
panes) drawn in the current Omarchy theme.

## Install

```sh
omarchy plugin add https://github.com/leonavas/omaslack --enable
```

Or from a checkout of your own:

```sh
git clone https://github.com/leonavas/omaslack
ln -s "$PWD/omaslack" ~/.config/omarchy/plugins/leonavas.omaslack
omarchy-shell shell rescanPlugins
omarchy plugin enable leonavas.omaslack --section right
```

Requirements: `python3` (network and websocket), `qt6-webengine` and Qt's
`qml` runtime for the sign-in window (`/usr/lib/qt6/bin/qml`), `curl`,
`notify-send`, `wl-clipboard`, `zenity` (file picker), `xdg-open`.

## Sign in

- **Sign in with Slack** opens Slack's own sign-in page in a window of its own;
  once you're in, the session (the browser token and its `d` cookie) is kept in
  `~/.config/omaslack/accounts.json` (mode 600) and only ever sent to Slack.
  The window's web cache is deleted when it closes; its cookies stay, so the
  next sign-in skips the password.
- **Sign in with a token** (the small link under it): `xoxc-…` with its
  `xoxd-…` cookie, or a `xoxp-…` user token.

Add more workspaces from the rail (the workspace icon → Add a workspace).

## What's there

Channels, DMs and group DMs in Slack's sidebar sections (starred, custom
sections with their emoji, Silenced; rename, new and delete from the section
menu), unread bars and mention badges; real time over Slack's websocket
(messages, edits, reactions, typing, presence, read state); a composer that
formats as you type (bold, italic, strike, code, code blocks, quotes, lists,
emoji pictures, mention pills) and sends Slack's rich text; threads (pane,
"also send to channel", the Threads view); reactions and the emoji picker
(Slack's emoji pictures, skin tones, custom and animated emoji); search
(Ctrl+K) with previews; apps and bots with their names, pictures and
profiles; files and images (inline, viewer, upload, pasted images); Block Kit
and attachments; message actions (edit, delete, forward, save for later,
remind, mark unread, pin, copy link, follow thread); slash commands; channel
details (topic, description, members, notifications, rename, archive,
convert, delete, invite); new message / channel; status, presence, pause
notifications, profile; workspaces stacked or expanded in the rail; DMs,
Activity and Later tabs; drafts; desktop notifications; keyboard shortcuts
(Ctrl+/); English and Portuguese; zoom (Ctrl+= / Ctrl+-).

## The bar

- **Icon.** Slack's mark, white with a faint outline by default (Color, Mono
  or a glyph in the settings); dimmed while signed out.
- **Badges.** Red at the bottom-right counts unread direct and group messages,
  plus thread replies that mention you. Blue at the top-right counts channel
  mentions, unread channels that notify you and new replies in threads you
  follow. "Group notifications" folds both into one red badge.
- **Hover preview.** The unread conversations with their messages (Slack's
  bold, italic and emoji), followed threads with new replies, and the
  reactions people put on your messages. A click jumps there.
- **Reaction bubbles** float out of the icon, except while paused.
- **Pause notifications** uses Slack's do-not-disturb (30 minutes, 1 hour,
  2 hours, until tomorrow, or a day and time); a pause you set swaps the
  badges for a bell-off mark.
- **Scratchpad parking.** The window lives in a special workspace (Omarchy's
  scratchpad by default): a click shows it, another puts it away. With
  "Launch in Foreground" off it opens straight there, in the background.

| Mouse | Action |
|---|---|
| Left click | Show the window, or put it away |
| Middle click | Close the window |
| Right click | The menu |
| Hover | Preview of what's unread |

IPC: `quickshell ipc -p $OMARCHY_PATH/shell call omaslack toggle`.

## Updates

omaslack looks for a new version on GitHub at start-up and every 6 hours;
the rail shows a button over your photo when there is one. Installed with
`omarchy plugin add`, a click runs `omarchy plugin update`; a checkout of
your own only tells you to `git pull`.

## Notes

The window is Quickshell's (app id `org.quickshell`, shared by every window
of the shell), so docks and taskbars show Quickshell's icon for it. It also
tags itself in Hyprland with `icon:<plugin>/assets/slack.svg`, for widgets
that read that tag.

Unofficial client, not affiliated with Slack Technologies.
