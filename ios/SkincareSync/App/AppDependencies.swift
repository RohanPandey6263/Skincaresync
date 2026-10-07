import SwiftUI

/// Generic remote-state container used by every network-backed screen.
enum LoadState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: APIError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum AppTab: Hashable, CaseIterable {
    case routine, ingredients, account
}

/// Cross-tab navigation intents (Home's primary action opens Routine).
@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .routine
    /// Debug-only indicator that the app is running against fixture data.
    var usesFixtureData = false
    /// Debug-only: Routine pushes the current report as soon as it appears.
    var openReportOnLaunch = false
    /// Debug-only: Ingredients pushes this ingredient id on first appearance.
    var openIngredientOnLaunch: Int?
    /// Debug-only: Routine opens the editor for the first morning product.
    var openEditorOnLaunch = false
}

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: any APIClient = MockAPIClient()
}

extension EnvironmentValues {
    /// The API client for the current run. Defaults to a mock only so previews
    /// work without wiring; the app always injects the live client explicitly.
    var api: any APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
