import SwiftUI

struct CommunityFeedScreen: View {
    var store: CommunityStore
    @Binding var showReportFor: CommunityReportPayload?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if store.isSuspended {
                    NoticeBanner(
                        message: "Community access for this account is paused. You can read the feed, but the server blocks new posts, comments and likes.",
                        systemImage: "hand.raised.fill"
                    )
                } else {
                    CommunityPostComposer(store: store)
                }

                CommunitySectionChips(
                    items: CommunityFeedFilter.allCases,
                    title: \.title,
                    selection: store.feedFilter
                ) { filter in
                    Task { await store.setFeedFilter(filter) }
                }
                .padding(.horizontal, -Spacing.xl)

                if let error = store.feedError {
                    ErrorBanner(message: error) {
                        Task { await store.loadFeed(reset: true) }
                    }
                }

                if store.feedLoading && store.feed.isEmpty {
                    LoadingCard(label: "Loading the feed")
                } else if store.feed.isEmpty {
                    FormaEmptyState(
                        systemImage: "rectangle.stack",
                        title: "Nothing here yet",
                        message: emptyMessage
                    )
                } else {
                    ForEach(store.feed) { post in
                        CommunityPostCard(store: store, post: post, showReportFor: $showReportFor)
                    }

                    if store.feedHasMore {
                        SecondaryButton(title: "Load more posts", systemImage: "arrow.down.circle") {
                            Task { await store.loadFeed(reset: false) }
                        }
                        .onAppear {
                            Task { await store.loadFeed(reset: false) }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(FormaBackground())
        .navigationTitle("Community feed")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.loadFeed(reset: true) }
        .task {
            if store.feed.isEmpty {
                await store.loadFeed(reset: true)
            }
        }
    }

    private var emptyMessage: String {
        switch store.feedFilter {
        case .all:
            return "No posts have been shared yet. Posts come from real members — this screen stays empty until someone posts."
        case .connections:
            return "None of your connections have posted yet."
        case .gym:
            return "No one at your gym has posted yet."
        }
    }
}

// MARK: - Composer

struct CommunityPostComposer: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette
    @State private var content = ""
    @State private var kind: CommunityPostKind = .update
    @State private var achievement = ""
    @State private var expanded = false

    private var trimmed: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var busy: Bool { store.isBusy("create-post") }

