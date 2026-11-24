import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var didBootstrap = false

    var body: some View {
        ZStack {
            FormaBackground()
            content
        }
        .preferredColorScheme(model.colorScheme)
        .tint(palette.accentText)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await model.bootstrap()
        }
        .onOpenURL { url in
            guard url.scheme == "forma" else { return }
            model.routeDeepLink(url)
        }
        .sheet(isPresented: Binding(
            get: { model.isAccountPresented },
            set: { model.isAccountPresented = $0 }
        )) {
            NavigationStack {
                AccountView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { model.isAccountPresented = false }
                                .foregroundStyle(palette.accentText)
                        }
                    }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshOnForeground() }
        }
        .animation(.easeInOut(duration: 0.22), value: model.mode)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .loading:
            LaunchView()
        case .local:
            if model.isBootstrapping {
                LaunchView()
            } else if model.repository == nil {
                LoadFailureView(message: model.loadError ?? "The local database could not be opened.")
            } else if model.needsOnboarding || model.pendingOnboardingOutcome != nil || model.isCompletingOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
    }
}

struct LaunchView: View {
    @Environment(\.formaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            BrandMark(size: 58, color: palette.accentText)
                .scaleEffect(pulse ? 1.04 : 0.98)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            Text("FORMA")
                .font(FormaFont.displayFont(17, weight: .bold))
                .tracking(5)
                .foregroundStyle(palette.text)
        }
        .onAppear { pulse = true }
    }
}

struct LoadFailureView: View {
    var message: String
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Wordmark()
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(palette.warning)
            Text("Your local data could not open")
                .font(FormaFont.displayFont(21, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(message)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .padding(.horizontal, Spacing.huge)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 420)
    }
}
