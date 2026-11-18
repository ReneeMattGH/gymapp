import Foundation
import Supabase

/// Everything the Community feature needs from the backend. Every method maps
/// to a security-definer RPC in `0007_community.sql`; the client never writes
/// community tables directly, so blocks, age rules, suspension, privacy and
/// admin checks are all enforced by Postgres.
protocol CommunityServicing: AnyObject {
    func communityBootstrap() async throws -> CommunityBootstrap
    func communityDiscover(scope: CommunityScope, query: String, interest: String, limit: Int, offset: Int) async throws -> [CommunityMember]
    func communitySearchGyms(query: String, limit: Int, offset: Int) async throws -> [GymSummary]
    func communityRequestGym(name: String, city: String, area: String?, address: String?) async throws -> GymRequestResult
    func communityJoinGym(id: String) async throws
    func communityLeaveGym() async throws
    func communitySetArea(city: String, area: String) async throws
    func communitySaveProfile(username: String, displayName: String, bio: String?, interests: [String], categories: [String], avatarURL: String?) async throws -> CommunityProfile
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

extension SupabaseService: CommunityServicing {
    func communityBootstrap() async throws -> CommunityBootstrap {
        try await communityRPC("community_bootstrap", [:])
    }

    func communityDiscover(
        scope: CommunityScope,
        query: String,
        interest: String,
        limit: Int,
        offset: Int
    ) async throws -> [CommunityMember] {
        try await communityRPC("community_discover", [
            "p_scope": .string(scope.rawValue),
            "p_query": .string(query),
            "p_interest": .string(interest),
            "p_limit": .integer(limit),
            "p_offset": .integer(offset),
        ])
    }

    func communitySearchGyms(query: String, limit: Int, offset: Int) async throws -> [GymSummary] {
        try await communityRPC("community_search_gyms", [
            "p_query": .string(query),
            "p_limit": .integer(limit),
            "p_offset": .integer(offset),
        ])
    }

