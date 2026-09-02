import SwiftUI
import UIKit
import VisionKit

/// SwiftUI wrapper around VisionKit's `DataScannerViewController`, limited to
/// retail barcode symbologies. Reports the first stable code and stops.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> ScannerHostController {
        ScannerHostController(onCode: onCode)
    }

    func updateUIViewController(_ controller: ScannerHostController, context: Context) {
        controller.onCode = onCode
    }
}

/// Hosts the scanner as a child so scanning starts and stops with the view's
/// lifecycle rather than on construction.
final class ScannerHostController: UIViewController, DataScannerViewControllerDelegate {
    var onCode: (String) -> Void
    private var scanner: DataScannerViewController?
    private var delivered = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .qr, .dataMatrix])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
        self.scanner = scanner
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        delivered = false
        try? scanner?.startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner?.stopScanning()
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        deliver(from: addedItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        deliver(from: [item])
    }

    private func deliver(from items: [RecognizedItem]) {
        guard !delivered else { return }
        for item in items {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, !value.isEmpty {
                delivered = true
                scanner?.stopScanning()
                onCode(value)
                return
            }
        }
    }
}
