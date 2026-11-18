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
                    NavigationLink(value: CommunityRoute.profileEditor) {
                        Text(store.profile == nil ? "Create profile" : "Edit profile")
                            .font(FormaFont.bodyFont(13, weight: .semibold))
                            .foregroundStyle(palette.accentText)
                    }
                }

                FormaCard {
                    SectionHeader(title: "Gym and area")
                    if let membership = store.membership {
                        KeyValueRow(label: "Gym", value: membership.gymName)
                        FormaDivider()
                        KeyValueRow(label: "Area", value: [membership.area, membership.city].compactMap { $0 }.joined(separator: ", "))
                    } else if let preferences = draft, let area = preferences.area {
                        KeyValueRow(label: "Area", value: "\(area), \(preferences.city ?? "")")
                        FormaDivider()
                        KeyValueRow(label: "Gym", value: "None selected")
                    } else {
                        Text("No gym or area selected yet.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                    }
                    NavigationLink(value: CommunityRoute.gymSelection) {
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
                            subtitle: "Show your coarse area and city. Never an address or map point.",
                            isOn: binding.showArea
                        )
                        FormaDivider()
                        settingToggle(
                            title: "Allow nearby discovery",
                            subtitle: "Let members in your area group find you.",
                            isOn: binding.nearbyDiscovery
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
                    NavigationLink(value: CommunityRoute.connectionRequests) {
                        settingsRow(label: "Connection requests", systemImage: "person.badge.plus", badge: store.incomingRequestCount)
                    }
                    FormaDivider()
                    NavigationLink(value: CommunityRoute.blockedMembers) {
                        settingsRow(label: "Blocked members", systemImage: "hand.raised")
                    }
                    FormaDivider()
                    NavigationLink(value: CommunityRoute.notifications) {
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
            nearbyDiscovery: false,
            allowConnectionRequests: true,
            allowMessages: true,
            city: store.membership?.city,
            area: store.membership?.area,
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
        .tint(palette.accent)
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

// MARK: - Gym and area selection

struct CommunityGymSelectionView: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette
    @State private var query = ""
    @State private var requestName = ""
    @State private var requestCity = ""
    @State private var requestArea = ""
    @State private var requestAddress = ""
    @State private var requestResult: String?
    @State private var actionError: String?
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Discovery matches members by the gym or area you pick here. It never reads your device location, so nothing here confirms where you are right now.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let membership = store.membership {
                    FormaCard(style: .raised) {
                        SectionHeader(title: "Your gym")
                        Text(membership.gymName)
                            .font(FormaFont.displayFont(19, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text([membership.area, membership.city].compactMap { $0 }.joined(separator: ", "))
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textSecondary)
                        if membership.verificationStatus != "verified" {
                            TagLabel(text: "Awaiting review", color: palette.warning)
                        }
                        SecondaryButton(title: "Leave this gym community", destructive: true) {
                            confirmLeave = true
                        }
                    }
                }

                FormaCard {
                    SectionHeader(title: "Search gyms")
                    FormaTextField(placeholder: "Gym name, city or area", text: $query, capitalization: .words)
                        .onChange(of: query) { _, value in
                            Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                guard !Task.isCancelled else { return }
                                await store.searchGyms(query: value)
                            }
                        }

                    if let error = store.gymSearchError {
                        ErrorBanner(message: error) {
                            Task { await store.searchGyms(query: query) }
                        }
                    }

                    if store.gymSearchLoading {
                        LoadingCard(label: "Searching gyms")
                    } else if store.gymResults.isEmpty {
                        Text("No gyms match yet. Request one below; it appears in search for you while it waits for review.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(store.gymResults) { gym in
                            gymRow(gym)
                            if gym.id != store.gymResults.last?.id {
                                FormaDivider()
                            }
                        }
                    }
                }

                FormaCard {
                    SectionHeader(title: "Choose an area instead")
                    Text("Areas come from the community directory. Your area is never mapped to an exact location.")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                    if store.areas.isEmpty {
                        Text("No areas are listed yet. Pick a gym or request one.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(cityGroups, id: \.city) { group in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(group.city.uppercased())
                                    .font(FormaFont.bodyFont(10, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(palette.textTertiary)
                                FlowLayout(spacing: Spacing.sm) {
                                    ForEach(group.areas) { area in
                                        FormaChip(
                                            label: area.area,
                                            selected: store.preferences?.area == area.area && store.preferences?.city == area.city
                                        ) {
                                            Task { await chooseArea(area) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                FormaCard {
                    SectionHeader(title: "Request a gym")
                    FormaTextField(label: "Gym name", placeholder: "e.g. Fitness District", text: $requestName, capitalization: .words)
                    FormaTextField(label: "City", placeholder: "e.g. Chennai", text: $requestCity, capitalization: .words)
                    FormaTextField(label: "Area (optional)", placeholder: "e.g. Adyar", text: $requestArea, capitalization: .words)
                    FormaTextField(label: "Address (optional)", placeholder: "Street address", text: $requestAddress, capitalization: .words)

                    if let requestResult {
                        NoticeBanner(message: requestResult, systemImage: "checkmark.circle", accent: true)
                    }
                    if let actionError {
                        ErrorBanner(message: actionError)
                    }

                    PrimaryButton(
                        title: store.isBusy("request-gym") ? "Submitting" : "Submit gym request",
                        isLoading: store.isBusy("request-gym"),
                        isDisabled: requestName.trimmingCharacters(in: .whitespaces).count < 2 || requestCity.trimmingCharacters(in: .whitespaces).count < 2
                    ) {
                        Task { await submitRequest() }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Gym and area")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.searchGyms(query: query)
            if store.areas.isEmpty {
                await store.loadBootstrap()
            }
        }
        .confirmationDialog("Leave this gym community?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave gym", role: .destructive) {
                Task {
                    let ok = await store.leaveGym()
                    if !ok { actionError = store.actionError }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You stay in your area group unless you change it. Your connections and messages are not removed.")
        }
    }

    private struct CityGroup {
        var city: String
        var areas: [CommunityArea]
    }

    private var cityGroups: [CityGroup] {
        Dictionary(grouping: store.areas, by: \.city)
            .map { CityGroup(city: $0.key, areas: $0.value.sorted { $0.area < $1.area }) }
            .sorted { $0.city < $1.city }
    }

    private func gymRow(_ gym: GymSummary) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 15))
                .foregroundStyle(palette.accentText)
                .frame(width: 34, height: 34)
                .background(palette.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(gym.name)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text([gym.area, gym.city].compactMap { $0 }.joined(separator: ", "))
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                HStack(spacing: Spacing.sm) {
                    TagLabel(
                        text: gym.verificationStatus == "verified" ? "Verified" : "Awaiting review",
                        color: gym.verificationStatus == "verified" ? palette.success : palette.warning
                    )
                    Text("\(gym.memberCount) members")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Spacing.sm)

            if store.membership?.gymID == gym.id {
                TagLabel(text: "Current", color: palette.textSecondary)
            } else {
                Button {
                    Task {
                        actionError = nil
                        let ok = await store.joinGym(gym)
                        if !ok { actionError = store.actionError }
                    }
                } label: {
                    Group {
                        if store.isBusy("join-gym") {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Join")
                                .font(FormaFont.bodyFont(12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(palette.accent, in: Capsule())
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(store.isBusy("join-gym"))
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func chooseArea(_ area: CommunityArea) async {
        actionError = nil
        let ok = await store.setArea(city: area.city, area: area.area)
        if !ok { actionError = store.actionError }
    }

    private func submitRequest() async {
        requestResult = nil
        actionError = nil
        let result = await store.requestGym(
            name: requestName.trimmingCharacters(in: .whitespacesAndNewlines),
            city: requestCity.trimmingCharacters(in: .whitespacesAndNewlines),
            area: requestArea.isEmpty ? nil : requestArea.trimmingCharacters(in: .whitespacesAndNewlines),
            address: requestAddress.isEmpty ? nil : requestAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let result else {
            actionError = store.actionError ?? "The gym request could not be submitted."
            return
        }
        if result.created {
            requestResult = "Submitted. This gym is visible in your search while it waits for review."
        } else if result.status == "verified" {
            requestResult = "That gym already exists and is verified. Search for it to join."
        } else {
            requestResult = "That gym already exists and is waiting for review."
        }
        requestName = ""
        requestCity = ""
        requestArea = ""
        requestAddress = ""
    }
}