    func communityRequestGym(name: String, city: String, area: String?, address: String?) async throws -> GymRequestResult {
        try await communityRPC("community_request_gym", [
            "p_name": .string(name),
            "p_city": .string(city),
            "p_area": area.map(AnyJSON.string) ?? .null,
            "p_address": address.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityJoinGym(id: String) async throws {
        _ = try await communityRPCVoid("community_join_gym", ["p_gym_id": .string(id)])
    }

    func communityLeaveGym() async throws {
        _ = try await communityRPCVoid("community_leave_gym", [:])
    }

    func communitySetArea(city: String, area: String) async throws {
        _ = try await communityRPCVoid("community_set_area", [
            "p_city": .string(city),
            "p_area": .string(area),
        ])
    }

    func communitySaveProfile(
        username: String,
        displayName: String,
        bio: String?,
        interests: [String],
        categories: [String],
        avatarURL: String?
    ) async throws -> CommunityProfile {
        try await communityRPC("community_save_profile", [
            "p_username": .string(username),
            "p_display_name": .string(displayName),
            "p_bio": bio.map(AnyJSON.string) ?? .null,
            "p_interests": .array(interests.map(AnyJSON.string)),
            "p_categories": .array(categories.map(AnyJSON.string)),
            "p_avatar_url": avatarURL.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityUploadAvatar(data: Data) async throws -> String {
        guard let userID = client.auth.currentUser?.id.uuidString else {
            throw CommunityError(message: "Sign in to upload a photo.")
        }
        let path = "\(userID)/avatar-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            _ = try await client.storage.from("community-avatars").upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
            return try client.storage.from("community-avatars").getPublicURL(path: path).absoluteString
        } catch {
            throw Self.communityError(error)
        }
    }

    func communitySavePreferences(_ preferences: CommunityPreferences) async throws -> CommunityPreferences {
        try await communityRPC("community_save_preferences", [
            "p_discoverable": .bool(preferences.discoverable),
            "p_show_gym": .bool(preferences.showGym),
            "p_show_area": .bool(preferences.showArea),
            "p_nearby_discovery": .bool(preferences.nearbyDiscovery),
            "p_allow_connection_requests": .bool(preferences.allowConnectionRequests),
            "p_allow_messages": .bool(preferences.allowMessages),
            "p_notify_connections": .bool(preferences.notifyConnections),
            "p_notify_messages": .bool(preferences.notifyMessages),
            "p_notify_comments": .bool(preferences.notifyComments),
            "p_notify_likes": .bool(preferences.notifyLikes),
        ])
    }

    func communitySendConnectionRequest(target: String) async throws -> ConnectionRequestResult {
        try await communityRPC("community_send_connection_request", ["p_target": .string(target)])
    }

    func communityRespondToConnection(id: String, accept: Bool) async throws -> ConnectionResponseResult {
        try await communityRPC("community_respond_connection", [
            "p_connection_id": .string(id),
            "p_accept": .bool(accept),
        ])
    }

    func communityRemoveConnection(id: String) async throws {
        _ = try await communityRPCVoid("community_remove_connection", ["p_connection_id": .string(id)])
    }

    func communityBlock(target: String, blocked: Bool) async throws {
        _ = try await communityRPCVoid("community_block", [
            "p_target": .string(target),
            "p_block": .bool(blocked),
        ])
    }

    func communityConnections() async throws -> [CommunityConnection] {
        try await communityRPC("community_connections_list", [:])
    }

    func communityBlockedMembers() async throws -> [BlockedMember] {
        try await communityRPC("community_blocked_members", [:])
    }

    func communityPublicProfile(userID: String) async throws -> CommunityPublicProfile? {
        try await communityRPC("community_public_profile", ["p_user": .string(userID)])
    }

    func communityFeed(filter: CommunityFeedFilter, limit: Int, offset: Int) async throws -> [CommunityPost] {
        try await communityRPC("community_feed", [
            "p_filter": .string(filter.rawValue),
            "p_limit": .integer(limit),
            "p_offset": .integer(offset),
        ])
    }

    func communityCreatePost(
        id: String,
        content: String,
        kind: CommunityPostKind,
        sessionID: String?,
        achievementLabel: String?
    ) async throws -> CommunityCreatedPost {
        try await communityRPC("community_create_post", [
            "p_id": .string(id),
            "p_content": .string(content),
            "p_kind": .string(kind.rawValue),
            "p_session_id": sessionID.map(AnyJSON.string) ?? .null,
            "p_achievement_label": achievementLabel.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityUpdatePost(id: String, content: String) async throws {
        _ = try await communityRPCVoid("community_update_post", [
            "p_id": .string(id),
            "p_content": .string(content),
        ])
    }

    func communityDeletePost(id: String) async throws {
        _ = try await communityRPCVoid("community_delete_post", ["p_id": .string(id)])
    }

    func communityToggleLike(postID: String, liked: Bool) async throws -> CommunityLikeResult {
        try await communityRPC("community_toggle_like", [
            "p_post_id": .string(postID),
            "p_like": .bool(liked),
        ])
    }

    func communityComments(postID: String, limit: Int, offset: Int) async throws -> [CommunityComment] {
        try await communityRPC("community_comments_list", [
            "p_post_id": .string(postID),
            "p_limit": .integer(limit),
            "p_offset": .integer(offset),
        ])
    }

    func communityAddComment(id: String, postID: String, content: String) async throws -> CommunityCreatedPost {
        try await communityRPC("community_add_comment", [
            "p_id": .string(id),
            "p_post_id": .string(postID),
            "p_content": .string(content),
        ])
    }

    func communityDeleteComment(id: String) async throws {
        _ = try await communityRPCVoid("community_delete_comment", ["p_id": .string(id)])
    }

    func communityHidePost(id: String, hidden: Bool) async throws {
        _ = try await communityRPCVoid("community_hide_post", [
            "p_post_id": .string(id),
            "p_hidden": .bool(hidden),
        ])
    }

    func communityConversations() async throws -> [CommunityConversation] {
        try await communityRPC("community_conversations_list", [:])
    }

    func communityMessages(conversationID: String, before: Date?, limit: Int) async throws -> [CommunityMessage] {
        var params: [String: AnyJSON] = [
            "p_conversation_id": .string(conversationID),
            "p_limit": .integer(limit),
        ]
        if let before {
            params["p_before"] = .string(Self.communityTimestamp.string(from: before))
        }
        return try await communityRPC("community_messages_list", params)
    }

    func communitySendMessage(id: String, conversationID: String, body: String) async throws -> CommunitySendMessageResult {
        try await communityRPC("community_send_message", [
            "p_id": .string(id),
            "p_conversation_id": .string(conversationID),
            "p_body": .string(body),
        ])
    }

    func communityMarkConversationRead(id: String) async throws {
        _ = try await communityRPCVoid("community_mark_conversation_read", ["p_conversation_id": .string(id)])
    }

    func communityMuteConversation(id: String, muted: Bool) async throws {
        _ = try await communityRPCVoid("community_mute_conversation", [
            "p_conversation_id": .string(id),
            "p_muted": .bool(muted),
        ])
    }

    func communityReport(
        targetType: CommunityReportTarget,
        targetID: String,
        reason: CommunityReportReason,
        details: String?
    ) async throws -> CommunityReportResult {
        try await communityRPC("community_report", [
            "p_target_type": .string(targetType.rawValue),
            "p_target_id": .string(targetID),
            "p_reason": .string(reason.rawValue),
            "p_details": details.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityNotifications(limit: Int, offset: Int) async throws -> [CommunityNotification] {
        try await communityRPC("community_notifications_list", [
            "p_limit": .integer(limit),
            "p_offset": .integer(offset),
        ])
    }

    func communityMarkNotificationsRead(ids: [String]?) async throws {
        var params: [String: AnyJSON] = [:]
        if let ids {
            params["p_ids"] = .array(ids.map(AnyJSON.string))
        } else {
            params["p_ids"] = .null
        }
        _ = try await communityRPCVoid("community_mark_notifications_read", params)
    }

    func communityAdminReports() async throws -> [CommunityModerationReport] {
        try await communityRPC("community_admin_reports", [:])
    }

    func communityAdminSetSuspension(userID: String, suspended: Bool, reason: String?) async throws {
        _ = try await communityRPCVoid("community_admin_set_suspension", [
            "p_user": .string(userID),
            "p_suspended": .bool(suspended),
            "p_reason": reason.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityAdminResolveReport(id: String, action: String, note: String?) async throws {
        _ = try await communityRPCVoid("community_admin_resolve_report", [
            "p_report_id": .string(id),
            "p_action": .string(action),
            "p_note": note.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityAdminGyms() async throws -> [CommunityAdminGym] {
        try await communityRPC("community_admin_gyms", [:])
    }

    func communityAdminReviewGym(id: String, approve: Bool, note: String?) async throws {
        _ = try await communityRPCVoid("community_admin_review_gym", [
            "p_gym_id": .string(id),
            "p_approve": .bool(approve),
            "p_note": note.map(AnyJSON.string) ?? .null,
        ])
    }

    func communityAdminAudit() async throws -> [CommunityAuditEntry] {
        try await communityRPC("community_admin_audit", [:])
    }

    func communityNotificationStream(userID: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let realtime = client.realtimeV2
                let channel = realtime.channel("forma-community-\(userID)")
                let token = channel.onPostgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "community_notifications",
                    filter: .eq("user_id", value: userID)
                ) { _ in
                    continuation.yield(())
                }
                defer { token.cancel() }

                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.finish()
                    return
                }

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                }
                await realtime.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private static let communityTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func communityRPC<T: Decodable>(_ name: String, _ params: [String: AnyJSON]) async throws -> T {
        do {
            return try await client.rpc(name, params: params).execute().value
        } catch {
            throw Self.communityError(error)
        }
    }

    /// PostgREST returns an empty body for `void` functions, so decode `Void`.
    private func communityRPCVoid(_ name: String, _ params: [String: AnyJSON]) async throws {
        do {
            _ = try await client.rpc(name, params: params).execute()
        } catch {
            throw Self.communityError(error)
        }
    }

    static func communityError(_ error: Error) -> Error {
        if let postgrest = error as? PostgrestError {
            return CommunityError(message: postgrest.message)
        }
        if let community = error as? CommunityError {
            return community
        }
        return CommunityError(message: error.localizedDescription)
    }
}
