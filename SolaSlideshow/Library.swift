import CloudKit
import Foundation
import Observation
import UIKit

/// The slideshows in the list, and the downsized image copies of those that keep one.
///
/// A folder or an album plays straight from Files or Photos, and a copy is the user's
/// choice. Single photos and files can't be opened again later, so they are always copied.
///
/// Layout in Application Support (left out of device and iCloud backups):
///   Slideshows/library.json        the list of `Show`s
///   Slideshows/library.backup.json the list as it was at the last start
///   Slideshows/<id>/000000.img     saved copies, numbered in play order
///   Slideshows/<id>/thumb.jpg      168 px square thumbnail
///   Slideshows/<id>/shapes.json    format of each saved image (portrait/landscape/square)
///   Slideshows/CloudSync.json      iCloud sync state (only once sync was turned on)
@Observable
final class Library {
    /// One library for the whole app: every window shows and changes the same list.
    static let shared = Library()

    struct Saving: Equatable {
        let id: String
        var saved: Int
        let total: Int
    }

    /// Where the images of a pick come from.
    enum Origin {
        /// Single photos or files.
        case picked
        case folder(URL)
        /// A Photos album, by its `localIdentifier`.
        case album(String)
    }

    enum SourceError: Error {
        /// The app may not read the Photos library.
        case noAccess
        /// The folder or album doesn't exist anymore or can't be reached right now.
        case gone
    }

    private(set) var shows: [Show] = []
    /// The slideshow whose copies are being made right now.
    private(set) var saving: Saving?
    /// Which slideshow gets its copies made, and which ones wait for that.
    private(set) var queue = CopyQueue<[SourceItem]>()
    /// Slideshows that get their copies once the one before them is done, in this order.
    var queued: [String] { queue.waiting }
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
    /// How long one image may take to arrive before the copy goes on without it.
    private static let readTimeout = Duration.seconds(180)
    private var defaultsModified: Date {
        get { UserDefaults.standard.object(forKey: Self.settingsModifiedKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Self.settingsModifiedKey) }
    }
    /// Set while changes from iCloud are applied, so they aren't sent back.
    private var applyingRemote = false
    /// Slideshows that got images from iCloud since the last refresh.
    private var touched: Set<String> = []
    private let root: URL
    /// The task that makes the copies of `queue.running`.
    @ObservationIgnored private var copying: Task<Void, Never>?
    /// How many image records a slideshow had in iCloud before its copies were made again.
    @ObservationIgnored private var formerImages: [String: Int] = [:]
    @ObservationIgnored private var background = UIBackgroundTaskIdentifier.invalid
    /// The list file exists but couldn't be read at the start: it must not be written over.
    @ObservationIgnored private var listBlocked = false
    private var thumbs: [String: (version: Date, image: UIImage)] = [:]
    /// Formats of the saved images, valid for one version of the images (`Show.content`).
    private var shapeCache: [String: ShapeFile] = [:]

    private struct ShapeFile: Codable {
        var content: Date
        var shapes: [ImageShape?]
    }

    private init() {
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
        // The copies are the user's images. They stay out of backups, so "nothing is uploaded"
        // also holds for iCloud Backup; iCloud sync is the way to get them onto another device.
        var noBackup = URLResourceValues()
        noBackup.isExcludedFromBackup = true
        var folder = root
        try? folder.setResourceValues(noBackup)
        cloud = CloudSync(zone: "Slideshows", folder: root)

        if let d = UserDefaults.standard.data(forKey: Self.settingsKey), let s = try? JSONDecoder().decode(ShowSettings.self, from: d) {
            defaults = s
        } else {
            defaults = ShowSettings()
        }
        loadList()
        cloud.attach(self)
        queueUnsent()
        Task { await resumeCopies() }
    }

    // MARK: Paths

