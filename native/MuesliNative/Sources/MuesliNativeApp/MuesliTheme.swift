import SwiftUI
import MuesliCore

/// Six friendly color themes. They deliberately change the accent rather than
/// forcing a dark background, so first-run setup and the default app remain
/// readable in light mode. Dark mode stays a separate, explicit preference.
enum MuesliColorTheme: String, CaseIterable, Identifiable {
    case clean
    case molokai
    case solarized
    case nord
    case dracula
    case forest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clean: return "Clean"
        case .molokai: return "Molokai"
        case .solarized: return "Solarized"
        case .nord: return "Nord"
        case .dracula: return "Dracula"
        case .forest: return "Forest"
        }
    }

    var hex: String {
        switch self {
        case .clean: return "2563eb"
        case .molokai: return "f92672"
        case .solarized: return "2aa198"
        case .nord: return "5e81ac"
        case .dracula: return "8b5cf6"
        case .forest: return "059669"
        }
    }

    static func resolved(for hex: String) -> Self {
        let normalized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        // `1e1e2e` is the legacy sentinel that means “use the default accent.”
        if normalized == "1e1e2e" { return .clean }
        return allCases.first(where: { $0.hex == normalized }) ?? .clean
    }
}

enum MuesliTheme {
    // MARK: - Colors — Backgrounds (layered)

    static let backgroundDeepDarkHex = 0x0B0C0E
    static let backgroundDeepLightHex = 0xF5F5F7
    static let backgroundDeep   = Color.adaptive(dark: backgroundDeepDarkHex, light: backgroundDeepLightHex)

    /// AppKit counterpart of `backgroundDeep`, for window chrome that cannot use SwiftUI colors.
    static let backgroundDeepNSColor = NSColor.adaptive(
        dark: backgroundDeepDarkHex,
        light: backgroundDeepLightHex
    )
    static let backgroundBase   = Color.adaptive(dark: 0x161719, light: 0xFFFFFF)
    static let backgroundRaised = Color.adaptive(dark: 0x1C1D20, light: 0xF1F3F7)
    static let backgroundHover  = Color.adaptive(dark: 0x232528, light: 0xE8E8EC)

    // MARK: - Surfaces (interactive elements)

    static let surfacePrimary   = Color.adaptive(dark: 0x262830, light: 0xF8F9FC)
    static let surfaceSelected  = Color.adaptive(dark: 0x2E3340, light: 0xEAF0FF)
    static let surfaceBorder    = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.07,
        light: .black, lightAlpha: 0.08
    )

    // MARK: - Text hierarchy

    static let textPrimary = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.92,
        light: .black, lightAlpha: 0.92
    )
    static let textSecondary = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.62,
        light: .black, lightAlpha: 0.68
    )
    static let textTertiary = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.40,
        light: .black, lightAlpha: 0.60
    )

    // MARK: - Accent

    static let defaultAccentDarkHex = 0x6BA3F7
    static let defaultAccentLightHex = 0x2563EB
    static let defaultAccent    = Color.adaptive(dark: defaultAccentDarkHex, light: defaultAccentLightHex)
    static var accentOverrideHex: String?
    static var accent: Color {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            return Color(hex: Int(val))
        }
        return defaultAccent
    }
    static var accentSubtle: Color { accent.opacity(0.15) }

    // MARK: - Semantic

    static let recording        = Color(hex: 0xEF4444)
    static let transcribing     = Color.adaptive(dark: 0xF59E0B, light: 0xA65308)
    static let success          = Color.adaptive(dark: 0x34D399, light: 0x15803D)

    // MARK: - Typography (SF Pro via .system())

    static func title1() -> Font { .system(size: 26, weight: .bold) }
    static func title2() -> Font { .system(size: 20, weight: .semibold) }
    static func title3() -> Font { .system(size: 18, weight: .semibold) }
    static func headline() -> Font { .system(size: 15, weight: .semibold) }
    static func body() -> Font { .system(size: 14, weight: .regular) }
    static func callout() -> Font { .system(size: 13, weight: .regular) }
    static func caption() -> Font { .system(size: 12, weight: .regular) }
    static func captionMedium() -> Font { .system(size: 12, weight: .medium) }

    // MARK: - Spacing (4pt grid)

    /// Top padding for page content and for the sidebar header, so a page's heading lines up
    /// with the app name in the sidebar.
    static let pageTop: CGFloat = 8

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner radii

    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
    static let cornerLarge: CGFloat = 14
    static let cornerXL: CGFloat = 20
}

// MARK: - Color Helpers

extension Color {
    init(hex: String) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") { normalized.removeFirst() }
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else {
            self = .black
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor.adaptive(dark: dark, light: light))
    }

    static func adaptiveAlpha(dark: NSColor, darkAlpha: CGFloat, light: NSColor, lightAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.withAlphaComponent(darkAlpha)
                : light.withAlphaComponent(lightAlpha)
        })
    }
}

extension NSColor {
    static func adaptive(dark: Int, light: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        }
    }
}

/// Page heading used by every dashboard page, so titles stay identical across tabs.
struct PageTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(MuesliTheme.title1())
            .foregroundStyle(MuesliTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
