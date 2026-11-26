import ActCore
import AppKit

@MainActor
final class ScreenplayAutocompleteController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    private let table = NSTableView()
    private let scroll = NSScrollView()
    weak var textView: NSTextView?
    var onApply: ((String, NSRange) -> Void)?

    private(set) var session: FountainAutocomplete.Session?
    private(set) var suggestions: [FountainAutocomplete.Suggestion] = []
    private(set) var selectedRow = 0

    nonisolated(unsafe) private var eventMonitor: Any?
    nonisolated(unsafe) private var deactivateObserver: NSObjectProtocol?
    nonisolated(unsafe) private var windowObserver: NSObjectProtocol?

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
    }

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.level = .popUpMenu
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = 280
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(acceptSelection)
        table.allowsEmptySelection = false
        scroll.documentView = table
        panel.contentView = scroll
    }

    func refresh(textView: NSTextView, source: String, screenplay: () -> FountainScreenplay, libraryNames: [String]) {
        self.textView = textView
        let selection = textView.selectedRange()
        guard let session = FountainAutocomplete.session(source: source, selection: selection, libraryNames: libraryNames,
                                                        imeComposing: textView.hasMarkedText()) else {
            dismiss()
            return
        }
        let items = FountainAutocomplete.suggestions(for: session, screenplay: screenplay(),
                                                      libraryNames: libraryNames, locale: L10n.language)
        guard !items.isEmpty else {
            dismiss()
            return
        }
        self.session = session
        suggestions = items
        selectedRow = min(selectedRow, items.count - 1)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        table.scrollRowToVisible(selectedRow)
        positionPanel()
        if !panel.isVisible {
            textView.window?.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
                MainActor.assumeIsolated {
                    if event.window !== self?.panel { self?.dismiss() }
                }
                return event
            }
            deactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: textView.window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
    }

    func dismiss() {
        session = nil
        suggestions = []
        table.reloadData()
        selectedRow = 0
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver); self.deactivateObserver = nil }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver); self.windowObserver = nil }
    }

    func moveHighlight(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        selectedRow = (selectedRow + delta + suggestions.count) % suggestions.count
        table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        table.scrollRowToVisible(selectedRow)
    }

    @discardableResult
    func accept() -> Bool {
        guard let session, suggestions.indices.contains(selectedRow), let textView else { return false }
        let suggestion = suggestions[selectedRow]
        guard let result = FountainAutocomplete.applying(suggestion, to: textView.string, session: session) else { return false }
        onApply?(result.source, result.selection)
        dismiss()
        return true
    }

    @objc private func acceptSelection() { accept() }

    func numberOfRows(in tableView: NSTableView) -> Int { suggestions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard suggestions.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()
        view.textField?.stringValue = suggestions[row].displayText
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedRow = table.selectedRow >= 0 ? table.selectedRow : selectedRow
    }

    private func positionPanel() {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let selection = textView.selectedRange()
        let index = min(selection.location, max(0, (textView.string as NSString).length - 1))
        let glyph = layout.glyphIndexForCharacter(at: index)
        var rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: layout.numberOfGlyphs > glyph ? 1 : 0), in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        guard let window = textView.window else { return }
        let windowRect = textView.convert(rect, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        let visible = window.screen?.visibleFrame ?? screenRect
        let width = min(CGFloat(300), visible.width)
        let height = min(CGFloat(suggestions.count) * table.rowHeight + 6, 220)
        let x = min(max(screenRect.minX, visible.minX), visible.maxX - width)
        let below = screenRect.minY - height - 4
        let y = below >= visible.minY ? below : min(screenRect.maxY + 4, visible.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
