import Foundation
import SwiftUI

/// AgentCoordinator orchestrates the dual-agent architecture:
/// - VoiceAgent handles real-time voice conversation (synchronous)
/// - ActionAgent executes tasks in the background (asynchronous)
///
/// When the voice model requests a tool call, the coordinator routes it
/// to the ActionAgent. When the ActionAgent completes, the result is
/// sent back through the VoiceAgent to the voice model.
@MainActor
class AgentCoordinator: ObservableObject {
  let voiceAgent: VoiceAgent
  let actionAgent: ActionAgent
  private let agentBridge: AgentBridge

  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var agentConnectionState: AgentConnectionState = .notConfigured

  private var stateObservation: Task<Void, Never>?

  init(
    voiceModelProvider: VoiceModelProvider,
    audioManager: AudioManager,
    agentBridge: AgentBridge
  ) {
    self.agentBridge = agentBridge
    self.voiceAgent = VoiceAgent(provider: voiceModelProvider, audioManager: audioManager)
    self.actionAgent = ActionAgent(bridge: agentBridge)
    wireAgents()
  }

  func startSession(config: VoiceSessionConfig, streamingMode: StreamingMode) async -> Bool {
    // Check agent connectivity
    await agentBridge.checkConnection()
    agentBridge.resetSession()

    // Start state observation
    startStateObservation()

    // Start voice agent (connects to model, starts audio)
    let success = await voiceAgent.start(config: config, streamingMode: streamingMode)
    return success
  }

  func stopSession() {
    actionAgent.cancelAll()
    voiceAgent.stop()
    stateObservation?.cancel()
    stateObservation = nil
    toolCallStatus = .idle
  }

  func sendVideoFrame(_ image: UIImage) {
    voiceAgent.sendVideoFrameIfThrottled(image: image)
  }

  // MARK: - Private

  private func wireAgents() {
    // Voice Agent -> Action Agent: route tool calls
    voiceAgent.onToolCall = { [weak self] id, name, args in
      guard let self else { return }
      let taskDesc = args["task"] as? String ?? String(describing: args)
      RemoteLogger.shared.log("voice:tool_call", data: ["tool": name, "task": taskDesc])
      let task = AgentTask(id: id, name: name, description: taskDesc)
      self.actionAgent.executeTask(task)
    }

    voiceAgent.onToolCallCancellation = { [weak self] ids in
      guard let self else { return }
      for id in ids {
        self.actionAgent.cancelTask(id: id)
      }
    }

    // Action Agent -> Voice Agent: deliver results back to voice model
    actionAgent.onResult = { [weak self] result in
      let resultText: String
      switch result.result {
      case .success(let s): resultText = s
      case .failure(let e): resultText = "ERROR: \(e)"
      }
      RemoteLogger.shared.log("voice:tool_result", data: ["tool": result.toolName, "result": String(resultText.prefix(500))])
      self?.voiceAgent.sendToolResponse(result.responsePayload)
    }
  }

  private func startStateObservation() {
    stateObservation = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled, let self else { break }
        self.toolCallStatus = self.agentBridge.lastToolCallStatus
        self.agentConnectionState = self.agentBridge.connectionState
      }
    }
  }
}
