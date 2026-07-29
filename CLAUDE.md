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
- **`-sender` and a clickable banner body are mutually exclusive.** `-sender`
  gives the banner the Claude icon and swallows the click: `-execute` is then
  ignored and only the *Show* button resumes. Verified directly — it is a
  platform constraint, which is why the icon is opt-in behind
  `CLAUDE_NOTIFY_ICON=1`. `LSUIElement` and the alert style are *not* the cause;
  both were investigated and cleared.
- **Never build the click action by nesting quotes.** It once nested a shell
  command inside an AppleScript literal inside a single-quoted `-execute` arg;
  a space produced `\ ` and an apostrophe closed a layer early, both silently.
  The click now calls `open-session.sh` with `printf %q` arguments — keep any
  new logic in that script rather than growing the string again.
- **`TERM_PROGRAM` is empty in the hook environment,** so the host app cannot be
  detected at click time (by then the frontmost app is Notification Centre).
  `notify-macos.sh` walks the process tree while the hook runs and passes
  `CLAUDE_NOTIFY_HOST` through to the click.
- **A bare `osascript` notification is owned by Script Editor** — clicking it
  opens Script Editor's file dialog. Send user-facing notifications through
  `terminal-notifier` when it is available (`notify()` in `open-session.sh`).
- **Old banners carry the command that was current when they were sent.** A
  banner sitting in Notification Centre still runs the *old* click action, so
  clear them (`terminal-notifier -remove ALL`) before testing a change to it,
  or you will debug a fix that is already in place.

## Keeping this file honest

When a change corrects a wrong assumption — especially one that took an
experiment to settle — add it to the traps above in the same commit. The bar is
"cost real time and is not visible in the code", not "might be interesting":
this file earns its keep only if it stays short enough to read in full.

Two habits that paid off repeatedly here, both worth continuing:

- **Verify the test, not just the code.** After adding an assertion, break the
  fix on purpose and confirm the test fails. Several "passing" tests here proved
  vacuous — one asserted on a `sed` expression that mangled its own input,
  another checked a branch the machine never took.
- **Prefer an experiment to a plausible theory.** `LSUIElement`, the alert
  style, and the notification style were all convincing explanations for the
  click problem. All three were wrong; a two-minute test with `-execute` and no
  `-sender` settled it.

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
