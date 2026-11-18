import SwiftUI
import WidgetKit

struct WidgetPalette {
    let scheme: ColorScheme

    var background: Color { scheme == .dark ? Color(hex: 0x070806) : Color(hex: 0xF3F4EC) }
    var backgroundAlt: Color { scheme == .dark ? Color(hex: 0x0A0C09) : Color(hex: 0xEAEDE0) }
    var surface: Color { scheme == .dark ? Color(hex: 0x11150F) : Color(hex: 0xFFFFFF) }
    var surfaceRaised: Color { scheme == .dark ? Color(hex: 0x181D15) : Color(hex: 0xF6F8F0) }
    var border: Color { scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.09) }
    var text: Color { scheme == .dark ? Color(hex: 0xF3F6EE) : Color(hex: 0x101408) }
    var textSecondary: Color { scheme == .dark ? Color(hex: 0xA9B2A0) : Color(hex: 0x575F4D) }
    var textTertiary: Color { scheme == .dark ? Color(hex: 0x7B8573) : Color(hex: 0x8A9280) }
    var accent: Color { Color(hex: 0xC7FA4F) }
    var accentInk: Color { scheme == .dark ? Color(hex: 0x0B0E06) : Color(hex: 0x101408) }
    var accentText: Color { scheme == .dark ? Color(hex: 0xC7FA4F) : Color(hex: 0x4F6E00) }
    var track: Color { scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    var warning: Color { scheme == .dark ? Color(hex: 0xF2C46B) : Color(hex: 0x946200) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum WidgetText {
    static func narrowWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    static func shortWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func dayAndMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func minutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func remaining(_ week: WidgetWeekSummary) -> String {
        guard week.goal > 0 else { return "No weekly goal set" }
        if week.remaining == 0 { return "Weekly goal reached" }
        return "\(week.remaining) session\(week.remaining == 1 ? "" : "s") to go"
    }

    static func weekFraction(_ week: WidgetWeekSummary) -> String {
        guard week.goal > 0 else { return "No goal" }
        return "\(week.completed)/\(week.goal)"
    }
}

struct WidgetBrandMark: View {
    var size: CGFloat = 16
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

struct WidgetBackground: View {
    let palette: WidgetPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.background, palette.backgroundAlt],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [palette.accent.opacity(palette.scheme == .dark ? 0.10 : 0.07), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 150
            )
        }
    }
}

struct WidgetCard<Content: View>: View {
    let palette: WidgetPalette
    var raised: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(raised ? palette.surfaceRaised : palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }
}