    var body: some View {
        FormaCard {
            SectionHeader(title: "Share with the community")

            if expanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(CommunityPostKind.allCases) { option in
                            FormaChip(label: option.title, selected: kind == option) {
                                kind = option
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }

            FormaTextEditor(
                label: "Post",
                placeholder: "Share a workout, milestone or encouragement. Workout data is only shared if you choose to post it.",
                text: $content,
                minHeight: expanded ? 96 : 60
            )
            .onTapGesture { expanded = true }

            if expanded && (kind == .achievement || kind == .milestone) {
                FormaTextField(
                    label: "Achievement (optional)",
                    placeholder: "e.g. First 100 kg squat",
                    text: $achievement
                )
            }

            HStack {
                Text("\(min(trimmed.count, 2000))/2000")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Button {
                    Task { await post() }
                } label: {
                    Group {
                        if busy {
                            ProgressView().controlSize(.small).tint(palette.accentInk)
                        } else {
                            Text("Post")
                                .font(FormaFont.bodyFont(13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 8)
                    .background(palette.accent, in: Capsule())
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(trimmed.isEmpty || trimmed.count > 2000 || busy)
                .opacity(trimmed.isEmpty || busy ? 0.45 : 1)
            }

            if !expanded {
                Text("Posts are public to discoverable members who can see this feed. Your workout details stay private unless you attach them to a post.")
                    .font(FormaFont.bodyFont(10))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func post() async {
        let label = kind == .achievement || kind == .milestone ? achievement.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let ok = await store.createPost(
            content: trimmed,
            kind: kind,
            sessionID: nil,
            achievementLabel: label.isEmpty ? nil : label
        )
        if ok {
            content = ""
            achievement = ""
            kind = .update
            expanded = false
        }
    }
}

// MARK: - Post card

struct CommunityPostCard: View {
    var store: CommunityStore
    var post: CommunityPost
    @Binding var showReportFor: CommunityReportPayload?

    @Environment(\.formaPalette) private var palette
    @State private var showComments = false
    @State private var confirmDelete = false
    @State private var confirmHide = false

    var body: some View {
        FormaCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                CommunityAvatar(name: post.displayName, urlString: post.avatarURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(post.displayName)
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.text)
                        if post.isOwn {
                            TagLabel(text: "You", color: palette.textSecondary)
                        }
                    }
                    Text("@\(post.username) · \(CommunityTime.short(post.createdAt))")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: Spacing.sm)
                moreMenu
            }

            if post.kind != .update {
                TagLabel(text: post.kind.title, color: palette.accentText)
            }

            Text(post.content)
                .font(FormaFont.bodyFont(14))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)

            if let achievement = post.achievementLabel, !achievement.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.warning)
                    Text(achievement)
                        .font(FormaFont.bodyFont(12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.warningSoft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }

            if let session = post.sharedSession {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.accentText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title)
                            .font(FormaFont.bodyFont(12, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("\(max(1, session.durationSeconds / 60)) min session")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }

            HStack(spacing: Spacing.xl) {
                Button {
                    Task { await store.toggleLike(post) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: post.liked ? "heart.fill" : "heart")
                        Text("\(post.likeCount)")
                    }
                    .font(FormaFont.bodyFont(13, weight: .medium))
                    .foregroundStyle(post.liked ? palette.accentText : palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(post.liked ? "Remove like" : "Like post")

                Button {
                    showComments = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left")
                        Text("\(post.commentCount)")
                    }
                    .font(FormaFont.bodyFont(13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open comments")

                Spacer()
            }
        }
        .sheet(isPresented: $showComments) {
            CommunityPostCommentsSheet(store: store, post: post)
        }
        .confirmationDialog("Hide this post?", isPresented: $confirmHide, titleVisibility: .visible) {
            Button("Hide post") {
                Task { await store.hidePost(post) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hidden posts stop appearing in your feed. The author is not notified.")
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) {
                Task { await store.deletePost(post) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                confirmHide = true
            } label: {
                Label("Hide post", systemImage: "eye.slash")
            }
            Button {
                showReportFor = CommunityReportPayload(targetType: .post, targetID: post.id, label: "post")
            } label: {
                Label("Report post", systemImage: "flag")
            }
            if post.isOwn {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete post", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Post options")
    }
}

// MARK: - Comments

struct CommunityPostCommentsSheet: View {
    var store: CommunityStore
    var post: CommunityPost

    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var comments: [CommunityComment] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var loadError: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var reportComment: CommunityComment?
    @FocusState private var composerFocused: Bool

    private let pageSize = 50

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    if loading {
                        LoadingCard(label: "Loading comments")
                    } else if let loadError {
                        ErrorBanner(message: loadError) {
                            Task { await load(reset: true) }
                        }
                    } else if comments.isEmpty {
                        Text("No comments yet. Comments come from real members.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xxl)
                    } else {
                        ForEach(comments) { comment in
                            row(comment)
                            FormaDivider()
                        }
                        if hasMore {
                            SecondaryButton(title: loadingMore ? "Loading" : "Load more comments") {
                                Task { await load(reset: false) }
                            }
                            .disabled(loadingMore)
                        }
                    }
                }
                .padding(Spacing.xl)
            }
            .background(FormaBackground())
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load(reset: true) }
            .sheet(item: $reportComment) { comment in
                CommunityReportSheet(
                    targetType: .comment,
                    targetID: comment.id,
                    targetLabel: "comment"
                ) { reason, details in
                    await store.report(targetType: .comment, targetID: comment.id, reason: reason, details: details)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let sendError {
                ErrorBanner(message: sendError) { self.sendError = nil }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
            }
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(FormaFont.bodyFont(14))
                    .foregroundStyle(palette.text)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(palette.input, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(composerFocused ? palette.accentBorder : palette.border, lineWidth: 1)
                    }

                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if sending {
                            ProgressView().tint(palette.accentInk)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(palette.accentInk)
                    .frame(width: 42, height: 42)
                    .background(palette.accent, in: Circle())
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(trimmedDraft.isEmpty || sending || store.isSuspended)
                .opacity(trimmedDraft.isEmpty || sending || store.isSuspended ? 0.45 : 1)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { FormaDivider() }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func row(_ comment: CommunityComment) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            CommunityAvatar(name: comment.displayName, urlString: comment.avatarURL, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.sm) {
                    Text(comment.displayName)
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(CommunityTime.short(comment.createdAt))
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(comment.content)
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.sm)
            Menu {
                if comment.isOwn {
                    Button(role: .destructive) {
                        Task { await remove(comment) }
                    } label: {
                        Label("Delete comment", systemImage: "trash")
                    }
                } else {
                    Button {
                        reportComment = comment
                    } label: {
                        Label("Report comment", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Comment options")
        }
    }

    private func load(reset: Bool) async {
        if reset {
            loading = true
            loadError = nil
        } else {
            guard hasMore, !loadingMore else { return }
            loadingMore = true
        }
        defer {
            loading = false
            loadingMore = false
        }
        let offset = reset ? 0 : comments.count
        let rows = await store.loadComments(postID: post.id, offset: offset)
        if reset {
            comments = rows
        } else {
            let known = Set(comments.map(\.id))
            comments += rows.filter { !known.contains($0.id) }
        }
        hasMore = rows.count >= pageSize
        if rows.isEmpty, let actionError = store.actionError, comments.isEmpty {
            loadError = actionError
        }
    }

    private func send() async {
        let body = trimmedDraft
        guard !body.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        if await store.addComment(postID: post.id, content: body) {
            draft = ""
            await load(reset: true)
        } else {
            sendError = store.actionError ?? "The comment could not be added. Try again."
        }
        sending = false
    }

    private func remove(_ comment: CommunityComment) async {
        await store.deleteComment(id: comment.id, postID: post.id)
        comments.removeAll { $0.id == comment.id }
    }
}
