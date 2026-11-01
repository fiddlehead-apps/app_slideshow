import Photos
import SwiftUI
import UIKit

/// An album (or a folder of albums) in the Photos library, as plain values so it can
/// travel between the main actor and the background work that reads the library.
nonisolated struct PhotoAlbum: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case album, folder }

    /// The `localIdentifier` of the PHAssetCollection or PHCollectionList.
    let id: String
    let title: String
    let kind: Kind
    /// Images in an album, albums and folders in a folder.
    let count: Int
    /// The `localIdentifier` of the image shown as the album's cover.
    let cover: String?
}

/// Reads albums and their images from the Photos library (PhotoKit). Works the same on
/// iPhone, iPad and the Mac; only images are used, videos are left out.
nonisolated enum PhotoAlbums {
    enum Access { case full, limited, denied }

    /// Asks for access the first time. Picking an album needs read access to the library;
    /// with "limited" access Photos only shows the images the user selected, and no albums.
    @MainActor static func requestAccess() async -> Access {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        default: return .denied
        }
    }

    nonisolated struct Sections: Sendable {
        /// Recents and Favorites.
        var library: [PhotoAlbum] = []
        /// The user's own albums and folders, in the order they have in Photos.
        var mine: [PhotoAlbum] = []
        var shared: [PhotoAlbum] = []
        /// Selfies, Portrait, Panoramas, Screenshots, …
        var types: [PhotoAlbum] = []

        var isEmpty: Bool { library.isEmpty && mine.isEmpty && shared.isEmpty && types.isEmpty }
    }

    private static let librarySubtypes: [PHAssetCollectionSubtype] = [.smartAlbumUserLibrary, .smartAlbumFavorites]
    private static let typeSubtypes: [PHAssetCollectionSubtype] = [
        .smartAlbumSelfPortraits, .smartAlbumDepthEffect, .smartAlbumLivePhotos, .smartAlbumPanoramas,
        .smartAlbumBursts, .smartAlbumLongExposures, .smartAlbumAnimated, .smartAlbumRAW,
        .smartAlbumScreenshots, .smartAlbumRecentlyAdded
    ]

    private static func imagesOnly() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    /// Every album that has images, sorted into the sections of the picker.
    @concurrent static func load() async -> Sections {
        var s = Sections()
        s.library = librarySubtypes.compactMap { smartAlbum($0) }
        s.types = typeSubtypes.compactMap { smartAlbum($0) }
        s.mine = collections(PHCollectionList.fetchTopLevelUserCollections(with: nil))
        s.shared = all(PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil))
            .compactMap { album($0) }
        return s
    }

    /// The albums and folders inside a folder.
    @concurrent static func contents(ofFolder id: String) async -> [PhotoAlbum] {
        guard let list = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
        return collections(PHCollection.fetchCollections(in: list, options: nil))
    }

    /// The album's images in the order Photos shows them.
    @concurrent static func items(inAlbum id: String) async -> [SourceItem] {
        guard let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
        return all(PHAsset.fetchAssets(in: c, options: imagesOnly())).map { .asset($0.localIdentifier) }
    }

    private static func all<T: AnyObject>(_ result: PHFetchResult<T>) -> [T] {
        result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    private static func smartAlbum(_ subtype: PHAssetCollectionSubtype) -> PhotoAlbum? {
        PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).firstObject.flatMap(album)
    }

    private static func collections(_ result: PHFetchResult<PHCollection>) -> [PhotoAlbum] {
        all(result).compactMap { c in
            if let a = c as? PHAssetCollection { return album(a) }
            guard let list = c as? PHCollectionList else { return nil }
            let inside = PHCollection.fetchCollections(in: list, options: nil).count
            guard inside > 0 else { return nil }
            return PhotoAlbum(id: list.localIdentifier, title: list.localizedTitle ?? "", kind: .folder,
                              count: inside, cover: nil)
        }
    }

    /// nil for albums without images (empty, or only videos).
    private static func album(_ c: PHAssetCollection) -> PhotoAlbum? {
        let assets = PHAsset.fetchAssets(in: c, options: imagesOnly())
        guard assets.count > 0 else { return nil }
        let key = PHAsset.fetchKeyAssets(in: c, options: imagesOnly())?.firstObject ?? assets.lastObject
        return PhotoAlbum(id: c.localIdentifier, title: c.localizedTitle ?? "", kind: .album,
                          count: assets.count, cover: key?.localIdentifier)
    }

    // MARK: Images

    private static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// The image's bytes as Photos shows it (with edits). Images that are only in iCloud
    /// Photos are downloaded first.
    @concurrent static func data(forAsset id: String) async throws -> Data {
        guard let a = asset(id) else { throw ImageError.unreadable }
        let o = PHImageRequestOptions()
        o.version = .current
        o.deliveryMode = .highQualityFormat
        o.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { c in
            // With .highQualityFormat the handler is called exactly once.
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: o) { data, _, _, info in
                if let data {
                    c.resume(returning: data)
                } else {
                    c.resume(throwing: (info?[PHImageErrorKey] as? Error) ?? ImageError.unreadable)
                }
            }
        }
    }

    /// A small square picture for the album list.
    @concurrent static func cover(_ id: String, side: CGFloat) async -> UIImage? {
        guard let a = asset(id) else { return nil }
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        return await withCheckedContinuation { c in
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFill, options: o) { image, _ in
                c.resume(returning: image)
            }
        }
    }
}