    private var listURL: URL { root.appendingPathComponent("library.json") }
    private var backupURL: URL { root.appendingPathComponent("library.backup.json") }
    private var damagedURL: URL { root.appendingPathComponent("library.damaged.json") }
    func directory(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func imageURL(_ id: String, _ index: Int) -> URL {
        directory(for: id).appendingPathComponent(String(format: "%06d.img", index))
    }
    private func thumbURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("thumb.jpg") }
    private func shapesURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("shapes.json") }

    // MARK: The list file

    private enum Stored {
        case shows([Show])
        case missing
        case unreadable
    }

    /// One entry that can't be decoded doesn't take the rest of the list with it.
    private static func read(_ url: URL) -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let d = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Lossy<Show>].self, from: d) else { return .unreadable }
        return .shows(list.compactMap(\.value))
    }

    private func loadList() {
        let fm = FileManager.default
        switch Self.read(listURL) {
        case .shows(let list):
            shows = list
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: listURL, to: backupURL)
            removeLeftovers()
        case .missing:
            break
        case .unreadable:
            if case .shows(let list) = Self.read(backupURL) {
                // Damaged: carry on with the list from the start before.
                shows = list
                setListAside()
            } else {
                // It may only be locked (the device wasn't unlocked since it restarted).
                listBlocked = true
            }
        }
    }

    private func setListAside() {
        try? FileManager.default.removeItem(at: damagedURL)
        try? FileManager.default.moveItem(at: listURL, to: damagedURL)
    }

    private func persist() {
        if listBlocked {
            switch Self.read(listURL) {
            case .shows(let list):
                // Readable after all: keep what is in it next to what was added meanwhile.
                let known = Set(shows.map(\.id))
                shows += list.filter { !known.contains($0.id) }
            case .missing:
                break
            case .unreadable:
                guard UIApplication.shared.isProtectedDataAvailable else { return }
                setListAside()
            }
            listBlocked = false
        }
        guard let d = try? JSONEncoder().encode(shows) else { return }
        try? d.write(to: listURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Removes folders of slideshows that aren't in the list (e.g. images that came from
    /// iCloud for a slideshow deleted here). Only ones that have been lying around for a week.
    private func removeLeftovers() {
        let fm = FileManager.default
        let known = Set(shows.map(\.id))
        let limit = Date().addingTimeInterval(-7 * 86_400)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let found = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))) ?? []
        for dir in found where !known.contains(dir.lastPathComponent) {
            guard let v = try? dir.resourceValues(forKeys: keys), v.isDirectory == true,
                  let changed = v.contentModificationDate, changed < limit else { continue }
            try? fm.removeItem(at: dir)
        }
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

    /// A change to a slideshow's details: saved, and queued for iCloud if it syncs (only
    /// slideshows with a copy do, a folder or album can't be opened on another device).
    private func edit(_ id: String, _ change: (inout Show) -> Void) {
        modify(id) {
            change(&$0)
            $0.modified = Date()
        }
        persist()
        if show(id)?.copy == true { cloud.changed([id]) }
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
        await stopJob(id)
        guard let s = show(id) else { return }
        shows.removeAll { $0.id == id }
        thumbs[id] = nil
        shapeCache[id] = nil
        formerImages[id] = nil
        persist()
        try? FileManager.default.removeItem(at: directory(for: id))
        if cloud.knows(id) { cloud.deleted(Self.records(id, images: max(s.saved, s.count))) }
    }

    // MARK: Folders and albums

    /// What is in a slideshow's folder or album right now. `ask` lets the system ask for
    /// access to Photos; without it a slideshow whose album needs asking counts as no access.
    func source(of id: String, ask: Bool) async -> Result<[SourceItem], SourceError> {
        guard let s = show(id) else { return .failure(.gone) }
        if let album = s.album {
            guard await PhotoAlbums.access(ask: ask) != .denied else { return .failure(.noAccess) }
            guard let found = await PhotoAlbums.items(inAlbum: album) else { return .failure(.gone) }
            return .success(found)
        }
        guard let bookmark = s.bookmark, let opened = await Bookmark.open(bookmark) else { return .failure(.gone) }
        if let fresh = opened.fresh {
            modify(id) {
                $0.bookmark = fresh
                $0.path = Bookmark.path(opened.url)
            }
            persist()
        }
        return .success(await Images.scan(folder: opened.url, access: opened.access))
    }

    /// What to tell the user when a slideshow's folder or album couldn't be opened.
    func explain(_ error: SourceError, for s: Show) -> String {
        switch error {
        case .noAccess:
            PhotoAlbums.noAccessText
        case .gone where s.album != nil:
            String(localized: "The album of “\(s.name)” can’t be found in Photos anymore. Choose the album again.")
        case .gone:
            String(localized: "The folder of “\(s.name)” can’t be opened right now. If it was moved or deleted, choose the folder again.")
        }
    }

    /// Puts a fresh pick into the list, or brings the slideshow of the same folder or album
    /// up to date, and returns it so the player can adopt its settings right away. Where the
    /// slideshow keeps a copy, the copies are made in the background.
    @discardableResult
    func add(_ items: [SourceItem], name: String, origin: Origin) -> Show {
        let now = Date()
        var show: Show
        if let existing = Self.match(origin, in: shows) {
            show = existing
            if !show.copy { show.count = items.count }
            show.lastPlayed = now
            show.modified = now
        } else {
            show = Show(id: Show.newID(), name: name, folder: nil, count: items.count, settings: defaults)
            show.copy = false
            shows.append(show)
        }
        switch origin {
        case .picked:
            show.copy = true
        case .folder(let url):
            show.folder = url.lastPathComponent
            show.path = Bookmark.path(url)
            show.bookmark = Bookmark.make(url) ?? show.bookmark
            // Without a bookmark the folder can't be opened again, so it needs the copy.
            if show.bookmark == nil { show.copy = true }
        case .album(let id):
            show.album = id
        }
        modify(show.id) { $0 = show }
        persist()
        if show.copy {
            startCopy(show.id, items)
        } else {
            refreshThumb(show.id, items)
        }
        return show
    }

    /// The slideshow a pick belongs to, if its folder or album is in the list already.
    static func match(_ origin: Origin, in shows: [Show]) -> Show? {
        // A hidden slideshow isn't taken over: the pick would vanish into the hidden list.
        let visible = shows.filter { !$0.hidden }
        switch origin {
        case .picked:
            return nil
        case .album(let id):
            return visible.first { $0.album == id }
        case .folder(let url):
            let path = Bookmark.path(url), name = url.lastPathComponent
            // The same folder, not just one with the same name. Slideshows from before folders
            // were remembered, or from another device, only have the name to go by.
            return visible.first { $0.path == path }
                ?? visible.first { $0.path == nil && $0.album == nil && $0.folder == name }
        }
    }

    /// A folder's or album's slideshow was opened from the list: notes what is in it now.
    func opened(_ id: String, _ items: [SourceItem]) {
        guard let s = show(id) else { return }
        markPlayed(id)
        guard !s.copy else { return }
        modify(id) { $0.count = items.count }
        persist()
        if !s.hasThumb || s.count != items.count { refreshThumb(id, items) }
    }

    /// The picture in the list for a slideshow without a copy: its first image that opens.
    private func refreshThumb(_ id: String, _ items: [SourceItem]) {
        let dir = directory(for: id), url = thumbURL(id)
        Task {
            for item in items.prefix(8) {
                guard let data = try? await item.data(timeout: .seconds(60)),
                      let t = try? await Images.shrink(data, maxEdge: 400, wantThumb: true).thumb else { continue }
                // A copy that was turned on meanwhile makes its own.
                guard show(id)?.copy == false else { return }
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard (try? await Self.write(t, to: url)) != nil else { return }
                thumbs[id] = nil
                modify(id) {
                    $0.hasThumb = true
                    $0.updated = Date()
                }
                persist()
                return
            }
        }
    }

    // MARK: Copies

    /// Whether copies are being made or are waiting to be.
    var isBusy: Bool { saving != nil || !queue.isEmpty }

    /// Turns the saved copy of a folder's or album's slideshow on or off. Returns what went
    /// wrong if the folder or album couldn't be opened to copy it.
    @discardableResult
    func setCopy(_ id: String, _ on: Bool) async -> SourceError? {
        guard let s = show(id), s.hasReference, s.copy != on else { return nil }
        guard on else {
            await stopJob(id)
            dropCopies(id)
            persist()
            return nil
        }
        // On right away, so the switch doesn't hang while a big folder is read.
        modify(id) {
            $0.copy = true
            $0.done = false
        }
        let result = await source(of: id, ask: true)
        guard show(id)?.copy == true else { return nil }
        if case .success(let found) = result, !found.isEmpty {
            persist()
            startCopy(id, found)
            return nil
        }
        modify(id) { $0.copy = false }
        if case .failure(let error) = result { return error }
        return .gone
    }

    /// What deleting a slideshow's copy does, for the question that comes before it.
    func deletingCopyMeans(_ s: Show) -> String {
        var parts: [String] = []
        if !s.hasReference {
            parts.append(String(localized: "This slideshow only exists as its copy, so deleting the copy deletes the whole slideshow."))
        } else {
            if s.bytes > 0 {
                parts.append(String(localized: "This frees \(Format.bytes(s.bytes)) on this device.", comment: "The placeholder is a size like “86 MB”"))
            }
            parts.append(s.album != nil
                ? String(localized: "The slideshow stays in the list and plays from its album in Photos.")
                : String(localized: "The slideshow stays in the list and plays from its folder in Files."))
        }
        if cloud.knows(s.id) {
            parts.append(String(localized: "It is also removed from iCloud and from your other devices."))
        }
        return parts.joined(separator: " ")
    }

    /// Deletes a slideshow's saved copy. A slideshow that only exists as its copy (single
    /// photos and files, or one that came from iCloud) is deleted with it.
    func deleteCopy(_ id: String) async {
        guard let s = show(id) else { return }
        if s.hasReference {
            await setCopy(id, false)
        } else {
            await delete(id)
        }
    }

    /// Removes the saved images of a slideshow that goes on playing from its folder or album.
    private func dropCopies(_ id: String) {
        guard let s = show(id) else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory(for: id), includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != thumbURL(id).lastPathComponent {
            try? fm.removeItem(at: file)
        }
        shapeCache[id] = nil
        formerImages[id] = nil
        modify(id) {
            $0.copy = false
            $0.saved = 0
            $0.bytes = 0
            $0.done = false
            $0.names = []
        }
        // A slideshow without a copy isn't in iCloud.
        if cloud.knows(id) { cloud.deleted(Self.records(id, images: max(s.saved, s.count))) }
    }

    /// Queues a slideshow for copying. Copies are made one slideshow after the other; a pick
    /// made while another one is still being saved waits for its turn instead of stopping it.
    private func startCopy(_ id: String, _ items: [SourceItem]) {
        // Images picked again: the copy that is being made is of the old ones.
        if queue.add(id, items) { copying?.cancel() }
        next()
    }

    private func next() {
        guard let job = queue.start() else {
            if queue.isEmpty { keepRunningInBackground(false) }
            return
        }
        keepRunningInBackground(true)
        copying = Task {
            await run(job.id, job.job)
            copying = nil
            queue.finished()
            next()
        }
    }

    /// Takes a slideshow out of the queue and waits until its copying has stopped.
    private func stopJob(_ id: String) async {
        if queue.remove(id), let task = copying {
            task.cancel()
            await task.value
        }
    }

    /// Asks iOS for the extra time it grants after the app is left, so short copies still finish.
    private func keepRunningInBackground(_ on: Bool) {
        if on, background == .invalid {
            background = UIApplication.shared.beginBackgroundTask(withName: "Saving copies") { [weak self] in
                // Called on the main thread when the time is up.
                MainActor.assumeIsolated { self?.keepRunningInBackground(false) }
            }
        } else if !on, background != .invalid {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
    }

    /// Copies that were cut short when the app was closed start again, as long as their
    /// folder or album opens without asking the user for anything.
    private func resumeCopies() async {
        for s in shows where s.copy && !s.done && s.hasReference {
            guard case .success(let found) = await source(of: s.id, ask: false), !found.isEmpty,
                  let now = show(s.id), now.copy, !now.done,
                  queue.running != s.id, !queued.contains(s.id) else { continue }
            startCopy(s.id, found)
        }
    }

    /// Copies that never got to iCloud because the app was closed while they were made.
    private func queueUnsent() {
        guard cloud.isOn else { return }
        for s in shows where s.copy && s.saved > 0 && (s.done || !s.hasReference) && !cloud.knows(s.id) {
            cloud.changed(Self.records(s.id, images: s.saved))
        }
    }

    private func run(_ id: String, _ items: [SourceItem]) async {
        guard let before = show(id), before.copy else { return }
        let dir = directory(for: id)
        let fm = FileManager.default
        if cloud.knows(id) {
            formerImages[id] = max(formerImages[id] ?? 0, before.saved, before.count)
        }
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        thumbs[id] = nil
        shapeCache[id] = nil
        let started = Date()
        modify(id) {
            $0.count = items.count
            $0.saved = 0
            $0.bytes = 0
            $0.done = false
            $0.hasThumb = false
            $0.names = []
            $0.updated = started
            $0.content = started
        }
        persist()
        saving = Saving(id: id, saved: 0, total: items.count)
        defer { if saving?.id == id { saving = nil } }

        var n = 0, bytes: Int64 = 0, hasThumb = false, full = false, failed = 0
        var names: [String] = []
        var written = Date()
        for item in items {
            if Task.isCancelled || show(id)?.copy != true { break }
            do {
                let data = try await item.data(timeout: Self.readTimeout)
                let r = try await Images.shrink(data, maxEdge: Images.copyEdge, wantThumb: !hasThumb)
                if Task.isCancelled || show(id)?.copy != true { break }
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
                let (saved, total) = (n, bytes)
                modify(id) {
                    $0.saved = saved
                    $0.bytes = total
                    if newThumb { $0.hasThumb = true; $0.updated = Date() }
                }
                // Not after every image: the whole list is written each time.
                if newThumb || Date().timeIntervalSince(written) > 3 {
                    persist()
                    written = Date()
                }
            } catch {
                if Task.isCancelled { break }
                if Self.isOutOfSpace(error) { full = true; break }
                failed += 1
            }
        }

        // Stopped on purpose (picked again, copy turned off, deleted): whoever did it tidies up.
        guard !Task.isCancelled, let s = show(id), s.copy else { return }

        if s.hasReference, n == 0 || full {
            // No copy came of it. The slideshow still plays from its folder or album.
            dropCopies(id)
            persist()
            notice = full
                ? String(localized: "Storage on this device is full, so “\(s.name)” plays without a copy.")
                : String(localized: "No copy of “\(s.name)” could be made: none of its images could be read.")
            return
        }
        if n == 0 {
            // Nothing to show at all.
            shows.removeAll { $0.id == id }
            formerImages[id] = nil
            persist()
            try? fm.removeItem(at: dir)
            notice = full
                ? String(localized: "Storage on this device is full. None of the images from “\(s.name)” could be saved.")
                : String(localized: "None of the images from “\(s.name)” could be read, so there is no slideshow.")
            return
        }

        // File names only where there are any (photos from the library have none).
        let kept = names.contains { !$0.isEmpty } ? names : []
        let (saved, total, complete) = (n, bytes, !full)
        modify(id) {
            $0.saved = saved
            $0.bytes = total
            $0.names = kept
            $0.done = complete
            $0.count = complete ? saved : items.count
        }
        persist()
        // Uploaded once the copies are done, not image by image while they're made.
        cloud.changed(Self.records(id, images: saved))
        let former = formerImages.removeValue(forKey: id) ?? 0
        if former > saved { cloud.deleted((saved..<former).map { Self.imageRecord(id, $0) }) }
        if full {
            notice = String(localized: "Storage on this device is full. \(n) of \(items.count) images from “\(s.name)” were saved.")
        } else if failed > 0 {
            notice = String(localized: "\(failed) of \(items.count) images from “\(s.name)” couldn’t be read and were left out of the copy.")
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

/// Decodes to nil instead of failing, for reading a list entry by entry.
nonisolated private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - iCloud

/// Records: "Show" per slideshow (named by its ID), "Image" per saved copy (named
/// "<show>-<index>", the file as asset) and "Defaults" for the settings of new slideshows.
/// Thumbnails, sizes and how many images are saved are worked out on each device.
///
/// Only slideshows with a copy sync: the copy is what another device can play. A folder or
/// album is only known to the device that picked it, so those fields stay local, and a
/// slideshow without a copy isn't in iCloud at all.
extension Library: CloudSyncStore {
    static let defaultsRecord = "defaults"

    static func imageRecord(_ show: String, _ index: Int) -> String { "\(show)-\(index)" }

    /// The record of a slideshow and of its first `images` images.
    static func records(_ show: String, images: Int) -> [String] {
        [show] + (0..<images).map { imageRecord(show, $0) }
    }

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
        [Self.defaultsRecord] + shows.filter(\.copy).flatMap { Self.records($0.id, images: $0.saved) }
    }

    func record(for id: CKRecord.ID, existing: CKRecord?) -> CKRecord? {
        switch RecordName(id.recordName) {
        case .defaults:
            let r = existing ?? CKRecord(recordType: "Defaults", recordID: id)
            r.encryptedValues["settings"] = try? JSONEncoder().encode(defaults)
            r["modified"] = defaultsModified
            return r
        case .show(let sid):
            guard let s = show(sid), s.copy else { return nil }
            let r = existing ?? CKRecord(recordType: "Show", recordID: id)
            let e = r.encryptedValues
            e["name"] = s.name
            e["folder"] = s.folder
            // A record holds at most 1 MB. The file names of a very big folder don't fit, so
            // they stay behind and the other devices show the images without names.
            let names = try? JSONEncoder().encode(s.names)
            e["names"] = (names?.count ?? 0) <= 400_000 ? names : nil
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
            guard let s = show(sid), s.copy, index < s.saved, FileManager.default.fileExists(atPath: url.path) else { return nil }
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
            let e = r.encryptedValues
            guard let name = e["name"] as? String else { return false }
            let remote = RemoteShow(
                name: name,
                folder: e["folder"] as? String,
                names: (e["names"] as? Data).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [],
                settings: (e["settings"] as? Data).flatMap { try? JSONDecoder().decode(ShowSettings.self, from: $0) } ?? defaults,
                hidden: e["hidden"] as? Bool ?? false,
                count: r["count"] as? Int ?? 0,
                done: r["done"] as? Bool ?? false,
                created: r["created"] as? Date,
                lastPlayed: r["lastPlayed"] as? Date,
                modified: r["modified"] as? Date ?? .distantPast,
                content: r["content"] as? Date ?? .distantPast)
            let merged = Show.merged(show(sid), id: sid, with: remote)
            if let s = merged.show {
                if let i = shows.firstIndex(where: { $0.id == sid }) { shows[i] = s } else { shows.append(s) }
                touched.insert(sid)
            }
            // Whatever is newer here goes back up.
            return merged.resend

        case .image(let sid, let index):
            // A slideshow that is being saved here right now uploads its own images when done.
            guard saving?.id != sid else { return false }
            if let local = show(sid), local.content > r["content"] as? Date ?? .distantPast { return true }
            // No file: the record came back from a refused upload, which carries no assets.
            // `CloudSync` fetches it again in full.
            guard let file = (r["file"] as? CKAsset)?.fileURL else { return false }
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
            if queue.remove(sid) { copying?.cancel() }
            if show(sid)?.hasReference == true {
                // Gone from iCloud (deleted, or its copy was turned off, on another device). Its
                // folder or album is here, so it stays and plays from there without the copy.
                dropCopies(sid)
                break
            }
            shows.removeAll { $0.id == sid }
            thumbs[sid] = nil
            shapeCache[sid] = nil
            formerImages[sid] = nil
            try? FileManager.default.removeItem(at: directory(for: sid))
        case .image(let sid, let index):
            try? FileManager.default.removeItem(at: imageURL(sid, index))
            touched.insert(sid)
        case .defaults, nil:
            break
        }
    }

    func didApplyChanges() {
        for sid in touched where saving?.id != sid && !queued.contains(sid) { refreshFromFiles(sid) }
        touched = []
        persist()
    }

    /// Counts the images that are here (from the first one on, as the player plays them)
    /// and makes the thumbnail from the first image.
    private func refreshFromFiles(_ sid: String) {
        guard let s = show(sid), s.copy else { return }
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
        cloud.isOn && s.copy && s.done && s.saved < s.count && saving?.id != s.id && !queued.contains(s.id)
    }
}
