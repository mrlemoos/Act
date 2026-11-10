import ActCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceSection: String { case screenplay, shots, characters }

struct WorkspaceView: View {
    @ObservedObject var document: FountainDocument
    @State private var sourceMode = false
    @State private var workspace: WorkspaceSection = .screenplay
    @ObservedObject private var preferences: WritingPreferences
    @State private var selectedOutlineEntry: String?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var selectionRequest = UUID()
    @State private var showOutline = false
    @State private var errorMessage: String?

    init(document: FountainDocument, initiallyShowsOutline: Bool = false, preferences: WritingPreferences = .shared, initialWorkspace: WorkspaceSection = .screenplay) {
        self.document = document
        self.preferences = preferences
        _showOutline = State(initialValue: initiallyShowsOutline)
        _workspace = State(initialValue: initialWorkspace)
    }

    private var screenplay: FountainScreenplay { FountainParser.parse(document.source) }
    private var outlineEntries: [FountainOutlineEntry] { FountainOutline.entries(in: screenplay) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button { showOutline.toggle() } label: { Image(systemName: "sidebar.left") }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                    .help("Toggle scene outline")
                    .accessibilityLabel("Toggle scene outline")
                Spacer()
                Picker("Workspace", selection: $workspace) {
                    Text("Screenplay").tag(WorkspaceSection.screenplay)
                    Text("Shot list").tag(WorkspaceSection.shots)
                    Text("Characters").tag(WorkspaceSection.characters)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
                Spacer()
                Menu {
                    Toggle("Scene outline", isOn: $showOutline)
                    if workspace == .screenplay {
                        Toggle("Fountain source", isOn: $sourceMode)
                            .keyboardShortcut("m", modifiers: [.command, .shift])
                        Divider()
                        Button("PDF Preview…") { document.showPDFPreview() }
                        Button("Export PDF…", action: exportPDF)
                            .keyboardShortcut("e", modifiers: [.command, .shift])
                    }
                    Divider()
                    Button("Settings…") { (NSApp.delegate as? ActApplicationDelegate)?.openSettings(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("View and export").accessibilityLabel("View and export")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24).frame(height: 42)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            HStack(spacing: 0) {
                if showOutline {
                    outline.frame(width: 228)
                    Divider()
                }
                if workspace == .shots {
                    ShotWorkspace(document: document)
                } else if workspace == .characters {
                    CharacterWorkspace(document: document)
                } else {
                    screenplayEditor
                }
                if document.showsSettings {
                    Divider()
                    SettingsView(preferences: preferences) { document.showsSettings = false }
                        .frame(width: 320)
                }
            }

        }
        .frame(minWidth: 820, minHeight: 540)
        .onChange(of: workspace) { _, value in
            document.isShotWorkspaceActive = value == .shots
            document.isCharacterWorkspaceActive = value == .characters
        }
        .onChange(of: document.showsSettings) { _, value in if value { showOutline = false } }
        .onChange(of: showOutline) { _, value in if value { document.showsSettings = false } }
        .onAppear {
            if document.showsSettings { showOutline = false }
            document.isShotWorkspaceActive = workspace == .shots
            document.isCharacterWorkspaceActive = workspace == .characters
        }
        .alert("Unable to export PDF", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outline").font(.system(size: 11, weight: .medium))
                Spacer()
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 25).padding(.bottom, 18)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if outlineEntries.isEmpty {
                        Text("No outline")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 4)
                    }
                    ForEach(outlineEntries) { entry in
                        Button {
                            selectedOutlineEntry = entry.id
                            selection = NSRange(location: entry.range.location, length: 0)
                            selectionRequest = UUID()
                            workspace = .screenplay
                        } label: {
                            Text(entry.text.isEmpty ? (entry.kind == .section ? "Untitled section" : "Synopsis") : entry.text)
                                .font(.system(size: entry.kind == .section ? 12 : 11, weight: entry.kind == .section ? .semibold : entry.kind == .synopsis ? .regular : .medium))
                                .foregroundStyle(entry.kind == .section ? Color(nsColor: SectionColours.forLevel(entry.depth + 1)) : entry.kind == .synopsis ? Color.secondary : Color.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12 + CGFloat(min(entry.depth, 5)) * 10)
                                .padding(.trailing, 12)
                                .padding(.vertical, entry.kind == .synopsis ? 5 : 10)
                                .background(selectedOutlineEntry == entry.id ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.kind == .synopsis ? "Synopsis: " + entry.text : entry.text)
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var screenplayEditor: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .textBackgroundColor)
            ScreenplayEditor(document: document, sourceMode: sourceMode, selection: selection, selectionRequest: selectionRequest, settings: preferences.settings)
            if document.source.isEmpty {
                Text("INT.").font(.custom(preferences.settings.fontName, size: preferences.settings.fontSize * 4 / 3)).foregroundStyle(.quaternary)
                    .frame(maxWidth: 624, alignment: .leading).padding(.top, 76).padding(.horizontal, 56).allowsHitTesting(false)
            }
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (document.fileURL?.deletingPathExtension().lastPathComponent ?? "Screenplay") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ScreenplayPDF.export(source: document.source, to: url, settings: preferences.settings) }
        catch { errorMessage = error.localizedDescription }
    }
}
