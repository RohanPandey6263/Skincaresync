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
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var email = ""
    @State private var password = ""
    @State private var error: APIError?
    @State private var submitting = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        AuthValidation.isPlausibleEmail(email) && !password.isEmpty && !submitting
    }

    var body: some View {
        @Bindable var session = session
        Form {
            if let notice = session.notice {
                Section {
                    InlineNotice(kind: .info, text: notice, actionTitle: "Dismiss") { session.notice = nil }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if let bootstrapError = session.bootstrapError {
                Section {
                    InlineNotice(kind: .error, text: "Couldn't check your session. \(bootstrapError.message)", actionTitle: "Retry") {
                        Task { await session.bootstrap() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Sign in")
                        .font(Typography.title)
                        .foregroundStyle(Palette.forest)
                        .accessibilityAddTraits(.isHeader)
                    Text("Accounts are optional for analysis. Sign in to manage your security settings.")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.muted)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.xs, bottom: Spacing.s, trailing: Spacing.xs))
            }
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await submit() } } }
            }
            Section {
                FormErrorView(error: error)
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if submitting { ProgressView().tint(Palette.onForest) }
                        Text(submitting ? "Signing in…" : "Sign in")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Button("Create an account") { path.append(.register) }
                Button("Forgot password?") { path.append(.forgotPassword) }
                Button("Have a confirmation or reset code?") { path.append(.verifyEmail) }
            }
            .foregroundStyle(Palette.forest)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.page)
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        error = nil
        focus = nil
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
        Form {
            if let success {
                Section {
                    InlineNotice(kind: .success, text: success.message)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    if let token = success.devToken {
                        Text("Development server: confirmation code \(token)")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.muted)
                            .textSelection(.enabled)
                    }
                    Button("Enter the confirmation code") { path.append(.verifyEmail) }
                    Button("Back to sign in") { path.removeAll() }
                }
            } else {
                Section {
                    TextField("Name (optional)", text: $displayName)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirm)
                        .textContentType(.newPassword)
                } footer: {
                    if passwordTooShort {
                        Text("Passwords need at least \(AuthValidation.minimumPasswordLength) characters.")
                    } else if mismatch {
                        Text("The two passwords do not match.")
                    } else {
                        Text("At least \(AuthValidation.minimumPasswordLength) characters. A confirmation link is emailed to you.")
                    }
                }
                Section {
                    FormErrorView(error: error)
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if submitting { ProgressView().tint(Palette.onForest) }
                            Text(submitting ? "Creating account…" : "Create account")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
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
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { Task { await submit() } }
            } footer: {
                Text("If an account exists for this address, reset instructions are emailed to it. The link opens the web app; you can also paste the code here.")
            }
            Section {
                FormErrorView(error: error)
                if let message {
                    InlineNotice(kind: .success, text: message.message)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    if let token = message.devToken {
                        Text("Development server: reset code \(token)")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.muted)
                            .textSelection(.enabled)
                    }
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if submitting { ProgressView().tint(Palette.onForest) }
                        Text("Send reset instructions")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!AuthValidation.isPlausibleEmail(email) || submitting)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Button("I have a reset code") { path.append(.resetPassword) }
                    .foregroundStyle(Palette.forest)
            }
        }
        .scrollContentBackground(.hidden)
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
        Form {
            Section {
                TextField("Reset code", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm)
                    .textContentType(.newPassword)
            } footer: {
                Text("Paste the code from the reset email. Every signed-in device is logged out when the password changes.")
            }
            Section {
                FormErrorView(error: error)
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if submitting { ProgressView().tint(Palette.onForest) }
                        Text("Set new password")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
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
        Form {
            Section {
                TextField("Confirmation code", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } footer: {
                Text("Paste the code from the confirmation email.")
            }
            Section {
                FormErrorView(error: error)
                if let message {
                    InlineNotice(kind: .success, text: message)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if submitting { ProgressView().tint(Palette.onForest) }
                        Text("Confirm email")
                    }
                }
                .buttonStyle(.primary)
                .disabled(token.trimmingCharacters(in: .whitespaces).count < 16 || submitting)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Button("I have a password reset code instead") { path.append(.resetPassword) }
                    .foregroundStyle(Palette.forest)
            }
        }
        .scrollContentBackground(.hidden)
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
        Form {
            Section {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm)
                    .textContentType(.newPassword)
            } footer: {
                Text("At least \(AuthValidation.minimumPasswordLength) characters. Other devices are signed out; this one stays signed in.")
            }
            Section {
                FormErrorView(error: error)
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if submitting { ProgressView().tint(Palette.onForest) }
                        Text("Update password")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
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
