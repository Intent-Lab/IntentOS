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
    case agentSessionKey
    case agentSessionCreatedAt
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
