import AppKit
import SwiftUI

// MARK: Text size
//
// macOS doesn't scale SwiftUI Mac apps with the system text size, so WK Console
// has its own setting (View ▸ Make Text Bigger / Smaller, and in Settings).
// Every font in the app goes through `appFont` so it follows the setting.

enum TextScale {
    static let key = "TextScale"
    static let levels: [Double] = [1.0, 1.15, 1.3, 1.5, 1.75]
    static let names = ["Standard", "Large", "Larger", "Extra large", "Largest"]

    static func step(_ current: Double, by delta: Int) -> Double {
        let i = levels.firstIndex { $0 >= current - 0.001 } ?? 0
        return levels[min(max(i + delta, 0), levels.count - 1)]
    }
}

/// Base sizes at the standard text size. Nothing is smaller than 12 pt.
enum AppText {
    case small, body, heading, title, transcript, speed, icon

    var size: CGFloat {
        switch self {
        case .small: 12
        case .body: 13
        case .heading: 15
        case .title: 19
        case .transcript: 17
        case .speed: 64
        case .icon: 40
        }
    }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var textScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct AppFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let text: AppText
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: text.size * scale, weight: weight, design: design))
    }
}

extension View {
    func appFont(_ text: AppText, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFont(text: text, weight: weight, design: design))
    }
}

/// Applied at the root of each window: sets the scale, the default font for
/// controls and form rows, and larger controls at the bigger sizes.
struct TextScaling: ViewModifier {
    @AppStorage(TextScale.key) private var scale = 1.0

    func body(content: Content) -> some View {
        content
            .environment(\.textScale, scale)
            .font(.system(size: AppText.body.size * scale))
            .controlSize(scale >= 1.3 ? .large : .regular)
    }
}

struct TextSizeCommands: Commands {
    @AppStorage(TextScale.key) private var scale = 1.0

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Make Text Bigger") { scale = TextScale.step(scale, by: 1) }
                .keyboardShortcut("+")
                .disabled(scale >= TextScale.levels.last!)
            Button("Make Text Smaller") { scale = TextScale.step(scale, by: -1) }
                .keyboardShortcut("-")
                .disabled(scale <= TextScale.levels.first!)
            Button("Actual Size") { scale = 1.0 }
                .keyboardShortcut("0")
                .disabled(scale == 1.0)
            Divider()
        }
    }
}

// MARK: Colours
//
// The system green and orange are too light for text on a light background
// (about 2.5:1). These keep the system colours in dark mode, where they're
// readable, and use darker shades in light mode (at least 4.5:1 on white).

enum Palette {
    static let warning = adaptive(light: NSColor(red: 0.54, green: 0.29, blue: 0.0, alpha: 1), dark: .systemOrange)
    static let success = adaptive(light: NSColor(red: 0.10, green: 0.42, blue: 0.18, alpha: 1), dark: .systemGreen)
    static let danger = adaptive(light: NSColor(red: 0.70, green: 0.13, blue: 0.10, alpha: 1), dark: .systemRed)
    /// Supporting text. The system secondary grey is only 3.9:1 on a light window.
    static let secondaryText = adaptive(light: NSColor(white: 0.36, alpha: 1), dark: .secondaryLabelColor)
    /// Accent-coloured text (paddle sending, the message being sent).
    static let accentText = adaptive(light: NSColor(red: 0.0, green: 0.33, blue: 0.70, alpha: 1),
                                     dark: NSColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 1))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        })
    }
}

/// A warning or error line: icon plus text, so it doesn't rely on colour.
struct NoticeText: View {
    enum Kind { case warning, error }
    let text: String
    var kind: Kind = .warning

    init(_ text: String, kind: Kind = .warning) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        Label(text, systemImage: kind == .error ? "xmark.octagon" : "exclamationmark.triangle")
            .appFont(.small)
            .foregroundStyle(kind == .error ? Palette.danger : Palette.warning)
    }
}

// MARK: VoiceOver

enum VoiceOver {
    static var isRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }

    static func announce(_ text: String) {
        guard isRunning else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
