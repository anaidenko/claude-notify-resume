# claude-notify-resume

[![npm](https://img.shields.io/npm/v/@anaidenko/claude-notify-resume)](https://www.npmjs.com/package/@anaidenko/claude-notify-resume)
[![npm downloads](https://img.shields.io/npm/dm/@anaidenko/claude-notify-resume)](https://www.npmjs.com/package/@anaidenko/claude-notify-resume)
[![CI](https://github.com/anaidenko/claude-notify-resume/actions/workflows/ci.yml/badge.svg)](https://github.com/anaidenko/claude-notify-resume/actions/workflows/ci.yml)

Desktop notifications for [Claude Code](https://claude.com/claude-code) that
tell you **which conversation** replied — or is waiting on you — and take you
back into it.

<img src="https://raw.githubusercontent.com/anaidenko/claude-notify-resume/main/assets/banner-replied.png" alt="A macOS notification titled &quot;Replied&quot;, with the body &quot;Fix the geofence rounding bug&quot; — the name of the chat that finished." width="500">

*The body is the chat's own name, so you know which session it is.
(Click it to resume — see [where the session reopens](#where-the-session-reopens).)*

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

**Known limitation — VS Code extension.** Every status except `Replied` rides
on the `Notification` hook event, and the VS Code native extension never emits
it — a Claude Code CLI/extension parity bug, not something a plugin can work
around ([anthropics/claude-code#59718](https://github.com/anthropics/claude-code/issues/59718),
[#31285](https://github.com/anthropics/claude-code/issues/31285),
[#26925](https://github.com/anthropics/claude-code/issues/26925),
[#11156](https://github.com/anthropics/claude-code/issues/11156)). A session in
the VS Code side panel still gets `Replied` (the `Stop` hook fires there), but
no `Permission needed` or `Waiting for you` banner will ever appear for it.
Terminal sessions get all of them.

## Install

```bash
npx @anaidenko/claude-notify-resume
```

That adds the marketplace and installs the plugin, or updates it if it is
already installed. It needs Claude Code and Node.js, which the plugin uses
anyway. The npm package is only the installer: the plugin itself still comes
from the marketplace, so every install updates the same way, however it
started.

By hand, it is two commands:

```bash
claude plugin marketplace add anaidenko/claude-plugins
claude plugin install claude-notify-resume@anaidenko
```

The same thing works from inside a session as `/plugin marketplace add …` and
`/plugin install claude-notify-resume@anaidenko`; the CLI is shown here because
it prints what it did, which matters when something goes wrong.

Restart Claude Code afterwards — hook config is read at startup.

The plugin is served from [anaidenko/claude-plugins](https://github.com/anaidenko/claude-plugins),
a marketplace carrying several plugins — adding it once makes the others
available too.

Third-party marketplaces do not refresh themselves by default, so turn on
auto-update once and new versions arrive on their own: `/plugin` → **Marketplaces**
→ select `anaidenko` → enable auto-update. Claude Code then refreshes shortly
after a session starts and prompts you to `/reload-plugins`.

Without it, run the installer again (`npx @anaidenko/claude-notify-resume`),
or update by hand:

```bash
claude plugin marketplace update anaidenko
claude plugin update claude-notify-resume@anaidenko
```

**macOS** works out of the box via AppleScript. For click-to-resume, install
the notifier binary:

```bash
brew install terminal-notifier
```

Then build the icon bundle: it compiles a tiny native notifier (needs the Xcode
Command Line Tools — `xcode-select --install`), which gives every banner the
Claude icon while the whole banner stays clickable. The first banner without it
offers the setup command as a banner of its own and copies it to the clipboard;
it looks like this:

```bash
~/.claude/plugins/cache/anaidenko/claude-notify-resume/<version>/scripts/setup-macos-icon.sh
```

That script ends by sending a test banner. **If you do not see it**, open
**System Settings → Notifications → Claude Code** and turn on *Allow
notifications*: a newly created bundle starts switched off, and macOS then
discards its banners with no error and a success exit code.

**Linux** needs nothing beyond `notify-send`, which desktop distros ship with
libnotify preinstalled. If yours does not: `sudo apt install libnotify-bin`
(or your distro's package). Without it no banner can appear at all — the hook
stays silent by design rather than interrupting your session.

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
**posting application**, and `terminal-notifier`'s `-appIcon` / `-contentImage`
do not affect that slot. So `setup-macos-icon.sh` builds a small real app —
`scripts/claude-notify.swift`, compiled on your machine — that posts the
notification natively and receives the click itself, with the session id riding
inside each notification. (Spoofing the sender with `-sender` was tried first:
it swallows the body click and its click-to-launch behaviour proved
undocumented and flaky.)

| File | Role |
| --- | --- |
| `hooks/hooks.json` | Declares the `Stop` / `Notification` hooks |
| `scripts/notify.sh` | Parses the payload, resolves the chat name, dispatches per platform |
| `scripts/notify-parse.js` | Reads the payload + `ai-title` from the transcript |
| `scripts/notify-macos.sh` | Builds and sends the macOS banner |
| `scripts/notify-linux.sh` | Builds and sends the Linux banner |
| `scripts/open-session.sh` | Reopens a session when a banner is clicked |
| `scripts/load-config.sh` | Reads the config file, letting the environment win |
| `scripts/setup-macos-icon.sh` | Compiles and installs the icon bundle (macOS setup) |
| `scripts/claude-notify.swift` | The bundle's notifier: posts natively, handles the click |
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

# Force a terminal instead of the detected one: Terminal or iTerm
TERMINAL=iTerm
```

| Key | Effect |
| --- | --- |
| `MUTE` | Comma-separated statuses to drop |
| `TERMINAL` | Force `Terminal` or `iTerm` instead of the detected one |

`Replied` fires on **every** reply — the point when you have walked away, noise
when you are watching the chat. Muting it keeps the ones that actually need you.

Status names are matched case-insensitively, spaces around commas are fine, and
an unknown name is ignored. A malformed file cannot break the hook.

Every key also works as an environment variable prefixed `CLAUDE_NOTIFY_`
(e.g. `CLAUDE_NOTIFY_MUTE`), which overrides the file for a one-off.

### Where the session reopens

Clicking a banner reopens the session where it was running. The plugin detects
that from the process tree when the notification is sent:

- **The VS Code extension:** the session's own tab, in the window it belongs
  to, even when another VS Code window was active. If that window has closed
  since, or VS Code has restarted, the session resumes in a terminal instead.
- **iTerm or Terminal:** that terminal, focusing the tab already running the
  session rather than opening a new window for each click.

For banners with the Claude icon, the VS Code tab needs the notifier from 1.3.3
or later. Re-run `setup-macos-icon.sh` once after updating; until then those
clicks open a terminal.

A CLI session in VS Code's integrated terminal resumes in a real terminal, as
does VS Code Insiders. The integrated terminal has no tab to return to and
cannot be driven by a script, and the Insiders path is untested.

Two things worth knowing about a resumed session:

- It is a *separate* Claude Code process reading the same transcript, not a live
  view of the one you left. Keep talking in the original window and the resumed
  one will not see those messages — it shows the conversation as of the moment
  it started. Resuming again picks up the rest.

## Uninstall

```bash
claude plugin uninstall claude-notify-resume@anaidenko
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
| Distribution | Claude Code marketplace (git); npm for the `npx` installer, published from CI via Trusted Publishing |

## Contributing

Patches welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The most useful
contribution is a **tested Windows path**, which is the one platform this could
not be verified on.

## License

MIT
