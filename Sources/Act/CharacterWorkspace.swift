import ActCore
import AppKit
import SwiftUI

enum CharacterColours {
    static func colour(_ index: Int) -> NSColor {
        let hue = (0.07 + Double(index) * 0.618033988749895).truncatingRemainder(dividingBy: 1)
        return NSColor(name: NSColor.Name("ActCharacter\(index)")) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedHue: hue, saturation: dark ? 0.56 : 0.75, brightness: dark ? 0.95 : 0.66, alpha: 1)
        }
    }
}

struct CharacterWorkspace: View {
    @ObservedObject var document: FountainDocument
    @ObservedObject private var model: CharacterWorkspaceModel
    @State private var showingTools = false
    init(document: FountainDocument) { self.document = document; model = document.characterWorkspace }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Characters").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showingTools = true } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).help("Character tools").accessibilityLabel("Character tools")
                }.padding(20)
                if model.library.characters.isEmpty {
                    Text("Select a name in an action paragraph. Right-click to mark a character.")
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.library.characters) { character in
                            Button { model.selectedID = character.id } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(nsColor: CharacterColours.colour(character.colourIndex))).frame(width: 8, height: 8)
                                    Text(character.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Spacer()
                                    if character.needsReview { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help("Action text changed") }
                                }.padding(.horizontal, 12).padding(.vertical, 12)
                                    .background(model.selectedID == character.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 8)
                }
            }.frame(width: 220).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if let character = model.selectedCharacter { detail(character) }
            else {
                VStack(spacing: 12) {
                    Text("A face for the character.").font(.system(size: 22, weight: .medium, design: .serif))
                    Text("Mark a name in your screenplay to start a reference sheet.").foregroundStyle(.secondary)
                    Button("Character tools…") { showingTools = true }.padding(.top, 8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showingTools) { tools }
        .alert("Character sheets", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { model.prepare(screenplayURL: document.fileURL, source: document.source) }
    }

    private func detail(_ character: CharacterReference) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(character.name).font(.system(size: 26, weight: .medium, design: .serif))
                        .foregroundStyle(Color(nsColor: CharacterColours.colour(character.colourIndex)))
                    Spacer()
                    if model.isBusy {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.cancel() }
                    } else {
                        Button("Extract physical details") { model.extract(id: character.id) }
                            .disabled(character.marks.contains(where: \.isDetached))
                    }
                }
                if character.needsReview {
                    Label("Action text changed. Review the marked paragraphs and re-extract when ready.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if !character.contradictions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Conflicting physical details").font(.callout).fontWeight(.medium)
                        ForEach(character.contradictions, id: \.self) { Text($0).font(.callout) }
                        Text("Resolve these choices in your prompt before generating.").font(.caption)
                    }.foregroundStyle(.orange)
                }
                DisclosureGroup("Marked action paragraphs · \(character.marks.count)") {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(character.marks) { mark in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(mark.paragraph).font(.custom("Courier", size: 13)).textSelection(.enabled)
                                if mark.isDetached { Text("Name no longer linked. Mark it again in the screenplay, then remove this occurrence.").foregroundStyle(.orange) }
                                ForEach(Array(mark.traits.enumerated()), id: \.offset) { _, trait in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(trait.attribute): \(trait.value)").font(.callout)
                                        Text("Source: \(trait.evidence)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if mark.extractedParagraph != nil && mark.traits.isEmpty {
                                    Text("No explicit physical details found.").font(.caption).foregroundStyle(.secondary)
                                }
                                Button("Remove occurrence") { removeMark(mark.id, character: character.id) }
                                    .font(.caption).disabled(model.isBusy)
                            }
                        }
                    }.padding(.top, 12)
                }.font(.callout)
                if let version = character.activeVersion, let data = try? model.imageData(for: version), let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 500)
                        .accessibilityLabel("Active reference sheet for \(character.name)")
                    HStack {
                        Picker("Version", selection: Binding(get: { character.activeVersionID }, set: { id in
                            if let index = model.library.characters.firstIndex(where: { $0.id == character.id }) { model.library.characters[index].activeVersionID = id }
                        })) {
                            ForEach(Array(character.versions.enumerated()), id: \.element.id) { index, version in
                                Text("\(index + 1) · \(version.agent.capitalized) · \(version.createdAt.formatted(date: .abbreviated, time: .shortened))").tag(Optional(version.id))
                            }
                        }
                        Button("Reveal image") {
                            if let directory = model.directory { NSWorkspace.shared.activateFileViewerSelecting([directory.appendingPathComponent(version.imageFile)]) }
                        }
                    }
                    DisclosureGroup("Prompt used for this version") { Text(version.prompt).font(.callout).textSelection(.enabled).padding(.top, 8) }
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Model sheet prompt").font(.callout).fontWeight(.medium)
                        Spacer()
                        Button("Use extracted details") { model.useExtractedDetails(id: character.id) }.font(.caption).disabled(model.isBusy)
                    }
                    TextEditor(text: Binding(get: { model.library.characters.first { $0.id == character.id }?.prompt ?? "" },
                                             set: { model.updatePrompt($0, id: character.id) }))
                        .font(.system(size: 14)).scrollContentBackground(.hidden)
                        .padding(10).frame(minHeight: 200)
                        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.12)))
                        .accessibilityLabel("Model sheet prompt")
                    Text("Edit appearance or describe a change. Generation starts only when you choose it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if model.availableAgents.isEmpty {
                        Button("Connect an image agent…") { showingTools = true }
                    } else {
                        Picker("Agent", selection: $model.selectedAgent) {
                            ForEach(model.availableAgents, id: \.agent) { Text($0.agent.title).tag(Optional($0.agent)) }
                        }.frame(maxWidth: 220)
                    }
                    Spacer()
                    if character.activeVersion != nil {
                        Button("Iterate on active sheet") { model.generate(id: character.id, iterate: true) }
                            .disabled(model.isBusy || model.selectedConnection?.canEdit != true || character.prompt.isEmpty)
                            .help(model.selectedConnection?.canEdit == true ? "Send the active image with this prompt" : "Verify reference-image editing in Character Tools first")
                    }
                    Button("Generate new sheet") { model.generate(id: character.id, iterate: false) }
                        .disabled(model.isBusy || model.selectedConnection == nil || character.prompt.isEmpty)
                }
                if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }.padding(32).frame(maxWidth: 880).frame(maxWidth: .infinity)
        }
    }

    private func removeMark(_ id: UUID, character: UUID) {
        guard let index = model.library.characters.firstIndex(where: { $0.id == character }) else { return }
        model.library.characters[index].marks.removeAll { $0.id == id }
        model.save()
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Character tools").font(.title2).fontWeight(.semibold)
            Text("Physical details stay on your Mac. Image agents receive only prompts and reference images you approve.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("Local MLX extraction").font(.headline)
                HStack { Text(model.mlxExecutable?.lastPathComponent ?? "MLX runtime not configured").lineLimit(1); Spacer(); Button("Choose runtime…") { model.chooseMLX(model: false) } }
                HStack { Text(model.mlxModel?.lastPathComponent ?? "Downloaded MLX model not selected").lineLimit(1); Spacer(); Button("Choose model…") { model.chooseMLX(model: true) } }
                Text("Install mlx-lm separately and choose an existing MLX model folder. No model download or cloud fallback happens during extraction.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("uv tool install mlx-lm").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Divider()
            Text("Image agents").font(.headline)
            Text("Sign in and configure image tools in your terminal. Each test generates an image and may incur charges. Only agents that pass appear in the generation picker.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(CharacterImageAgent.allCases) { agent in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(agent.title).fontWeight(.medium)
                        Spacer()
                        Button("Choose…") { model.chooseAgent(agent) }
                        Button("Test generation") { model.verify(agent, editing: false) }
                        Button("Test editing") { model.verify(agent, editing: true) }.disabled(model.connection(for: agent)?.canGenerate != true)
                    }
                    let connection = model.connection(for: agent)
                    Text(connection?.canEdit == true ? "Generation and reference editing verified" : connection?.canGenerate == true ? "Generation verified · reference editing disabled" : "Not verified")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(model.isBusy)
            if model.isBusy { HStack { ProgressView().controlSize(.small); Text(model.status).font(.caption); Spacer(); Button("Cancel") { model.cancel() } } }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Spacer(); Button("Done") { showingTools = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 640)
    }
}
