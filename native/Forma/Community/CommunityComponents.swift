import SwiftUI

enum CommunityTime {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func short(_ date: Date?) -> String {
        guard let date else { return "" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func messageStamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Formatters.time(date)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday \(Formatters.time(date))"
        }
        return Formatters.shortDate(date)
    }
}

struct CommunityAvatar: View {
    var name: String
    var urlString: String?
    var size: CGFloat = 44
    @Environment(\.formaPalette) private var palette

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
    }

    private var fallback: some View {
        Text(initials)
            .font(FormaFont.displayFont(size * 0.36, weight: .semibold))
            .foregroundStyle(palette.accentInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.accent)
    }
}

struct CommunityMemberRow: View {
    var member: CommunityMember
    var trailing: AnyView?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(spacing: Spacing.md) {
            CommunityAvatar(name: member.displayName, urlString: member.avatarURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            if let trailing { trailing }
        }
    }

    private var subtitle: String {
        var pieces: [String] = []
        if let gym = member.gymName { pieces.append(gym) }
        let place = [member.area, member.city, member.country]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !place.isEmpty { pieces.append(place.joined(separator: ", ")) }
        pieces.append("@\(member.username)")
        return pieces.joined(separator: " · ")
    }
}

struct CommunityConnectionBadge: View {
    var status: ConnectionStatus
    @Environment(\.formaPalette) private var palette

    var body: some View {
        switch status {
        case .accepted:
            TagLabel(text: "Connected", color: palette.success)
        case .pendingSent:
            TagLabel(text: "Request sent", color: palette.textSecondary)
        case .pendingReceived:
            TagLabel(text: "Respond", color: palette.accentText)
        case .blocked:
            TagLabel(text: "Blocked", color: palette.danger)
        case .none:
            EmptyView()
        }
    }
}

/// Report sheet shared by profiles, posts, comments and messages. Reporting is
/// user initiated and always needs a reason; the server writes the row.
struct CommunityReportSheet: View {
    var targetType: CommunityReportTarget
    var targetID: String
    var targetLabel: String
    var onReport: (CommunityReportReason, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var reason: CommunityReportReason = .harassment
    @State private var details = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Report \(targetLabel)")
                        .font(FormaFont.displayFont(22, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("Moderators review reports. The reported member is not told who reported them.")
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)

                    ForEach(CommunityReportReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(reason == option ? palette.accentText : palette.textTertiary)
                                Text(option.title)
                                    .font(FormaFont.bodyFont(14))
                                    .foregroundStyle(palette.text)
                                Spacer()
                            }
                            .padding(Spacing.md)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        }
                        .buttonStyle(PressableScaleStyle())
                    }

                    FormaTextEditor(
                        label: "What happened? (optional)",
                        placeholder: "Add context for the reviewer",
                        text: $details,
                        minHeight: 90
                    )

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    PrimaryButton(
                        title: submitting ? "Sending report" : "Send report",
                        isLoading: submitting,
                        isDisabled: submitting
                    ) {
                        Task {
                            submitting = true
                            errorMessage = nil
                            let ok = await onReport(reason, details.trimmingCharacters(in: .whitespacesAndNewlines))
                            submitting = false
                            if ok { dismiss() } else { errorMessage = "The report could not be sent. Check your connection and try again." }
                        }
                    }
                }
                .padding(Spacing.xl)
            }
            .background(FormaBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CommunitySectionChips<Item: Identifiable & Equatable>: View where Item: RawRepresentable, Item.RawValue == String {
    var items: [Item]
    var title: (Item) -> String
    var selection: Item
    var onSelect: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(items) { item in
                    FormaChip(label: title(item), selected: item == selection) {
                        onSelect(item)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
        }
        .scrollClipDisabled()
    }
}
