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
    messages.append(ChatMessage(role: .assistant, text: "", status: .streaming))
    RemoteLogger.shared.log("chat:user", data: ["text": text])

    // Track the placeholder message ID so we only update that specific bubble
    let placeholderId = messages.last!.id

    // Observe streaming text updates from the agent bridge
    streamingObservation?.cancel()
    streamingObservation = Task { [weak self] in
      var lastText = ""
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms polling
        guard let self, !Task.isCancelled else { break }
        let current = self.agentBridge.streamingText
        if current != lastText && !current.isEmpty {
          lastText = current
          self.updateMessage(id: placeholderId) { msg in
            msg.text = current
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

      switch result {
      case .success(let response):
        RemoteLogger.shared.log("chat:agent", data: ["text": String(response.prefix(500))])
        self.updateMessage(id: placeholderId) { msg in
          msg.text = response
          msg.status = .complete
        }
      case .failure(let error):
        RemoteLogger.shared.log("chat:error", data: ["error": error])
        self.updateMessage(id: placeholderId) { msg in
          msg.text = "Failed to reach agent: \(error)"
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
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled, let self else { break }
        self.voiceConnectionState = self.geminiSessionVM.connectionState
        self.isModelSpeaking = self.geminiSessionVM.isModelSpeaking
        self.toolCallStatus = self.geminiSessionVM.toolCallStatus

        let newUser = self.geminiSessionVM.userTranscript
        let newAI = self.geminiSessionVM.aiTranscript

        // --- Live user bubble ---
        if !newUser.isEmpty {
          if newUser != self.lastUserTranscript {
            if self.activeUserBubbleId == nil {
              // New user turn: create a bubble
              let bubble = ChatMessage(role: .user, text: newUser, status: .streaming)
              self.messages.append(bubble)
              self.activeUserBubbleId = bubble.id
            } else {
              // Update existing bubble
              self.updateMessage(id: self.activeUserBubbleId!) { msg in
                msg.text = newUser
              }
            }
            self.lastUserTranscript = newUser
          }
        }

        // --- Live AI bubble ---
        if !newAI.isEmpty {
          if newAI != self.lastAITranscript {
            // Finalize user bubble when AI starts responding
            if let userId = self.activeUserBubbleId {
              self.updateMessage(id: userId) { msg in
                msg.status = .complete
              }
            }

            if self.activeAIBubbleId == nil {
              // New AI turn: create a bubble
              let bubble = ChatMessage(role: .assistant, text: newAI, status: .streaming)
              self.messages.append(bubble)
              self.activeAIBubbleId = bubble.id
            } else {
              // Update existing bubble
              self.updateMessage(id: self.activeAIBubbleId!) { msg in
                msg.text = newAI
              }
            }
            self.lastAITranscript = newAI
          }
        }

        // --- Turn complete: user transcript cleared by VoiceAgent ---
        if newUser.isEmpty && self.activeUserBubbleId != nil {
          // Finalize both bubbles for this turn
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
          // Reset for next turn
          self.activeUserBubbleId = nil
          self.activeAIBubbleId = nil
          self.lastUserTranscript = ""
          self.lastAITranscript = ""
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

    RemoteLogger.shared.log("session:voice_end")
    geminiSessionVM.stopSession()

    // Bridge voice messages into agent's conversation history
    // Collect all messages added during this voice session (user + assistant after voice started)
    let voiceMessages = messages.compactMap { msg -> [String: String]? in
      let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      switch msg.role {
      case .user: return ["role": "user", "content": text]
      case .assistant: return ["role": "assistant", "content": text]
      case .toolCall: return nil
      }
    }
    if !voiceMessages.isEmpty {
      agentBridge.injectContext(voiceMessages)
    }

    isVoiceModeActive = false
    voiceConnectionState = .disconnected
    isModelSpeaking = false
    toolCallStatus = .idle
    activeUserBubbleId = nil
    activeAIBubbleId = nil
    lastUserTranscript = ""
    lastAITranscript = ""
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
