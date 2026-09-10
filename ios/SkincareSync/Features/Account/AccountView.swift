import SwiftUI

enum AccountRoute: Hashable {
    case register
    case forgotPassword
    case resetPassword
    case verifyEmail
    case security
    case changePassword
    case deleteAccount
}

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var path: [AccountRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch session.state {
                case .unknown:
                    List { SkeletonRows(count: 3) }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                case .signedOut:
                    SignInView(path: $path)
                case .signedIn(let user):
                    SignedInView(user: user, path: $path)
                }
            }
            .background(Palette.page)
            .navigationTitle("Account")
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .register: RegisterView(path: $path)
                case .forgotPassword: ForgotPasswordView(path: $path)
                case .resetPassword: ResetPasswordView(path: $path)
                case .verifyEmail: VerifyEmailView(path: $path)
                case .security: SecurityView(path: $path)
                case .changePassword: ChangePasswordView(path: $path)
                case .deleteAccount: DeleteAccountView(path: $path)
                }
            }
        }
        .onChange(of: session.isSignedIn) { _, _ in
            // Signing in or out invalidates whatever was pushed.
            path.removeAll()
        }
    }
}

/// Signed-in root: profile summary, verification, security link, and a large log-out.
private struct SignedInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.api) private var api
    let user: AuthUser
    @Binding var path: [AccountRoute]

    @State private var resendMessage: String?
    @State private var resending = false
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var session = session
        List {
            if let notice = session.notice {
                Section {
                    InlineNotice(kind: .success, text: notice, actionTitle: "Dismiss") { session.notice = nil }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(user.displayName ?? user.email)
                        .font(Typography.heading)
                        .foregroundStyle(Palette.forest)
                    if user.displayName != nil {
                        Text(user.email).font(Typography.meta).foregroundStyle(Palette.muted)
                    }
                    Text("Member since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.faint)
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)

                HStack(spacing: Spacing.s) {
                    Image(systemName: user.emailVerified ? "checkmark.seal.fill" : "envelope.badge")
                        .foregroundStyle(user.emailVerified ? Palette.sage : Palette.terracotta)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.emailVerified ? "Email confirmed" : "Email not confirmed")
                            .foregroundStyle(Palette.forest)
                        if !user.emailVerified {
                            Text("Confirm your address to enable password reset by email.")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                if !user.emailVerified {
                    Button {
                        Task { await resendVerification() }
                    } label: {
                        HStack {
                            Text("Resend confirmation email")
                            if resending { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(resending)
                    Button("Enter a confirmation code") { path.append(.verifyEmail) }
                    if let resendMessage {
                        Text(resendMessage).font(Typography.meta).foregroundStyle(Palette.muted)
                    }
                }
            } header: {
                Text("Profile")
            }

            Section {
                NavigationLink(value: AccountRoute.security) {
                    Label("Security", systemImage: "lock.shield")
                        .foregroundStyle(Palette.forest)
                }
                .frame(minHeight: Metrics.touchTarget - 12)
            } footer: {
                Text("Password, signed-in devices, connected accounts, activity, and account removal.")
            }

            Section {
                Label("Routines stay on this device", systemImage: "iphone")
                    .foregroundStyle(Palette.muted)
                    .font(Typography.meta)
            } footer: {
                Text("Your account does not sync routines. Drafts are saved locally and survive relaunching the app.")
            }

            Section {
                Button {
                    confirmSignOut = true
                } label: {
                    HStack(spacing: Spacing.s) {
                        if session.isSigningOut { ProgressView().tint(.white) }
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .buttonStyle(.destructive)
                .disabled(session.isSigningOut)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityHint("Signs out of SkincareSync on this device")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, Spacing.l, for: .scrollContent)
        .confirmationDialog("Log out of SkincareSync on this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                Task { await session.signOut() }
            }
        }
        .refreshable { await session.refreshUser() }
    }

    private func resendVerification() async {
        resending = true
        defer { resending = false }
        do {
            resendMessage = try await api.resendVerification(email: user.email).message
        } catch let error as APIError {
            resendMessage = error.message
        } catch {
            resendMessage = APIError.invalidResponse.message
        }
    }
}

#Preview("Signed in") {
    AccountView()
        .environment(\.api, MockAPIClient.signedIn())
        .environment({ () -> SessionStore in
            let store = SessionStore(api: MockAPIClient.signedIn())
            Task { await store.bootstrap() }
            return store
        }())
}

#Preview("Signed out") {
    AccountView()
        .environment(\.api, MockAPIClient())
        .environment({ () -> SessionStore in
            let store = SessionStore(api: MockAPIClient())
            Task { await store.bootstrap() }
            return store
        }())
}
