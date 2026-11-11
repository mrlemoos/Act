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
                Text(L10n.string("Style", table: "Writing")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(L10n.string("Close settings", table: "Writing")).accessibilityLabel(L10n.string("Close settings", table: "Writing"))
                }
            }.padding(.horizontal, 20).frame(height: 44)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section(L10n.string("Typography", table: "Writing")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.string("Font", table: "Writing"))
                                Spacer(minLength: 12)
                                Picker(L10n.string("Font", table: "Writing"), selection: $preferences.settings.fontName) {
                                    ForEach(fonts, id: \.self) { family in Text(family).tag(family) }
                                }.labelsHidden().frame(maxWidth: 180)
                            }
                            preview(.font)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.string("Size", table: "Writing"))
                                Spacer()
                                Text("\(Int(preferences.settings.fontSize)) pt")
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Stepper(L10n.string("Font size", table: "Writing"), value: $preferences.settings.fontSize, in: 8...24, step: 1)
                                    .labelsHidden().fixedSize().accessibilityLabel(L10n.string("Font size", table: "Writing"))
                            }
                            preview(.size)
                        }
                    }
                    Divider()
                    section(L10n.string("Scene headings", table: "Writing")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.string("Space before heading", table: "Writing"))
                            Picker(L10n.string("Space before heading", table: "Writing"), selection: $preferences.settings.blankLinesBeforeSlugline) {
                                Text(L10n.string("1 blank line", table: "Writing")).tag(1)
                                Text(L10n.string("2 blank lines", table: "Writing")).tag(2)
                            }.labelsHidden().pickerStyle(.segmented)
                            preview(.spacing)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(L10n.string("Bold headings", table: "Writing"), isOn: $preferences.settings.boldSluglines)
                                .toggleStyle(.switch)
                            preview(.heading)
                        }
                    }
                    Divider()
                    section(L10n.string("Dialogue", table: "Writing")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(L10n.string("Automatic CONT'D", table: "Writing"), isOn: $preferences.settings.dialogueContinuations)
                                .toggleStyle(.switch)
                            Text(L10n.string("When the same speaker resumes after action.", table: "Writing"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            preview(.dialogue)
                        }
                    }
                    Text(L10n.string("Applies to all screenplays and PDF exports.", table: "Writing"))
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
                Text(L10n.string("The beginning of something.", table: "Writing"))
                Text("Aa Bb Cc 0123456789").foregroundStyle(.secondary).padding(.top, 6)
            case .size:
                Text(L10n.string("She sets down the cup.", table: "Writing"))
            case .spacing:
                Text(L10n.string("She steps outside.", table: "Writing")).foregroundStyle(.secondary)
                Text(L10n.string("EXT. STREET - DAY", table: "Writing")).font(headingFont)
                    .padding(.top, CGFloat(settings.validated.blankLinesBeforeSlugline) * lineHeight)
            case .heading:
                Text(L10n.string("INT. KITCHEN - DAY", table: "Writing")).font(headingFont)
            case .dialogue:
                dialogue
            case .full:
                Text(L10n.string("A quiet morning", table: "Writing"))
                    .font(.system(size: font.pointSize, weight: .semibold))
                    .foregroundStyle(Color(nsColor: SectionColours.forLevel(1)))
                Text(L10n.string("She sets down the cup.", table: "Writing")).padding(.top, lineHeight)
                Text(L10n.string("INT. KITCHEN - DAY", table: "Writing")).font(headingFont)
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
            Text(L10n.string("Stay for coffee.", table: "Writing")).padding(.leading, 20)
            Text(L10n.string("She waits.", table: "Writing")).padding(.top, lineHeight).foregroundStyle(.secondary)
            Text(continuedCue).padding(.leading, 44).padding(.top, lineHeight)
            Text(L10n.string("Please.", table: "Writing")).padding(.leading, 20)
        }
    }

    private var previewLabel: String {
        switch kind {
        case .full: L10n.string("Live screenplay style example", table: "Writing")
        case .font: L10n.string("Live font preview", table: "Writing")
        case .size: L10n.string("Live font size preview", table: "Writing")
        case .spacing: L10n.string("Live scene heading spacing preview", table: "Writing")
        case .heading: L10n.string("Live scene heading weight preview", table: "Writing")
        case .dialogue: L10n.string("Live dialogue continuation preview", table: "Writing")
        }
    }
}
