import Foundation

/// Tracks active play time; pauses when the game leaves the screen or the app backgrounds.
struct GameClock: Codable, Equatable, Sendable {
    private(set) var accumulated: TimeInterval = 0
    private var resumedAt: Date?

    var isRunning: Bool { resumedAt != nil }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    mutating func start(at now: Date = .now) {
        guard resumedAt == nil else { return }
        resumedAt = now
    }

    mutating func pause(at now: Date = .now) {
        guard let resumedAt else { return }
        accumulated += now.timeIntervalSince(resumedAt)
        self.resumedAt = nil
    }

    mutating func reset() {
        accumulated = 0
        resumedAt = nil
    }

    // A clock is always persisted paused so a relaunch never counts time spent closed.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elapsed(), forKey: .accumulated)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accumulated = try c.decode(TimeInterval.self, forKey: .accumulated)
    }

    private enum CodingKeys: String, CodingKey { case accumulated }
}

extension TimeInterval {
    /// "m:ss" or "h:mm:ss".
    var clockString: String {
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
