import Foundation
import EventKit
import AppKit

struct MeetingRow: Identifiable {
    let id: String
    let title: String
    let timeRange: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let isCurrent: Bool
    let calendarColor: NSColor?
    let url: URL?
    let googleMeetURL: URL?
}

struct MeetingSection: Identifiable {
    let id: String
    let title: String
    let meetings: [MeetingRow]
}

final class MeetingsViewModel: ObservableObject {
    @Published private(set) var sections: [MeetingSection] = []
    @Published private(set) var allEvents: [MeetingRow] = []
    @Published var accessIssue: CalendarAccessIssue?

    private var eventsByID: [String: EKEvent] = [:]

    func update(current: EKEvent?, next: EKEvent?, all events: [EKEvent]) {
        _ = current
        _ = next
        var updatedEventsByID: [String: EKEvent] = [:]
        let now = Date()

        let calendar = Calendar.current
        var groupedRows: [Date: [MeetingRow]] = [:]

        for event in events {
            let identifier = identifier(for: event)
            updatedEventsByID[identifier] = event

            let trimmedTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmedTitle?.isEmpty == false) ? trimmedTitle! : "No Title"
            let timeRange = "\(Self.timeFormatter.string(from: event.startDate)) - \(Self.timeFormatter.string(from: event.endDate))"
            let isCurrent = event.startDate <= now && now < event.endDate
            let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let calendarColor = NSColor(cgColor: event.calendar.cgColor)
            let meetURL = Self.googleMeetURL(from: event)

            let row = MeetingRow(
                id: identifier,
                title: title,
                timeRange: timeRange,
                startDate: event.startDate,
                endDate: event.endDate,
                location: (location?.isEmpty == false) ? location : nil,
                isCurrent: isCurrent,
                calendarColor: calendarColor,
                url: event.url,
                googleMeetURL: meetURL
            )

            let day = calendar.startOfDay(for: event.startDate)
            groupedRows[day, default: []].append(row)
        }

        let sections = groupedRows
            .sorted(by: { $0.key < $1.key })
            .map { day, rows -> MeetingSection in
                let title = Self.formattedDayTitle(for: day)
                let sortedRows = rows.sorted(by: { $0.startDate < $1.startDate })
                return MeetingSection(id: Self.sectionIdentifierFormatter.string(from: day), title: title, meetings: sortedRows)
            }

        DispatchQueue.main.async {
            self.eventsByID = updatedEventsByID
            self.sections = sections
            self.allEvents = sections.flatMap { $0.meetings }
        }
    }

    private static func googleMeetURL(from event: EKEvent) -> URL? {
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

    func event(for id: String) -> EKEvent? {
        eventsByID[id]
    }

    private func identifier(for event: EKEvent) -> String {
        if let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty {
            return eventIdentifier
        }
        let calendarItemIdentifier = event.calendarItemIdentifier
        if !calendarItemIdentifier.isEmpty {
            return calendarItemIdentifier
        }
        return UUID().uuidString
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func formattedDayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return NSLocalizedString("Today", comment: "Section title for today's meetings")
        }
        if calendar.isDateInTomorrow(date) {
            return NSLocalizedString("Tomorrow", comment: "Section title for tomorrow's meetings")
        }
        if calendar.isDateInYesterday(date) {
            return NSLocalizedString("Yesterday", comment: "Section title for yesterday's meetings")
        }
        return dayTitleFormatter.string(from: date)
    }

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        return formatter
    }()

    static let sectionIdentifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
