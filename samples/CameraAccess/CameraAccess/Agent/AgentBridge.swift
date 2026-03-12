import Foundation

enum AgentConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

/// Represents a step in the agent's execution (for UI status display)
struct AgentStep: Identifiable, Equatable {
  let id = UUID().uuidString
  let type: StepType
  let label: String
  var isDone: Bool = false
  var success: Bool = true

  enum StepType: Equatable {
    case thinking
    case tool(String) // tool name
  }

  /// User-friendly display text
  var displayText: String {
    if !isDone {
      return label
    }
    return success ? label : "Failed: \(label)"
  }
}

@MainActor
class AgentBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: AgentConnectionState = .notConfigured
  @Published var streamingText: String = ""
  @Published var agentSteps: [AgentStep] = []

  private let session: URLSession
  private let pingSession: URLSession
  private var sessionKey: String
  private var conversationHistory: [[String: String]] = []
  private static let sessionMaxAge: TimeInterval = 86400 // 24 hours

  // Direct E2B sandbox connection
  private var sandboxUrl: String?
  private var sandboxAuthToken: String?

  /// Which backend this bridge is using (read once at init, stable for lifetime)
  let backend: AgentBackend

  init() {
    self.backend = SettingsManager.shared.agentBackend

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
      NSLog("[Agent:%@] Resumed session: %@", backend.rawValue, existingKey)
    } else {
      let newKey = AgentBridge.newSessionKey()
      self.sessionKey = newKey
      settings.agentSessionKey = newKey
      settings.agentSessionCreatedAt = Date().timeIntervalSince1970
      NSLog("[Agent:%@] New session: %@", backend.rawValue, newKey)
    }
  }

  private var maxHistoryTurns: Int {
    backend == .openClaw ? 10 : 3
  }

  func checkConnection() async {
    switch backend {
    case .e2b:
      await checkE2BConnection()
    case .openClaw:
      await checkOpenClawConnection()
    }
  }

  private func checkE2BConnection() async {
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
        NSLog("[Agent:E2B] Gateway reachable (HTTP %d)", http.statusCode)
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      NSLog("[Agent:E2B] Gateway unreachable: %@", error.localizedDescription)
    }
  }

  private func checkOpenClawConnection() async {
    let settings = SettingsManager.shared
    guard !settings.openClawHost.isEmpty, !settings.openClawGatewayToken.isEmpty else {
      connectionState = .notConfigured
      return
    }
    connectionState = .checking
    let base = "\(settings.openClawHost):\(settings.openClawPort)"
    guard let url = URL(string: "\(base)/v1/chat/completions") else {
      connectionState = .unreachable("Invalid URL")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(settings.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    do {
      let (_, response) = try await pingSession.data(for: request)
      if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
        connectionState = .connected
        NSLog("[Agent:OpenClaw] Gateway reachable (HTTP %d)", http.statusCode)
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      NSLog("[Agent:OpenClaw] Gateway unreachable: %@", error.localizedDescription)
    }
  }

  func resetSession() {
    let newKey = AgentBridge.newSessionKey()
    sessionKey = newKey
    conversationHistory = []
    sandboxUrl = nil
    sandboxAuthToken = nil
    let settings = SettingsManager.shared
    settings.agentSessionKey = newKey
    settings.agentSessionCreatedAt = Date().timeIntervalSince1970
    NSLog("[Agent] Reset session: %@", newKey)
  }

  private static func newSessionKey() -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    return "agent:main:glass:\(ts)"
  }

  /// Inject prior conversation context (e.g. voice transcripts) into both
  /// the iOS-side history (for Vercel fallback / OpenClaw) and the E2B sandbox (for direct path)
  func injectContext(_ messages: [[String: String]]) {
    conversationHistory.insert(contentsOf: messages, at: 0)
    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }
    NSLog("[Agent:%@] Injected %d context messages (total: %d)", backend.rawValue, messages.count, conversationHistory.count)

    // Also inject into E2B sandbox's in-memory conversation state (E2B only)
    if backend == .e2b {
      Task {
        await injectContextToSandbox(messages)
      }
    }
  }

  /// Send context messages to the E2B sandbox so its in-memory conversation
  /// state includes voice transcripts and prior context
  private func injectContextToSandbox(_ messages: [[String: String]]) async {
    guard let sandboxUrl = sandboxUrl, let authToken = sandboxAuthToken else {
      NSLog("[Agent] No sandbox to inject context into")
      return
    }
    guard let url = URL(string: "\(sandboxUrl)/context") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 10

    let body: [String: Any] = ["messages": messages, "token": authToken]
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (_, response) = try await session.data(for: request)
      if let http = response as? HTTPURLResponse {
        NSLog("[Agent] Context injected to sandbox: HTTP %d", http.statusCode)
      }
    } catch {
      NSLog("[Agent] Failed to inject context to sandbox: %@", error.localizedDescription)
    }
  }

  // MARK: - Sandbox Init

  private func initSandbox() async throws {
    guard let url = URL(string: "\(AgentConfig.baseURL)/api/agent/init") else {
      throw AgentError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(AgentConfig.token, forHTTPHeaderField: "x-api-token")
    request.setValue(sessionKey, forHTTPHeaderField: "x-agent-session-key")
    request.setValue(SettingsManager.shared.userId, forHTTPHeaderField: "x-agent-user-id")
    request.httpBody = try JSONSerialization.data(withJSONObject: [String: String]())

    NSLog("[Agent] Initializing sandbox for session: %@", sessionKey)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw AgentError.httpError(code)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sbUrl = json["sandboxUrl"] as? String,
          let authToken = json["authToken"] as? String else {
      throw AgentError.invalidResponse
    }

    self.sandboxUrl = sbUrl
    self.sandboxAuthToken = authToken
    NSLog("[Agent] Sandbox initialized: %@", sbUrl)
  }

  // MARK: - Direct E2B Streaming

  private func sendToSandboxStreaming(prompt: String) async throws -> String {
    guard let sandboxUrl = sandboxUrl, let authToken = sandboxAuthToken else {
      throw AgentError.sandboxNotInitialized
    }

    guard let url = URL(string: "\(sandboxUrl)/stream") else {
      throw AgentError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 120

    var body: [String: Any] = ["prompt": prompt, "token": authToken]
    body["userId"] = SettingsManager.shared.userId
    if let googleToken = await GoogleAuthManager.shared.freshAccessToken() {
      body["googleAccessToken"] = googleToken
    }
    if let notionToken = NotionAuthManager.shared.accessToken() {
      body["notionAccessToken"] = notionToken
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    streamingText = ""

    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw AgentError.httpError(code)
    }

    var finalResult: String?
    var currentEvent = ""

    for try await line in bytes.lines {
      if line.hasPrefix("event: ") {
        currentEvent = String(line.dropFirst(7))
      } else if line.hasPrefix("data: ") {
        let dataStr = String(line.dropFirst(6))

        switch currentEvent {
        case "token":
          if let data = dataStr.data(using: .utf8),
             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let text = json["text"] as? String {
            // Mark thinking as done on first token
            if streamingText.isEmpty {
              if let idx = agentSteps.firstIndex(where: { $0.type == .thinking && !$0.isDone }) {
                agentSteps[idx].isDone = true
              }
            }
            streamingText += text
          }

        case "tool_start":
          if let data = dataStr.data(using: .utf8),
             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let tool = json["tool"] as? String {
            let input = json["input"] as? [String: Any]
            let label = Self.friendlyToolLabel(tool: tool, input: input)
            agentSteps.append(AgentStep(type: .tool(tool), label: label))
            NSLog("[Agent] Tool: %@", tool)
          }

        case "tool_done":
          if let data = dataStr.data(using: .utf8),
             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let tool = json["tool"] as? String {
            let success = json["success"] as? Bool ?? true
            // Find the last in-progress step for this tool and mark done
            if let idx = agentSteps.lastIndex(where: { $0.type == .tool(tool) && !$0.isDone }) {
              agentSteps[idx].isDone = true
              agentSteps[idx].success = success
            }
          }

        case "done":
          if let data = dataStr.data(using: .utf8),
             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let result = json["result"] as? String {
            finalResult = result
            NSLog("[Agent] Done. cost: %@, duration: %@ms",
                  String(describing: json["cost_usd"]),
                  String(describing: json["duration_ms"]))
          }

        case "error":
          if let data = dataStr.data(using: .utf8),
             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let error = json["error"] as? String {
            throw AgentError.serverError(error)
          }

        default:
          break
        }

        currentEvent = ""
      }
    }

    return finalResult ?? streamingText
  }

  // MARK: - Vercel Fallback

  private func sendViaVercel(prompt: String) async throws -> String {
    guard let url = URL(string: "\(AgentConfig.baseURL)/api/agent/chat") else {
      throw AgentError.invalidURL
    }

    conversationHistory.append(["role": "user", "content": prompt])
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
      "stream": false,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw AgentError.httpError(code)
    }

    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let choices = json["choices"] as? [[String: Any]],
       let first = choices.first,
       let message = first["message"] as? [String: Any],
       let content = message["content"] as? String {
      conversationHistory.append(["role": "assistant", "content": content])
      return content
    }

    let raw = String(data: data, encoding: .utf8) ?? "OK"
    conversationHistory.append(["role": "assistant", "content": raw])
    return raw
  }

  // MARK: - OpenClaw

  private func sendViaOpenClaw(prompt: String) async throws -> String {
    let settings = SettingsManager.shared
    let base = "\(settings.openClawHost):\(settings.openClawPort)"
    guard let url = URL(string: "\(base)/v1/chat/completions") else {
      throw AgentError.invalidURL
    }

    conversationHistory.append(["role": "user", "content": prompt])
    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(settings.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": conversationHistory,
      "stream": false,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    NSLog("[Agent:OpenClaw] Sending %d messages in conversation", conversationHistory.count)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw AgentError.httpError(code)
    }

    // Mark thinking as done
    if let idx = agentSteps.firstIndex(where: { $0.type == .thinking && !$0.isDone }) {
      agentSteps[idx].isDone = true
    }

    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let choices = json["choices"] as? [[String: Any]],
       let first = choices.first,
       let message = first["message"] as? [String: Any],
       let content = message["content"] as? String {
      conversationHistory.append(["role": "assistant", "content": content])
      streamingText = content
      return content
    }

    let raw = String(data: data, encoding: .utf8) ?? "OK"
    conversationHistory.append(["role": "assistant", "content": raw])
    streamingText = raw
    return raw
  }

  // MARK: - Public API

  func delegateTask(
    task: String,
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)
    streamingText = ""
    agentSteps = [AgentStep(type: .thinking, label: "Thinking...")]

    do {
      let content: String
      switch backend {
      case .e2b:
        content = try await sendDirectOrFallback(prompt: task)
      case .openClaw:
        content = try await sendViaOpenClaw(prompt: task)
      }
      NSLog("[Agent:%@] Result: %@", backend.rawValue, String(content.prefix(200)))
      if let idx = agentSteps.firstIndex(where: { $0.type == .thinking && !$0.isDone }) {
        agentSteps[idx].isDone = true
      }
      lastToolCallStatus = .completed(toolName)
      return .success(content)
    } catch {
      NSLog("[Agent:%@] Error: %@", backend.rawValue, error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Agent error: \(error.localizedDescription)")
    }
  }

  private func sendDirectOrFallback(prompt: String) async throws -> String {
    // Initialize sandbox if needed
    if sandboxUrl == nil {
      do {
        try await initSandbox()
      } catch {
        NSLog("[Agent] Init failed, falling back to Vercel: %@", error.localizedDescription)
        return try await sendViaVercel(prompt: prompt)
      }
    }

    // Try direct E2B streaming
    do {
      return try await sendToSandboxStreaming(prompt: prompt)
    } catch {
      NSLog("[Agent] Direct E2B failed: %@, re-initializing...", error.localizedDescription)
      // Sandbox may have expired -- re-init and retry once
      do {
        sandboxUrl = nil
        sandboxAuthToken = nil
        try await initSandbox()
        return try await sendToSandboxStreaming(prompt: prompt)
      } catch {
        NSLog("[Agent] Retry failed, falling back to Vercel: %@", error.localizedDescription)
        return try await sendViaVercel(prompt: prompt)
      }
    }
  }

  // MARK: - Friendly Labels

  /// Convert tool name + input into a user-friendly status label
  private static func friendlyToolLabel(tool: String, input: [String: Any]?) -> String {
    switch tool {
    case "Bash":
      if let cmd = input?["command"] as? String {
        let short = cmd.components(separatedBy: "\n").first ?? cmd
        let trimmed = short.count > 60 ? String(short.prefix(60)) + "..." : short
        return "Running: \(trimmed)"
      }
      return "Running command..."
    case "Read":
      if let path = input?["file_path"] as? String {
        let file = (path as NSString).lastPathComponent
        return "Reading \(file)"
      }
      return "Reading file..."
    case "Write":
      if let path = input?["file_path"] as? String {
        let file = (path as NSString).lastPathComponent
        return "Writing \(file)"
      }
      return "Writing file..."
    case "Edit":
      if let path = input?["file_path"] as? String {
        let file = (path as NSString).lastPathComponent
        return "Editing \(file)"
      }
      return "Editing file..."
    case "Glob":
      if let pattern = input?["pattern"] as? String {
        return "Searching: \(pattern)"
      }
      return "Searching files..."
    case "Grep":
      if let pattern = input?["pattern"] as? String {
        let short = pattern.count > 40 ? String(pattern.prefix(40)) + "..." : pattern
        return "Searching: \(short)"
      }
      return "Searching code..."
    case "WebSearch":
      if let query = input?["query"] as? String {
        return "Searching: \(query)"
      }
      return "Web search..."
    case "WebFetch":
      return "Fetching web page..."
    case "google_calendar_events":
      return "Checking calendar..."
    case "google_gmail_search":
      if let query = input?["query"] as? String {
        let short = query.count > 40 ? String(query.prefix(40)) + "..." : query
        return "Searching email: \(short)"
      }
      return "Searching email..."
    case "google_gmail_read":
      return "Reading email..."
    case "google_drive_search":
      if let query = input?["query"] as? String {
        let short = query.count > 40 ? String(query.prefix(40)) + "..." : query
        return "Searching Drive: \(short)"
      }
      return "Searching Drive..."
    case "google_drive_read":
      if let name = input?["file_name"] as? String {
        return "Reading \(name)"
      }
      return "Reading Drive file..."
    case "google_drive_create":
      if let name = input?["name"] as? String {
        return "Creating \(name)"
      }
      return "Creating Drive file..."
    case "google_drive_update":
      if let name = input?["file_name"] as? String {
        return "Updating \(name)"
      }
      return "Updating Drive file..."
    case "notion_search":
      if let query = input?["query"] as? String {
        let short = query.count > 40 ? String(query.prefix(40)) + "..." : query
        return "Searching Notion: \(short)"
      }
      return "Searching Notion..."
    case "notion_read_page":
      return "Reading Notion page..."
    case "notion_create_page":
      if let title = input?["title"] as? String {
        return "Creating \(title)"
      }
      return "Creating Notion page..."
    case "notion_update_page":
      return "Updating Notion page..."
    case "memory_read":
      return "Recalling memories..."
    case "memory_save":
      return "Saving to memory..."
    case "memory_delete":
      return "Removing memory..."
    case "memory_search":
      return "Searching memories..."
    case "memory_list":
      return "Checking memory..."
    default:
      return "Running \(tool)..."
    }
  }
}

// MARK: - Errors

private enum AgentError: LocalizedError {
  case invalidURL
  case httpError(Int)
  case invalidResponse
  case sandboxNotInitialized
  case serverError(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL: return "Invalid URL"
    case .httpError(let code): return "HTTP error \(code)"
    case .invalidResponse: return "Invalid response from server"
    case .sandboxNotInitialized: return "Sandbox not initialized"
    case .serverError(let msg): return "Server error: \(msg)"
    }
  }
}
