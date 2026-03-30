import Foundation
import SwiftUI

@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var agentConnectionState: AgentConnectionState = .notConfigured

  private(set) var coordinator: AgentCoordinator?
  private var stateObservation: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private let eventClient = OpenClawEventClient()
  private var reconnectAttempts: Int = 0
  private let maxReconnectAttempts = 3
  private var lastSessionConfig: VoiceSessionConfig?
  private var lastStreamingMode: StreamingMode = .glasses

  var streamingMode: StreamingMode = .glasses
  var conversationContext: String?
  var sharedAgentBridge: AgentBridge?

  func startSession() async {
    guard !isGeminiActive else { return }

    guard GeminiConfig.isConfigured else {
      errorMessage = "Gemini API key not configured. Open GeminiConfig.swift and replace YOUR_GEMINI_API_KEY with your key from https://aistudio.google.com/apikey"
      return
    }

    isGeminiActive = true
    reconnectAttempts = 0

    // Build config with conversation context if available
    var instruction = GeminiConfig.systemInstruction
    if let ctx = conversationContext, !ctx.isEmpty {
      instruction += "\n\n[Recent conversation for context -- the user may refer to this]\n\(ctx)"
    }
    let config = VoiceSessionConfig(
      systemInstruction: instruction,
      toolDeclarations: ToolDeclarations.allDeclarations(),
      responseModalities: ["AUDIO"]
    )
    lastSessionConfig = config
    lastStreamingMode = streamingMode

    let success = await connectSession(config: config)
    if !success {
      isGeminiActive = false
      connectionState = .disconnected
    }
  }

  /// Internal: create coordinator, connect, and start observation
  private func connectSession(config: VoiceSessionConfig) async -> Bool {
    // Create the dual-agent stack
    let provider = GeminiLiveProvider()
    let audioManager = AudioManager()
    let agentBridge = sharedAgentBridge ?? AgentBridge()

    let coord = AgentCoordinator(
      voiceModelProvider: provider,
      audioManager: audioManager,
      agentBridge: agentBridge
    )
    self.coordinator = coord

    // Handle unexpected disconnection -- attempt auto-reconnect
    coord.voiceAgent.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }
        NSLog("[Voice] Disconnected: %@", reason ?? "unknown")
        self.attemptReconnect(reason: reason)
      }
    }

    // Start state observation (poll coordinator state -> @Published properties)
    stateObservation?.cancel()
    stateObservation = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled, let self, let coord = self.coordinator else { break }
        self.connectionState = coord.voiceAgent.connectionState.asGeminiState
        self.isModelSpeaking = coord.voiceAgent.isModelSpeaking
        self.userTranscript = coord.voiceAgent.userTranscript
        self.aiTranscript = coord.voiceAgent.aiTranscript
        self.toolCallStatus = coord.toolCallStatus
        self.agentConnectionState = coord.agentConnectionState
      }
    }

    let success = await coord.startSession(config: config, streamingMode: lastStreamingMode)

    if !success {
      let msg: String
      if case .error(let err) = coord.voiceAgent.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to Gemini"
      }
      errorMessage = msg
      stateObservation?.cancel()
      stateObservation = nil
      coordinator = nil
      return false
    }

    reconnectAttempts = 0

    // Connect event client for proactive notifications (OpenClaw only)
    if SettingsManager.shared.proactiveNotificationsEnabled &&
       SettingsManager.shared.agentBackend == .openClaw {
      eventClient.onNotification = { [weak self] text in
        guard let self else { return }
        Task { @MainActor in
          guard self.isGeminiActive, self.connectionState == .ready else { return }
          self.coordinator?.voiceAgent.sendTextMessage(text)
        }
      }
      eventClient.connect()
    }

    return true
  }

  private func attemptReconnect(reason: String?) {
    // Clean up old coordinator without fully stopping (keep isGeminiActive = true)
    coordinator?.stopSession()
    coordinator = nil
    stateObservation?.cancel()
    stateObservation = nil
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle

    reconnectAttempts += 1
    if reconnectAttempts > maxReconnectAttempts {
      NSLog("[Voice] Max reconnect attempts reached, stopping")
      isGeminiActive = false
      connectionState = .disconnected
      errorMessage = "Connection lost: \(reason ?? "Unknown error")"
      return
    }

    NSLog("[Voice] Reconnecting (attempt %d/%d)...", reconnectAttempts, maxReconnectAttempts)
    connectionState = .connecting

    reconnectTask?.cancel()
    reconnectTask = Task { [weak self] in
      // Brief delay before reconnecting (increases with each attempt)
      let delayMs = UInt64(reconnectAttempts) * 1_000_000_000 // 1s, 2s, 3s
      try? await Task.sleep(nanoseconds: delayMs)
      guard !Task.isCancelled, let self, self.isGeminiActive else { return }

      // Rebuild config with current conversation context
      var instruction = GeminiConfig.systemInstruction
      if let ctx = self.conversationContext, !ctx.isEmpty {
        instruction += "\n\n[Recent conversation for context -- the user may refer to this]\n\(ctx)"
      }
      let config = VoiceSessionConfig(
        systemInstruction: instruction,
        toolDeclarations: ToolDeclarations.allDeclarations(),
        responseModalities: ["AUDIO"]
      )

      let success = await self.connectSession(config: config)
      if success {
        NSLog("[Voice] Reconnected successfully")
      } else {
        NSLog("[Voice] Reconnect failed, will retry")
        // connectSession already set errorMessage; attemptReconnect will be called
        // again by the new coordinator's onDisconnected if it fails to connect
        if self.isGeminiActive && self.reconnectAttempts <= self.maxReconnectAttempts {
          self.attemptReconnect(reason: "Reconnect failed")
        } else {
          self.isGeminiActive = false
          self.connectionState = .disconnected
        }
      }
    }
  }

  func stopSession() {
    // Flush memory before tearing down (fire-and-forget)
    if let bridge = sharedAgentBridge {
      Task { await bridge.flushMemory() }
    }
    eventClient.disconnect()
    reconnectTask?.cancel()
    reconnectTask = nil
    reconnectAttempts = 0
    coordinator?.stopSession()
    coordinator = nil
    stateObservation?.cancel()
    stateObservation = nil
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
  }

  func sendVideoFrameIfThrottled(image: UIImage) {
    guard isGeminiActive, connectionState == .ready else { return }
    coordinator?.sendVideoFrame(image)
  }

}
