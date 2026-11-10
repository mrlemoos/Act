import ActCore
import AppKit
import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenplayPreviewModel: ObservableObject {
    @Published private(set) var pdf: PDFDocument?
    @Published var error: String?
    private weak var screenplay: FountainDocument?
    private let preferences: WritingPreferences
    private var subscriptions: Set<AnyCancellable> = []

    init(document: FountainDocument, preferences: WritingPreferences = .shared) {
        screenplay = document
        self.preferences = preferences
        document.$source.combineLatest(preferences.$settings)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    func refresh() {
        guard let screenplay else { return }
        do {
            let data = try ScreenplayPDF.data(source: screenplay.source, settings: preferences.settings)
            guard let document = PDFDocument(data: data) else { throw ScreenplayPDFError.cannotCreatePDF }
            pdf = document
            error = nil
        } catch {
            pdf = nil
            self.error = error.localizedDescription
        }
    }

    func printPDF() {
        refresh()
        guard let pdf, let screenplay else { return }
        let info = NSPrintInfo(dictionary: [:])
        info.paperSize = ScreenplayPaper.read(from: screenplay.source).size
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            error = "Act could not prepare the screenplay for printing."
            return
        }
        operation.run()
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (screenplay?.fileURL?.deletingPathExtension().lastPathComponent ?? "Screenplay") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        refresh()
        guard let data = pdf?.dataRepresentation() else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}

struct ScreenplayPreview: View {
    @ObservedObject var document: FountainDocument
    @ObservedObject var model: ScreenplayPreviewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("Paper", selection: Binding(get: { ScreenplayPaper.read(from: document.source) }, set: { document.setPaper($0) })) {
                    ForEach(ScreenplayPaper.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 190)
                Spacer()
                Button("Export PDF…", action: model.exportPDF)
                Button("Print…", action: model.printPDF).buttonStyle(.borderedProminent)
            }.padding(16)
            Divider()
            if let error = model.error {
                ContentUnavailableView("Unable to create PDF", systemImage: "doc", description: Text(error))
                Button("Retry", action: model.refresh).padding(.bottom)
            } else if let pdf = model.pdf {
                ScreenplayPDFView(document: pdf)
            }
        }.frame(minWidth: 580, minHeight: 480)
    }
}

struct ScreenplayPDFView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document !== document else { return }
        let previous = view.document
        let index = view.currentPage.flatMap { previous?.index(for: $0) } ?? 0
        let point = view.currentDestination?.point
        let scale = view.scaleFactor
        let autoScales = view.autoScales
        view.document = document
        view.autoScales = autoScales
        if !autoScales { view.scaleFactor = scale }
        if previous != nil, let page = document.page(at: min(index, document.pageCount - 1)) {
            if let point { view.go(to: PDFDestination(page: page, at: point)) }
            else { view.go(to: page) }
        }
    }
}

@MainActor
final class ScreenplayPreviewController: NSWindowController {
    let model: ScreenplayPreviewModel

    init(document: FountainDocument) {
        model = ScreenplayPreviewModel(document: document)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PDF preview"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 580, height: 480)
        window.contentView = NSHostingView(rootView: ScreenplayPreview(document: document, model: model))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}
