import Foundation

/// JSON file persistence for preview data and the in-progress workout.
actor LocalStore {
    static let shared = LocalStore()

    private let directory: URL
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = support.appendingPathComponent("Forma", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
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

    // Completed form-analysis sessions that still need a backend write. The
    // queue holds only measured session metadata, never frames.

    private func pendingFormName(_ userId: String) -> String {
        "pending-form-sessions-\(safe(userId))"
    }

    func pendingFormSessions(userId: String) -> [WorkoutSession] {
        read([WorkoutSession].self, name: pendingFormName(userId)) ?? []
    }

    func enqueuePendingFormSession(_ session: WorkoutSession, userId: String) {
        var items = pendingFormSessions(userId: userId)
        if let index = items.firstIndex(where: { $0.id == session.id }) {
            items[index] = session
        } else {
            items.append(session)
        }
        write(items, name: pendingFormName(userId))
    }

    func removePendingFormSession(id: String, userId: String) {
        var items = pendingFormSessions(userId: userId)
        items.removeAll { $0.id == id }
        if items.isEmpty {
            remove(name: pendingFormName(userId))
        } else {
            write(items, name: pendingFormName(userId))
        }
    }

    func clearAllData() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}
