import SwiftUI

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var input = ""
    @State private var showHistory = false
    @State private var showClearConfirm = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                FormaDivider()
                conversation
                composer
            }
            .background(FormaBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistorySheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.background)
        }
        .confirmationDialog(
            "Clear this conversation?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear conversation", role: .destructive) {
                Task { await model.clearConversation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the messages and the coach's saved memory for this chat. Other conversations stay in your history.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.md) {
            BrandMark(size: 30, color: palette.accent)
                .padding(8)
                .background(palette.surface, in: Circle())
                .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Forma coach")
                    .font(FormaFont.displayFont(18, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    TagLabel(text: model.prefersAI ? "Live AI" : "Preview", color: model.prefersAI ? palette.accentText : palette.warning)
                        .fixedSize()
                    Text(model.prefersAI ? "Safety-checked" : "On-device")
                        .font(FormaFont.bodyFont(10.5))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.sm)
            if model.currentConversation != nil || !model.messages.isEmpty {
                IconButton(systemImage: "trash", label: "Clear conversation") {
                    showClearConfirm = true
                }
                .disabled(model.coachBusy || model.isDeletingConversation)
            }
            IconButton(systemImage: "clock.arrow.circlepath", label: "Conversation history") {
                showHistory = true
            }
            IconButton(systemImage: "square.and.pencil", label: "New conversation", accent: true) {
                model.newConversation()
                inputFocused = false
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    if model.messages.isEmpty {
                        welcome
                    } else {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    if model.coachBusy {
                        streamingBubble
                    }
                    if model.isLoadingMessages && model.messages.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(palette.accentText)
                            Text("Loading conversation…")
                                .font(FormaFont.bodyFont(11.5))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                    if let error = model.coachError {
                        ErrorBanner(message: error)
                        if model.lastFailedPrompt != nil && !model.coachBusy {
                            SecondaryButton(title: "Retry reply", systemImage: "arrow.clockwise") {
                                model.retryLastCoachMessage()
                            }
                        }
                    }
                    if let notice = model.coachNotice {
                        NoticeBanner(message: notice, systemImage: "stop.circle")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: model.streamingText) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: model.coachBusy) { _, busy in
                if busy { scrollToBottom(proxy, animated: true) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Overline(text: model.prefersAI ? "Your coach" : "Preview coach")
                Text("Ask about training,\nform, or recovery.")
                    .font(FormaFont.displayFont(28, weight: .bold))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.prefersAI
                     ? "Your coach sees your plan, recent sessions, equipment, and goals — and stays conservative with injuries."
                     : "The preview coach gives safety-first answers from your local plan. Every reply is generated on this device.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(model.coachSuggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.selection()
                        model.submitCoachMessage(suggestion)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.accentText)
                            Text(suggestion)
                                .font(FormaFont.bodyFont(13, weight: .medium))
                                .foregroundStyle(palette.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
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
            NoticeBanner(
                message: "Forma does not diagnose or treat injuries. If you feel sharp pain, dizziness, or unusual shortness of breath, stop and seek professional help.",
                systemImage: "heart.text.square"
            )
        }
        .padding(.top, Spacing.lg)
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            BrandMark(size: 20, color: palette.accentText)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if model.streamingText.isEmpty {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).tint(palette.accentText)
                        Text("Thinking…")
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(Spacing.md)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    Text(model.streamingText)
                        .font(FormaFont.bodyFont(14))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(Spacing.md)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.accentBorder, lineWidth: 1)
                        }
                }
            }
            Spacer(minLength: 40)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Ask about training, form, or recovery…", text: $input, axis: .vertical)
                .font(FormaFont.bodyFont(14))
                .foregroundStyle(palette.text)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 11)
                .background(palette.input, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(inputFocused ? palette.accentBorder : palette.border, lineWidth: 1)
                }

            if model.coachBusy {
                Button {
                    Haptics.warning()
                    model.stopCoachReply()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(width: 42, height: 42)
                        .background(palette.surfaceRaised, in: Circle())
                        .overlay { Circle().strokeBorder(palette.borderStrong, lineWidth: 1) }
                }
                .accessibilityLabel("Stop response")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.accentInk)
                        .frame(width: 42, height: 42)
                        .background(palette.accent, in: Circle())
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background {
            palette.background
                .opacity(0.97)
                .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        inputFocused = false
        model.submitCoachMessage(text)
    }
}

// MARK: - Bubbles

private struct MessageBubble: View {
    let message: CoachMessage
    @Environment(\.formaPalette) private var palette

    private var isUser: Bool { message.role == .user }

    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if isUser {
                Spacer(minLength: 48)
            } else {
                BrandMark(size: 20, color: palette.accentText)
                    .padding(.top, 2)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(rendered)
                    .font(FormaFont.bodyFont(14))
                    .foregroundStyle(isUser ? palette.accentInk : palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surface),
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    )
                    .overlay {
                        if !isUser {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.border, lineWidth: 1)
                        }
                    }
                if !isUser && !message.sources.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(message.sources) { source in
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(source.name)
                                    .font(FormaFont.bodyFont(9.5, weight: .medium))
                            }
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(palette.surfaceRaised, in: Capsule())
                            .accessibilityLabel("Source: \(source.name)")
                        }
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                }
                Text(Formatters.time(message.createdAt))
                    .font(FormaFont.bodyFont(9.5))
                    .foregroundStyle(palette.textTertiary)
            }
            if !isUser {
                Spacer(minLength: 32)
            }
        }
    }
}

// MARK: - History

struct ConversationHistorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var deleting: CoachConversation?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            SheetHeading(
                title: "Conversations",
                subtitle: "Saved on your account. Open one to continue.",
                onClose: { dismiss() }
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            if model.conversations.isEmpty {
                FormaEmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No conversations yet",
                    message: "Ask the coach anything and your conversation will be saved here."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: Spacing.sm) {
                        ForEach(model.conversations) { conversation in
                            HStack(spacing: Spacing.md) {
                                Button {
                                    Task {
                                        await model.openConversation(conversation)
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: Spacing.md) {
                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(palette.accentText)
                                            .frame(width: 34, height: 34)
                                            .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(conversation.title)
                                                .font(FormaFont.bodyFont(13.5, weight: .semibold))
                                                .foregroundStyle(palette.text)
                                                .lineLimit(1)
                                            Text(Formatters.shortDate(conversation.updatedAt) + " · " + Formatters.time(conversation.updatedAt))
                                                .font(FormaFont.bodyFont(10.5))
                                                .foregroundStyle(palette.textTertiary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    deleting = conversation
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(palette.textTertiary)
                                        .frame(width: 34, height: 34)
                                }
                                .accessibilityLabel("Delete conversation")
                            }
                            .padding(Spacing.md)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: 1)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                }
                .scrollIndicators(.hidden)
            }

            SecondaryButton(title: "Start a new conversation", systemImage: "square.and.pencil") {
                model.newConversation()
                dismiss()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .background(FormaBackground())
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    Task { await model.deleteConversation(deleting) }
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The messages will be removed from your account.")
        }
    }
}
