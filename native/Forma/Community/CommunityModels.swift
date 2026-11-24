import Foundation

// MARK: - Primitives

enum CommunityScope: String, CaseIterable, Identifiable, Hashable {
    case gym
    case area
    case city
    case region
    case country
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gym: "My gym"
        case .area: "Nearby"
        case .city: "City"
        case .region: "Region"
        case .country: "Country"
        case .global: "Global"
        }
    }

    var detail: String {
        switch self {
        case .gym: "Members who selected the same gym as you."
        case .area: "Members in your area or a neighbouring area group."
        case .city: "Members in your city who chose to share it."
        case .region: "Members whose primary gym is in the same region as yours."
        case .country: "Members in your country who chose to share it."
        case .global: "Discoverable members anywhere, matched by country, city, gym or interests."
        }
    }
}

enum CommunityFeedFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case connections
    case gym

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .connections: "Connections"
        case .gym: "My gym"
        }
    }
}

enum CommunityPostKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case update
    case workout
    case milestone
    case achievement
    case motivation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .update: "Update"
        case .workout: "Workout"
        case .milestone: "Milestone"
        case .achievement: "Achievement"
        case .motivation: "Motivation"
        }
    }
}

enum ConnectionStatus: String, Codable, Hashable {
    case none
    case pendingSent = "pending_sent"
    case pendingReceived = "pending_received"
    case accepted
    case blocked

    var title: String {
        switch self {
        case .none: "Not connected"
        case .pendingSent: "Request sent"
        case .pendingReceived: "Wants to connect"
        case .accepted: "Connected"
        case .blocked: "Blocked"
        }
    }
}

enum CommunityReportReason: String, CaseIterable, Identifiable, Hashable {
    case harassment
    case spam
    case inappropriate
    case impersonation
    case suspicious
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: "Harassment or bullying"
        case .spam: "Spam or advertising"
        case .inappropriate: "Inappropriate content"
        case .impersonation: "Impersonation"
        case .suspicious: "Suspicious behaviour"
        case .other: "Something else"
        }
    }
}

enum CommunityReportTarget: String, Hashable {
    case profile
    case post
    case comment
    case message
}

// MARK: - Profile and privacy

struct CommunityProfile: Codable, Hashable, Identifiable {
    var userID: String
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: String?
    var interests: [String]
    var workoutCategories: [String]
    var achievementsOptIn: Bool
    var createdAt: Date?
    var updatedAt: Date?

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case interests
        case workoutCategories = "workout_categories"
        case achievementsOptIn = "achievements_opt_in"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityPreferences: Codable, Hashable {
    var userID: String
    var discoverable: Bool
    var showGym: Bool
    var showArea: Bool
    var showCity: Bool
    var showCountry: Bool
    var nearbyDiscovery: Bool
    var globalDiscovery: Bool
    var allowConnectionRequests: Bool
    var allowMessages: Bool
    var city: String?
    var area: String?
    var country: String?
    var countryCode: String?
    var notifyConnections: Bool
    var notifyMessages: Bool
    var notifyComments: Bool
    var notifyLikes: Bool

    init(
        userID: String,
        discoverable: Bool,
        showGym: Bool,
        showArea: Bool,
        showCity: Bool = true,
        showCountry: Bool = true,
        nearbyDiscovery: Bool,
        globalDiscovery: Bool = true,
        allowConnectionRequests: Bool,
        allowMessages: Bool,
        city: String?,
        area: String?,
        country: String? = nil,
        countryCode: String? = nil,
        notifyConnections: Bool,
        notifyMessages: Bool,
        notifyComments: Bool,
        notifyLikes: Bool
    ) {
        self.userID = userID
        self.discoverable = discoverable
        self.showGym = showGym
        self.showArea = showArea
        self.showCity = showCity
        self.showCountry = showCountry
        self.nearbyDiscovery = nearbyDiscovery
        self.globalDiscovery = globalDiscovery
        self.allowConnectionRequests = allowConnectionRequests
        self.allowMessages = allowMessages
        self.city = city
        self.area = area
        self.country = country
        self.countryCode = countryCode
        self.notifyConnections = notifyConnections
        self.notifyMessages = notifyMessages
        self.notifyComments = notifyComments
        self.notifyLikes = notifyLikes
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case discoverable
        case showGym = "show_gym"
        case showArea = "show_area"
        case showCity = "show_city"
        case showCountry = "show_country"
        case nearbyDiscovery = "nearby_discovery"
        case globalDiscovery = "global_discovery"
        case allowConnectionRequests = "allow_connection_requests"
        case allowMessages = "allow_messages"
        case city
        case area
        case country
        case countryCode = "country_code"
        case notifyConnections = "notify_connections"
        case notifyMessages = "notify_messages"
        case notifyComments = "notify_comments"
        case notifyLikes = "notify_likes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        discoverable = try container.decodeIfPresent(Bool.self, forKey: .discoverable) ?? false
        showGym = try container.decodeIfPresent(Bool.self, forKey: .showGym) ?? true
        showArea = try container.decodeIfPresent(Bool.self, forKey: .showArea) ?? true
        showCity = try container.decodeIfPresent(Bool.self, forKey: .showCity) ?? showArea
        showCountry = try container.decodeIfPresent(Bool.self, forKey: .showCountry) ?? true
        nearbyDiscovery = try container.decodeIfPresent(Bool.self, forKey: .nearbyDiscovery) ?? false
        globalDiscovery = try container.decodeIfPresent(Bool.self, forKey: .globalDiscovery) ?? true
        allowConnectionRequests = try container.decodeIfPresent(Bool.self, forKey: .allowConnectionRequests) ?? true
        allowMessages = try container.decodeIfPresent(Bool.self, forKey: .allowMessages) ?? true
        city = try container.decodeIfPresent(String.self, forKey: .city)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        notifyConnections = try container.decodeIfPresent(Bool.self, forKey: .notifyConnections) ?? true
        notifyMessages = try container.decodeIfPresent(Bool.self, forKey: .notifyMessages) ?? true
        notifyComments = try container.decodeIfPresent(Bool.self, forKey: .notifyComments) ?? true
        notifyLikes = try container.decodeIfPresent(Bool.self, forKey: .notifyLikes) ?? true
    }
}

struct CommunityMembership: Codable, Hashable, Identifiable {
    var gymID: String
    var membershipID: String
    var gymName: String
    var address: String?
    var city: String?
    var area: String?
    var state: String?
    var country: String?
    var countryCode: String?
    var postalCode: String?
    var membershipType: String
    var isPrimary: Bool
    var visibility: String
    var verificationStatus: String

