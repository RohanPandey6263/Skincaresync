import SwiftUI
import UIKit

/// Barcode entry: camera when available, manual code entry always.
struct BarcodeScannerSheet: View {
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    let onMatch: (ProductMatch) -> Void

    @State private var model: ScannerViewModel?
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.page)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = ScannerViewModel(api: api, scannerSupported: BarcodeScannerView.isSupported)
            }
            await model?.prepare()
        }
        .onChange(of: model?.phase) { _, phase in
            if case .matched(let match) = phase {
                onMatch(match)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ScannerViewModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Group {
                switch model.phase {
                case .checkingPermission:
                    ProgressView("Preparing camera…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unsupported:
                    scannerUnavailable(
                        title: "Camera scanning isn't available here",
                        message: "This device or simulator cannot run the barcode scanner. Type the barcode number below instead.")
                case .permissionDenied:
                    scannerUnavailable(
                        title: "Camera access is off",
                        message: "Allow camera access in Settings to scan, or type the barcode number below. Camera access is never required.",
                        showSettings: true)
                case .scanning, .lookingUp, .noMatch, .failed, .matched:
                    ZStack(alignment: .bottom) {
                        BarcodeScannerView { code in model.handleScanned(code) }
                            .ignoresSafeArea(edges: .horizontal)
                            .accessibilityLabel("Camera viewfinder. Point at a product barcode.")
                        statusOverlay(model)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)

            manualEntry(model)
        }
    }

    @ViewBuilder
    private func statusOverlay(_ model: ScannerViewModel) -> some View {
        switch model.phase {
        case .scanning:
            Text("Point the camera at the product barcode")
                .font(Typography.meta)
                .foregroundStyle(.white)
                .padding(Spacing.s)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(Spacing.m)
        case .lookingUp(let code):
            HStack(spacing: Spacing.s) {
                ProgressView().tint(.white)
                Text("Looking up \(code)…")
            }
            .font(Typography.meta)
            .foregroundStyle(.white)
            .padding(Spacing.s)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(Spacing.m)
            .accessibilityElement(children: .combine)
        case .noMatch(let code, let message):
            resultBanner(title: "No match for \(code)", message: message, model: model)
        case .failed(let code, let error):
            resultBanner(title: "\(error.title) (\(code))", message: error.message, model: model)
        default:
            EmptyView()
        }
    }

    private func resultBanner(title: String, message: String, model: ScannerViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.forest)
            Text(message).font(Typography.meta).foregroundStyle(Palette.muted)
            HStack(spacing: Spacing.s) {
                Button("Scan again") { model.scanAgain() }.buttonStyle(.secondary)
                Button("Retry lookup") { model.retryLookup() }.buttonStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .background(Palette.page)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .padding(Spacing.m)
    }

    private func scannerUnavailable(title: String, message: String, showSettings: Bool = false) -> some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.sage)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(Palette.forest)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 240)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func manualEntry(_ model: ScannerViewModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Or type the barcode number").eyebrowStyle()
            HStack(spacing: Spacing.s) {
                TextField("e.g. 3337875597180", text: $model.manualCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($codeFieldFocused)
                    .submitLabel(.search)
                    .onSubmit { model.lookupManualCode() }
                    .accessibilityLabel("Barcode number")
                Button("Look up") { model.lookupManualCode() }
                    .buttonStyle(.secondary)
                    .frame(width: 110)
                    .disabled(model.manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if case .lookingUp(let code) = model.phase, code == model.manualCode.trimmingCharacters(in: .whitespaces) {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Looking up \(code)…").font(Typography.meta).foregroundStyle(Palette.muted)
                }
            }
            if !model.showsCamera {
                switch model.phase {
                case .noMatch(let code, let message):
                    InlineNotice(kind: .error, text: "No match for \(code). \(message)", actionTitle: "Retry") { model.retryLookup() }
                case .failed(let code, let error):
                    InlineNotice(kind: .error, text: "\(error.title) for \(code). \(error.message)", actionTitle: "Retry") { model.retryLookup() }
                default:
                    EmptyView()
                }
            }
        }
        .padding(Spacing.m)
        .background(Palette.page)
    }
}

#Preview {
    BarcodeScannerSheet { _ in }
        .environment(\.api, MockAPIClient())
}
