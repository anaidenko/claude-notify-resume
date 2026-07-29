# Linux test harness for the notification hook.
#
#   docker build -t claude-notify-test -f test/Dockerfile .
#   docker run --rm claude-notify-test
#
# Defaults to Debian; pass --build-arg BASE=ubuntu:24.04 for another distro, or
# just run test/run-linux-tests.sh to sweep all of them.
#
# A container has no notification daemon, so no banner can appear. What this
# does verify is everything up to the D-Bus call: transcript parsing, the chat
# name, platform dispatch, and that every failure path still exits 0 — the
# property that keeps a broken notifier from breaking someone's session.
ARG BASE=debian:bookworm-slim
FROM ${BASE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs libnotify-bin ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /plugin
COPY scripts/ ./scripts/
COPY assets/ ./assets/
COPY test/linux-suite.sh test/run-tests.sh ./test/
RUN chmod +x scripts/*.sh test/*.sh

ENTRYPOINT ["./test/linux-suite.sh"]