    var id: String { membershipID.isEmpty ? gymID : membershipID }

    enum CodingKeys: String, CodingKey {
        case gymID = "gym_id"
        case membershipID = "membership_id"
        case gymName = "gym_name"
        case address
        case city
        case area
        case state
        case country
        case countryCode = "country_code"
        case postalCode = "postal_code"
        case membershipType = "membership_type"
        case isPrimary = "is_primary"
        case visibility
        case verificationStatus = "verification_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gymID = try container.decode(String.self, forKey: .gymID)
        membershipID = try container.decodeIfPresent(String.self, forKey: .membershipID) ?? ""
        gymName = try container.decode(String.self, forKey: .gymName)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        postalCode = try container.decodeIfPresent(String.self, forKey: .postalCode)
        membershipType = try container.decodeIfPresent(String.self, forKey: .membershipType) ?? "member"
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? true
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "members"
        verificationStatus = try container.decode(String.self, forKey: .verificationStatus)
    }

    var locationText: String {
        [area, city, country].compactMap { $0 }.joined(separator: ", ")
    }

    var membershipTypeTitle: String {
        switch membershipType {
        case "day_pass": "Day pass"
        case "online": "Online"
        case "coach": "Coach"
        default: "Member"
        }
    }
}

// MARK: - Members and discovery

struct CommunityMember: Codable, Hashable, Identifiable {
    var userID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var bio: String?
    var interests: [String]
    var workoutCategories: [String]
    var gymName: String?
    var area: String?
    var city: String?
    var country: String?
    var countryCode: String?
    var connectionStatus: ConnectionStatus

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case interests
        case workoutCategories = "workout_categories"
        case gymName = "gym_name"
        case area
        case city
        case country
        case countryCode = "country_code"
        case connectionStatus = "connection_status"
    }

    init(
        userID: String,
        username: String,
        displayName: String,
        avatarURL: String?,
        bio: String?,
        interests: [String],
        workoutCategories: [String],
        gymName: String?,
        area: String?,
        city: String?,
        country: String? = nil,
        countryCode: String? = nil,
        connectionStatus: ConnectionStatus
    ) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
        self.interests = interests
        self.workoutCategories = workoutCategories
        self.gymName = gymName
        self.area = area
        self.city = city
        self.country = country
        self.countryCode = countryCode
        self.connectionStatus = connectionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        workoutCategories = try container.decodeIfPresent([String].self, forKey: .workoutCategories) ?? []
        gymName = try container.decodeIfPresent(String.self, forKey: .gymName)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
        connectionStatus = ConnectionStatus(rawValue: rawStatus ?? "") ?? .none
    }
}