// MARK: - Picker

/// The sheet that lists the albums in Photos. Picking one plays all of its images.
struct AlbumPicker: View {
    var limited: Bool
    var onPick: (PhotoAlbum) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sections: PhotoAlbums.Sections?

    var body: some View {
        NavigationStack {
            Group {
                if let sections {
                    if sections.isEmpty && !limited {
                        ContentUnavailableView("No albums with photos", systemImage: "rectangle.stack",
                                               description: Text("Make an album in the Photos app and it shows up here."))
                    } else {
                        List {
                            if limited { LimitedAccessNote() }
                            section("Library", sections.library)
                            section("My albums", sections.mine)
                            section("Shared albums", sections.shared)
                            section("Media types", sections.types)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Choose an album")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PhotoAlbum.self) { folder in
                AlbumFolderList(folder: folder, onPick: onPick)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { sections = await PhotoAlbums.load() }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ albums: [PhotoAlbum]) -> some View {
        if !albums.isEmpty {
            Section(title) {
                ForEach(albums) { AlbumRow(album: $0, onPick: onPick) }
            }
            .listRowBackground(Color.surface)
        }
    }
}

/// The albums inside a folder of albums.
private struct AlbumFolderList: View {
    let folder: PhotoAlbum
    var onPick: (PhotoAlbum) -> Void

    @State private var albums: [PhotoAlbum]?

    var body: some View {
        Group {
            if let albums {
                List {
                    ForEach(albums) { AlbumRow(album: $0, onPick: onPick) }
                        .listRowBackground(Color.surface)
                }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle(folder.title)
        .task { albums = await PhotoAlbums.contents(ofFolder: folder.id) }
    }
}

private struct AlbumRow: View {
    let album: PhotoAlbum
    var onPick: (PhotoAlbum) -> Void

    var body: some View {
        switch album.kind {
        case .album:
            Button { onPick(album) } label: { label }
                .foregroundStyle(Color.ink)
        case .folder:
            NavigationLink(value: album) { label }
        }
    }

    private var label: some View {
        HStack(spacing: 14) {
            AlbumCover(album: album)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Group {
                    switch album.kind {
                    case .album: Text("\(album.count) images")
                    case .folder: Text("\(album.count) albums", comment: "Number of albums in a folder of albums in Photos")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

private struct AlbumCover: View {
    let album: PhotoAlbum
    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    private let side: CGFloat = 56

    var body: some View {
        ZStack {
            Color.line
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: album.kind == .folder ? "folder" : "photo.on.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 10))
        .task(id: album.cover) {
            guard let cover = album.cover else { return }
            image = await PhotoAlbums.cover(cover, side: side * scale)
        }
        .accessibilityHidden(true)
    }
}

/// With limited access, Photos hides the albums. Says how to allow full access.
private struct LimitedAccessNote: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sola Slideshow can only see the photos you selected, so albums don’t show up. To choose an album, allow access to all photos.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accent)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.surface)
    }
}
