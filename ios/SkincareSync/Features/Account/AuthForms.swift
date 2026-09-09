import SwiftUI

/// Shared pieces for the sign-in, registration and password screens.
enum AuthValidation {
    static let minimumPasswordLength = 12

    static func isPlausibleEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

/// Error line under a form, with per-field messages surfaced from a 422.
struct FormErrorView: View {
    let error: APIError?

    var body: some View {
        if let error {
            InlineNotice(kind: .error, text: text(for: error))
        }
    }

    private func text(for error: APIError) -> String {
        if case .validation(let fields) = error {
            return fields.sorted { $0.key < $1.key }
                .map { key, message in key == "request" ? message : "\(key.replacingOccurrences(of: "_", with: " ").capitalized): \(message)" }
                .joined(separator: " ")
        }
        return "\(error.title). \(error.message)"
    }
}

/// The title block every auth screen opens with: a small tracked label over a
/// big sentence-case line, set straight on the page.
struct AuthHeader: View {
    let number: String
    let eyebrow: String
    let title: String
    var description: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionLabel(number, eyebrow)
            Text(title)
                .headlineStyle(Typography.display)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGutter()
        .padding(.top, Spacing.l)
    }
}

/// Vertical rhythm for an auth form: one card holding the fields and actions.
struct AuthFormBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .softCard()
        .cardGutter()
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.xl)
    }
}

/// A quiet text link: bold, sentence case, underlined.
struct TextLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.control)
                .underline()
                .foregroundStyle(Palette.cocoa)
                .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var email = ""
    @State private var password = ""
    @State private var error: APIError?
    @State private var submitting = false

    private var canSubmit: Bool {
        AuthValidation.isPlausibleEmail(email) && !password.isEmpty && !submitting
    }

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(number: "01", eyebrow: "Sign in", title: "Welcome back.",
                           description: "Accounts are optional for analysis. Sign in to manage your security settings.")
                AuthFormBody {
                    if let notice = session.notice {
                        InlineNotice(kind: .info, text: notice, actionTitle: "Dismiss") { session.notice = nil }
                    }
                    if let bootstrapError = session.bootstrapError {
                        InlineNotice(kind: .error, text: "Couldn't check your session. \(bootstrapError.message)", actionTitle: "Retry") {
                            Task { await session.bootstrap() }
                        }
                    }
                    UnderlinedField(label: "Email", text: $email, placeholder: "you@example.com")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    UnderlinedField(label: "Password", text: $password, secure: true)
                        .textContentType(.password)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                    FormErrorView(error: error)
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if submitting { ProgressView().tint(Palette.onInk) }
                            Text(submitting ? "Signing in…" : "Sign in")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
                    Rule()
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextLinkButton(title: "Create an account") { path.append(.register) }
                        TextLinkButton(title: "Forgot password?") { path.append(.forgotPassword) }
                        TextLinkButton(title: "Have a confirmation or reset code?") { path.append(.verifyEmail) }
                    }
                }
            }
        }
        .background(Palette.page)
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        error = nil
        error = await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        submitting = false
        if error == nil { password = "" }
    }
}

struct RegisterView: View {
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: APIError?
    @State private var success: MessageResponse?
    @State private var submitting = false

    private var passwordTooShort: Bool { !password.isEmpty && password.count < AuthValidation.minimumPasswordLength }
    private var mismatch: Bool { !confirm.isEmpty && confirm != password }

    private var canSubmit: Bool {
        AuthValidation.isPlausibleEmail(email) && password.count >= AuthValidation.minimumPasswordLength
            && confirm == password && !submitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(number: "02", eyebrow: "Register", title: "Create your account.",
                           description: "Manage your security settings and pick up where you left off.")
                AuthFormBody {
                    if let success {
                        InlineNotice(kind: .success, text: success.message)
                        if let token = success.devToken {
                            Text("Development server: confirmation code \(token)")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.secondary)
                                .textSelection(.enabled)
                        }
                        Button("Enter the confirmation code") { path.append(.verifyEmail) }.buttonStyle(.primary)
                        Button("Back to sign in") { path.removeAll() }.buttonStyle(.secondary)
                    } else {
                        UnderlinedField(label: "Name", text: $displayName, placeholder: "Shown on your account page", meta: "Optional")
                            .textContentType(.name)
                        UnderlinedField(label: "Email", text: $email, placeholder: "you@example.com")
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        UnderlinedField(label: "Password", text: $password, secure: true,
                                        meta: "At least \(AuthValidation.minimumPasswordLength) characters")
                            .textContentType(.newPassword)
                        UnderlinedField(label: "Confirm password", text: $confirm, secure: true)
                            .textContentType(.newPassword)
                        if passwordTooShort {
                            Text("Passwords need at least \(AuthValidation.minimumPasswordLength) characters.")
                                .font(Typography.metaBold).foregroundStyle(Palette.accentText)
                        } else if mismatch {
                            Text("The two passwords do not match.")
                                .font(Typography.metaBold).foregroundStyle(Palette.accentText)
                        }
                        FormErrorView(error: error)
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: Spacing.s) {
                                if submitting { ProgressView().tint(Palette.onInk) }
                                Text(submitting ? "Creating account…" : "Create account")
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(!canSubmit)
                        Text("A confirmation link is emailed to you.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        submitting = true
        error = nil
        let name = displayName.trimmingCharacters(in: .whitespaces)
        switch await session.register(email: email.trimmingCharacters(in: .whitespaces), password: password,
                                      displayName: name.isEmpty ? nil : name) {
        case .success(let response):
            success = response
            password = ""
            confirm = ""
        case .failure(let failure):
            error = failure
        }
        submitting = false
    }
}

struct ForgotPasswordView: View {
    @Environment(\.api) private var api
    @Binding var path: [AccountRoute]

    @State private var email = ""
    @State private var message: MessageResponse?
    @State private var error: APIError?
    @State private var submitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(number: "03", eyebrow: "Reset", title: "Reset your password.",
                           description: "If an account exists for this address, reset instructions are emailed to it. The link opens the web app; you can also paste the code here.")
                AuthFormBody {
                    UnderlinedField(label: "Email", text: $email, placeholder: "you@example.com")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await submit() } }
                    FormErrorView(error: error)
                    if let message {
                        InlineNotice(kind: .success, text: message.message)
                        if let token = message.devToken {
                            Text("Development server: reset code \(token)")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if submitting { ProgressView().tint(Palette.onInk) }
                            Text("Send reset instructions")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!AuthValidation.isPlausibleEmail(email) || submitting)
                    Rule()
                    TextLinkButton(title: "I have a reset code") { path.append(.resetPassword) }
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Forgot password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            message = try await api.forgotPassword(email: email.trimmingCharacters(in: .whitespaces))
        } catch let failure as APIError {
            error = failure
        } catch {
            self.error = .invalidResponse
        }
        submitting = false
    }
}

