#!/usr/bin/env bash
# Checks what the npm package would ship, without publishing anything.
#
#   ./test/package-suite.sh
#
# The `files` whitelist in package.json decides the tarball. A file missing from
# it breaks every install that comes from npm (the hook points at
# scripts/notify.sh), while a file wrongly included is effectively permanent,
# because npm allows an unpublish only within 72 hours. So the suite asserts on
# both sides.
#
# It packs a copy of the whole working tree, ignored files included, and plants
# decoys. Packing a clean checkout would leave nothing for the exclusions to
# exclude, so they would pass whatever `files` says.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

command -v npm >/dev/null 2>&1 || {
    printf 'npm not found; this suite needs it to pack.\n' >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Everything but git's own data and installed modules.
(cd "$REPO_ROOT" && tar --exclude=./.git --exclude=./node_modules -cf - .) | (cd "$WORK" && tar -xf -)
mkdir -p "$WORK/tmp"
printf 'decoy\n' >"$WORK/tmp/leak.txt"
printf 'decoy\n' >"$WORK/.DS_Store"

# The repo has no version on purpose; publish.yml injects one the same way.
(cd "$WORK" && npm pkg set version=0.0.0-test >/dev/null) || {
    printf 'could not set a test version\n' >&2
    exit 1
}

PACKED="$(cd "$WORK" && npm pack --dry-run --json 2>/dev/null)"
FILES="$(printf '%s' "$PACKED" | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        for (const f of JSON.parse(s)[0].files) console.log(f.path);
    });' 2>/dev/null)"

if [ -z "$FILES" ]; then
    printf '  FAIL  npm pack produced no file list\n%s\n' "$PACKED"
    exit 1
fi

has() {
    if printf '%s\n' "$FILES" | grep -qxF "$1"; then
        printf '  ok    ships %s\n' "$1"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  missing %s\n' "$1"
        FAIL=$((FAIL + 1))
    fi
}

lacks() {
    local hit
    hit="$(printf '%s\n' "$FILES" | grep -E "$1" | head -1)"
    if [ -z "$hit" ]; then
        printf '  ok    leaves out %s\n' "$2"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  ships %s (%s)\n' "$2" "$hit"
        FAIL=$((FAIL + 1))
    fi
}

printf '═══ npm package contents\n'

# Every runtime file the plugin and the installer use. scripts/ is listed from
# git rather than by hand, so a new script cannot be forgotten here.
has package.json
has README.md
has LICENSE
has CHANGELOG.md
has .claude-plugin/plugin.json
has hooks/hooks.json
has bin/claude-notify-resume.js
has assets/claude-logo.png
has claude-notify-resume.conf.example
while IFS= read -r f; do
    has "$f"
done < <(cd "$REPO_ROOT" && git ls-files scripts)

lacks '^test/' 'the test suites'
lacks '^tmp/' 'tmp/'
lacks '^\.github/' '.github/'
lacks '^\.claude/' '.claude/ (skills, plans)'
lacks '^CLAUDE\.md$' 'CLAUDE.md'
lacks '^CONTRIBUTING\.md$' 'CONTRIBUTING.md'
lacks '\.DS_Store$' '.DS_Store'
lacks '^assets/(banner|social)' 'README-only images'

# npm would publish a bin without its shebang and the command would not run.
if head -1 "$REPO_ROOT/bin/claude-notify-resume.js" | grep -q '^#!/usr/bin/env node'; then
    printf '  ok    the bin starts with a node shebang\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL  the bin has no node shebang\n'
    FAIL=$((FAIL + 1))
fi

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
