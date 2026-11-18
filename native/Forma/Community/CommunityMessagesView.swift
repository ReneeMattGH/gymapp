import SwiftUI

struct CommunityMessagesSection: View {
    var store: CommunityStore
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let error = store.conversationsError {
                ErrorBanner(message: error) {
                    Task { await store.loadConversations() }
                }
            }

            if store.conversationsLoading && store.conversations.isEmpty {
                LoadingCard(label: "Loading conversations")
            } else if store.conversations.isEmpty {
                FormaEmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No messages yet",
                    message: "Messaging only opens after a connection request is accepted. Conversations appear here once you or a connection send the first message."
                )
            } else {
                FormaCard {
                    SectionHeader(title: "Conversations")
                    ForEach(store.conversations) { conversation in
                        NavigationLink(value: CommunityRoute.conversation(conversation)) {
                            row(conversation)
                        }
                        .buttonStyle(.plain)
                        if conversation.conversationID != store.conversations.last?.conversationID {
                            FormaDivider()
                        }
                    }
                }

                Text("Messages are stored on the server and shown only to the two connected members. This release supports text and emoji; links and attachments are not accepted.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .task { await store.loadConversations() }
    }

    private func row(_ conversation: CommunityConversation) -> some View {
        HStack(spacing: Spacing.md) {
            CommunityAvatar(name: conversation.displayName, urlString: conversation.avatarURL)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xs) {
                    Text(conversation.displayName)
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if conversation.muted {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Text(conversation.lastMessage ?? "No messages yet")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(conversation.unreadCount > 0 ? palette.text : palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 5) {
                if let last = conversation.lastMessageAt {
                    Text(CommunityTime.short(last))
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
                if conversation.unreadCount > 0 {
                    Text(conversation.unreadCount > 9 ? "9+" : "\(conversation.unreadCount)")
                        .font(FormaFont.bodyFont(9, weight: .bold))
                        .foregroundStyle(palette.accentInk)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 3)
                        .background(palette.accent, in: Capsule())
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Thread

struct CommunityMessageThreadView: View {
    var store: CommunityStore
    var conversation: CommunityConversation

    @Environment(\.formaPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [CommunityMessage] = []
    @State private var loading = true
    @State private var loadingOlder = false
    @State private var hasMore = false
    @State private var loadError: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var reportTarget: CommunityMessage?
    @FocusState private var composerFocused: Bool

    private let pageLimit = 40

    private var current: CommunityConversation {
        store.conversations.first { $0.conversationID == conversation.conversationID } ?? conversation
    }

    private var myID: String { store.userID ?? "" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    if hasMore {
                        SecondaryButton(title: loadingOlder ? "Loading" : "Load earlier messages", systemImage: "arrow.up.circle") {
                            Task { await loadOlder() }
                        }
                        .disabled(loadingOlder)
                    }

                    if loading {
                        LoadingCard(label: "Loading messages")
                    } else if let loadError {
                        ErrorBanner(message: loadError) {
                            Task { await loadInitial(force: true) }
                        }
                    } else if messages.isEmpty {
                        Text("No messages yet. Say hello to \(current.displayName).")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xxl)
                    } else {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .background(FormaBackground())
            .safeAreaInset(edge: .bottom) { composer }
            .refreshable { await refreshNewest() }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: current.lastMessageAt) { _, _ in
                Task { await refreshNewest() }
            }
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.muteConversation(current, muted: !current.muted) }
                } label: {
                    Image(systemName: current.muted ? "bell.slash" : "bell")
                }
                .accessibilityLabel(current.muted ? "Unmute conversation" : "Mute conversation")
            }
        }
        .task { await loadInitial(force: false) }
        .sheet(item: $reportTarget) { message in
            CommunityReportSheet(
                targetType: .message,
                targetID: message.id,
                targetLabel: "message"
            ) { reason, details in
                await store.report(targetType: .message, targetID: message.id, reason: reason, details: details)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if store.isSuspended {
                Text("This account cannot send messages while Community access is paused.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
            }
            if let sendError {
                ErrorBanner(message: sendError) {
                    self.sendError = nil
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .font(FormaFont.bodyFont(14))
                    .foregroundStyle(palette.text)
                    .lineLimit(1...5)
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
                .opacity(trimmedDraft.isEmpty || store.isSuspended ? 0.45 : 1)
                .accessibilityLabel("Send message")
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

    @ViewBuilder
    private func bubble(_ message: CommunityMessage) -> some View {
        let mine = message.senderID == myID
        HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 56) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(FormaFont.bodyFont(14))
                    .foregroundStyle(mine ? palette.accentInk : palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CommunityTime.messageStamp(message.createdAt))
                    .font(FormaFont.bodyFont(9))
                    .foregroundStyle(mine ? palette.accentInk.opacity(0.7) : palette.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 9)
            .background(
                mine ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surface),
                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            )
            .overlay {
                if !mine {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            }
            .contextMenu {
                if !mine {
                    Button {
                        reportTarget = message
                    } label: {
                        Label("Report message", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        Task {
                            await store.block(userID: message.senderID, blocked: true)
                            dismiss()
                        }
                    } label: {
                        Label("Block sender", systemImage: "hand.raised")
                    }
                }
            }
            if !mine { Spacer(minLength: 56) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(.snappy(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func loadInitial(force: Bool) async {
        guard messages.isEmpty || force else { return }
        loading = true
        loadError = nil
        let page = await store.loadMessages(conversationID: conversation.conversationID, before: nil)
        messages = page
        hasMore = page.count >= pageLimit
        loading = false
        if page.isEmpty, let actionError = store.actionError {
            loadError = actionError
        }
        await store.markConversationRead(current)
    }

    private func refreshNewest() async {
        let page = await store.loadMessages(conversationID: conversation.conversationID, before: nil)
        guard !page.isEmpty else { return }
        var known = Set(messages.map(\.id))
        var merged = messages
        for message in page where !known.contains(message.id) {
            merged.append(message)
            known.insert(message.id)
        }
        merged.sort { $0.createdAt < $1.createdAt }
        messages = merged
        if page.count >= pageLimit { hasMore = true }
        await store.markConversationRead(current)
    }

    private func loadOlder() async {
        guard let oldest = messages.first?.createdAt else { return }
        loadingOlder = true
        let page = await store.loadMessages(conversationID: conversation.conversationID, before: oldest)
        if !page.isEmpty {
            let known = Set(messages.map(\.id))
            messages.insert(contentsOf: page.filter { !known.contains($0.id) }, at: 0)
        }
        hasMore = page.count >= pageLimit
        loadingOlder = false
    }

    private func send() async {
        let body = trimmedDraft
        guard !body.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        if let message = await store.sendMessage(conversationID: conversation.conversationID, body: body) {
            messages.append(message)
            draft = ""
        } else {
            sendError = store.actionError ?? "The message could not be sent. Check your connection and try again."
        }
        sending = false
    }
}
