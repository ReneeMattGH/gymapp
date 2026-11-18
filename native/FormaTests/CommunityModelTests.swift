import XCTest
@testable import Forma

final class CommunityModelTests: XCTestCase {
    /// Mirrors the Supabase SDK decoder: ISO-8601 with or without fractional seconds.
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFraction.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    func testMemberDecodesSnakeCaseAndDefaults() throws {
        let member = try decode(CommunityMember.self, from: """
        {
          "user_id": "u-1",
          "username": "matt",
          "display_name": "Matt",
          "interests": ["strength"],
          "gym_name": "Velocity Gym",
          "area": "Adyar",
          "city": "Chennai",
          "connection_status": "pending_sent"
        }
        """)
        XCTAssertEqual(member.userID, "u-1")
        XCTAssertEqual(member.displayName, "Matt")
        XCTAssertEqual(member.interests, ["strength"])
        XCTAssertEqual(member.workoutCategories, [])
        XCTAssertNil(member.avatarURL)
        XCTAssertEqual(member.connectionStatus, .pendingSent)
        XCTAssertEqual(member.id, "u-1")
    }

    func testUnknownConnectionStatusFallsBackToNone() throws {
        let member = try decode(CommunityMember.self, from: """
        {"user_id":"u-2","username":"sam","display_name":"Sam","connection_status":"something_new"}
        """)
        XCTAssertEqual(member.connectionStatus, .none)
    }

    func testPublicProfileDefaultsPrivateFlagsToFalse() throws {
        let profile = try decode(CommunityPublicProfile.self, from: """
        {
          "user_id":"u-3",
          "username":"asha",
          "display_name":"Asha",
          "joined_at":"2026-02-01T10:15:30Z",
          "connection_status":"accepted"
        }
        """)
        XCTAssertEqual(profile.connectionStatus, .accepted)
        XCTAssertFalse(profile.sharedGym)
        XCTAssertFalse(profile.sharedArea)
        XCTAssertFalse(profile.achievementsOptIn)
        XCTAssertNotNil(profile.joinedAt)
    }

    func testPostDecodesKindCountsAndSharedSession() throws {
        let post = try decode(CommunityPost.self, from: """
        {
          "id":"p-1",
          "author_id":"u-1",
          "username":"matt",
          "display_name":"Matt",
          "content":"Squat day",
          "kind":"milestone",
          "achievement_label":"100 kg x 5",
          "like_count":4,
          "comment_count":2,
          "liked":true,
          "is_own":true,
          "shared_session":{
            "session_id":"s-1","title":"Lower body","started_at":"2026-03-01T06:00:00Z","duration_seconds":2700
          },
          "created_at":"2026-03-01T07:00:00Z"
        }
        """)
        XCTAssertEqual(post.kind, .milestone)
        XCTAssertEqual(post.likeCount, 4)
        XCTAssertEqual(post.commentCount, 2)
        XCTAssertTrue(post.liked)
        XCTAssertTrue(post.isOwn)
        XCTAssertEqual(post.sharedSession?.durationSeconds, 2700)
        XCTAssertNil(post.updatedAt)
    }

    func testUnknownPostKindFallsBackToUpdate() throws {
        let post = try decode(CommunityPost.self, from: """
        {"id":"p-2","author_id":"u-1","username":"m","display_name":"M","content":"Hi","kind":"future_kind","created_at":"2026-03-01T07:00:00Z"}
        """)
        XCTAssertEqual(post.kind, .update)
        XCTAssertEqual(post.likeCount, 0)
        XCTAssertFalse(post.liked)
    }

