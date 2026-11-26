import AppKit
import SwiftUI
import EventKit

final class MeetingsPopoverController: NSObject, NSPopoverDelegate {
    private let viewModel: MeetingsViewModel
    private let popover: NSPopover
    private let hostingController: NSHostingController<MeetingsView>

    private let onSelectEvent: (EKEvent) -> Void
    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(viewModel: MeetingsViewModel,
         onSelectEvent: @escaping (EKEvent) -> Void,
         onRefresh: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSelectEvent = onSelectEvent
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit

        self.hostingController = NSHostingController(rootView: MeetingsView(
            viewModel: viewModel,
            onSelectMeeting: { _ in }, // Placeholder
            onRefresh: {},
            onOpenSettings: {},
            onQuit: {}
        ))

        self.popover = NSPopover()

        super.init()

        self.hostingController.rootView = MeetingsView(
            viewModel: viewModel,
            onSelectMeeting: { [weak self] id in
                guard let self, let event = viewModel.event(for: id) else { return }
                self.close()
                onSelectEvent(event)
            },
            onRefresh: { [weak self] in
                guard let self else { return }
                self.close()
                onRefresh()
            },
            onOpenSettings: { [weak self] in
                self?.close()
                onOpenSettings()
            },
            onQuit: { [weak self] in
                self?.close()
                onQuit()
            }
        )

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 360, height: 500)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func updateMeetings(current: EKEvent?, next: EKEvent?, all events: [EKEvent], accessIssue: CalendarAccessIssue?) {
        viewModel.update(current: current, next: next, all: events)
        if viewModel.accessIssue != accessIssue {
            viewModel.accessIssue = accessIssue
        }
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        false
    }
}
