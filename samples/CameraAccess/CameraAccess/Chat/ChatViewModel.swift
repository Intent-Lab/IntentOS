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
  private let chatService = GeminiChatService()
  private let openClawBridge = OpenClawBridge()
  let geminiSessionVM = GeminiSessionViewModel()

  private var streamTask: Task<Void, Never>?
  private var voiceObservation: Task<Void, Never>?
  private var voiceTranscripts: [(role: ChatMessageRole, text: String)] = []
  private var lastUserTranscript: String = ""
  private var lastAITranscript: String = ""

  var streamingMode: StreamingMode = .glasses

  // MARK: - Text Mode

  func sendMessage() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSending else { return }

    inputText = ""
    isSending = true
    errorMessage = nil

    // Append user message
    messages.append(ChatMessage(role: .user, text: text))

    // Append streaming placeholder
    let assistantId = UUID().uuidString
    messages.append(ChatMessage(id: assistantId, role: .assistant, text: "", status: .streaming))

    streamTask = Task {
      do {
        let stream = chatService.sendMessage(text)
        try await consumeStream(stream, assistantMessageId: assistantId)
      } catch {
        updateLastAssistantMessage { msg in
          msg.status = .error(error.localizedDescription)
          if msg.text.isEmpty { msg.text = "Failed to get response." }
        }
      }
      isSending = false
    }
  }

  // MARK: - Voice Mode

  func startVoiceMode() async {
    guard !isVoiceModeActive else { return }
    isVoiceModeActive = true
    voiceTranscripts = []
    lastUserTranscript = ""
    lastAITranscript = ""

    geminiSessionVM.streamingMode = streamingMode

    // Start voice state observation
    voiceObservation = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled, let self else { break }
        self.voiceConnectionState = self.geminiSessionVM.connectionState
        self.isModelSpeaking = self.geminiSessionVM.isModelSpeaking
        self.toolCallStatus = self.geminiSessionVM.toolCallStatus

        // Track transcript pairs for chat history
        let newUser = self.geminiSessionVM.userTranscript
        let newAI = self.geminiSessionVM.aiTranscript

        // When user transcript appears
        if !newUser.isEmpty && newUser != self.lastUserTranscript {
          self.lastUserTranscript = newUser
        }
        self.userTranscript = newUser

        // When AI transcript appears
        if !newAI.isEmpty && newAI != self.lastAITranscript {
          self.lastAITranscript = newAI
        }
        self.aiTranscript = newAI

        // When a turn completes (transcripts get cleared), snapshot the pair
        if newUser.isEmpty && !self.lastUserTranscript.isEmpty {
          if !self.lastUserTranscript.isEmpty {
            self.voiceTranscripts.append((role: .user, text: self.lastUserTranscript))
          }
          if !self.lastAITranscript.isEmpty {
            self.voiceTranscripts.append((role: .assistant, text: self.lastAITranscript))
          }
          self.lastUserTranscript = ""
          self.lastAITranscript = ""
        }
      }
    }

    await geminiSessionVM.startSession()

    if !geminiSessionVM.isGeminiActive {
      // Failed to start
      isVoiceModeActive = false
      voiceObservation?.cancel()
      voiceObservation = nil
      errorMessage = geminiSessionVM.errorMessage ?? "Failed to start voice mode"
    }
  }

  func stopVoiceMode() {
    // Capture any remaining transcript pair
    if !lastUserTranscript.isEmpty {
      voiceTranscripts.append((role: .user, text: lastUserTranscript))
    }
    if !lastAITranscript.isEmpty {
      voiceTranscripts.append((role: .assistant, text: lastAITranscript))
    }

    geminiSessionVM.stopSession()
    voiceObservation?.cancel()
    voiceObservation = nil

    // Append voice transcripts to chat history
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

  private func consumeStream(_ stream: AsyncThrowingStream<GeminiChatEvent, Error>, assistantMessageId: String) async throws {
    for try await event in stream {
      guard !Task.isCancelled else { break }
      switch event {
      case .textDelta(let text):
        updateLastAssistantMessage { msg in
          msg.text += text
        }

      case .toolCall(let id, let name, let args):
        // Show tool call in chat
        updateLastAssistantMessage { msg in
          msg.status = .complete
        }
        let taskDesc = args["task"] as? String ?? String(describing: args)
        messages.append(ChatMessage(role: .toolCall, text: "Running: \(name)", status: .streaming, toolCallName: name))

        // Execute tool
        let result = await openClawBridge.delegateTask(task: taskDesc, toolName: name)

        // Update tool call message with result
        updateLastMessage(where: { $0.role == .toolCall && $0.toolCallName == name && $0.status == .streaming }) { msg in
          switch result {
          case .success(let text):
            msg.text = "Done: \(name)"
            msg.toolCallResult = text
            msg.status = .complete
          case .failure(let err):
            msg.text = "Failed: \(name)"
            msg.toolCallResult = err
            msg.status = .error(err)
          }
        }

        // Send tool result back to Gemini and continue streaming
        let resultValue = result.responseValue
        let followUpId = UUID().uuidString
        messages.append(ChatMessage(id: followUpId, role: .assistant, text: "", status: .streaming))

        let followUp = chatService.sendToolResponse(callId: id, name: name, result: resultValue)
        try await consumeStream(followUp, assistantMessageId: followUpId)
        return // The recursive call handles the rest

      case .done:
        updateLastAssistantMessage { msg in
          if msg.status == .streaming {
            msg.status = .complete
          }
        }
      }
    }
  }

  private func updateLastAssistantMessage(_ update: (inout ChatMessage) -> Void) {
    guard let idx = messages.lastIndex(where: { $0.role == .assistant }) else { return }
    update(&messages[idx])
  }

  private func updateLastMessage(where predicate: (ChatMessage) -> Bool, _ update: (inout ChatMessage) -> Void) {
    guard let idx = messages.lastIndex(where: predicate) else { return }
    update(&messages[idx])
  }
}
