import Foundation
import AppKit
import EventKit

enum ReminderLeadTime: Int, CaseIterable {
    case one = 1
    case five = 5
    case fifteen = 15

    var minutesDescription: String {
        switch self {
        case .one:
            return "1 minute before"
        case .five:
            return "5 minutes before"
        case .fifteen:
            return "15 minutes before"
        }
    }
}

enum ReminderStyle: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case glassmorphism = "Glassmorphism"
    
    var id: String { rawValue }
}

struct ReminderPreferences {
    static let notifyOneMinuteKey = "notifyOneMinute"
    static let notifyFiveMinutesKey = "notifyFiveMinutes"
    static let notifyFifteenMinutesKey = "notifyFifteenMinutes"
    static let notificationSoundNameKey = "notificationSoundName"
    static let showAllDayEventsKey = "showAllDayEvents"
    static let showMeetingTitleInMenuKey = "showMeetingTitleInMenu"
    static let preferredLeadTimeKey = "preferredLeadTime"
    private static let leadTimeMigrationKey = "leadTimeMigrationV2"
    static let reminderStyleKey = "reminderStyle"
    static let selectedCalendarIDsKey = "selectedCalendarIDs"
    static let daysToDisplayKey = "daysToDisplay"
    static let snoozeMinutesKey = "snoozeMinutes"

    static let defaultSoundName = "Glass"
    static let defaultDaysToDisplay = 7
    static let defaultSnoozeMinutes = 5
    private static let minDaysToDisplay = 1
    private static let maxDaysToDisplay = 30
    private static let minSnoozeMinutes = 1
    private static let maxSnoozeMinutes = 30
    private static let supportedExtensions: [String] = ["aiff", "aif", "caf", "wav", "mp3", "m4a"]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            notifyOneMinuteKey: true,
            notifyFiveMinutesKey: false,
            notifyFifteenMinutesKey: false,
            notificationSoundNameKey: defaultSoundName,
            showAllDayEventsKey: true,
            showMeetingTitleInMenuKey: true,
            preferredLeadTimeKey: ReminderLeadTime.one.rawValue,
            reminderStyleKey: ReminderStyle.glassmorphism.rawValue,
            selectedCalendarIDsKey: [],
            daysToDisplayKey: defaultDaysToDisplay,
            snoozeMinutesKey: defaultSnoozeMinutes
        ])
        migrateLeadTimesIfNeeded()
    }

    static func isEnabled(for leadTime: ReminderLeadTime) -> Bool {
        switch leadTime {
        case .one:
            return notifyOneMinute
        case .five:
            return notifyFiveMinutes
        case .fifteen:
            return notifyFifteenMinutes
        }
    }

    static func setEnabled(_ enabled: Bool, for leadTime: ReminderLeadTime) {
        switch leadTime {
        case .one:
            notifyOneMinute = enabled
        case .five:
            notifyFiveMinutes = enabled
        case .fifteen:
            notifyFifteenMinutes = enabled
        }
    }

    static var notifyOneMinute: Bool {
        get { UserDefaults.standard.bool(forKey: notifyOneMinuteKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyOneMinuteKey) }
    }

    static var notifyFiveMinutes: Bool {
        get { UserDefaults.standard.bool(forKey: notifyFiveMinutesKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyFiveMinutesKey) }
    }

    static var notifyFifteenMinutes: Bool {
        get { UserDefaults.standard.bool(forKey: notifyFifteenMinutesKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyFifteenMinutesKey) }
    }

    static var preferredLeadTime: ReminderLeadTime {
        get {
            let raw = UserDefaults.standard.integer(forKey: preferredLeadTimeKey)
            return ReminderLeadTime(rawValue: raw) ?? .one
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferredLeadTimeKey)
        }
    }

    private static func migrateLeadTimesIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: leadTimeMigrationKey) {
            return
        }

        let rawValue = defaults.integer(forKey: preferredLeadTimeKey)
        let preferred = ReminderLeadTime(rawValue: rawValue) ?? .one

        notifyOneMinute = preferred == .one
        notifyFiveMinutes = preferred == .five
        notifyFifteenMinutes = preferred == .fifteen

        defaults.set(true, forKey: leadTimeMigrationKey)
    }

    static var reminderStyle: ReminderStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: reminderStyleKey) ?? ReminderStyle.glassmorphism.rawValue
            return ReminderStyle(rawValue: raw) ?? .glassmorphism
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: reminderStyleKey)
        }
    }

    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: notificationSoundNameKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationSoundNameKey)
        }
    }

    static var availableSoundNames: [String] {
        var names = Set(soundResources().keys)
        names.insert(defaultSoundName)
        return names.sorted()
    }

    static func soundURL(for name: String) -> URL? {
        soundResources()[name]
    }

    static var showAllDayEvents: Bool {
        get { UserDefaults.standard.bool(forKey: showAllDayEventsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showAllDayEventsKey) }
    }

    static var showMeetingTitleInMenu: Bool {
        get { UserDefaults.standard.bool(forKey: showMeetingTitleInMenuKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMeetingTitleInMenuKey) }
    }

    static var selectedCalendarIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.array(forKey: selectedCalendarIDsKey) as? [String] ?? []
            return Set(stored)
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: selectedCalendarIDsKey)
            } else {
                UserDefaults.standard.set(Array(newValue), forKey: selectedCalendarIDsKey)
            }
        }
    }

    static func isCalendarSelected(_ calendar: EKCalendar) -> Bool {
        let selected = selectedCalendarIDs
        guard !selected.isEmpty else { return true }
        return selected.contains(calendar.calendarIdentifier)
    }

    static func filteredCalendars(from calendars: [EKCalendar]) -> [EKCalendar] {
        let selected = selectedCalendarIDs
        guard !selected.isEmpty else { return calendars }
        let filtered = calendars.filter { selected.contains($0.calendarIdentifier) }
        return filtered.isEmpty ? calendars : filtered
    }

    static var daysToDisplay: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: daysToDisplayKey)
            if value == 0 {
                return defaultDaysToDisplay
            }
            return max(min(value, maxDaysToDisplay), minDaysToDisplay)
        }
        set {
            let clamped = max(min(newValue, maxDaysToDisplay), minDaysToDisplay)
            UserDefaults.standard.set(clamped, forKey: daysToDisplayKey)
        }
    }

    static var snoozeMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: snoozeMinutesKey)
            if value == 0 {
                return defaultSnoozeMinutes
            }
            return max(min(value, maxSnoozeMinutes), minSnoozeMinutes)
        }
        set {
            let clamped = max(min(newValue, maxSnoozeMinutes), minSnoozeMinutes)
            UserDefaults.standard.set(clamped, forKey: snoozeMinutesKey)
        }
    }

    private static func soundResources() -> [String: URL] {
        var resources: [String: URL] = [:]
        let fileManager = FileManager.default

        for directory in soundDirectories() where fileManager.fileExists(atPath: directory.path) {
            guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
                continue
            }

            for url in contents {
                let ext = url.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }

                let name = url.deletingPathExtension().lastPathComponent
                if resources[name] == nil {
                    resources[name] = url
                }
            }
        }

        return resources
    }

    private static func soundDirectories() -> [URL] {
        var directories: [URL] = [
            URL(fileURLWithPath: "/System/Library/Sounds"),
            URL(fileURLWithPath: "/Library/Sounds")
        ]

        if let userLibrary = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(userLibrary.appendingPathComponent("Sounds"))
        }

        return directories
    }
}
