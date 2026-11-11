import ActCore
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
        for case let project as ProjectBoardDocument in documents.documents {
            if project.workspaceHost == nil && !project.confirmTermination() { return .terminateCancel }
        }
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

    @objc private func newProject(_ sender: Any?) {
        do {
            let document = try documents.makeUntitledDocument(ofType: "dev.act.project")
            documents.addDocument(document); document.makeWindowControllers(); document.showWindows()
        } catch { NSApp.presentError(error) }
    }

    private var activeFileDocument: NSDocument? {
        NSApp.keyWindow?.windowController?.document as? NSDocument ?? documents.currentDocument
    }

    @objc private func previewCurrentDocument(_ sender: Any?) { activeDocument?.showPDFPreview() }

    @objc private func saveCurrentDocument(_ sender: Any?) { activeFileDocument?.save(sender) }
    @objc private func saveCurrentDocumentAs(_ sender: Any?) { activeFileDocument?.saveAs(sender) }
    @objc private func revertCurrentDocument(_ sender: Any?) { activeFileDocument?.revertToSaved(sender) }
    @objc private func closeCurrentDocument(_ sender: Any?) {
        guard let document = activeFileDocument else { return }
        let window = document.windowControllers.compactMap(\.window).first { $0.isKeyWindow || $0.isMainWindow }
            ?? document.windowControllers.first?.window
        window?.performClose(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openSettings(_:)) { return true }
        if menuItem.action == #selector(revertCurrentDocument(_:)) { if let host = activeFileDocument as? FountainDocument, host.requestedWorkspace == .board { return host.projectBoard?.fileURL != nil }
            return activeFileDocument?.fileURL != nil }
        return activeFileDocument != nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let app = NSMenu(title: "Act")
        app.addItem(withTitle: L10n.string("About Act", table: "Menus"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: L10n.string("Settings…", table: "Menus"), action: #selector(openSettings(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: L10n.string("Hide Act", table: "Menus"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: L10n.string("Quit Act", table: "Menus"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "Act", action: nil, keyEquivalent: "").submenu = app
        let file = NSMenu(title: L10n.string("File", table: "Menus"))
        file.addItem(withTitle: L10n.string("New", table: "Menus"), action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n").target = documents
        file.addItem(withTitle: L10n.string("New Project", table: "Menus"), action: #selector(newProject(_:)), keyEquivalent: "N").target = self
        file.addItem(withTitle: L10n.string("Open…", table: "Menus"), action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o").target = documents
        file.addItem(.separator())
        file.addItem(withTitle: L10n.string("Close", table: "Menus"), action: #selector(closeCurrentDocument(_:)), keyEquivalent: "w").target = self
        file.addItem(withTitle: L10n.string("Save", table: "Menus"), action: #selector(saveCurrentDocument(_:)), keyEquivalent: "s").target = self
        let saveAs = file.addItem(withTitle: L10n.string("Save As…", table: "Menus"), action: #selector(saveCurrentDocumentAs(_:)), keyEquivalent: "S")
        saveAs.target = self
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: L10n.string("Revert to Saved…", table: "Menus"), action: #selector(revertCurrentDocument(_:)), keyEquivalent: "").target = self
        file.addItem(.separator())
        file.addItem(withTitle: L10n.string("PDF Preview…", table: "Menus"), action: #selector(previewCurrentDocument(_:)), keyEquivalent: "p").target = self
        menu.addItem(withTitle: L10n.string("File", table: "Menus"), action: nil, keyEquivalent: "").submenu = file
        let edit = NSMenu(title: L10n.string("Edit", table: "Menus"))
        edit.addItem(withTitle: L10n.string("Undo", table: "Menus"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L10n.string("Redo", table: "Menus"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.string("Cut", table: "Menus"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.string("Copy", table: "Menus"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.string("Paste", table: "Menus"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.string("Select All", table: "Menus"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: L10n.string("Find…", table: "Menus"), action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        menu.addItem(withTitle: L10n.string("Edit", table: "Menus"), action: nil, keyEquivalent: "").submenu = edit
        let window = NSMenu(title: L10n.string("Window", table: "Menus"))
        window.addItem(withTitle: L10n.string("Minimise", table: "Menus"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L10n.string("Zoom", table: "Menus"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L10n.string("Window", table: "Menus"), action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window
        return menu
    }
}
