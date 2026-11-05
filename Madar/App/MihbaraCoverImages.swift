import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import MadarCore
import MadarData
import MadarDesign
import MadarCommands

/// FB-36 (owner, 5 Nov 2026): «ابي طريقه لو اضفت غلاف الكتاب يجيك ويطلع له شكل حلو».
/// A book's own cover photo (`book.saveCover`, a Media row keyed `book-cover:<id>`) is shown on its face in the library
/// and in «بين يديك», and its spine on the bookcase takes the tested binding nearest the photo's colour.
/// Thumbnails and colours are a derived, in-memory cache rebuilt from the store; nothing here is a record.
@MainActor @Observable final class MihbaraCoverStore {
    static let shared = MihbaraCoverStore()
    private(set) var images: [UUID: UIImage] = [:]
    private(set) var bindings: [UUID: Int] = [:]
    @ObservationIgnored private var hashes: [UUID: String] = [:]

    private struct Loaded: @unchecked Sendable { let id: UUID; let hash: String; let image: CGImage?; let colour: UInt32? }

    func reload(_ container: ModelContainer) async {
        let known = hashes
        let loaded: [Loaded] = await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            guard let rows = try? context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })) else { return [] }
            var result: [Loaded] = []
            for row in rows {
                guard let key = row.sourceID, key.hasPrefix("book-cover:"), let id = UUID(uuidString: String(key.dropFirst(11))) else { continue }
                if known[id] == row.sha256 { result.append(.init(id: id, hash: row.sha256, image: nil, colour: nil)); continue }
                guard let data = row.data, let image = Self.thumbnail(data, maxPixel: 720) else { continue }
                result.append(.init(id: id, hash: row.sha256, image: image, colour: Self.averageColour(image)))
            }
            return result
        }.value
        var images = self.images, bindings = self.bindings, hashes: [UUID: String] = [:]
        let live = Set(loaded.map(\.id))
        for id in Array(images.keys) where !live.contains(id) { images[id] = nil; bindings[id] = nil }
        for item in loaded {
            hashes[item.id] = item.hash
            guard let image = item.image else { continue }
            images[item.id] = UIImage(cgImage: image)
            if let colour = item.colour { bindings[item.id] = BookBindings.nearest(to: colour) }
        }
        self.hashes = hashes
        if images != self.images { self.images = images }
        if bindings != self.bindings { self.bindings = bindings }
    }

    /// A photo becomes a JPEG of at most 1200 px on its long side (about 150–300 KB), upright, before it is stored.
    nonisolated static func prepared(_ data: Data) -> Data? {
        guard let image = thumbnail(data, maxPixel: 1200) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    nonisolated static func thumbnail(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The photo's mean colour, by drawing it into one pixel.
    nonisolated static func averageColour(_ image: CGImage) -> UInt32? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UInt32(pixel[0]) << 16 | UInt32(pixel[1]) << 8 | UInt32(pixel[2])
    }
}

extension AppSession {
    /// Saves (or, with nil, removes) a book's cover and refreshes every shelf that shows it.
    func saveBookCover(_ bookID: UUID, photo: Data?) async throws {
        var image = Data()
        if let photo {
            guard let prepared = await Task.detached(priority: .userInitiated, operation: { MihbaraCoverStore.prepared(photo) }).value else {
                throw DataError.invalidValue("تعذّرت قراءة الصورة. جرّب صورة أخرى.")
            }
            image = prepared
        }
        try await executeBookCommand("book.saveCover", payload: ["bookID": .string(bookID.uuidString), "image": .string(image.base64EncodedString())])
        await MihbaraCoverStore.shared.reload(container)
    }
}

/// The cover on the book card: tap it to choose a photo from the library, change it, or take it off.
struct MihbaraCoverButton: View {
    let app: AppSession
    let book: MihbaraBook
    let books: [MihbaraBook]
    var shape: MihbaraBookShape? = nil
    var scale: CGFloat = 0.62
    @Environment(\.roomTheme) private var theme
    @State private var picking = false
    @State private var item: PhotosPickerItem?
    @State private var saving = false
    private var hasCover: Bool { MihbaraCoverStore.shared.images[book.id] != nil }

    var body: some View {
        let digits = AppMihbaraService(app: app).digits
        let height = MihbaraBookCovers.metrics(pages: shape?.pages ?? book.pages).height
        Menu {
            Button(hasCover ? "غيّر صورة الغلاف" : "اختر صورة الغلاف", systemImage: "photo") { picking = true }
            if hasCover { Button("أزل صورة الغلاف", systemImage: "xmark.circle", role: .destructive) { save(nil) } }
        } label: {
            MihbaraBookCover(book: book, shape: shape, leather: MihbaraBookCovers.leatherIndices(for: books)[book.id] ?? 0, digits: digits)
                .scaleEffect(scale, anchor: .center)
                .frame(width: 124 * scale, height: height * scale)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: saving ? "hourglass" : hasCover ? "photo" : "camera.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .offset(x: -6, y: 6)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(.madarPlain)
        .disabled(saving)
        .accessibilityLabel(hasCover ? "غلاف الكتاب" : "أضف صورة الغلاف")
        .accessibilityIdentifier("mihbara-cover-button")
        .photosPicker(isPresented: $picking, selection: $item, matching: .images, photoLibrary: .shared())
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            item = nil
            Task {
                guard let data = try? await picked.loadTransferable(type: Data.self) else { app.errorMessage = "تعذّرت قراءة الصورة. جرّب صورة أخرى."; return }
                save(data)
            }
        }
    }

    private func save(_ photo: Data?) {
        saving = true
        Task {
            defer { saving = false }
            do { try await app.saveBookCover(book.id, photo: photo) } catch { app.errorMessage = error.localizedDescription }
        }
    }
}
