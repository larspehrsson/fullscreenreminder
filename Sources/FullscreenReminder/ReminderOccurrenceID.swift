import Foundation
import EventKit

struct ReminderOccurrenceID: Hashable {
    let eventIdentifier: String
    let occurrenceStart: Date

    init?(event: EKEvent) {
        guard let identifier = event.eventIdentifier else { return nil }
        self.eventIdentifier = identifier
        self.occurrenceStart = event.startDate
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let identifierData = Data(base64Encoded: components[0]),
              let identifier = String(data: identifierData, encoding: .utf8),
              let occurrence = ReminderOccurrenceID.formatter.date(from: components[1]) else {
            return nil
        }
        self.eventIdentifier = identifier
        self.occurrenceStart = occurrence
    }

    var rawValue: String {
        let encodedIdentifier = Data(eventIdentifier.utf8).base64EncodedString()
        let timestamp = ReminderOccurrenceID.formatter.string(from: occurrenceStart)
        return "\(encodedIdentifier)|\(timestamp)"
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
