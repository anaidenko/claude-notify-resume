---
name: release
description: Use when cutting a new version of claude-notify-resume (asked to release, ship, tag or publish a version, put it on npm, or create a GitHub Release), or when a version tag's Publish run failed and needs recovery.
---

# Release

A release is one commit plus one annotated tag on `main`. Pushing the tag runs
[publish.yml](../../../.github/workflows/publish.yml), which publishes
`@anaidenko/claude-notify-resume` to npm and then creates the GitHub Release.
Marketplace users get the new version through `plugin.json`.

Two actions here cannot be undone: the push, and (first release on npm only)
the hand-published release candidate. An npm version is permanent, and installed
copies pick up a bump on `main`. **Ask before each of them**, and show exactly
what will go out. Everything else is local and can be undone.

## 1. Preflight

Stop and report if any of these fail:

```bash
git switch main && git status --porcelain        # must print nothing
git fetch origin && git status -sb               # not behind origin/main
npm run lint
npm test                                         # takes 2+ min: timeout 600000 or background
PREV="v$(node -p "require('./.claude-plugin/plugin.json').version")"
git log "$PREV"..HEAD --oneline                  # must not be empty
```

`origin/main` must already hold everything except the release commit, with CI
green on it. If HEAD is ahead, ask, push `main`, and wait for CI
(`gh run watch`). The release commit only changes docs and the version, and
`publish.yml` re-runs only the npm suites. So a green CI on the commit before
it is what vouches for the code that ships.

