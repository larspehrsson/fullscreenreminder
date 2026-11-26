import SwiftUI

final class KeyCatchingHostingView<Content: View>: NSHostingView<Content> {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
