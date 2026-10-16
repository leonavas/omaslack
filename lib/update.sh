#!/usr/bin/env bash

# Omaslack's update screen, shown the way Omarchy shows its own update
# (omarchy-update): the floating terminal with Omarchy's logo, a box with
# both versions and the exact command, the command with its output in view
# (`omarchy plugin update` shows the changes and asks itself; a pull of your
# own checkout is asked here, with gum's confirm), a line saying how it
# went, and a key to close. A no closes it: 130, which Omarchy's wrapper
# takes as nothing to wait on.
# core/Updater.qml calls `open`, which opens the terminal and `run`s in it.
#
#   update.sh open|run --mode=omarchy|checkout --id=<plugin id> --folder=<dir>
#     --from=<version> --to=<version> [--base=<path prefix>] [--note=<json>]
#     [--lang=en|pt-BR] [--repo=<url>] [--dry-run]
#
# How it went goes to <base>.* for whichever copy of the plugin is running
# once it's done (an update restarts the shell halfway through): the note
# (.json, from `open`), the pid of the run (.pid: the terminal is still
# open), the command's output (.log) and its exit code (.rc; 130: no).
# --dry-run runs nothing and writes none of them.

have() { command -v "$1" >/dev/null 2>&1; }

# The app's language (Preferences), else English.
t() { case $lang in pt*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }

green() { printf '\033[32m%s\033[0m\n' "$@"; }
red() { printf '\033[0;31m%s\033[0m\n' "$@"; }

# The top-level version (the manifest's first "version" key).
manifest_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$folder/manifest.json" 2>/dev/null | head -n 1
}

# ---------------------------------------------------------------- open
# Omarchy's floating terminal with its presentation (logo first, "Done!
# Press any key" last); else a plain one, where `run` does both itself.
# Forked off, so the app's process is done at once, and in uwsm's own
# scope, so the shell restart that comes with the update can't take it along.
open_terminal() {
  local self cmd term=()
  self=$(readlink -f -- "${BASH_SOURCE[0]}")
  if [ -z "$dry" ]; then
    printf '%s\n' "$note" >"$base.json" || return 1
    rm -f -- "$base.rc" "$base.log" "$base.pid"
  fi
  if have omarchy-launch-floating-terminal-with-presentation; then
    cmd=$(printf '%q ' bash "$self" run "$@")
    setsid -f omarchy-launch-floating-terminal-with-presentation "$cmd" >/dev/null 2>&1 </dev/null
    return 0
  fi
  if have xdg-terminal-exec; then
    term=(xdg-terminal-exec --app-id=org.omarchy.terminal --title=Omarchy -e)
  elif [ -n "${TERMINAL:-}" ] && have "${TERMINAL%% *}"; then
    read -ra term <<<"$TERMINAL"
    term+=(-e)
  else
    [ -n "$dry" ] || rm -f -- "$base.json"
    echo "update.sh: no terminal to open (xdg-terminal-exec or \$TERMINAL)" >&2
    return 127
  fi
  have uwsm-app && term=(uwsm-app -- "${term[@]}")
  setsid -f "${term[@]}" bash "$self" run --standalone "$@" >/dev/null 2>&1 </dev/null
}

# ---------------------------------------------------------------- run
# gum's confirm, as Omarchy asks; else a plain y/N.
confirm() {
  if have gum; then
    gum confirm "$1"
    return
  fi
  local answer
  read -r -p "$1 [$(t y s)/N] " answer </dev/tty || return 1
  case $answer in [yYsS]*) return 0 ;; esac
  return 1
}

# Omarchy's update asks only on a terminal (stdin and stdout both), so its
# output is kept through script(1)'s terminal rather than a pipe; the log
# without script's own lines, the colors and the carriage returns.
in_tty() {
  local rc
  if ! have script; then
    : >"$base.log"
    "$@"
    return
  fi
  SHELL=$BASH script -qec "$(printf '%q ' "$@")" "$base.tty"
  rc=$?
  LC_ALL=C sed -e 's/\x1b\][^\x07]*\x07//g' -e 's/\x1b\[[0-?]*[ -\/]*[@-~]//g' -e 's/\r//g' \
    -e '/^Script \(started\|done\) on /d' -- "$base.tty" >"$base.log" 2>/dev/null
  rm -f -- "$base.tty"
  return "$rc"
}

