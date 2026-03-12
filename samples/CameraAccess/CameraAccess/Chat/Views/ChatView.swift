import MWDATCore
import SwiftUI

struct ChatView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesVM: WearablesViewModel
  @StateObject private var viewModel = ChatViewModel()
  @StateObject private var streamVM: StreamSessionViewModel

  @State private var showSettings = false
  @State private var showGallery = false
  @State private var showGlassesStream = false
  @FocusState private var isInputFocused: Bool

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesVM = wearablesVM
    self._streamVM = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
  }

  var body: some View {
    VStack(spacing: 0) {
      ChatTopBar(
        showGlassesButton: wearablesVM.registrationState == .registered || wearablesVM.hasMockDevice,
        onGlassesTapped: { showGlassesStream = true },
        onGalleryTapped: { showGallery = true },
        onSettingsTapped: { showSettings = true }
      )

      ZStack(alignment: .bottom) {
        ChatMessageList(messages: viewModel.messages)
          .padding(.bottom, 56)

        ChatInputBar(
          text: $viewModel.inputText,
          isSending: viewModel.isSending,
          isVoiceModeActive: viewModel.isVoiceModeActive,
          isModelSpeaking: viewModel.isModelSpeaking,
          voiceConnectionState: viewModel.voiceConnectionState,
          isInputFocused: $isInputFocused,
          onSend: {
            isInputFocused = false
            viewModel.sendMessage()
          },
          onVoiceTapped: {
            isInputFocused = false
            Task { await viewModel.startVoiceMode() }
          },
          onVoiceStop: {
            viewModel.stopVoiceMode()
          }
        )
      }
    }
    .task {
      // Wire glasses frames to the shared GeminiSessionViewModel
      streamVM.geminiSessionVM = viewModel.geminiSessionVM
    }
    .onChange(of: viewModel.voiceConnectionState) { state in
      // Auto-start glasses streaming AFTER voice session is fully connected
      // (audio setup is done at this point, so it won't disrupt Bluetooth)
      if state == .ready && streamVM.hasActiveDevice && !streamVM.isStreaming {
        Task { await streamVM.handleStartStreaming() }
      }
    }
    .sheet(isPresented: $showGallery) {
      GalleryView()
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .fullScreenCover(isPresented: $showGlassesStream) {
      ZStack(alignment: .topLeading) {
        StreamSessionView(wearables: wearables, wearablesVM: wearablesVM, streamVM: streamVM, geminiVM: viewModel.geminiSessionVM)

        Button {
          showGlassesStream = false
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .shadow(radius: 4)
        }
        .accessibilityLabel("Close glasses streaming")
        .padding(.leading, 16)
        .padding(.top, 16)
      }
    }
    .alert("Error", isPresented: .init(
      get: { viewModel.errorMessage != nil },
      set: { if !$0 { viewModel.errorMessage = nil } }
    )) {
      Button("OK") { viewModel.errorMessage = nil }
    } message: {
      Text(viewModel.errorMessage ?? "")
    }
  }
}
