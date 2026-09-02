import SwiftUI

@main
struct SkincareSyncApp: App {
    @State private var container = AppContainer.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch container {
            case .ready(let dependencies):
                RootView()
                    .environment(\.api, dependencies.api)
                    .environment(dependencies.session)
                    .environment(dependencies.routine)
                    .environment(dependencies.navigation)
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background || phase == .inactive {
                            dependencies.routine.saveNow()
                        }
                    }
            case .misconfigured(let failure):
                ConfigurationErrorView(failure: failure)
            }
        }
    }
}

/// Everything built once at launch.
@MainActor
struct AppDependencies {
    let api: any APIClient
    let session: SessionStore
    let routine: RoutineStore
    let navigation: AppNavigation
}

@MainActor
enum AppContainer {
    case ready(AppDependencies)
    case misconfigured(APIConfiguration.Failure)

    /// Debug-only launch argument that swaps in the fixture-backed client.
    /// It is never used implicitly: it must be passed explicitly and the UI
    /// shows a persistent "Fixture data" badge while it is on.
    static let mockLaunchArgument = "-SkincareSyncMockAPI"

    static func make() -> AppContainer {
        let navigation = AppNavigation()
        let api: any APIClient

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        DebugLaunchOptions.apply(arguments, to: navigation)
        if arguments.contains(mockLaunchArgument) {
            navigation.usesFixtureData = true
            api = arguments.contains(DebugLaunchOptions.signedOutArgument) ? MockAPIClient() : MockAPIClient.signedIn()
            let dependencies = build(api: api, navigation: navigation, draftStore: InMemoryDraftStore(initial: Fixtures.sampleDraft))
            if arguments.contains(DebugLaunchOptions.openReportArgument) {
                dependencies.routine.installFixtureReport(Fixtures.sampleReport)
            }
            return .ready(dependencies)
        }
        #endif

        switch APIConfiguration.fromBundle() {
        case .failure(let failure):
            return .misconfigured(failure)
        case .success(let configuration):
            api = LiveAPIClient(configuration: configuration)
        }

        let draftStore: any DraftStore
        do {
            draftStore = try FileDraftStore.standard()
        } catch {
            // Application Support being unavailable is unexpected; keep the
            // app usable for this run rather than crash.
            draftStore = InMemoryDraftStore()
        }
        return .ready(build(api: api, navigation: navigation, draftStore: draftStore))
    }

    private static func build(api: any APIClient, navigation: AppNavigation, draftStore: any DraftStore) -> AppDependencies {
        AppDependencies(
            api: api,
            session: SessionStore(api: api),
            routine: RoutineStore(api: api, draftStore: draftStore),
            navigation: navigation
        )
    }
}

/// Shown instead of the app when a release build has no HTTPS endpoint.
struct ConfigurationErrorView: View {
    let failure: APIConfiguration.Failure

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionLabel("00", "SkincareSync")
            Text("Backend not configured")
                .headlineStyle(Typography.display)
            Text(failure.message)
                .font(Typography.body)
                .foregroundStyle(Palette.secondary)
            Rule()
            Text("See ios/README.md for how API_BASE_URL is set per build configuration.")
                .font(Typography.meta)
                .foregroundStyle(Palette.faint)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }
}

#if DEBUG
/// Launch arguments used only for manual verification and screenshots.
/// `-SkincareSyncMockAPI` swaps in fixtures; `-SkincareSyncStartTab routine`
/// picks the first tab; `-SkincareSyncOpenReport` pushes the fixture report;
/// `-SkincareSyncMockSignedOut` makes the mock session start signed out;
/// `-SkincareSyncOpenIngredient 6` pushes an ingredient detail;
/// `-SkincareSyncOpenEditor` opens the editor for the first morning product.
enum DebugLaunchOptions {
    static let startTabArgument = "-SkincareSyncStartTab"
    static let openReportArgument = "-SkincareSyncOpenReport"
    static let signedOutArgument = "-SkincareSyncMockSignedOut"
    static let openIngredientArgument = "-SkincareSyncOpenIngredient"
    static let openEditorArgument = "-SkincareSyncOpenEditor"

    @MainActor
    static func apply(_ arguments: [String], to navigation: AppNavigation) {
        if let index = arguments.firstIndex(of: startTabArgument), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "home": navigation.selectedTab = .home
            case "routine": navigation.selectedTab = .routine
            case "ingredients": navigation.selectedTab = .ingredients
            case "account": navigation.selectedTab = .account
            default: break
            }
        }
        if arguments.contains(openReportArgument) {
            navigation.selectedTab = .routine
            navigation.openReportOnLaunch = true
        }
        if let index = arguments.firstIndex(of: openIngredientArgument), index + 1 < arguments.count,
           let id = Int(arguments[index + 1]) {
            navigation.selectedTab = .ingredients
            navigation.openIngredientOnLaunch = id
        }
        if arguments.contains(openEditorArgument) {
            navigation.selectedTab = .routine
            navigation.openEditorOnLaunch = true
        }
    }
}
#endif