# The exit code for whoever picks it up, and Omarchy's key to close when
# its wrapper isn't there to ask.
finish() {
  trap - HUP INT TERM
  [ -n "$dry" ] || { rm -f -- "$base.tty"; echo "$1" >"$base.rc"; }
  if [ -n "$standalone" ] && [ "$1" -ne 130 ]; then
    if have omarchy-show-done; then
      omarchy-show-done
    else
      printf '\n%s' "$(t "Done! Press any key to close..." "Pronto! Aperte qualquer tecla para fechar...")"
      read -rsn 1 </dev/tty
      echo
    fi
  fi
  exit "$1"
}

# ---------------------------------------------------------------- the id
# A copy installed before the plugin's id changed (leonavas.omaslack, now
# omaslack) sits in a folder named after the old id, and shell.json puts
# its widget on the bar by that id: with the new manifest in, the shell
# knows the plugin by the new one, so the widget would drop off the bar and
# `omarchy plugin update <id>` would no longer find it. So, after an update
# Omarchy made (never a checkout of your own), the folder moves to the new
# id and every mention of the old id in shell.json follows: a backup of it
# next to it first, then the new file written whole and put in place in one
# step. Not when a folder by the new name is there already. Anything wrong
# and nothing is touched; it says how to do it by hand.
step() {
  printf '%s\n' "$@"
  [ -n "$dry" ] || printf '%s\n' "$@" >>"$base.log"
}

migrate_id() {
  local plugins=$HOME/.config/omarchy/plugins shell=$HOME/.config/omarchy/shell.json
  local new src dest backup="" tmp="" manual
  new=$(jq -r '.id // empty' "$folder/manifest.json" 2>/dev/null)
  [ -n "$new" ] && [ "$new" != "$id" ] || return 0
  src=$plugins/$id dest=$plugins/$new
  # The real file, should shell.json be a link (dotfiles kept elsewhere).
  [ ! -L "$shell" ] || shell=$(readlink -f -- "$shell")
  manual=$(t "To do it by hand: mv $src $dest, replace \"$id\" with \"$new\" in $shell, then run omarchy-restart-shell." \
    "Para fazer à mão: mv $src $dest, troque \"$id\" por \"$new\" em $shell e depois rode omarchy-restart-shell.")
  echo
  if ! [[ $new =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $new != *..* ]] || { [ ! -e "$src" ] && [ ! -L "$src" ]; }; then
    red "$(t "The plugin's id is now $new, but it couldn't be moved by itself." "O id do plugin agora é $new, mas não foi possível movê-lo sozinho.")" "$manual"
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    red "$(t "The plugin's id is now $new, and $dest is there already: nothing was moved." "O id do plugin agora é $new, e $dest já existe: nada foi movido.")" "$manual"
    return 1
  fi
  [ ! -f "$shell" ] || backup=$shell.bak.omaslack-$(date +%Y%m%d-%H%M%S)
  step "$(t "The plugin's id changed from $id to $new: moving $src to $dest" "O id do plugin mudou de $id para $new: movendo $src para $dest")"
  [ -z "$backup" ] ||
    step "$(t "and renaming it in $shell (backup: $backup)" "e renomeando no $shell (cópia: $backup)")"

  # shell.json rewritten beside it before anything moves: the old id as a
  # whole word (an entry's id, its "<id>#2" copies, a key, a path), in keys
  # and values alike.
  if [ -n "$backup" ]; then
    tmp=$(mktemp -- "$shell.XXXXXX") &&
      jq --arg pat "(?<![A-Za-z0-9._-])${id//./\\.}(?![A-Za-z0-9._-])" --arg new "$new" '
        def re: gsub($pat; $new);
        walk(if type == "object" then with_entries(.key |= re) elif type == "string" then re else . end)' \
        "$shell" >"$tmp" && jq -e . "$tmp" >/dev/null && chmod --reference="$shell" -- "$tmp" &&
      cp -p -- "$shell" "$backup" || {
      [ -z "$tmp" ] || rm -f -- "$tmp"
      [ -z "$backup" ] || rm -f -- "$backup"
      red "$(t "Couldn't rewrite $shell: nothing was changed." "Não foi possível reescrever o $shell: nada foi mudado.")" "$manual"
      return 1
    }
  fi
  if ! mv -T -- "$src" "$dest"; then
    [ -z "$tmp" ] || rm -f -- "$tmp" "$backup"
    red "$(t "Couldn't move $src: nothing was changed." "Não foi possível mover $src: nada foi mudado.")" "$manual"
    return 1
  fi
  if [ -n "$tmp" ] && ! mv -f -- "$tmp" "$shell"; then
    mv -T -- "$dest" "$src"
    rm -f -- "$tmp" "$backup"
    red "$(t "Couldn't write $shell: nothing was changed." "Não foi possível gravar o $shell: nada foi mudado.")" "$manual"
    return 1
  fi
  [ -d "$folder" ] || folder=$dest
  id=$new
  step "$(t "Moved: Omaslack is now $new, with its place on the bar." "Movido: o Omaslack agora é $new, com o seu lugar na barra.")"
}

