import Foundation
import Observation
import UIKit

/// The saved slideshows and their downsized image copies.
///
/// Layout in Application Support:
///   Slideshows/library.json        the list of `Show`s
///   Slideshows/<id>/000000.img     saved copies, numbered in play order
///   Slideshows/<id>/thumb.jpg      168 px square thumbnail
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
        didSet { if let d = try? JSONEncoder().encode(defaults) { UserDefaults.standard.set(d, forKey: Self.settingsKey) } }
    }

    private static let settingsKey = "settings-v1"
    private let root: URL
    private var job: Task<Void, Never>?
    private var jobNumber = 0
    private var jobOwner: [String: Int] = [:]
    private var thumbs: [String: (version: Date, image: UIImage)] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Slideshows", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if let d = UserDefaults.standard.data(forKey: Self.settingsKey), let s = try? JSONDecoder().decode(ShowSettings.self, from: d) {
            defaults = s
        } else {
            defaults = ShowSettings()
        }
        if let d = try? Data(contentsOf: listURL), let list = try? JSONDecoder().decode([Show].self, from: d) {
            shows = list
        }
    }

    // MARK: Paths

    private var listURL: URL { root.appendingPathComponent("library.json") }
    func directory(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func imageURL(_ id: String, _ index: Int) -> URL {
        directory(for: id).appendingPathComponent(String(format: "%06d.img", index))
    }
    private func thumbURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("thumb.jpg") }

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

    func rename(_ id: String, to name: String) {
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        modify(id) { $0.name = String(v.prefix(60)) }
        persist()
    }

    func setHidden(_ id: String, _ hidden: Bool) {
        modify(id) { $0.hidden = hidden }
        persist()
    }

    func markPlayed(_ id: String) {
        modify(id) { $0.lastPlayed = Date() }
        persist()
    }

    func setSettings(_ id: String, _ s: ShowSettings) {
        modify(id) { $0.settings = s }
        persist()
    }

    func delete(_ id: String) async {
        if saving?.id == id {
            jobOwner[id] = nil
            job?.cancel()
            await job?.value
        }
        shows.removeAll { $0.id == id }
        thumbs[id] = nil
        persist()
        try? FileManager.default.removeItem(at: directory(for: id))
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
        if let folder, let existing = shows.first(where: { $0.folder == folder }) {
            show = existing
            show.count = items.count
            show.saved = 0
            show.bytes = 0
            show.done = false
            show.hasThumb = false
            show.names = []
            show.updated = now
            show.lastPlayed = now
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
            await run(my: my, id: id, items: items, maxEdge: maxEdge)
        }
        return show
    }

    private func run(my: Int, id: String, items: [SourceItem], maxEdge: Int) async {
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
