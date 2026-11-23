import Foundation

/// Stores profile pictures as JPEG files beside the database. The database
/// only keeps the file name, so profile rows stay lightweight.
enum ProfilePhotoStore {
    static func directory() throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support
            .appendingPathComponent("Forma", isDirectory: true)
            .appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func url(for name: String) -> URL? {
        try? directory().appendingPathComponent(name)
    }

    /// Writes the image and returns the stored file name. Replacing a picture
    /// removes the old file so orphans do not accumulate.
    static func save(_ data: Data, replacing oldName: String?) throws -> String {
        let name = "profile-\(UUID().uuidString).jpg"
        try data.write(to: try directory().appendingPathComponent(name), options: .atomic)
        if let oldName { delete(oldName) }
        return name
    }

    static func delete(_ name: String) {
        guard let url = url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
