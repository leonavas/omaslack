# Developing Omaslack

## Run from your own checkout

```sh
git clone https://github.com/leonavas/omaslack
ln -s "$PWD/omaslack" ~/.config/omarchy/plugins/omaslack
omarchy-shell shell rescanPlugins
omarchy plugin enable omaslack --section right
```

After changing QML, restart the shell with `omarchy-restart-shell`: a plugin rescan keeps serving the old QML.

## Environment variables

- `SLACKQS_DEMO=1` runs the app against a pretend workspace (`lib/Demo.js`), so no sign-in is needed. The screenshots use it.
- `SLACKQS_OPEN=1` opens the window as soon as the shell starts.
- `SLACKQS_READONLY=1` only lets read methods reach Slack, for working against a real workspace safely.
- `SLACKQS_UPDATE_DEV=1` treats whatever is on GitHub as newer, so you can see the update button.

## The update screen

`bash lib/update.sh run --dry-run --mode=checkout --folder=. --from=0.2.0 --to=0.3.0` shows the update screen in your current terminal without running anything (`--mode=omarchy --id=omaslack` shows the other one).

An install made by `omarchy plugin add` (a git folder in Omarchy's plugin folder) updates with `omarchy plugin update <id>`, without `--yes`: Omarchy shows the diff and asks to confirm, and a no there leaves everything as it was.

A checkout (a symlink in Omarchy's plugin folder to a clone of this repo, with the plugin at its top) updates from the app with `git -C <folder> pull --ff-only` instead of `omarchy plugin update`, after a confirm of its own (`gum confirm`, else a plain y/N). A failure, such as local changes in the way or a branch that can't fast-forward, shows git's message and changes nothing. A copy that isn't in git can't be updated from the app; the button tells you where to get the new version.

The background check reads the setting `checkUpdates` (default on; "Check for updates" in Preferences → Advanced). The account menu's **Check for updates** works either way, and `SLACKQS_UPDATE_DEV=1` makes it find a "new" version.
