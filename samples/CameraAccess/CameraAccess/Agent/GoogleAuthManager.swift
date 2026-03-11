import Foundation
import GoogleSignIn

@MainActor
class GoogleAuthManager: ObservableObject {
  static let shared = GoogleAuthManager()

  @Published var isSignedIn: Bool = false
  @Published var userEmail: String?
  @Published var userName: String?

  private let scopes = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/gmail.readonly",
  ]

  private init() {
    restorePreviousSignIn()
  }

  func restorePreviousSignIn() {
    GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
      Task { @MainActor in
        guard let self else { return }
        if let user, error == nil {
          self.updateUser(user)
        } else {
          self.clearUser()
        }
      }
    }
  }

  func signIn(presenting viewController: UIViewController) {
    let config = GIDConfiguration(clientID: Secrets.googleClientID)
    GIDSignIn.sharedInstance.configuration = config
    GIDSignIn.sharedInstance.signIn(
      withPresenting: viewController,
      hint: nil,
      additionalScopes: scopes
    ) { [weak self] result, error in
      Task { @MainActor in
        guard let self else { return }
        if let user = result?.user, error == nil {
          self.updateUser(user)
          NSLog("[GoogleAuth] Signed in: %@", user.profile?.email ?? "unknown")
        } else {
          NSLog("[GoogleAuth] Sign-in failed: %@", error?.localizedDescription ?? "unknown")
          self.clearUser()
        }
      }
    }
  }

  func signOut() {
    GIDSignIn.sharedInstance.signOut()
    clearUser()
    NSLog("[GoogleAuth] Signed out")
  }

  /// Get a fresh access token, refreshing if needed.
  /// Call this before every agent request.
  func freshAccessToken() async -> String? {
    guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
    do {
      try await user.refreshTokensIfNeeded()
      return user.accessToken.tokenString
    } catch {
      NSLog("[GoogleAuth] Token refresh failed: %@", error.localizedDescription)
      return nil
    }
  }

  private func updateUser(_ user: GIDGoogleUser) {
    isSignedIn = true
    userEmail = user.profile?.email
    userName = user.profile?.name
  }

  private func clearUser() {
    isSignedIn = false
    userEmail = nil
    userName = nil
  }
}
