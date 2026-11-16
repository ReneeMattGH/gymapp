import SwiftUI

struct AvoidExerciseSheet: View {
    var exercises: [Exercise]
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var query = ""

    private var filtered: [Exercise] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return exercises }
        return exercises.filter { exercise in
            exercise.name.lowercased().contains(text)
                || exercise.primaryMuscles.contains { $0.label.lowercased().contains(text) }
        }
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            SheetHeading(
                title: "Exercises to skip",
                subtitle: "Your plan will not include these. You can change this at any time.",
                onClose: { dismiss() }
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            FormaTextField(placeholder: "Search exercises", text: $query, capitalization: .never)
                .padding(.horizontal, Spacing.xl)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { exercise in
                        row(exercise)
                    }
                    if filtered.isEmpty {
                        Text("No exercises match that search.")
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.vertical, Spacing.xxl)
                    }
                }
                .padding(.horizontal, Spacing.xl)
            }
            .scrollIndicators(.hidden)

            PrimaryButton(title: selected.isEmpty ? "Done" : "Done · \(selected.count) selected") {
                dismiss()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .background(FormaBackground())
    }

    private func row(_ exercise: Exercise) -> some View {
        let active = selected.contains(exercise.id)
        return Button {
            Haptics.selection()
            if active {
                selected.removeAll { $0 == exercise.id }
            } else {
                selected.append(exercise.id)
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: active ? "checkmark" : "")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.accentInk)
                    .frame(width: 22, height: 22)
                    .background(
                        active ? AnyShapeStyle(palette.accent) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderStrong, lineWidth: 1.4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(exercise.primaryMuscles.map(\.label).joined(separator: " · "))
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.border).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? "Selected" : "Not selected")
    }
}
