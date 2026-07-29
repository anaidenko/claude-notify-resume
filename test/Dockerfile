# Linux test harness for the notification hook.
#
#   docker build -t claude-notify-test test/
#   docker run --rm claude-notify-test
#
# A container has no notification daemon, so no banner can appear. What this
# does verify is everything up to the D-Bus call: transcript parsing, the chat
# name, platform dispatch, and that every failure path still exits 0 — the
# property that keeps a broken notifier from breaking someone's session.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs libnotify-bin ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /plugin
COPY scripts/ ./scripts/
COPY assets/ ./assets/
COPY test/run-tests.sh ./test/run-tests.sh
RUN chmod +x scripts/*.sh test/run-tests.sh

ENTRYPOINT ["./test/run-tests.sh"]