run_update() {
  local cmd shown before after rc now declined=""
  case $mode in
  omarchy) cmd=(omarchy plugin update "$id") ;;
  checkout) cmd=(git -C "$folder" pull --ff-only) ;;
  *)
    red "update.sh: unknown install mode '$mode'"
    finish 2
    ;;
  esac
  shown=$(printf '%q ' "${cmd[@]}")
  shown=${shown% }

  # Closing the window (HUP) or Ctrl+C is a no too.
  if [ -z "$dry" ]; then
    echo $$ >"$base.pid"
    trap 'finish 130' HUP INT TERM
  fi
  [ -z "$standalone" ] || clear

  local lines=(
    "$(t "Update Omaslack?" "Atualizar o Omaslack?")"
    ""
    "• $(t "Current version" "Versão atual"): ${from:-?}"
    "• $(t "New version" "Versão nova"): ${to:-?}"
    "• $(t "The shell then restarts, and Slack's window comes back" "Depois o shell reinicia, e a janela do Slack volta")"
    ""
    "$(t "Command:" "Comando:")"
    "$shown"
    ""
    "$(t "What's new" "Novidades"): $repo/releases"
  )
  [ "$mode" != omarchy ] ||
    lines=("${lines[@]:0:5}" "• $(t "Omarchy shows the changes, then asks to confirm" "O Omarchy mostra as mudanças e depois pede para confirmar")" "${lines[@]:5}")
  if have gum; then
    gum style --border normal --padding "1 2" "${lines[@]}"
  else
    printf '  %s\n' "${lines[@]}"
  fi
  echo

  # Omarchy's update asks itself (the same prompt as for any plugin); only
  # a pull of your own checkout is asked here.
  if [ "$mode" = checkout ] && ! confirm "$(t "Continue with update?" "Continuar com a atualização?")"; then
    t "Update cancelled" "Atualização cancelada"
    echo
    finish 130
  fi

  echo
  printf '\033[2m$ %s\033[0m\n' "$shown"
  before=$(git -C "$folder" rev-parse HEAD 2>/dev/null)
  if [ -n "$dry" ]; then
    t "Dry run: nothing was run." "Simulação: nada foi rodado."
    echo
    rc=0
  elif [ "$mode" = omarchy ]; then
    in_tty "${cmd[@]}"
    rc=$?
  else
    "${cmd[@]}" 2>&1 | tee -- "$base.log"
    rc=${PIPESTATUS[0]}
  fi
  after=$(git -C "$folder" rev-parse HEAD 2>/dev/null)

  # A no at Omarchy's prompt: it says "Skipped" and ends well, with what it
  # fetched still ahead of this copy; or Ctrl+C in it.
  if [ "$mode" = omarchy ] && [ -z "$dry" ]; then
    [ "$rc" -ne 130 ] || declined=1
    [ "$rc" -ne 0 ] || [ "$before" != "$after" ] ||
      [ "$(git -C "$folder" rev-parse -q --verify FETCH_HEAD 2>/dev/null)" = "$after" ] || declined=1
  fi
  if [ -n "$declined" ]; then
    echo
    t "Update cancelled" "Atualização cancelada"
    echo
    finish 130
  fi

  # A copy from before the id changed takes the new one, before the restart.
  if [ "$mode" = omarchy ] && [ "$rc" -eq 0 ] && [ -z "$dry" ] && [ "$before" != "$after" ]; then
    migrate_id
  fi

  # Once it pulled something, the whole shell restarts, as omarchy-update
  # ends: a rescan of the plugins (what `omarchy plugin update` does) keeps
  # serving the old QML of files changed in place. This terminal is in a
  # session of its own and stays; only without the restart, the rescan.
  if [ "$rc" -eq 0 ] && [ -z "$dry" ] && [ "$before" != "$after" ]; then
    printf '\n\033[32m%s\033[0m\n' "$(t "Restarting the shell" "Reiniciando o shell")"
    if have omarchy-restart-shell; then
      omarchy-restart-shell ||
        red "$(t "Couldn't restart the shell: run omarchy-restart-shell" "Não foi possível reiniciar o shell: rode omarchy-restart-shell")"
    else
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 ||
        red "$(t "Couldn't reload the plugin: run omarchy-shell shell rescanPlugins" "Não foi possível recarregar o plugin: rode omarchy-shell shell rescanPlugins")"
    fi
  fi

  now=$(manifest_version)
  echo
  if [ "$rc" -ne 0 ]; then
    red "$(t "The update didn't go through (exit $rc)." "A atualização não foi feita (saída $rc).")" \
      "$(t "Review the output above, correct the error and try again." "Revise a saída acima, corrija o erro e tente de novo.")"
  elif [ -n "$dry" ]; then
    green "$(t "Nothing changed." "Nada mudou.")"
  elif [ "$before" = "$after" ]; then
    green "$(t "Omaslack is already up to date (${now:-$from})." "O Omaslack já está atualizado (${now:-$from}).")"
  else
    green "$(t "Omaslack updated: ${from:-?} → ${now:-$to}. The shell restarted with it." "Omaslack atualizado: ${from:-?} → ${now:-$to}. O shell reiniciou com ele.")"
  fi
  finish "$rc"
}

