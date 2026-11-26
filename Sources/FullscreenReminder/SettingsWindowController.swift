import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var sizeObservation: NSKeyValueObservation?
    private var resignObserver: NSObjectProtocol?

    func present(with viewModel: CalendarSelectionViewModel) {
        guard let window else { return }
        viewModel.reload()

        // The window follows the SwiftUI content's preferred size, so it grows when the calendar
        // list (loaded asynchronously) arrives. Letting the hosting controller set the size through
        // .intrinsicContentSize constraints collapsed the window to 0x0 on a second opening.
        let hostingController = NSHostingController(rootView: SettingsView(calendarSelectionViewModel: viewModel))
        hostingController.sizingOptions = [.preferredContentSize]
        window.contentViewController = hostingController
        fit(to: hostingController.view.fittingSize, keepingTop: false)
        window.center()
        sizeObservation = hostingController.observe(\.preferredContentSize, options: [.new]) { [weak self] controller, _ in
            DispatchQueue.main.async { self?.fit(to: controller.preferredContentSize, keepingTop: true) }
        }

        // Close when the user switches to another app. Otherwise the window lingers behind other
        // windows (or on another Space), and clicking the menu bar icon, which activates the app,
        // brings it back as if Settings had opened by itself.
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.close()
            }
        }

        showWindow(nil)
        // A menu bar (LSUIElement) app is usually not active when this is called, and macOS
        // no longer lets it force itself frontmost, so bring the window forward regardless.
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    private func fit(to size: NSSize, keepingTop: Bool) {
        guard let window, size.width > 100, size.height > 100 else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        let contentSize = NSSize(width: size.width, height: min(size.height, (visible?.height ?? 900) - 40))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        guard abs(frame.height - window.frame.height) > 0.5 || abs(frame.width - window.frame.width) > 0.5 else { return }
        frame.origin.x = window.frame.minX
        frame.origin.y = keepingTop ? window.frame.maxY - frame.height : window.frame.minY
        if keepingTop, let visible, frame.minY < visible.minY {
            frame.origin.y = visible.minY  // Grow downward, but stay on screen.
        }
        window.setFrame(frame, display: true)
    }
}