struct ResetPasswordView: View {
    @Environment(\.api) private var api
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var token = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: APIError?
    @State private var submitting = false

    private var canSubmit: Bool {
        token.trimmingCharacters(in: .whitespaces).count >= 16
            && password.count >= AuthValidation.minimumPasswordLength && confirm == password && !submitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(number: "03", eyebrow: "Reset", title: "Choose a new password.",
                           description: "Paste the code from the reset email. Every signed-in device is logged out when the password changes.")
                AuthFormBody {
                    UnderlinedField(label: "Reset code", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    UnderlinedField(label: "New password", text: $password, secure: true,
                                    meta: "At least \(AuthValidation.minimumPasswordLength) characters")
                        .textContentType(.newPassword)
                    UnderlinedField(label: "Confirm new password", text: $confirm, secure: true)
                        .textContentType(.newPassword)
                    FormErrorView(error: error)
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if submitting { ProgressView().tint(Palette.onInk) }
                            Text("Set new password")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            let response = try await api.resetPassword(token: token.trimmingCharacters(in: .whitespaces), password: password)
            session.notice = response.message
            path.removeAll()
        } catch let failure as APIError {
            error = failure
        } catch {
            self.error = .invalidResponse
        }
        submitting = false
    }
}

struct VerifyEmailView: View {
    @Environment(\.api) private var api
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var token = ""
    @State private var message: String?
    @State private var error: APIError?
    @State private var submitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(number: "04", eyebrow: "Confirm", title: "Confirm your email.",
                           description: "Paste the code from the confirmation email.")
                AuthFormBody {
                    UnderlinedField(label: "Confirmation code", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    FormErrorView(error: error)
                    if let message {
                        InlineNotice(kind: .success, text: message)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if submitting { ProgressView().tint(Palette.onInk) }
                            Text("Confirm email")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(token.trimmingCharacters(in: .whitespaces).count < 16 || submitting)
                    Rule()
                    TextLinkButton(title: "I have a password reset code instead") { path.append(.resetPassword) }
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Confirm email")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            message = try await api.verifyEmail(token: token.trimmingCharacters(in: .whitespaces)).message
            if session.isSignedIn { await session.refreshUser() }
        } catch let failure as APIError {
            error = failure
        } catch {
            self.error = .invalidResponse
        }
        submitting = false
    }
}

struct ChangePasswordView: View {
    @Environment(\.api) private var api
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: APIError?
    @State private var submitting = false

    private var canSubmit: Bool {
        !current.isEmpty && password.count >= AuthValidation.minimumPasswordLength && confirm == password && !submitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(number: "01", eyebrow: "Password", title: "Change password.",
                           description: "At least \(AuthValidation.minimumPasswordLength) characters. Other devices are signed out; this one stays signed in.")
                AuthFormBody {
                    UnderlinedField(label: "Current password", text: $current, secure: true)
                        .textContentType(.password)
                    UnderlinedField(label: "New password", text: $password, secure: true)
                        .textContentType(.newPassword)
                    UnderlinedField(label: "Confirm new password", text: $confirm, secure: true)
                        .textContentType(.newPassword)
                    FormErrorView(error: error)
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if submitting { ProgressView().tint(Palette.onInk) }
                            Text("Update password")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
                }
            }
        }
        .background(Palette.page)
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            let response = try await api.changePassword(current: current, new: password)
            session.notice = response.message
            path.removeLast()
        } catch let failure as APIError {
            if failure.isUnauthorized { session.markSignedOut() }
            error = failure
        } catch {
            self.error = .invalidResponse
        }
        submitting = false
    }
}
