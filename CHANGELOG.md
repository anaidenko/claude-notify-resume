# Changelog

Notable changes to this plugin. Versions follow [semver](https://semver.org);
the `version` field in `.claude-plugin/plugin.json` is what makes an update
reachable to installed copies (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## 1.1.6

Fixes from an independent review.

### Fixed

- **Clicking a banner from an editor-hosted session now finds its tab.** The
  VS Code extension spawns `claude --resume=<id>`; the lookup only matched the
  space-separated form, so those sessions never matched.
- **A click no longer does nothing when the session's tab belongs to another
  app** (a different terminal, tmux, or no tty at all) — it opens a new window
  instead of silently activating the app.
- **`CLAUDE_NOTIFY_MUTE=` (empty) now overrides the config file**, which is how
  you switch muting off for a single run; it was being ignored.
- **A `#` inside a quoted config value is kept** instead of truncating the value.
- The icon-setup offer arrives as a banner with the command on the clipboard.
  It used to print to stderr, which Claude Code discards for a hook that exits 0
  — so nobody ever saw it.
- `npm run notify:demo` no longer overwrites the real click target, which made a
  later **Show** on a genuine banner resume a session that never existed.

## 1.1.5

Documentation only.

- The config file is the single documented way to change settings; the README no
  longer suggests `export`.
- The icon is presented as part of macOS setup rather than a choice to weigh:
  resuming from **Show** is simply how it works.

## 1.1.4

- The plugin prints the icon-setup command once, with the real path for your
  install, instead of asking the README to describe a versioned cache path.

## 1.1.3

Documentation only.

- Install and update instructions use the `claude plugin` CLI, which reports
  what it did; the slash-command equivalents are noted alongside.
- Commands name the marketplace (`claude-notify-resume@anaidenko`), so they stay
  unambiguous now that a similarly named plugin exists elsewhere.
- The icon-bundle path picks the newest cached version instead of globbing every
  installed one — with two versions cached, the glob expanded to two paths and
  `setup-macos-icon.sh remove` silently ran the install flow instead.

## 1.1.2

Documentation only — no change to how the plugin behaves.

- README explains marketplace auto-update, so new versions arrive without
  running two commands by hand.
- Added issue templates.

## 1.1.1

No functional change — the plugin behaves exactly as 1.1.0.

- CI pins shellcheck 0.11.0 instead of taking Ubuntu's 0.9.0, which disagreed
  about `A && B || C` and failed a lint that was clean locally.
- Added a social preview image.

## 1.1.0

### Added

- `MUTE` drops the statuses you would rather not hear about — e.g.
  `MUTE=Replied,Waiting for you` keeps only the banners that need you.
- Settings live in `~/.claude/claude-notify-resume.conf` (see the example file),
  with `CLAUDE_NOTIFY_*` environment variables as one-off overrides.
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

## 1.0.0

First release.

- Banners titled with the event status — `Replied`, `Permission needed`,
  `Waiting for you`, `Input needed`, and the background-agent pair — and bodied
  with the chat's own AI-generated name, read from the session transcript.
- Click a banner to resume that exact session (`claude --resume`), which keeps
  working after the terminal tab is closed.
- macOS via `terminal-notifier`, with an AppleScript fallback that needs nothing
  installed; an optional bundle supplies the Claude icon.
- Linux via `notify-send`, verified against a real notification daemon over
  D-Bus.
- Every failure path exits 0, so a missing notifier or malformed payload can
  never break a session.
