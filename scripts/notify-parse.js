// Helper for notify.sh — reads a Claude Code hook payload on stdin and prints
// three lines: session id, transcript path, cwd ("-" when a field is absent).
// When the transcript is readable, the chat's name is printed as a fourth
// line: the last `custom-title` record (a manual rename) if one exists,
// otherwise the last `ai-title` (the auto-generated name). A fifth line names
// the tool still waiting on the user, or is empty (see findPendingTool below).
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
    let pendingTool = "";
    if (transcript !== "-") {
        try {
            const lines = require("fs").readFileSync(transcript, "utf8").split("\n");
            pendingTool = findPendingTool(lines);
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

    process.stdout.write(
        [sessionId, transcript, cwd, title.replace(/[\r\n]+/g, " ").trim(), pendingTool].join("\n"),
    );
});

// The tool a permission-style dialog is waiting on: the last `tool_use` in the
// transcript, provided no `tool_result` answers it yet. notify.sh needs it to
// tell a question or a plan from a real permission request, and the payload
// cannot say: it carries no tool name, and its message text differs by host
// (VS Code names the tool, the CLI does not). The tool_use is written about 6 s
// before `permission_prompt` fires, so it is always there in time.
//
// Walks backwards from the end and stops at the first assistant record holding
// a tool_use, so even a huge transcript costs a handful of JSON.parse calls.
// Results seen on the way (later in the file) are the answers. Anything that is
// not the last call, such as a parallel call's dialog, gives "" and the banner
// stays "Permission needed", which is what it said before this existed.
function findPendingTool(lines) {
    const answered = new Set();
    for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i];
        // `"tool_use_id"` does not contain `"tool_use"` (closing quote), so a
        // result line passes only the second test, as it should.
        const hasUse = line.includes('"tool_use"');
        if (!hasUse && !line.includes('"tool_result"')) continue;
        let record;
        try {
            record = JSON.parse(line);
        } catch {
            continue; // Skip unparsable transcript lines.
        }
        const content = record?.message?.content;
        if (!Array.isArray(content)) continue;
        for (const block of content) {
            if (block?.type === "tool_result" && block.tool_use_id) answered.add(block.tool_use_id);
        }
        if (record.type !== "assistant" || !hasUse) continue;
        const uses = content.filter(block => block?.type === "tool_use");
        if (uses.length === 0) continue;
        const last = uses[uses.length - 1];
        if (answered.has(last.id)) return "";
        return String(last.name ?? "")
            .replace(/[\r\n]+/g, " ")
            .trim();
    }
    return "";
}
