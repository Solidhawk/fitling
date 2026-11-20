import SwiftUI
import Vision
import VisionKit

/// The camera looks for EAN-13, EAN-8 and UPC barcodes. Where scanning is not possible (no
/// camera, no permission, the simulator), the barcode can be typed in.
struct ScanSheet: View {
    let onCode: @MainActor (String) -> Void
    @State private var typed = ""
    @Environment(\.dismiss) private var dismiss

    private var canScan: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                if canScan {
                    BarcodeScanner(onCode: onCode)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .accessibilityLabel(Text("scan.title"))
                } else {
                    Text("scan.unavailable")
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: Spacing.s) {
                    TextField("scan.manual.field", text: $typed)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("scan.manual")
                    Button("scan.manual.submit") { onCode(typed) }
                        .buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                        .disabled(typed.isEmpty)
                        .accessibilityIdentifier("scan.manual.submit")
                }
            }
            .padding(Spacing.l)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.ground)
            .navigationTitle("scan.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    // Main actor, like the scanner; @preconcurrency in case the SDK declares the delegate without it.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency DataScannerViewControllerDelegate {
        let onCode: @MainActor (String) -> Void
        /// The scanner reports the same code many times while it is in view.
        private var lastCode: String?

        init(onCode: @escaping @MainActor (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case let .barcode(barcode) = item, let code = barcode.payloadStringValue, code != lastCode else { continue }
                lastCode = code
                onCode(code)
                return
            }
        }
    }
}
