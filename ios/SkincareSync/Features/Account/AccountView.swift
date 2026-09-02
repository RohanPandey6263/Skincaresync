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
                    ScrollView { SkeletonRows(count: 3).padding(.horizontal, Spacing.m) }
                case .signedOut:
                    SignInView(path: $path)
                case .signedIn(let user):
                    SignedInView(user: user, path: $path)
                }
            }
            .background(Palette.page)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
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

/// Signed-in root: profile block, verification, security link, and a large log-out.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let notice = session.notice {
                    InlineNotice(kind: .success, text: notice, actionTitle: "Dismiss") { session.notice = nil }
                        .padding(Spacing.m)
                }

                VStack(alignment: .leading, spacing: Spacing.m) {
                    SectionLabel("01", "Profile")
                    Text(user.displayName ?? user.email)
                        .headlineStyle(Typography.title)
                    if user.displayName != nil {
                        Text(user.email).font(Typography.body).foregroundStyle(Palette.ink)
                    }
                    Text("Member since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.secondary)
                }
                .padding(Spacing.m)
                .padding(.top, Spacing.m)
                .accessibilityElement(children: .combine)

                Rule(width: Metrics.borderHeavy)

                HStack(alignment: .top, spacing: Spacing.m) {
                    IconBox(symbol: user.emailVerified ? "checkmark.square.fill" : "envelope.badge",
                            tone: user.emailVerified ? nil : Severity.high.presentation,
                            filled: user.emailVerified)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(user.emailVerified ? "Email confirmed" : "Email not confirmed")
                            .headlineStyle(Typography.pairName)
                        if !user.emailVerified {
                            Text("Confirm your address to enable password reset by email.")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(Spacing.m)
                .accessibilityElement(children: .combine)

                if !user.emailVerified {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Button {
                            Task { await resendVerification() }
                        } label: {
                            HStack {
                                Text("Resend confirmation email")
                                if resending { Spacer(); ProgressView().tint(Palette.ink) }
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(resending)
                        Button("Enter a confirmation code") { path.append(.verifyEmail) }
                            .buttonStyle(.secondary)
                        if let resendMessage {
                            Text(resendMessage).font(Typography.meta).foregroundStyle(Palette.secondary)
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.m)
                }

                Rule(width: Metrics.borderHeavy)

                NavigationLink(value: AccountRoute.security) {
                    HStack(spacing: Spacing.m) {
                        IconBox(symbol: "lock.fill")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Security").headlineStyle(Typography.pairName)
                            Text("Password, signed-in devices, connected accounts, activity, and account removal.")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.body.weight(.bold)).foregroundStyle(Palette.ink)
                    }
                    .padding(Spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rule()

                HStack(spacing: Spacing.m) {
                    Image(systemName: "iphone").font(.body.weight(.bold)).foregroundStyle(Palette.secondary)
                    Text("Routines stay on this device. Your account does not sync them; drafts are saved locally and survive relaunching the app.")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.m)
                .swissGrid()
                .accessibilityElement(children: .combine)

                Rule(width: Metrics.borderHeavy)

                Button {
                    confirmSignOut = true
                } label: {
                    HStack(spacing: Spacing.s) {
                        if session.isSigningOut { ProgressView().tint(Palette.onAccent) }
                        Text("Log out")
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.body.weight(.bold))
                    }
                }
                .buttonStyle(.destructive)
                .disabled(session.isSigningOut)
                .padding(Spacing.m)
                .padding(.bottom, Spacing.xl)
                .accessibilityHint("Signs out of SkincareSync on this device")
            }
        }
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
