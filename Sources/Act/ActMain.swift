import AppKit
import SwiftUI

@main
struct ActMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ActApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class ActApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let documents = ActDocumentController()
    @objc func openSettings(_ sender: Any?) {
        if activeDocument == nil { documents.newDocument(sender) }
        guard let document = activeDocument else { return }
        document.showsSettings = true
        document.windowControllers.first?.window?.makeKeyAndOrderFront(sender)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if documents.documents.isEmpty { documents.newDocument(nil) }
        installMainMenu()
        DispatchQueue.main.async { self.installMainMenu() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func installMainMenu() {
        NSApp.mainMenu = makeMenu()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for case let document as FountainDocument in documents.documents {
            if !document.confirmShotClosure() { return .terminateCancel }
        }
        return .terminateNow
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        documents.newDocument(nil)
        return true
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            documents.openDocument(withContentsOf: URL(fileURLWithPath: filename), display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    private var activeDocument: FountainDocument? {
        for window in NSApp.orderedWindows {
            if let document = window.windowController?.document as? FountainDocument { return document }
            if let document = documents.documents.first(where: { document in document.windowControllers.contains { $0.window === window } }) as? FountainDocument { return document }
        }
        return documents.currentDocument as? FountainDocument
    }

    @objc private func previewCurrentDocument(_ sender: Any?) { activeDocument?.showPDFPreview() }

    @objc private func saveCurrentDocument(_ sender: Any?) { activeDocument?.save(sender) }
    @objc private func saveCurrentDocumentAs(_ sender: Any?) { activeDocument?.saveAs(sender) }
    @objc private func revertCurrentDocument(_ sender: Any?) { activeDocument?.revertToSaved(sender) }
    @objc private func closeCurrentDocument(_ sender: Any?) {
        guard let document = activeDocument else { return }
        let window = document.windowControllers.compactMap(\.window).first { $0.isKeyWindow || $0.isMainWindow }
            ?? document.windowControllers.first?.window
        window?.performClose(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openSettings(_:)) { return true }
        if menuItem.action == #selector(revertCurrentDocument(_:)) { return activeDocument?.fileURL != nil }
        return activeDocument != nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let app = NSMenu(title: "Act")
        app.addItem(withTitle: "About Act", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Act", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Act", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "Act", action: nil, keyEquivalent: "").submenu = app
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n").target = documents
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o").target = documents
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(closeCurrentDocument(_:)), keyEquivalent: "w").target = self
        file.addItem(withTitle: "Save", action: #selector(saveCurrentDocument(_:)), keyEquivalent: "s").target = self
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(saveCurrentDocumentAs(_:)), keyEquivalent: "S")
        saveAs.target = self
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Revert to Saved…", action: #selector(revertCurrentDocument(_:)), keyEquivalent: "").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "PDF Preview…", action: #selector(previewCurrentDocument(_:)), keyEquivalent: "p").target = self
        menu.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = file
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window
        return menu
    }
}
