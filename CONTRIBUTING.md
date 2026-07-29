# Contributing

Bug reports and patches are welcome. The project is small on purpose — bash
plus one Node file, no dependencies, no build step.

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

1. Bump `version` in `.claude-plugin/plugin.json` (semver).
2. Commit and push; tag the release (`git tag v1.1.0 && git push --tags`).
3. Users pick it up with `/plugin update claude-code-notify`.

That field is the only place a version lives — `package.json` deliberately has
none, so the two cannot drift.

## Style

Match the surrounding code: 4-space indent in shell, `set -uo pipefail`,
comments that explain *why* rather than restating the line. Run `npm run lint`
before opening a PR.
