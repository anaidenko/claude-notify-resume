#!/usr/bin/env bash
# Checks for the npx installer, bin/claude-notify-resume.js.
#
#   ./test/install-suite.sh
#
# `claude` is shadowed by a stub that records every call and answers the two
# `--json` queries from STUB_MARKETPLACES / STUB_PLUGINS, so nothing is
# installed. A plain PATH stub is enough here: unlike notify.sh, the installer
# does not put /opt/homebrew/bin ahead of PATH. Runs on macOS and Linux.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/bin/claude-notify-resume.js"
PLUGIN_ID="claude-notify-resume@anaidenko"
PASS=0
FAIL=0

NODE="$(command -v node)" || {
    printf 'node not found; the installer needs it.\n' >&2
    exit 1
}

STUB_BIN="$(mktemp -d)"
EMPTY_BIN="$(mktemp -d)"
STUB_LOG="$STUB_BIN/calls.log"
trap 'rm -rf "$STUB_BIN" "$EMPTY_BIN"' EXIT

# STUB_PLUGINS_AFTER, when set, is the plugin list once `plugin install` has run.
cat >"$STUB_BIN/claude" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >>"$STUB_LOG"
case "\$*" in
    "plugin marketplace list --json") printf '%s\n' "\${STUB_MARKETPLACES:-[]}" ;;
    "plugin list --json")
        if [ -n "\${STUB_PLUGINS_AFTER:-}" ] && grep -q '^plugin install' "$STUB_LOG"; then
            printf '%s\n' "\$STUB_PLUGINS_AFTER"
        else
            printf '%s\n' "\${STUB_PLUGINS:-[]}"
        fi
        ;;
    *) [ -n "\${STUB_FAIL_ON:-}" ] && [ "\$*" = "\$STUB_FAIL_ON" ] && exit 7 ;;
esac
exit 0
STUB
chmod +x "$STUB_BIN/claude"

# On macOS the installer builds the notifier app once the Xcode tools answer.
# Missing by default, so the checks below see no build; STUB_CLT=1 has them.
cat >"$STUB_BIN/xcode-select" <<'STUB'
#!/bin/bash
[ "${STUB_CLT:-}" = 1 ] && { echo /Library/Developer/CommandLineTools; exit 0; }
exit 2
STUB
chmod +x "$STUB_BIN/xcode-select"

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        printf '  ok    %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*)
            printf '  ok    %s\n' "$name"
            PASS=$((PASS + 1))
            ;;
        *)
            printf '  FAIL  %s\n        missing: %s\n        in:      %s\n' "$name" "$needle" "$haystack"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

# run [VAR=value ...] [-- installer args]: sets OUT, CODE and CALLS
# (the stub's calls joined by " | ").
run() {
    local -a envs=() args=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    [ "${1:-}" = "--" ] && shift
    args=("$@")
    : >"$STUB_LOG"
    OUT="$(env PATH="$STUB_BIN:$PATH" ${envs[@]+"${envs[@]}"} "$NODE" "$INSTALLER" ${args[@]+"${args[@]}"} 2>&1 </dev/null)"
    CODE=$?
    CALLS="$(paste -sd'|' "$STUB_LOG" | sed 's/|/ | /g')"
}

OURS_GITHUB='[{"name":"anaidenko","source":"github","repo":"anaidenko/claude-plugins"}]'
OURS_URL='[{"name":"anaidenko","source":"git","url":"https://github.com/anaidenko/claude-plugins.git"}]'
FOREIGN='[{"name":"anaidenko","source":"github","repo":"anaidenko/claude-notify-resume"}]'
INSTALLED='[{"id":"claude-notify-resume@anaidenko","version":"1.3.3","scope":"user"}]'
OTHER_PLUGIN='[{"id":"something-else@anaidenko","version":"1.0.0","scope":"user"}]'

printf '═══ npx installer\n'

run
check "fresh machine: adds the marketplace, then installs" \
    "plugin marketplace list --json | plugin marketplace add anaidenko/claude-plugins | plugin list --json | plugin install claude-notify-resume@anaidenko" \
    "$CALLS"
