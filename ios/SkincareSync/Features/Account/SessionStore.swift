import Foundation
import Observation

/// Who is signed in. The backend decides; this only mirrors its answer.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(AuthUser)
    }

    private let api: any APIClient

    private(set) var state: State = .unknown
    private(set) var isBootstrapping = false
    /// Set when the session check itself failed (offline, backend down).
    private(set) var bootstrapError: APIError?
    private(set) var isSigningOut = false
    /// One-shot message shown at the top of the Account tab.
    var notice: String?

    init(api: any APIClient) {
        self.api = api
    }

    var user: AuthUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    /// `GET /api/auth/session` on launch. `null` means signed out.
    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            if let session = try await api.session() {
                state = .signedIn(session.user)
            } else {
                state = .signedOut
            }
            bootstrapError = nil
        } catch let error as APIError {
            if error.isCancellation { return }
            bootstrapError = error
            if case .unknown = state { state = .signedOut }
        } catch {
            bootstrapError = .invalidResponse
            if case .unknown = state { state = .signedOut }
        }
    }

    func signIn(email: String, password: String) async -> APIError? {
        do {
            let session = try await api.login(email: email, password: password)
            state = .signedIn(session.user)
            bootstrapError = nil
            notice = nil
            Haptics.success()
            return nil
        } catch let error as APIError {
            return error.isCancellation ? nil : error
        } catch {
            return .invalidResponse
        }
    }

    func register(email: String, password: String, displayName: String?) async -> Result<MessageResponse, APIError> {
        do {
            return .success(try await api.register(email: email, password: password, displayName: displayName))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    /// Always ends signed out locally, even if the backend cannot be reached.
    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            let response = try await api.logout()
            notice = response.message
        } catch let error as APIError {
            api.clearLocalSession()
            notice = error.isConnectivity
                ? "Signed out on this device. The server could not be reached, so the session will expire on its own."
                : "You are signed out."
        } catch {
            api.clearLocalSession()
            notice = "You are signed out."
        }
        state = .signedOut
    }

    func signOutEverywhere() async -> APIError? {
        do {
            let response = try await api.logoutAll()
            notice = response.message
            state = .signedOut
            return nil
        } catch let error as APIError {
            if error.isUnauthorized { markSignedOut() }
            return error
        } catch {
            return .invalidResponse
        }
    }

    func refreshUser() async {
        do {
            let user = try await api.me()
            state = .signedIn(user)
        } catch let error as APIError {
            if error.isUnauthorized { markSignedOut() }
        } catch {
            // Keep the existing state on transient failures.
        }
    }

    /// Called when a protected call returns 401: the cookie is gone or expired.
    func markSignedOut() {
        api.clearLocalSession()
        state = .signedOut
        notice = "Your session ended. Sign in again to continue."
    }

    /// After deactivation or deletion the server has already cleared cookies.
    func accountRemoved(message: String) {
        api.clearLocalSession()
        state = .signedOut
        notice = message
    }
}
