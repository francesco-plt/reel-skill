#!/usr/bin/env bash
# Install the reel skill and CLI for OpenCode (or any agent using ~/.config/opencode/skills).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO/skills/reel"
SKILLS_DIR="${OPENCODE_SKILLS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills}"
BIN_DIR="${REEL_BIN_DIR:-$HOME/.local/bin}"
MODE="copy"

die()  { echo "install: error: $*" >&2; exit 1; }
note() { echo "install: $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --link) MODE="link"; shift ;;
    --copy) MODE="copy"; shift ;;
    --skills-dir) SKILLS_DIR="${2:?--skills-dir needs a value}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:?--bin-dir needs a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,3p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      cat <<'EOF'

Usage: ./install.sh [--link] [--skills-dir DIR] [--bin-dir DIR]

  --link         symlink the skill directory instead of copying it (for development)
  --skills-dir   target skill directory (default: ~/.config/opencode/skills)
  --bin-dir      where to link the `reel` CLI (default: ~/.local/bin)
EOF
      exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[[ -f "$SKILL_SRC/SKILL.md" ]] || die "SKILL.md not found at $SKILL_SRC — run install.sh from the repo"
[[ -x "$SKILL_SRC/scripts/reel.sh" ]] || chmod +x "$SKILL_SRC/scripts/reel.sh"

# --- dependencies (warn only: the agent can still be installed now)
missing=()
for bin in yt-dlp ffmpeg ffprobe jq curl; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  note "missing dependencies: ${missing[*]}"
  note "  brew install ${missing[*]}   (or your package manager)"
fi
[[ -n "${OPENAI_API_KEY:-}" ]] || note "OPENAI_API_KEY is not set — transcription will fail until it is"

# --- skill
mkdir -p "$SKILLS_DIR"
TARGET="$SKILLS_DIR/reel"

if [[ -L "$TARGET" ]]; then
  rm -f "$TARGET"
elif [[ -e "$TARGET" ]]; then
  [[ -f "$TARGET/SKILL.md" ]] || die "$TARGET exists and does not look like a reel skill; remove it yourself"
  rm -rf "$TARGET"
fi

if [[ "$MODE" == "link" ]]; then
  ln -s "$SKILL_SRC" "$TARGET"
  note "linked  $TARGET -> $SKILL_SRC"
else
  cp -R "$SKILL_SRC" "$TARGET"
  note "copied  $SKILL_SRC -> $TARGET"
fi

# --- CLI
mkdir -p "$BIN_DIR"
LINK="$BIN_DIR/reel"
if [[ -e "$LINK" && ! -L "$LINK" ]]; then
  die "$LINK exists and is not a symlink; move it aside first"
fi
ln -sf "$SKILL_SRC/scripts/reel.sh" "$LINK"
note "linked  $LINK -> $SKILL_SRC/scripts/reel.sh"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) note "$BIN_DIR is not on your PATH — add it to use \`reel\` directly" ;;
esac

note "done. Run \`opencode reload\` (or start a new session), then: reel --version"
