import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User preferences, backed by `UserDefaults`.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Keys.sound) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    var appearance: AppearancePreference { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }

    private enum Keys {
        static let sound = "settings.sound"
        static let haptics = "settings.haptics"
        static let appearance = "settings.appearance"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.sound: true, Keys.haptics: true])
        soundEnabled = defaults.bool(forKey: Keys.sound)
        hapticsEnabled = defaults.bool(forKey: Keys.haptics)
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
    }
}
