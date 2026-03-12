import CallKit
import AVFoundation

/// Manages CallKit integration so the voice session appears as a phone call on iOS.
/// This gives us: lock screen call UI, background audio keep-alive, green status bar pill,
/// and native mute/end controls.
@MainActor
class CallManager: NSObject, ObservableObject {
  static let shared = CallManager()

  @Published var isCallActive: Bool = false {
    didSet { CallManager._isCallActiveAtomic = isCallActive }
  }
  @Published var isMuted: Bool = false

  /// Thread-safe read for non-MainActor code (e.g. AudioManager)
  private(set) nonisolated(unsafe) static var _isCallActiveAtomic: Bool = false

  // Callbacks for coordinating with the voice pipeline
  var onAudioActivated: (() -> Void)?
  var onAudioDeactivated: (() -> Void)?
  var onCallEnded: (() -> Void)?
  var onMuteToggled: ((Bool) -> Void)?

  private let provider: CXProvider
  private let callController = CXCallController()
  private var activeCallUUID: UUID?
  private var audioActivationContinuation: CheckedContinuation<Void, Never>?

  override init() {
    let config = CXProviderConfiguration()
    config.supportsVideo = false
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]

    self.provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil) // nil = main queue
  }

  /// Start a "call" -- shows the green call bar and lock screen UI
  func startCall(displayName: String = "Matcha") {
    let uuid = UUID()
    activeCallUUID = uuid

    let handle = CXHandle(type: .generic, value: displayName)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = false
    action.contactIdentifier = displayName

    let transaction = CXTransaction(action: action)
    callController.request(transaction) { error in
      if let error {
        NSLog("[CallKit] Start call failed: %@", error.localizedDescription)
      } else {
        NSLog("[CallKit] Start call requested")
      }
    }
  }

  /// End the active call
  func endCall() {
    guard let uuid = activeCallUUID else { return }

    let action = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: action)
    callController.request(transaction) { error in
      if let error {
        NSLog("[CallKit] End call failed: %@", error.localizedDescription)
      } else {
        NSLog("[CallKit] End call requested")
      }
    }
  }

  /// Report that the outgoing call has connected (updates UI from "Calling..." to timer)
  func reportCallConnected() {
    guard let uuid = activeCallUUID else { return }
    provider.reportOutgoingCall(with: uuid, connectedAt: Date())
  }

  /// Start a call and wait until CallKit activates the audio session.
  /// Returns once didActivate fires, so the caller can safely start audio capture.
  func startCallAndWaitForAudio(displayName: String = "Matcha") async {
    startCall(displayName: displayName)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      self.audioActivationContinuation = continuation
    }
  }
}

// MARK: - CXProviderDelegate

extension CallManager: CXProviderDelegate {

  nonisolated func providerDidReset(_ provider: CXProvider) {
    NSLog("[CallKit] Provider did reset")
    Task { @MainActor in
      self.activeCallUUID = nil
      self.isCallActive = false
      self.isMuted = false
      self.onCallEnded?()
    }
  }

  nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    NSLog("[CallKit] Perform start call")

    // Do NOT configure the audio session here -- it disrupts the Bluetooth connection
    // to the glasses. AudioManager.setupAudioSession() handles configuration later,
    // after CallKit's didActivate fires.

    // Report connecting
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

    Task { @MainActor in
      self.isCallActive = true
    }

    action.fulfill()
  }

  nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    NSLog("[CallKit] Perform end call")
    Task { @MainActor in
      self.activeCallUUID = nil
      self.isCallActive = false
      self.isMuted = false
      self.onCallEnded?()
    }
    action.fulfill()
  }

  nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    NSLog("[CallKit] Mute toggled: %@", action.isMuted ? "ON" : "OFF")
    Task { @MainActor in
      self.isMuted = action.isMuted
      self.onMuteToggled?(action.isMuted)
    }
    action.fulfill()
  }

  nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    NSLog("[CallKit] Hold toggled: %@", action.isOnHold ? "ON" : "OFF")
    // For now, treat hold as end
    if action.isOnHold {
      Task { @MainActor in
        self.onCallEnded?()
      }
    }
    action.fulfill()
  }

  // CRITICAL: Audio session activated by CallKit -- NOW safe to start audio engine
  nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    NSLog("[CallKit] Audio session ACTIVATED")
    Task { @MainActor in
      // Resume any awaiting startCallAndWaitForAudio() call
      self.audioActivationContinuation?.resume()
      self.audioActivationContinuation = nil
      self.onAudioActivated?()
    }
  }

  // Audio session deactivated -- stop audio engine
  nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    NSLog("[CallKit] Audio session DEACTIVATED")
    Task { @MainActor in
      self.onAudioDeactivated?()
    }
  }
}
