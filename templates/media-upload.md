# Template: media upload

Copy this template, fill the placeholders, and execute. `xr media upload` drives X's chunked `INIT → APPEND → FINALIZE →
STATUS` state machine end-to-end; you don't call the four substeps directly. `xr media alt-text` then describes an
uploaded image or video for screen readers, and `xr media subtitles add` / `remove` attach or detach a subtitle track on
an uploaded video. All four are write ops: they hit production, and the upload counts against your media-upload caps.

## Pre-flight

```bash
xr auth status --output json                 # .apps[]: confirm oauth1: true OR an oauth2_users entry
xr media upload --help                       # confirm flags for your installed version
```

Every media verb requires OAuth1 OR OAuth2 (user-scoped; the spec `xr` vendors names `media.write` as the OAuth2 scope
for upload, alt text, and subtitles). Bearer (app-only) cannot upload or describe media: an app whose only credential is
a bearer answers `reason: "auth-method-mismatch"`, exit `2`, with `available_in_app: ["app"]` and `supported:
["oauth2","oauth1"]`.

`xr media upload <FILE> --dry-run --output json` validates the flags only: it does not read the file, so a missing path
still answers `would_succeed: true`, and the live call answers `reason: "io"`, exit `5`, instead. Check the path
yourself (`[ -r "$FILE" ]`) before relying on the preflight.

## Picking `--media-type` and `--category`

| File                  | `--media-type` | `--category`    | Use for                          |
| --------------------- | -------------- | --------------- | -------------------------------- |
| Image (PNG)           | `image/png`    | `tweet_image`   | A still attached to a post       |
| Image (JPEG)          | `image/jpeg`   | `tweet_image`   | A still attached to a post       |
| Image (GIF, animated) | `image/gif`    | `tweet_gif`     | An animated GIF attached to post |
| Short video           | `video/mp4`    | `tweet_video`   | A clip attached to a post        |
| Longer video          | `video/mp4`    | `amplify_video` | Sponsored / longer-form video    |
| DM image              | `image/png`    | `dm_image`      | Attach to a DM                   |
| DM video              | `video/mp4`    | `dm_video`      | Attach to a DM                   |
| Subtitles (SubRip)    | `text/srt`     | `subtitles`     | Track for `media subtitles add`  |
| Subtitles (WebVTT)    | `text/vtt`     | `subtitles`     | Track for `media subtitles add`  |

`--media-type` defaults to `video/mp4` and `--category` defaults to `amplify_video` when omitted. For images, ALWAYS
override both, because the defaults will reject your upload.

The authoritative catalog of categories changes occasionally; verify at
<https://docs.x.com/x-api/media/quickstart/media-upload-chunked.md> when in doubt.

## Upload (image, GIF, video)

```bash
RESP=$(xr media upload <FILE> \
  --media-type <MIME> \
  --category <CATEGORY> \
  --output json)

MEDIA_ID=$(printf '%s' "$RESP" | jaq -r '.data.id')
echo "Uploaded: $MEDIA_ID"
```

The answer is one API document (no `status` key): `data.id` is the media id to thread into `--media-id`, beside
`data.media_key` and `data.expires_after_secs`; `xr schema` has no `media-upload` entry, so read the fields from a live
call rather than a schema. When the upload waited for processing (next section), the same document also carries the
final `data.processing_info`.

## The wait for processing (video, and whatever X is still processing)

A video needs server-side processing before a post can carry it, and X can still be processing other media, such as
an animated GIF, when the upload is finalized. `xr media upload` waits for both by default: always for a category whose
name contains `video` (`tweet_video`, `amplify_video`, `dm_video`), and for any other upload whose FINALIZE answer
reports processing still under way. An upload X reports as ready returns at once.

```bash
xr media upload ./clip.mp4 --media-type video/mp4 --category tweet_video --output json
```

After a wait, `data.processing_info.state` in the answer is `succeeded` (good) or `failed`
(`data.processing_info.error` names the problem). When X reports no state for media it has finished with, the answer
carries no `processing_info`.

| Form            | What it does                                                            |
| --------------- | ----------------------------------------------------------------------- |
| no flag         | Waits up to the default deadline (`xr media upload --help` states it)   |
| `--wait=<SECS>` | Waits up to that many seconds                                           |
| `--wait=false`  | Returns after FINALIZE without reading a status; `--wait=0` is the same |
| `--wait 120`    | `invalid-args`, exit `2`: the value follows `=`                         |

A wait that reaches its deadline exits `1` with `reason: "processing-timeout"`. The upload is intact: stdout still
carries the FINALIZE document, and the envelope on stderr names the media id and the command that waits again for twice
as long. After `--wait=30`:

```json
{
  "status": "error",
  "reason": "processing-timeout",
  "exit_code": 1,
  "media_id": "<MEDIA_ID>",
  "message": "media <MEDIA_ID> was still processing when the 30-second wait ended",
  "next_step": { "action": "resume-wait", "command": "xr media status <MEDIA_ID> --wait=60" }
}
```

Run `next_step.command` as given (append `--output json` to read its answer); do not upload the file again. Each
timeout doubles the wait its command names.

A `processing_info` still `pending` or `in_progress` in the answer means the upload did not wait (`--wait=false`) or
the wait ended early; `xr media status <MEDIA_ID> --wait` waits on it.

## Polling explicitly

`xr media status <id>` reads the status once and exits `0` while the job is still processing. `xr media status <id>
--wait` (or `--wait=<SECS>`) blocks until processing finishes or its deadline passes, with the same
`processing-timeout` envelope. To upload without blocking and poll yourself, pass `--wait=false`; the manual loop below
is for when you need per-poll control:

```bash
MEDIA_ID=$(xr media upload ./clip.mp4 --media-type video/mp4 --category tweet_video --wait=false --output json | jaq -r '.data.id')