struct CommunityPublicProfile: Codable, Hashable {
    var userID: String
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: String?
    var interests: [String]
    var workoutCategories: [String]
    var joinedAt: Date?
    var achievementsOptIn: Bool
    var gymName: String?
    var city: String?
    var area: String?
    var country: String?
    var countryCode: String?
    var connectionStatus: ConnectionStatus
    var sharedGym: Bool
    var sharedArea: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case interests
        case workoutCategories = "workout_categories"
        case joinedAt = "joined_at"
        case achievementsOptIn = "achievements_opt_in"
        case gymName = "gym_name"
        case city
        case area
        case country
        case countryCode = "country_code"
        case connectionStatus = "connection_status"
        case sharedGym = "shared_gym"
        case sharedArea = "shared_area"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        workoutCategories = try container.decodeIfPresent([String].self, forKey: .workoutCategories) ?? []
        joinedAt = try container.decodeIfPresent(Date.self, forKey: .joinedAt)
        achievementsOptIn = try container.decodeIfPresent(Bool.self, forKey: .achievementsOptIn) ?? false
        gymName = try container.decodeIfPresent(String.self, forKey: .gymName)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
        connectionStatus = ConnectionStatus(rawValue: rawStatus ?? "") ?? .none
        sharedGym = try container.decodeIfPresent(Bool.self, forKey: .sharedGym) ?? false
        sharedArea = try container.decodeIfPresent(Bool.self, forKey: .sharedArea) ?? false
    }
}

// MARK: - Gyms and areas

struct CommunityArea: Codable, Hashable, Identifiable {
    var city: String
    var area: String
    var nearbyGroup: String

    var id: String { "\(city)|\(area)" }

    enum CodingKeys: String, CodingKey {
        case city
        case area
        case nearbyGroup = "nearby_group"
    }
}

struct GymSummary: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var address: String?
    var city: String?
    var state: String?
    var country: String?
    var countryCode: String?
    var area: String?
    var postalCode: String?
    var latitude: Double?
    var longitude: Double?
    var website: String?
    var phone: String?
    var source: String
    var providerName: String?
    var verificationStatus: String
    var memberCount: Int
    var distanceKm: Double?
    var lastVerifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case city
        case state
        case country
        case countryCode = "country_code"
        case area
        case postalCode = "postal_code"
        case latitude
        case longitude
        case website
        case phone
        case source
        case providerName = "provider_name"
        case verificationStatus = "verification_status"
        case memberCount = "member_count"
        case distanceKm = "distance_km"
        case lastVerifiedAt = "last_verified_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        postalCode = try container.decodeIfPresent(String.self, forKey: .postalCode)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "forma"
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        verificationStatus = try container.decodeIfPresent(String.self, forKey: .verificationStatus) ?? "pending"
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
        lastVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
    }

    var isVerified: Bool { verificationStatus == "verified" }
    var isImported: Bool { verificationStatus == "imported" }

    var statusTitle: String {
        switch verificationStatus {
        case "verified": "Verified"
        case "imported": "Directory listing"
        default: "Awaiting review"
        }
    }

    var locationText: String {
        [area, city, state, country].compactMap { $0 }.joined(separator: ", ")
    }

    var distanceText: String? {
        guard let distanceKm else { return nil }
        if distanceKm < 1 {
            return "\(Int((distanceKm * 1000).rounded())) m away"
        }
        return String(format: "%.1f km away", distanceKm)
    }
}

struct GymProviderStatus: Codable, Hashable {
    var configured: Bool
    var name: String?
    var reason: String?
    var attribution: String?

    enum CodingKeys: String, CodingKey {
        case configured
        case name
        case reason
        case attribution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configured = try container.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        name = try container.decodeIfPresent(String.self, forKey: .name)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution)
    }
}

struct GymJoinOptions: Encodable {
    var isPrimary: Bool
    var membershipType: String
    var visibility: String
}

struct GymRequestResult: Codable, Hashable {
    var id: String
    var status: String
    var created: Bool
}

// MARK: - Connections

struct CommunityConnection: Codable, Hashable, Identifiable {
    var connectionID: String
    var userID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var status: String
    var direction: String
    var conversationID: String?
    var createdAt: Date?

    var id: String { connectionID }

    var isPending: Bool { status == "pending" }
    var isAccepted: Bool { status == "accepted" }
    var isIncoming: Bool { direction == "received" }

    enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case status
        case direction
        case conversationID = "conversation_id"
        case createdAt = "created_at"
    }
}

