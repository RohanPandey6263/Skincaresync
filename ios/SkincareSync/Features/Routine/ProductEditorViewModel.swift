import Foundation
import Observation

/// Search and barcode lookup for one product row. Superseded searches are
/// cancelled so a slow earlier response can never overwrite a newer one.
@MainActor
@Observable
final class ProductEditorViewModel {
    enum SearchState: Equatable {
        case idle
        case loading
        case results([ProductMatch])
        case empty
        case failed(APIError)
    }

    private let api: any APIClient
    private(set) var search: SearchState = .idle
    private(set) var lookup: LoadState<ProductMatch> = .idle
    /// Copy shown when the user tries to search with both fields blank.
    private(set) var searchHint: String?

    private var searchTask: Task<Void, Never>?
    private var lookupTask: Task<Void, Never>?
    private var generation = 0

    init(api: any APIClient) {
        self.api = api
    }

    func searchProducts(brand: String, name: String) {
        let brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty || !name.isEmpty else {
            searchHint = "Enter a brand or a product name to search."
            return
        }
        searchHint = nil
        searchTask?.cancel()
        generation += 1
        let current = generation
        search = .loading
        searchTask = Task { [api] in
            do {
                let matches = try await api.searchProducts(brand: brand, name: name)
                guard !Task.isCancelled, current == generation else { return }
                search = matches.isEmpty ? .empty : .results(matches)
            } catch let error as APIError {
                guard !error.isCancellation, current == generation else { return }
                search = .failed(error)
            } catch {
                guard current == generation else { return }
                search = .failed(.invalidResponse)
            }
        }
    }

    func lookupCode(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        lookupTask?.cancel()
        lookup = .loading
        lookupTask = Task { [api] in
            do {
                let match = try await api.lookupProduct(code: code)
                guard !Task.isCancelled else { return }
                lookup = .loaded(match)
            } catch let error as APIError {
                if error.isCancellation { return }
                lookup = .failed(error)
            } catch {
                lookup = .failed(.invalidResponse)
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        generation += 1
        search = .idle
    }

    func clearLookup() {
        lookupTask?.cancel()
        lookup = .idle
    }

    func cancelAll() {
        searchTask?.cancel()
        lookupTask?.cancel()
    }
}
