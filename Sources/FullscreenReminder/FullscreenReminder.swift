import SwiftUI
import EventKit
import AppKit

// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and its `Settings` scene
// made a second settings window that macOS also opened on its own at launch.
@main
enum FullscreenReminderApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

extension Notification.Name {
    static let refreshMeetings = Notification.Name("refreshMeetings")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private struct ReminderDispatchKey: Hashable {
        let occurrenceID: ReminderOccurrenceID
        let leadTime: Int
    }

    private struct PendingReminder {
        let key: ReminderDispatchKey
        let event: EKEvent
    }

    var statusBarItem: NSStatusItem!
    var eventStore = EKEventStore()
    var timer: Timer?
    var nextMeeting: EKEvent?
    var currentMeeting: EKEvent?
    var reminderWindowController: ReminderWindowController?
    var triggeredReminderLeadTimes: [ReminderOccurrenceID: Set<Int>] = [:]
    var notificationSound: NSSound?
    private final class ReminderTimer {
        let fireDate: Date
        let source: DispatchSourceTimer

        init(fireDate: Date, source: DispatchSourceTimer) {
            self.fireDate = fireDate
            self.source = source
        }

        func cancel() {
            source.setEventHandler {}
            source.cancel()
        }
    }

    private var reminderTimers: [ReminderOccurrenceID: [Int: ReminderTimer]] = [:]
    private var reminderEvents: [ReminderOccurrenceID: EKEvent] = [:]
    private var pendingEventStoreRefresh: DispatchWorkItem?
    private var isScreenLocked = false
    private var isAppJustLaunched = true
    private var welcomeBackTimer: Timer?
    private var snoozeTimers: [ReminderOccurrenceID: ReminderTimer] = [:]
    private var autoJoinTimers: [ReminderOccurrenceID: ReminderTimer] = [:]
    private var activeReminderKey: ReminderDispatchKey?
    private var pendingReminders: [PendingReminder] = []
    var upcomingEvents: [EKEvent] = []
    lazy var calendarSelectionViewModel = CalendarSelectionViewModel(eventStore: eventStore)
    lazy var statusBarIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "processbar", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = false
            return image
        }
        let fallback = NSApp.applicationIconImage
        fallback?.size = NSSize(width: 22, height: 22)
        fallback?.isTemplate = false
        return fallback
    }()
    private let eventStoreQueue = DispatchQueue(label: "FullscreenReminder.EventStore")
    lazy var settingsWindowController = SettingsWindowController()
    private let meetingsViewModel = MeetingsViewModel()
    lazy var meetingsPopoverController = MeetingsPopoverController(
        viewModel: meetingsViewModel,
        onSelectEvent: { [weak self] event in
            self?.openEventInCalendar(event)
        },
        onRefresh: { [weak self] in
            self?.fetchNextMeeting()
        },
        onOpenSettings: { [weak self] in
            self?.openSettings(nil)
        },
        onQuit: {
            NSApp.terminate(nil)
        }
    )
    private static let eventOpenDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ReminderPreferences.registerDefaults()
        _ = AppUpdater.shared

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        NotificationCenter.default.addObserver(self, selector: #selector(cancelFutureRemindersNotification(_:)), name: .cancelFutureReminders, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMeetingsNotification(_:)), name: .refreshMeetings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(eventStoreChangedNotification(_:)), name: .EKEventStoreChanged, object: eventStore)
        NotificationCenter.default.addObserver(self, selector: #selector(previewReminderNotification(_:)), name: .previewReminder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(snoozeReminderNotification(_:)), name: .snoozeReminder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleAutoJoinNotification(_:)), name: .scheduleAutoJoin, object: nil)

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)

        if let button = statusBarItem.button {
            button.title = "Next Meeting"
            button.action = #selector(statusBarItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imageScaling = .scaleProportionallyDown
        }

        // Preload meetings popover on the main thread so it is safe to use later
        _ = meetingsPopoverController

        requestCalendarAccess()
        
        // Schedule the "Startup Silence" end
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.isAppJustLaunched = false
            self?.fetchNextMeeting()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fetchNextMeeting()
        }
        startTimer()
    }

    @objc func statusBarItemClicked(sender: NSStatusBarButton) {
        meetingsPopoverController.toggle(relativeTo: sender)
    }

    @objc func showNextMeetingReminder() {
        if let meeting = currentMeeting ?? nextMeeting {
            showReminder(with: meeting)
        }
    }

    @objc private func screenLocked() {
        isScreenLocked = true
        welcomeBackTimer?.invalidate()
    }

    @objc private func screenUnlocked() {
        isScreenLocked = false
        welcomeBackTimer?.invalidate()
        welcomeBackTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.fetchNextMeeting()
        }
    }

    func requestCalendarAccess() {
        eventStore.requestFullAccessToEvents { (granted, error) in
            if granted {
                print("Calendar access granted")
                DispatchQueue.main.async {
                    self.fetchNextMeeting()
                }
            } else {
                print("Calendar access denied")
            }
        }
    }

    func startTimer() {
        timer?.invalidate()

        let now = Date()
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .strict,
            direction: .forward
        ) ?? now.addingTimeInterval(60)

        let alignedTimer = Timer(
            fire: nextMinute,
            interval: 60.0,
            repeats: true
        ) { [weak self] _ in
            self?.fetchNextMeeting()
        }
        alignedTimer.tolerance = 0.5
        RunLoop.main.add(alignedTimer, forMode: .common)
        timer = alignedTimer
    }

    func fetchNextMeeting() {
        eventStoreQueue.async { [weak self] in
            guard let self else { return }

            let calendars = ReminderPreferences.filteredCalendars(from: self.eventStore.calendars(for: .event))
            let horizonDays = ReminderPreferences.daysToDisplay
            let startDate = Date()
            let endDate = Calendar.current.date(byAdding: .day, value: horizonDays, to: startDate) ?? startDate.addingTimeInterval(Double(horizonDays) * 24 * 60 * 60)
            let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
            let events = self.eventStore.events(matching: predicate)
                .sorted(by: { $0.startDate < $1.startDate })

            let now = Date()
            let accessIssue = CalendarAccess.issue(for: self.eventStore)
            let currentMeeting = events.first(where: { $0.startDate <= now && now < $0.endDate })
            let nextMeeting = events.first(where: { $0.startDate > now })

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.currentMeeting = currentMeeting
                self.nextMeeting = nextMeeting

                self.cleanupTriggeredLeadTimes(using: events)
                self.scheduleReminderTimers(for: events)
                self.upcomingEvents = events

                self.meetingsPopoverController.updateMeetings(current: currentMeeting, next: nextMeeting, all: events, accessIssue: accessIssue)
                self.updateStatusItem()
                self.statusBarItem.button?.toolTip = accessIssue == nil ? nil : "FullscreenReminder can't read your calendars"
            }
        }
    }

    func updateStatusItem() {
        guard let button = statusBarItem.button else { return }
        if let icon = statusBarIcon {
            button.image = icon
            button.imageScaling = .scaleProportionallyDown
        }
        button.imagePosition = .imageOnly
        button.title = ""

        let now = Date()
        let horizon = now.addingTimeInterval(3 * 60 * 60)
        let displayableEvents = upcomingEvents.filter { shouldDisplayInStatusBar($0) }
        let timedEvents = displayableEvents.filter { !$0.isAllDay }

        if let currentEvent = timedEvents.first(where: { $0.startDate <= now && now < $0.endDate }) {
            updateStatusForCurrent(event: currentEvent, button: button)
            return
        }

        if let nextEvent = timedEvents.first(where: { $0.startDate <= horizon && $0.startDate > now }) {
            updateStatusForUpcoming(event: nextEvent, button: button)
            return
        }

        // Fallback: show all-day events only when no timed event is active or upcoming soon,
        // and only if the user enabled all-day events in settings.
        if let allDayEvent = fallbackAllDayEvent(now: now) {
            updateStatusForAllDay(event: allDayEvent, button: button)
            return
        }
    }

    private func formattedTimeDescription(forMinutes minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    private func roundedMinutes(from interval: TimeInterval) -> Int {
        let totalSeconds = max(interval, 0)
        let minutes = Int(totalSeconds / 60)
        let seconds = Int(totalSeconds) % 60
        return minutes + (seconds > 30 ? 1 : 0)
    }

    func showReminder(with event: EKEvent) {
        playNotificationSound()
        reminderWindowController?.close()
        meetingsPopoverController.close()

        let controller = ReminderWindowController(event: event)
        controller.onClose = { [weak self] in
            self?.reminderDidClose()
        }
        reminderWindowController = controller
        reminderWindowController?.showReminder()
    }

    private func enqueueOrShowReminder(event: EKEvent, occurrenceID: ReminderOccurrenceID, leadTime: Int) {
        let key = ReminderDispatchKey(occurrenceID: occurrenceID, leadTime: leadTime)
        if activeReminderKey == key || pendingReminders.contains(where: { $0.key == key }) {
            return
        }

        let pending = PendingReminder(key: key, event: event)
        if reminderWindowController == nil {
            activeReminderKey = key
            showReminder(with: event)
            return
        }

        pendingReminders.append(pending)
        pendingReminders.sort { lhs, rhs in
            if lhs.event.startDate != rhs.event.startDate {
                return lhs.event.startDate < rhs.event.startDate
            }
            let lhsTitle = lhs.event.title ?? ""
            let rhsTitle = rhs.event.title ?? ""
            if lhsTitle != rhsTitle {
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            return lhs.key.leadTime > rhs.key.leadTime
        }
    }

    private func openEventInCalendar(_ event: EKEvent) {
        let rawIdentifier: String? = {
            let calendarIdentifier = event.calendarItemIdentifier
            if !calendarIdentifier.isEmpty {
                return calendarIdentifier
            }
            if let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty {
                return eventIdentifier
            }
            return nil
        }()

        if let identifier = rawIdentifier,
           let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {

            let anchorDate: Date? = {
                if event.isAllDay, let endDate = event.endDate {
                    // Calendar resolves all-day entries using the exclusive end date; using the raw
                    // startDate often lands us on the previous day in UTC, so anchor on endDate.
                    return endDate
                }
                if let occurrence = event.occurrenceDate {
                    return occurrence
                }
                return event.startDate
            }()

            if let startDate = anchorDate {
                let startStamp = Self.eventOpenDateFormatter.string(from: startDate)
                if let url = URL(string: "ical://ekevent/\(startStamp)/\(encoded)") {
                    print("Opening event using occurrence URL: \(url.absoluteString)")
                    NSWorkspace.shared.open(url)
                    return
                }
            }

            if let url = URL(string: "ical://ekevent/\(encoded)") {
                print("Opening event using identifier URL: \(url.absoluteString)")
                NSWorkspace.shared.open(url)
                return
            }
        }

        let referenceDate = event.startDate.timeIntervalSinceReferenceDate
        if let fallbackURL = URL(string: "calshow:\(referenceDate)") {
            print("Opening event using fallback URL: \(fallbackURL.absoluteString)")
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    func reminderDidClose() {
        activeReminderKey = nil
        reminderWindowController = nil
        while !pendingReminders.isEmpty {
            let next = pendingReminders.removeFirst()
            if let endDate = next.event.endDate, endDate <= Date() {
                continue
            }
            activeReminderKey = next.key
            showReminder(with: next.event)
            break
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        calendarSelectionViewModel.reload()
        settingsWindowController.present(with: calendarSelectionViewModel)
    }

    @objc func openAbout(_ sender: Any?) {
        // Placeholder for About functionality if it were implemented
        // NSApp.activate(ignoringOtherApps: true)
        // aboutWindowController.show()
    }
    
    @objc private func previewReminderNotification(_ notification: Notification) {
        let dummyEvent = EKEvent(eventStore: eventStore)
        dummyEvent.title = "Preview Meeting"
        dummyEvent.startDate = Date().addingTimeInterval(300) // Starts in 5 mins
        dummyEvent.endDate = Date().addingTimeInterval(3900) // Ends in 1h 5m
        dummyEvent.location = "Conf Room A"
        dummyEvent.calendar = eventStore.defaultCalendarForNewEvents
        
        showReminder(with: dummyEvent)
    }

    @objc private func snoozeReminderNotification(_ notification: Notification) {
        guard
            let rawValue = notification.userInfo?["eventIdentifier"] as? String,
            let occurrenceID = ReminderOccurrenceID(rawValue: rawValue)
        else { return }

        let seconds = notification.userInfo?["seconds"] as? Int
        let minutes = notification.userInfo?["minutes"] as? Int
        let fallbackSeconds = (minutes ?? ReminderPreferences.defaultSnoozeMinutes) * 60
        scheduleSnooze(for: occurrenceID, seconds: seconds ?? fallbackSeconds)
    }

    @objc private func scheduleAutoJoinNotification(_ notification: Notification) {
        guard
            let rawValue = notification.userInfo?["eventIdentifier"] as? String,
            let occurrenceID = ReminderOccurrenceID(rawValue: rawValue),
            let urlString = notification.userInfo?["url"] as? String,
            let url = URL(string: urlString)
        else { return }

        scheduleAutoJoin(for: occurrenceID, url: url)
    }

    private func cleanupTriggeredLeadTimes(using events: [EKEvent]) {
        let validOccurrences = Set(events.compactMap { ReminderOccurrenceID(event: $0) })
        triggeredReminderLeadTimes = triggeredReminderLeadTimes.filter { validOccurrences.contains($0.key) }
        reminderEvents = reminderEvents.filter { validOccurrences.contains($0.key) }
        cleanupReminderTimers(validOccurrenceIDs: validOccurrences)
    }

    private func playNotificationSound() {
        let soundName = ReminderPreferences.selectedSoundName

        if let url = ReminderPreferences.soundURL(for: soundName),
           let sound = NSSound(contentsOf: url, byReference: true) {
            notificationSound = sound
            if sound.play() == false {
                NSSound.beep()
            }
            return
        }

        notificationSound = NSSound(named: NSSound.Name(soundName))
        if notificationSound?.play() == false {
            NSSound.beep()
        }
    }

    private func makeReminderTimer(
        fireDate: Date,
        occurrenceID: ReminderOccurrenceID,
        leadTime: Int
    ) -> ReminderTimer {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        let delaySeconds = max(fireDate.timeIntervalSinceNow, 0)
        let deadline = DispatchWallTime.now() + .nanoseconds(Int(delaySeconds * 1_000_000_000))
        timer.schedule(wallDeadline: deadline, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.handleScheduledReminder(occurrenceID: occurrenceID, leadTime: leadTime)
        }
        timer.resume()
        return ReminderTimer(fireDate: fireDate, source: timer)
    }

    private func makeSnoozeTimer(
        fireDate: Date,
        occurrenceID: ReminderOccurrenceID
    ) -> ReminderTimer {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        let delaySeconds = max(fireDate.timeIntervalSinceNow, 0)
        let deadline = DispatchWallTime.now() + .nanoseconds(Int(delaySeconds * 1_000_000_000))
        timer.schedule(wallDeadline: deadline, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.snoozeTimers[occurrenceID]?.cancel()
            self.snoozeTimers.removeValue(forKey: occurrenceID)

            let event = self.reminderEvents[occurrenceID]
                ?? self.upcomingEvents.first(where: {
                    $0.eventIdentifier == occurrenceID.eventIdentifier &&
                    abs($0.startDate.timeIntervalSince(occurrenceID.occurrenceStart)) < 60
                })
                ?? self.eventStore.event(withIdentifier: occurrenceID.eventIdentifier)
            guard let event else { return }

            let now = Date()
            if let endDate = event.endDate, now >= endDate {
                return
            }

            self.enqueueOrShowReminder(event: event, occurrenceID: occurrenceID, leadTime: -1000)
        }
        timer.resume()
        return ReminderTimer(fireDate: fireDate, source: timer)
    }

    private func makeAutoJoinTimer(
        fireDate: Date,
        occurrenceID: ReminderOccurrenceID,
        url: URL
    ) -> ReminderTimer {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        let delaySeconds = max(fireDate.timeIntervalSinceNow, 0)
        let deadline = DispatchWallTime.now() + .nanoseconds(Int(delaySeconds * 1_000_000_000))
        timer.schedule(wallDeadline: deadline, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.autoJoinTimers[occurrenceID]?.cancel()
            self.autoJoinTimers.removeValue(forKey: occurrenceID)
            NSWorkspace.shared.open(url)
        }
        timer.resume()
        return ReminderTimer(fireDate: fireDate, source: timer)
    }

    private func scheduleReminderTimers(for events: [EKEvent]) {
        let now = Date()
        let validOccurrences = Set(events.compactMap { ReminderOccurrenceID(event: $0) })

        for event in events {
            guard let occurrenceID = ReminderOccurrenceID(event: event) else { continue }

            reminderEvents[occurrenceID] = event

            var timersForEvent = reminderTimers[occurrenceID] ?? [:]

            for leadTime in ReminderLeadTime.allCases {
                let leadValue = leadTime.rawValue

                guard ReminderPreferences.isEnabled(for: leadTime) else {
                    if let timer = timersForEvent[leadValue] {
                        timer.cancel()
                        timersForEvent.removeValue(forKey: leadValue)
                    }
                    continue
                }

                let fireDate = occurrenceID.occurrenceStart.addingTimeInterval(-TimeInterval(leadValue * 60))

                if fireDate <= now {
                    handleScheduledReminder(occurrenceID: occurrenceID, leadTime: leadValue)
                    if let timer = timersForEvent[leadValue] {
                        timer.cancel()
                        timersForEvent.removeValue(forKey: leadValue)
                    }
                    continue
                }

                let existingTimer = timersForEvent[leadValue]
                if let existingTimer, abs(existingTimer.fireDate.timeIntervalSince(fireDate)) < 1 {
                    continue
                }

                existingTimer?.cancel()
                let timer = makeReminderTimer(
                    fireDate: fireDate,
                    occurrenceID: occurrenceID,
                    leadTime: leadValue
                )
                timersForEvent[leadValue] = timer
            }

            reminderTimers[occurrenceID] = timersForEvent
        }

        cleanupReminderTimers(validOccurrenceIDs: validOccurrences)
    }

    private func handleScheduledReminder(occurrenceID: ReminderOccurrenceID, leadTime: Int) {
        if isScreenLocked || isAppJustLaunched { return }
        
        var triggered = triggeredReminderLeadTimes[occurrenceID] ?? []
        if triggered.contains(leadTime) { return }

        let scheduledFireDate = occurrenceID.occurrenceStart.addingTimeInterval(-TimeInterval(leadTime * 60))
        let timeSinceFire = Date().timeIntervalSince(scheduledFireDate)
        
        // If the reminder is more than 5 minutes overdue, mark it as triggered but don't show it.
        // This prevents a flood of reminders when launching the app during an ongoing meeting.
        if timeSinceFire > 300 {
             triggered.insert(leadTime)
             triggeredReminderLeadTimes[occurrenceID] = triggered
             return
        }

        let event = reminderEvents[occurrenceID]
            ?? upcomingEvents.first(where: {
                $0.eventIdentifier == occurrenceID.eventIdentifier &&
                abs($0.startDate.timeIntervalSince(occurrenceID.occurrenceStart)) < 60
            })
            ?? eventStore.event(withIdentifier: occurrenceID.eventIdentifier)
        guard let event else { return }

        triggered.insert(leadTime)
        triggeredReminderLeadTimes[occurrenceID] = triggered

        if var timersForEvent = reminderTimers[occurrenceID] {
            timersForEvent[leadTime]?.cancel()
            timersForEvent.removeValue(forKey: leadTime)
            if timersForEvent.isEmpty {
                reminderTimers.removeValue(forKey: occurrenceID)
                reminderEvents.removeValue(forKey: occurrenceID)
            } else {
                reminderTimers[occurrenceID] = timersForEvent
            }
        }

        enqueueOrShowReminder(event: event, occurrenceID: occurrenceID, leadTime: leadTime)
    }

    private func cleanupReminderTimers(validOccurrenceIDs: Set<ReminderOccurrenceID>) {
        for (occurrenceID, timers) in reminderTimers where !validOccurrenceIDs.contains(occurrenceID) {
            for timer in timers.values {
                timer.cancel()
            }
            reminderTimers.removeValue(forKey: occurrenceID)
            reminderEvents.removeValue(forKey: occurrenceID)
        }

        for (occurrenceID, timer) in snoozeTimers where !validOccurrenceIDs.contains(occurrenceID) {
            timer.cancel()
            snoozeTimers.removeValue(forKey: occurrenceID)
        }

        for (occurrenceID, timer) in autoJoinTimers where !validOccurrenceIDs.contains(occurrenceID) {
            timer.cancel()
            autoJoinTimers.removeValue(forKey: occurrenceID)
        }

        pendingReminders.removeAll { !validOccurrenceIDs.contains($0.key.occurrenceID) }
        if let activeReminderKey, !validOccurrenceIDs.contains(activeReminderKey.occurrenceID) {
            self.activeReminderKey = nil
        }
    }

    @objc private func cancelFutureRemindersNotification(_ notification: Notification) {
        guard let rawValue = notification.userInfo?["eventIdentifier"] as? String,
              let occurrenceID = ReminderOccurrenceID(rawValue: rawValue) else { return }
        cancelFutureReminders(for: occurrenceID)
    }

    @objc private func eventStoreChangedNotification(_ notification: Notification) {
        scheduleImmediateMeetingRefresh()
    }

    private func scheduleImmediateMeetingRefresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingEventStoreRefresh?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingEventStoreRefresh = nil
                self.fetchNextMeeting()
            }
            self.pendingEventStoreRefresh = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    private func cancelFutureReminders(for occurrenceID: ReminderOccurrenceID) {
        if let timers = reminderTimers[occurrenceID] {
            timers.values.forEach { $0.cancel() }
            reminderTimers.removeValue(forKey: occurrenceID)
        }
        if let timer = snoozeTimers[occurrenceID] {
            timer.cancel()
            snoozeTimers.removeValue(forKey: occurrenceID)
        }
        if let timer = autoJoinTimers[occurrenceID] {
            timer.cancel()
            autoJoinTimers.removeValue(forKey: occurrenceID)
        }
        pendingReminders.removeAll { $0.key.occurrenceID == occurrenceID }
        reminderEvents.removeValue(forKey: occurrenceID)
        triggeredReminderLeadTimes[occurrenceID] = Set(ReminderLeadTime.allCases.map { $0.rawValue })
    }

    private func scheduleSnooze(for occurrenceID: ReminderOccurrenceID, seconds: Int) {
        let event = reminderEvents[occurrenceID] ?? eventStore.event(withIdentifier: occurrenceID.eventIdentifier)
        guard let event else { return }

        let now = Date()
        guard event.startDate > now else { return }

        let fireDate = now.addingTimeInterval(TimeInterval(max(seconds, 1)))
        if let existing = snoozeTimers[occurrenceID] {
            existing.cancel()
        }

        let timer = makeSnoozeTimer(fireDate: fireDate, occurrenceID: occurrenceID)
        snoozeTimers[occurrenceID] = timer
    }

    private func scheduleAutoJoin(for occurrenceID: ReminderOccurrenceID, url: URL) {
        let now = Date()
        let fireDate = max(occurrenceID.occurrenceStart.addingTimeInterval(-3), now)

        if let existing = autoJoinTimers[occurrenceID] {
            existing.cancel()
        }
        autoJoinTimers[occurrenceID] = makeAutoJoinTimer(fireDate: fireDate, occurrenceID: occurrenceID, url: url)
    }

    @objc private func refreshMeetingsNotification(_ notification: Notification) {
        fetchNextMeeting()
    }

    private func updateStatusForCurrent(event: EKEvent, button: NSStatusBarButton) {
        if ReminderPreferences.showMeetingTitleInMenu {
            let timeRemaining = event.endDate?.timeIntervalSinceNow ?? 0
            let minutesRemaining = roundedMinutes(from: timeRemaining)
            let formatted = formattedTimeDescription(forMinutes: minutesRemaining)
            
            var title = event.title ?? "No Title"
            let maxLength = 20
            if title.count > maxLength {
                title = String(title.prefix(maxLength - 3)) + "..."
            }
            button.title = "\(title) (Ends in \(formatted))"
        } else {
            button.title = ""
        }
        button.imagePosition = ReminderPreferences.showMeetingTitleInMenu ? .imageLeading : .imageOnly
    }

    private func updateStatusForUpcoming(event: EKEvent, button: NSStatusBarButton) {
        if ReminderPreferences.showMeetingTitleInMenu {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"

            let meetingTime = formatter.string(from: event.startDate)
            let timeUntilMeeting = max(event.startDate.timeIntervalSinceNow, 0)
            let minutesUntilMeeting = roundedMinutes(from: timeUntilMeeting)
            let timeString = formattedTimeDescription(forMinutes: minutesUntilMeeting)
            
            var title = event.title ?? "No Title"
            let maxLength = 20
            if title.count > maxLength {
                title = String(title.prefix(maxLength - 3)) + "..."
            }
            button.title = "\(title) at \(meetingTime) (\(timeString))"
        } else {
            button.title = ""
        }
        button.imagePosition = ReminderPreferences.showMeetingTitleInMenu ? .imageLeading : .imageOnly
    }

    private func updateStatusForAllDay(event: EKEvent, button: NSStatusBarButton) {
        if ReminderPreferences.showMeetingTitleInMenu {
            var title = event.title ?? "No Title"
            let maxLength = 20
            if title.count > maxLength {
                title = String(title.prefix(maxLength - 3)) + "..."
            }
            button.title = "\(title) (All day)"
        } else {
            button.title = ""
        }
        button.imagePosition = ReminderPreferences.showMeetingTitleInMenu ? .imageLeading : .imageOnly
    }

    private func fallbackAllDayEvent(now: Date) -> EKEvent? {
        guard ReminderPreferences.showAllDayEvents else { return nil }
        let allDayEvents = upcomingEvents.filter { $0.isAllDay }
        if let activeAllDay = allDayEvents.first(where: { $0.startDate <= now && now < $0.endDate }) {
            return activeAllDay
        }
        return allDayEvents.first(where: { $0.startDate > now })
    }

    private func shouldDisplayInStatusBar(_ event: EKEvent) -> Bool {
        if ReminderPreferences.showAllDayEvents {
            return true
        }

        if event.isAllDay {
            return false
        }

        let calendar = Calendar.current
        if let endDate = event.endDate,
           !calendar.isDate(event.startDate, inSameDayAs: endDate) {
            return false
        }

        return true
    }

}
