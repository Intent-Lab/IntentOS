import Foundation

enum AgentConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

@MainActor
class AgentBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: AgentConnectionState = .notConfigured

  private let session: URLSession
  private let pingSession: URLSession
  private var sessionKey: String
  private var conversationHistory: [[String: String]] = []
  private let maxHistoryTurns = 3
  private static let sessionMaxAge: TimeInterval = 86400 // 24 hours

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)

    // Reuse persisted session key if < 24 hours old
    let settings = SettingsManager.shared
    let age = Date().timeIntervalSince1970 - settings.agentSessionCreatedAt
    if let existingKey = settings.agentSessionKey, age < AgentBridge.sessionMaxAge {
      self.sessionKey = existingKey
      NSLog("[Agent] Resumed session: %@", existingKey)
    } else {
      let newKey = AgentBridge.newSessionKey()
      self.sessionKey = newKey
      settings.agentSessionKey = newKey
      settings.agentSessionCreatedAt = Date().timeIntervalSince1970
      NSLog("[Agent] New session: %@", newKey)
    }
  }

  func checkConnection() async {
    guard AgentConfig.isConfigured else {
      connectionState = .notConfigured
      return
    }
    connectionState = .checking
    guard let url = URL(string: "\(AgentConfig.baseURL)/api/agent/health") else {
      connectionState = .unreachable("Invalid URL")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(AgentConfig.token, forHTTPHeaderField: "x-api-token")
    do {
      let (_, response) = try await pingSession.data(for: request)
      if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
        connectionState = .connected
        NSLog("[Agent] Gateway reachable (HTTP %d)", http.statusCode)
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      NSLog("[Agent] Gateway unreachable: %@", error.localizedDescription)
    }
  }

  func resetSession() {
    let newKey = AgentBridge.newSessionKey()
    sessionKey = newKey
    conversationHistory = []
    let settings = SettingsManager.shared
    settings.agentSessionKey = newKey
    settings.agentSessionCreatedAt = Date().timeIntervalSince1970
    NSLog("[Agent] Reset session: %@", newKey)
  }

  private static func newSessionKey() -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    return "agent:main:glass:\(ts)"
  }

  /// Inject prior conversation context (e.g. voice transcripts) into history
  /// so subsequent messages have full context from other interaction modes.
  func injectContext(_ messages: [[String: String]]) {
    conversationHistory.insert(contentsOf: messages, at: 0)
    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }
    NSLog("[Agent] Injected %d context messages (total: %d)", messages.count, conversationHistory.count)
  }

  // MARK: - Agent Chat (session continuity via x-agent-session-key header)

  func delegateTask(
    task: String,
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)

    guard let url = URL(string: "\(AgentConfig.baseURL)/api/agent/chat") else {
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    // Append the new user message to conversation history
    conversationHistory.append(["role": "user", "content": task])

    // Trim history to keep only the most recent turns (user+assistant pairs)
    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(AgentConfig.token, forHTTPHeaderField: "x-api-token")
    request.setValue(sessionKey, forHTTPHeaderField: "x-agent-session-key")

    let body: [String: Any] = [
      "model": "claude-agent",
      "messages": conversationHistory,
      "stream": false
    ]

    NSLog("[Agent] Sending %d messages in conversation", conversationHistory.count)

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[Agent] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        // Append assistant response to history for continuity
        conversationHistory.append(["role": "assistant", "content": content])
        NSLog("[Agent] Agent result: %@", String(content.prefix(200)))
        lastToolCallStatus = .completed(toolName)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      conversationHistory.append(["role": "assistant", "content": raw])
      NSLog("[Agent] Agent raw: %@", String(raw.prefix(200)))
      lastToolCallStatus = .completed(toolName)
      return .success(raw)
    } catch {
      NSLog("[Agent] Agent error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Agent error: \(error.localizedDescription)")
    }
  }
}
