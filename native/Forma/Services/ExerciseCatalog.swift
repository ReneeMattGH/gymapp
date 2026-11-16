import Foundation

enum ExerciseCatalog {
    private static var cached: [Exercise]?

    static var all: [Exercise] {
        if let cached { return cached }
        let loaded = load()
        cached = loaded
        return loaded
    }

    static var byID: [String: Exercise] {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    static func exercise(_ id: String) -> Exercise? {
        byID[id]
    }

    static func name(_ id: String) -> String {
        byID[id]?.name ?? id
    }

    private static func load() -> [Exercise] {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: "exercises", withExtension: "json"),
            bundle.url(forResource: "exercises", withExtension: "json", subdirectory: "Resources"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else { return [] }
        do {
            let data = try Data(contentsOf: url)
            // Keep the bundled order: plan generation picks deterministically by index.
            var decoded = try JSONDecoder().decode([Exercise].self, from: data)
            for index in decoded.indices where decoded[index].source == nil {
                decoded[index].source = "Forma verified library · bundled copy"
            }
            return decoded
        } catch {
            assertionFailure("Exercise catalog failed to load: \(error)")
            return []
        }
    }
}
