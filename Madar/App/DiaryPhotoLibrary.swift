import SwiftUI
import Photos
import ImageIO
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
    static func smallCopy(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: copyPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        return CGImageDestinationFinalize(target) ? out as Data : nil
    }
    static var canRead: Bool { [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    /// Photos taken on this Gregorian day in the place's time zone, newest last, at most 30.
    static func assets(on day: GregorianDay, timeZone: TimeZone) -> [PHAsset] {
        guard canRead else { return [] }
        let start = day.date(in: timeZone), end = day.adding(days: 1).date(in: timeZone)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@", PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]; options.fetchLimit = 30
        let result = PHAsset.fetchAssets(with: options)
        return (0..<result.count).map { result.object(at: $0) }
    }
    static func asset(_ id: String) -> PHAsset? { canRead ? PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject : nil }
    static func image(_ asset: PHAsset, side: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions(); options.deliveryMode = .highQualityFormat; options.isNetworkAccessAllowed = true; options.resizeMode = .fast
        return await withCheckedContinuation { done in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { image, _ in done.resume(returning: image) }
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
    let link: (PHAsset) async -> Void
    @Environment(\.roomTheme) private var theme
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var assets: [PHAsset] = []
    @State private var linked: Set<String> = []
    @State private var busy: String?
    var body: some View {
        Group {
            if status == .notDetermined {
                Button { Task { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite); load() } } label: {
                    Label("اعرض صور هذا اليوم من تطبيق الصور", systemImage: "photo.on.rectangle.angled").font(MadarTypography.caption()).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("diary-day-photos-allow")
            } else if !visible.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("صور هذا اليوم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(visible, id: \.localIdentifier) { DiaryDayPhotoThumb(asset: $0, busy: busy == $0.localIdentifier, pick: pick) } }
                    }
                }.accessibilityIdentifier("diary-day-photos")
            }
        }.task(id: day.description) { load() }
    }
    private var visible: [PHAsset] { assets.filter { !linked.contains($0.localIdentifier) } }
    private func load() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        assets = DiaryPhotoLibrary.assets(on: day, timeZone: app.activePlace.timeZone); linked = DiaryPhotoLibrary.linkedIDs(app)
    }
    private func pick(_ asset: PHAsset) {
        guard busy == nil else { return }; busy = asset.localIdentifier
        Task { await link(asset); linked.insert(asset.localIdentifier); busy = nil }
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
            }.frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(theme.line) }
        }.buttonStyle(.plain).accessibilityLabel("أضف هذه الصورة إلى صفحة اليوم").accessibilityIdentifier("diary-day-photo")
            .task { image = await DiaryPhotoLibrary.image(asset, side: 128) }
    }
}
