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
- **A manual chat rename is a `custom-title` record, not a new `ai-title`.**
  Worse, after a rename the transcript keeps re-emitting the *old* `ai-title`
  on every turn, *after* each `custom-title` — so "last title record wins"
  silently reverts the rename. The parser must prefer `custom-title` by type;
  position in the file proves nothing.
- **Never spoof the sender with a fake, script-only bundle.** The `-sender`
  scheme swallowed the body click by design, and macOS's willingness to launch
  the fake app on click proved undocumented and flaky: it worked, then refused
  (unsigned), then launched at *delivery* time after signing, then went silent
  even with a fresh `usernoted`. The answer was a real compiled app
  (`claude-notify.swift`) that posts natively — the icon and the body click
  stopped being enemies the moment the notification had a real owner.
- **`usernoted` caches the notification→app binding.** Rebuilding a bundle
  leaves banners bound to the old snapshot; `killall usernoted` resets the
  daemon (it restarts itself). A useful diagnostic, though not a fix for the
  spoofed-sender scheme above.
- **A cold `activate` of Terminal opens its startup window,** so a `do script`
  on top yields two windows — one empty, one yours. Check
  `application "Terminal" is running` (which does not launch it) and reuse the
  startup window on a cold start. Same for iTerm.
- **Stub probes need `</dev/null`.** An `osascript -e …` call without a heredoc
  inherits the caller's stdin; the test stub reads stdin to capture heredoc
  bodies, so without the redirect the suite hangs forever.
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
- **Claude Code overwrites a Terminal tab's `custom title`** with the chat's
  own name, so a marker written there does not survive and tab reuse silently
  degrades to a new window per click. Match the tab by tty instead — find it
  with `ps ax -o tty=,command=` against `claude --resume <id>`.
- **The click handler gets a minimal PATH too,** not just the hook. Missing
  this made `open-session.sh` report "VS Code CLI not found" on a machine where
  `code` was installed — it simply was not on the click's PATH.
- **The state paths still say `claude-code-notify`** — `~/.claude/claude-code-notify`
  and `~/.local/state/claude-code-notify` — and that is deliberate. The plugin was
  renamed to `claude-notify-resume`, but renaming those directories would orphan
  the click state and icon bundle of every existing install for no user-visible
  gain. Same reasoning as `BUNDLE_ID`: internal identifiers stay put.
- **shellcheck versions disagree, so CI pins one.** Ubuntu's apt ships 0.9.0,
  which flags `A && B || C` (SC2015) where 0.11.0 stays quiet — a lint that was
  clean locally failed on the first CI run. The workflow fetches 0.11.0 directly
  and then runs `npm run lint`, so CI and a developer run the same check.
- **Marketplaces are keyed by the `name` inside `marketplace.json`,** not by
  repo URL. This repo and `claude-video-digest` both declared `"name":
  "anaidenko"`, so adding the second one silently took the slot — the first
  stayed `enabled: true` in settings while `claude plugin list` reported
  `failed to load`, and its hooks died with no error anywhere. It read as "the
  plugin broke", and cost a full debugging session. Both now live in
  `anaidenko/claude-plugins`, and neither repo carries a `marketplace.json`.
  Note `claude plugin marketplace update` does *not* re-read a changed `name`;
  that needs `remove` + `add`.
- **`git push --tags` pushes only tags, not the branch.** It left v1.1.2–v1.1.5
  on GitHub pointing at commits that had never been pushed, while `main` still
  showed 1.1.1 — so the marketplace kept serving the old version. Use
  `git push --follow-tags`.
- **Never bake a plugin-cache path into the icon bundle.** Updating installs a
  new `<version>/` directory and deletes the old one, so a path fixed at build
  time dies on the next update and the click silently does nothing. Resolve the
  newest `cache/*/claude-notify-resume/*/scripts/` at click time.
- **Old banners carry the command that was current when they were sent.** A
  banner sitting in Notification Centre still runs the *old* click action, so
  clear them before testing a change to it, or you will debug a fix that is
  already in place. `terminal-notifier -remove ALL` covers less than it sounds
  like: `ALL` is every group posted through terminal-notifier — including other
  projects' banners, since they all share the `fr.julienxx.oss.terminal-notifier`
  bundle — while banners from the native bundle (the main path since 1.1.9) are
  not its to remove and `-list ALL` does not even see them. Clear those by hand
  in Notification Centre. Per-session removal is `-remove claude-<session-id>`
  (the group set in `notify-macos.sh`); there is no wildcard.
- **One session can appear twice in `ps`.** The VS Code extension spawns a copy
  with no controlling terminal, printed as `??` and listed *before* the real
  tab, so `{ print $1; exit }` returned a tty no tab can own — the lookup failed
  and every click opened another window next to the session already running.
  Skip ttyless rows (`$1 != "??"`). The test that was meant to cover this
  asserted on its own inline copy of the awk, so it stayed green regardless of
  what the script did; it now lifts the expression out of `open-session.sh`.
- **Sort version directories numerically, not as strings.** The bundle's
  fallback picks the newest installed copy, and `"1.1.10" < "1.1.9"`
  lexicographically — so the first two-digit release quietly routed every
  fallback click into the *previous* version, the stale code the fallback exists
  to escape. Latent from the day the fallback was written; it woke up at 1.1.10.
- **`application "X" is running` lies in the click handler's environment.** It
  answers from the caller's Launch Services session, and both the hook and the
  click run stripped, so it returns `false` for a Terminal that is plainly on
  screen. The cold-start branch then fired on a *warm* start and produced the
  extra empty window it exists to prevent — the bug survived a release because
  the suite stubbed the probe's answer instead of its truthfulness. Use
  `pgrep -x`, which asks the kernel and launches nothing. Note the process is
  `iTerm2` even though the app is `iTerm`; matching the app name finds nothing
  and makes every start look cold.
- **The VS Code extension never emits the `Notification` hook event.** `Stop`
  fires there, so `Replied` banners arrive and the plugin looks healthy — but
  `Permission needed`, `Waiting for you` and every other Notification-based
  status cannot fire in a side-panel session, and no hooks.json change will
  help. Known Claude Code parity bug: anthropics/claude-code #59718, #31285,
  #26925, #11156. Diagnose it from transcripts, not theories: the machine's
  `~/.claude/projects/*/*.jsonl` showed `stop_hook_summary` records running
  `notify.sh "Replied"` while no `Notification` hookEvent existed in any
  transcript at all. The README states the limitation; keep it there until the
  upstream bug closes for real (the linked issues close as duplicates, not
  fixes).

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

## Planning a change

For anything larger than a one-file edit, `/plan-task` writes a structured plan to
`.claude/plans/` before any code is touched — see
[.claude/skills/plan-task/SKILL.md](.claude/skills/plan-task/SKILL.md). Plans are
gitignored personal working documents; commit one only when asked.

## Platform reality

macOS is the developed and daily-used path. Linux is covered by the container
suite, but no banner has ever been observed on a real Linux desktop — the
container has no notification daemon. Windows is deliberately absent rather
than shipped untested; do not add a Windows path that cannot be run.
