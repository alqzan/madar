import SwiftUI
import Photos
import ImageIO
import UIKit
import UniformTypeIdentifiers
import SwiftData
import MadarCore
import MadarData
import MadarDesign

/// Owner, 24 Oct 2026: «ارتباط تطبيقنا بتطبيق الصور». A diary photo stays in the Photos library; Madar keeps the
/// asset identifier and a small copy (so the day still shows it if the original is deleted or on another device).
enum DiaryPhotoLibrary {
    /// Long edge of the kept copy, in pixels. JPEG at this size is tens of kilobytes.
    static let copyPixels = 640
    /// B1-13: a camera photo has no original in Photos, so the diary keeps the only copy: 2048 px on the long edge, good JPEG.
    static let cameraPixels = 2048
    static func cameraCopy(of data: Data) -> Data? { scaledCopy(of: data, maxPixels: cameraPixels, quality: 0.85) }
    static func smallCopy(of data: Data) -> Data? { scaledCopy(of: data, maxPixels: copyPixels, quality: 0.72) }
    static func scaledCopy(of data: Data, maxPixels: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(target) ? out as Data : nil
    }
    static var canRead: Bool { [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    /// Photos taken on this Gregorian day in the place's time zone: the newest 30, oldest first.
    static func assets(on day: GregorianDay, timeZone: TimeZone) -> [PHAsset] {
        guard canRead else { return [] }
        let start = day.date(in: timeZone), end = day.adding(days: 1).date(in: timeZone)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@", PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; options.fetchLimit = 30
        let result = PHAsset.fetchAssets(with: options)
        return (0..<result.count).map { result.object(at: $0) }.reversed()
    }
    static func asset(_ id: String) -> PHAsset? { canRead ? PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject : nil }
    static func image(_ asset: PHAsset, side: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.isNetworkAccessAllowed = false; options.resizeMode = .fast
        return await withCheckedContinuation { done in
            // `.opportunistic` calls back twice (a degraded image, then the final one); a continuation resumes once (FB-45: crash).
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                done.resume(returning: image)
            }
        }
    }
    static func data(_ asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.version = .current
        return await withCheckedContinuation { done in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in done.resume(returning: data) }
        }
    }
    /// Library identifiers already linked anywhere in the diary, so a suggestion is never offered twice.
    @MainActor static func linkedIDs(_ app: AppSession) -> Set<String> {
        let predicate = #Predicate<Media> { $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil }
        let rows: [Media] = (try? ModelContext(app.container).fetch(FetchDescriptor<Media>(predicate: predicate))) ?? []
        return Set(rows.compactMap { DiaryPhotoLink.assetID(sourceID: $0.sourceID) })
    }
}

/// «صور هذا اليوم»: the day's own photos from the Photos library, one tap links one. Nothing is added without a tap.
/// Before access is decided it offers one quiet invitation; with access denied it shows nothing (no dead button).
struct DiaryDayPhotos: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    let link: (PHAsset) async -> Bool
    /// On the day page a tap shows the photo full size (pin or comment there); in the editors a tap pins it.
    var open: ((PHAsset) -> Void)? = nil
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var assets: [PHAsset] = []
    @State private var linked: Set<String> = []
    @State private var busy: String?
    var body: some View {
        // Keep a real container even when authorization is already granted and the
        // initial asset list is empty; Group has no child to run the loading task on.
        VStack(alignment: .leading, spacing: 0) {
            if status == .notDetermined {
                Button { Task { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite); load() } } label: {
                    Label("اعرض صور هذا اليوم من تطبيق الصور", systemImage: "photo.on.rectangle.angled").font(MadarTypography.caption()).frame(minHeight: 44)
                }.buttonStyle(.madarPlain).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("diary-day-photos-allow")
            } else if !visible.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(open == nil ? "صور هذا اليوم · المس صورة لتثبيتها في الصفحة" : "صور هذا اليوم · المس صورة لتراها وتعلّق عليها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(visible, id: \.localIdentifier) { asset in DiaryDayPhotoThumb(asset: asset, busy: busy == asset.localIdentifier, pick: { if let open { open($0) } else { pick($0) } }) } }
                    }
                }.accessibilityIdentifier("diary-day-photos")
            }
        }
        .task(id: day.description) {
            // Owner 12 Nov: the day's photos appear by default; the one system prompt is asked the first time a day opens.
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined, ProcessInfo.processInfo.environment["MADAR_UI_NOW"] == nil {
                status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            load()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { load() } }
    }
    private var visible: [PHAsset] { assets.filter { !linked.contains($0.localIdentifier) } }
    private func load() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        assets = DiaryPhotoLibrary.assets(on: day, timeZone: app.activePlace.timeZone); linked = DiaryPhotoLibrary.linkedIDs(app)
    }
    private func pick(_ asset: PHAsset) {
        guard busy == nil else { return }; busy = asset.localIdentifier
        Task {
            if await link(asset) { linked.insert(asset.localIdentifier) }
            busy = nil
        }
    }
}
private struct DiaryDayPhotoThumb: View {
    let asset: PHAsset
    let busy: Bool
    let pick: (PHAsset) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var image: UIImage?
    var body: some View {
        Button { pick(asset) } label: {
            ZStack {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { theme.surface }
                if busy { ProgressView() }
            }.frame(width: 88, height: 88).clipShape(.rect(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(theme.line) }
        }.buttonStyle(.madarPlain).accessibilityLabel("أضف هذه الصورة إلى صفحة اليوم").accessibilityIdentifier("diary-day-photo")
            .task { image = await DiaryPhotoLibrary.image(asset, side: 200) }
    }
}

/// Opens the system camera directly from the diary. Captures are handed back as
/// images and reduced to Madar's existing small local attachment copy.
struct DiaryCameraCapture: UIViewControllerRepresentable {
    let captured: (UIImage) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(captured: captured, cancelled: cancelled) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let captured: (UIImage) -> Void
        let cancelled: () -> Void
        init(captured: @escaping (UIImage) -> Void, cancelled: @escaping () -> Void) {
            self.captured = captured; self.cancelled = cancelled
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { captured(image) } else { cancelled() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancelled() }
    }
}
