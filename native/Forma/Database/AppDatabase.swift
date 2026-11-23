import Foundation
import GRDB

/// The device-local SQLite database. It owns personal training data only;
/// Community data lives on the backend and is never merged in implicitly.
final class AppDatabase: @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try FormaMigrations.migrate(writer)
    }

    /// Opens (or creates) `forma.sqlite` in Application Support/Forma.
    static func onDisk() throws -> AppDatabase {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("Forma", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try onDisk(at: directory.appendingPathComponent("forma.sqlite"))
    }

    static func onDisk(at url: URL) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        configuration.maximumReaderCount = 4
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        return try AppDatabase(writer: pool)
    }

    /// Used by tests only: keeps every run isolated from real device data.
    static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        return try AppDatabase(writer: queue)
    }
}

enum DatabaseFailure: Error, CustomStringConvertible {
    case corruptValue(field: String, value: String)
    case missingReference(field: String)

    var description: String {
        switch self {
        case let .corruptValue(field, value):
            "Stored value for \(field) is invalid: \(value)"
        case let .missingReference(field):
            "Missing referenced value for \(field)"
        }
    }
}

/// `DATETIME` columns keep millisecond precision, so a timestamp minted with
/// `Date()` reads back slightly earlier than the copy still held in memory.
/// Values destined for a column go through the database encoding here, which
/// makes the in-memory value and the stored value the same instant.
enum StoredTimestamp {
    static func now() -> Date {
        truncated(Date())
    }

    static func truncated(_ date: Date) -> Date {
        Date.fromDatabaseValue(date.databaseValue) ?? date
    }
}

enum RecordCoding {
    static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String, field: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(string.utf8))
        } catch {
            throw DatabaseFailure.corruptValue(field: field, value: string)
        }
    }
}
