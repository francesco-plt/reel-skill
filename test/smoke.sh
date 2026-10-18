#!/usr/bin/env bash
# Smoke test: exercises the full pipeline on a synthetic reel.
# With OPENAI_API_KEY set it also generates speech (TTS) and asserts a transcript.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/skills/reel/scripts/reel.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/reel-smoke.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$*"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$*"; }
check(){ if eval "$1"; then ok "$2"; else bad "$2"; fi; }

echo "static checks"
check 'bash -n "$SCRIPT"' "bash -n reel.sh"
check 'bash -n "$REPO/install.sh"' "bash -n install.sh"
check 'bash -n "$REPO/uninstall.sh"' "bash -n uninstall.sh"
check '"$SCRIPT" --version | grep -Eq "^reel(\.sh)? [0-9]+\.[0-9]+"' "--version prints a version"
check '"$SCRIPT" --help | grep -q -- --max-frames' "--help lists flags"
check '! "$SCRIPT" 2>/dev/null' "missing argument exits non-zero"

echo "building sample video"
ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=size=720x1280:rate=30" \
  -f lavfi -i "anullsrc=channel_layout=mono:sample_rate=16000" \
  -t 12 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$TMP/silent.mp4" -y

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  echo "generating speech via TTS"
  if curl -sS --fail-with-body https://api.openai.com/v1/audio/speech \
      -H "Authorization: Bearer $OPENAI_API_KEY" -H 'Content-Type: application/json' \
      -d '{"model":"tts-1","voice":"alloy","input":"Step one, open the terminal. Step two, run the reel command."}' \
      -o "$TMP/tts.mp3"; then
    ffmpeg -hide_banner -loglevel error -i "$TMP/silent.mp4" -i "$TMP/tts.mp3" \
      -c:v copy -c:a aac -shortest "$TMP/sample.mp4" -y
    echo "pipeline (with audio)"
    if "$SCRIPT" "$TMP/sample.mp4" --out "$TMP/bundle" --max-frames 3 >/dev/null 2>&1; then
      ok "reel exited 0"
      check '[ -s "$TMP/bundle/reel.md" ]' "reel.md written"
      check 'grep -q "\[0m0" "$TMP/bundle/transcript.txt"' "transcript has timestamped lines"
      check '[ "$(ls "$TMP/bundle"/frames/*.jpg 2>/dev/null | wc -l)" -ge 1 ]' "keyframes extracted"
    else
      bad "reel exited non-zero"
    fi
  else
    bad "TTS request failed"
  fi
else
  echo "OPENAI_API_KEY not set — skipping transcription, testing visual path only"
  if "$SCRIPT" "$TMP/silent.mp4" --out "$TMP/bundle" --no-transcript --max-frames 3 >/dev/null 2>&1; then
    ok "reel --no-transcript exited 0"
    check 'grep -q "transcription skipped" "$TMP/bundle/reel.md"' "reel.md marks transcript as skipped"
  else
    bad "reel --no-transcript exited non-zero"
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