check "fresh machine: exits 0" "0" "$CODE"
contains "fresh machine: says to restart" "Restart Claude Code" "$OUT"
contains "fresh machine: says it installed" "Installed claude-notify-resume@anaidenko" "$OUT"

run STUB_MARKETPLACES="$OURS_GITHUB" STUB_PLUGINS="$OTHER_PLUGIN"
check "our marketplace present: refreshes it instead of adding" \
    "plugin marketplace list --json | plugin marketplace update anaidenko | plugin list --json | plugin install claude-notify-resume@anaidenko" \
    "$CALLS"

run STUB_MARKETPLACES="$OURS_URL"
contains "our marketplace added by git URL counts as ours" "plugin marketplace update anaidenko" "$CALLS"

run STUB_MARKETPLACES="$OURS_GITHUB" STUB_PLUGINS="$INSTALLED"
check "already installed: updates instead of installing" \
    "plugin marketplace list --json | plugin marketplace update anaidenko | plugin list --json | plugin update claude-notify-resume@anaidenko" \
    "$CALLS"
contains "already installed: says it is up to date" "claude-notify-resume@anaidenko is installed and up to date" "$OUT"
# The guard that protects a user's setup: a stray "anaidenko" marketplace
# (early installs pointed it at the plugin's own repo) must be left alone.
run STUB_MARKETPLACES="$FOREIGN"
check "foreign marketplace: exits 1" "1" "$CODE"
check "foreign marketplace: makes no change at all" "plugin marketplace list --json" "$CALLS"
contains "foreign marketplace: names what it points at" "anaidenko/claude-notify-resume" "$OUT"
contains "foreign marketplace: prints the fix" "claude plugin marketplace remove anaidenko" "$OUT"

run STUB_FAIL_ON="plugin install claude-notify-resume@anaidenko"
check "a failing install exits 1" "1" "$CODE"
contains "a failing install says which command failed" "plugin install claude-notify-resume@anaidenko\` failed" "$OUT"

run STUB_MARKETPLACES="not json"
check "unreadable --json output: exits 1" "1" "$CODE"
check "unreadable --json output: makes no change" "plugin marketplace list --json" "$CALLS"

: >"$STUB_LOG"
OUT="$(env PATH="$EMPTY_BIN" "$NODE" "$INSTALLER" 2>&1 </dev/null)"
CODE=$?
check "no claude on PATH: exits 1" "1" "$CODE"
contains "no claude on PATH: says so" "not found on PATH" "$OUT"

run -- --help
check "--help: exits 0" "0" "$CODE"
check "--help: calls nothing" "" "$CALLS"
contains "--help: shows the npx line" "npx @anaidenko/claude-notify-resume" "$OUT"

run -- --bogus
check "an unknown flag: exits 1" "1" "$CODE"
check "an unknown flag: calls nothing" "" "$CALLS"

# ── the macOS notifier app ──
# Built from the copy `claude plugin list` reports, never from this package,
# so the binary matches the hooks that call it. A stand-in setup script
# records its run; nothing is compiled.
if [ "$(uname -s)" = "Darwin" ]; then
    printf '\n═══ macOS notifier app\n'
    FAKE_PLUGIN="$STUB_BIN/cache/claude-notify-resume/1.5.0"
    mkdir -p "$FAKE_PLUGIN/scripts"
    cat >"$FAKE_PLUGIN/scripts/setup-macos-icon.sh" <<STUB