# ---------------------------------------------------------------- main
main() {
  local action=${1:-}
  shift
  mode="" id="" folder="" from="" to="" note="{}" dry="" standalone=""
  lang=en
  repo=https://github.com/leonavas/omaslack
  # The session's runtime folder, else a private one in the cache.
  base=${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omaslack}/omaslack-update
  local arg opts=()
  for arg in "$@"; do
    case $arg in
    --mode=*) mode=${arg#*=} ;;
    --id=*) id=${arg#*=} ;;
    --folder=*) folder=${arg#*=} ;;
    --from=*) from=${arg#*=} ;;
    --to=*) to=${arg#*=} ;;
    --base=*) base=${arg#*=} ;;
    --note=*) note=${arg#*=} ;;
    --lang=*) lang=${arg#*=} ;;
    --repo=*) repo=${arg#*=} ;;
    --dry-run) dry=1 ;;
    --standalone) standalone=1 ;;
    *)
      echo "update.sh: unknown option $arg" >&2
      return 2
      ;;
    esac
    # `open` hands its options on to `run`, all but run's own.
    [ "$arg" = --standalone ] || opts+=("$arg")
  done
  command -v omarchy >/dev/null 2>&1 || PATH=$PATH:${OMARCHY_PATH:-/usr/share/omarchy}/bin
  [ -n "$dry" ] || mkdir -p -m 700 -- "${base%/*}" 2>/dev/null

  case $action in
  open) open_terminal "${opts[@]}" ;;
  run) run_update ;;
  *)
    echo "usage: update.sh open|run --mode=omarchy|checkout --id=<id> --folder=<dir> --from=<v> --to=<v> [--base=<prefix>] [--note=<json>] [--lang=en|pt-BR] [--dry-run]" >&2
    return 2
    ;;
  esac
}

# All of it read before it runs: the update rewrites this very file.
main "$@"; exit $?
