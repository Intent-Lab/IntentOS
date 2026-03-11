import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
  // MARK: - Published State
  @Published var messages: [ChatMessage] = []
  @Published var inputText: String = ""
  @Published var isSending: Bool = false
  @Published var errorMessage: String?

  // Voice mode
  @Published var isVoiceModeActive: Bool = false
  @Published var voiceConnectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var toolCallStatus: ToolCallStatus = .idle

  // MARK: - Dependencies
  let agentBridge = AgentBridge()
  let geminiSessionVM = GeminiSessionViewModel()

  private var sendTask: Task<Void, Never>?
  private var streamingObservation: Task<Void, Never>?
  private var voiceObservation: Task<Void, Never>?

  // Voice mode: live bubble IDs for the current turn
  private var activeUserBubbleId: String?
  private var activeAIBubbleId: String?
  private var lastUserTranscript: String = ""
  private var lastAITranscript: String = ""
  private var voiceSessionStartIndex: Int = 0

  // Agent card tracking (voice + text mode)
  private var lastToolCallStatus: ToolCallStatus = .idle
  private var agentCardId: String?          // single card message for agent execution
  private var lastAgentStreamingText: String = ""
  private var lastRenderedStepCount: Int = 0

  // Voice from chat always uses iPhone mode (speaker + mic co-located on phone)
  var streamingMode: StreamingMode = .iPhone

  // MARK: - Text Mode (sends directly to agent backend)

  func sendMessage() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSending else { return }

    inputText = ""
    isSending = true
    errorMessage = nil

    messages.append(ChatMessage(role: .user, text: text))
    // Create an agent card for the response
    let card = ChatMessage(role: .assistant, text: "", status: .streaming, isAgentResult: true)
    messages.append(card)
    let cardId = card.id
    agentCardId = cardId
    RemoteLogger.shared.log("chat:user", data: ["text": text])

    // Observe streaming text + agent steps from the agent bridge
    streamingObservation?.cancel()
    lastRenderedStepCount = 0
    streamingObservation = Task { [weak self] in
      var lastText = ""
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms polling
        guard let self, !Task.isCancelled else { break }

        let steps = self.agentBridge.agentSteps
        let current = self.agentBridge.streamingText
        let stepsChanged = steps.count != self.lastRenderedStepCount ||
          steps.enumerated().contains(where: { i, s in i < self.lastRenderedStepCount && s.isDone })
        let textChanged = current != lastText && !current.isEmpty

        if stepsChanged || textChanged {
          if textChanged { lastText = current }
          self.lastRenderedStepCount = steps.count
          self.updateMessage(id: cardId) { msg in
            msg.agentSteps = steps
            if !current.isEmpty {
              msg.text = current
            }
            msg.status = .streaming
          }
        }
      }
    }

    sendTask = Task {
      // Check agent connectivity first
      if agentBridge.connectionState == .notConfigured {
        await agentBridge.checkConnection()
      }

      let result = await agentBridge.delegateTask(task: text)

      // Stop streaming observation before final update
      self.streamingObservation?.cancel()
      self.streamingObservation = nil

      let finalSteps = self.agentBridge.agentSteps
      switch result {
      case .success(let response):
        RemoteLogger.shared.log("chat:agent", data: ["text": String(response.prefix(500))])
        self.updateMessage(id: cardId) { msg in
          msg.text = response
          msg.agentSteps = finalSteps
          msg.status = .complete
        }
      case .failure(let error):
        RemoteLogger.shared.log("chat:error", data: ["error": error])
        self.updateMessage(id: cardId) { msg in
          msg.text = "Failed to reach agent: \(error)"
          msg.agentSteps = finalSteps
          msg.status = .error(error)
        }
      }

      isSending = false
    }
  }

  // MARK: - Voice Mode (Gemini Live, inline in chat)

  func startVoiceMode() async {
    guard !isVoiceModeActive else { return }
    isVoiceModeActive = true
    activeUserBubbleId = nil
    activeAIBubbleId = nil
    lastUserTranscript = ""
    lastAITranscript = ""
    voiceSessionStartIndex = messages.count

    geminiSessionVM.streamingMode = streamingMode
    geminiSessionVM.sharedAgentBridge = agentBridge

    // Bridge text conversation context into Gemini's system instruction
    let recentMessages = messages.suffix(10)
    let contextLines = recentMessages.compactMap { msg -> String? in
      let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      switch msg.role {
      case .user: return "User: \(text)"
      case .assistant: return "Assistant: \(text)"
      case .toolCall: return nil
      }
    }
    geminiSessionVM.conversationContext = contextLines.isEmpty ? nil : contextLines.joined(separator: "\n")

    voiceObservation = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms - read VoiceAgent directly
        guard !Task.isCancelled, let self else { break }

        // Read directly from VoiceAgent to avoid the extra 100ms polling layer
        let coord = self.geminiSessionVM.coordinator
        let voiceAgent = coord?.voiceAgent

        let newConnectionState = self.geminiSessionVM.connectionState
        // When reconnecting, update conversation context with all messages so far
        if newConnectionState == .connecting && self.voiceConnectionState != .connecting {
          let recentMessages = self.messages.suffix(20)
          let contextLines = recentMessages.compactMap { msg -> String? in
            let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch msg.role {
            case .user: return "User: \(text)"
            case .assistant: return "Assistant: \(text)"
            case .toolCall: return nil
            }
          }
          self.geminiSessionVM.conversationContext = contextLines.isEmpty ? nil : contextLines.joined(separator: "\n")
        }
        self.voiceConnectionState = newConnectionState
        self.isModelSpeaking = voiceAgent?.isModelSpeaking ?? false

        let currentToolStatus = coord?.toolCallStatus ?? .idle
        self.toolCallStatus = currentToolStatus

        let newUser = voiceAgent?.userTranscript ?? ""
        let newAI = voiceAgent?.aiTranscript ?? ""

        // --- Agent card: create/update a single card for agent execution ---
        if currentToolStatus != self.lastToolCallStatus {
          if case .executing = currentToolStatus {
            // Finalize current AI bubble before showing agent card
            if let aiId = self.activeAIBubbleId {
              self.updateMessage(id: aiId) { msg in msg.status = .complete }
              self.activeAIBubbleId = nil
            }
            // Create agent card
            let card = ChatMessage(
              role: .assistant, text: "", status: .streaming,
              isAgentResult: true, agentSteps: self.agentBridge.agentSteps
            )
            self.messages.append(card)
            self.agentCardId = card.id
            self.lastAgentStreamingText = ""
            self.lastRenderedStepCount = 0
          } else if case .completed = currentToolStatus {
            // Finalize agent card
            if let cardId = self.agentCardId {
              self.updateMessage(id: cardId) { msg in
                msg.agentSteps = self.agentBridge.agentSteps
                msg.status = .complete
              }
            }
            self.agentCardId = nil
            self.lastAgentStreamingText = ""
            // Reset AI tracking so Gemini's summary appears as a new bubble
            self.lastAITranscript = ""
            self.activeAIBubbleId = nil
          } else if case .failed = currentToolStatus {
            if let cardId = self.agentCardId {
              self.updateMessage(id: cardId) { msg in
                msg.agentSteps = self.agentBridge.agentSteps
                msg.status = .error("Agent failed")
              }
            }
            self.agentCardId = nil
            self.lastAgentStreamingText = ""
          }
          self.lastToolCallStatus = currentToolStatus
        }

        // Update agent card with new steps and streaming text
        if case .executing = currentToolStatus, let cardId = self.agentCardId {
          let steps = self.agentBridge.agentSteps
          let agentText = self.agentBridge.streamingText
          let stepsChanged = steps.count != self.lastRenderedStepCount
          let textChanged = !agentText.isEmpty && agentText != self.lastAgentStreamingText

          if stepsChanged || textChanged {
            self.lastRenderedStepCount = steps.count
            if textChanged { self.lastAgentStreamingText = agentText }
            self.updateMessage(id: cardId) { msg in
              msg.agentSteps = steps
              if !agentText.isEmpty {
                msg.text = agentText
              }
            }
          }
        }

        // --- Live user bubble ---
        if !newUser.isEmpty {
          if newUser != self.lastUserTranscript {
            if self.activeUserBubbleId == nil {
              // New user turn starting -- reset AI tracking so next AI response is fresh
              self.lastAITranscript = ""
              self.activeAIBubbleId = nil

              let bubble = ChatMessage(role: .user, text: newUser, status: .streaming)
              self.messages.append(bubble)
              self.activeUserBubbleId = bubble.id
            } else {
              self.updateMessage(id: self.activeUserBubbleId!) { msg in
                msg.text = newUser
              }
            }
            self.lastUserTranscript = newUser
          }
        }

        // --- Live AI bubble ---
        if !newAI.isEmpty && newAI != self.lastAITranscript {
          // Finalize user bubble when AI starts responding
          if let userId = self.activeUserBubbleId {
            self.updateMessage(id: userId) { msg in
              msg.status = .complete
            }
          }

          if self.activeAIBubbleId == nil {
            let bubble = ChatMessage(role: .assistant, text: newAI, status: .streaming)
            self.messages.append(bubble)
            self.activeAIBubbleId = bubble.id
          } else {
            self.updateMessage(id: self.activeAIBubbleId!) { msg in
              msg.text = newAI
            }
          }
          self.lastAITranscript = newAI
        }

        // --- Turn complete: user transcript cleared by VoiceAgent ---
        if newUser.isEmpty && self.activeUserBubbleId != nil {
          if let userId = self.activeUserBubbleId {
            self.updateMessage(id: userId) { msg in
              msg.status = .complete
            }
          }
          if let aiId = self.activeAIBubbleId {
            self.updateMessage(id: aiId) { msg in
              msg.status = .complete
            }
          }
          // Reset user bubble but KEEP lastAITranscript to prevent
          // stale aiTranscript (not cleared by VoiceAgent on turnComplete)
          // from creating a duplicate AI bubble
          self.activeUserBubbleId = nil
          self.activeAIBubbleId = nil
          self.lastUserTranscript = ""
          // lastAITranscript intentionally NOT reset here
        }
      }
    }

    RemoteLogger.shared.log("session:voice_start")
    await geminiSessionVM.startSession()

    if !geminiSessionVM.isGeminiActive {
      isVoiceModeActive = false
      voiceObservation?.cancel()
      voiceObservation = nil
      errorMessage = geminiSessionVM.errorMessage ?? "Failed to start voice mode"
    }
  }

  func stopVoiceMode() {
    voiceObservation?.cancel()
    voiceObservation = nil

    // Finalize any in-progress bubbles
    if let userId = activeUserBubbleId {
      updateMessage(id: userId) { msg in msg.status = .complete }
    }
    if let aiId = activeAIBubbleId {
      updateMessage(id: aiId) { msg in msg.status = .complete }
    }
    if let cardId = agentCardId {
      updateMessage(id: cardId) { msg in msg.status = .complete }
    }

    RemoteLogger.shared.log("session:voice_end")
    geminiSessionVM.stopSession()

    // Bridge voice session messages into the agent's conversation history
    // Only inject messages added during this voice session (not prior text chat)
    let voiceSessionMessages = Array(messages.suffix(from: voiceSessionStartIndex))
    let contextMessages = voiceSessionMessages.compactMap { msg -> [String: String]? in
      let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      switch msg.role {
      case .user: return ["role": "user", "content": text]
      case .assistant: return ["role": "assistant", "content": text]
      case .toolCall: return nil
      }
    }
    if !contextMessages.isEmpty {
      agentBridge.injectContext(contextMessages)
    }

    isVoiceModeActive = false
    voiceConnectionState = .disconnected
    isModelSpeaking = false
    toolCallStatus = .idle
    activeUserBubbleId = nil
    activeAIBubbleId = nil
    lastUserTranscript = ""
    lastAITranscript = ""
    lastToolCallStatus = .idle
    agentCardId = nil
    lastAgentStreamingText = ""
    lastRenderedStepCount = 0
  }

  func sendVideoFrame(_ image: UIImage) {
    if isVoiceModeActive {
      geminiSessionVM.sendVideoFrameIfThrottled(image: image)
    }
  }

  // MARK: - Private

  private func updateMessage(id: String, _ update: (inout ChatMessage) -> Void) {
    guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
    update(&messages[idx])
  }
}