When `npm view @anaidenko/claude-notify-resume` answers **404**, the package
does not exist yet: do [First publish](#first-publish-only-when-npm-has-no-package)
between steps 2 and 3.

## 2. Version and summary

- **Version**, from the changes since `$PREV`. A fix is a patch. A new
  capability users can see is a minor. If a user's setup stops working
  unchanged (a config key removed, a platform dropped), it is a major. Ask
  when the call is not obvious.
- **Summary:** a short lowercase phrase naming the headline change *for
  users*, e.g. `a VS Code session reopens in its own tab`. The commit, the tag
  and the Release title all carry it.

## 3. CHANGELOG

The section becomes the GitHub Release notes verbatim, so it has to stand on
its own for a user.

- If `## Unreleased` exists, rename it to `## X.Y.Z — YYYY-MM-DD` (today:
  `date +%F`). Then check it against `git log "$PREV"..HEAD`: add any
  user-visible change it is missing.
- Otherwise write the section from that log. `feat:` and `fix:` commits are
  the material. `docs: Record …` commits are internal trap notes: leave them
  out.
- Use `### Added` / `### Changed` / `### Fixed`. Wrap at 80 columns, and match
  the tone of the entries below it: what changed for the user, and what to do
  if anything.

## 4. Bump, commit, tag

The version lives only in `.claude-plugin/plugin.json`. Never add one to
`package.json`; `publish.yml` injects it at publish time.

```bash
node -e 'const f=".claude-plugin/plugin.json",fs=require("fs"),j=JSON.parse(fs.readFileSync(f));j.version="X.Y.Z";fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")'
git add .claude-plugin/plugin.json CHANGELOG.md
git diff --cached --stat                         # exactly these two files
git commit -m "docs: Release X.Y.Z — <summary>"
git tag -a vX.Y.Z -m "X.Y.Z — <summary>"
```

The tag subject must start with the bare version: `publish.yml` titles the
Release `v` + that subject, and fails the run if the tag does not equal
`v` + the `plugin.json` version.

## 5. Ask before pushing

Show the user:
- the version and summary;
- the CHANGELOG section;
- `git log origin/main..HEAD --oneline`, which should be the single release
  commit;
- that the push publishes `X.Y.Z` to npm permanently, creates the GitHub
  Release, and offers the update to every installed copy.

Push only after an explicit yes in this conversation.

## 6. Push and watch

```bash
git push --follow-tags          # never --tags: it pushes the tag without the commit
gh run list --workflow publish.yml --commit "$(git rev-parse HEAD)" --json databaseId,status
gh run watch <databaseId> --exit-status
```

The run can take a few seconds to appear: repeat the `list` until it does.
Right after a push, an unfiltered `--limit 1` can return the previous release's
run.

## 7. Verify the result, not the log

```bash
npm view @anaidenko/claude-notify-resume version                 # X.Y.Z (the registry can lag a minute)
npm view @anaidenko/claude-notify-resume@X.Y.Z dist.attestations # non-empty: provenance from CI
gh release view vX.Y.Z --json name,url
```

A version published by hand has no attestations. That is expected for the
first-publish `rc.0`, and a red flag for any other version.

Then report the Release and npm links, plus the update line for users:
`npx @anaidenko/claude-notify-resume`, or
`claude plugin marketplace update anaidenko && claude plugin update claude-notify-resume@anaidenko`.

The marketplace repo (`anaidenko/claude-plugins`) needs no change, unless the
plugin's description or repo URL changed (CONTRIBUTING → The marketplace).

## When the Publish run fails

| Failed step | Cause | Fix |
| --- | --- | --- |
| Check the tag matches plugin.json | tagged without the bump | Nothing was published: confirm with `npm view …@X.Y.Z` (404). Then `git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z`, add a fix commit (never amend a pushed one), and tag that commit. |
| Publish: 404, ENEEDAUTH, OIDC errors | the trusted publisher is missing, does not allow `npm publish`, or expired (a new one lapses 2 days after creation without a successful publish) | npmjs.com → package → Settings → Trusted publishing. Re-create it if it expired ([First publish](#first-publish-only-when-npm-has-no-package), step 3), then `gh run rerun <id> --failed`. |
| GitHub Release, npm already done | | `gh run rerun <id> --failed`: the npm job skips a version it already has. |
| Release notes are the generic fallback | the CHANGELOG heading did not match `## X.Y.Z` | `gh release edit vX.Y.Z --notes-file <file>` |
| A bad version reached npm | | Never `npm unpublish`. Run `npm deprecate @anaidenko/claude-notify-resume@X.Y.Z "<why>"` and ship a fix. |

Never move a tag once npm has its version.

## First publish (only when npm has no package)

A trusted publisher can be configured only for a package that exists. A new
configuration **expires unless a publish succeeds through it within 2 days**.
So a release candidate creates the package by hand, and the real version goes
out through CI the same day, which validates the configuration.

Every npm write on the maintainer's account asks for a 2FA code, which this
session cannot enter. Give the user each npm command to run in their own
terminal, then check the result yourself with `npm view`.

1. **Ask first.** Show the user `X.Y.Z-rc.0` and say it stays in npm's version
   list for good, marked as a pre-release.
2. The user runs this from the clean HEAD, which `origin/main` already has:
   ```bash
   npm pkg set version=X.Y.Z-rc.0 && npm publish --tag next; git checkout package.json && git status --porcelain
   ```
   The rc is built from the pre-bump tree. Its `plugin.json` still says the
   previous version, and its CHANGELOG has no `X.Y.Z` section. That is
   harmless, since npm does not deliver the plugin. Leave it as it is.

   **Expect a placeholder first.** npm answers "Your package is being
   processed", and for about 2 minutes `npm view … versions` lists only
   `0.0.0-stage`, tagged `latest`. That happens even with a plain
   `npm publish`, and the placeholder stays in the version list for good. It
   is not a staged publish waiting for approval (`npx npm@11 stage list`
   shows nothing). Wait until the rc is listed, then have the user run
   `npm deprecate @anaidenko/claude-notify-resume@0.0.0-stage "registry placeholder"`.
   The trusted publisher's 2-day clock should not start before the rc is
   visible.
3. The user creates the trusted publisher. Make sure `publish.yml` is on
   `origin/main`: npm checks that the file exists.
   - **Default, on the website:** npmjs.com → package → Settings → Trusted
     publishing → GitHub Actions. User `anaidenko`, repository
     `claude-notify-resume`, workflow `publish.yml`, allow `npm publish`.
     Publishing access "Require two-factor authentication and disallow
     tokens" is compatible: the 1.4.0 CI publish went through with it set.
   - **From the CLI,** which needs npm 11 and also asks for a 2FA code. Check
     the flags with `npx npm@11 trust github --help` first:
     `npx npm@11 trust github @anaidenko/claude-notify-resume --file publish.yml --repo anaidenko/claude-notify-resume --allow-publish`
4. Check the release candidate:
   - `npx @anaidenko/claude-notify-resume@next --help` works;
   - the npm page renders the README.
5. Continue at step 3 now. The 2-day clock started at step 3 of this section,
   and only the CI publish of `X.Y.Z` stops it. If that run fails, fix it and
   re-run within the same window. Otherwise re-create the trusted publisher
   first.
