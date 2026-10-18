import Foundation
import ReadiumShared
import ReadiumStreamer
import MadarCore
import MadarData

struct MihbaraOfflineHTTPClient: HTTPClient {
    func stream(request: HTTPRequestConvertible, consume: @escaping (Data, Double?) -> HTTPResult<Void>) async -> HTTPResult<HTTPResponse> {
        .failure(.offline(nil))
    }
}

enum MihbaraEPUBLoader {
    nonisolated static func open(at file: URL) async throws -> sending Publication {
        let http = MihbaraOfflineHTTPClient()
        let retriever = AssetRetriever(httpClient: http)
        guard let fileURL = FileURL(url: file), case .success(let asset) = await retriever.retrieve(url: fileURL) else {
            throw DataError.invalidValue("تعذّر فتح بنية ملف EPUB")
        }
        let parser = DefaultPublicationParser(httpClient: http, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory())
        let opener = PublicationOpener(parser: parser, onCreatePublication: { manifest, container, _ in
            let htmlResources = Set((manifest.readingOrder + manifest.resources)
                .filter { $0.mediaType?.isHTML == true }.map { $0.url().removingFragment() })
            container = container.map { href, resource in
                let path = href.string.lowercased().split(separator: "?").first.map(String.init) ?? ""
                guard htmlResources.contains(href.removingFragment()) || [".xhtml", ".html", ".htm"].contains(where: { path.hasSuffix($0) }) else { return resource }
                return TransformingResource(resource) { result in
                    result.flatMap { bytes in
                        let encoding: String.Encoding = String(data: bytes, encoding: .utf8) == nil ? .utf16 : .utf8
                        guard let source = String(data: bytes, encoding: encoding),
                              let secured = ReadingDocumentPolicy.secure(source), let securedBytes = secured.data(using: encoding) else {
                            return .failure(.decoding("EPUB document has no safe HTML head"))
                        }
                        return .success(securedBytes)
                    }
                }
            }
        })
        guard case .success(let opened) = await opener.open(asset: asset, allowUserInteraction: false) else {
            throw DataError.invalidValue("ملف EPUB غير مكتمل أو غير مدعوم")
        }
        return opened
    }
}
