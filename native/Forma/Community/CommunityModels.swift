import Foundation

// MARK: - Primitives

enum CommunityScope: String, CaseIterable, Identifiable, Hashable {
    case gym
    case area
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gym: "My gym"
        case .area: "Nearby"
        case .all: "Everyone"
        }
    }

    var detail: String {
        switch self {
        case .gym: "Members who selected the same gym as you."
        case .area: "Members in your area or a neighbouring area group."
        case .all: "Members who chose to be discoverable, wherever they train."
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
    var nearbyDiscovery: Bool
    var allowConnectionRequests: Bool
    var allowMessages: Bool
    var city: String?
    var area: String?
    var notifyConnections: Bool
    var notifyMessages: Bool
    var notifyComments: Bool
    var notifyLikes: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case discoverable
        case showGym = "show_gym"
        case showArea = "show_area"
        case nearbyDiscovery = "nearby_discovery"
        case allowConnectionRequests = "allow_connection_requests"
        case allowMessages = "allow_messages"
        case city
        case area
        case notifyConnections = "notify_connections"
        case notifyMessages = "notify_messages"
        case notifyComments = "notify_comments"
        case notifyLikes = "notify_likes"
    }
}

struct CommunityMembership: Codable, Hashable {
    var gymID: String
    var gymName: String
    var address: String?
    var city: String
    var area: String?
    var verificationStatus: String

    enum CodingKeys: String, CodingKey {
        case gymID = "gym_id"
        case gymName = "gym_name"
        case address
        case city
        case area
        case verificationStatus = "verification_status"
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
    var city: String
    var state: String?
    var country: String?
    var area: String?
    var verificationStatus: String
    var memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case city
        case state
        case country
        case area
        case verificationStatus = "verification_status"
        case memberCount = "member_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decode(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        verificationStatus = try container.decode(String.self, forKey: .verificationStatus)
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
    }
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

// MARK: - Bootstrap

struct CommunityBootstrap: Codable, Hashable {
    var profile: CommunityProfile?
    var preferences: CommunityPreferences?
    var membership: CommunityMembership?
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
    var city: String
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
