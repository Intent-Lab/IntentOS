import SwiftUI

// MARK: - Font Theme

enum FontTheme: String, CaseIterable {
  case system = "System"
  case tiempos = "Tiempos"
}

// MARK: - AppFont

/// Central font provider. Reads the current theme from SettingsManager
/// and returns either system fonts or Tiempos custom fonts.
///
/// Usage: replace `.font(.body)` with `.font(AppFont.body)`
struct AppFont {
  private static var theme: FontTheme {
    FontTheme(rawValue: SettingsManager.shared.fontTheme) ?? .system
  }

  // MARK: - Body / Text

  static var body: Font {
    switch theme {
    case .system: return .body
    case .tiempos: return .custom("TestTiemposText-Regular", size: 17)
    }
  }

  static var bodyMedium: Font {
    switch theme {
    case .system: return .body.weight(.medium)
    case .tiempos: return .custom("TestTiemposText-Medium", size: 17)
    }
  }

  static var bodySemibold: Font {
    switch theme {
    case .system: return .body.weight(.semibold)
    case .tiempos: return .custom("TestTiemposText-Semibold", size: 17)
    }
  }

  static var bodyBold: Font {
    switch theme {
    case .system: return .body.bold()
    case .tiempos: return .custom("TestTiemposText-Bold", size: 17)
    }
  }

  static var bodyItalic: Font {
    switch theme {
    case .system: return .body.italic()
    case .tiempos: return .custom("TestTiemposText-RegularItalic", size: 17)
    }
  }

  // MARK: - Captions / Small

  static var caption: Font {
    switch theme {
    case .system: return .caption
    case .tiempos: return .custom("TestTiemposText-Regular", size: 12)
    }
  }

  static var caption2: Font {
    switch theme {
    case .system: return .caption2
    case .tiempos: return .custom("TestTiemposText-Regular", size: 11)
    }
  }

  static var footnote: Font {
    switch theme {
    case .system: return .footnote
    case .tiempos: return .custom("TestTiemposText-Regular", size: 13)
    }
  }

  // MARK: - Subheadline / Callout

  static var subheadline: Font {
    switch theme {
    case .system: return .subheadline
    case .tiempos: return .custom("TestTiemposText-Regular", size: 15)
    }
  }

  static var callout: Font {
    switch theme {
    case .system: return .callout
    case .tiempos: return .custom("TestTiemposText-Regular", size: 16)
    }
  }

  // MARK: - Headlines (use Tiempos Fine for display)

  static var headline: Font {
    switch theme {
    case .system: return .headline
    case .tiempos: return .custom("TestTiemposFine-Semibold", size: 17)
    }
  }

  static var title3: Font {
    switch theme {
    case .system: return .title3
    case .tiempos: return .custom("TestTiemposFine-Semibold", size: 20)
    }
  }

  static var title2: Font {
    switch theme {
    case .system: return .title2
    case .tiempos: return .custom("TestTiemposFine-Semibold", size: 22)
    }
  }

  static var title: Font {
    switch theme {
    case .system: return .title
    case .tiempos: return .custom("TestTiemposFine-Semibold", size: 28)
    }
  }

  static var largeTitle: Font {
    switch theme {
    case .system: return .largeTitle
    case .tiempos: return .custom("TestTiemposFine-Regular", size: 34)
    }
  }

  // MARK: - Monospaced (always system, Tiempos has no mono)

  static func monospaced(_ style: Font.TextStyle = .body) -> Font {
    .system(style, design: .monospaced)
  }
}
