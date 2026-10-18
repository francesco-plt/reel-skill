# reel

Turn an Instagram Reel — or any video link `yt-dlp` understands — into something an
AI coding agent can actually read: a timestamped transcript, the post caption, and
a handful of keyframes.

Originally built for [OpenCode](https://opencode.ai), which (like most agent
harnesses) drops audio and video from prompts: only UTF-8 text, directories, and
PNG/JPEG/GIF/WebP images reach the model. So "watch this reel" has to become
"read this transcript and look at these stills".

```sh
reel https://www.instagram.com/reel/Cxxxxxxxxxx/
# ~/.cache/reel/some-creator-Cxxxxxxxxxx
```

Then point the agent at `reel.md` — or let the bundled skill do it.

## How it works

```
url ──> yt-dlp ──> ffmpeg ──┬──> audio ──> Whisper API ──> transcript.txt  ([0m42s] lines)
                            └──> frames ─────────────────> frames/NN.jpg
                            └──> metadata ───────────────> caption, author, date
                                                           └──> reel.md (read this first)
```

No model, no agent loop: one bash script, three external binaries, one API call.

## Requirements

| Dependency | Why | Install (macOS) |
| --- | --- | --- |
| `bash` 3.2+ | runs the script | preinstalled |
| [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) | downloads the reel | `brew install yt-dlp` |
| `ffmpeg` + `ffprobe` | audio extraction, frame sampling | `brew install ffmpeg` |
| `jq`, `curl` | JSON handling, API call | `brew install jq` |
| `OPENAI_API_KEY` | speech-to-text (`whisper-1`) | export it |

Linux works too — `install.sh` and the script avoid GNU-only flags, but only macOS
arm64 is tested. Windows is untested (WSL should behave like Linux).

## Install

```sh
git clone <this-repo> ~/dev/reel-skill
cd ~/dev/reel-skill
./install.sh
```

That copies `skills/reel` into `${XDG_CONFIG_HOME:-~/.config}/opencode/skills/reel`
and symlinks the CLI onto `~/.local/bin/reel`. Then:

```sh
opencode reload     # or start a new session
reel --version
```

Options:

```sh
./install.sh --link           # symlink the skill dir too, so git pull updates it live
./install.sh --skills-dir DIR # install the skill somewhere else
./install.sh --bin-dir DIR    # put the CLI somewhere else (default ~/.local/bin)
```

`install.sh` never touches files outside the two target directories, and refuses to
overwrite a `reel` entry that is not ours.

## Usage

```sh
reel <url|file> [options]
```

Pass a local path instead of a URL to process a screen recording or a downloaded
clip — same pipeline.

| Flag | Default | Purpose |
| --- | --- | --- |
| `-o, --out DIR` | `~/.cache/reel/<author>-<id>` | where to write the bundle |
| `--max-frames N` | `12` | cap on extracted stills |
| `--every SECONDS` | auto | fixed sampling interval instead of `duration/N` (clamped to 1.5–8s) |
| `--no-frames` | off | audio-only processing |
| `--no-transcript` | off | visual-only processing; skips the API call |
| `--prompt TEXT` | — | Whisper hint: names, jargon, language |
| `--keep-video` | off | copy the mp4 into the bundle |
| `--cookies-from-browser B` | — | e.g. `safari`, `chrome` — for private or login-walled posts |
| `--max-seconds N` | `600` | refuse longer videos |
| `-V, --version` | — | print version |

Environment: `OPENAI_API_KEY` (required unless `--no-transcript`),
`REEL_WHISPER_MODEL` (default `whisper-1`), `REEL_CACHE_DIR`, `REEL_KEEP_WORK=1`
to keep intermediate files.

### Bundle layout

```
~/.cache/reel/<author>-<id>/
├── reel.md          # read this: caption + transcript + frame index
├── transcript.txt   # timestamped lines, one per segment
├── meta.json        # full yt-dlp metadata
└── frames/
    ├── 01.jpg
    └── ...
```

## Using it from an agent

**Automatic.** The skill description matches "what does this reel say", so the
agent loads it and runs the pipeline when you paste a link.

**Explicit.** Mention the skill by ID: `@reel <url>`. With OpenCode, `install.sh`
also drops a `/reel <url>` slash command.

**No agent at all.** Run `reel`, then attach `reel.md` and a few `frames/*.jpg`
to any chat — or `cat` the transcript into a prompt.

## Cost and privacy

Transcription sends the **extracted audio only** to the OpenAI API (~$0.006 per
minute for `whisper-1`; a 95s reel is under a cent). The video never leaves your
machine. Use `--no-transcript` for a zero-network-cost bundle when the reel is
visual-only.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Instagram sent an empty media response` | private/age-gated/region-locked: add `--cookies-from-browser safari` |
| `missing dependency: ...` | install it — see Requirements |
| `extracted audio is 25MB+` | over the Whisper upload limit; split the input or use a longer-form pipeline |
| Frames miss the action | raise `--max-frames`, or pin `--every 1` for dense sampling |
| Agent ignores the frames | the bundle must be read by path; `reel.md` lists each file |

Re-running on the same URL overwrites the bundle in place.

## Uninstall

```sh
./uninstall.sh            # remove skill + CLI link
./uninstall.sh --purge    # also delete ~/.cache/reel
```

## License

MIT — see [LICENSE](LICENSE).
