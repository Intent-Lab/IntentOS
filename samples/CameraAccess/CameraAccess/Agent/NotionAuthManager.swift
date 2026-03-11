import Foundation
import AuthenticationServices

@MainActor
class NotionAuthManager: NSObject, ObservableObject {
  static let shared = NotionAuthManager()

  @Published var isSignedIn: Bool = false
  @Published var workspaceName: String?

  private static let keychainService = "com.matcha.notion"
  private static let keychainAccountToken = "access_token"
  private static let keychainAccountWorkspace = "workspace_name"

  override private init() {
    super.init()
    restoreToken()
  }

  func signIn(from viewController: UIViewController) {
    let settings = SettingsManager.shared
    let baseURL = settings.agentBaseURL

    // Generate CSRF nonce
    let state = UUID().uuidString

    guard let authURL = URL(string: "\(baseURL)/api/notion/auth?state=\(state)") else {
      NSLog("[NotionAuth] Invalid auth URL")
      return
    }

    let session = ASWebAuthenticationSession(
      url: authURL,
      callbackURLScheme: "matcha"
    ) { [weak self] callbackURL, error in
      Task { @MainActor in
        guard let self else { return }

        if let error {
          NSLog("[NotionAuth] Auth failed: %@", error.localizedDescription)
          return
        }

        guard let callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
          NSLog("[NotionAuth] Missing token in callback")
          return
        }

        // Verify state matches
        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        if returnedState != state {
          NSLog("[NotionAuth] State mismatch")
          return
        }

        let workspace = components.queryItems?.first(where: { $0.name == "workspace" })?.value ?? "Notion"

        // Save to Keychain
        Self.saveToKeychain(key: Self.keychainAccountToken, value: token)
        Self.saveToKeychain(key: Self.keychainAccountWorkspace, value: workspace)

        self.isSignedIn = true
        self.workspaceName = workspace
        NSLog("[NotionAuth] Signed in: %@", workspace)
      }
    }

    session.presentationContextProvider = viewController as? ASWebAuthenticationPresentationContextProviding
      ?? DefaultPresentationContext(anchor: viewController.view.window)
    session.prefersEphemeralWebBrowserSession = false
    session.start()
  }

  func signOut() {
    Self.deleteFromKeychain(key: Self.keychainAccountToken)
    Self.deleteFromKeychain(key: Self.keychainAccountWorkspace)
    isSignedIn = false
    workspaceName = nil
    NSLog("[NotionAuth] Signed out")
  }

  /// Get the stored access token (synchronous -- Notion tokens don't expire)
  func accessToken() -> String? {
    return Self.loadFromKeychain(key: Self.keychainAccountToken)
  }

  private func restoreToken() {
    if let token = Self.loadFromKeychain(key: Self.keychainAccountToken), !token.isEmpty {
      isSignedIn = true
      workspaceName = Self.loadFromKeychain(key: Self.keychainAccountWorkspace) ?? "Notion"
      NSLog("[NotionAuth] Restored session: %@", workspaceName ?? "unknown")
    }
  }

  // MARK: - Keychain Helpers

  private static func saveToKeychain(key: String, value: String) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
    var addQuery = query
    addQuery[kSecValueData as String] = data
    SecItemAdd(addQuery as CFDictionary, nil)
  }

  private static func loadFromKeychain(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func deleteFromKeychain(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

/// Default presentation context for ASWebAuthenticationSession
private class DefaultPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
  let anchor: ASPresentationAnchor?

  init(anchor: ASPresentationAnchor?) {
    self.anchor = anchor
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return anchor ?? ASPresentationAnchor()
  }
}
