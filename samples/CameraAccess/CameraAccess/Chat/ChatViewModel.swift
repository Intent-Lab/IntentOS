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
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle

  // MARK: - Dependencies
  let agentBridge = AgentBridge()
  let geminiSessionVM = GeminiSessionViewModel()

  private var sendTask: Task<Void, Never>?
  private var streamingObservation: Task<Void, Never>?
  private var voiceObservation: Task<Void, Never>?
  private var voiceTranscripts: [(role: ChatMessageRole, text: String)] = []
  private var lastUserTranscript: String = ""
  private var lastAITranscript: String = ""

  // Voice from chat always uses iPhone mode (speaker + mic co-located on phone)
  // Glasses streaming view sets its own mode when launched separately
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

  // MARK: - Voice Mode (Gemini Live + agent dual-agent)

  func startVoiceMode() async {
    guard !isVoiceModeActive else { return }
    isVoiceModeActive = true
    voiceTranscripts = []
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

        if !newUser.isEmpty && newUser != self.lastUserTranscript {
          self.lastUserTranscript = newUser
        }
        self.userTranscript = newUser

        if !newAI.isEmpty && newAI != self.lastAITranscript {
          self.lastAITranscript = newAI
        }
        self.aiTranscript = newAI

        // Snapshot transcript pair when turn completes (transcripts cleared)
        if newUser.isEmpty && !self.lastUserTranscript.isEmpty {
          if !self.lastUserTranscript.isEmpty {
            RemoteLogger.shared.log("voice:user", data: ["text": self.lastUserTranscript])
            self.voiceTranscripts.append((role: .user, text: self.lastUserTranscript))
          }
          if !self.lastAITranscript.isEmpty {
            RemoteLogger.shared.log("voice:ai", data: ["text": self.lastAITranscript])
            self.voiceTranscripts.append((role: .assistant, text: self.lastAITranscript))
          }
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
    // Cancel observation FIRST to prevent it from re-populating lastAITranscript
    // from VoiceAgent's stale aiTranscript (not cleared on turnComplete)
    voiceObservation?.cancel()
    voiceObservation = nil

    // Only append remaining transcripts if they haven't already been snapshotted
    if !lastUserTranscript.isEmpty {
      let alreadyCaptured = voiceTranscripts.last(where: { $0.role == .user })?.text == lastUserTranscript
      if !alreadyCaptured {
        voiceTranscripts.append((role: .user, text: lastUserTranscript))
      }
    }
    if !lastAITranscript.isEmpty {
      let alreadyCaptured = voiceTranscripts.last(where: { $0.role == .assistant })?.text == lastAITranscript
      if !alreadyCaptured {
        voiceTranscripts.append((role: .assistant, text: lastAITranscript))
      }
    }

    RemoteLogger.shared.log("session:voice_end", data: ["turns": String(voiceTranscripts.count)])
    geminiSessionVM.stopSession()

    // Bridge voice transcripts into agent's conversation history
    let contextMessages = voiceTranscripts.compactMap { transcript -> [String: String]? in
      let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      let role = transcript.role == .user ? "user" : "assistant"
      return ["role": role, "content": text]
    }
    if !contextMessages.isEmpty {
      agentBridge.injectContext(contextMessages)
    }

    for transcript in voiceTranscripts {
      if !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        messages.append(ChatMessage(role: transcript.role, text: transcript.text))
      }
    }

    isVoiceModeActive = false
    voiceConnectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
    voiceTranscripts = []
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
