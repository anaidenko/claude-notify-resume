# claude-code-notify

Desktop notifications for [Claude Code](https://claude.com/claude-code) that
tell you **which conversation** finished — and take you back into it.

```
┌────────────────────────────────────────────────┐
│  ✳  Replied                                    │
│     Fix the geofence rounding bug              │
└────────────────────────────────────────────────┘
```

Run several Claude sessions at once and the usual notification is useless: five
identical banners saying "Claude Code is done", with no clue which repo, which
task, or where to go next. This one names the chat and reopens it when clicked.

## What makes it different

Most Claude Code notifiers title the banner with a static string, the working
directory, or the git branch. Two things here work differently:

- **The banner is titled with the chat's own name** — the AI-generated title you
  see in `/resume`, read from the session transcript. Not the folder, not the
  branch, not a truncated UUID: the actual subject of the conversation.
- **Clicking it resumes that session** (`claude --resume <id>`), rather than
  focusing whichever terminal window happens to still be open. This keeps
  working after you have closed the tab.

Both matter most in exactly the case that breaks other tools: many parallel
sessions across several repos.

The status also says what actually happened, rather than lumping every event
under one word:

| Status | Fires when |
| --- | --- |
| `Replied` | Claude finished responding — every turn, *not* "task complete" |
| `Permission needed` | A tool call is waiting for your approval |
| `Waiting for you` | Claude is idle, awaiting your next prompt |
| `Input needed` | An MCP server opened an elicitation form |
| `Background agent needs you` / `finished` | A background session wants input, or ended |

Deliberately *not* subscribed: `auth_success`, `elicitation_complete`,
`elicitation_response` — they announce things you just watched happen.

## Install

```
/plugin marketplace add anaidenko/claude-code-notify
/plugin install claude-code-notify
```

Restart Claude Code — hook config is read at startup.

**macOS** also needs the notifier binary, and optionally the icon bundle:

```bash
brew install terminal-notifier

# Optional: gives the banner the Claude icon, and enables click-to-resume
~/.claude/plugins/cache/anaidenko/claude-code-notify/*/scripts/setup-macos-icon.sh
```

That script ends by sending a test banner. **If you do not see it**, open
**System Settings → Notifications → Claude Code** and turn on *Allow
notifications*: a newly created bundle starts switched off, and macOS then
discards its banners with no error and a success exit code.

## Platform support

| Platform | Status | Notes |
| --- | --- | --- |
| macOS | Supported, in daily use | `terminal-notifier`; icon + click-to-resume via a generated `.app` |
| Linux | Supported | `notify-send`; no click action |
| Windows | Not supported | PRs welcome |

Every path fails silently by design: a notification must never break your
session — if the notifier is missing or the payload is malformed, the hook
exits 0 and says nothing.

The Linux path is covered by a container test suite:

```bash
docker build -t claude-notify-test -f test/Dockerfile .
docker run --rm claude-notify-test
```

A container has no notification daemon, so no banner can appear there. What the
suite does verify is everything up to the D-Bus call: transcript parsing, the
chat name, platform dispatch, the arguments `notify-send` receives, and that
every failure path still exits 0 — including when libnotify is not installed.

## How it works

Claude Code hands a hook a JSON payload on stdin — `session_id`,
`transcript_path`, `cwd`. The chat name is not in it, so `notify-parse.js`
reads the transcript and takes the last `ai-title` record:

```json
{ "type": "ai-title", "sessionId": "6f960b23-…", "aiTitle": "Fix the geofence rounding bug" }
```

It is re-emitted as the conversation evolves, so the last one wins. This is an
internal record type, not a documented API — if it ever disappears, the banner
falls back to the project directory name.

On macOS the icon needs a detour: the banner's left-hand icon comes from the
**sending application**, and `terminal-notifier`'s `-appIcon` / `-contentImage`
do not affect that slot. So `setup-macos-icon.sh` generates a tiny `.app` that
exists only to own the icon, and passes `-sender`. That flag also takes over the
click, so the bundle performs the resume itself.

| File | Role |
| --- | --- |
| `hooks/hooks.json` | Declares the `Stop` / `Notification` hooks |
| `scripts/notify.sh` | Parses the payload, resolves the chat name, dispatches per platform |
| `scripts/notify-parse.js` | Reads the payload + `ai-title` from the transcript |
| `scripts/notify-macos.sh` | Builds and sends the macOS banner |
| `scripts/setup-macos-icon.sh` | Optional: builds the icon bundle |

To fire a banner by hand while debugging, set `CLAUDE_NOTIFY_TEST=1` so it is
prefixed `[TEST]` and never mistaken for a real one:

```bash
echo '{"session_id":"x","transcript_path":"","cwd":"'"$PWD"'"}' \
  | CLAUDE_NOTIFY_TEST=1 scripts/notify.sh "Completed"
```

The marker is `TEST ·` rather than `[TEST]` on purpose: a `-title` starting with
`[` is swallowed by `terminal-notifier`, which silently falls back to its
default title of "Terminal" — the banner still shows, just not the title you
passed.

### Known limitation

With the icon bundle installed, the click target lives in a single state file
that each notification overwrites. So with two sessions running, clicking an
*older* banner opens whichever notified most recently. macOS does not tell the
app which banner was clicked, so fixing this means dropping the custom icon —
without the bundle, `-execute` makes every click exact.

## Uninstall

```
/plugin uninstall claude-code-notify
```

Then, if you built the icon bundle: `scripts/setup-macos-icon.sh remove`

## License

MIT
