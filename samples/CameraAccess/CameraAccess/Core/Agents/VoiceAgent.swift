import Foundation
import SwiftUI

/// VoiceAgent manages real-time voice interaction through a VoiceModelProvider.
/// It wires audio capture/playback, consumes the provider's event stream,
/// and exposes tool call events for the AgentCoordinator to route.
@MainActor
class VoiceAgent: ObservableObject {
  @Published var connectionState: VoiceModelConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""

  var onToolCall: ((String, String, [String: Any]) -> Void)?
  var onToolCallCancellation: (([String]) -> Void)?
  var onDisconnected: ((String?) -> Void)?

  private let provider: VoiceModelProvider
  let audioManager: AudioManager
  private var eventListenerTask: Task<Void, Never>?
  private var lastVideoFrameTime: Date = .distantPast

  var streamingMode: StreamingMode = .glasses

  init(provider: VoiceModelProvider, audioManager: AudioManager) {
    self.provider = provider
    self.audioManager = audioManager
  }

  func start(config: VoiceSessionConfig, streamingMode: StreamingMode) async -> Bool {
    self.streamingMode = streamingMode

    // Wire mic capture -> voice model
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        // Mute mic while model speaks when speaker is on the phone
        let speakerOnPhone = self.streamingMode == .iPhone || SettingsManager.shared.speakerOutputEnabled
        if speakerOnPhone && self.provider.isModelSpeaking { return }
        self.provider.sendAudio(data: data)
      }
    }

    // Setup audio session
    do {
      try audioManager.setupAudioSession(useIPhoneMode: streamingMode == .iPhone)
    } catch {
      connectionState = .error("Audio setup failed: \(error.localizedDescription)")
      return false
    }

    // Connect to voice model
    let success = await provider.connect(config: config)
    if !success {
      let msg: String
      if case .error(let err) = provider.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to voice model"
      }
      connectionState = .error(msg)
      return false
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      provider.disconnect()
      connectionState = .error("Mic capture failed: \(error.localizedDescription)")
      return false
    }

    connectionState = .ready

    // Start consuming the provider's event stream
    startEventListener()

    return true
  }

  func stop() {
    eventListenerTask?.cancel()
    eventListenerTask = nil
    audioManager.stopCapture()
    provider.disconnect()
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
  }

  func sendVideoFrameIfThrottled(image: UIImage) {
    guard connectionState == .ready else { return }
    let now = Date()
    guard now.timeIntervalSince(lastVideoFrameTime) >= GeminiConfig.videoFrameInterval else { return }
    lastVideoFrameTime = now
    provider.sendVideoFrame(image: image)
  }

  func sendToolResponse(_ response: [String: Any]) {
    provider.sendToolResponse(response)
  }

  // MARK: - Private

  private func startEventListener() {
    eventListenerTask = Task { [weak self] in
      guard let self else { return }
      for await event in self.provider.events {
        guard !Task.isCancelled else { break }
        switch event {
        case .audioResponse(let data):
          self.audioManager.playAudio(data: data)

        case .inputTranscription(let text):
          self.userTranscript += text
          self.aiTranscript = ""

        case .outputTranscription(let text):
          self.aiTranscript += text

        case .toolCall(let id, let name, let args):
          self.onToolCall?(id, name, args)

        case .toolCallCancellation(let ids):
          self.onToolCallCancellation?(ids)

        case .turnComplete:
          self.isModelSpeaking = false
          self.userTranscript = ""

        case .interrupted:
          self.isModelSpeaking = false
          self.audioManager.stopPlayback()

        case .modelSpeakingChanged(let speaking):
          self.isModelSpeaking = speaking

        case .sessionStarted:
          self.connectionState = .ready

        case .sessionEnded(let reason):
          self.connectionState = .disconnected
          self.isModelSpeaking = false
          self.onDisconnected?(reason)

        case .error(let msg):
          self.connectionState = .error(msg)
        }
      }
    }
  }
}
