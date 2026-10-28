import CloudKit
import Foundation
import Observation
import UIKit

/// The saved slideshows and their downsized image copies.
///
/// Layout in Application Support:
///   Slideshows/library.json        the list of `Show`s
///   Slideshows/<id>/000000.img     saved copies, numbered in play order
///   Slideshows/<id>/thumb.jpg      168 px square thumbnail
///   Slideshows/<id>/shapes.json    format of each saved image (portrait/landscape/square)
///   Slideshows/CloudSync.json      iCloud sync state (only once sync was turned on)
@Observable
final class Library {
    struct Saving: Equatable {
        let id: String
        var saved: Int
        let total: Int
    }

    private(set) var shows: [Show] = []
    private(set) var saving: Saving?
    /// Something the start screen should say (e.g. storage full).
    var notice: String?

    /// Defaults for new slideshows; changed whenever settings change in the player.
    var defaults: ShowSettings {
        didSet {
            if let d = try? JSONEncoder().encode(defaults) { UserDefaults.standard.set(d, forKey: Self.settingsKey) }
            guard defaults != oldValue, !applyingRemote else { return }
            defaultsModified = Date()
            cloud.changed([Self.defaultsRecord])
        }
    }

    /// Opt-in iCloud sync; does nothing until the user turns it on.
    let cloud: CloudSync

    private static let settingsKey = "settings-v1"
    private static let settingsModifiedKey = "settings-modified"
    private var defaultsModified: Date {
        get { UserDefaults.standard.object(forKey: Self.settingsModifiedKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Self.settingsModifiedKey) }
    }
    /// Set while changes from iCloud are applied, so they aren't sent back.
    private var applyingRemote = false
    /// Slideshows that got images from iCloud since the last refresh.
    private var touched: Set<String> = []
    private let root: URL
    private var job: Task<Void, Never>?
    private var jobNumber = 0
    private var jobOwner: [String: Int] = [:]
    private var thumbs: [String: (version: Date, image: UIImage)] = [:]
    /// Formats of the saved images, valid for one version of the images (`Show.content`).
    private var shapeCache: [String: ShapeFile] = [:]

    private struct ShapeFile: Codable {
        var content: Date
        var shapes: [ImageShape?]
    }

    init() {
        var support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if targetEnvironment(macCatalyst)
        // Not sandboxed on the Mac, so Application Support is shared with every other app.
        let base = support
        support.appendPathComponent(Bundle.main.bundleIdentifier ?? "eu.fiddlehead.sola.slideshow", isDirectory: true)
        // Builds before the move to eu.fiddlehead kept their slideshows under the old bundle ID.
        let legacy = base.appendingPathComponent("org.christophschneider.slideshow/Slideshows", isDirectory: true)
        let moved = support.appendingPathComponent("Slideshows", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path), !FileManager.default.fileExists(atPath: moved.path) {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: legacy, to: moved)
        }
        #endif
        root = support.appendingPathComponent("Slideshows", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cloud = CloudSync(zone: "Slideshows", folder: root)

        if let d = UserDefaults.standard.data(forKey: Self.settingsKey), let s = try? JSONDecoder().decode(ShowSettings.self, from: d) {
            defaults = s
        } else {
            defaults = ShowSettings()
        }
        if let d = try? Data(contentsOf: listURL), let list = try? JSONDecoder().decode([Show].self, from: d) {
            shows = list
        }
        cloud.attach(self)
    }

    // MARK: Paths

