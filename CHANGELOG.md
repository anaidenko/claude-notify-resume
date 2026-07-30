# Changelog

Notable changes to this plugin. Versions follow [semver](https://semver.org);
the `version` field in `.claude-plugin/plugin.json` is what makes an update
reachable to installed copies (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## 1.1.0

### Added

- Clicking a banner reopens the session in your own terminal — iTerm if that is
  what you use, otherwise Terminal — detected from the process tree when the
  notification is sent.
- A second click focuses the tab already running that session instead of
  opening another window, matched by tty.

### Changed

- The Claude icon is now the default. It and a clickable banner body cannot
  coexist on macOS (`-sender` swallows the click), so resuming happens through
  the banner's *Show* button; remove the icon bundle for a fully clickable
  banner instead.
- Running Claude Code inside VS Code still resumes into a real terminal: VS Code
  has no scriptable terminal, and resuming the conversation matters more than
  landing in the editor. `CLAUDE_NOTIFY_TERMINAL=vscode` opts into folder-only.

### Fixed

- The icon bundle is a thin launcher for `open-session.sh` rather than a second
  copy of the same logic, which had already drifted out of step.
- The click handler restores `PATH`, so `code` and `terminal-notifier` resolve
  instead of being reported as missing.
- A vanished session folder is reported instead of opening a terminal on a bare
  `cd` failure.

## 1.0.2

### Added

- Clicking a banner now reopens the session in the app Claude Code is running
  under — VS Code, iTerm or Terminal — detected automatically, overridable with
  `CLAUDE_NOTIFY_TERMINAL`.
- Terminal and iTerm reuse the tab already open for a session instead of
  stacking up a new window per click.

### Fixed

- Made explicit that the Claude icon and a clickable banner body cannot
  coexist: `terminal-notifier`'s `-sender` gives the banner its icon but
  swallows the body click, leaving the *Show* button as the way to resume.
  Installing the icon bundle is what picks that side; removing it restores a
  fully clickable banner.
- A click landing on a folder that has since been renamed or deleted now says
  so, instead of opening a terminal on a bare `cd` failure.
- Notifications raised by the click handler go through `terminal-notifier`
  where possible: a bare `osascript` notification is owned by Script Editor, so
  clicking it opened Script Editor's file dialog.
- A working directory containing an apostrophe no longer breaks the click.

## 1.0.1

Fixes found in review before the first public release.

### Fixed

- **Click-to-resume no longer breaks on paths containing a space.** The resume
  command is shell-quoted with `printf %q`, which emits `My\ Project`; embedded
  in an AppleScript string literal that is a syntax error, so the click silently
  did nothing. Both the `-execute` path and the icon bundle now escape for
  AppleScript as well as for the shell.
- **The Linux banner shows its icon.** The icon path was resolved one directory
  too high, so the file was never found and `--icon` was silently dropped.
- **`last-session` is written atomically**, so a click landing mid-write can no
  longer read a half-written file.
- **The nvm fallback picks the newest Node**, not the lexicographically last —
  `v9` sorted after `v22`, and the parser needs modern syntax.

### Changed

- `npm test` runs the suite matching the current platform; on Linux it runs
  natively, without Docker.
- The test suites no longer touch real user state or deliver real banners: the
  notifier binaries are stubbed, and the state directory is overridable via
  `CLAUDE_NOTIFY_STATE_DIR`.
- `npm run notify:demo` sends a genuine banner (no `TEST ·` prefix) and accepts
  `CLAUDE_NOTIFY_DEMO_CHAT` to set the chat name.

### Added

- End-to-end Linux delivery test against a real D-Bus session and notification
  daemon, asserting what the daemon actually received.
- Test coverage for the Linux icon path and for a cwd containing spaces — both
  regressions that had shipped unnoticed.
- `CONTRIBUTING.md`, `CLAUDE.md`, and this changelog.

## 1.0.0

Initial release.

- Banners titled with the event status and bodied with the chat's own
  AI-generated name, read from the session transcript.
- Click a banner to resume that exact session (`claude --resume`).
- macOS via `terminal-notifier`, with an AppleScript fallback that needs
  nothing installed; optional icon bundle for the Claude icon.
- Linux via `notify-send`.
- Every failure path exits 0, so a broken notifier can never break a session.
