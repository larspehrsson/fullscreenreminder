import AppKit
import EventKit

/// Why the app can't show meetings, when it's a permissions problem rather than an empty calendar.
enum CalendarAccessIssue: Equatable {
    /// Access was denied, restricted, or limited to "add events only".
    case notGranted
    /// macOS reports full access, yet no calendars are visible. Typically a permission left over
    /// from an older build signed by someone else: macOS keeps it tied to that signature, and
    /// only resetting it (then granting again) helps.
    case noCalendars
}

enum CalendarAccess {
    /// Call off the main thread: it asks the event store for its calendars.
    static func issue(for store: EKEventStore) -> CalendarAccessIssue? {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return store.calendars(for: .event).isEmpty ? .noCalendars : nil
        case .notDetermined:
            return nil  // The permission prompt is still to come.
        default:
            return .notGranted
        }
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    /// Forgets this app's calendar permission and relaunches, so macOS asks again from scratch.
    static func resetAndRelaunch() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Calendar", bundleID]
        do {
            try reset.run()
            reset.waitUntilExit()
        } catch {
            print("tccutil reset failed: \(error)")
            openPrivacySettings()
            return
        }

        // A detached shell reopens the app once this process has quit.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
