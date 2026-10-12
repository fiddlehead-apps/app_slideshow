import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Keeps a folder picked in Files readable for as long as anything still
/// refers to it (playback and the saving job both hold on to it).
nonisolated final class FolderAccess: Sendable {
    let url: URL
    private let started: Bool

    init(_ url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    deinit { if started { url.stopAccessingSecurityScopedResource() } }
}

/// One picked image, before it has been copied into the app.
nonisolated enum SourceItem: Sendable {
    case file(URL, name: String, access: FolderAccess?)
    case photo(PhotosPickerItem)

    var name: String {
        switch self {
        case .file(_, let name, _): name
        case .photo: ""
        }
    }

    /// Reads the image bytes. Files are read through a file coordinator, which
    /// makes iCloud Drive download items that are not on the device yet.
    @concurrent func data() async throws -> Data {
        switch self {
        case .file(let url, _, let access):
            return try withExtendedLifetime(access) { try Self.coordinatedRead(url) }
        case .photo(let item):
            guard let d = try await item.loadTransferable(type: Data.self) else { throw ImageError.unreadable }
            return d
        }
    }

    private static func coordinatedRead(_ url: URL) throws -> Data {
        var coordError: NSError?
        var result: Result<Data, Error> = .failure(ImageError.unreadable)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { try Data(contentsOf: u) }
        }
        if let coordError { throw coordError }
        return try result.get()
    }
}

nonisolated enum ImageError: Error { case unreadable, encodeFailed }

nonisolated enum Images {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff"]

    /// Longest edge kept for saved copies: the screen's native resolution,
    /// at least 1600 and at most 2732 pixels (same rule as the web app).
    @MainActor static var maxEdge: Int {
        let b = UIScreen.main.nativeBounds
        return min(2732, max(1600, Int(max(b.width, b.height))))
    }

    /// Lists every image in a folder and its subfolders, sorted by path the way
    /// Finder sorts ("img2" before "img10"). Hidden files and folders are skipped.
    @concurrent static func scan(folder: URL, access: FolderAccess) async -> [SourceItem] {
        collect(folder: folder, access: access)
    }

    private static func collect(folder: URL, access: FolderAccess) -> [SourceItem] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else { return [] }
        let base = folder.standardizedFileURL.path
        var found: [(rel: String, url: URL, name: String)] = []
        for case let url as URL in e {
            if Task.isCancelled { return [] }
            var name = url.lastPathComponent
            var real = url
            // iCloud Drive can list files that are not downloaded as ".Name.jpg.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(7))
                real = url.deletingLastPathComponent().appendingPathComponent(name)
            } else if name.hasPrefix(".") {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { e.skipDescendants() }
                continue
            }
            guard extensions.contains(real.pathExtension.lowercased()) else { continue }
            var rel = real.standardizedFileURL.path
            if rel.hasPrefix(base) { rel = String(rel.dropFirst(base.count)) }
            found.append((rel, real, name))
        }
        found.sort { $0.rel.localizedStandardCompare($1.rel) == .orderedAscending }
        return found.map { .file($0.url, name: $0.name, access: access) }
    }

    /// Single files picked in Files (not a folder).
    static func items(fromFiles urls: [URL]) -> [SourceItem] {
        urls.filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { .file($0, name: $0.lastPathComponent, access: FolderAccess($0)) }
    }

    // MARK: Decoding

    private static func thumbnail(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Decodes an image for display, already scaled down to at most `maxPixel`.
    @concurrent static func display(data: Data, maxPixel: Int) async -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = thumbnail(src, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: cg)
    }

    @concurrent static func display(url: URL, maxPixel: Int) async -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = thumbnail(src, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Saving copies

    struct Shrunk: Sendable {
        let data: Data
        let thumb: Data?
    }

    /// Makes the copy that gets saved: the original bytes if the image is
    /// already small enough and in a common format, otherwise a JPEG whose
    /// longest edge is `maxEdge`. Optionally also a 168 px square thumbnail.
    @concurrent static func shrink(_ data: Data, maxEdge: Int, wantThumb: Bool) async throws -> Shrunk {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { throw ImageError.unreadable }

        let type = CGImageSourceGetType(src).flatMap { UTType($0 as String) }
        let keepable: [UTType] = [.jpeg, .png, .gif, .webP]
        let out: Data
        if max(w, h) <= maxEdge, let type, keepable.contains(type) {
            out = data
        } else {
            guard let cg = thumbnail(src, maxPixel: maxEdge) else { throw ImageError.unreadable }
            out = try jpeg(cg, quality: 0.86)
        }

        var thumb: Data?
        if wantThumb, let cg = thumbnail(src, maxPixel: 400) {
            let m = min(cg.width, cg.height)
            let crop = CGRect(x: (cg.width - m) / 2, y: (cg.height - m) / 2, width: m, height: m)
            if let sq = cg.cropping(to: crop), let small = draw(sq, side: 168) {
                thumb = try? jpeg(small, quality: 0.8)
            }
        }
        return Shrunk(data: out, thumb: thumb)
    }

    private static func draw(_ cg: CGImage, side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }

    /// Transparent areas turn black, like in the web app.
    private static func opaque(_ cg: CGImage) -> CGImage {
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return cg
        default: break
        }
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    private static func jpeg(_ cg: CGImage, quality: Double) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageError.encodeFailed
        }
        CGImageDestinationAddImage(dest, opaque(cg), [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageError.encodeFailed }
        return out as Data
    }
}
