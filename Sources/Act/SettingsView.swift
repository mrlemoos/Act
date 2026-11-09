import ActCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: WritingPreferences
    var onClose: (() -> Void)? = nil

    private var fonts: [String] {
        Array(Set(NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") } + [preferences.settings.fontName])).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Style").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Close settings").accessibilityLabel("Close settings")
                }
            }.padding(.horizontal, 20).frame(height: 44)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Typography") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Font")
                                Spacer(minLength: 12)
                                Picker("Font", selection: $preferences.settings.fontName) {
                                    ForEach(fonts, id: \.self) { family in Text(family).tag(family) }
                                }.labelsHidden().frame(maxWidth: 180)
                            }
                            preview(.font)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Size")
                                Spacer()
                                Text("\(Int(preferences.settings.fontSize)) pt")
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Stepper("Font size", value: $preferences.settings.fontSize, in: 8...24, step: 1)
                                    .labelsHidden().fixedSize().accessibilityLabel("Font size")
                            }
                            preview(.size)
                        }
                    }
                    Divider()
                    section("Scene headings") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Space before heading")
                            Picker("Space before heading", selection: $preferences.settings.blankLinesBeforeSlugline) {
                                Text("1 blank line").tag(1)
                                Text("2 blank lines").tag(2)
                            }.labelsHidden().pickerStyle(.segmented)
                            preview(.spacing)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Bold headings", isOn: $preferences.settings.boldSluglines)
                                .toggleStyle(.switch)
                            preview(.heading)
                        }
                    }
                    Divider()
                    section("Dialogue") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Automatic CONT'D", isOn: $preferences.settings.dialogueContinuations)
                                .toggleStyle(.switch)
                            Text("When the same speaker resumes after action.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            preview(.dialogue)
                        }
                    }
                    Text("Applies to all screenplays and PDF exports.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12)).controlSize(.small).padding(20)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func preview(_ kind: ScreenplayStyleExample.Kind) -> some View {
        ScreenplayStyleExample(preferences: preferences, kind: kind)
    }

}

/// Read-only examples use the same font resolution and cue presentation as writing.
struct ScreenplayStyleExample: View {
    enum Kind { case full, font, size, spacing, heading, dialogue }

    @ObservedObject var preferences: WritingPreferences
    var kind: Kind = .full
    private var settings: ScreenplaySettings { preferences.settings }

    private var font: NSFont {
        let preference = settings.validated
        let size = preference.fontSize * 4 / 3
        return NSFontManager.shared.font(withFamily: preference.fontName, traits: [], weight: 5, size: size)
            ?? NSFont(name: preference.fontName, size: size)
            ?? NSFont(name: "Courier", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private var lineHeight: CGFloat { NSLayoutManager().defaultLineHeight(for: font) + 3 }
    private var continuedCue: String {
        let screenplay = FountainParser.parse("INT. KITCHEN - DAY\n\nMARA\nStay for coffee.\n\nShe waits.\n\nMARA\nPlease.")
        guard let cue = screenplay.elements.last(where: { $0.kind == .character }) else { return "MARA" }
        return ScreenplayPresentation.characterCues(in: screenplay, settings: settings)[cue.range.location] ?? "MARA"
    }

    private var headingFont: Font {
        Font(NSFontManager.shared.convert(font, toHaveTrait: settings.boldSluglines ? .boldFontMask : .unboldFontMask))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch kind {
            case .font:
                Text("The beginning of something.")
                Text("Aa Bb Cc 0123456789").foregroundStyle(.secondary).padding(.top, 6)
            case .size:
                Text("She sets down the cup.")
            case .spacing:
                Text("She steps outside.").foregroundStyle(.secondary)
                Text("EXT. STREET - DAY").font(headingFont)
                    .padding(.top, CGFloat(settings.validated.blankLinesBeforeSlugline) * lineHeight)
            case .heading:
                Text("INT. KITCHEN - DAY").font(headingFont)
            case .dialogue:
                dialogue
            case .full:
                Text("A quiet morning")
                    .font(.system(size: font.pointSize, weight: .semibold))
                    .foregroundStyle(Color(nsColor: SectionColours.forLevel(1)))
                Text("She sets down the cup.").padding(.top, lineHeight)
                Text("INT. KITCHEN - DAY").font(headingFont)
                    .padding(.top, CGFloat(settings.validated.blankLinesBeforeSlugline) * lineHeight)
                dialogue.padding(.top, lineHeight)
            }
        }
        .font(Font(font)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(previewLabel)
    }

    private var dialogue: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MARA").padding(.leading, 44)
            Text("Stay for coffee.").padding(.leading, 20)
            Text("She waits.").padding(.top, lineHeight).foregroundStyle(.secondary)
            Text(continuedCue).padding(.leading, 44).padding(.top, lineHeight)
            Text("Please.").padding(.leading, 20)
        }
    }

    private var previewLabel: String {
        switch kind {
        case .full: "Live screenplay style example"
        case .font: "Live font preview"
        case .size: "Live font size preview"
        case .spacing: "Live scene heading spacing preview"
        case .heading: "Live scene heading weight preview"
        case .dialogue: "Live dialogue continuation preview"
        }
    }
}
