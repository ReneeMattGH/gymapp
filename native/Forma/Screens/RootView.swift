import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var didBootstrap = false
    @State private var showPasswordUpdate = false

    var body: some View {
        ZStack {
            FormaBackground()
            content
        }
        .preferredColorScheme(model.colorScheme)
        .tint(palette.accent)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await model.bootstrap()
        }
        .onOpenURL { url in
            guard url.scheme == "forma" else { return }
            model.handleAuthURL(url)
            if url.host == "update-password" || url.absoluteString.contains("update-password") {
                showPasswordUpdate = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshOnForeground() }
        }
        .sheet(isPresented: $showPasswordUpdate) {
            UpdatePasswordView()
        }
        .animation(.easeInOut(duration: 0.22), value: model.mode)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .loading:
            LaunchView()
        case .setupRequired:
            SetupRequiredView()
        case .preview, .supabase:
            if model.isBootstrapping || (model.isLoadingData && model.profile == nil) {
                LaunchView()
            } else if model.user == nil {
                AuthView()
            } else if let error = model.loadError, model.profile == nil {
                LoadFailureView(message: error)
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
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            BrandMark(size: 58, color: palette.accent)
                .scaleEffect(pulse ? 1.04 : 0.98)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
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
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(palette.warning)
            Text("Your data could not load")
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
