import ActCore
import SwiftUI

/// Presentation state owned by a writing window, never by its document or preferences.
@MainActor
final class ScreenplayZoom: ObservableObject {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 2
    @Published private(set) var scale: CGFloat = 1

    var percentage: String {
        Double(scale).formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: L10n.language)))
    }

    func set(_ value: CGFloat) {
        guard value.isFinite else { return }
        let bounded = min(Self.maximum, max(Self.minimum, value))
        if scale != bounded { scale = bounded }
    }

    func step(_ direction: CGFloat) {
        set((scale * 100 + direction * 10).rounded() / 100)
    }
}

struct ScreenplayZoomControl: View {
    @ObservedObject var zoom: ScreenplayZoom
    @State private var showsControls = false

    var body: some View {
        Button { showsControls.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text(zoom.percentage).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        .accessibilityLabel(L10n.string("Screenplay zoom", table: "Writing"))
        .accessibilityValue(zoom.percentage)
        .help(L10n.string("Screenplay zoom", table: "Writing"))
        .popover(isPresented: $showsControls, arrowEdge: .top) {
            HStack(spacing: 12) {
                Button { zoom.step(-1) } label: { Image(systemName: "minus") }
                    .accessibilityLabel(L10n.string("Zoom out", table: "Writing"))
                    .disabled(zoom.scale <= ScreenplayZoom.minimum)
                Text(zoom.percentage).monospacedDigit().frame(minWidth: 45)
                    .accessibilityLabel(L10n.string("Screenplay zoom", table: "Writing"))
                Button { zoom.step(1) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L10n.string("Zoom in", table: "Writing"))
                    .disabled(zoom.scale >= ScreenplayZoom.maximum)
                Divider().frame(height: 18)
                Button(L10n.string("Reset to 100%", table: "Writing")) { zoom.set(1) }
            }
            .padding(14)
        }
    }
}
