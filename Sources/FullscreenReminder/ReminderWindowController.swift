import AppKit
import SwiftUI
import EventKit

class ReminderWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    convenience init(event: EKEvent) {
        let contentView = KeyCatchingHostingView(rootView: ReminderView(event: event))
        contentView.onEscape = {
            NotificationCenter.default.post(name: .closeReminderWindow, object: nil)
        }
        let window = ReminderWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = contentView
        window.styleMask = [.borderless]
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.makeFirstResponder(window.contentView)
        self.init(window: window)
        window.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(closeWindow), name: .closeReminderWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateWindowFrame), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateWindowFrame), name: NSWindow.didChangeScreenNotification, object: window)
    }

    func showReminder() {
        updateWindowFrame()
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(self)
        } else {
            showWindow(self)
        }
    }

    @objc func closeWindow() {
        window?.close()
    }

    @objc private func updateWindowFrame() {
        guard let window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
