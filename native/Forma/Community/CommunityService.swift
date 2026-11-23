import Foundation

/// Everything the Community feature needs from the backend. Every method maps
/// to an authenticated route on the Forma backend; the client never writes
/// community tables directly, so blocks, age rules, suspension, privacy and
/// admin checks are all enforced server-side.
protocol CommunityServicing: AnyObject {
    func communityBootstrap() async throws -> CommunityBootstrap
    func communityDiscover(scope: CommunityScope, query: String, interest: String, limit: Int, offset: Int) async throws -> [CommunityMember]
    func communitySearchGyms(query: String, limit: Int, offset: Int) async throws -> [GymSummary]
    func communityRequestGym(name: String, city: String, area: String?, address: String?) async throws -> GymRequestResult
    func communityJoinGym(id: String) async throws
    func communityLeaveGym() async throws
    func communitySetArea(city: String, area: String) async throws
    func communitySaveProfile(username: String, displayName: String, bio: String?, interests: [String], categories: [String], avatarURL: String?, age: Int?) async throws -> CommunityProfile
    func communityUploadAvatar(data: Data) async throws -> String
    func communitySavePreferences(_ preferences: CommunityPreferences) async throws -> CommunityPreferences
    func communitySendConnectionRequest(target: String) async throws -> ConnectionRequestResult
    func communityRespondToConnection(id: String, accept: Bool) async throws -> ConnectionResponseResult
    func communityRemoveConnection(id: String) async throws
    func communityBlock(target: String, blocked: Bool) async throws
    func communityConnections() async throws -> [CommunityConnection]
    func communityBlockedMembers() async throws -> [BlockedMember]
    func communityPublicProfile(userID: String) async throws -> CommunityPublicProfile?
    func communityFeed(filter: CommunityFeedFilter, limit: Int, offset: Int) async throws -> [CommunityPost]
    func communityCreatePost(id: String, content: String, kind: CommunityPostKind, sessionID: String?, achievementLabel: String?) async throws -> CommunityCreatedPost
    func communityUpdatePost(id: String, content: String) async throws
    func communityDeletePost(id: String) async throws
    func communityToggleLike(postID: String, liked: Bool) async throws -> CommunityLikeResult
    func communityComments(postID: String, limit: Int, offset: Int) async throws -> [CommunityComment]
    func communityAddComment(id: String, postID: String, content: String) async throws -> CommunityCreatedPost
    func communityDeleteComment(id: String) async throws
    func communityHidePost(id: String, hidden: Bool) async throws
    func communityConversations() async throws -> [CommunityConversation]
    func communityMessages(conversationID: String, before: Date?, limit: Int) async throws -> [CommunityMessage]
    func communitySendMessage(id: String, conversationID: String, body: String) async throws -> CommunitySendMessageResult
    func communityMarkConversationRead(id: String) async throws
    func communityMuteConversation(id: String, muted: Bool) async throws
    func communityReport(targetType: CommunityReportTarget, targetID: String, reason: CommunityReportReason, details: String?) async throws -> CommunityReportResult
    func communityNotifications(limit: Int, offset: Int) async throws -> [CommunityNotification]
    func communityMarkNotificationsRead(ids: [String]?) async throws
    func communityNotificationStream(userID: String) -> AsyncStream<Void>

    // Admin moderation. These fail with a server error for non-admins; the app
    // is not the source of truth for the admin role.
    func communityAdminReports() async throws -> [CommunityModerationReport]
    func communityAdminSetSuspension(userID: String, suspended: Bool, reason: String?) async throws
    func communityAdminResolveReport(id: String, action: String, note: String?) async throws
    func communityAdminGyms() async throws -> [CommunityAdminGym]
    func communityAdminReviewGym(id: String, approve: Bool, note: String?) async throws
    func communityAdminAudit() async throws -> [CommunityAuditEntry]
}
