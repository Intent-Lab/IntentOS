import Foundation

/// Sends conversation events to the agent API for persistent logging.
/// All methods are fire-and-forget — logging never blocks the UI or conversation flow.
final class RemoteLogger {
  static let shared = RemoteLogger()

  private let session: URLSession
  private var sequenceNumber = 0

  private init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 5
    self.session = URLSession(configuration: config)
  }

  /// Log a conversation event. Types:
  /// - "voice:user" — user speech transcript from Gemini
  /// - "voice:ai" — Gemini voice response transcript
  /// - "voice:tool_call" — Gemini triggered execute tool
  /// - "voice:tool_result" — tool result sent back to Gemini
  /// - "chat:user" — user typed a text message
  /// - "chat:agent" — agent responded to text chat
  /// - "chat:error" — error in text chat
  /// - "session:start" — voice/chat session started
  /// - "session:end" — voice mode ended
  func log(_ type: String, data: [String: String] = [:]) {
    guard AgentConfig.isConfigured else { return }
    guard let url = URL(string: "\(AgentConfig.baseURL)/api/agent/logs") else { return }

    sequenceNumber += 1
    var payload: [String: Any] = [
      "type": "event",
      "session": "ios-client",
      "data": [
        "event": type,
        "seq": sequenceNumber
      ].merging(data) { _, new in new }
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(AgentConfig.token, forHTTPHeaderField: "x-api-token")

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    } catch { return }

    // Fire and forget
    Task.detached(priority: .utility) { [session] in
      _ = try? await session.data(for: request)
    }
  }
}
