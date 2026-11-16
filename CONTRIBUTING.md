# Contributing

Bug reports and patches are welcome. The project is small on purpose — bash
plus two Node files (the hook's transcript parser and the `npx` installer), no
dependencies, no build step.

## Running the tests

```bash
npm test              # native suite for your platform
npm run test:all      # + other platforms, where possible (Docker)
npm run test:dbus     # end-to-end Linux delivery, real D-Bus + daemon
npm run lint          # shellcheck
```

Three suites, in increasing order of what they prove:

| Suite | Proves |
| --- | --- |
| `test:macos` / `linux-suite.sh` | the script builds the right notifier command |
| `test:dbus` | a real notification daemon *receives* the title, body and icon |
| `notify:demo` | a human sees the banner (the only thing automation cannot check) |

Neither suite needs the plugin installed — they run the scripts straight out of
the repo. Neither one delivers a real notification either: `terminal-notifier`,
`osascript` and `notify-send` are shadowed by stubs that record their arguments,
so a test run never touches your Notification Centre. To see an actual banner,
use `npm run notify:demo`.

Add a distro by passing it through:

```bash
./test/run-linux-tests.sh debian:trixie-slim
```

## The one rule

**A hook must never break the user's session.** Claude Code runs these scripts
on every turn, so any failure — missing binary, malformed payload, unreadable
transcript — has to exit 0 silently. Please keep new code inside that
constraint, and add a case to the suite covering the failure you introduced a
path for.

## Where help is most useful

- **Windows.** Deliberately unimplemented: it could not be verified from a
  macOS machine, and shipping untested platform code seemed worse than shipping
  none. A tested PowerShell path (BurntToast or a native toast) is the single
  biggest gap.

    Since the maintainer cannot run Windows, a PR adding it has to carry its own
    evidence. Please include:

    1. **A screenshot of the actual notification**, showing the status as the
       title and the chat name as the body.
    2. **Your environment** — Windows version, PowerShell version, and whether
       you used BurntToast or a native toast API.
    3. **A test suite** in the shape of the existing ones (`test/*-suite.sh`
       stub the notifier and assert on its arguments), plus the output of
       running it.
    4. **Confirmation that every failure path exits 0** — no notifier
       installed, malformed payload, empty stdin. This is the one rule above,
       and it is what protects users from a broken hook.

    Without a Windows machine to check against, that evidence is what makes the
    difference between merging and leaving the PR open. A patch that only
    *looks* correct will not be merged — that is the same standard the Linux
    path was held to.
- **Other Linux distros and desktop environments.** The suite covers Debian and
  Ubuntu; `notify-send` behaviour varies with the notification daemon, so
  reports from KDE, GNOME on Wayland, and others are useful.
- **Click-to-resume on Linux.** `notify-send` has no portable click action, so
  there is currently none. If your daemon supports actions, a guarded
  implementation would be welcome.

## Things worth knowing before you patch

Two non-obvious behaviours the code works around — both cost hours to find, so
they are worth stating plainly:

- **`ai-title` is an internal transcript record, not a public API.** It is how
  the banner learns the chat's name. If it ever changes shape, the fallback to
  the project directory name is what keeps this working.
- **macOS grants notification permission per bundle id, once, on that id's
  first appearance.** Changing `BUNDLE_ID` in `setup-macos-icon.sh` turns every
  existing install into a new, unapproved sender whose banners vanish with no
  error and a success exit code. Don't change it.

## Releasing

Claude Code caches an installed plugin in a directory named after its version,
so **bumping `version` in `.claude-plugin/plugin.json` is what makes an update
reachable** — push alone leaves existing installs on the cached copy.

In Claude Code, `/release` walks through all of it (see
[.claude/skills/release/SKILL.md](.claude/skills/release/SKILL.md)) and asks
before it pushes. By hand:

1. Bump `version` in `.claude-plugin/plugin.json` (semver).
2. Turn `## Unreleased` in `CHANGELOG.md` into `## X.Y.Z — YYYY-MM-DD`.
3. Commit as `docs: Release X.Y.Z — <summary>`, tag with the same subject, and
   push both together:
   `git tag -a vX.Y.Z -m "X.Y.Z — <summary>" && git push --follow-tags`.
   (`git push --tags` pushes *only* tags, which leaves the tag on GitHub pointing
   at a commit that is not there yet.)
4. The tag runs [publish.yml](.github/workflows/publish.yml). It checks the tag
   against `plugin.json`, publishes to npm, then creates the GitHub Release.
   The Release is titled with the tag's subject, and its notes are the CHANGELOG
   section.
5. Users on auto-update get it automatically; others run
   `npx @anaidenko/claude-notify-resume` again, or
   `claude plugin marketplace update anaidenko && claude plugin update claude-notify-resume@anaidenko`.

That field is the only place a version lives — `package.json` deliberately has
none, so the two cannot drift. `publish.yml` injects it at publish time.

### npm

The package [`@anaidenko/claude-notify-resume`](https://www.npmjs.com/package/@anaidenko/claude-notify-resume)
carries the `npx` installer. Installed copies still come from the marketplace,
never from npm.

- **No token anywhere.** CI publishes through npm Trusted Publishing (OIDC).
  The trusted publisher on npmjs.com names the workflow file, so renaming
  `publish.yml` breaks publishing until the npm side is set up again.
- **The very first npm release is different.** A trusted publisher can only be
  configured for a package that already exists, and a new one expires 2 days
  after creation unless a publish succeeds through it. See *First publish* in
  the release skill.
- **A failed publish job is re-run, never re-tagged.** Fix the cause, then run
  `gh run rerun <id> --failed`. The job skips a version npm already has, so
  re-runs are safe.
- **Never `npm unpublish`.** It works only within 72 hours, and a version number
  can never be reused. To retract a bad release, `npm deprecate` it and ship a
  fix.

### The marketplace

The plugin is served from [anaidenko/claude-plugins](https://github.com/anaidenko/claude-plugins),
which references this repo by URL. **A release does not touch it:** versions are
read from `plugin.json` at install time, and the manifest deliberately carries no
`version` field to keep in sync.

It does need an edit when this repo is renamed or moved (its `url` there points
at the old location) or when the one-line description users see in the plugin
browser changes — that copy lives in the manifest, not here.

Note that this repo has no `marketplace.json` of its own, deliberately.
Marketplaces are keyed by the `name` inside that file rather than by repo URL,
so a second repo declaring the same name silently takes the slot; the loser's
plugin stays `enabled` while failing to load, with its hooks quietly dead. That
happened here — hence the shared marketplace.

## Style

Match the surrounding code: 4-space indent in shell, `set -uo pipefail`,
comments that explain *why* rather than restating the line. Run `npm run lint`
before opening a PR.
