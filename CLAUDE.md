# CLAUDE.md

Notes for working on this repo with Claude Code. Start with
[CONTRIBUTING.md](CONTRIBUTING.md) for tests and the release process; this file
only records what is easy to get wrong.

## The one rule

**A hook must never break the user's session.** These scripts run on every
turn, so every failure path exits 0 silently — missing binary, malformed
payload, unreadable transcript. Do not add a path that can exit non-zero, and
do not "improve" error handling by surfacing errors to the user.

## Traps that already cost hours

- **`bash -x` traces a command *and still runs it*.** Asserting on a trace is
  how the macOS suite used to deliver real banners on every test run. Use the
  `CLAUDE_NOTIFY_BIN` stub directory instead — `test/run-macos-tests.sh` shows
  the pattern.
- **Never change `BUNDLE_ID`** in `scripts/setup-macos-icon.sh`. macOS grants
  notification permission per bundle id, once, on that id's first appearance.
  A new id turns every existing install into an unapproved sender whose
  banners vanish with no error and a success exit code.
- **A `-title` starting with `[` is swallowed by `terminal-notifier`,** which
  falls back to its own default of "Terminal". Hence the `TEST ·` marker rather
  than `[TEST]`.
- **`notify.sh` deliberately puts `/opt/homebrew/bin` ahead of the caller's
  `PATH`** — hooks inherit a minimal environment where `node` and
  `terminal-notifier` are both missing. Prepending a stub directory to `PATH`
  therefore does not shadow them; that is what `CLAUDE_NOTIFY_BIN` is for.
- **`ai-title` is an internal transcript record, not a public API.** It is how
  the banner learns the chat's name. Keep the fallback to the project directory
  name working.

## Verifying a change

```bash
npm test              # macOS, fast
npm run test:linux    # Linux, in Docker
npm run lint          # shellcheck — keep it at zero warnings
```

Both suites run the scripts straight out of the repo, so neither needs the
plugin installed. Add a test with any new failure path — the Linux icon path
was silently broken precisely because nothing asserted on it.

To see a real banner rather than assert on arguments: `npm run notify:demo`.

## Platform reality

macOS is the developed and daily-used path. Linux is covered by the container
suite, but no banner has ever been observed on a real Linux desktop — the
container has no notification daemon. Windows is deliberately absent rather
than shipped untested; do not add a Windows path that cannot be run.
