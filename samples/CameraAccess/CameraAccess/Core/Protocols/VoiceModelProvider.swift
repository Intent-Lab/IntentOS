import Foundation
import UIKit

// MARK: - Voice Model Events

enum VoiceModelEvent {
  case audioResponse(Data)
  case inputTranscription(String)
  case outputTranscription(String)
  case toolCall(id: String, name: String, args: [String: Any])
  case toolCallCancellation(ids: [String])
  case turnComplete
  case interrupted
  case sessionStarted
  case sessionEnded(reason: String?)
  case modelSpeakingChanged(Bool)
  case error(String)
}

// MARK: - Voice Model Connection State

enum VoiceModelConnectionState: Equatable {
  case disconnected
  case connecting
  case settingUp
  case ready
  case error(String)

  /// Convert to the existing GeminiConnectionState for backward compatibility
  var asGeminiState: GeminiConnectionState {
    switch self {
    case .disconnected: return .disconnected
    case .connecting: return .connecting
    case .settingUp: return .settingUp
    case .ready: return .ready
    case .error(let msg): return .error(msg)
    }
  }

  /// Create from existing GeminiConnectionState
  init(from geminiState: GeminiConnectionState) {
    switch geminiState {
    case .disconnected: self = .disconnected
    case .connecting: self = .connecting
    case .settingUp: self = .settingUp
    case .ready: self = .ready
    case .error(let msg): self = .error(msg)
    }
  }
}

// MARK: - Voice Session Configuration

struct VoiceSessionConfig {
  let systemInstruction: String
  let toolDeclarations: [[String: Any]]
  let responseModalities: [String]

  /// Default config using existing GeminiConfig values
  static var geminiDefault: VoiceSessionConfig {
    VoiceSessionConfig(
      systemInstruction: GeminiConfig.systemInstruction,
      toolDeclarations: ToolDeclarations.allDeclarations(),
      responseModalities: ["AUDIO"]
    )
  }
}

// MARK: - VoiceModelProvider Protocol

protocol VoiceModelProvider: AnyObject {
  var id: String { get }
  var name: String { get }
  var supportsVideo: Bool { get }
  var connectionState: VoiceModelConnectionState { get }
  var isModelSpeaking: Bool { get }

  func connect(config: VoiceSessionConfig) async -> Bool
  func disconnect()
  func sendAudio(data: Data)
  func sendVideoFrame(image: UIImage)
  func sendToolResponse(_ response: [String: Any])
  func sendTextMessage(_ text: String)

  var events: AsyncStream<VoiceModelEvent> { get }
}
