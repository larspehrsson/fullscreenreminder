import AppKit

final class ReminderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        makeKeyAndOrderFront(sender)
    }
}
