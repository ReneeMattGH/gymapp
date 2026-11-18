import SwiftUI

struct CommunityNotificationsView: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Notifications are created by real community activity and live in your account. They update here in real time while the app is open.")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = store.notificationsError {
                    ErrorBanner(message: error) {
                        Task { await store.loadNotifications() }
                    }
                }

                if store.notificationsLoading && store.notifications.isEmpty {
                    LoadingCard(label: "Loading notifications")
                } else if store.notifications.isEmpty {
                    FormaEmptyState(
                        systemImage: "bell",
                        title: "Nothing yet",
                        message: "Connection requests, messages, comments and likes appear here once they happen. Forma never creates sample notifications."
                    )
                } else {
                    FormaCard {
                        ForEach(store.notifications) { notification in
                            notificationRow(notification)
                            if notification.id != store.notifications.last?.id {
                                FormaDivider()
                            }
                        }
                    }

                    if store.notificationsHasMore {
                        SecondaryButton(title: "Load older notifications", systemImage: "arrow.down.circle") {
                            Task { await store.loadMoreNotifications() }
                        }
                    }
                }

                NavigationLink(value: CommunityRoute.settings) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(palette.textSecondary)
                        Text("Notification settings")
                            .font(FormaFont.bodyFont(14, weight: .medium))
                            .foregroundStyle(palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(Spacing.lg)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") {
                    Task { await store.markNotificationsRead() }
                }
                .disabled(store.unreadNotifications == 0)
            }
        }
        .refreshable { await store.loadNotifications() }
        .task { await store.loadNotifications() }
    }

    @ViewBuilder
    private func notificationRow(_ notification: CommunityNotification) -> some View {
        if let route = route(for: notification) {
            NavigationLink(value: route) {
                content(notification)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                Task { await store.markNotificationsRead(ids: [notification.id]) }
            })
        } else {
            Button {
                Task { await store.markNotificationsRead(ids: [notification.id]) }
            } label: {
                content(notification)
            }
            .buttonStyle(.plain)
        }
    }

    private func content(_ notification: CommunityNotification) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: notification.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(notification.isUnread ? palette.accentText : palette.textSecondary)
                .frame(width: 36, height: 36)
                .background(notification.isUnread ? palette.accentSoft : palette.surfaceRaised, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.sm) {
                    Text(notification.title)
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    if notification.isUnread {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(body(for: notification))
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CommunityTime.short(notification.createdAt))
                    .font(FormaFont.bodyFont(10))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    private func body(for notification: CommunityNotification) -> String {
        if let actor = notification.actorDisplayName ?? notification.actorUsername {
            return "\(actor) \(notification.body)"
        }
        return notification.body
    }

    private func route(for notification: CommunityNotification) -> CommunityRoute? {
        switch notification.kind {
        case "connection_request":
            return .connectionRequests
        case "connection_accepted", "message":
            guard let actorID = notification.actorID else { return nil }
            return .member(actorID)
        case "post_comment", "post_like":
            return notification.postID == nil ? nil : .feed
        default:
            return nil
        }
    }
}
