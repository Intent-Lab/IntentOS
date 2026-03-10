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
    ZStack {
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
          isInputFocused: $isInputFocused,
          onSend: { viewModel.sendMessage() },
          onVoiceTapped: {
            isInputFocused = false
            Task { await viewModel.startVoiceMode() }
          }
        )
      }

      if viewModel.isVoiceModeActive {
        VoiceModeOverlay(viewModel: viewModel)
          .animation(.easeInOut(duration: 0.3), value: viewModel.isVoiceModeActive)
      }
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
