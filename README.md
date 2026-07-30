# claude-notify-resume

Desktop notifications for [Claude Code](https://claude.com/claude-code) that
tell you **which conversation** finished — and take you back into it.

<img src="assets/banner-permission-needed.png" alt="A macOS notification titled &quot;Permission needed&quot;, with the body &quot;Migrate the auth service to OAuth&quot; — the name of the chat that is waiting." width="500">

*The body is the chat's own name, so you know which session is asking.
(Shown with the optional icon enabled — see [the trade-off](#the-icon-costs-you-the-click).)*

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
/plugin marketplace add anaidenko/claude-notify-resume
/plugin install claude-notify-resume
```

Restart Claude Code — hook config is read at startup.

**macOS** works out of the box via AppleScript. For click-to-resume, install
the notifier binary:

```bash
brew install terminal-notifier
```

Then build the icon bundle, which gives the banner the Claude icon:

```bash
~/.claude/plugins/cache/anaidenko/claude-notify-resume/*/scripts/setup-macos-icon.sh
```

With the bundle installed you resume via the banner's **Show** button; skip it
and the whole banner is clickable instead. See
[the trade-off](#the-icon-costs-you-the-click).

That script ends by sending a test banner. **If you do not see it**, open
**System Settings → Notifications → Claude Code** and turn on *Allow
notifications*: a newly created bundle starts switched off, and macOS then
discards its banners with no error and a success exit code.

**Linux** needs nothing beyond `notify-send`, which desktop distros ship with
libnotify preinstalled. If yours does not: `sudo apt install libnotify-bin`
(or your distro's package) — the plugin says so once if it is missing.

## Platform support

| Platform | Status | Notes |
| --- | --- | --- |
| macOS | Supported, in daily use | AppleScript out of the box; `terminal-notifier` adds click-to-resume, and optionally the icon |
| Linux | Supported | `notify-send`; tested on Debian + Ubuntu; no click action |
| Windows | Not supported | PRs welcome |

Every path fails silently by design: a notification must never break your
session — if the notifier is missing or the payload is malformed, the hook
exits 0 and says nothing.

```bash
npm test              # native suite for your platform
npm run test:all      # + Linux suites and real-daemon delivery via Docker
npm run notify:demo   # send one real banner
```

The suites run the scripts straight out of the repo — no install, no
dependencies — and never deliver a banner: the notifier binaries are shadowed by
stubs that record their arguments. Delivery itself is verified separately
against a real notification daemon over D-Bus (`npm run test:dbus`). Verified on
**Debian 12** and **Ubuntu 24.04**; per-suite details are in
[CONTRIBUTING.md](CONTRIBUTING.md).

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
exists only to own the icon, and passes `-sender`. That flag also swallows the
click, which is why the icon is opt-in — see
[the trade-off](#the-icon-costs-you-the-click).

| File | Role |
| --- | --- |
| `hooks/hooks.json` | Declares the `Stop` / `Notification` hooks |
| `scripts/notify.sh` | Parses the payload, resolves the chat name, dispatches per platform |
| `scripts/notify-parse.js` | Reads the payload + `ai-title` from the transcript |
| `scripts/notify-macos.sh` | Builds and sends the macOS banner |
| `scripts/notify-linux.sh` | Builds and sends the Linux banner |
| `scripts/open-session.sh` | Reopens a session when a banner is clicked |
| `scripts/load-config.sh` | Reads the config file, letting the environment win |
| `scripts/setup-macos-icon.sh` | Optional: builds the icon bundle |
| `test/run-tests.sh` | Picks the suite matching your platform |

To fire a banner by hand while debugging, set `CLAUDE_NOTIFY_TEST=1` so it is
prefixed `TEST ·` and never mistaken for a real one:

```bash
echo '{"session_id":"x","transcript_path":"","cwd":"'"$PWD"'"}' \
  | CLAUDE_NOTIFY_TEST=1 scripts/notify.sh "Replied"
```

The marker is `TEST ·` rather than `[TEST]` on purpose: a `-title` starting with
`[` is swallowed by `terminal-notifier`, which silently falls back to its
default title of "Terminal" — the banner still shows, just not the title you
passed.

### Configuration

Nothing needs configuring — the defaults are what the plugin is tuned for. When
you do want to change something, write `~/.claude/claude-notify-resume.conf` (copy
[`claude-notify-resume.conf.example`](claude-notify-resume.conf.example) to start):

```ini
# Statuses you would rather not be told about
MUTE=Replied,Waiting for you

# Force a terminal instead of the detected one: Terminal, iTerm, or vscode
TERMINAL=iTerm
```

| Key | Effect |
| --- | --- |
| `MUTE` | Comma-separated statuses to drop |
| `TERMINAL` | Force `Terminal`, `iTerm`, or `vscode` instead of the detected host |

`Replied` fires on **every** reply — the point when you have walked away, noise
when you are watching the chat. Muting it keeps the ones that actually need you.

Status names are matched case-insensitively, spaces around commas are fine, and
an unknown name is ignored. A malformed file cannot break the hook.

Every key also works as an environment variable prefixed `CLAUDE_NOTIFY_`
(e.g. `CLAUDE_NOTIFY_MUTE`), which overrides the file for a one-off.

### Where the session reopens

Clicking a banner reopens the session in your terminal — iTerm if that is what
you use, otherwise Terminal — detected from the process tree when the
notification is sent. Override it if the guess is wrong:

```bash
export CLAUDE_NOTIFY_TERMINAL=Terminal   # or iTerm, or vscode
```

The session reopens in a real terminal — Terminal or iTerm, whichever you use —
and reuses the tab already open for that session instead of stacking up a window
per click.

Running Claude Code inside VS Code is the one case where the host is
deliberately not followed: VS Code has no scriptable terminal, so the best it
could do is open the folder and leave you to paste the command. Resuming the
conversation is the point, so a VS Code session still gets a terminal. If you
would rather it just opened the folder, set
`CLAUDE_NOTIFY_TERMINAL=vscode`.

A resumed session is a *separate* Claude Code process reading the same
transcript, not a live view of the one you left. If you keep talking in the
original window, the resumed one will not see those messages — it shows the
conversation as of the moment it started. Resuming again picks up the rest.

### The icon costs you the click

macOS will not give you both. `terminal-notifier`'s `-sender` is what puts the
Claude icon on the banner, and it takes the click with it: with `-sender`
present, `-execute` is ignored, clicking the banner *body* does nothing, and
only the **Show** action button — which you have to hover to reveal — resumes
the session. Verified directly; it is a platform constraint, not a bug here.

Which way round you get depends on one thing: whether the icon bundle is
installed. With it, the banner carries the Claude icon and **Show** is the way
back in. Without it, the whole banner is clickable but shows the terminal's
icon. Run `setup-macos-icon.sh remove` to switch.

The icon path has a second cost worth knowing: the click target lives in a
single state file that each notification overwrites, so with two sessions
running, clicking an *older* banner opens whichever notified most recently —
macOS does not say which banner was clicked. Without the bundle every click is
exact.

## Uninstall

```
/plugin uninstall claude-notify-resume
```

Then, if you built the icon bundle: `scripts/setup-macos-icon.sh remove`

## Built with

No runtime dependencies — the plugin is shell plus one Node script, and
everything below is either already on the machine or optional.

| Area | Used |
| --- | --- |
| Language | Bash (POSIX-leaning, bash 3.2-compatible), Node.js (stdlib only) |
| Integration | Claude Code plugin API — `Stop` / `Notification` hooks, JSONL transcript parsing |
| macOS | `terminal-notifier`, AppleScript (`osascript`), a generated `.app` bundle for the icon |
| Linux | `notify-send` / libnotify, D-Bus |
| Testing | Docker (Debian, Ubuntu), stubbed binaries, a real D-Bus + notification-daemon harness |
| Tooling | shellcheck, npm scripts as the entry point |

## Contributing

Patches welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The most useful
contribution is a **tested Windows path**, which is the one platform this could
not be verified on.

## License

MIT