    private var listURL: URL { root.appendingPathComponent("library.json") }
    func directory(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func imageURL(_ id: String, _ index: Int) -> URL {
        directory(for: id).appendingPathComponent(String(format: "%06d.img", index))
    }
    private func thumbURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("thumb.jpg") }
    private func shapesURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("shapes.json") }

    private func persist() {
        guard let d = try? JSONEncoder().encode(shows) else { return }
        try? d.write(to: listURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Lists

    func list(hidden: Bool) -> [Show] {
        shows.filter { $0.hidden == hidden }.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    func usage(hidden: Bool) -> Int64 {
        shows.filter { $0.hidden == hidden }.reduce(0) { $0 + $1.bytes }
    }

    func show(_ id: String) -> Show? { shows.first { $0.id == id } }

    /// The formats of the first `count` saved images, for showing only portrait or landscape
    /// ones. Read from the files once per version of the images and kept on this device
    /// (not synced: images that come from iCloud are read here too).
    func shapes(_ id: String, count: Int) async -> [ImageShape?] {
        guard let s = show(id) else { return [] }
        let file = shapeCache[id] ?? (try? Data(contentsOf: shapesURL(id))).flatMap { try? JSONDecoder().decode(ShapeFile.self, from: $0) }
        var shapes = file?.content == s.content ? file!.shapes : []
        if shapes.count < count { shapes += Array(repeating: nil, count: count - shapes.count) }
        // Unknown ones too: the file may have been missing or still arriving last time.
        let missing = (0..<count).filter { shapes[$0] == nil }
        guard !missing.isEmpty else { return Array(shapes.prefix(count)) }
        let read = await Images.shapes(of: missing.map { imageURL(id, $0) })
        for (i, shape) in zip(missing, read) { shapes[i] = shape }
        // Images saved again meanwhile: these shapes belong to the old ones, don't keep them.
        guard show(id)?.content == s.content else { return Array(shapes.prefix(count)) }
        let updated = ShapeFile(content: s.content, shapes: shapes)
        shapeCache[id] = updated
        if let d = try? JSONEncoder().encode(updated) { try? d.write(to: shapesURL(id), options: .atomic) }
        return Array(shapes.prefix(count))
    }

    func thumb(for s: Show) -> UIImage? {
        guard s.hasThumb else { return nil }
        if let t = thumbs[s.id], t.version == s.updated { return t.image }
        guard let img = UIImage(contentsOfFile: thumbURL(s.id).path) else { return nil }
        thumbs[s.id] = (s.updated, img)
        return img
    }

    // MARK: Editing

    private func modify(_ id: String, _ change: (inout Show) -> Void) {
        guard let i = shows.firstIndex(where: { $0.id == id }) else { return }
        change(&shows[i])
    }

    /// A change to a saved slideshow's details: saved, and queued for iCloud if sync is on.
    private func edit(_ id: String, _ change: (inout Show) -> Void) {
        modify(id) {
            change(&$0)
            $0.modified = Date()
        }
        persist()
        cloud.changed([id])
    }

    func rename(_ id: String, to name: String) {
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        edit(id) { $0.name = String(v.prefix(60)) }
    }

    func setHidden(_ id: String, _ hidden: Bool) {
        edit(id) { $0.hidden = hidden }
    }

    func markPlayed(_ id: String) {
        edit(id) { $0.lastPlayed = Date() }
    }

    func setSettings(_ id: String, _ s: ShowSettings) {
        guard show(id)?.settings != s else { return }
        edit(id) { $0.settings = s }
    }

    func delete(_ id: String) async {
        if saving?.id == id {
            jobOwner[id] = nil
            job?.cancel()
            await job?.value
        }
        let images = show(id).map { max($0.saved, $0.count) } ?? 0
        shows.removeAll { $0.id == id }
        thumbs[id] = nil
        shapeCache[id] = nil
        persist()
        try? FileManager.default.removeItem(at: directory(for: id))
        cloud.deleted([id] + (0..<images).map { Self.imageRecord(id, $0) })
    }

    // MARK: Saving copies

    /// Creates the entry for a fresh pick (or reuses the one for the same
    /// folder) and starts copying the images in the background. Returns the
    /// entry so the player can adopt its settings right away.
    @discardableResult
    func save(_ items: [SourceItem], name: String, folder: String?) -> Show {
        jobNumber += 1
        let my = jobNumber
        let now = Date()
        var show: Show
        var oldImages = 0  // images of the old version, some of them may have to go from iCloud
        if let folder, let existing = shows.first(where: { $0.folder == folder }) {
            show = existing
            oldImages = max(existing.saved, existing.count)
            show.count = items.count
            show.saved = 0
            show.bytes = 0
            show.done = false
            show.hasThumb = false
            show.names = []
            show.updated = now
            show.lastPlayed = now
            show.modified = now
            show.content = now
            modify(show.id) { $0 = show }
        } else {
            show = Show(id: Show.newID(), name: name, folder: folder, count: items.count, settings: defaults)
            shows.append(show)
        }
        persist()
        jobOwner[show.id] = my
        saving = Saving(id: show.id, saved: 0, total: items.count)

        let id = show.id
        let maxEdge = Images.maxEdge
        let previous = job
        previous?.cancel()
        job = Task {
            await previous?.value
            await run(my: my, id: id, items: items, maxEdge: maxEdge, oldImages: oldImages)
        }
        return show
    }

    private func run(my: Int, id: String, items: [SourceItem], maxEdge: Int, oldImages: Int) async {
        let dir = directory(for: id)
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        thumbs[id] = nil
        if saving?.id != id { saving = Saving(id: id, saved: 0, total: items.count) }

        var n = 0, bytes: Int64 = 0, hasThumb = false, full = false
        var names: [String] = []
        for item in items {
            if Task.isCancelled || show(id) == nil { break }
            do {
                let data = try await item.data()
                let r = try await Images.shrink(data, maxEdge: maxEdge, wantThumb: !hasThumb)
                if Task.isCancelled || show(id) == nil { break }
                try await Self.write(r.data, to: imageURL(id, n))
                var newThumb = false
                if let t = r.thumb, (try? await Self.write(t, to: thumbURL(id))) != nil {
                    hasThumb = true
                    newThumb = true
                }
                n += 1
                bytes += Int64(r.data.count)
                names.append(item.name)
                saving?.saved = n
                let (saved, total, nm) = (n, bytes, names)
                modify(id) {
                    $0.saved = saved
                    $0.bytes = total
                    $0.names = nm
                    if newThumb { $0.hasThumb = true; $0.updated = Date() }
                }
                if newThumb || n % 5 == 0 { persist() }
            } catch {
                if Self.isOutOfSpace(error) { full = true; break }
            }
        }

        let finished = !Task.isCancelled && !full
        if jobOwner[id] == my {
            jobOwner[id] = nil
            let (saved, total, nm) = (n, bytes, names)
            modify(id) {
                $0.saved = saved
                $0.bytes = total
                $0.names = nm
                $0.done = finished
                $0.count = finished ? saved : items.count
            }
            persist()
            // Uploaded once the copies are done, not image by image while they're made.
            cloud.changed([id] + (0..<n).map { Self.imageRecord(id, $0) })
            if oldImages > n { cloud.deleted((n..<oldImages).map { Self.imageRecord(id, $0) }) }
        }
        if saving?.id == id { saving = nil }
        if full, let s = show(id) {
            notice = String(localized: "Storage on this device is full. \(n) of \(items.count) images from “\(s.name)” were saved.")
        }
    }

    @concurrent private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
    }

    private nonisolated static func isOutOfSpace(_ error: Error) -> Bool {
        let e = error as NSError
        return (e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError)
            || (e.domain == NSPOSIXErrorDomain && e.code == Int(ENOSPC))
    }
}

// MARK: - iCloud

/// Records: "Show" per slideshow (named by its ID), "Image" per saved copy (named
/// "<show>-<index>", the file as asset) and "Defaults" for the settings of new slideshows.
/// Thumbnails, sizes and how many images are saved are worked out on each device.
extension Library: CloudSyncStore {
    static let defaultsRecord = "defaults"

    static func imageRecord(_ show: String, _ index: Int) -> String { "\(show)-\(index)" }

    private enum RecordName {
        case defaults, show(String), image(String, Int)

        init?(_ name: String) {
            if name == Library.defaultsRecord { self = .defaults; return }
            let parts = name.split(separator: "-")
            if parts.count == 1 { self = .show(name); return }
            guard parts.count == 2, let i = Int(parts[1]) else { return nil }
            self = .image(String(parts[0]), i)
        }
    }

    func allRecordNames() -> [String] {
        [Self.defaultsRecord] + shows.flatMap { s in [s.id] + (0..<s.saved).map { Self.imageRecord(s.id, $0) } }
    }

    func record(for id: CKRecord.ID, existing: CKRecord?) -> CKRecord? {
        switch RecordName(id.recordName) {
        case .defaults:
            let r = existing ?? CKRecord(recordType: "Defaults", recordID: id)
            r.encryptedValues["settings"] = try? JSONEncoder().encode(defaults)
            r["modified"] = defaultsModified
            return r
        case .show(let sid):
            guard let s = show(sid) else { return nil }
            let r = existing ?? CKRecord(recordType: "Show", recordID: id)
            let e = r.encryptedValues
            e["name"] = s.name
            e["folder"] = s.folder
            e["names"] = try? JSONEncoder().encode(s.names)
            e["settings"] = try? JSONEncoder().encode(s.settings)
            e["hidden"] = s.hidden
            r["count"] = s.count
            r["done"] = s.done
            r["created"] = s.created
            r["lastPlayed"] = s.lastPlayed
            r["modified"] = s.modified
            r["content"] = s.content
            return r
        case .image(let sid, let index):
            let url = imageURL(sid, index)
            guard let s = show(sid), index < s.saved, FileManager.default.fileExists(atPath: url.path) else { return nil }
            let r = existing ?? CKRecord(recordType: "Image", recordID: id)
            r["show"] = sid
            r["index"] = index
            r["content"] = s.content
            r["file"] = CKAsset(fileURL: url)
            return r
        case nil:
            return nil
        }
    }

    func merge(_ r: CKRecord) -> Bool {
        switch RecordName(r.recordID.recordName) {
        case .defaults:
            let remote = r["modified"] as? Date ?? .distantPast
            if defaultsModified > remote { return true }
            if let d = r.encryptedValues["settings"] as? Data, let s = try? JSONDecoder().decode(ShowSettings.self, from: d) {
                applyingRemote = true
                defaults = s
                applyingRemote = false
                defaultsModified = remote
            }
            return false

        case .show(let sid):
            let remote = r["modified"] as? Date ?? .distantPast
            if let local = show(sid), local.modified > remote { return true }
            let e = r.encryptedValues
            guard let name = e["name"] as? String else { return false }
            let settings = (e["settings"] as? Data).flatMap { try? JSONDecoder().decode(ShowSettings.self, from: $0) } ?? defaults
            var s = show(sid) ?? Show(id: sid, name: name, folder: nil, count: 0, settings: settings)
            s.name = name
            s.folder = e["folder"] as? String
            s.names = (e["names"] as? Data).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            s.settings = settings
            s.hidden = e["hidden"] as? Bool ?? false
            s.count = r["count"] as? Int ?? 0
            s.done = r["done"] as? Bool ?? false
            s.created = r["created"] as? Date ?? s.created
            s.lastPlayed = r["lastPlayed"] as? Date ?? s.lastPlayed
            s.modified = remote
            s.content = r["content"] as? Date ?? s.content
            if let i = shows.firstIndex(where: { $0.id == sid }) { shows[i] = s } else { shows.append(s) }
            touched.insert(sid)
            return false

        case .image(let sid, let index):
            // A slideshow that is being saved here right now uploads its own images when done.
            guard saving?.id != sid, let file = (r["file"] as? CKAsset)?.fileURL else { return false }
            if let local = show(sid), local.content > r["content"] as? Date ?? .distantPast { return true }
            let fm = FileManager.default
            let url = imageURL(sid, index)
            try? fm.createDirectory(at: directory(for: sid), withIntermediateDirectories: true)
            try? fm.removeItem(at: url)
            // A clone on APFS, so no bytes are copied. The asset file is only valid during this call.
            if (try? fm.copyItem(at: file, to: url)) != nil {
                try? (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            }
            if index == 0 { removeThumb(sid) }
            touched.insert(sid)
            return false

        case nil:
            return false
        }
    }

    func remove(_ id: CKRecord.ID) {
        switch RecordName(id.recordName) {
        case .show(let sid):
            if saving?.id == sid {
                jobOwner[sid] = nil
                job?.cancel()
            }
            shows.removeAll { $0.id == sid }
            thumbs[sid] = nil
            shapeCache[sid] = nil
            try? FileManager.default.removeItem(at: directory(for: sid))
        case .image(let sid, let index):
            try? FileManager.default.removeItem(at: imageURL(sid, index))
            touched.insert(sid)
        case .defaults, nil:
            break
        }
    }

    func didApplyChanges() {
        for sid in touched where saving?.id != sid { refreshFromFiles(sid) }
        touched = []
        persist()
    }

    /// Counts the images that are here (from the first one on, as the player plays them)
    /// and makes the thumbnail from the first image.
    private func refreshFromFiles(_ sid: String) {
        guard let s = show(sid) else { return }
        let fm = FileManager.default
        var n = 0, bytes: Int64 = 0
        while n < s.count, let size = (try? fm.attributesOfItem(atPath: imageURL(sid, n).path))?[.size] as? NSNumber {
            n += 1
            bytes += size.int64Value
        }
        modify(sid) {
            $0.saved = n
            $0.bytes = bytes
        }
        guard n > 0, !s.hasThumb || !fm.fileExists(atPath: thumbURL(sid).path) else { return }
        let first = imageURL(sid, 0), thumb = thumbURL(sid)
        Task {
            guard let data = try? Data(contentsOf: first),
                  let t = try? await Images.shrink(data, maxEdge: 400, wantThumb: true).thumb,
                  (try? await Self.write(t, to: thumb)) != nil else { return }
            thumbs[sid] = nil
            modify(sid) {
                $0.hasThumb = true
                $0.updated = Date()
            }
            persist()
        }
    }

    private func removeThumb(_ sid: String) {
        try? FileManager.default.removeItem(at: thumbURL(sid))
        thumbs[sid] = nil
        modify(sid) { $0.hasThumb = false }
    }

    /// The slideshow is complete in iCloud but not all images are here yet.
    func isDownloading(_ s: Show) -> Bool {
        cloud.isOn && s.done && s.saved < s.count && saving?.id != s.id
    }
}
