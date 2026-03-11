import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared
  @ObservedObject private var googleAuth = GoogleAuthManager.shared

  @State private var geminiAPIKey: String = ""
  @State private var geminiSystemPrompt: String = ""
  @State private var agentBaseURL: String = ""
  @State private var agentToken: String = ""
  @State private var webrtcSignalingURL: String = ""
  @State private var speakerOutputEnabled: Bool = false
  @State private var showResetConfirmation = false

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Gemini API")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("API Key")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Enter Gemini API key", text: $geminiAPIKey)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("System Prompt"), footer: Text("Customize the AI assistant's behavior and personality. Changes take effect on the next Gemini session.")) {
          TextEditor(text: $geminiSystemPrompt)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 200)
        }

        Section(header: Text("Agent"), footer: Text("Connect to the Matcha agent API (E2B + Claude Agent SDK) for task execution.")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Base URL")
              .font(.caption)
              .foregroundStyle(.secondary)
            TextField("https://your-deployment.vercel.app", text: $agentBaseURL)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .keyboardType(.URL)
              .font(.system(.body, design: .monospaced))
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("API Token")
              .font(.caption)
              .foregroundStyle(.secondary)
            TextField("Shared secret token", text: $agentToken)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("Google Account"), footer: Text("Connect your Google account to let the agent access your Calendar and Gmail (read-only).")) {
          if googleAuth.isSignedIn {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(googleAuth.userName ?? "Google Account")
                  .font(.body)
                Text(googleAuth.userEmail ?? "")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Sign Out") {
                googleAuth.signOut()
              }
              .foregroundColor(.red)
            }
          } else {
            Button("Sign in with Google") {
              guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let rootVC = windowScene.windows.first?.rootViewController else { return }
              googleAuth.signIn(presenting: rootVC)
            }
          }
        }

        Section(header: Text("WebRTC")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Signaling URL")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("wss://your-server.example.com", text: $webrtcSignalingURL)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .keyboardType(.URL)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("Audio"), footer: Text("Route audio output to the iPhone speaker instead of glasses. Useful for demos where others need to hear.")) {
          Toggle("Speaker Output", isOn: $speakerOutputEnabled)
        }

        Section {
          Button("Reset to Defaults") {
            showResetConfirmation = true
          }
          .foregroundColor(.red)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            save()
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .alert("Reset Settings", isPresented: $showResetConfirmation) {
        Button("Reset", role: .destructive) {
          settings.resetAll()
          loadCurrentValues()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will reset all settings to the values built into the app.")
      }
      .onAppear {
        loadCurrentValues()
      }
    }
  }

  private func loadCurrentValues() {
    geminiAPIKey = settings.geminiAPIKey
    geminiSystemPrompt = settings.geminiSystemPrompt
    agentBaseURL = settings.agentBaseURL
    agentToken = settings.agentToken
    webrtcSignalingURL = settings.webrtcSignalingURL
    speakerOutputEnabled = settings.speakerOutputEnabled
  }

  private func save() {
    settings.geminiAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.geminiSystemPrompt = geminiSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.agentBaseURL = agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.agentToken = agentToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.webrtcSignalingURL = webrtcSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.speakerOutputEnabled = speakerOutputEnabled
  }
}
