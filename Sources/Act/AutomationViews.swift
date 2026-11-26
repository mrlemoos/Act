import AppKit
import SwiftUI

@MainActor
final class AutomationPopupController: NSWindowController {
    init<Content: View>(title: String, size: NSSize, content: Content) {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 500, height: 420)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []; panel.contentView = host
        super.init(window: panel)
    }
    required init?(coder: NSCoder) { nil }
    func present() { window?.center(); window?.makeKeyAndOrderFront(nil) }
}