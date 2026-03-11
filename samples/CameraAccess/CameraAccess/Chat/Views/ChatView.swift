import MWDATCore
import SwiftUI

struct ChatView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesVM: WearablesViewModel
  @StateObject private var viewModel = ChatViewModel()

  @State private var showSettings = false
  @State private var showGlassesStream = false
  @FocusState private var isInputFocused: Bool

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesVM = wearablesVM
  }

  var body: some View {
    VStack(spacing: 0) {
      ChatTopBar(
        showGlassesButton: wearablesVM.registrationState == .registered || wearablesVM.hasMockDevice,
        onGlassesTapped: { showGlassesStream = true },
        onSettingsTapped: { showSettings = true }
      )

      Divider()

      ChatMessageList(messages: viewModel.messages)

      Divider()

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
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .fullScreenCover(isPresented: $showGlassesStream) {
      ZStack(alignment: .topLeading) {
        StreamSessionView(wearables: wearables, wearablesVM: wearablesVM)

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
