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
                    ProgressView().tint(Palette.ink)
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
                    .font(Typography.control)
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
        VStack(spacing: 0) {
            Group {
                switch model.phase {
                case .checkingPermission:
                    ProgressView("Preparing camera…")
                        .tint(Palette.ink)
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
                            .accessibilityLabel("Camera viewfinder. Point at a product barcode.")
                        reticle
                        statusOverlay(model)
                    }
                    .softClip()
                    .cardGutter()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 240)

            manualEntry(model)
        }
    }

    /// Four coral corners, rounded: the only coral on the screen.
    private var reticle: some View {
        GeometryReader { proxy in
            let inset = proxy.size.width * 0.14
            let arm: CGFloat = 28
            let w: CGFloat = 4
            ZStack {
                Path { p in
                    let r = CGRect(x: inset, y: inset, width: proxy.size.width - 2 * inset, height: proxy.size.height - 2 * inset)
                    for corner in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                        let dx: CGFloat = corner.x == r.minX ? arm : -arm
                        let dy: CGFloat = corner.y == r.minY ? arm : -arm
                        p.move(to: CGPoint(x: corner.x, y: corner.y + dy))
                        p.addLine(to: corner)
                        p.addLine(to: CGPoint(x: corner.x + dx, y: corner.y))
                    }
                }
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func statusOverlay(_ model: ScannerViewModel) -> some View {
        switch model.phase {
        case .scanning:
            Text("Point the camera at the product barcode")
                .eyebrowStyle(color: .white)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(.black.opacity(0.72), in: Capsule(style: .continuous))
                .padding(Spacing.m)
        case .lookingUp(let code):
            HStack(spacing: Spacing.s) {
                ProgressView().tint(.white)
                Text("Looking up \(code)…")
            }
            .eyebrowStyle(color: .white)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(.black.opacity(0.72), in: Capsule(style: .continuous))
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
            Text(title).headlineStyle(Typography.pairName)
            Text(message).font(Typography.meta).foregroundStyle(Palette.secondary)
            HStack(spacing: Spacing.s) {
                Button("Scan again") { model.scanAgain() }.buttonStyle(.secondary)
                Button("Retry lookup") { model.retryLookup() }.buttonStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .softCard()
        .padding(Spacing.m)
    }

    private func scannerUnavailable(title: String, message: String, showSettings: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            IconBox(symbol: "camera.fill")
            Text(title)
                .headlineStyle(Typography.heading)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.secondary)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .swissGrid(radius: Radius.card)
        .cardGutter()
    }

    private func manualEntry(_ model: ScannerViewModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionLabel("02", "Or type the barcode number")
                UnderlinedField(label: "Barcode number", text: $model.manualCode, placeholder: "e.g. 3337875597180")
                    .keyboardType(.numberPad)
                    .focused($codeFieldFocused)
                    .onSubmit { model.lookupManualCode() }
                Button("Look up") { model.lookupManualCode() }
                    .buttonStyle(.primary)
                    .disabled(model.manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                if case .lookingUp(let code) = model.phase, code == model.manualCode.trimmingCharacters(in: .whitespaces) {
                    HStack(spacing: Spacing.s) {
                        ProgressView().tint(Palette.ink)
                        Text("Looking up \(code)…").eyebrowStyle()
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
            .softCard()
            .cardGutter()
        }
        .padding(.vertical, Spacing.m)
    }
}

#Preview {
    BarcodeScannerSheet { _ in }
        .environment(\.api, MockAPIClient())
}
