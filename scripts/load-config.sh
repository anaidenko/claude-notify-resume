#!/usr/bin/env bash
# Load settings from a config file, without overriding anything already set in
# the environment.
#
#   . "$(dirname "$0")/load-config.sh"
#
# Why a file at all: the `env` block in ~/.claude/settings.json is global — every
# variable there is exported into every process Claude Code spawns, so a name
# like MUTE risks colliding with something else entirely. A file scoped to this
# plugin cannot.
#
# Precedence is environment first, file second. That way an inline
# `CLAUDE_NOTIFY_MUTE=… ` for one-off debugging still wins over the file.
#
# Format is deliberately dull — KEY=value, one per line, # for comments:
#
#     # ~/.claude/claude-notify-resume.conf
#     MUTE=Replied,Waiting for you
#     TERMINAL=iTerm
#
# Keys map to CLAUDE_NOTIFY_<KEY>. Unknown keys are ignored, so a typo is
# harmless rather than fatal — this runs inside a hook, which must never break
# the session.

CLAUDE_NOTIFY_CONFIG="${CLAUDE_NOTIFY_CONFIG:-$HOME/.claude/claude-notify-resume.conf}"

if [ -f "$CLAUDE_NOTIFY_CONFIG" ]; then
    while IFS= read -r config_line || [ -n "$config_line" ]; do
        config_line="$(printf '%s' "$config_line" |
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        # A whole-line comment goes now; an inline one is handled after
        # unquoting, so a `#` inside quotes survives as part of the value.
        case "$config_line" in
            '#'*) continue ;;
        esac
        [ -n "$config_line" ] || continue

        case "$config_line" in
            *=*) ;;
            *) continue ;;
        esac

        config_key="${config_line%%=*}"
        config_value="${config_line#*=}"
        config_key="$(printf '%s' "$config_key" |
            sed 's/[[:space:]]*$//' | tr '[:lower:]' '[:upper:]')"
        config_value="$(printf '%s' "$config_value" | sed 's/^[[:space:]]*//')"

        # Only plain names, so a malformed line cannot inject a variable.
        case "$config_key" in
            *[^A-Z0-9_]*) continue ;;
            '') continue ;;
        esac

        # Strip one layer of matching quotes, for values with trailing spaces or
        # a literal `#`. Unquoted values lose an inline comment instead.
        case "$config_value" in
            '"'*'"') config_value="${config_value#\"}"; config_value="${config_value%\"}" ;;
            "'"*"'") config_value="${config_value#\'}"; config_value="${config_value%\'}" ;;
            *)
                config_value="${config_value%%#*}"
                config_value="$(printf '%s' "$config_value" | sed 's/[[:space:]]*$//')"
                ;;
        esac

        # Environment wins — including when it is deliberately empty, which is
        # how you switch a file setting off for a single run
        # (`CLAUDE_NOTIFY_MUTE= claude …`). Test set-ness, not emptiness.
        eval "config_existing=\${CLAUDE_NOTIFY_$config_key+set}"
        [ -n "$config_existing" ] && continue

        eval "export CLAUDE_NOTIFY_$config_key=\$config_value"
    done <"$CLAUDE_NOTIFY_CONFIG"
fi

unset config_line config_key config_value config_existing
