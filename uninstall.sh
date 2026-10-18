#!/usr/bin/env bash
# Remove the reel skill, its CLI link, and optionally the bundle cache.
set -euo pipefail

SKILLS_DIR="${OPENCODE_SKILLS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills}"
BIN_DIR="${REEL_BIN_DIR:-$HOME/.local/bin}"
CACHE_DIR="${REEL_CACHE_DIR:-$HOME/.cache/reel}"
PURGE=0

die()  { echo "uninstall: error: $*" >&2; exit 1; }
note() { echo "uninstall: $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --skills-dir) SKILLS_DIR="${2:?--skills-dir needs a value}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:?--bin-dir needs a value}"; shift 2 ;;
    -h|--help)
      echo "Usage: ./uninstall.sh [--purge] [--skills-dir DIR] [--bin-dir DIR]"
      echo "  --purge   also delete $CACHE_DIR"
      exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

TARGET="$SKILLS_DIR/reel"
if [[ -L "$TARGET" ]]; then
  rm -f "$TARGET"; note "removed link $TARGET"
elif [[ -d "$TARGET" ]]; then
  [[ -f "$TARGET/SKILL.md" ]] || die "$TARGET does not look like the reel skill; refusing to delete"
  rm -rf "$TARGET"; note "removed $TARGET"
else
  note "no skill installed at $TARGET"
fi

LINK="$BIN_DIR/reel"
if [[ -L "$LINK" ]]; then
  rm -f "$LINK"; note "removed $LINK"
elif [[ -e "$LINK" ]]; then
  note "left $LINK alone (not a symlink)"
fi

if [[ $PURGE -eq 1 ]]; then
  rm -rf "$CACHE_DIR"; note "deleted $CACHE_DIR"
fi

note "done. Run \`opencode reload\` to drop the skill from running sessions."