while true; do
  STATUS=$(xr media status "$MEDIA_ID" --output json | jaq -r '.data.processing_info.state // "succeeded"')
  case "$STATUS" in
    succeeded) break ;;
    failed)
      echo "Processing failed" >&2
      xr media status "$MEDIA_ID" --output json | jaq '.data.processing_info' >&2
      exit 1
      ;;
    pending|in_progress)
      WAIT_SECS=$(xr media status "$MEDIA_ID" --output json | jaq -r '.data.processing_info.check_after_secs // 5')
      sleep "$WAIT_SECS"
      ;;
    *)
      echo "Unknown state: $STATUS" >&2
      exit 1
      ;;
  esac
done

echo "Processing complete: $MEDIA_ID"
```

The X API tells you how long to wait via `processing_info.check_after_secs`. Honor it, since tight-polling burns rate.

## Describing an image or video: alt text

Alt text is what a screen reader announces in place of the media. Set it after the upload and before the post, through
the gate:

```bash
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- \
  xr media alt-text "$MEDIA_ID" "<DESCRIPTION>"
```

Write the description from what the media shows, never from the file name or the post text: the subject, the action, any
text that appears in the image, and whatever detail the post depends on. Leave out "Image of" (a screen reader already
announces an image). When you cannot see the media yourself, ask the user for the description rather than inventing one;
a wrong description is worse than none.

The preflight checks the inputs and nothing else: a media id of 1 to 19 digits, and text that is not blank and at most
1000 characters. A refusal arrives as `would_succeed: false` with `reason: "invalid-media-id"`, `"empty-alt-text"`, or
`"alt-text-too-long"`, and the gate prints that reason. The live answer is the X API document, `{"data":{"id":"<media
id>","associated_metadata":{…}}}`, which `xr validate --schema alt-text` checks.

Text that starts with `-` (`-5°C at the start`) is read as a flag and answers `invalid-args`; put it after `--`: `xr
media alt-text "$MEDIA_ID" -- "-5°C at the start"`. The gate takes the same form and adds its own flags before the `--`.

Endpoint reference: <https://docs.x.com/x-api/media/create-media-metadata.md>.

## Subtitles on a video

A subtitle track is its own upload (category `subtitles`, an `.srt` or `.vtt` file), attached to an uploaded video by
id:

```bash
SUBS_ID=$(xr media upload ./captions.srt --media-type text/srt --category subtitles --output json | jaq -r '.data.id')

~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- \
  xr media subtitles add "$VIDEO_ID" "$SUBS_ID" --language en --name English
```

- `--language` is the track's two-letter code, in either case (`en`, not `eng`); `xr` sends it upper-cased. It is
  required.
- `--name` is the label viewers pick the track by. It is optional.
- `--category` names the category **the video** was uploaded with: `amplify_video` (the default, matching `media
  upload`'s default) or `tweet_video`. Any other value is `invalid-args`, exit `2`. `xr` cannot check it against the
  upload, so a video uploaded as `tweet_video` (the short-clip row above) needs `--category tweet_video` here and on
  `remove`.

The answer is `{"data":{"id":"<video id>","media_category":"AmplifyVideo","associated_subtitles":{…}}}` (schema
`subtitles`). To take a track off, name the video, the language, and the same `--category`:

```bash
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- \
  xr media subtitles remove "$VIDEO_ID" --language en --category amplify_video
```

That answers `{"data":{"deleted":true}}` (schema `delete`). Neither verb takes `--force`. Preflight refusals are
`invalid-media-id` (an id that is not 1 to 19 digits) and `invalid-language-code`.

Endpoint reference: <https://docs.x.com/x-api/media/create-media-subtitles.md> and
<https://docs.x.com/x-api/media/delete-media-subtitles.md>.

## Attaching to a post

`--media-id` on `xr post` (or `xr reply` / `xr quote`) is repeatable. Gate the attach through `scripts/dry-run-gate.sh`
so the post itself goes through the standard preflight:

```bash
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- \
  xr post "<TEXT>" --media-id "$MEDIA_ID"
```

Manual path:

```bash
xr post "<TEXT>" --media-id "$MEDIA_ID" --dry-run --output json
xr post "<TEXT>" --media-id "$MEDIA_ID" --output json
```

For multiple attachments:

```bash
xr post "<TEXT>" \
  --media-id "$MEDIA_ID_A" \
  --media-id "$MEDIA_ID_B" \
  --media-id "$MEDIA_ID_C" \
  --output json
```

X enforces per-post attachment limits (typically up to 4 images, or 1 video, or 1 GIF). Verify the current limit at
<https://docs.x.com/x-api/posts/create-post.md>.

## Errors and retries

| Symptom                                  | Likely cause                                                         | Fix                                                                                 |
| ---------------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `reason: "auth-method-mismatch"`         | Bearer-only is staged; need OAuth1 / OAuth2                          | Re-auth with [oauth2-setup.md](oauth2-setup.md)                                     |
| `reason: "auth-required"`, exit `77`     | No credential staged at all                                          | Follow the envelope's `next_step`                                                   |
| `reason: "io"`, exit `5`                 | The file path does not exist or is unreadable                        | Fix the path; `--dry-run` does not catch this                                       |
| `reason: "network-error"`, exit `5`      | No answer from X (DNS, TCP, TLS, timeout); same exit as `io`         | Branch on `reason`, not the exit code; retry once, bump `--timeout`                 |
| `reason: "invalid-request"`, exit `1`    | X rejected the INIT or FINALIZE body (400 / 422)                     | Read `message`; fix `--media-type` / `--category` for the file                      |
| `reason: "invalid-args"`, exit `2`       | A flag was mistyped (`--wait false`, an unknown option)              | `xr media upload --help`; a `--wait` value follows `=`                              |
| `reason: "processing-timeout"`, exit `1` | The wait ended with the video still processing; the upload is intact | Run `next_step.command`; it waits twice as long                                     |
| Upload succeeds; `processing failed`     | File doesn't meet X's spec (size, codec, duration)                   | Inspect `processing_info.error`; transcode if needed                                |
| `reason: "rate-limited"`                 | Per-user media cap hit                                               | Wait `retry_after_secs` when the envelope carries it; else `xr usage --output json` |
| Attach to post fails after upload        | `media_id` not yet ready                                             | Let the upload's wait finish, or `xr media status <id> --wait`                      |
| Repeated retries for same file           | Network truncation; retry doesn't resume the same upload             | New upload starts a new `media_id`; chain through the new id                        |
| Preflight `would_succeed: false`         | An input check failed; `reason` names it                             | Fix the id, the text, or `--language`; see the two sections above                   |
| `reason: "validation"`, exit `1`         | The same input check on a live `alt-text` / `subtitles` call         | `message` names the check; no request was sent                                      |
| `invalid-args` on `media subtitles`      | `--category` outside the two values, or no `--language`              | `--category amplify_video` or `tweet_video`; pass `--language xx`                   |

## Cleanup

X does not currently expose a media-delete endpoint via the public API. An unattached `media_id` expires server-side
after a few hours. No client-side cleanup is needed.

## Validating the response

`xr validate` has no schema for the upload answer, so gate on the field you need before relying on the ID (the alt-text
and subtitle answers validate as `alt-text`, `subtitles`, and `delete`):

```bash
xr media upload <FILE> --media-type <MIME> --category <CATEGORY> --output json \
  | jaq -e '.data.id | strings' >/dev/null || { echo "upload answered no media id" >&2; exit 1; }
```

If the field is missing on a `0` exit, the typed response may be drifting from the live API; file `[skill]`-prefixed at
<https://github.com/brettdavies/xurl-rs/issues>.
