import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    @State private var query = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var selectedMuscle: MuscleGroup?
    @State private var onlyFavorites = false
    @State private var visibleCount = 30

    private var filters: ExerciseFilters {
        ExerciseFilters(
            query: query,
            category: selectedCategory,
            muscle: selectedMuscle,
            onlyFavorites: onlyFavorites,
            favoriteIDs: model.favoriteExercises
        )
    }

    private var page: ExercisePage {
        ExerciseService.search(model.exercises, filters: filters, limit: visibleCount)
    }

    private var filtered: [Exercise] { page.items }

    private var hasFilters: Bool {
        !query.isEmpty || onlyFavorites || selectedCategory != nil || selectedMuscle != nil
    }

    private var recent: [Exercise] {
        model.recentExercises.compactMap { model.exercise($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PageHeading(
                    eyebrow: "Library",
                    title: "Exercises",
                    subtitle: "\(model.exercises.count) verified movements with instructions, cues, and common mistakes."
                )
                if let notice = model.libraryNotice {
                    NoticeBanner(message: notice, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
                searchRow
                filterRow
                if !hasFilters && !recent.isEmpty {
                    recentSection
                }
                if filtered.isEmpty {
                    FormaEmptyState(
                        systemImage: "magnifyingglass",
                        title: favoritesOnlyActive ? "No favourites yet" : "No matches",
                        message: favoritesOnlyActive
                            ? "Tap the star on any exercise to keep it close."
                            : "Try a different search or clear the filters."
                    )
                    if hasFilters {
                        SecondaryButton(title: "Clear filters", systemImage: "xmark") {
                            clearFilters()
                        }
                    }
                } else {
                    VStack(spacing: Spacing.sm) {
                        ForEach(filtered) { exercise in
                            row(exercise)
                        }
                    }
                    if page.hasMore {
                        SecondaryButton(
                            title: "Show more (\(page.total - filtered.count) remaining)",
                            systemImage: "chevron.down"
                        ) {
                            visibleCount += 30
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: filters) { _, _ in
            visibleCount = 30
        }
        .background(FormaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var favoritesOnlyActive: Bool {
        onlyFavorites && query.isEmpty && selectedCategory == nil && selectedMuscle == nil
    }

    private var searchRow: some View {
        HStack(spacing: Spacing.sm) {
            FormaTextField(placeholder: "Search exercises", text: $query, capitalization: .never)
            Menu {
                Button("All muscles") { selectedMuscle = nil }
                Divider()
                ForEach(MuscleGroup.allCases) { muscle in
                    Button(muscle.label) { selectedMuscle = muscle }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: selectedMuscle == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(selectedMuscle?.label ?? "Muscle")
                        .font(FormaFont.bodyFont(8.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(selectedMuscle == nil ? palette.textSecondary : palette.accentText)
                .frame(width: 64, height: 48)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(selectedMuscle == nil ? palette.border : palette.accentBorder, lineWidth: 1)
                }
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                FormaChip(label: "All", selected: !onlyFavorites && selectedCategory == nil) {
                    onlyFavorites = false
                    selectedCategory = nil
                }
                ForEach(ExerciseCategory.allCases) { category in
                    FormaChip(label: category.label, selected: selectedCategory == category) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
                FormaChip(label: "Favourites", selected: onlyFavorites) {
                    onlyFavorites.toggle()
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Recently viewed")
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    ForEach(recent) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ExerciseGlyph(exercise: exercise, size: 36)
                                Text(exercise.name)
                                    .font(FormaFont.bodyFont(12, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Text(exercise.primaryMuscles.prefix(1).map(\.label).joined())
                                    .font(FormaFont.bodyFont(10))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .frame(width: 128, alignment: .leading)
                            .padding(Spacing.md)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        HStack(spacing: Spacing.sm) {
            NavigationLink {
                ExerciseDetailView(exercise: exercise)
            } label: {
                HStack(spacing: Spacing.md) {
                    ExerciseGlyph(exercise: exercise, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.leading)
                        Text(exercise.primaryMuscles.map(\.label).joined(separator: " · "))
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(exercise.category.label)
                                .font(FormaFont.bodyFont(9.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(palette.accentText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accentSoft, in: Capsule())
                            Text(exercise.difficulty.label)
                                .font(FormaFont.bodyFont(9.5, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.toggleFavorite(exercise.id)
            } label: {
                Image(systemName: model.favoriteExercises.contains(exercise.id) ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.favoriteExercises.contains(exercise.id) ? palette.accentText : palette.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(model.favoriteExercises.contains(exercise.id) ? "Remove favourite" : "Add favourite")
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func clearFilters() {
        query = ""
        onlyFavorites = false
        selectedCategory = nil
        selectedMuscle = nil
    }
}

// MARK: - Detail

struct ExerciseDetailView: View {
    let exercise: Exercise?
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header(exercise)
                    if !exercise.instructions.isEmpty {
                        numberedCard(title: "How to perform", items: exercise.instructions)
                    }
                    if !exercise.cues.isEmpty {
                        bulletCard(title: "Coaching cues", icon: "target", items: exercise.cues, tint: palette.accentText)
                    }
                    if !exercise.mistakes.isEmpty {
                        bulletCard(title: "Common mistakes", icon: "exclamationmark.triangle", items: exercise.mistakes, tint: palette.warning)
                    }
                    alternatives(exercise)
                    NoticeBanner(
                        message: "General guidance only. Stop if a movement causes pain, dizziness, or unusual shortness of breath. Persistent issues deserve a qualified professional.",
                        systemImage: "heart.text.square"
                    )
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            } else {
                FormaEmptyState(
                    systemImage: "questionmark.circle",
                    title: "Exercise unavailable",
                    message: "This movement is not in the current library. Refresh and try again."
                )
                .padding(.top, Spacing.xxxl)
            }
        }
        .scrollIndicators(.hidden)
        .background(FormaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let exercise {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.toggleFavorite(exercise.id)
                    } label: {
                        Image(systemName: model.favoriteExercises.contains(exercise.id) ? "star.fill" : "star")
                            .foregroundStyle(model.favoriteExercises.contains(exercise.id) ? palette.accentText : palette.textSecondary)
                    }
                    .accessibilityLabel(model.favoriteExercises.contains(exercise.id) ? "Remove favourite" : "Add favourite")
                }
            }
        }
        .onAppear {
            if let exercise { model.recordExerciseView(exercise.id) }
        }
    }

    private func header(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.lg) {
                ExerciseGlyph(exercise: exercise, size: 72)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(exercise.category.label.uppercased())
                        .font(FormaFont.bodyFont(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(palette.accentText)
                    Text(exercise.name)
                        .font(FormaFont.displayFont(28, weight: .bold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        TagLabel(text: exercise.difficulty.label, color: palette.textSecondary)
                        if exercise.isUnilateral {
                            TagLabel(text: "One side", color: palette.textTertiary)
                        }
                    }
                }
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(exercise.primaryMuscles, id: \.self) { muscle in
                    muscleChip(muscle.label, primary: true)
                }
                ForEach(exercise.secondaryMuscles, id: \.self) { muscle in
                    muscleChip(muscle.label, primary: false)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
                Text(exercise.equipment.isEmpty ? "No equipment listed" : exercise.equipment.map(\.label).joined(separator: " · "))
                    .font(FormaFont.bodyFont(11.5))
                    .foregroundStyle(palette.textSecondary)
            }
            if let source = exercise.source {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                    Text(source)
                        .font(FormaFont.bodyFont(10.5))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func muscleChip(_ label: String, primary: Bool) -> some View {
        Text(label)
            .font(FormaFont.bodyFont(10.5, weight: .medium))
            .foregroundStyle(primary ? palette.text : palette.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(primary ? palette.surfaceRaised : palette.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(primary ? Color.clear : palette.border, lineWidth: 1)
            }
    }

    private func numberedCard(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            cardTitle(title, icon: "list.number")
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Text("\(index + 1)")
                        .font(FormaFont.displayFont(11, weight: .semibold))
                        .foregroundStyle(palette.accentText)
                        .frame(width: 22, height: 22)
                        .background(palette.accentSoft, in: Circle())
                    Text(item)
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func bulletCard(title: String, icon: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            cardTitle(title, icon: icon)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Circle().fill(tint).frame(width: 4, height: 4).padding(.top, 6)
                    Text(item)
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            Text(title.uppercased())
                .font(FormaFont.bodyFont(10.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func alternatives(_ exercise: Exercise) -> some View {
        let options = exercise.alternatives.compactMap { model.exercise($0) }
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Alternatives")
                ForEach(options) { option in
                    NavigationLink {
                        ExerciseDetailView(exercise: option)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            ExerciseGlyph(exercise: option, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(FormaFont.bodyFont(13.5, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(option.equipment.map(\.label).joined(separator: " · "))
                                    .font(FormaFont.bodyFont(10.5))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .padding(Spacing.md)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
        }
    }
}