    func testBootstrapDecodesAndDefaultsMissingCollections() throws {
        let bootstrap = try decode(CommunityBootstrap.self, from: """
        {
          "is_admin": true,
          "suspended": false,
          "members_at_gym": 12,
          "nearby_members": 40,
          "incoming_request_count": 1,
          "unread_notifications": 3,
          "unread_messages": 2,
          "membership": {"gym_id":"g-1","gym_name":"Velocity Gym","city":"Chennai","verification_status":"verified"},
          "suggestions": [
            {"user_id":"u-4","username":"ravi","display_name":"Ravi","connection_status":"none"}
          ],
          "areas": [
            {"city":"Chennai","area":"Adyar","nearby_group":"south"}
          ]
        }
        """)
        XCTAssertTrue(bootstrap.isAdmin)
        XCTAssertEqual(bootstrap.membersAtGym, 12)
        XCTAssertEqual(bootstrap.nearbyMembers, 40)
        XCTAssertEqual(bootstrap.incomingRequestCount, 1)
        XCTAssertEqual(bootstrap.unreadNotifications, 3)
        XCTAssertEqual(bootstrap.unreadMessages, 2)
        XCTAssertEqual(bootstrap.membership?.gymName, "Velocity Gym")
        XCTAssertEqual(bootstrap.suggestions.count, 1)
        XCTAssertEqual(bootstrap.areas.first?.nearbyGroup, "south")
        XCTAssertTrue(bootstrap.nearby.isEmpty)
        XCTAssertTrue(bootstrap.incomingRequests.isEmpty)
        XCTAssertTrue(bootstrap.connections.isEmpty)
        XCTAssertTrue(bootstrap.feed.isEmpty)
        XCTAssertNil(bootstrap.profile)
        XCTAssertNil(bootstrap.preferences)
    }

    func testConversationDefaultsUnreadAndMute() throws {
        let conversation = try decode(CommunityConversation.self, from: """
        {
          "conversation_id":"c-1",
          "connection_id":"k-1",
          "user_id":"u-5",
          "username":"nina",
          "display_name":"Nina",
          "last_message":"See you tomorrow",
          "last_message_at":"2026-03-02T08:00:00.123Z"
        }
        """)
        XCTAssertEqual(conversation.unreadCount, 0)
        XCTAssertFalse(conversation.muted)
        XCTAssertNotNil(conversation.lastMessageAt)
    }

    func testNotificationTitlesImagesAndUnreadState() {
        let base = "{\"id\":\"n-1\",\"body\":\"Body\",\"created_at\":\"2026-03-02T08:00:00Z\""

        func notification(_ kind: String) throws -> CommunityNotification {
            try decode(CommunityNotification.self, from: "\(base),\"kind\":\"\(kind)\"}")
        }

        let request = try? notification("connection_request")
        XCTAssertEqual(request?.title, "New connection request")
        XCTAssertEqual(request?.systemImage, "person.2.fill")
        XCTAssertEqual(request?.isUnread, true)

        XCTAssertEqual((try? notification("connection_accepted"))?.title, "Connection accepted")
        XCTAssertEqual((try? notification("message"))?.title, "New message")
        XCTAssertEqual((try? notification("message"))?.systemImage, "bubble.left.fill")
        XCTAssertEqual((try? notification("post_comment"))?.title, "New comment")
        XCTAssertEqual((try? notification("post_like"))?.systemImage, "heart.fill")
        XCTAssertEqual((try? notification("unexpected"))?.title, "Community activity")
        XCTAssertEqual((try? notification("unexpected"))?.systemImage, "bell.fill")
    }

    func testConnectionFlagsDistinguishDirectionAndStatus() throws {
        let connection = try decode(CommunityConnection.self, from: """
        {
          "connection_id":"k-2","user_id":"u-6","username":"leo","display_name":"Leo",
          "status":"pending","direction":"received","created_at":"2026-03-03T09:00:00Z"
        }
        """)
        XCTAssertTrue(connection.isPending)
        XCTAssertFalse(connection.isAccepted)
        XCTAssertTrue(connection.isIncoming)
        XCTAssertNil(connection.conversationID)
    }

    func testConnectionStatusParsing() {
        XCTAssertEqual(ConnectionStatus(rawValue: "pending_sent"), .pendingSent)
        XCTAssertEqual(ConnectionStatus(rawValue: "pending_received"), .pendingReceived)
        XCTAssertEqual(ConnectionStatus(rawValue: "accepted"), .accepted)
        XCTAssertEqual(ConnectionStatus(rawValue: "blocked"), .blocked)
        XCTAssertNil(ConnectionStatus(rawValue: "unknown"))
    }

    func testErrorDescriptions() {
        let error = CommunityError(message: "Messaging is not available for this conversation.")
        XCTAssertEqual(error.errorDescription, "Messaging is not available for this conversation.")
        XCTAssertTrue(CommunityError.notConfigured.message.contains("Supabase"))
    }
}
