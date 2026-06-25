import SwiftUI

enum ReadingTheme: String, CaseIterable, Codable {
    case white
    case sepia
    case dark
    case yellow

    var displayName: String {
        switch self {
        case .white: return L10n.themeWhite
        case .sepia: return L10n.themeSepia
        case .dark: return L10n.themeDark
        case .yellow: return L10n.themeYellow
        }
    }

    var backgroundColor: Color {
        switch self {
        case .white: return .white
        case .sepia: return Color(red: 0.98, green: 0.94, blue: 0.85)
        case .dark: return Color(red: 0.10, green: 0.10, blue: 0.18)
        case .yellow: return Color(red: 1.0, green: 0.98, blue: 0.77)
        }
    }

    var textColor: Color {
        switch self {
        case .white: return Color(red: 0.10, green: 0.10, blue: 0.10)
        case .sepia: return Color(red: 0.23, green: 0.18, blue: 0.10)
        case .dark: return Color(red: 0.91, green: 0.91, blue: 0.91)
        case .yellow: return Color(red: 0.10, green: 0.10, blue: 0.10)
        }
    }

    var accentColor: Color {
        switch self {
        case .white: return .blue
        case .sepia: return Color(red: 0.55, green: 0.27, blue: 0.07)
        case .dark: return Color(red: 0.91, green: 0.27, blue: 0.38)
        case .yellow: return Color(red: 0.90, green: 0.32, blue: 0.0)
        }
    }
}
