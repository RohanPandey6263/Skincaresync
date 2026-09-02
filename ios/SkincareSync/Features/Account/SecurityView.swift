import SwiftUI

@MainActor
@Observable
final class SecurityViewModel {
    private let api: any APIClient
    private(set) var sessions: LoadState<[SessionInfo]> = .idle
    private(set) var events: LoadState<[AuthEvent]> = .idle
    private(set) var identities: LoadState<[LinkedIdentity]> = .idle
    private(set) var actionError: APIError?
    private(set) var actionMessage: String?
    private var tasks: [Task<Void, Never>] = []

    init(api: any APIClient) {
        self.api = api
    }

    func loadAll() {
        loadSessions()
        loadEvents()
        loadIdentities()
    }

    func loadSessions() {
        sessions = .loading
        tasks.append(Task { [api] in
            do { sessions = .loaded(try await api.sessions()) }
            catch let error as APIError { if !error.isCancellation { sessions = .failed(error) } }
            catch { sessions = .failed(.invalidResponse) }
        })
    }

    func loadEvents() {
        events = .loading
        tasks.append(Task { [api] in
            do { events = .loaded(try await api.events()) }
            catch let error as APIError { if !error.isCancellation { events = .failed(error) } }
            catch { events = .failed(.invalidResponse) }
        })
    }

    func loadIdentities() {
        identities = .loading
        tasks.append(Task { [api] in
            do { identities = .loaded(try await api.identities()) }
            catch let error as APIError { if !error.isCancellation { identities = .failed(error) } }
            catch { identities = .failed(.invalidResponse) }
        })
    }

    func revoke(session: SessionInfo) async -> APIError? {
        do {
            actionMessage = try await api.revokeSession(id: session.sessionId).message
            if case .loaded(let list) = sessions {
                sessions = .loaded(list.filter { $0.sessionId != session.sessionId })
            }
            return nil
        } catch let error as APIError {
            actionError = error
            return error
        } catch {
            actionError = .invalidResponse
            return .invalidResponse
        }
    }

    func unlink(identity: LinkedIdentity) async -> APIError? {
        do {
            actionMessage = try await api.unlinkIdentity(provider: identity.provider).message
            if case .loaded(let list) = identities {
                identities = .loaded(list.filter { $0.provider != identity.provider })
            }
            return nil
        } catch let error as APIError {
            actionError = error
            return error
        } catch {
            actionError = .invalidResponse
            return .invalidResponse
        }
    }

    func deactivate() async -> Result<MessageResponse, APIError> {
        do { return .success(try await api.deactivate()) }
        catch let error as APIError { return .failure(error) }
        catch { return .failure(.invalidResponse) }
    }

