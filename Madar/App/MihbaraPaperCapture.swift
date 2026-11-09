import SwiftUI
import UIKit
import AVFoundation
import Vision
import VisionKit
import MadarCore
import MadarDesign

struct PaperBarcodeScannerSheet: View {
    let onISBN: (String) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if DataScannerViewController.isSupported {
                PaperBarcodeScanner(onISBN: onISBN, onError: { message in onError(message); dismiss() })
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("مسح الباركود غير متاح", systemImage: "barcode.viewfinder", description: Text("اكتب رقم الكتاب الدولي (ISBN) المطبوع تحت الباركود خلف الغلاف."))
            }
            Button("تمّ") { dismiss() }
                .font(.body.weight(.semibold))
                .padding(12)
                .background(.regularMaterial, in: .capsule)
                .padding()
                .accessibilityIdentifier("mihbara-paper-scanner-close")
        }
        .background(MadarToken.colors["rooms.mihbara.dark.desk"] ?? RoomTheme(room: "mihbara", dark: true).background)
    }
}

private struct PaperBarcodeScanner: UIViewControllerRepresentable {
    let onISBN: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onISBN: onISBN, onError: onError) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        context.coordinator.requestCameraAccess()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onISBN: (String) -> Void
        let onError: (String) -> Void
        private var finished = false
        weak var scanner: DataScannerViewController?

        init(onISBN: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onISBN = onISBN
            self.onError = onError
        }

        func requestCameraAccess() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                beginScanning()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard granted else { self.onError("لم تسمح باستخدام الكاميرا. أدخل رقم ISBN-13 يدويًا."); return }
                        self.beginScanning()
                    }
                }
            default:
                onError("الكاميرا غير مسموحة؛ أدخل رقم ISBN-13 يدويًا.")
            }
        }

        func beginScanning() {
            guard DataScannerViewController.isAvailable else {
                onError("الكاميرا غير متاحة الآن؛ أدخل رقم ISBN-13 يدويًا.")
                return
            }
            guard let scanner else { onError("تعذر تشغيل الكاميرا. أدخل رقم ISBN-13 يدويًا."); return }
            do { try scanner.startScanning() }
            catch { onError("تعذر تشغيل الكاميرا. أدخل رقم ISBN-13 يدويًا.") }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue else { continue }
                guard let isbn = PaperBookIndex.normalizedISBN13(value) else {
                    onError("هذا الباركود ليس ISBN-13 صالحًا. يمكنك كتابة الرقم يدويًا.")
                    continue
                }
                finished = true
                dataScanner.stopScanning()
                onISBN(isbn)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError("توقف مسح الباركود. أدخل رقم ISBN-13 يدويًا.")
        }
    }
}

struct PaperIndexDocumentScanner: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onLines: ([String]) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, onLines: onLines, onError: onError) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let isPresented: Binding<Bool>
        let onLines: ([String]) -> Void
        let onError: (String) -> Void

        init(isPresented: Binding<Bool>, onLines: @escaping ([String]) -> Void, onError: @escaping (String) -> Void) {
            self.isPresented = isPresented
            self.onLines = onLines
            self.onError = onError
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0, let image = scan.imageOfPage(at: 0).cgImage else {
                isPresented.wrappedValue = false
                onError("لم نجد صورة صالحة للفهرس. أعد التصوير أو أدخل الفصول يدويًا.")
                return
            }
            let outcome = Self.recognizeArabicIndex(in: image)
            isPresented.wrappedValue = false
            switch outcome {
            case .lines(let lines): onLines(lines)
            case .arabicUnavailable: onError("التعرّف العربي غير متاح على هذا الجهاز؛ الصورة لم تُحفظ، ويمكنك إدخال الفصول يدويًا.")
            case .failed: onError("تعذر قراءة النص من الصورة؛ الصورة لم تُحفظ، ويمكنك إدخال الفصول يدويًا.")
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            isPresented.wrappedValue = false
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            isPresented.wrappedValue = false
            onError("تعذر تصوير الصفحة؛ يمكنك إدخال الفصول يدويًا.")
        }

        private enum OCRResult { case lines([String]), arabicUnavailable, failed }

        private static func recognizeArabicIndex(in image: CGImage) -> OCRResult {
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let languages = try request.supportedRecognitionLanguages()
                guard let arabic = languages.first(where: { $0 == "ar" || $0.hasPrefix("ar-") }) else { return .arabicUnavailable }
                request.recognitionLanguages = [arabic]
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return .lines(lines)
            } catch {
                return .failed
            }
        }
    }
}
