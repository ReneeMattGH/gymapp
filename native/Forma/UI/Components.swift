import SwiftUI

// MARK: - Backgrounds

struct FormaBackground: View {
    @Environment(\.formaPalette) private var palette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.background, palette.backgroundAlt],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(palette.accent.opacity(0.07))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 140, y: -300)
            Circle()
                .fill(palette.accent.opacity(0.035))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: -180, y: 420)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

struct FormaCard<Content: View>: View {
    enum Style {
        case standard, raised, accent
    }

    var style: Style = .standard
    var padding: CGFloat = Spacing.lg
    @ViewBuilder var content: Content
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(style == .accent ? palette.accentSoft : (style == .raised ? palette.surfaceRaised : palette.surface))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(style == .accent ? palette.accentBorder : palette.border, lineWidth: 1)
        }
    }
}

struct SectionHeader: View {
    var title: String
    var action: (label: String, action: () -> Void)?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(FormaFont.bodyFont(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            if let action {
                Button(action.label, action: action.action)
                    .font(FormaFont.bodyFont(13, weight: .medium))
                    .foregroundStyle(palette.accentText)
            }
        }
    }
}

struct Overline: View {
    var text: String
    @Environment(\.formaPalette) private var palette

    var body: some View {
        Text(text.uppercased())
            .font(FormaFont.bodyFont(11, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(palette.accentText)
    }
}

struct PageHeading: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let eyebrow {
                Overline(text: eyebrow)
            }
            Text(title)
                .font(FormaFont.displayFont(30, weight: .bold))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(FormaFont.bodyFont(14))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var isLoading = false
    var isDisabled = false
    var action: () -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(palette.accentInk)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(FormaFont.bodyFont(15, weight: .semibold))
            }
            .foregroundStyle(palette.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(palette.accentGradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct SecondaryButton: View {
    var title: String
    var systemImage: String?
    var isDisabled = false
    var destructive = false
    var action: () -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(FormaFont.bodyFont(14, weight: .medium))
            }
            .foregroundStyle(destructive ? palette.danger : palette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(destructive ? palette.danger.opacity(0.3) : palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct IconButton: View {
    var systemImage: String
    var label: String
    var accent = false
    var action: () -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent ? palette.accentInk : palette.text)
                .frame(width: 38, height: 38)
                .background(
                    accent ? AnyShapeStyle(palette.accentGradient) : AnyShapeStyle(palette.surface),
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(accent ? Color.clear : palette.border, lineWidth: 1)
                }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(label)
    }
}

struct TextButton: View {
    var title: String
    var destructive = false
    var action: () -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FormaFont.bodyFont(13, weight: .medium))
                .foregroundStyle(destructive ? palette.danger : palette.accentText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips

struct FormaChip: View {
    var label: String
    var selected = false
    var disabled = false
    var action: () -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(FormaFont.bodyFont(13, weight: .medium))
                .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 9)
                .background(
                    selected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surface),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(selected ? Color.clear : palette.border, lineWidth: 1)
                }
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.85 : 1)
    }
}

struct TagLabel: View {
    var text: String
    var color: Color?
    @Environment(\.formaPalette) private var palette

    var body: some View {
        Text(text.uppercased())
            .font(FormaFont.bodyFont(10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color ?? palette.accentText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((color ?? palette.accentText).opacity(0.12), in: Capsule())
    }
}

// MARK: - Inputs

struct FormaTextField: View {
    var label: String?
    var placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var contentType: UITextContentType?
    var suffix: String?

    @Environment(\.formaPalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(FormaFont.bodyFont(12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: Spacing.sm) {
                Group {
                    if secure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(FormaFont.bodyFont(15))
                .foregroundStyle(palette.text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .textContentType(contentType)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .focused($focused)

                if let suffix {
                    Text(suffix)
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 48)
            .background(palette.input, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(focused ? palette.accentBorder : palette.border, lineWidth: 1)
            }
        }
    }
}

struct FormaTextEditor: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    @Environment(\.formaPalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FormaFont.bodyFont(12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(FormaFont.bodyFont(14))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $text)
                    .font(FormaFont.bodyFont(14))
                    .foregroundStyle(palette.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Spacing.sm + 2)
                    .padding(.vertical, 6)
                    .focused($focused)
                    .frame(minHeight: minHeight)
            }
            .background(palette.input, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(focused ? palette.accentBorder : palette.border, lineWidth: 1)
            }
        }
    }
}

struct StepperControl: View {
    var value: Int
    var range: ClosedRange<Int>
    var suffix: String?
    var onChange: (Int) -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(spacing: Spacing.lg) {
            stepperButton("minus") {
                onChange(max(range.lowerBound, value - 1))
            }
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(FormaFont.displayFont(22, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .contentTransition(.numericText())
                if let suffix {
                    Text(suffix)
                        .font(FormaFont.bodyFont(10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(minWidth: 56)
            stepperButton("plus") {
                onChange(min(range.upperBound, value + 1))
            }
        }
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.15)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 40, height: 40)
                .background(palette.surfaceRaised, in: Circle())
                .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
        }
        .buttonStyle(PressableScaleStyle())
    }
}

// MARK: - Feedback

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(palette.danger)
            Text(message)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("Retry", action: retry)
                    .font(FormaFont.bodyFont(12, weight: .semibold))
                    .foregroundStyle(palette.accentText)
            }
        }
        .padding(Spacing.md)
        .background(palette.dangerSoft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.danger.opacity(0.22), lineWidth: 1)
        }
    }
}

