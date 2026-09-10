import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let api: any APIClient
    private(set) var health: LoadState<HealthStatus> = .idle
    private var task: Task<Void, Never>?

    init(api: any APIClient) {
        self.api = api
    }

    func load() {
        guard !health.isLoading else { return }
        task?.cancel()
        health = .loading
        task = Task { [api] in
            do {
                let status = try await api.health()
                guard !Task.isCancelled else { return }
                health = .loaded(status)
            } catch let error as APIError {
                if error.isCancellation { return }
                health = .failed(error)
            } catch {
                health = .failed(.invalidResponse)
            }
        }
    }

    /// "22,288 ingredients · 3,549 products · 156 interaction rules"
    nonisolated static func statusLine(for status: HealthStatus) -> String? {
        guard status.ok, let ingredients = status.ingredientCount,
              let products = status.productCount, let interactions = status.interactionCount
        else { return nil }
        let format = { (value: Int) in value.formatted(.number.grouping(.automatic)) }
        return "\(format(ingredients)) ingredients · \(format(products)) products · \(format(interactions)) interaction rules"
    }
}
