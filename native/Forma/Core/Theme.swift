import SwiftUI
import UIKit

enum ThemeMode: String, CaseIterable, Identifiable, Codable {
    case dark, light, system

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }
    var icon: String {
        switch self {
        case .dark: "moon.stars"
        case .light: "sun.max"
        case .system: "circle.lefthalf.filled"
        }
    }
}

enum FormaFont {
    static let display = "SpaceGrotesk-SemiBold"
    static let displayMedium = "SpaceGrotesk-Medium"
    static let displayBold = "SpaceGrotesk-Bold"
    static let body = "Inter-Regular"
    static let bodyMedium = "Inter-Medium"
    static let bodySemibold = "Inter-SemiBold"

    static func displayFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = displayBold
        case .medium: name = displayMedium
        default: name = display
        }
        return .custom(name, size: size, relativeTo: textStyle(for: size))
    }

    static func bodyFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = bodySemibold
        case .medium: name = bodyMedium
        default: name = body
        }
        return .custom(name, size: size, relativeTo: textStyle(for: size))
    }

    /// Maps a point size onto a Dynamic Type style so custom fonts scale with
    /// the user's text-size setting instead of staying fixed.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle
        case 24..<30: .title
        case 20..<24: .title2
        case 18..<20: .title3
        case 15..<18: .headline
        case 13..<15: .body
        case 11.5..<13: .subheadline
        case 10..<11.5: .footnote
        default: .caption2
        }
    }
}

private extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark)
        })
    }

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light ? light : dark
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

struct FormaPalette {
    let background: Color
    let backgroundAlt: Color
    let surface: Color
    let surfaceRaised: Color
    let border: Color
    let borderStrong: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentInk: Color
    let accentText: Color
    let accentSoft: Color
    let accentBorder: Color
    let danger: Color
    let dangerSoft: Color
    let warning: Color
    let warningSoft: Color
    let info: Color
    let success: Color
    let input: Color

    static let lime: UInt32 = 0xC7FA4F
    static let ink: UInt32 = 0x070806

    static let shared = FormaPalette(
        background: .adaptive(light: 0xF3F4EC, dark: 0x070806),
        backgroundAlt: .adaptive(light: 0xEAEDE0, dark: 0x0A0C09),
        surface: .adaptive(light: 0xFFFFFF, dark: 0x10130E),
        surfaceRaised: .adaptive(light: 0xF7F8F1, dark: 0x171B14),
        border: .adaptive(
            light: UIColor(white: 0.06, alpha: 0.12),
            dark: UIColor(red: 232 / 255, green: 1, blue: 200 / 255, alpha: 0.08)
        ),
        borderStrong: .adaptive(
            light: UIColor(white: 0.06, alpha: 0.22),
            dark: UIColor(red: 232 / 255, green: 1, blue: 200 / 255, alpha: 0.16)
        ),
        text: .adaptive(light: 0x101408, dark: 0xF3F6EE),
        textSecondary: .adaptive(light: 0x575F4D, dark: 0xA9B2A0),
        textTertiary: .adaptive(light: 0x8A9280, dark: 0x6F7869),
        accent: Color(hex: lime),
        accentInk: .adaptive(light: 0x101408, dark: 0x0B0E06),
        accentText: .adaptive(light: 0x4F6E00, dark: 0xC7FA4F),
        accentSoft: .adaptive(
            light: UIColor(red: 96 / 255, green: 132 / 255, blue: 10 / 255, alpha: 0.10),
            dark: UIColor(red: 199 / 255, green: 250 / 255, blue: 79 / 255, alpha: 0.12)
        ),
        accentBorder: .adaptive(
            light: UIColor(red: 79 / 255, green: 110 / 255, blue: 0, alpha: 0.32),
            dark: UIColor(red: 199 / 255, green: 250 / 255, blue: 79 / 255, alpha: 0.36)
        ),
        danger: .adaptive(light: 0xBE4535, dark: 0xFF7A6B),
        dangerSoft: .adaptive(
            light: UIColor(red: 190 / 255, green: 69 / 255, blue: 53 / 255, alpha: 0.10),
            dark: UIColor(red: 1, green: 122 / 255, blue: 107 / 255, alpha: 0.12)
        ),
        warning: .adaptive(light: 0x946200, dark: 0xF2C46B),
        warningSoft: .adaptive(
            light: UIColor(red: 148 / 255, green: 98 / 255, blue: 0, alpha: 0.10),
            dark: UIColor(red: 242 / 255, green: 196 / 255, blue: 107 / 255, alpha: 0.12)
        ),
        info: .adaptive(light: 0x276C99, dark: 0x8DCBFF),
        success: .adaptive(light: 0x4F6E00, dark: 0xC7FA4F),
        input: .adaptive(light: 0xF2F4EC, dark: 0x12160F)
    )

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xD8FF76), Color(hex: 0xAEEB3E)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var screenGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundAlt],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 26
    static let xxl: CGFloat = 32
}

// MARK: - Brand mark

/// The Forma mark: an open arc with a crossbar and a dot, drawn in code so it
/// stays crisp at any size.
struct BrandMark: View {
    var size: CGFloat = 28
    var color: Color

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let lineWidth = canvasSize.width * 0.115
            let inset = lineWidth / 2 + canvasSize.width * 0.06
            let arcRect = rect.insetBy(dx: inset, dy: inset)

            var arc = Path()
            arc.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: min(arcRect.width, arcRect.height) / 2,
                startAngle: .degrees(38),
                endAngle: .degrees(342),
                clockwise: false
            )
            context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            var bar = Path()
            let barY = rect.midY + rect.height * 0.02
            bar.move(to: CGPoint(x: rect.width * 0.34, y: barY))
            bar.addLine(to: CGPoint(x: rect.width * 0.66, y: barY))
            context.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            let dotSize = canvasSize.width * 0.13
            let dot = Path(ellipseIn: CGRect(
                x: rect.width * 0.635,
                y: barY - dotSize / 2,
                width: dotSize,
                height: dotSize
            ))
            context.fill(dot, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var compact = false
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(spacing: Spacing.sm) {
            BrandMark(size: compact ? 22 : 28, color: palette.accentText)
            if !compact {
                Text("FORMA")
                    .font(FormaFont.displayFont(19, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(palette.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forma")
    }
}

// MARK: - Environment

private struct FormaPaletteKey: EnvironmentKey {
    typealias Value = FormaPalette
    static var defaultValue: FormaPalette { FormaPalette.shared }
}

extension EnvironmentValues {
    var formaPalette: FormaPalette {
        get { self[FormaPaletteKey.self] }
        set { self[FormaPaletteKey.self] = newValue }
    }
}
