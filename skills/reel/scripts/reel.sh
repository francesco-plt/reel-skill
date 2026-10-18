#!/usr/bin/env bash
# reel — turn an Instagram Reel (or any yt-dlp-supported video) into a
# model-readable bundle: transcript.txt + keyframe JPEGs + reel.md
#
# OpenCode V2 cannot attach audio/video to a prompt, so this converts a reel
# into text and images the session can actually read.
set -euo pipefail

PROG="$(basename "$0")"
VERSION="1.0.0"
CACHE_DIR="${REEL_CACHE_DIR:-$HOME/.cache/reel}"
MODEL="${REEL_WHISPER_MODEL:-whisper-1}"
API_URL="https://api.openai.com/v1/audio/transcriptions"

die() { echo "$PROG: error: $*" >&2; exit 1; }
warn() { echo "$PROG: $*" >&2; }
usage() {
  cat <<EOF
Usage: $PROG <url|file> [options]

Options:
  -o, --out DIR              Output directory (default: $CACHE_DIR/<id>)
      --max-frames N         Max keyframes to extract (default: 12)
      --every SECONDS        Fixed seconds between frames (default: auto)
      --no-frames            Skip frame extraction
      --no-transcript        Skip audio transcription
      --keep-video           Keep the downloaded mp4 in the bundle
      --prompt TEXT          Hint passed to Whisper (names, jargon, language)
      --cookies-from-browser B
                             Pass cookies to yt-dlp (private/age-gated reels)
      --max-seconds N        Refuse videos longer than N seconds (default: 600)
  -h, --help                 This help
  -V, --version              Print version

Environment:
  OPENAI_API_KEY        required for transcription
  REEL_WHISPER_MODEL    whisper model (default: whisper-1)
  REEL_CACHE_DIR        bundle root (default: ~/.cache/reel)
  REEL_KEEP_WORK        set to 1 to keep intermediate wav/mp4
EOF
}

URL=""; OUT=""; MAX_FRAMES=12; EVERY=""; DO_FRAMES=1; DO_TRANSCRIPT=1
KEEP_VIDEO=0; PROMPT=""; COOKIES=""; MAX_SECONDS=600

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out) OUT="${2:?}"; shift 2 ;;
    --max-frames) MAX_FRAMES="${2:?}"; shift 2 ;;
    --every) EVERY="${2:?}"; shift 2 ;;
    --no-frames) DO_FRAMES=0; shift ;;
    --no-transcript) DO_TRANSCRIPT=0; shift ;;
    --keep-video) KEEP_VIDEO=1; shift ;;
    --prompt) PROMPT="${2:?}"; shift 2 ;;
    --cookies-from-browser) COOKIES="${2:?}"; shift 2 ;;
    --max-seconds) MAX_SECONDS="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -V|--version) echo "$PROG $VERSION"; exit 0 ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) [[ -z "$URL" ]] || die "only one input supported"; URL="$1"; shift ;;
  esac
done

[[ -n "$URL" ]] || { usage >&2; exit 2; }

# ---------------------------------------------------------------- dependencies
for bin in ffmpeg ffprobe jq curl; do
  command -v "$bin" >/dev/null || die "missing dependency: $bin"
done
IS_LOCAL=0
[[ -f "$URL" ]] && IS_LOCAL=1
if [[ $IS_LOCAL -eq 0 ]]; then
  command -v yt-dlp >/dev/null || die "missing dependency: yt-dlp (brew install yt-dlp)"
fi
if [[ $DO_TRANSCRIPT -eq 1 && -z "${OPENAI_API_KEY:-}" ]]; then
  die "OPENAI_API_KEY is not set (needed for Whisper)"
fi

# ---------------------------------------------------------------- fetch video
WORK="$(mktemp -d "${TMPDIR:-/tmp}/reel.XXXXXX")"
trap '[[ "${REEL_KEEP_WORK:-0}" == "1" ]] || rm -rf "$WORK"' EXIT

