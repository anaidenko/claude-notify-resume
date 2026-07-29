#!/usr/bin/env bash
# Run the Linux test suite against every supported distro.
#
#   test/run-linux-tests.sh                 # all distros
#   test/run-linux-tests.sh ubuntu:24.04    # just one
#
# Requires Docker. Each distro gets a clean container, so a fix verified here
# is verified on the distro a bug was reported against — not just on whichever
# base image happened to be the default.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [ "$#" -gt 0 ]; then
    DISTROS=("$@")
else
    DISTROS=(debian:bookworm-slim ubuntu:24.04)
fi

command -v docker >/dev/null 2>&1 || {
    printf 'docker is required but not installed.\n' >&2
    exit 1
}
docker info >/dev/null 2>&1 || {
    printf 'The Docker daemon is not running.\n' >&2
    exit 1
}

FAILED=()

for distro in "${DISTROS[@]}"; do
    printf '\n═══ %s\n' "$distro"
    tag="claude-notify-test-$(printf '%s' "$distro" | tr ':/.' '---')"

    if ! docker build -q -t "$tag" --build-arg "BASE=$distro" -f test/Dockerfile . >/dev/null; then
        printf '  BUILD FAILED\n'
        FAILED+=("$distro (build)")
        continue
    fi

    docker run --rm "$tag" || FAILED+=("$distro")
done

printf '\n═══ Summary\n'
if [ "${#FAILED[@]}" -eq 0 ]; then
    printf '  All %d distro(s) passed.\n\n' "${#DISTROS[@]}"
    exit 0
fi
printf '  Failed: %s\n\n' "${FAILED[*]}"
exit 1
