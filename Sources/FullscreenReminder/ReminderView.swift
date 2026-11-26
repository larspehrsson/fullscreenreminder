import SwiftUI
import EventKit
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct ReminderView: View {
    var event: EKEvent
    @AppStorage(ReminderPreferences.reminderStyleKey) private var style = ReminderStyle.glassmorphism
    @AppStorage(ReminderPreferences.snoozeMinutesKey) private var snoozeMinutes =
        ReminderPreferences.defaultSnoozeMinutes
    @State private var infoLine: String?
    @State private var timer: Timer?
    @State private var isHovering = false
    @State private var isShiftPressed = false
    @State private var modifierFlagsMonitor: Any?

    var body: some View {
        Group {
            switch style {
            case .classic:
                classicBody
            case .glassmorphism:
                glassmorphismBody
            }
        }
        .onAppear {
            updateInfoLine()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                updateInfoLine()
            }
            isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
                isShiftPressed = event.modifierFlags.contains(.shift)
                return event
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            if let monitor = modifierFlagsMonitor {
                NSEvent.removeMonitor(monitor)
                modifierFlagsMonitor = nil
            }
        }
    }

    var glassmorphismBody: some View {
        ZStack {
            // Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            // Contrast Overlay
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            // Content
            VStack(spacing: 32) {
                // Header: Icon
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }

                // Main Info
                VStack(spacing: 12) {
                    Text(event.title)
                        .font(.system(size: 42, weight: .bold, design: .default))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(.horizontal)

                    Text(timeRange)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }

                // Countdown / Status
                if let infoLine {
                    Text(infoLine)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(infoColor)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.4))
                        )
                        .overlay(
                            Capsule()
                                .stroke(infoColor.opacity(0.5), lineWidth: 1)
                        )
                }

                // Actions
                HStack(spacing: 24) {
                    if let url = event.url {
                        ActionButton(title: "Join Meeting", icon: "video.fill", color: .green) {
                            NSWorkspace.shared.open(url)
                            closeWindow()
                        }
                    }
                    
                    if let googleMeetURL = googleMeetURL(from: event) {
                        ActionButton(title: isShiftPressed ? "Automatically join" : "Join Google Meet", icon: "video.circle.fill", color: .blue) {
                            if isShiftPressed {
                                scheduleAutoJoin(googleMeetURL)
                            } else {
                                NSWorkspace.shared.open(googleMeetURL)
                            }
                            closeWindow()
                        }
                    }

                    if canSnooze {
                        ActionButton(title: snoozeLabel, icon: "zzz", color: .orange) {
                            snoozeReminder()
                            closeWindow()
                        }
                    }

                    ActionButton(title: isShiftPressed ? "Dismiss All" : "Dismiss", icon: "xmark", color: .gray) {
                        dismissReminder()
                    }
                }
                .padding(.top, 16)
            }
            .padding(40)
        }
    }

    var classicBody: some View {
        VStack(spacing: 20) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
                    .shadow(radius: 8)
            }
            Text("Meeting Reminder")
                .font(.largeTitle)
            Text(event.title)
                .font(.title)
            Text(timeRange)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(Color.green)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
            if let infoLine {
                Text(infoLine)
                    .font(.title2)
                    .foregroundColor(infoColor)
                    .multilineTextAlignment(.center)
            }
            HStack {
                if let url = event.url {
                    Button("Join Meeting") {
                        NSWorkspace.shared.open(url)
                        closeWindow()
                    }
                }
                if let googleMeetURL = googleMeetURL(from: event) {
                    Button(isShiftPressed ? "Automatically join" : "Join Google Meeting") {
                        if isShiftPressed {
                            scheduleAutoJoin(googleMeetURL)
                        } else {
                            NSWorkspace.shared.open(googleMeetURL)
                        }
                        closeWindow()
                    }
                }
                if canSnooze {
                    Button(snoozeLabel) {
                        snoozeReminder()
                        closeWindow()
                    }
                }
                Button {
                    dismissReminder()
                } label: {
                    Text(isShiftPressed ? "Dismiss All" : "Dismiss")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8))
        .foregroundColor(.white)
    }

    private func closeWindow() {
        NotificationCenter.default.post(name: .closeReminderWindow, object: nil)
    }

    private func dismissReminder() {
        if isShiftPressed, let reminderEventIdentifier {
            NotificationCenter.default.post(
                name: .cancelFutureReminders,
                object: nil,
                userInfo: ["eventIdentifier": reminderEventIdentifier]
            )
        }
        closeWindow()
    }

    private func snoozeReminder() {
        guard let reminderEventIdentifier else { return }
        NotificationCenter.default.post(
            name: .snoozeReminder,
            object: nil,
            userInfo: [
                "eventIdentifier": reminderEventIdentifier,
                "seconds": snoozeDelaySeconds
            ]
        )
    }

    private func scheduleAutoJoin(_ url: URL) {
        guard let reminderEventIdentifier else { return }
        NotificationCenter.default.post(
            name: .scheduleAutoJoin,
            object: nil,
            userInfo: [
                "eventIdentifier": reminderEventIdentifier,
                "url": url.absoluteString
            ]
        )
    }

    private func googleMeetURL(from event: EKEvent) -> URL? {
        let notes = event.notes ?? ""
        let pattern = "https://meet.google.com/[a-zA-Z-]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: notes.utf16.count)
        if let match = regex?.firstMatch(in: notes, options: [], range: range) {
            if let urlRange = Range(match.range, in: notes) {
                return URL(string: String(notes[urlRange]))
            }
        }
        return nil
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(isHovering ? 0.9 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .foregroundColor(.white)
            .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

extension Notification.Name {
    static let closeReminderWindow = Notification.Name("closeReminderWindow")
    static let cancelFutureReminders = Notification.Name("cancelFutureReminders")
    static let snoozeReminder = Notification.Name("snoozeReminder")
    static let scheduleAutoJoin = Notification.Name("scheduleAutoJoin")
    static let previewReminder = Notification.Name("previewReminder")
}

private extension ReminderView {
    var timingMessage: String? {
        let now = Date()

        if event.startDate > now {
            let interval = event.startDate.timeIntervalSince(now)
            return countdownString(prefix: "Starts in", interval: interval)
        } else if let endDate = event.endDate, endDate > now {
            let interval = now.timeIntervalSince(event.startDate)
            if interval < 60 {
                return "Started just now"
            }
            return countdownString(prefix: "Started", interval: interval, suffix: "ago")
        }

        return nil
    }

    var combinedInfoLine: String? {
        let timing = timingMessage
        let location = sanitizedLocation

        switch (timing, location) {
        case (nil, nil):
            return nil
        case (let timing?, nil):
            return timing
        case (nil, let location?):
            return location
        case (let timing?, let location?):
            return "\(location) — \(timing)"
        }
    }

    var sanitizedLocation: String? {
        guard let raw = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    func countdownString(prefix: String, interval: TimeInterval, suffix: String? = nil) -> String {
        let totalSeconds = max(interval, 0)
        if totalSeconds < 1 {
            return suffix == nil ? "Starts now" : "Started just now"
        }

        let wholeSeconds = Int(totalSeconds)
        if wholeSeconds < 60 {
            if let suffix {
                return "Started \(wholeSeconds)s \(suffix)"
            }
            return "Starts in \(wholeSeconds)s"
        }

        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60
        let roundedMinutes = minutes + (seconds > 30 ? 1 : 0)
        let hours = roundedMinutes / 60
        let minutesRemainder = roundedMinutes % 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours)h")
        }
        if minutesRemainder > 0 {
            components.append("\(minutesRemainder)m")
        }

        let detail = components.joined(separator: " ")
        if let suffix {
            return "\(prefix) \(detail) \(suffix)"
        }
        return "\(prefix) \(detail)"
    }

    func updateInfoLine() {
        infoLine = combinedInfoLine
    }

    var reminderEventIdentifier: String? {
        ReminderOccurrenceID(event: event)?.rawValue
    }

    var timeRange: String {
        let formatter = ReminderView.timeFormatter
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }

    var canSnooze: Bool {
        event.startDate.timeIntervalSinceNow > 0
    }

    var snoozeDelaySeconds: Int {
        let secondsUntilStart = max(event.startDate.timeIntervalSinceNow, 0)
        let configuredSeconds = TimeInterval(snoozeMinutes * 60)
        let clamped = min(secondsUntilStart, configuredSeconds)
        return max(Int(ceil(clamped)), 1)
    }

    var snoozeLabel: String {
        if snoozeDelaySeconds < 60 {
            return "Snooze \(snoozeDelaySeconds)s"
        }
        let minutes = Int(ceil(TimeInterval(snoozeDelaySeconds) / 60))
        return "Snooze \(minutes)m"
    }

    var infoColor: Color {
        isInProgress ? .red : .yellow
    }

    var isInProgress: Bool {
        let now = Date()
        guard let endDate = event.endDate else { return event.startDate <= now }
        return event.startDate <= now && now < endDate
    }

    var appIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "appicon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
