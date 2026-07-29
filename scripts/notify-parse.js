// Helper for notify.sh — reads a Claude Code hook payload on stdin and prints
// three lines: session id, transcript path, cwd ("-" when a field is absent).
// When the transcript is readable, its last `ai-title` record is printed as a
// fourth line, giving the notification the chat's own name.
//
// Kept as a file rather than `node -e` inline: quoting an inline script inside
// shell command substitution silently truncates it.

let raw = "";
process.stdin.on("data", d => (raw += d));
process.stdin.on("end", () => {
    let payload = {};
    try {
        payload = JSON.parse(raw);
    } catch {
        // Malformed payload: fall through to placeholders.
    }

    const clean = value =>
        String(value ?? "")
            .replace(/[\r\n]+/g, " ")
            .trim() || "-";

    const sessionId = clean(payload.session_id);
    const transcript = clean(payload.transcript_path);
    const cwd = clean(payload.cwd);

    let title = "";
    if (transcript !== "-") {
        try {
            const lines = require("fs").readFileSync(transcript, "utf8").split("\n");
            for (const line of lines) {
                if (!line.includes("ai-title")) continue;
                try {
                    const record = JSON.parse(line);
                    if (record.type === "ai-title" && record.aiTitle) title = record.aiTitle;
                } catch {
                    // Skip unparsable transcript lines.
                }
            }
        } catch {
            // Unreadable transcript: fall back to the directory name in notify.sh.
        }
    }

    process.stdout.write([sessionId, transcript, cwd, title.replace(/[\r\n]+/g, " ").trim()].join("\n"));
});
