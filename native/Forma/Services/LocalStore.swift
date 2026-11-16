import Foundation

/// JSON file persistence for preview data and the in-progress workout.
actor LocalStore {
    static let shared = LocalStore()

    private let directory: URL
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("Forma", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    private func safe(_ key: String) -> String {
        key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }

    func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder.forma.decode(type, from: data)
    }

    func write<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder.forma.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    func remove(name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    func hasFile(name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    // Active workout is scoped by user so accounts never inherit each other's session.

    func loadActiveWorkout(userId: String) -> ActiveWorkout? {
        read(ActiveWorkout.self, name: "active-workout-\(safe(userId))")
    }

    func saveActiveWorkout(_ workout: ActiveWorkout?) {
        guard let workout else { return }
        write(workout, name: "active-workout-\(safe(workout.userId))")
    }

    func clearActiveWorkout(userId: String) {
        remove(name: "active-workout-\(safe(userId))")
    }

    func clearAllData() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}
