import AppKit

@MainActor
enum SectionColours {
    private static let pink = adaptive(light: (0.69, 0.18, 0.44), dark: (0.96, 0.54, 0.73))
    private static let blue = adaptive(light: (0.14, 0.37, 0.68), dark: (0.51, 0.73, 0.96))
    private static let orange = adaptive(light: (0.64, 0.30, 0.07), dark: (0.97, 0.67, 0.40))

    static func forLevel(_ level: Int) -> NSColor {
        switch level {
        case ...1: pink
        case 2: blue
        default: orange
        }
    }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let colour = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: colour.0, green: colour.1, blue: colour.2, alpha: 1)
        }
    }
}
