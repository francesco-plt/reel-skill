---
name: Reel
description: Turn an Instagram Reel (or other yt-dlp-supported video/audio link) into text and images the session can actually read — transcript, caption, and keyframes. Use when the user shares a reel/video URL, asks what a video says or shows, or asks to summarize/take notes on short-form video content.
---

# Reel

OpenCode V2 does not pass audio or video to models: only UTF-8 text, directories,
and PNG/JPEG/GIF/WebP images become visible. Never try to attach an `.mp4` or
`.mp3` — it is silently dropped from the request. Convert first.

`scripts/reel.sh` (also installed as `reel` on `$PATH`) does the conversion:

```
instagram/other URL ──> yt-dlp ──> ffmpeg ──┬──> audio ──> Whisper ──> transcript.txt
                                            └──> keyframes ──────────> frames/*.jpg
                                                        └──> reel.md (index + caption)
```

## Workflow

1. Run the converter and capture the bundle path:

   ```sh
   reel "<url>"
   ```

   It prints the bundle directory on stdout and progress on stderr. Default
   location is `~/.cache/reel/<author>-<id>/`. Pass `-o DIR` to choose another.

2. Read `reel.md` from that directory. It contains the caption, the
   timestamped transcript, and an index of the keyframes with their approximate
   offsets.

3. Read the frames with the `read` tool (they are JPEGs, up to 12 by default).
   Read them when on-screen text, UI, charts, or visual context matters — a
   reel's substance is often entirely in the frames. Skip frames only if the
   question is purely about spoken content.

4. Answer from the transcript + frames, and cite timestamps (`[0m42s]`) when the
   user may want to jump back to the source.

## Flags

| Flag | Purpose |
| --- | --- |
| `--max-frames N` | more/fewer stills (default 12) |
| `--every SECONDS` | fixed sampling interval instead of auto |
| `--no-frames` | audio-only reel (podcast clips, talking heads) |
| `--no-transcript` | music-only or visual-only reel; saves the API call |
| `--prompt TEXT` | Whisper hint: names, product names, jargon, language |
| `--keep-video` | copy the mp4 into the bundle when exact frames matter |
| `--cookies-from-browser safari` | private, age-gated, or login-walled reels |
| `--max-seconds N` | guard against long videos (default 600) |

Also accept a local file path, so the same command works for screen recordings
and downloaded clips.

## Notes

- Transcription uses the OpenAI `whisper-1` API and needs `OPENAI_API_KEY`
  (~$0.006/min). `REEL_WHISPER_MODEL` overrides the model.
- Public reels usually work anonymously. If `yt-dlp` returns a login/empty-media
  error, retry with `--cookies-from-browser safari` (or `chrome`).
- Re-run the command on the same URL to refresh a bundle; it overwrites in place.
- Individual frames stay well under the 20 MiB attachment limit at the default
  1280px width, so attaching a frame directly to a prompt also works.
