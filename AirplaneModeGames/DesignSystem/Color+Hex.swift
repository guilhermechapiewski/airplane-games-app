import SwiftUI

extension Color {
    /// Creates an sRGB color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that adapts between light and dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Theme {
    /// App background behind game boards.
    static let background = Color(light: Color(hex: 0xF4F5FA), dark: Color(hex: 0x0E1016))
    /// Raised surfaces such as boards and panels.
    static let surface = Color(light: .white, dark: Color(hex: 0x1B1E27))
    /// Slightly recessed areas (empty cells, wells).
    static let well = Color(light: Color(hex: 0xE6E8F0), dark: Color(hex: 0x262A36))
    static let hairline = Color(light: Color(hex: 0xD5D8E3), dark: Color(hex: 0x353A48))
    static let secondaryText = Color.secondary

    static let cornerRadius: CGFloat = 16
    static let smallRadius: CGFloat = 8
}
