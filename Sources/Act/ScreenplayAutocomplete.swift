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

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
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
        table.doubleAction = #selector(acceptSelection)
        table.allowsEmptySelection = false
        scroll.documentView = table
        panel.contentView = scroll
    }

    func refresh(textView: NSTextView, source: String, screenplay: FountainScreenplay, libraryNames: [String]) {
        self.textView = textView
        let selection = textView.selectedRange()
        guard let session = FountainAutocomplete.session(source: source, selection: selection, libraryNames: libraryNames,
                                                        imeComposing: textView.hasMarkedText()) else {
            dismiss()
            return
        }
        let items = FountainAutocomplete.suggestions(for: session, screenplay: screenplay,
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
        if !panel.isVisible { panel.orderFront(nil) }
    }

    func dismiss() {
        session = nil
        suggestions = []
        selectedRow = 0
        panel.orderOut(nil)
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

    func handleClick(at location: NSPoint) -> Bool {
        guard panel.isVisible else { return false }
        let local = table.convert(location, from: nil)
        let row = table.row(at: local)
        guard row >= 0 else { return false }
        selectedRow = row
        return accept()
    }

    @objc private func acceptSelection() { accept() }

    func numberOfRows(in tableView: NSTableView) -> Int { suggestions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
        var rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 0), in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        guard let window = textView.window else { return }
        let screen = window.convertToScreen(NSRect(origin: rect.origin, size: .zero)).origin
        let height = min(CGFloat(suggestions.count) * table.rowHeight + 6, 220)
        panel.setFrame(NSRect(x: screen.x, y: screen.y - height - 4, width: 300, height: height), display: true)
    }
}