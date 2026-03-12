import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  private let defaults = UserDefaults.standard

  private enum Key: String {
    case geminiAPIKey
    case geminiSystemPrompt
    case agentBaseURL
    case agentToken
    case webrtcSignalingURL
    case speakerOutputEnabled
    case userId
    case agentSessionKey
    case agentSessionCreatedAt
    case fontTheme
  }

  private init() {}

  // MARK: - Gemini

  var geminiAPIKey: String {
    get { defaults.string(forKey: Key.geminiAPIKey.rawValue) ?? Secrets.geminiAPIKey }
    set { defaults.set(newValue, forKey: Key.geminiAPIKey.rawValue) }
  }

  var geminiSystemPrompt: String {
    get { defaults.string(forKey: Key.geminiSystemPrompt.rawValue) ?? GeminiConfig.defaultSystemInstruction }
    set { defaults.set(newValue, forKey: Key.geminiSystemPrompt.rawValue) }
  }

  // MARK: - Agent

  var agentBaseURL: String {
    get { defaults.string(forKey: Key.agentBaseURL.rawValue) ?? Secrets.agentBaseURL }
    set { defaults.set(newValue, forKey: Key.agentBaseURL.rawValue) }
  }

  var agentToken: String {
    get { defaults.string(forKey: Key.agentToken.rawValue) ?? Secrets.agentToken }
    set { defaults.set(newValue, forKey: Key.agentToken.rawValue) }
  }

  // MARK: - WebRTC

  var webrtcSignalingURL: String {
    get { defaults.string(forKey: Key.webrtcSignalingURL.rawValue) ?? Secrets.webrtcSignalingURL }
    set { defaults.set(newValue, forKey: Key.webrtcSignalingURL.rawValue) }
  }

  // MARK: - Audio

  var speakerOutputEnabled: Bool {
    get { defaults.bool(forKey: Key.speakerOutputEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.speakerOutputEnabled.rawValue) }
  }

  // MARK: - User Identity (permanent, survives reset)

  var userId: String {
    if let id = defaults.string(forKey: Key.userId.rawValue) { return id }
    let id = UUID().uuidString
    defaults.set(id, forKey: Key.userId.rawValue)
    return id
  }

  // MARK: - Font Theme

  var fontTheme: String {
    get { defaults.string(forKey: Key.fontTheme.rawValue) ?? FontTheme.tiempos.rawValue }
    set { defaults.set(newValue, forKey: Key.fontTheme.rawValue) }
  }

  // MARK: - Session Persistence

  var agentSessionKey: String? {
    get { defaults.string(forKey: Key.agentSessionKey.rawValue) }
    set { defaults.set(newValue, forKey: Key.agentSessionKey.rawValue) }
  }

  var agentSessionCreatedAt: TimeInterval {
    get { defaults.double(forKey: Key.agentSessionCreatedAt.rawValue) }
    set { defaults.set(newValue, forKey: Key.agentSessionCreatedAt.rawValue) }
  }

  // MARK: - Reset

  func resetAll() {
    for key in [Key.geminiAPIKey, .geminiSystemPrompt, .agentBaseURL, .agentToken,
                .webrtcSignalingURL, .speakerOutputEnabled,
                .agentSessionKey, .agentSessionCreatedAt] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
