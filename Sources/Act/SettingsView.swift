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
                    Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Close settings").accessibilityLabel("Close settings")
                }
            }.padding(.horizontal, 20).frame(height: 44)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Font")
                            Spacer(minLength: 12)
                            Picker("Font", selection: $preferences.settings.fontName) {
                                ForEach(fonts, id: \.self) { family in Text(family).tag(family) }
                            }.labelsHidden().frame(maxWidth: 180)
                        }
                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(preferences.settings.fontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                            Stepper("Font size", value: $preferences.settings.fontSize, in: 8...24, step: 1)
                                .labelsHidden().fixedSize().accessibilityLabel("Font size")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before sluglines")
                            Picker("Before sluglines", selection: $preferences.settings.blankLinesBeforeSlugline) {
                                Text("1 blank line").tag(1)
                                Text("2 blank lines").tag(2)
                            }.labelsHidden().pickerStyle(.segmented)
                        }
                        Toggle("Bold sluglines", isOn: $preferences.settings.boldSluglines)
                        Toggle("Automatic CONT'D", isOn: $preferences.settings.dialogueContinuations)
                    }.font(.system(size: 12)).controlSize(.small)
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Example").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        ScreenplayStyleExample(preferences: preferences)
                    }
                }.padding(20)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Read-only examples use the same font resolution and cue presentation as writing.
struct ScreenplayStyleExample: View {
    @ObservedObject var preferences: WritingPreferences
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A quiet morning")
                .font(.system(size: font.pointSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: SectionColours.forLevel(1)))
            Text("She sets down the cup.").padding(.top, lineHeight)
            Text("INT. KITCHEN - DAY")
                .font(Font(NSFontManager.shared.convert(font, toHaveTrait: settings.boldSluglines ? .boldFontMask : .unboldFontMask)))
                .padding(.top, CGFloat(settings.validated.blankLinesBeforeSlugline) * lineHeight)
            Text("MARA").padding(.leading, 44).padding(.top, lineHeight)
            Text("Stay for coffee.").padding(.leading, 20)
            Text("She waits.").padding(.top, lineHeight)
            Text(continuedCue).padding(.leading, 44).padding(.top, lineHeight)
            Text("Please.").padding(.leading, 20)
        }
        .font(Font(font)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live screenplay style example")
    }
}
