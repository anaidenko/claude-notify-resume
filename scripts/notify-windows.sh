#!/usr/bin/env bash
# Windows toast via PowerShell (Git Bash / MSYS / Cygwin).
#
# UNVERIFIED: written from the BurntToast interface, not exercised on Windows.
# Falls back silently when the module is absent, since a hook must never break
# the session. Click-to-resume is omitted — BurntToast activation needs a
# registered AppId, which is more setup than a notification warrants.
set -uo pipefail

STATUS="$1"
CHAT="$2"

command -v powershell.exe >/dev/null 2>&1 || exit 0

powershell.exe -NoProfile -NonInteractive -Command "
  if (Get-Module -ListAvailable -Name BurntToast) {
    Import-Module BurntToast
    New-BurntToastNotification -Text '$(printf '%s' "$STATUS" | sed "s/'/''/g")', '$(printf '%s' "$CHAT" | sed "s/'/''/g")'
  }
" >/dev/null 2>&1 || true
exit 0