META="$WORK/meta.json"
VIDEO=""

if [[ $IS_LOCAL -eq 1 ]]; then
  VIDEO="$URL"
  jq -n --arg p "$URL" '{title: ($p|split("/")|last), uploader: "local", webpage_url: "",
    description: "", duration: null, upload_date: null, id: null}' > "$META"
else
  YT=(yt-dlp -J --no-playlist --no-warnings)
  [[ -n "$COOKIES" ]] && YT+=(--cookies-from-browser "$COOKIES")
  if ! "${YT[@]}" "$URL" > "$META" 2> "$WORK/yt.err"; then
    cat "$WORK/yt.err" >&2
    echo >&2
    warn "yt-dlp could not read that URL (post may not exist, or be login-walled)."
    warn "Retry private/age-gated reels with: --cookies-from-browser safari"
    exit 1
  fi

  YD=(yt-dlp --no-playlist --no-warnings --no-progress
      -f 'bv*+ba/b' --merge-output-format mp4
      -o "$WORK/video.%(ext)s")
  [[ -n "$COOKIES" ]] && YD+=(--cookies-from-browser "$COOKIES")
  if ! "${YD[@]}" "$URL" >/dev/null 2> "$WORK/dl.err"; then
    cat "$WORK/dl.err" >&2
    warn "download failed"
    exit 1
  fi
  VIDEO="$(ls "$WORK"/video.* 2>/dev/null | head -1)"
  [[ -n "$VIDEO" ]] || die "download produced no file"
fi

DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" | cut -d. -f1)"
DURATION="${DURATION//[!0-9]/}"
DURATION="${DURATION:-0}"
if [[ "$DURATION" -gt "$MAX_SECONDS" ]]; then
  die "video is ${DURATION}s, over --max-seconds ${MAX_SECONDS}"
fi

# ---------------------------------------------------------------- bundle dir
ID="$(jq -r '.id // empty' "$META")"
SLUG="$(jq -r '.uploader // "local"' "$META" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
[[ -z "$ID" ]] && ID="$(basename "$VIDEO" | sed 's/\.[^.]*$//')"
DIR="${OUT:-$CACHE_DIR/${SLUG:-reel}-$ID}"
mkdir -p "$DIR/frames"

# ---------------------------------------------------------------- keyframes
if [[ $DO_FRAMES -eq 1 ]]; then
  if [[ -z "$EVERY" ]]; then
    # aim for MAX_FRAMES evenly spaced stills, clamped to a sane interval
    EVERY="$(awk -v d="$DURATION" -v n="$MAX_FRAMES" 'BEGIN{
      if (d<=0) {print 2; exit}
      s = d/n; if (s<1.5) s=1.5; if (s>8) s=8;
      printf "%.2f", s }')"
  fi
  # -ss before -i keeps it fast; scale to 1280 wide max, cap 20 MiB per frame
  ffmpeg -hide_banner -loglevel error -i "$VIDEO" \
    -vf "fps=1/${EVERY},scale='min(1280,iw)':-2" -q:v 3 -frames:v "$MAX_FRAMES" \
    "$DIR/frames/%02d.jpg"
fi