struct IncomingConnectionRequest: Codable, Hashable, Identifiable {
    var connectionID: String
    var userID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var createdAt: Date?

    var id: String { connectionID }

    enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}

struct ConnectionRequestResult: Codable, Hashable {
    var connectionID: String
    var status: String

    enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case status
    }
}

struct ConnectionResponseResult: Codable, Hashable {
    var connectionID: String
    var status: String
    var conversationID: String?

    enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case status
        case conversationID = "conversation_id"
    }
}

struct BlockedMember: Codable, Hashable, Identifiable {
    var userID: String
    var username: String?
    var displayName: String?
    var avatarURL: String?
    var blockedAt: Date?

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case blockedAt = "blocked_at"
    }
}

// MARK: - Feed

struct SharedSessionSummary: Codable, Hashable {
    var sessionID: String
    var title: String
    var startedAt: Date?
    var durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case title
        case startedAt = "started_at"
        case durationSeconds = "duration_seconds"
    }
}

struct CommunityPost: Codable, Hashable, Identifiable {
    var id: String
    var authorID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var content: String
    var kind: CommunityPostKind
    var achievementLabel: String?
    var likeCount: Int
    var commentCount: Int
    var liked: Bool
    var isOwn: Bool
    var sharedSession: SharedSessionSummary?
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case content
        case kind
        case achievementLabel = "achievement_label"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case liked
        case isOwn = "is_own"
        case sharedSession = "shared_session"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        authorID = try container.decode(String.self, forKey: .authorID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        content = try container.decode(String.self, forKey: .content)
        kind = CommunityPostKind(rawValue: try container.decode(String.self, forKey: .kind)) ?? .update
        achievementLabel = try container.decodeIfPresent(String.self, forKey: .achievementLabel)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        liked = try container.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        isOwn = try container.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
        sharedSession = try container.decodeIfPresent(SharedSessionSummary.self, forKey: .sharedSession)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct CommunityComment: Codable, Hashable, Identifiable {
    var id: String
    var postID: String
    var authorID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var content: String
    var isOwn: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case content
        case isOwn = "is_own"
        case createdAt = "created_at"
    }
}

struct CommunityLikeResult: Codable, Hashable {
    var liked: Bool
    var likeCount: Int
    var commentCount: Int

    enum CodingKeys: String, CodingKey {
        case liked
        case likeCount = "like_count"
        case commentCount = "comment_count"
    }
}

struct CommunityCreatedPost: Codable, Hashable {
    var id: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
    }
}

// MARK: - Messaging

struct CommunityConversation: Codable, Hashable, Identifiable {
    var conversationID: String
    var connectionID: String
    var userID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var lastMessage: String?
    var lastMessageAt: Date?
    var unreadCount: Int
    var muted: Bool

    var id: String { conversationID }

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case connectionID = "connection_id"
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
        case muted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        connectionID = try container.decode(String.self, forKey: .connectionID)
        userID = try container.decode(String.self, forKey: .userID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}

struct CommunityMessage: Codable, Hashable, Identifiable {
    var id: String
    var conversationID: String
    var senderID: String
    var body: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body
        case createdAt = "created_at"
    }
}

struct CommunitySendMessageResult: Codable, Hashable {
    var id: String
    var createdAt: Date
    var duplicate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case duplicate
    }
}

// MARK: - Notifications and reports

struct CommunityNotification: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var actorID: String?
    var actorUsername: String?
    var actorDisplayName: String?
    var actorAvatarURL: String?
    var entityID: String?
    var postID: String?
    var body: String
    var readAt: Date?
    var createdAt: Date

    var isUnread: Bool { readAt == nil }

    var title: String {
        switch kind {
        case "connection_request": "New connection request"
        case "connection_accepted": "Connection accepted"
        case "message": "New message"
        case "post_comment": "New comment"
        case "post_like": "New like"
        default: "Community activity"
        }
    }

    var systemImage: String {
        switch kind {
        case "connection_request", "connection_accepted": "person.2.fill"
        case "message": "bubble.left.fill"
        case "post_comment": "text.bubble.fill"
        case "post_like": "heart.fill"
        default: "bell.fill"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case actorID = "actor_id"
        case actorUsername = "actor_username"
        case actorDisplayName = "actor_display_name"
        case actorAvatarURL = "actor_avatar_url"
        case entityID = "entity_id"
        case postID = "post_id"
        case body
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

struct CommunityReportResult: Codable, Hashable {
    var id: String
    var status: String
}

enum GymReportReason: String, CaseIterable, Identifiable, Hashable {
    case incorrectDetails = "incorrect_details"
    case spam
    case inappropriate
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incorrectDetails: "Incorrect gym information"
        case .spam: "Spam or advertising"
        case .inappropriate: "Inappropriate content"
        case .other: "Something else"
        }
    }
}

