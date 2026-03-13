import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared
  @ObservedObject private var googleAuth = GoogleAuthManager.shared
  @ObservedObject private var notionAuth = NotionAuthManager.shared

  @State private var geminiAPIKey: String = ""
  @State private var geminiSystemPrompt: String = ""
  @State private var selectedBackend: AgentBackend = .e2b
  @State private var agentBaseURL: String = ""
  @State private var agentToken: String = ""
  @State private var openClawHost: String = ""
  @State private var openClawPort: String = ""
  @State private var openClawHookToken: String = ""
  @State private var openClawGatewayToken: String = ""
  @State private var webrtcSignalingURL: String = ""
  @State private var speakerOutputEnabled: Bool = false
  @State private var selectedFontTheme: FontTheme = .tiempos
  @State private var showResetConfirmation = false
  @State private var openClawStatus: OpenClawConnectionStatus = .idle

  enum OpenClawConnectionStatus: Equatable {
    case idle
    case checking
    case connected
    case unreachable(String)
  }

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Gemini API")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("API Key")
              .font(AppFont.caption)
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

        Section(header: Text("Agent Backend")) {
          Picker("Backend", selection: $selectedBackend) {
            ForEach(AgentBackend.allCases, id: \.self) { backend in
              Text(backend.rawValue).tag(backend)
            }
          }
          .pickerStyle(.segmented)
        }

        if selectedBackend == .e2b {
          Section(header: Text("E2B Agent"), footer: Text("Connect to the Matcha agent API (E2B + Claude Agent SDK) for task execution.")) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Base URL")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
              TextField("https://your-deployment.vercel.app", text: $agentBaseURL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
              Text("API Token")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
              TextField("Shared secret token", text: $agentToken)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
            }
          }
        } else {
          Section(header: Text("OpenClaw"), footer: Text("Connect to an OpenClaw gateway running on your Mac for agentic tool-calling.")) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Host")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
              TextField("http://your-mac.local", text: $openClawHost)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
              Text("Port")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
              TextField("18789", text: $openClawPort)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
              Text("Hook Token")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
              TextField("Hook secret token", text: $openClawHookToken)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
              Text("Gateway Token")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
              TextField("Gateway auth token", text: $openClawGatewayToken)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
            }

            HStack {
              Button(action: { testOpenClawConnection() }) {
                HStack(spacing: 6) {
                  if openClawStatus == .checking {
                    ProgressView()
                      .controlSize(.small)
                  }
                  Text(openClawStatus == .checking ? "Testing..." : "Test Connection")
                }
              }
              .disabled(openClawStatus == .checking || openClawHost.trimmingCharacters(in: .whitespaces).isEmpty)

              Spacer()

              switch openClawStatus {
              case .idle, .checking:
                EmptyView()
              case .connected:
                HStack(spacing: 4) {
                  Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                  Text("Connected")
                    .font(AppFont.caption)
                    .foregroundStyle(.green)
                }
              case .unreachable(let reason):
                HStack(spacing: 4) {
                  Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                  Text(reason)
                    .font(AppFont.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                }
              }
            }
          }
        }

        Section(header: Text("Google Account"), footer: Text("Connect your Google account to let the agent access your Calendar and Gmail (read-only).")) {
          if googleAuth.isSignedIn {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(googleAuth.userName ?? "Google Account")
                  .font(AppFont.body)
                Text(googleAuth.userEmail ?? "")
                  .font(AppFont.caption)
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

        Section(header: Text("Notion"), footer: Text("Connect your Notion workspace to let the agent search, read, and create pages.")) {
          if notionAuth.isSignedIn {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(notionAuth.workspaceName ?? "Notion Workspace")
                  .font(AppFont.body)
                Text("Connected")
                  .font(AppFont.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Disconnect") {
                notionAuth.signOut()
              }
              .foregroundColor(.red)
            }
          } else {
            Button("Connect Notion") {
              guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let rootVC = windowScene.windows.first?.rootViewController else { return }
              notionAuth.signIn(from: rootVC)
            }
          }
        }

        Section(header: Text("WebRTC")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Signaling URL")
              .font(AppFont.caption)
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

        Section(header: Text("Font"), footer: Text("Switch between system font (SF Pro) and Tiempos serif font.")) {
          Picker("Font Theme", selection: $selectedFontTheme) {
            ForEach(FontTheme.allCases, id: \.self) { theme in
              Text(theme.rawValue).tag(theme)
            }
          }
          .pickerStyle(.segmented)
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
    selectedBackend = settings.agentBackend
    agentBaseURL = settings.agentBaseURL
    agentToken = settings.agentToken
    openClawHost = settings.openClawHost
    openClawPort = String(settings.openClawPort)
    openClawHookToken = settings.openClawHookToken
    openClawGatewayToken = settings.openClawGatewayToken
    webrtcSignalingURL = settings.webrtcSignalingURL
    speakerOutputEnabled = settings.speakerOutputEnabled
    selectedFontTheme = FontTheme(rawValue: settings.fontTheme) ?? .tiempos
  }

  private func testOpenClawConnection() {
    let host = openClawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    let port = openClawPort.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = openClawGatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !host.isEmpty, !token.isEmpty else {
      openClawStatus = .unreachable("Missing host or token")
      return
    }

    let base = "\(host):\(port.isEmpty ? "18789" : port)"
    guard let url = URL(string: "\(base)/v1/chat/completions") else {
      openClawStatus = .unreachable("Invalid URL")
      return
    }

    openClawStatus = .checking

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 5
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    Task {
      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
          openClawStatus = .connected
        } else {
          openClawStatus = .unreachable("Unexpected response")
        }
      } catch {
        openClawStatus = .unreachable("Unreachable")
      }
    }
  }

  private func save() {
    settings.geminiAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.geminiSystemPrompt = geminiSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.agentBackend = selectedBackend
    settings.agentBaseURL = agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.agentToken = agentToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openClawHost = openClawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openClawPort = Int(openClawPort) ?? 18789
    settings.openClawHookToken = openClawHookToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openClawGatewayToken = openClawGatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.webrtcSignalingURL = webrtcSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.speakerOutputEnabled = speakerOutputEnabled
    settings.fontTheme = selectedFontTheme.rawValue
  }
}
