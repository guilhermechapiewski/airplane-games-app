import Foundation

/// Persists `Codable` values as small JSON files in Application Support.
///
/// Writes are atomic and protected with `completeUntilFirstUserAuthentication`.
/// Each game owns a key (its `GameID.rawValue` by convention).
///
/// Games save after nearly every move, so encoding and writing happen on a serial background
/// queue to keep touches responsive. Reads, existence checks and removals go through the same
/// queue, so they always observe earlier saves.
struct GameStore: Sendable {
    let directory: URL
    private static let queue = DispatchQueue(label: "GameStore", qos: .utility)

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

    func save<T: Encodable & Sendable>(_ value: T, key: String) {
        let url = url(for: key)
        Self.queue.async {
            do {
                let data = try JSONEncoder().encode(value)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                assertionFailure("GameStore save failed for \(key): \(error)")
            }
        }
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let url = url(for: key)
        guard let data = Self.queue.sync(execute: { try? Data(contentsOf: url) }) else { return nil }
        // A save from an older, incompatible version is discarded rather than crashing.
        return try? JSONDecoder().decode(type, from: data)
    }

    func exists(key: String) -> Bool {
        let path = url(for: key).path
        return Self.queue.sync { FileManager.default.fileExists(atPath: path) }
    }

    func remove(key: String) {
        let url = url(for: key)
        Self.queue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Removes every saved key that `matches` (keys are file names without the extension).
    func removeKeys(where matches: @escaping @Sendable (String) -> Bool) {
        let directory = directory
        Self.queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" && matches(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func removeAll() {
        let directory = directory
        Self.queue.sync {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
