import ActCore
import AppKit
import SwiftUI
import Combine

struct ProjectBoardView: View {
    @ObservedObject var document: ProjectBoardDocument
    @State private var selected: UUID?
    @State private var sceneDraft: BoardCard?
    @State private var scenes: [FountainScene] = []
    @State private var drag = CGSize.zero
    @State private var refresh = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(L10n.string("Project board", table: "Board")).font(.headline)
                Spacer()
                Button(L10n.string("Link draft…", table: "Board")) { document.chooseDraft() }
                Button(L10n.string("Note", table: "Board")) { addNote() }
                Button(L10n.string("Group", table: "Board")) { document.change(L10n.string("Add group", table: "Board")) { $0.groups.append(BoardGroup(title: BoardPresentation.defaultGroupTitle(), position: document.insertionPoint)) } }
                Divider().frame(height: 18)
                Button("−") { zoom(by: 0.8) }.accessibilityLabel(L10n.string("Zoom out", table: "Board"))
                Text(document.board.zoom.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: L10n.language))))
                    .monospacedDigit().frame(width: 44)
                Button("+") { zoom(by: 1.25) }.accessibilityLabel(L10n.string("Zoom in", table: "Board"))
                Button(L10n.string("Reset view", table: "Board")) { document.change(L10n.string("Reset view", table: "Board")) { $0.pan = BoardPoint(x: 80, y: 80); $0.zoom = 1 } }
            }.buttonStyle(.borderless).padding(18)
            Divider()
            if let failure = document.failure {
                HStack {
                    Text(failure).font(.callout).textSelection(.enabled)
                    Spacer()
                    if document.saveFailed {
                        Button(L10n.string("Save copy…", table: "Board")) { document.saveAs(nil) }
                        Button(L10n.string("Reload…", table: "Board")) { document.revertToSaved(nil) }
                    }
                    Button(L10n.string("Dismiss", table: "Board")) { document.failure = nil }
                }.padding(12).background(Color.orange.opacity(0.15))
            }
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)
                    BoardNavigationSurface { delta, factor, point in
                        document.change(L10n.string("Navigate board", table: "Board")) { board in
                            board.navigate(by: delta, magnification: factor, around: point)
                        }
                    }
                    Canvas { context, size in
                        let spacing = 28 * document.board.zoom
                        let x0 = document.board.pan.x.truncatingRemainder(dividingBy: spacing)
                        let y0 = document.board.pan.y.truncatingRemainder(dividingBy: spacing)
                        for x in stride(from: x0, to: size.width, by: spacing) {
                            for y in stride(from: y0, to: size.height, by: spacing) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.22)))
                            }
                        }
                    }.allowsHitTesting(false)
                    ForEach(document.board.groups) { group in groupView(group) }
                    ForEach(document.board.cards) { card in cardView(card) }
                    if document.board.cards.isEmpty && document.board.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.string("Give your story room.", table: "Board")).font(.system(size: 34, weight: .medium, design: .serif))
                            Text(L10n.string("Link a draft, collect beats, arrange your project.", table: "Board")).foregroundStyle(.secondary)
                            Button(L10n.string("Link Fountain draft…", table: "Board")) { document.chooseDraft() }
                        }.padding(60).allowsHitTesting(true)
                    }
                }.clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(L10n.string("Scroll to pan · Pinch to zoom · Drag card headers to arrange", table: "Board"))
                        .font(.caption).foregroundStyle(.secondary).padding(12).allowsHitTesting(false)
                }
                .onReceive(timer) { _ in refresh += 1 }
            }
        }
        .sheet(item: $sceneDraft) { draft in
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.format("Add scenes from %@", draft.title, table: "Board")).font(.headline)
                List(scenes) { scene in
                    Button(scene.heading) { document.addScene(scene, draft: draft) }
                }.frame(minWidth: 500, minHeight: 300)
                Button(L10n.string("Done", table: "Board")) { sceneDraft = nil }.keyboardShortcut(.defaultAction)
            }.padding(24)
        }
    }
    private func zoom(by factor: Double) {
        document.change(L10n.string("Zoom board", table: "Board")) { $0.zoom = min(2, max(0.25, $0.zoom * factor)) }
    }
    private func addNote() {
        document.change(L10n.string("Add note", table: "Board")) { $0.cards.append(BoardCard(kind: .note, title: BoardPresentation.defaultNoteTitle(), position: document.insertionPoint)) }
    }
    private func offset(_ point: BoardPoint, id: UUID) -> CGSize {
        CGSize(width: point.x * document.board.zoom + document.board.pan.x + (selected == id ? drag.width : 0),
               height: point.y * document.board.zoom + document.board.pan.y + (selected == id ? drag.height : 0))
    }
    private func moveGesture(_ id: UUID, group: Bool = false) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { value in selected = id; drag = value.translation }
            .onEnded { value in
                let delta = BoardPoint(x: value.translation.width / document.board.zoom, y: value.translation.height / document.board.zoom)
                document.change(group ? L10n.string("Move group", table: "Board") : L10n.string("Move card", table: "Board")) {
                    if group { $0.moveGroup(id, by: delta) } else { $0.moveCard(id, by: delta) }
                }
                drag = .zero
            }
    }
    private func groupView(_ group: BoardGroup) -> some View {
        let members = document.board.cards.filter { $0.groupID == group.id }
        let right = max(group.position.x + 320, members.map { $0.position.x + 256 }.max() ?? 0)
        let bottom = max(group.position.y + 240, members.map { $0.position.y + 240 }.max() ?? 0)
        return VStack(alignment: .leading) {
            HStack {
                Image(systemName: "rectangle.3.group")
                TextField(L10n.string("Group name", table: "Board"), text: Binding(get: { document.board.groups.first { $0.id == group.id }?.title ?? "" }, set: { value in
                    document.change(L10n.string("Rename group", table: "Board")) { board in if let i = board.groups.firstIndex(where: { $0.id == group.id }) { board.groups[i].title = value } }
                })).textFieldStyle(.plain)
                Image(systemName: "hand.draw").gesture(moveGesture(group.id, group: true))
                    .help(L10n.string("Drag to move group and cards", table: "Board"))
                    .accessibilityLabel(L10n.string("Move group", table: "Board"))
            }.padding(12).background(Color.accentColor.opacity(0.08)).contentShape(Rectangle()).gesture(moveGesture(group.id, group: true))
            Spacer()
        }
        .frame(width: right - group.position.x, height: bottom - group.position.y)
        .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        .scaleEffect(document.board.zoom, anchor: .topLeading).offset(offset(group.position, id: group.id))
        .contextMenu { Button(L10n.string("Remove group", table: "Board")) { document.change(L10n.string("Remove group", table: "Board")) { board in
            board.groups.removeAll { $0.id == group.id }
            for i in board.cards.indices where board.cards[i].groupID == group.id { board.cards[i].groupID = nil }
        } } }
    }
    private func cardView(_ card: BoardCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(BoardPresentation.kindTitle(card.kind).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Spacer()
                Image(systemName: "hand.draw").foregroundStyle(.secondary)
                    .help(L10n.string("Move card", table: "Board"))
                    .accessibilityLabel(L10n.string("Move card", table: "Board"))
            }.foregroundStyle(card.kind == .note ? Color.orange : Color.accentColor)
                .contentShape(Rectangle()).highPriorityGesture(moveGesture(card.id))
            if card.kind == .note {
                TextField(L10n.string("Beat title", table: "Board"), text: binding(card, \.title)).font(.system(size: 18, weight: .medium, design: .serif)).textFieldStyle(.plain)
            } else { Text(card.title).font(.system(size: 18, weight: .medium, design: .serif)).lineLimit(3) }
            if card.kind == .draft {
                Text(sceneCount(card)).font(.caption).foregroundStyle(.secondary)
            } else if let draft = document.board.cards.first(where: { $0.id == card.draftID }) {
                Text(draft.title).font(.caption).foregroundStyle(.secondary)
            }
            if !card.sharedWith.isEmpty {
                Text(L10n.format("Shared with %@", card.sharedWith.map { id in document.board.cards.first { $0.id == id }?.title ?? L10n.string("missing draft", table: "Board") }.joined(separator: ", "), table: "Board")).font(.caption).foregroundStyle(.secondary)
            }
            if card.kind == .characters, let image = thumbnail(card) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 130)
            }
            if card.kind == .note || card.kind == .scene {
                TextField(L10n.string("Notes…", table: "Board"), text: binding(card, \.text), axis: .vertical).lineLimit(2...5).textFieldStyle(.plain).font(.callout)
            }
            if card.kind != .note {
                Text(linkStatus(card)).font(.caption).foregroundStyle(.secondary)
                Button(L10n.string("Open", table: "Board")) { document.open(card) }.buttonStyle(.borderless)
            }
        }
        .padding(18).frame(width: 220, alignment: .leading)
        .background(card.kind == .note ? Color(nsColor: .textBackgroundColor).opacity(0.95) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == card.id ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected == card.id ? 2 : 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .scaleEffect(document.board.zoom, anchor: .topLeading).offset(offset(card.position, id: card.id))
        .contextMenu { cardMenu(card) }
    }
    private func binding(_ card: BoardCard, _ key: WritableKeyPath<BoardCard, String>) -> Binding<String> {
        Binding(get: { document.board.cards.first { $0.id == card.id }?[keyPath: key] ?? "" }, set: { value in
            document.change(L10n.string("Edit card", table: "Board")) { board in if let i = board.cards.firstIndex(where: { $0.id == card.id }) { board.cards[i][keyPath: key] = value } }
        })
    }
    @ViewBuilder private func cardMenu(_ card: BoardCard) -> some View {
        if card.kind == .draft {
            Button(L10n.string("Add scenes…", table: "Board")) {
                do { scenes = FountainParser.parse(try document.source(for: card)).scenes; sceneDraft = card }
                catch { document.failure = error.localizedDescription }
            }
            Button(L10n.string("Link character sheets", table: "Board")) { document.addAsset(.characters, draft: card) }
            Button(L10n.string("Link shot list", table: "Board")) { document.addAsset(.shots, draft: card) }
            Button(L10n.string("Relink draft…", table: "Board")) { document.relink(card) }
        }
        if card.draftID != nil { Button(L10n.string("Relink original draft…", table: "Board")) { document.relinkOwner(card) } }
        if card.kind == .shots { Button(L10n.string("Relink shot list…", table: "Board")) { document.relink(card) } }
        if card.kind == .characters || card.kind == .shots {
            Menu(L10n.string("Share reference with draft", table: "Board")) {
                ForEach(document.board.cards.filter { $0.kind == .draft && $0.id != card.draftID }) { draft in
                    Button(L10n.format(card.sharedWith.contains(draft.id) ? "Unlink %@" : "Link %@", draft.title, table: "Board")) {
                        document.change(L10n.string("Share asset reference", table: "Board")) { board in
                            guard let i = board.cards.firstIndex(where: { $0.id == card.id }) else { return }
                            if board.cards[i].sharedWith.contains(draft.id) { board.cards[i].sharedWith.removeAll { $0 == draft.id } }
                            else { board.cards[i].sharedWith.append(draft.id) }
                        }
                    }
                }
            }
        }
        if card.kind == .scene {
            Button(L10n.string("Review current scene…", table: "Board")) { review(card) }
        }
        Menu(L10n.string("Group", table: "Board")) {
            Button(L10n.string("None", table: "Board")) { setGroup(card, nil) }
            ForEach(document.board.groups) { group in Button(group.title) { setGroup(card, group.id) } }
        }
        Divider()
        Button(L10n.string("Remove card", table: "Board")) { document.change(L10n.string("Remove card", table: "Board")) { $0.removeCard(card.id) } }
    }
    private func setGroup(_ card: BoardCard, _ id: UUID?) {
        document.change(L10n.string("Set group", table: "Board")) { board in
            guard let i = board.cards.firstIndex(where: { $0.id == card.id }) else { return }
            board.cards[i].groupID = id
            if let group = board.groups.first(where: { $0.id == id }) {
                let count = board.cards.filter { $0.groupID == id && $0.id != card.id }.count
                board.cards[i].position = BoardPoint(x: group.position.x + 20 + Double(count % 2) * 280, y: group.position.y + 60 + Double(count / 2) * 280)
            }
        }
    }
    private func sceneCount(_ card: BoardCard) -> String {
        _ = refresh
        guard let source = try? document.source(for: card) else { return L10n.string("Draft unavailable · Relink to restore", table: "Board") }
        return BoardPresentation.sceneCount(FountainParser.parse(source).scenes.count)
    }
    private func linkStatus(_ card: BoardCard) -> String {
        _ = refresh
        guard let source = try? document.source(for: card) else { return L10n.string("Missing draft · Relink original draft", table: "Board") }
        if card.kind == .shots {
            guard let path = card.path, (try? ShotListStore.read(from: URL(fileURLWithPath: path))) != nil else { return L10n.string("Missing or invalid shot list · Relink", table: "Board") }
        }
        if card.kind == .scene {
            switch document.board.sceneState(for: card, source: source) {
            case .current: return L10n.string("Scene linked", table: "Board")
            case .changed: return L10n.string("Changed scene · Review required", table: "Board")
            case .missing: return L10n.string("Missing scene · Review required", table: "Board")
            }
        }
        return card.sharedWith.isEmpty ? L10n.string("Linked reference", table: "Board") : BoardPresentation.sharedDraftCount(card.sharedWith.count)
    }
    private func review(_ card: BoardCard) {
        do {
            scenes = FountainParser.parse(try document.source(for: card)).scenes
            let alert = NSAlert(); alert.messageText = L10n.string("Review scene link", table: "Board")
            alert.informativeText = L10n.string("Accept the current text for this scene? Notes and position are preserved. Missing scenes require adding a new scene card.", table: "Board")
            alert.addButton(withTitle: L10n.string("Accept current scene", table: "Board")); alert.addButton(withTitle: L10n.string("Cancel", table: "Board"))
            guard let scene = scenes.first(where: { $0.id == card.anchor?.id }) else { document.failure = L10n.string("Scene is missing. Add its replacement explicitly from the draft outline.", table: "Board"); return }
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            document.change(L10n.string("Review scene", table: "Board")) { board in if let i = board.cards.firstIndex(where: { $0.id == card.id }) {
                board.cards[i].anchor = SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text); board.cards[i].title = scene.heading
            } }
        } catch { document.failure = error.localizedDescription }
    }
    private func thumbnail(_ card: BoardCard) -> NSImage? {
        _ = refresh
        guard let url = document.board.resolvedURL(for: card) else { return nil }
        if let draft = NSDocumentController.shared.document(for: url) as? FountainDocument,
           let character = draft.characterWorkspace.library.characters.first,
           let data = try? draft.characterWorkspace.imageData(for: character.activeVersion) { return NSImage(data: data) }
        let directory = CharacterLibraryStore.directory(for: url)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("characters.json")),
              let library = try? CharacterLibraryStore.decode(data),
              let version = library.characters.compactMap(\.activeVersion).first else { return nil }
        let imageURL = directory.appendingPathComponent(version.imageFile).resolvingSymlinksInPath()
        guard imageURL.path.hasPrefix(directory.resolvingSymlinksInPath().path + "/images/"),
              let size = try? imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 25_165_824,
              let bytes = try? Data(contentsOf: imageURL), let image = try? CharacterImageGenerator.validate(bytes) else { return nil }
        return NSImage(data: image.data)
    }
}

struct BoardNavigationSurface: NSViewRepresentable {
    var navigate: (BoardPoint, Double, BoardPoint) -> Void
    func makeNSView(context: Context) -> BoardNavigationView { let view = BoardNavigationView(); view.navigate = navigate; return view }
    func updateNSView(_ nsView: BoardNavigationView, context: Context) { nsView.navigate = navigate }
}
final class BoardNavigationView: NSView {
    var navigate: ((BoardPoint, Double, BoardPoint) -> Void)?
    override var isFlipped: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        navigate?(BoardPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY), 1, BoardPoint())
    }
    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        navigate?(BoardPoint(), max(0.1, 1 + event.magnification), BoardPoint(x: point.x, y: point.y))
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func mouseDragged(with event: NSEvent) { navigate?(BoardPoint(x: event.deltaX, y: event.deltaY), 1, BoardPoint()) }
}
