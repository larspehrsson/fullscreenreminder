import Foundation
import EventKit
import AppKit

struct CalendarOption: Identifiable {
    let id: String
    let name: String
    let color: NSColor?
    let isSelected: Bool
}

final class CalendarSelectionViewModel: ObservableObject {
    @Published private(set) var calendarOptions: [CalendarOption] = []

    private let eventStore: EKEventStore
    private var allCalendarIDs: Set<String> = []

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
        reload()
    }

    func reload() {
        let calendars = eventStore.calendars(for: .event)
        let selectedIDs = ReminderPreferences.selectedCalendarIDs
        allCalendarIDs = Set(calendars.map { $0.calendarIdentifier })

        let options = calendars.map { calendar -> CalendarOption in
            let color = NSColor(cgColor: calendar.cgColor)
            let isSelected = selectedIDs.isEmpty ? true : selectedIDs.contains(calendar.calendarIdentifier)
            return CalendarOption(
                id: calendar.calendarIdentifier,
                name: calendar.title,
                color: color,
                isSelected: isSelected
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async {
            self.calendarOptions = options
        }
    }

    func toggleSelection(for calendarID: String) {
        var selected = ReminderPreferences.selectedCalendarIDs
        if selected.isEmpty {
            selected = allCalendarIDs
        }
        if selected.contains(calendarID) {
            selected.remove(calendarID)
        } else {
            selected.insert(calendarID)
        }
        if selected.count == allCalendarIDs.count {
            selected = []
        }
        ReminderPreferences.selectedCalendarIDs = selected
        reload()
        NotificationCenter.default.post(name: .refreshMeetings, object: nil)
    }

    func isAllCalendarsSelected(for totalCalendars: Int) -> Bool {
        let selected = ReminderPreferences.selectedCalendarIDs
        return selected.isEmpty || selected.count == totalCalendars
    }
}