// MARK: - Bootstrap

struct CommunityBootstrap: Codable, Hashable {
    var profile: CommunityProfile?
    var preferences: CommunityPreferences?
    var membership: CommunityMembership?
    var memberships: [CommunityMembership]
    var isAdmin: Bool
    var suspended: Bool
    var membersAtGym: Int
    var nearbyMembers: Int
    var incomingRequestCount: Int
    var unreadNotifications: Int
    var unreadMessages: Int
    var suggestions: [CommunityMember]
    var nearby: [CommunityMember]
    var incomingRequests: [IncomingConnectionRequest]
    var connections: [CommunityConnection]
    var feed: [CommunityPost]
    var areas: [CommunityArea]

    enum CodingKeys: String, CodingKey {
        case profile
        case preferences
        case membership
        case memberships
        case isAdmin = "is_admin"
        case suspended
        case membersAtGym = "members_at_gym"
        case nearbyMembers = "nearby_members"
        case incomingRequestCount = "incoming_request_count"
        case unreadNotifications = "unread_notifications"
        case unreadMessages = "unread_messages"
        case suggestions
        case nearby
        case incomingRequests = "incoming_requests"
        case connections
        case feed
        case areas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(CommunityProfile.self, forKey: .profile)
        preferences = try container.decodeIfPresent(CommunityPreferences.self, forKey: .preferences)
        membership = try container.decodeIfPresent(CommunityMembership.self, forKey: .membership)
        if let rows = try container.decodeIfPresent([CommunityMembership].self, forKey: .memberships) {
            memberships = rows
        } else if let membership {
            memberships = [membership]
        } else {
            memberships = []
        }
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        suspended = try container.decodeIfPresent(Bool.self, forKey: .suspended) ?? false
        membersAtGym = try container.decodeIfPresent(Int.self, forKey: .membersAtGym) ?? 0
        nearbyMembers = try container.decodeIfPresent(Int.self, forKey: .nearbyMembers) ?? 0
        incomingRequestCount = try container.decodeIfPresent(Int.self, forKey: .incomingRequestCount) ?? 0
        unreadNotifications = try container.decodeIfPresent(Int.self, forKey: .unreadNotifications) ?? 0
        unreadMessages = try container.decodeIfPresent(Int.self, forKey: .unreadMessages) ?? 0
        suggestions = try container.decodeIfPresent([CommunityMember].self, forKey: .suggestions) ?? []
        nearby = try container.decodeIfPresent([CommunityMember].self, forKey: .nearby) ?? []
        incomingRequests = try container.decodeIfPresent([IncomingConnectionRequest].self, forKey: .incomingRequests) ?? []
        connections = try container.decodeIfPresent([CommunityConnection].self, forKey: .connections) ?? []
        feed = try container.decodeIfPresent([CommunityPost].self, forKey: .feed) ?? []
        areas = try container.decodeIfPresent([CommunityArea].self, forKey: .areas) ?? []
    }
}

// MARK: - Admin moderation

struct CommunityModerationReport: Codable, Hashable, Identifiable {
    var id: String
    var reporterID: String
    var reporterUsername: String?
    var targetType: String
    var targetID: String
    var reason: String
    var details: String?
    var status: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case reporterID = "reporter_id"
        case reporterUsername = "reporter_username"
        case targetType = "target_type"
        case targetID = "target_id"
        case reason
        case details
        case status
        case createdAt = "created_at"
    }
}

struct CommunityAdminGym: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var city: String?
    var area: String?
    var address: String?
    var verificationStatus: String
    var submittedBy: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case city
        case area
        case address
        case verificationStatus = "verification_status"
        case submittedBy = "submitted_by"
        case createdAt = "created_at"
    }
}

struct CommunityAuditEntry: Codable, Hashable, Identifiable {
    var id: String
    var adminID: String
    var action: String
    var targetType: String
    var targetID: String?
    var note: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case adminID = "admin_id"
        case action
        case targetType = "target_type"
        case targetID = "target_id"
        case note
        case createdAt = "created_at"
    }
}

// MARK: - Errors

struct CommunityError: LocalizedError, Equatable {
    var message: String

    var errorDescription: String? { message }

    static let notConfigured = CommunityError(
        message: "Community needs the Forma backend. This build has no backend connection yet."
    )
}