#!/bin/bash
printf 'setup-macos-icon.sh\n' >>"$STUB_LOG"
exit "\${STUB_SETUP_RC:-0}"
STUB
    WITH_PATH="[{\"id\":\"$PLUGIN_ID\",\"version\":\"1.5.0\",\"scope\":\"user\",\"installPath\":\"$FAKE_PLUGIN\"}]"

    run
    contains "no Xcode tools: says how to get them" "xcode-select --install" "$OUT"
    check "no Xcode tools: exits 0, the plugin is installed" "0" "$CODE"

    run STUB_CLT=1 STUB_PLUGINS_AFTER="$WITH_PATH"
    check "fresh install: builds the app from the installed copy" \
        "plugin marketplace list --json | plugin marketplace add anaidenko/claude-plugins | plugin list --json | plugin install $PLUGIN_ID | plugin list --json | setup-macos-icon.sh" \
        "$CALLS"
    check "fresh install: exits 0" "0" "$CODE"

    run STUB_CLT=1 STUB_MARKETPLACES="$OURS_GITHUB" STUB_PLUGINS="$WITH_PATH"
    contains "an update rebuilds the app" "plugin update $PLUGIN_ID | plugin list --json | setup-macos-icon.sh" "$CALLS"

    run STUB_CLT=1 STUB_PLUGINS_AFTER="$WITH_PATH" STUB_SETUP_RC=1
    check "a failed build still exits 0" "0" "$CODE"
    contains "a failed build is reported" "the notifier app was not built" "$OUT"

    run STUB_CLT=1 STUB_PLUGINS_AFTER="[{\"id\":\"$PLUGIN_ID\",\"installPath\":\"/nonexistent\"}]"
    contains "a missing install path is reported" "the installed plugin was not found" "$OUT"
fi

# ── --uninstall ──
# HOME points at a scratch dir holding what the plugin leaves behind, so the
# real one is never touched. XDG_* are blanked so the HOME defaults apply.
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$STUB_BIN" "$EMPTY_BIN" "${TOOLS_BIN:-}" "$FAKE_HOME"' EXIT
seed_home() {
    rm -rf "$FAKE_HOME" && mkdir -p "$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.claude/claude-code-notify/Claude Code.app" "$FAKE_HOME/.local/state/claude-code-notify"
    printf 'MUTE=Replied\n' >"$FAKE_HOME/.claude/claude-notify-resume.conf"
}
UNINSTALL_ENV=(HOME="$FAKE_HOME" XDG_STATE_HOME= XDG_CONFIG_HOME=)

seed_home
run "${UNINSTALL_ENV[@]}" STUB_PLUGINS="$INSTALLED" -- --uninstall
check "--uninstall: removes the user install, and touches no marketplace" \
    "plugin list --json | plugin uninstall $PLUGIN_ID" "$CALLS"
check "--uninstall: exits 0" "0" "$CODE"
contains "--uninstall: says so" "Uninstalled $PLUGIN_ID" "$OUT"
check "--uninstall: removes the click state and icon app" "gone" "$([ -e "$FAKE_HOME/.claude/claude-code-notify" ] && echo there || echo gone)"
check "--uninstall: removes the Linux state dir" "gone" "$([ -e "$FAKE_HOME/.local/state/claude-code-notify" ] && echo there || echo gone)"
contains "--uninstall: reports what it removed" "Removed ~/.claude/claude-code-notify" "$OUT"
check "--uninstall: keeps the user's config" "kept" "$([ -f "$FAKE_HOME/.claude/claude-notify-resume.conf" ] && echo kept || echo gone)"
contains "--uninstall: says where the config is" "Kept your config: ~/.claude/claude-notify-resume.conf" "$OUT"
contains "--uninstall: points at the marketplace it leaves" "claude plugin marketplace remove anaidenko" "$OUT"

seed_home
run "${UNINSTALL_ENV[@]}" -- --uninstall
check "--uninstall, not installed: only looks" "plugin list --json" "$CALLS"
check "--uninstall, not installed: exits 0" "0" "$CODE"
contains "--uninstall, not installed: says so" "was not installed for your user" "$OUT"

run "${UNINSTALL_ENV[@]}" STUB_PLUGINS="[{\"id\":\"$PLUGIN_ID\",\"scope\":\"project\",\"projectPath\":\"/work/app\"}]" -- --uninstall
check "--uninstall, project scope only: removes nothing it cannot reach" "plugin list --json" "$CALLS"
contains "--uninstall, project scope only: names it" "Still installed with --scope project in /work/app" "$OUT"

run "${UNINSTALL_ENV[@]}" STUB_PLUGINS="$INSTALLED" STUB_FAIL_ON="plugin uninstall $PLUGIN_ID" -- --uninstall
check "--uninstall: a failing uninstall exits 1" "1" "$CODE"

run -- --uninstall --bogus
check "--uninstall with a stray flag: exits 1" "1" "$CODE"
check "--uninstall with a stray flag: calls nothing" "" "$CALLS"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
