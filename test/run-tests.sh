#!/usr/bin/env bash
# Run the right test suite for whatever machine this is.
#
#   ./test/run-tests.sh          # native suite for this platform
#   ./test/run-tests.sh --all    # also sweep other platforms, where possible
#
#   macOS  → the macOS suite; --all adds the Linux suites via Docker
#   Linux  → the Linux suite on the host, against the real notify-send
#
# Nothing here delivers a notification: the notifier binaries are shadowed by
# stubs that record their arguments.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

ALL=0
[ "${1:-}" = "--all" ] && ALL=1

case "$(uname -s)" in
    Darwin)
        printf '═══ macOS (host)\n'
        ./test/run-macos-tests.sh || exit 1

        if [ "$ALL" -eq 1 ]; then
            printf '\n═══ Linux (Docker)\n'
            ./test/run-linux-tests.sh || exit 1

            printf '\n═══ Linux delivery, real D-Bus + daemon (Docker)\n'
            docker build -q -t claude-notify-dbus -f test/Dockerfile.dbus . >/dev/null &&
                docker run --rm claude-notify-dbus || exit 1
        else
            printf 'Linux suites skipped — run with --all (needs Docker), or npm run test:linux\n\n'
        fi
        ;;

    Linux)
        # No Docker needed: this *is* Linux, and the suite runs against the
        # distro's own notify-send rather than a container's.
        # shellcheck disable=SC1091  # /etc/os-release exists at runtime, not here
        printf '═══ Linux (host: %s)\n' "$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-unknown}")"
        ./test/linux-suite.sh || exit 1

        if [ "$ALL" -eq 1 ] && command -v docker >/dev/null 2>&1; then
            printf '\n═══ Other distros (Docker)\n'
            ./test/run-linux-tests.sh || exit 1
        fi
        ;;

    *)
        printf 'Unsupported platform: %s\n' "$(uname -s)" >&2
        printf 'The suites cover macOS and Linux; Windows has no implementation yet.\n' >&2
        exit 1
        ;;
esac
