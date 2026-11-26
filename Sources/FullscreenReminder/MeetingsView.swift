import AppKit
import SwiftUI

struct MeetingsView: View {
    @ObservedObject var viewModel: MeetingsViewModel
    var onSelectMeeting: (String) -> Void
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    @State private var searchText: String = ""
    @State private var hoveredMeetingID: String?
    private var filteredSections: [MeetingSection] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return viewModel.sections
        }
        let lowercaseQuery = searchText.lowercased()
        let filteredMeetings = viewModel.sections.flatMap { $0.meetings }.filter { meeting in
            meeting.title.lowercased().contains(lowercaseQuery) ||
                (meeting.location?.lowercased().contains(lowercaseQuery) ?? false)
        }
        let grouped = Dictionary(grouping: filteredMeetings) { meeting in
            Calendar.current.startOfDay(for: meeting.startDate)
        }
        return grouped
            .sorted(by: { $0.key < $1.key })
            .map { day, rows in
                let title = MeetingsViewModel.formattedDayTitle(for: day)
                let sortedRows = rows.sorted(by: { $0.startDate < $1.startDate })
                return MeetingSection(id: MeetingsViewModel.sectionIdentifierFormatter.string(from: day), title: title, meetings: sortedRows)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Text("Meetings")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    headerButton(icon: "arrow.clockwise", help: "Refresh", action: onRefresh)
                    headerButton(icon: "gearshape.fill", help: "Settings", action: onOpenSettings)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Spotlight-style Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                TextField("Search events...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            let sections = filteredSections

            if let issue = viewModel.accessIssue {
                accessIssueView(issue)
            } else if sections.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section(header: sectionHeaderView(title: section.title)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(section.meetings) { meeting in
                                        meetingCard(for: meeting)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }

            // Footer
            footerView
        }
        .frame(width: 360)
        .frame(minHeight: 450, maxHeight: 600)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.3))
                .symbolEffect(.pulse, options: .repeating)
            
            Text("Clear Skies")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.secondary)
            
            Text("No meetings found for this period.")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accessIssueView(_ issue: CalendarAccessIssue) -> some View {
        let message: String
        switch issue {
        case .notGranted:
            message = "FullscreenReminder needs full access to your calendars to show meetings and reminders. Turn it on in Privacy & Security \u{2192} Calendars."
        case .noCalendars:
            message = "macOS says access is allowed, but no calendars are visible. This usually happens after updating from an older version. Reset the permission, then choose Full Access when macOS asks."
        }

        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("No Calendar Access")
                .font(.system(size: 18, weight: .bold))

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            VStack(spacing: 8) {
                if issue == .noCalendars {
                    Button("Reset Calendar Access") { CalendarAccess.resetAndRelaunch() }
                        .buttonStyle(.borderedProminent)
                    Button("Open Privacy Settings") { CalendarAccess.openPrivacySettings() }
                        .buttonStyle(.link)
                } else {
                    Button("Open Privacy Settings") { CalendarAccess.openPrivacySettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Reset Calendar Access") { CalendarAccess.resetAndRelaunch() }
                        .buttonStyle(.link)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerView: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1)
            // Quit sits down here, away from the header's Settings button.
            ZStack {
                Text("\(viewModel.allEvents.count) Events")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                HStack {
                    Spacer()
                    Button(action: onQuit) {
                        Label("Quit", systemImage: "power")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit FullscreenReminder")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.02))
    }

    private func headerButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func sectionHeaderView(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.9))
    }

    private func meetingCard(for meeting: MeetingRow) -> some View {
        let isHovered = hoveredMeetingID == meeting.id
        
        return Button {
            onSelectMeeting(meeting.id)
        } label: {
            HStack(spacing: 0) {
                // Left Accent
                RoundedRectangle(cornerRadius: 2)
                    .fill(meeting.calendarColor.flatMap { Color(nsColor: $0) } ?? Color.secondary)
                    .frame(width: 4)
                    .padding(.vertical, 12)
                    .padding(.leading, 2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(meeting.timeRange)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let url = meeting.googleMeetURL ?? meeting.url {
                            joinButton(url: url, isCurrent: meeting.isCurrent)
                        }
                    }

                    if let location = meeting.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                            Text(location)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                    }

                    if meeting.isCurrent {
                        statusBadge(text: inProgressText(for: meeting), color: .green)
                    } else if let upcoming = upcomingSoonText(for: meeting) {
                        statusBadge(text: upcoming, color: .orange)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(meeting.isCurrent ? Color.green.opacity(0.6) : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(meeting.isCurrent ? 0.1 : 0), radius: 4, x: 0, y: 2)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMeetingID = hovering ? meeting.id : nil
        }
    }

    private func joinButton(url: URL, isCurrent: Bool) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                Text("Join")
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isCurrent ? Color.green : Color.primary.opacity(0.1))
            .foregroundColor(isCurrent ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private func calendarIndicator(for meeting: MeetingRow) -> some View {
        let color =
            meeting.calendarColor.flatMap { Color(nsColor: $0) } ?? Color.secondary.opacity(0.5)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(maxHeight: .infinity)
    }
    private var sectionHeaderBackground: Color {
        Color(nsColor: NSColor.controlBackgroundColor).opacity(0.9)
    }
}

extension MeetingsView {
    fileprivate func inProgressText(for meeting: MeetingRow) -> String {
        let remaining = meeting.endDate.timeIntervalSince(Date())
        if remaining <= 0 {
            return "In progress"
        }

        let totalMinutes = Int((remaining + 59) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours)h")
        }
        if minutes > 0 {
            components.append("\(minutes)m")
        }

        let detail = components.joined(separator: " ")
        if detail.isEmpty {
            return "In progress"
        }
        return "In progress, \(detail) remaining"
    }

    fileprivate func upcomingSoonText(for meeting: MeetingRow) -> String? {
        let now = Date()
        guard meeting.startDate > now else { return nil }

        let timeUntil = meeting.startDate.timeIntervalSince(now)
        guard timeUntil <= 3 * 60 * 60 else { return nil }

        let totalMinutes = max(Int((timeUntil + 59) / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours)h")
        }
        if minutes > 0 {
            components.append("\(minutes)m")
        }

        let detail = components.joined(separator: " ")
        return detail.isEmpty ? nil : "Starts in \(detail)"
    }
}