# ---------------------------------------------------------------- transcript
TRANSCRIPT=""
if [[ $DO_TRANSCRIPT -eq 1 ]]; then
  WAV="$WORK/audio.mp3"
  ffmpeg -hide_banner -loglevel error -i "$VIDEO" -vn -ac 1 -ar 16000 \
    -c:a libmp3lame -b:a 48k "$WAV" -y
  BYTES="$(stat -f%z "$WAV" 2>/dev/null || stat -c%s "$WAV")"
  if [[ "$BYTES" -gt 25000000 ]]; then
    die "extracted audio is $((BYTES/1000000))MB, over the 25MB Whisper limit"
  fi

  CURL=(curl -sS --fail-with-body -X POST "$API_URL"
        -H "Authorization: Bearer $OPENAI_API_KEY"
        -F "file=@$WAV"
        -F "model=$MODEL"
        -F "response_format=verbose_json"
        -F "timestamp_granularities[]=segment")
  [[ -n "$PROMPT" ]] && CURL+=(-F "prompt=$PROMPT")

  if ! "${CURL[@]}" > "$WORK/whisper.json" 2> "$WORK/curl.err"; then
    cat "$WORK/curl.err" >&2; cat "$WORK/whisper.json" >&2
    warn "transcription failed"
    exit 1
  fi

  # segment-level timestamps, one line each: [mm:ss] text
  jq -r '
    def ts($s): (($s / 60 | floor) | tostring) + "m"
      + ((($s % 60) | floor) | tostring
         | if length == 1 then "0" + . else . end) + "s";
    (.segments // [])[]
    | (.text | gsub("^\\s+|\\s+$"; "")) as $t
    | select($t != "")
    | "[" + ts(.start) + "] " + $t
  ' "$WORK/whisper.json" > "$DIR/transcript.txt"
  # fall back to flat text if the API returned no segments
  [[ -s "$DIR/transcript.txt" ]] || jq -r '.text // ""' "$WORK/whisper.json" > "$DIR/transcript.txt"
  TRANSCRIPT="$DIR/transcript.txt"
fi

# ---------------------------------------------------------------- metadata
jq '.' "$META" > "$DIR/meta.json"
CAPTION="$(jq -r '.description // ""' "$META")"
UPLOADER="$(jq -r '.uploader // .channel // "unknown"' "$META")"
TITLE="$(jq -r '.title // ""' "$META")"
PAGE="$(jq -r '.webpage_url // empty' "$META")"
UPLOAD_DATE="$(jq -r '.upload_date // empty' "$META")"

# write reel.md
{
  echo "# Reel: ${TITLE:-$ID}"
  echo
  echo "- source: ${PAGE:-$URL}"
  echo "- author: $UPLOADER"
  [[ -n "$UPLOAD_DATE" ]] && echo "- posted: $UPLOAD_DATE"
  echo "- duration: ${DURATION}s"
  echo
  echo "## Caption"
  echo
  if [[ -n "$CAPTION" && "$CAPTION" != "null" ]]; then
    echo "$CAPTION"
  else
    echo "_(no caption captured)_"
  fi
  echo
  echo "## Transcript"
  echo
  if [[ -n "$TRANSCRIPT" && -s "$TRANSCRIPT" ]]; then
    echo '```'
    head -c 200000 "$TRANSCRIPT"
    echo '```'
  elif [[ $DO_TRANSCRIPT -eq 0 ]]; then
    echo "_(transcription skipped)_"
  else
    echo "_(no speech detected)_"
  fi
  echo
  if [[ $DO_FRAMES -eq 1 ]] && compgen -G "$DIR/frames/*.jpg" >/dev/null; then
    echo "## Keyframes (one every ${EVERY}s)"
    echo
    i=0
    for f in "$DIR"/frames/*.jpg; do
      i=$((i+1))
      t="$(awk -v e="$EVERY" -v i="$i" 'BEGIN{printf "%dm%02ds", (e*(i-1))/60, (e*(i-1))%60}')"
      echo "- \`$(basename "$f")\` — ~$t"
    done
    echo
    echo "Read these with the read tool to see on-screen text and visuals."
  fi
} > "$DIR/reel.md"

if [[ $KEEP_VIDEO -eq 1 ]]; then
  cp "$VIDEO" "$DIR/video.mp4"
fi

printf '%s\n' "$DIR"
warn "bundle ready: $DIR/reel.md"
if [[ $DO_FRAMES -eq 1 ]]; then
  warn "frames: $(ls "$DIR"/frames/*.jpg 2>/dev/null | wc -l | tr -d ' ')"
fi
