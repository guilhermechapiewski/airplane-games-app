/// Shared difficulty scale used by games that support it.
public enum Difficulty: String, CaseIterable, Codable, Sendable, Identifiable {
    case easy, medium, hard, expert

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .expert: "Expert"
        }
    }
}
