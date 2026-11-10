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
                Text("Project board").font(.headline)
                Spacer()
                Button("Link draft…") { document.chooseDraft() }
                Button("Note") { addNote() }
                Button("Group") { document.change("Add group") { $0.groups.append(BoardGroup(title: "Untitled group", position: document.insertionPoint)) } }
                Divider().frame(height: 18)
                Button("−") { zoom(by: 0.8) }.accessibilityLabel("Zoom out")
                Text("\(Int(document.board.zoom * 100))%").monospacedDigit().frame(width: 44)
                Button("+") { zoom(by: 1.25) }.accessibilityLabel("Zoom in")
                Button("Reset view") { document.change("Reset view") { $0.pan = BoardPoint(x: 80, y: 80); $0.zoom = 1 } }
            }.buttonStyle(.borderless).padding(18)
            Divider()
            if let failure = document.failure {
                HStack {
                    Text(failure).font(.callout).textSelection(.enabled)
                    Spacer()
                    if document.saveFailed {
                        Button("Save copy…") { document.saveAs(nil) }
                        Button("Reload…") { document.revertToSaved(nil) }
                    }
                    Button("Dismiss") { document.failure = nil }
                }.padding(12).background(Color.orange.opacity(0.15))
            }
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)
                    BoardNavigationSurface { delta, factor, point in
                        document.change("Navigate board") { board in
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
                            Text("Give your story room.").font(.system(size: 34, weight: .medium, design: .serif))
                            Text("Link a draft, collect beats, arrange your project.").foregroundStyle(.secondary)
                            Button("Link Fountain draft…") { document.chooseDraft() }
                        }.padding(60).allowsHitTesting(true)
                    }
                }.clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("Scroll to pan · Pinch to zoom · Drag card headers to arrange")
                        .font(.caption).foregroundStyle(.secondary).padding(12).allowsHitTesting(false)
                }
                .onReceive(timer) { _ in refresh += 1 }
            }
        }
        .sheet(item: $sceneDraft) { draft in
            VStack(alignment: .leading, spacing: 16) {
                Text("Add scenes from \(draft.title)").font(.headline)
                List(scenes) { scene in
                    Button(scene.heading) { document.addScene(scene, draft: draft) }
                }.frame(minWidth: 500, minHeight: 300)
                Button("Done") { sceneDraft = nil }.keyboardShortcut(.defaultAction)
            }.padding(24)
        }
    }
    private func zoom(by factor: Double) {
        document.change("Zoom board") { $0.zoom = min(2, max(0.25, $0.zoom * factor)) }
    }
    private func addNote() {
        document.change("Add note") { $0.cards.append(BoardCard(kind: .note, title: "Untitled beat", position: document.insertionPoint)) }
    }
    private func offset(_ point: BoardPoint, id: UUID) -> CGSize {
        CGSize(width: point.x * document.board.zoom + document.board.pan.x + (selected == id ? drag.width : 0),
               height: point.y * document.board.zoom + document.board.pan.y + (selected == id ? drag.height : 0))
    }
    private func moveGesture(_ id: UUID, group: Bool = false) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { value in selected = id; drag = value.translation }
            .onEnded { value in
                let delta = BoardPoint(x: value.translation.width / document.board.zoom, y: value.translation.height / document.board.zoom)
                document.change(group ? "Move group" : "Move card") {
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
                TextField("Group name", text: Binding(get: { document.board.groups.first { $0.id == group.id }?.title ?? "" }, set: { value in
                    document.change("Rename group") { board in if let i = board.groups.firstIndex(where: { $0.id == group.id }) { board.groups[i].title = value } }
                })).textFieldStyle(.plain)
                Image(systemName: "hand.draw").gesture(moveGesture(group.id, group: true)).help("Drag to move group and cards")
            }.padding(12).background(Color.accentColor.opacity(0.08)).contentShape(Rectangle()).gesture(moveGesture(group.id, group: true))
            Spacer()
        }
        .frame(width: right - group.position.x, height: bottom - group.position.y)
        .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        .scaleEffect(document.board.zoom, anchor: .topLeading).offset(offset(group.position, id: group.id))
        .contextMenu { Button("Remove group") { document.change("Remove group") { board in
            board.groups.removeAll { $0.id == group.id }
            for i in board.cards.indices where board.cards[i].groupID == group.id { board.cards[i].groupID = nil }
        } } }
    }
    private func cardView(_ card: BoardCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.kind.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Spacer()
                Image(systemName: "hand.draw").foregroundStyle(.secondary)
            }.foregroundStyle(card.kind == .note ? Color.orange : Color.accentColor)
                .contentShape(Rectangle()).highPriorityGesture(moveGesture(card.id))
            if card.kind == .note {
                TextField("Beat title", text: binding(card, \.title)).font(.system(size: 18, weight: .medium, design: .serif)).textFieldStyle(.plain)
            } else { Text(card.title).font(.system(size: 18, weight: .medium, design: .serif)).lineLimit(3) }
            if card.kind == .draft {
                Text(sceneCount(card)).font(.caption).foregroundStyle(.secondary)
            } else if let draft = document.board.cards.first(where: { $0.id == card.draftID }) {
                Text(draft.title).font(.caption).foregroundStyle(.secondary)
            }
            if !card.sharedWith.isEmpty {
                Text("Shared with " + card.sharedWith.map { id in document.board.cards.first { $0.id == id }?.title ?? "missing draft" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
            if card.kind == .characters, let image = thumbnail(card) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 130)
            }
            if card.kind == .note || card.kind == .scene {
                TextField("Notes…", text: binding(card, \.text), axis: .vertical).lineLimit(2...5).textFieldStyle(.plain).font(.callout)
            }
            if card.kind != .note {
                Text(linkStatus(card)).font(.caption).foregroundStyle(.secondary)
                Button("Open") { document.open(card) }.buttonStyle(.borderless)
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
            document.change("Edit card") { board in if let i = board.cards.firstIndex(where: { $0.id == card.id }) { board.cards[i][keyPath: key] = value } }
        })
    }
    @ViewBuilder private func cardMenu(_ card: BoardCard) -> some View {
        if card.kind == .draft {
            Button("Add scenes…") {
                do { scenes = FountainParser.parse(try document.source(for: card)).scenes; sceneDraft = card }
                catch { document.failure = error.localizedDescription }
            }
            Button("Link character sheets") { document.addAsset(.characters, draft: card) }
            Button("Link shot list") { document.addAsset(.shots, draft: card) }
            Button("Relink draft…") { document.relink(card) }
        }
        if card.draftID != nil { Button("Relink original draft…") { document.relinkOwner(card) } }
        if card.kind == .shots { Button("Relink shot list…") { document.relink(card) } }
        if card.kind == .characters || card.kind == .shots {
            Menu("Share reference with draft") {
                ForEach(document.board.cards.filter { $0.kind == .draft && $0.id != card.draftID }) { draft in
                    Button((card.sharedWith.contains(draft.id) ? "Unlink " : "Link ") + draft.title) {
                        document.change("Share asset reference") { board in
                            guard let i = board.cards.firstIndex(where: { $0.id == card.id }) else { return }
                            if board.cards[i].sharedWith.contains(draft.id) { board.cards[i].sharedWith.removeAll { $0 == draft.id } }
                            else { board.cards[i].sharedWith.append(draft.id) }
                        }
                    }
                }
            }
        }
        if card.kind == .scene {
            Button("Review current scene…") { review(card) }
        }
        Menu("Group") {
            Button("None") { setGroup(card, nil) }
            ForEach(document.board.groups) { group in Button(group.title) { setGroup(card, group.id) } }
        }
        Divider()
        Button("Remove card") { document.change("Remove card") { $0.removeCard(card.id) } }
    }
    private func setGroup(_ card: BoardCard, _ id: UUID?) {
        document.change("Set group") { board in
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
        guard let source = try? document.source(for: card) else { return "Draft unavailable · Relink to restore" }
        return "\(FountainParser.parse(source).scenes.count) scenes"
    }
    private func linkStatus(_ card: BoardCard) -> String {
        _ = refresh
        guard let source = try? document.source(for: card) else { return "Missing draft · Relink original draft" }
        if card.kind == .shots {
            guard let path = card.path, (try? ShotListStore.read(from: URL(fileURLWithPath: path))) != nil else { return "Missing or invalid shot list · Relink" }
        }
        if card.kind == .scene {
            switch document.board.sceneState(for: card, source: source) {
            case .current: return "Scene linked"
            case .changed: return "Changed scene · Review required"
            case .missing: return "Missing scene · Review required"
            }
        }
        return card.sharedWith.isEmpty ? "Linked reference" : "Shared reference · \(card.sharedWith.count) other drafts"
    }
    private func review(_ card: BoardCard) {
        do {
            scenes = FountainParser.parse(try document.source(for: card)).scenes
            let alert = NSAlert(); alert.messageText = "Review scene link"
            alert.informativeText = "Accept the current text for this scene? Notes and position are preserved. Missing scenes require adding a new scene card."
            alert.addButton(withTitle: "Accept current scene"); alert.addButton(withTitle: "Cancel")
            guard let scene = scenes.first(where: { $0.id == card.anchor?.id }) else { document.failure = "Scene is missing. Add its replacement explicitly from the draft outline."; return }
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            document.change("Review scene") { board in if let i = board.cards.firstIndex(where: { $0.id == card.id }) {
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
