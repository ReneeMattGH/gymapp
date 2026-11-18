import Foundation
import WidgetKit

/// One place that writes shared widget state and asks WidgetKit to reload.
/// Reloads are only requested after a real data change, never on a timer.
@MainActor
enum WidgetPublisher {
    static func publish(
        accountID: String,
        plan: WorkoutPlan?,
        preferences: Preferences?,
        sessions: [WorkoutSession],
        activeWorkout: ActiveWorkout?,
        isPreview: Bool,
        now: Date = Date()
    ) {
        var snapshot = WidgetSnapshotBuilder.build(
            accountID: accountID,
            plan: plan,
            preferences: preferences,
            sessions: sessions,
            activeWorkout: activeWorkout,
            isPreview: isPreview,
            now: now
        )
        snapshot.community = WidgetSharedDataStore.community(for: accountID)
        guard WidgetSharedDataStore.save(snapshot) else { return }
        reload()
    }

    static func clear() {
        WidgetSharedDataStore.clear()
        reload()
    }

    /// After a failed load or an account switch, never leave a different
    /// account's training data on the Home Screen.
    static func discardIfAccountDiffers(_ accountID: String?) {
        guard let accountID else {
            clear()
            return
        }
        guard let existing = WidgetSharedDataStore.load(), existing.accountID != accountID else { return }
        clear()
    }

    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: FormaWidgetKind.identifier)
    }
}

extension AppModel {
    func publishWidgetSnapshot(now: Date = Date()) {
        guard let user else {
            WidgetPublisher.clear()
            return
        }
        WidgetPublisher.publish(
            accountID: user.id,
            plan: plan,
            preferences: preferences,
            sessions: sessions,
            activeWorkout: activeWorkout,
            isPreview: isPreview,
            now: now
        )
    }

    func discardWidgetSnapshotIfAccountDiffers() {
        WidgetPublisher.discardIfAccountDiffers(user?.id)
    }
}
