import Foundation
import Observation

/// Catalog browsing: debounced search and suggestions, filters, pagination.
/// Results already on screen survive a failed refresh or load-more.
@MainActor
@Observable
final class IngredientsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(APIError)
    }

    enum LoadMoreState: Equatable {
        case idle
        case loading
        case failed(APIError)
    }

    static let pageSize = 25
    static let searchDebounce: Duration = .milliseconds(350)
    static let suggestDebounce: Duration = .milliseconds(200)

    private let api: any APIClient

    var query = ""
    private(set) var filters = IngredientQuery(limit: pageSize)
    private(set) var items: [IngredientSummary] = []
    private(set) var total: Int?
    private(set) var hasMore = false
    private(set) var phase: Phase = .idle
    private(set) var loadMore: LoadMoreState = .idle
    /// Error from a refresh that failed while older results are still shown.
    private(set) var inlineError: APIError?
    private(set) var suggestions: [IngredientSuggestion] = []
    private(set) var facets: LoadState<CatalogFacets> = .idle

    private var searchTask: Task<Void, Never>?
    private var suggestTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var facetsTask: Task<Void, Never>?
    private var generation = 0

    init(api: any APIClient) {
        self.api = api
    }

    var activeFilterCount: Int {
        var count = filters.functions.count
        if filters.source != nil { count += 1 }
        if filters.letter != nil { count += 1 }
        if filters.onlyWithInteractions { count += 1 }
        if filters.onlyRestricted { count += 1 }
        return count
    }

    var selectedLetter: String? { filters.letter }

    // MARK: Lifecycle

    func start() {
        if phase == .idle { search(immediately: true) }
        loadFacets()
    }

    /// Called on every keystroke.
    func queryChanged() {
        scheduleSuggestions()
        search(immediately: false)
    }

    /// Called when the user submits the search field or taps a suggestion.
    func submit() {
        suggestions = []
        suggestTask?.cancel()
        search(immediately: true)
    }

    func choose(suggestion: IngredientSuggestion) {
        query = suggestion.inciName
        submit()
    }

    // MARK: Filters

    func setLetter(_ letter: String?) {
        filters.letter = (filters.letter == letter) ? nil : letter
        search(immediately: true)
    }

    func apply(filters updated: IngredientQuery) {
        var next = updated
        next.text = filters.text
        next.limit = Self.pageSize
        next.offset = 0
        if next != filters {
            filters = next
            search(immediately: true)
        }
    }

    func clearFilters() {
        filters = IngredientQuery(limit: Self.pageSize)
        search(immediately: true)
    }

    func clearAll() {
        query = ""
        clearFilters()
    }

    // MARK: Search

    private func search(immediately: Bool) {
        searchTask?.cancel()
        loadMoreTask?.cancel()
        loadMore = .idle
        generation += 1
        let current = generation
        var request = filters
        request.text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        request.offset = 0
        // Keep old rows visible while a new page loads; only show the skeleton
        // when there is nothing to show.
        if items.isEmpty { phase = .loading }
        searchTask = Task { [api] in
            if !immediately {
                try? await Task.sleep(for: Self.searchDebounce)
                guard !Task.isCancelled else { return }
            }
            do {
                let page = try await api.searchIngredients(request)
                guard !Task.isCancelled, current == generation else { return }
                items = page.items
                total = page.total
                hasMore = page.hasMore
                inlineError = nil
                phase = page.items.isEmpty ? .empty : .loaded
            } catch let error as APIError {
                guard !error.isCancellation, current == generation else { return }
                if items.isEmpty {
                    phase = .failed(error)
                } else {
                    inlineError = error
                }
            } catch {
                guard current == generation else { return }
                if items.isEmpty { phase = .failed(.invalidResponse) } else { inlineError = .invalidResponse }
            }
        }
    }

    func retry() {
        search(immediately: true)
    }

    /// Pull-to-refresh: awaits the reload so the control dismisses at the right time.
    func refresh() async {
        search(immediately: true)
        await searchTask?.value
    }

    func loadMoreIfNeeded(current item: IngredientSummary) {
        guard hasMore, loadMore != .loading, item.id == items.last?.id else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard hasMore, loadMore != .loading else { return }
        loadMore = .loading
        var request = filters
        request.text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        request.offset = items.count
        let current = generation
        loadMoreTask = Task { [api] in
            do {
                let page = try await api.searchIngredients(request)
                guard !Task.isCancelled, current == generation else { return }
                let known = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !known.contains($0.id) })
                total = page.total
                hasMore = page.hasMore
                loadMore = .idle
            } catch let error as APIError {
                guard !error.isCancellation, current == generation else { return }
                loadMore = .failed(error)
            } catch {
                guard current == generation else { return }
                loadMore = .failed(.invalidResponse)
            }
        }
    }

    // MARK: Suggestions

    private func scheduleSuggestions() {
        suggestTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            suggestions = []
            return
        }
        suggestTask = Task { [api] in
            try? await Task.sleep(for: Self.suggestDebounce)
            guard !Task.isCancelled else { return }
            do {
                let results = try await api.suggestIngredients(text)
                guard !Task.isCancelled else { return }
                suggestions = results
            } catch {
                // Suggestions are a convenience; a failure just shows none.
                guard !Task.isCancelled else { return }
                suggestions = []
            }
        }
    }

    // MARK: Facets

    func loadFacets() {
        guard facets.value == nil, !facets.isLoading else { return }
        facets = .loading
        facetsTask = Task { [api] in
            do {
                let result = try await api.ingredientFacets()
                guard !Task.isCancelled else { return }
                facets = .loaded(result)
            } catch let error as APIError {
                if error.isCancellation { return }
                facets = .failed(error)
            } catch {
                facets = .failed(.invalidResponse)
            }
        }
    }
}
