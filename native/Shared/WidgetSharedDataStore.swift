import Foundation

/// App Group bridge between the app process and the widget extension.
///
/// The training snapshot and the Community counts are stored under separate
/// keys. Community counts can arrive before or after the training snapshot, so
/// reads always overlay the latest counts for the snapshot's account instead of
/// depending on write order.
enum WidgetSharedDataStore {
    static let appGroupIdentifier = "group.forma.coach"

    private static let snapshotKey = "forma.widget.snapshot"
    private static let communityKey = "forma.widget.community"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Pure codec (unit-testable)

    static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        guard snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion,
              !snapshot.accountID.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try? encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion,
              !snapshot.accountID.isEmpty else { return nil }
        return snapshot
    }

    static func encodeCommunity(_ summary: WidgetCommunitySummary) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try? encoder.encode(summary)
    }

    static func decodeCommunity(_ data: Data) -> WidgetCommunitySummary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(WidgetCommunitySummary.self, from: data)
    }

    // MARK: - Training snapshot

    static func load(defaults: UserDefaults? = WidgetSharedDataStore.sharedDefaults) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey),
              var snapshot = decode(data) else { return nil }
        // Overlay Community counts only for the same account.
        if let community = community(for: snapshot.accountID, defaults: defaults) {
            snapshot.community = community
        }
        return snapshot
    }

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot, defaults: UserDefaults? = WidgetSharedDataStore.sharedDefaults) -> Bool {
        guard let defaults, let data = encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    static func clear(defaults: UserDefaults? = WidgetSharedDataStore.sharedDefaults) {
        defaults?.removeObject(forKey: snapshotKey)
        defaults?.removeObject(forKey: communityKey)
        defaults?.removeObject(forKey: communityAccountKey)
    }

    // MARK: - Community counts

    static func community(for accountID: String, defaults: UserDefaults? = WidgetSharedDataStore.sharedDefaults) -> WidgetCommunitySummary? {
        guard let data = defaults?.data(forKey: communityKey),
              let summary = decodeCommunity(data) else { return nil }
        // The counts carry the account they belong to inside the payload. If it
        // would ever be read for a different account, it is discarded.
        guard summaryAccountID(defaults: defaults) == accountID else { return nil }
        return summary
    }

    /// Returns true when the stored counts actually changed, so callers only
    /// ask WidgetKit to reload for real differences.
    @discardableResult
    static func updateCommunity(
        accountID: String,
        pendingRequests: Int,
        unreadMessages: Int,
        unreadNotifications: Int,
        at date: Date = Date(),
        defaults: UserDefaults? = WidgetSharedDataStore.sharedDefaults
    ) -> Bool {
        guard let defaults, !accountID.isEmpty else { return false }
        let next = WidgetCommunitySummary(
            pendingRequests: max(0, pendingRequests),
            unreadMessages: max(0, unreadMessages),
            unreadNotifications: max(0, unreadNotifications),
            updatedAt: date
        )
        if let existing = self.community(for: accountID, defaults: defaults),
           existing.pendingRequests == next.pendingRequests,
           existing.unreadMessages == next.unreadMessages,
           existing.unreadNotifications == next.unreadNotifications {
            return false
        }
        guard let data = encodeCommunity(next) else { return false }
        defaults.set(data, forKey: communityKey)
        defaults.set(accountID, forKey: communityAccountKey)
        return true
    }

    private static let communityAccountKey = "forma.widget.community.account"

    private static func summaryAccountID(defaults: UserDefaults?) -> String? {
        defaults?.string(forKey: communityAccountKey)
    }
}
