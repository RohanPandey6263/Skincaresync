import AVFoundation
import Foundation
import Observation

/// Drives the scanner sheet: camera permission, scanning, lookup and retry.
@MainActor
@Observable
final class ScannerViewModel {
    enum Phase: Equatable {
        case checkingPermission
        case unsupported
        case permissionDenied
        case scanning
        case lookingUp(code: String)
        case noMatch(code: String, message: String)
        case failed(code: String, APIError)
        case matched(ProductMatch)
    }

    private let api: any APIClient
    private(set) var phase: Phase = .checkingPermission
    var manualCode = ""
    private var lookupTask: Task<Void, Never>?

    init(api: any APIClient, scannerSupported: Bool) {
        self.api = api
        if !scannerSupported { phase = .unsupported }
    }

    /// True when the live camera view should be shown.
    var showsCamera: Bool {
        switch phase {
        case .scanning, .lookingUp, .noMatch, .failed: true
        default: false
        }
    }

    func prepare() async {
        guard phase == .checkingPermission else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            phase = granted ? .scanning : .permissionDenied
        case .denied, .restricted:
            phase = .permissionDenied
        @unknown default:
            phase = .permissionDenied
        }
    }

    func handleScanned(_ code: String) {
        Haptics.success()
        lookup(code)
    }

    func lookupManualCode() {
        let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        lookup(code)
    }

    func lookup(_ code: String) {
        lookupTask?.cancel()
        phase = .lookingUp(code: code)
        lookupTask = Task { [api] in
            do {
                let match = try await api.lookupProduct(code: code)
                guard !Task.isCancelled else { return }
                phase = .matched(match)
            } catch let error as APIError {
                guard !error.isCancellation else { return }
                if error.isNotFound {
                    phase = .noMatch(code: code, message: error.message)
                } else {
                    phase = .failed(code: code, error)
                }
            } catch {
                phase = .failed(code: code, .invalidResponse)
            }
        }
    }

    func retryLookup() {
        switch phase {
        case .noMatch(let code, _), .failed(let code, _), .lookingUp(let code):
            lookup(code)
        default:
            break
        }
    }

    func scanAgain() {
        lookupTask?.cancel()
        phase = AVCaptureDevice.authorizationStatus(for: .video) == .authorized && !isUnsupported ? .scanning : phase
        if case .unsupported = phase { return }
        if phase != .scanning { phase = .scanning }
    }

    private var isUnsupported: Bool {
        if case .unsupported = phase { return true }
        return false
    }

    func cancel() {
        lookupTask?.cancel()
    }
}
