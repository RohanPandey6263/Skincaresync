import Foundation
@testable import SkincareSync

enum TestSupport {
    static let base = URL(string: "http://127.0.0.1:8000")!

    /// Polls until `condition` holds or the timeout passes. View models drive
    /// their own tasks, so tests observe their published state.
    @MainActor
    static func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    static func fixture(_ name: String) -> Data {
        Fixtures.data(named: name)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "SkincareSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
