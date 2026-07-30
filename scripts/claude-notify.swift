// The icon bundle's real executable. Compiled by setup-macos-icon.sh.
//
// Why this exists at all: a banner's icon comes from the app that posts it, and
// terminal-notifier's `-sender` spoof both swallows the click on the banner body
// and relies on macOS launching a fake, script-only app bundle — which today
// failed four different, undocumented ways. Posting natively from a real binary
// removes the whole class: the notification belongs to this app, so macOS
// delivers the click to it like to any other app, body and all.
//
// Two roles, picked by argv:
//
//   claude-notify post <title> <body> <session-id> <cwd> <opener> <group>
//       Post one notification carrying everything its click will need.
//
//   claude-notify
//       No arguments: macOS launched us because a notification was clicked.
//       Run the opener recorded in that notification, then quit.
//
// The session id and cwd ride inside each notification's userInfo, so every
// banner resumes its own session — no shared state file, no last-writer race.
import AppKit
import UserNotifications

let arguments = CommandLine.arguments

// The recorded opener path names the plugin version that posted the banner.
// Updating the plugin deletes that directory, so a banner posted before an
// update and clicked after it would point at nothing — the exact bug that broke
// the previous launcher. Fall back to the newest installed copy.
func resolveOpener(recorded: String) -> String? {
    let fm = FileManager.default
    if fm.fileExists(atPath: recorded) { return recorded }
    let cache = fm.homeDirectoryForCurrentUser.path + "/.claude/plugins/cache"
    var newest: String? = nil
    for market in (try? fm.contentsOfDirectory(atPath: cache)) ?? [] {
        let base = cache + "/" + market + "/claude-notify-resume"
        for version in ((try? fm.contentsOfDirectory(atPath: base)) ?? []).sorted() {
            let candidate = base + "/" + version + "/scripts/open-session.sh"
            if fm.fileExists(atPath: candidate) { newest = candidate }
        }
    }
    return newest
}

final class ClickHandler: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // If we were launched by a click, the response is delivered right after
        // launch. If nothing arrives, this was a stray launch — leave quietly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { NSApp.terminate(nil) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let opener = info["opener"] as? String,
           let session = info["session"] as? String,
           let cwd = info["cwd"] as? String,
           let script = resolveOpener(recorded: opener) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [script, session, cwd]
            try? proc.run()
            proc.waitUntilExit()
        }
        done()
        NSApp.terminate(nil)
    }
}

if arguments.count >= 3 && arguments[1] == "post" {
    // post <title> <body> [session cwd opener [group]]
    let center = UNUserNotificationCenter.current()

    let authorized = DispatchSemaphore(value: 0)
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in authorized.signal() }
    authorized.wait()

    let content = UNMutableNotificationContent()
    content.title = arguments[2]
    content.body = arguments.count > 3 ? arguments[3] : ""
    content.sound = .default
    if arguments.count > 6 {
        content.userInfo = ["session": arguments[4],
                            "cwd": arguments[5],
                            "opener": arguments[6]]
    }

    // Reusing the identifier replaces the banner already on screen from the
    // same chat instead of stacking a new one — the old `-group` behaviour.
    let identifier = arguments.count > 7 ? arguments[7] : UUID().uuidString
    let request = UNNotificationRequest(identifier: identifier,
                                        content: content,
                                        trigger: nil)
    let posted = DispatchSemaphore(value: 0)
    center.add(request) { _ in posted.signal() }
    posted.wait()
    exit(0)
}

// No arguments: launched by macOS to deliver a click.
let app = NSApplication.shared
let handler = ClickHandler()
app.delegate = handler
app.run()