struct NoticeBanner: View {
    var message: String
    var systemImage = "info.circle"
    var accent = false

    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(accent ? palette.accentText : palette.textSecondary)
            Text(message)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(accent ? palette.accentSoft : palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(accent ? palette.accentBorder : palette.border, lineWidth: 1)
        }
    }
}

struct FormaEmptyState: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(palette.accentText)
                .frame(width: 58, height: 58)
                .background(palette.accentSoft, in: Circle())
            Text(title)
                .font(FormaFont.displayFont(19, weight: .semibold))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(FormaFont.bodyFont(13, weight: .semibold))
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 10)
                    .background(palette.accent, in: Capsule())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
        .padding(.horizontal, Spacing.lg)
    }
}

struct LoadingCard: View {
    var label = "Loading"
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(spacing: Spacing.md) {
            ProgressView().tint(palette.accentText)
            Text(label)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }
}

// MARK: - Data display

struct StatTile: View {
    var value: String
    var label: String
    var detail: String?
    var accent = false

    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(FormaFont.displayFont(24, weight: .bold))
                .foregroundStyle(accent ? palette.accentText : palette.text)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(FormaFont.bodyFont(10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(palette.textTertiary)
            if let detail {
                Text(detail)
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(accent ? palette.accentBorder : palette.border, lineWidth: 1)
        }
    }
}

struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 92
    var lineWidth: CGFloat = 9
    var label: String?
    var caption: String?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(
                        colors: [Color(hex: 0xD8FF76), Color(hex: 0xAEEB3E)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: progress)
            VStack(spacing: 1) {
                if let label {
                    Text(label)
                        .font(FormaFont.displayFont(size * 0.22, weight: .bold))
                        .foregroundStyle(palette.text)
                        .contentTransition(.numericText())
                }
                if let caption {
                    Text(caption.uppercased())
                        .font(FormaFont.bodyFont(8, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label ?? "Progress"), \(caption ?? "")")
    }
}

struct SetDots: View {
    var total: Int
    var completed: Int

    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < completed ? palette.accent : palette.surfaceRaised)
                    .frame(width: index < completed ? 18 : 10, height: 6)
                    .overlay {
                        if index >= completed {
                            Capsule().strokeBorder(palette.border, lineWidth: 1)
                        }
                    }
            }
        }
        .animation(.snappy(duration: 0.25), value: completed)
    }
}

struct KeyValueRow: View {
    var label: String
    var value: String
    var valueColor: Color?
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack {
            Text(label)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(FormaFont.bodyFont(13, weight: .medium))
                .foregroundStyle(valueColor ?? palette.text)
        }
    }
}

struct FormaDivider: View {
    @Environment(\.formaPalette) private var palette
    var body: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }
}

// MARK: - Layout

/// Wraps chips onto multiple rows without relying on a scroll view.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0 && lineWidth + spacing + size.width > maxWidth {
                width = max(width, lineWidth)
                height += lineHeight + lineSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += lineWidth > 0 ? spacing + size.width : size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        width = max(width, lineWidth)
        height += lineHeight
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - View modifiers

extension View {
    func formaScreen() -> some View {
        self.background(FormaBackground())
    }

    func formaScroll() -> some View {
        scrollContentBackground(.hidden)
            .background(FormaBackground())
    }

    func formaNavBar() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }
}

// MARK: - Sheet chrome

struct SheetHeading: View {
    var title: String
    var subtitle: String?
    var onClose: (() -> Void)?
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FormaFont.displayFont(22, weight: .bold))
                    .foregroundStyle(palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(palette.surfaceRaised, in: Circle())
                }
                .accessibilityLabel("Close")
            }
        }
    }
}

// MARK: - Exercise presentation

struct MuscleTags: View {
    var exercise: Exercise
    var limit = 3
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(exercise.primaryMuscles.prefix(limit), id: \.self) { muscle in
                Text(muscle.label)
                    .font(FormaFont.bodyFont(10, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette.surfaceRaised, in: Capsule())
            }
            if exercise.primaryMuscles.count > limit {
                Text("+\(exercise.primaryMuscles.count - limit)")
                    .font(FormaFont.bodyFont(10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

struct ExerciseGlyph: View {
    var exercise: Exercise
    var size: CGFloat = 44

    @Environment(\.formaPalette) private var palette

    private var symbol: String {
        switch exercise.category {
        case .mobility:
            return "figure.flexibility"
        case .conditioning:
            return "figure.run"
        case .strength:
            if exercise.primaryMuscles.contains(.back) || exercise.primaryMuscles.contains(.arms) {
                return "figure.strengthtraining.functional"
            }
            return "figure.strengthtraining.traditional"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(palette.accentText)
            .frame(width: size, height: size)
            .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
