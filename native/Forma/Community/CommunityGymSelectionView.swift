import CoreLocation
import SwiftUI

// MARK: - Gym and area selection

struct CommunityGymSelectionView: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette

    private enum Mode: String, CaseIterable, Identifiable {
        case nearMe
        case search
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nearMe: "Near me"
            case .search: "Search"
            case .manual: "Manual"
            }
        }
    }

    @State private var mode: Mode = .search
    @State private var query = ""
    @State private var searchCountry = ""
    @State private var searchCity = ""
    @State private var requestName = ""
    @State private var requestCity = ""
    @State private var requestArea = ""
    @State private var requestAddress = ""
    @State private var requestState = ""
    @State private var requestCountry = ""
    @State private var requestPostal = ""
    @State private var requestResult: String?
    @State private var actionError: String?
    @State private var confirmRemove: CommunityMembership?
    @State private var confirmLeave = false
    @State private var detailGym: GymSummary?
    @State private var locationService: GymLocationService?
    @State private var locating = false
    @State private var locationError: String?
    @State private var lastCoordinate: CLLocationCoordinate2D?

    private let radii = [2, 5, 10, 25, 50]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Your gyms power Community matching. Choosing one never uses GPS, never confirms attendance and never reveals where you are to another member.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                membershipCard

                Picker("How to find your gym", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newMode in
                    if newMode == .search, store.gymResults.isEmpty {
                        Task { await store.searchGyms(query: query, country: searchCountry, city: searchCity) }
                    }
                }

                switch mode {
                case .nearMe: nearMeSection
                case .search: searchSection
                case .manual: manualSection
                }

                if let actionError {
                    ErrorBanner(message: actionError)
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Gyms")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadGymProviderStatus()
            if store.gymResults.isEmpty {
                await store.searchGyms(query: query)
            }
            if store.areas.isEmpty {
                await store.loadBootstrap()
            }
        }
        .sheet(item: $detailGym) { gym in
            GymDetailSheet(store: store, gym: gym)
        }
        .confirmationDialog(
            confirmRemove.map { "Remove \($0.gymName)?" } ?? "Remove gym?",
            isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove gym", role: .destructive) {
                guard let membership = confirmRemove else { return }
                confirmRemove = nil
                Task {
                    actionError = nil
                    if !(await store.removeMembership(gymID: membership.gymID)) {
                        actionError = store.actionError
                    }
                }
            }
            Button("Cancel", role: .cancel) { confirmRemove = nil }
        } message: {
            Text("Your profile, connections and messages stay. If this was your primary gym, another of your gyms becomes primary.")
        }
        .confirmationDialog("Leave every gym community?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave all gyms", role: .destructive) {
                Task {
                    actionError = nil
                    if !(await store.leaveGym()) {
                        actionError = store.actionError
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You stay in your area group unless you change it. Your connections and messages are not removed.")
        }
    }

    // MARK: - Current selection

    private var membershipCard: some View {
        FormaCard(style: .raised) {
            SectionHeader(title: "Current gyms")
            if store.memberships.isEmpty {
                Text("No gym selected yet. Pick one below, or continue without a gym and use area or global discovery.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(store.memberships.enumerated()), id: \.element.id) { index, membership in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(membership.gymName)
                                    .font(FormaFont.bodyFont(15, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                if !membership.locationText.isEmpty {
                                    Text(membership.locationText)
                                        .font(FormaFont.bodyFont(12))
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            Spacer(minLength: Spacing.sm)
                            Button {
                                confirmRemove = membership
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(membership.gymName)")
                        }
                        HStack(spacing: Spacing.sm) {
                            if membership.isPrimary {
                                TagLabel(text: "Primary", color: palette.accentText)
                            }
                            TagLabel(text: membership.membershipTypeTitle, color: palette.textSecondary)
                            TagLabel(text: visibilityTitle(membership.visibility), color: palette.textSecondary)
                            if membership.verificationStatus != "verified" {
                                TagLabel(text: "Awaiting review", color: palette.warning)
                            }
                        }
                    }
                    if index < store.memberships.count - 1 {
                        FormaDivider()
                    }
                }
                if store.memberships.count > 1 {
                    SecondaryButton(title: "Leave every gym", destructive: true) {
                        confirmLeave = true
                    }
                }
            }
        }
    }

    private func visibilityTitle(_ value: String) -> String {
        switch value {
        case "private": "Hidden membership"
        case "public": "Public membership"
        default: "Members-only"
        }
    }

    // MARK: - Near me

    private var nearMeSection: some View {
        FormaCard {
            SectionHeader(title: "Find gyms near me")
            Text("Forma asks for location only when you tap the button below, uses a single one-time fix and stops. The coordinate is sent to the gym directory to measure distance and is never stored on your profile or shown to members.")
                .font(FormaFont.bodyFont(11))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(radii, id: \.self) { radius in
                        FormaChip(label: "\(radius) km", selected: store.nearbyRadiusKm == radius) {
                            store.nearbyRadiusKm = radius
                            Task { await rerunNearbySearch() }
                        }
                    }
                }
            }
            .scrollClipDisabled()

            if locating {
                LoadingCard(label: "Finding your location")
            } else {
                PrimaryButton(title: lastCoordinate == nil ? "Find gyms near me" : "Search again") {
                    Task { await findNearbyGyms() }
                }
            }

            if let locationError {
                ErrorBanner(message: locationError)
                Text("You can always use Search or Manual instead; neither needs location permission.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.nearbyLoading {
                LoadingCard(label: "Looking nearby")
            } else if let error = store.nearbyError {
                ErrorBanner(message: error) {
                    Task { await rerunNearbySearch() }
                }
            } else if !store.nearbyGyms.isEmpty {
                ForEach(store.nearbyGyms) { gym in
                    gymRow(gym)
                    if gym.id != store.nearbyGyms.last?.id {
                        FormaDivider()
                    }
                }
                if let attribution = store.gymProviderStatus?.attribution {
                    Text(attribution)
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
            } else if lastCoordinate != nil {
                Text("No gyms were found within \(store.nearbyRadiusKm) km. Widen the radius or add the gym manually.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func findNearbyGyms() async {
        locating = true
        locationError = nil
        store.clearNearbyGyms()
        let service = locationService ?? GymLocationService()
        locationService = service
        do {
            let coordinate = try await service.currentCoordinate()
            lastCoordinate = coordinate
            await store.loadNearbyGyms(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            locationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        locating = false
    }

    private func rerunNearbySearch() async {
        guard let lastCoordinate else { return }
        await store.loadNearbyGyms(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
    }

    // MARK: - Search

    private var searchSection: some View {
        FormaCard {
            SectionHeader(title: "Search worldwide")
            FormaTextField(placeholder: "Gym name, area or postcode", text: $query, capitalization: .words)
                .onChange(of: query) { _, value in
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        await store.searchGyms(query: value, country: searchCountry, city: searchCity)
                    }
                }

            HStack(spacing: Spacing.md) {
                FormaTextField(
                    label: "Country (optional)",
                    placeholder: "e.g. India or IN",
                    text: $searchCountry,
                    capitalization: .words
                )
                FormaTextField(
                    label: "City (optional)",
                    placeholder: "e.g. Chennai",
                    text: $searchCity,
                    capitalization: .words
                )
            }

            SecondaryButton(title: "Apply filters", systemImage: "line.3.horizontal.decrease.circle") {
                Task { await store.searchGyms(query: query, country: searchCountry, city: searchCity) }
            }

            if let status = store.gymProviderStatus, !status.configured, let reason = status.reason {
                Text(reason)
                    .font(FormaFont.bodyFont(10))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = store.gymSearchError {
                ErrorBanner(message: error) {
                    Task { await store.searchGyms(query: query, country: searchCountry, city: searchCity) }
                }
            }

            if store.gymSearchLoading {
                LoadingCard(label: "Searching gyms")
            } else if store.gymResults.isEmpty {
                Text("No gyms match. Try a different country or city, or add the gym in Manual.")
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
                if store.gymHasMore {
                    SecondaryButton(title: "Load more gyms", systemImage: "arrow.down.circle") {
                        Task { await store.loadMoreGyms() }
                    }
                }
            }
        }
    }

    // MARK: - Manual

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            FormaCard {
                SectionHeader(title: "Choose an area")
                Text("Areas come from the community directory and are never mapped to an exact location.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                if store.areas.isEmpty {
                    Text("No areas are listed yet. Pick a gym or request one below.")
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
                SectionHeader(title: "Add a gym")
                Text("If your gym is missing, submit it here. It appears in your search right away and for everyone once a moderator confirms the details.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                FormaTextField(label: "Gym name", placeholder: "e.g. Fitness District", text: $requestName, capitalization: .words)
                FormaTextField(label: "City", placeholder: "e.g. Chennai", text: $requestCity, capitalization: .words)
                FormaTextField(label: "Country", placeholder: "e.g. India", text: $requestCountry, capitalization: .words)
                FormaTextField(label: "Area (optional)", placeholder: "e.g. Adyar", text: $requestArea, capitalization: .words)
                FormaTextField(label: "Address (optional)", placeholder: "Street address", text: $requestAddress, capitalization: .words)
                FormaTextField(label: "State or region (optional)", placeholder: "e.g. Tamil Nadu", text: $requestState, capitalization: .words)
                FormaTextField(label: "Postcode (optional)", placeholder: "e.g. 600020", text: $requestPostal, capitalization: .characters)

                if let requestResult {
                    NoticeBanner(message: requestResult, systemImage: "checkmark.circle", accent: true)
                }

                PrimaryButton(
                    title: store.isBusy("request-gym") ? "Submitting" : "Submit gym request",
                    isLoading: store.isBusy("request-gym"),
                    isDisabled: trimmed(requestName).count < 2 || trimmed(requestCity).count < 2
                ) {
                    Task { await submitRequest() }
                }
            }
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

    // MARK: - Shared row

    private func gymRow(_ gym: GymSummary) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 15))
                .foregroundStyle(palette.accentText)
                .frame(width: 34, height: 34)
                .background(palette.accentSoft, in: Circle())

            Button {
                detailGym = gym
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(gym.name)
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                    if !gym.locationText.isEmpty {
                        Text(gym.locationText)
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: Spacing.sm) {
                        TagLabel(
                            text: gym.statusTitle,
                            color: gym.isVerified ? palette.success : (gym.isImported ? palette.accentText : palette.warning)
                        )
                        Text("\(gym.memberCount) members")
                            .font(FormaFont.bodyFont(10))
                            .foregroundStyle(palette.textTertiary)
                        if let distance = gym.distanceText {
                            Text(distance)
                                .font(FormaFont.bodyFont(10))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: Spacing.sm)

            gymAction(gym)
        }
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private func gymAction(_ gym: GymSummary) -> some View {
        let membership = store.memberships.first { $0.gymID == gym.id }
        if store.isBusy("join-gym") || (membership.map { store.isBusy("remove-membership-\($0.gymID)") } ?? false) {
            ProgressView().controlSize(.mini)
        } else if let membership {
            Button {
                confirmRemove = membership
            } label: {
                TagLabel(text: membership.isPrimary ? "Primary" : "Added", color: palette.textSecondary)
            }
            .buttonStyle(.plain)
        } else if store.memberships.isEmpty {
            Button {
                Task { await join(gym, asPrimary: true) }
            } label: {
                capsuleLabel("Choose")
            }
            .buttonStyle(PressableScaleStyle())
        } else {
            Menu {
                Button("Set as my primary gym") {
                    Task { await join(gym, asPrimary: true) }
                }
                Button("Add to my gyms") {
                    Task { await join(gym, asPrimary: false) }
                }
            } label: {
                capsuleLabel("Add")
            }
        }
    }

    private func capsuleLabel(_ title: String) -> some View {
        Text(title)
            .font(FormaFont.bodyFont(12, weight: .semibold))
            .foregroundStyle(palette.accentInk)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(palette.accent, in: Capsule())
    }

    // MARK: - Actions

    private func join(_ gym: GymSummary, asPrimary: Bool) async {
        actionError = nil
        if !(await store.joinGym(gym, asPrimary: asPrimary)) {
            actionError = store.actionError
        }
    }

    private func chooseArea(_ area: CommunityArea) async {
        actionError = nil
        if !(await store.setArea(city: area.city, area: area.area)) {
            actionError = store.actionError
        }
    }

    private func submitRequest() async {
        requestResult = nil
        actionError = nil
        let result = await store.requestGym(
            name: trimmed(requestName),
            city: trimmed(requestCity),
            area: requestArea.isEmpty ? nil : trimmed(requestArea),
            address: requestAddress.isEmpty ? nil : trimmed(requestAddress),
            state: requestState.isEmpty ? nil : trimmed(requestState),
            country: requestCountry.isEmpty ? nil : trimmed(requestCountry),
            postalCode: requestPostal.isEmpty ? nil : trimmed(requestPostal)
        )
        guard let result else {
            actionError = store.actionError ?? "The gym request could not be submitted."
            return
        }
        if result.created {
            requestResult = "Submitted. This gym is visible in your search while it waits for review."
        } else if result.status == "verified" || result.status == "imported" {
            requestResult = "That gym already exists. Search for it to choose it."
        } else {
            requestResult = "That gym already exists and is waiting for review."
        }
        requestName = ""
        requestCity = ""
        requestArea = ""
        requestAddress = ""
        requestState = ""
        requestCountry = ""
        requestPostal = ""
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Gym detail

private struct GymDetailSheet: View {
    var store: CommunityStore
    var gym: GymSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var reason: GymReportReason = .incorrectDetails
    @State private var details = ""
    @State private var reported = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(gym.name)
                            .font(FormaFont.displayFont(22, weight: .semibold))
                            .foregroundStyle(palette.text)
                        if !gym.locationText.isEmpty {
                            Text(gym.locationText)
                                .font(FormaFont.bodyFont(13))
                                .foregroundStyle(palette.textSecondary)
                        }
                        HStack(spacing: Spacing.sm) {
                            TagLabel(
                                text: gym.statusTitle,
                                color: gym.isVerified ? palette.success : (gym.isImported ? palette.accentText : palette.warning)
                            )
                            Text("\(gym.memberCount) members")
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }

                    FormaCard {
                        if let address = gym.address { KeyValueRow(label: "Address", value: address) }
                        if let postal = gym.postalCode { KeyValueRow(label: "Postcode", value: postal) }
                        if let website = gym.website { KeyValueRow(label: "Website", value: website) }
                        if let phone = gym.phone { KeyValueRow(label: "Phone", value: phone) }
                        KeyValueRow(label: "Source", value: sourceTitle)
                        if let attribution = store.gymProviderStatus?.attribution, gym.providerName != nil {
                            Text(attribution)
                                .font(FormaFont.bodyFont(10))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Text(gym.isVerified
                            ? "A moderator confirmed this listing."
                            : (gym.isImported
                                ? "Imported from a public gym directory. It has not been checked by a member yet."
                                : "Submitted by a member and still awaiting review."))
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FormaCard {
                        SectionHeader(title: "Report this listing")
                        Text("Reports go to moderators and are never shown to the person who submitted the gym.")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Picker("Reason", selection: $reason) {
                            ForEach(GymReportReason.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        FormaTextField(label: "Details (optional)", placeholder: "What is wrong with this listing?", text: $details)
                        if reported {
                            NoticeBanner(message: "Report received.", systemImage: "checkmark.circle", accent: true)
                        }
                        if let error {
                            ErrorBanner(message: error)
                        }
                        SecondaryButton(title: "Submit report", destructive: true) {
                            Task {
                                error = nil
                                let ok = await store.reportGym(
                                    gym,
                                    reason: reason,
                                    details: details.isEmpty ? nil : details
                                )
                                if ok {
                                    reported = true
                                    details = ""
                                } else {
                                    error = store.actionError ?? "The report could not be submitted."
                                }
                            }
                        }
                        .disabled(reported)
                    }
                }
                .padding(Spacing.xl)
            }
            .background(FormaBackground())
            .navigationTitle("Gym details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var sourceTitle: String {
        switch gym.source {
        case "google": "Google Places"
        case "osm": "OpenStreetMap"
        case "user": "Member submission"
        default: "Forma"
        }
    }
}
