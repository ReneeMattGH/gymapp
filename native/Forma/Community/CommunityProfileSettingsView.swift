import PhotosUI
import SwiftUI
import UIKit

private let profileInterestOptions = [
    "Strength", "Cardio", "Yoga", "HIIT", "Mobility",
    "Bodybuilding", "Running", "CrossFit", "Calisthenics", "Powerlifting",
]

// MARK: - Profile editor

struct CommunityProfileEditorView: View {
    var store: CommunityStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var interests: Set<String> = []
    @State private var focus: Set<String> = []
    @State private var avatarURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var photoError: String?
    @State private var saveError: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Your community profile is separate from your private Forma account. Only discoverable members can see it, and you choose whether your gym and area are shown.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                FormaCard {
                    HStack(spacing: Spacing.lg) {
                        CommunityAvatar(name: displayName.isEmpty ? "You" : displayName, urlString: avatarURL, size: 72)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(uploading ? "Uploading photo" : "Choose photo")
                                    .font(FormaFont.bodyFont(13, weight: .semibold))
                                    .foregroundStyle(palette.accentText)
                            }
                            .disabled(uploading)
                            Text("Optional. Photos are resized on this device before upload.")
                                .font(FormaFont.bodyFont(10))
                                .foregroundStyle(palette.textTertiary)
                            if let photoError {
                                Text(photoError)
                                    .font(FormaFont.bodyFont(11))
                                    .foregroundStyle(palette.danger)
                            }
                        }
                    }
                }

                FormaTextField(
                    label: "Username",
                    placeholder: "e.g. matthew_lifts",
                    text: $username,
                    capitalization: .never
                )
                Text("Letters, numbers and underscores only. Three characters minimum; the server removes other characters and resolves duplicates.")
                    .font(FormaFont.bodyFont(10))
                    .foregroundStyle(palette.textTertiary)

                FormaTextField(
                    label: "Display name",
                    placeholder: "How members see your name",
                    text: $displayName,
                    capitalization: .words
                )

                FormaTextEditor(
                    label: "Short bio (optional)",
                    placeholder: "Training style, goals, or what you are working on",
                    text: $bio,
                    minHeight: 80
                )

                FormaCard {
                    SectionHeader(title: "Interests")
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(profileInterestOptions, id: \.self) { option in
                            FormaChip(label: option, selected: interests.contains(option)) {
                                toggle(option, in: &interests)
                            }
                        }
                    }
                }

                FormaCard {
                    SectionHeader(title: "Training focus")
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(profileInterestOptions, id: \.self) { option in
                            FormaChip(label: option, selected: focus.contains(option)) {
                                toggle(option, in: &focus)
                            }
                        }
                    }
                }

                if let saveError {
                    ErrorBanner(message: saveError)
                }

                PrimaryButton(
                    title: store.isBusy("save-profile") ? "Saving" : "Save profile",
                    isLoading: store.isBusy("save-profile"),
                    isDisabled: displayName.trimmingCharacters(in: .whitespaces).count < 2 || username.count < 3
                ) {
                    Task { await save() }
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle(store.profile == nil ? "Create profile" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadDraft() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func loadDraft() {
        guard !loaded else { return }
        loaded = true
        guard let profile = store.profile else { return }
        username = profile.username
        displayName = profile.displayName
        bio = profile.bio ?? ""
        interests = Set(profile.interests)
        focus = Set(profile.workoutCategories)
        avatarURL = profile.avatarURL
    }

    private func toggle(_ option: String, in set: inout Set<String>) {
        if set.contains(option) {
            set.remove(option)
        } else {
            set.insert(option)
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        photoError = nil
        defer { uploading = false }
        guard
            let raw = try? await item.loadTransferable(type: Data.self),
            let jpeg = Self.avatarJPEG(from: raw)
        else {
            photoError = "That photo could not be prepared. Try a different image."
            return
        }
        guard jpeg.count <= 4_000_000 else {
            photoError = "Choose a smaller photo."
            return
        }
        if let url = await store.uploadAvatar(data: jpeg) {
            avatarURL = url
        } else {
            photoError = store.actionError ?? "The photo could not be uploaded."
        }
    }

    private func save() async {
        saveError = nil
        let ok = await store.saveProfile(
            username: username,
            displayName: displayName,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            interests: profileInterestOptions.filter { interests.contains($0) },
            categories: profileInterestOptions.filter { focus.contains($0) },
            avatarURL: avatarURL
        )
        if ok {
            dismiss()
        } else {
            saveError = store.actionError ?? "The profile could not be saved."
        }
    }

    private static func avatarJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 512
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Settings

struct CommunitySettingsView: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette
    @State private var draft: CommunityPreferences?
    @State private var saved = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                FormaCard {
                    SectionHeader(title: "Your profile")
                    if let profile = store.profile {
                        HStack(spacing: Spacing.md) {
                            CommunityAvatar(name: profile.displayName, urlString: profile.avatarURL, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(FormaFont.bodyFont(14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text("@\(profile.username)")
                                    .font(FormaFont.bodyFont(12))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                        }
                    } else {
                        Text("Create a community profile before choosing privacy settings.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                    }
                    NavigationLink {
                        communityDestination(.profileEditor, store: store)
                    } label: {
                        Text(store.profile == nil ? "Create profile" : "Edit profile")
                            .font(FormaFont.bodyFont(13, weight: .semibold))
                            .foregroundStyle(palette.accentText)
                    }
                }

                FormaCard {
                    SectionHeader(title: "Gym and area")
                    if let membership = store.membership {
                        KeyValueRow(label: membership.isPrimary ? "Primary gym" : "Gym", value: membership.gymName)
                        if !membership.locationText.isEmpty {
                            FormaDivider()
                            KeyValueRow(label: "Location", value: membership.locationText)
                        }
                        if store.memberships.count > 1 {
                            FormaDivider()
                            KeyValueRow(label: "Other gyms", value: "\(store.memberships.count - 1)")
                        }
                    } else if let preferences = draft, let area = preferences.area {
                        KeyValueRow(label: "Area", value: "\(area), \(preferences.city ?? "")")
                        FormaDivider()
                        KeyValueRow(label: "Gym", value: "None selected")
                    } else {
                        Text("No gym or area selected yet.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                    }
                    NavigationLink {
                        communityDestination(.gymSelection, store: store)
                    } label: {
                        Text("Change gym or area")
                            .font(FormaFont.bodyFont(13, weight: .semibold))
                            .foregroundStyle(palette.accentText)
                    }
                    Text("Selection is coarse. Forma never uses GPS or reveals live gym presence.")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }

                if let binding = draftBinding {
                    FormaCard {
                        SectionHeader(title: "Discovery and privacy")
                        settingToggle(
                            title: "Appear in discovery",
                            subtitle: "When off, your profile is hidden from search and suggestions. Existing connections stay.",
                            isOn: binding.discoverable
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Show my gym",
                            subtitle: "Show the gym you selected on your profile.",
                            isOn: binding.showGym
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Show my area",
                            subtitle: "Show your coarse neighborhood. Never an address or map point.",
                            isOn: binding.showArea
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Show my city",
                            subtitle: "Let members see the city on your profile and use it for matching.",
                            isOn: binding.showCity
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Show my country",
                            subtitle: "Let members in other countries see which country you train in.",
                            isOn: binding.showCountry
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Allow nearby discovery",
                            subtitle: "Let members in your area group find you.",
                            isOn: binding.nearbyDiscovery
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Discoverable worldwide",
                            subtitle: "Let members anywhere find you in Global discovery. Only your chosen gym, city and country are shown.",
                            isOn: binding.globalDiscovery
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Allow connection requests",
                            subtitle: "Turn off to stop new requests. Existing connections are unaffected.",
                            isOn: binding.allowConnectionRequests
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Allow messages",
                            subtitle: "Messaging also requires an accepted connection, in both directions.",
                            isOn: binding.allowMessages
                        )
                    }

                    FormaCard {
                        SectionHeader(title: "Notifications")
                        settingToggle(
                            title: "Connection activity",
                            subtitle: "Requests and accepted connections.",
                            isOn: binding.notifyConnections
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Messages",
                            subtitle: "New messages from connections.",
                            isOn: binding.notifyMessages
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Comments",
                            subtitle: "Comments on your posts.",
                            isOn: binding.notifyComments
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Likes",
                            subtitle: "Likes on your posts.",
                            isOn: binding.notifyLikes
                        )
                        Text("These control in-app notifications. Push alerts are only sent when this build has an Apple Push configuration.")
                            .font(FormaFont.bodyFont(10))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let saveError {
                        ErrorBanner(message: saveError)
                    }
                    if saved {
                        NoticeBanner(message: "Settings saved.", systemImage: "checkmark.circle.fill", accent: true)
                    }

                    PrimaryButton(
                        title: store.isBusy("save-preferences") ? "Saving" : "Save settings",
                        isLoading: store.isBusy("save-preferences")
                    ) {
                        Task { await save() }
                    }
                } else {
                    LoadingCard(label: "Loading settings")
                }

                FormaCard {
                    SectionHeader(title: "Safety")
                    NavigationLink {
                        communityDestination(.connectionRequests, store: store)
                    } label: {
                        settingsRow(label: "Connection requests", systemImage: "person.badge.plus", badge: store.incomingRequestCount)
                    }
                    FormaDivider()
                    NavigationLink {
                        communityDestination(.blockedMembers, store: store)
                    } label: {
                        settingsRow(label: "Blocked members", systemImage: "hand.raised")
                    }
                    FormaDivider()
                    NavigationLink {
                        communityDestination(.notifications, store: store)
                    } label: {
                        settingsRow(label: "Notifications", systemImage: "bell", badge: store.unreadNotifications)
                    }
                    Text("Reports are reviewed by moderators. The person you report is not told who reported them.")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Community settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if draft == nil {
                draft = store.preferences ?? defaultPreferences
            }
        }
        .onChange(of: store.preferences) { _, newValue in
            if newValue != nil, !saved {
                draft = newValue
            }
        }
    }

    private var defaultPreferences: CommunityPreferences {
        CommunityPreferences(
            userID: store.userID ?? "",
            discoverable: false,
            showGym: true,
            showArea: true,
            showCity: true,
            showCountry: true,
            nearbyDiscovery: false,
            globalDiscovery: true,
            allowConnectionRequests: true,
            allowMessages: true,
            city: store.membership?.city,
            area: store.membership?.area,
            country: store.membership?.country,
            countryCode: store.membership?.countryCode,
            notifyConnections: true,
            notifyMessages: true,
            notifyComments: true,
            notifyLikes: true
        )
    }

    private var draftBinding: Binding<CommunityPreferences>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { self.draft ?? self.defaultPreferences },
            set: { self.draft = $0 }
        )
    }

    private func settingToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FormaFont.bodyFont(14, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(palette.accentText)
    }

    private func settingsRow(label: String, systemImage: String, badge: Int = 0) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22)
            Text(label)
                .font(FormaFont.bodyFont(14, weight: .medium))
                .foregroundStyle(palette.text)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(FormaFont.bodyFont(10, weight: .bold))
                    .foregroundStyle(palette.accentInk)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(palette.accent, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private func save() async {
        guard let draft else { return }
        saveError = nil
        saved = false
        let ok = await store.savePreferences(draft)
        if ok {
            self.draft = store.preferences ?? draft
            saved = true
        } else {
            saveError = store.actionError ?? "Settings could not be saved."
        }
    }
}
