// Helper for notify.sh — reads a Claude Code hook payload on stdin and prints
// three lines: session id, transcript path, cwd ("-" when a field is absent).
// When the transcript is readable, the chat's name is printed as a fourth
// line: the last `custom-title` record (a manual rename) if one exists,
// otherwise the last `ai-title` (the auto-generated name).
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

    // A manual rename appends a `custom-title` record, but the transcript keeps
    // re-emitting the old `ai-title` on every later turn — so the rename must
    // win by record type, not by position in the file.
    let aiTitle = "";
    let customTitle = "";
    if (transcript !== "-") {
        try {
            const lines = require("fs").readFileSync(transcript, "utf8").split("\n");
            for (const line of lines) {
                if (!line.includes("-title")) continue;
                try {
                    const record = JSON.parse(line);
                    if (record.type === "ai-title" && record.aiTitle) aiTitle = record.aiTitle;
                    if (record.type === "custom-title" && record.customTitle) customTitle = record.customTitle;
                } catch {
                    // Skip unparsable transcript lines.
                }
            }
        } catch {
            // Unreadable transcript: fall back to the directory name in notify.sh.
        }
    }
    const title = customTitle || aiTitle;

    process.stdout.write([sessionId, transcript, cwd, title.replace(/[\r\n]+/g, " ").trim()].join("\n"));
});
