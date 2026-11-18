import AppIntents
import SwiftUI
import WidgetKit

enum WidgetFocus: String, AppEnum {
    case automatic
    case today
    case weekly
    case consistency

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Small widget emphasis"

    static var caseDisplayRepresentations: [WidgetFocus: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Automatic"),
        .today: DisplayRepresentation(title: "Today's workout"),
        .weekly: DisplayRepresentation(title: "Weekly goal"),
        .consistency: DisplayRepresentation(title: "Streak")
    ]
}

struct FitnessWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fitness Command Center"
    static var description = IntentDescription("Choose what the small widget emphasises. Medium and large always show the full picture.")

    @Parameter(title: "Small widget emphasis", default: .automatic)
    var focus: WidgetFocus
}

struct FitnessEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let focus: WidgetFocus
}

struct FitnessTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FitnessEntry {
        FitnessEntry(date: Date(), snapshot: .empty(), focus: .automatic)
    }

    func snapshot(for configuration: FitnessWidgetConfigurationIntent, in context: Context) async -> FitnessEntry {
        let snapshot = WidgetSharedDataStore.load() ?? .empty()
        return FitnessEntry(date: Date(), snapshot: snapshot, focus: configuration.focus)
    }

    func timeline(for configuration: FitnessWidgetConfigurationIntent, in context: Context) async -> Timeline<FitnessEntry> {
        let now = Date()
        let snapshot = WidgetSharedDataStore.load() ?? .empty()
        let entry = FitnessEntry(date: now, snapshot: snapshot, focus: configuration.focus)
        let refresh = WidgetTimelineLogic.nextRefreshDate(after: now)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct FitnessCommandCenterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: FormaWidgetKind.identifier,
            intent: FitnessWidgetConfigurationIntent.self,
            provider: FitnessTimelineProvider()
        ) { entry in
            FitnessWidgetView(entry: entry)
        }
        .configurationDisplayName(FormaWidgetKind.displayName)
        .description("Today's session, weekly progress, streak and Community counts from your Forma account.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
