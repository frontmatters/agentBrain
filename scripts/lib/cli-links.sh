#!/usr/bin/env bash
# CLI link locations and safe relinking shared by setup and checkout relocation.
# AGENTBRAIN_HOME is the install parent; sandbox installs use only its bin/.
brain_cli_dirs() {
  local home="${AGENTBRAIN_HOME:-$HOME}"
  if [ "$home" = "$HOME" ]; then
    printf '%s\n' "$HOME/bin" "$HOME/.local/bin"
  else
    printf '%s\n' "$home/bin"
  fi
}

# Setup chooses the first existing directory; never replaces an unrelated file/link.
brain_cli_setup() { # directory, checkout
  local dir="$1" checkout="$2" name link
  for name in brain agentbrain; do
    link="$dir/$name"
    if [ ! -e "$link" ] && [ ! -L "$link" ] || { [ -L "$link" ] && [ "$(basename "$(readlink "$link")")" = brain.sh ]; }; then
      ln -sfn "$checkout/scripts/brain.sh" "$link"
    else
      echo "Note: ${link} exists and is not an agentBrain link — left untouched."
      echo "  Symlink $checkout/scripts/brain.sh onto your PATH yourself to use the '$name' command."
    fi
  done
}

# After a move, rewrite only links into the old checkout, plus brain.sh links
# installed by setup (even if they pointed through a now-stale alias).
brain_cli_move() { # old checkout, new checkout
  local old="$1" new="$2" dir link target replacement
  while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    for link in "$dir"/*; do
      [ -L "$link" ] || continue
      target="$(readlink "$link")"
      replacement="$target"
      case "$target" in
        "$old"/*) replacement="$new/${target#"$old"/}" ;;
      esac
      case "${link##*/}:$(basename "$target")" in
        brain:brain.sh|agentbrain:brain.sh) replacement="$new/scripts/brain.sh" ;;
      esac
      if [ "$replacement" != "$target" ]; then
        ln -sfn "$replacement" "$link"
        echo "Relinked $link -> $replacement"
      fi
    done
  done < <(brain_cli_dirs)
}
