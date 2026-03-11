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

    // Handle unexpected disconnection
    coord.voiceAgent.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }
        self.stopSession()
        self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
      }
    }

    // Start state observation (poll coordinator state -> @Published properties)
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
    let success = await coord.startSession(config: config, streamingMode: streamingMode)

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
      isGeminiActive = false
      connectionState = .disconnected
      return
    }
  }

  func stopSession() {
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