    func clearMessages() {
        actionError = nil
        actionMessage = nil
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

struct SecurityView: View {
    @Environment(\.api) private var api
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var model: SecurityViewModel?
    @State private var confirmSignOutAll = false
    @State private var confirmDeactivate = false
    @State private var busy = false

    var body: some View {
        List {
            if let model {
                content(model)
            } else {
                SkeletonRows(count: 4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.page)
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = SecurityViewModel(api: api) }
            model?.loadAll()
        }
        .refreshable { model?.loadAll() }
        .onDisappear { model?.cancel() }
        .confirmationDialog("Log out of every device, including this one?", isPresented: $confirmSignOutAll, titleVisibility: .visible) {
            Button("Log out all devices", role: .destructive) {
                Task {
                    busy = true
                    if let error = await session.signOutEverywhere() { session.notice = error.message }
                    busy = false
                }
            }
        }
        .confirmationDialog("Deactivate your account? You will be signed out and will need to contact support to restore it.",
                            isPresented: $confirmDeactivate, titleVisibility: .visible) {
            Button("Deactivate account", role: .destructive) {
                Task { await deactivate() }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: SecurityViewModel) -> some View {
        if let message = model.actionMessage {
            Section {
                InlineNotice(kind: .success, text: message, actionTitle: "Dismiss") { model.clearMessages() }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        } else if let error = model.actionError {
            Section {
                InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Dismiss") { model.clearMessages() }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }

        Section("Password") {
            if session.user?.hasPassword == true {
                NavigationLink(value: AccountRoute.changePassword) {
                    Label("Change password", systemImage: "key")
                        .foregroundStyle(Palette.forest)
                }
            } else {
                Label("This account signs in through a connected provider and has no password.", systemImage: "key.slash")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.muted)
            }
        }

        Section {
            remoteList(model.sessions, empty: "No other devices are signed in.", retry: model.loadSessions) { info in
                SessionRow(info: info)
                    .swipeActions(edge: .trailing) {
                        if !info.current {
                            Button(role: .destructive) {
                                Task { _ = await model.revoke(session: info) }
                            } label: {
                                Label("Log out device", systemImage: "xmark.circle")
                            }
                        }
                    }
            }
            Button {
                confirmSignOutAll = true
            } label: {
                Label(busy ? "Logging out…" : "Log out all devices", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(Palette.terracottaText)
            }
            .disabled(busy)
        } header: {
            Text("Signed-in devices")
        } footer: {
            Text("Swipe a device to log it out.")
        }

        Section {
            remoteList(model.identities, empty: "No connected accounts. Connecting Google or Apple is done from the web app.", retry: model.loadIdentities) { identity in
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.providerLabel).foregroundStyle(Palette.forest)
                    if let email = identity.email { Text(email).font(Typography.meta).foregroundStyle(Palette.muted) }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { _ = await model.unlink(identity: identity) }
                    } label: {
                        Label("Disconnect", systemImage: "link.badge.plus")
                    }
                }
            }
        } header: {
            Text("Connected accounts")
        } footer: {
            Text("Swipe to disconnect. A provider cannot be disconnected if it is the only way to sign in.")
        }

        Section("Recent activity") {
            remoteList(model.events, empty: "No activity recorded yet.", retry: model.loadEvents) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).foregroundStyle(Palette.forest)
                    Text(activityDetail(event)).font(Typography.meta).foregroundStyle(Palette.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }

        Section {
            Button { confirmDeactivate = true } label: {
                Label("Deactivate account", systemImage: "pause.circle")
                    .foregroundStyle(Palette.terracottaText)
            }
            NavigationLink(value: AccountRoute.deleteAccount) {
                Label("Delete account", systemImage: "trash")
                    .foregroundStyle(Palette.terracottaText)
            }
        } header: {
            Text("Danger zone")
        } footer: {
            Text("Deactivation can be reversed by support. Deletion removes your personal details permanently.")
        }
    }

    @ViewBuilder
    private func remoteList<T: Identifiable, Row: View>(
        _ state: LoadState<[T]>, empty: String, retry: @escaping () -> Void, @ViewBuilder row: @escaping (T) -> Row
    ) -> some View {
        switch state {
        case .idle, .loading:
            SkeletonRows(count: 2)
        case .failed(let error):
            InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Retry", action: retry)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                .task { if error.isUnauthorized { session.markSignedOut() } }
        case .loaded(let items):
            if items.isEmpty {
                Text(empty).font(Typography.meta).foregroundStyle(Palette.muted)
            } else {
                ForEach(items) { row($0) }
            }
        }
    }

    private func activityDetail(_ event: AuthEvent) -> String {
        var parts = [event.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let ip = event.ipAddress { parts.append(ip) }
        if !event.detail.isEmpty { parts.append(JSONValue.object(event.detail).displayText) }
        return parts.joined(separator: " · ")
    }

    private func deactivate() async {
        guard let model else { return }
        busy = true
        switch await model.deactivate() {
        case .success(let response):
            session.accountRemoved(message: response.message)
        case .failure(let error):
            session.notice = nil
            if error.isUnauthorized { session.markSignedOut() }
        }
        busy = false
    }
}

private struct SessionRow: View {
    let info: SessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Text(deviceName).foregroundStyle(Palette.forest)
                if info.current { TagPill(text: "This device", tone: ReportSectionKind.synergies.presentation) }
            }
            Text("Last active \(info.lastSeenAt.formatted(.relative(presentation: .named)))\(info.ipAddress.map { " · \($0)" } ?? "")")
                .font(Typography.meta)
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var deviceName: String {
        guard let agent = info.userAgent, !agent.isEmpty else { return "Unknown device" }
        if agent.hasPrefix("SkincareSync-iOS") { return "SkincareSync for iPhone" }
        if agent.contains("iPhone") { return "iPhone browser" }
        if agent.contains("Macintosh") { return "Mac browser" }
        if agent.contains("Windows") { return "Windows browser" }
        if agent.contains("Android") { return "Android browser" }
        return String(agent.prefix(40))
    }
}

struct DeleteAccountView: View {
    @Environment(\.api) private var api
    @Environment(SessionStore.self) private var session
    @Binding var path: [AccountRoute]

    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: APIError?
    @State private var submitting = false

    private var canSubmit: Bool { !password.isEmpty && confirmation.uppercased() == "DELETE" && !submitting }

    var body: some View {
        Form {
            Section {
                Text("Deleting removes your account and personal details. Routines saved on this device are not affected. This cannot be undone.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.forest)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.xs, bottom: Spacing.s, trailing: Spacing.xs))
            }
            Section {
                SecureField("Current password", text: $password)
                    .textContentType(.password)
                TextField("Type DELETE to confirm", text: $confirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section {
                FormErrorView(error: error)
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if submitting { ProgressView().tint(.white) }
                        Text("Delete my account")
                    }
                }
                .buttonStyle(.destructive)
                .disabled(!canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.page)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            let response = try await api.deleteAccount(currentPassword: password)
            session.accountRemoved(message: response.message)
        } catch let failure as APIError {
            if failure.isUnauthorized { session.markSignedOut() }
            error = failure
        } catch {
            self.error = .invalidResponse
        }
        submitting = false
    }
}

#Preview {
    NavigationStack {
        SecurityView(path: .constant([]))
            .environment(\.api, MockAPIClient.signedIn())
            .environment({ () -> SessionStore in
                let store = SessionStore(api: MockAPIClient.signedIn())
                Task { await store.bootstrap() }
                return store
            }())
    }
}
