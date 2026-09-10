import Foundation

/// Local persistence for the routine draft. The backend has no saved-routine
/// endpoint, so this is the only copy.
protocol DraftStore: Sendable {
    func load() throws -> RoutineDraft?
    func save(_ draft: RoutineDraft) throws
    func clear() throws
}

/// Writes one JSON file in Application Support, atomically.
struct FileDraftStore: DraftStore {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The app's default location.
    static func standard() throws -> FileDraftStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appending(path: "SkincareSync", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileDraftStore(fileURL: directory.appending(path: "routine-draft.json"))
    }

    func load() throws -> RoutineDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(RoutineDraft.self, from: data)
    }

    func save(_ draft: RoutineDraft) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(draft)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// Keeps the draft in memory only. Used by previews and tests.
final class InMemoryDraftStore: DraftStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RoutineDraft?

    init(initial: RoutineDraft? = nil) {
        stored = initial
    }

    func load() throws -> RoutineDraft? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ draft: RoutineDraft) throws {
        lock.lock(); defer { lock.unlock() }
        stored = draft
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
