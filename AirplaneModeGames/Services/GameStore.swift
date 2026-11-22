import Foundation

/// Persists `Codable` values as small JSON files in Application Support.
///
/// Writes are atomic and protected with `completeUntilFirstUserAuthentication`.
/// Each game owns a key (its `GameID.rawValue` by convention).
struct GameStore: Sendable {
    let directory: URL

    static let shared = GameStore()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Saves", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        // Keys are internal identifiers; sanitize defensively anyway.
        let safe = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func save<T: Encodable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url(for: key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            assertionFailure("GameStore save failed for \(key): \(error)")
        }
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        // A save from an older, incompatible version is discarded rather than crashing.
        return try? JSONDecoder().decode(type, from: data)
    }

    func exists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path)
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
