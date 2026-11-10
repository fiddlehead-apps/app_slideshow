import Foundation

/// Which images a slideshow shows, by their format.
nonisolated enum OrientationFilter: String, Codable, CaseIterable, Sendable {
    case all, portrait, landscape

    /// Square images, and images whose format isn't known, only show with `.all`.
    func allows(_ shape: ImageShape?) -> Bool {
        switch self {
        case .all: true
        case .portrait: shape == .portrait
        case .landscape: shape == .landscape
        }
    }
}

/// An image's format as it appears on screen, after rotation.
nonisolated enum ImageShape: String, Codable, Sendable {
    case portrait, landscape, square

    /// Within 2 % of each other counts as square.
    init(width: Int, height: Int) {
        if abs(width - height) * 50 <= max(width, height) {
            self = .square
        } else {
            self = height > width ? .portrait : .landscape
        }
    }
}

/// Playback options. Stored globally as the defaults for new slideshows,
/// and per slideshow so each one starts the way it was last played.
nonisolated struct ShowSettings: Codable, Equatable, Sendable {
    static let intervals = [3, 5, 10, 30, 60, 120, 300, 600, 900, 1800, 3600]
    /// Anything in here can be set as a custom time, from one second to a day.
    static let intervalRange = 1...86_400

    var interval = 5
    var shuffle = false
    var fill = false
    var fade = true
    var progress = true
    var orientation = OrientationFilter.all

    init() {}

    // Missing keys fall back to the defaults, so older saved data keeps loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShowSettings()
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? d.interval
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? d.shuffle
        fill = try c.decodeIfPresent(Bool.self, forKey: .fill) ?? d.fill
        fade = try c.decodeIfPresent(Bool.self, forKey: .fade) ?? d.fade
        progress = try c.decodeIfPresent(Bool.self, forKey: .progress) ?? d.progress
        // try?: a value from a newer version of the app falls back to showing all images.
        orientation = (try? c.decodeIfPresent(OrientationFilter.self, forKey: .orientation)) ?? d.orientation
        if !Self.intervalRange.contains(interval) { interval = d.interval }
    }

    static func intervalLabel(_ s: Int) -> String {
        s % 60 != 0 ? String(localized: "\(s) s", comment: "Seconds per image") : String(localized: "\(s / 60) min", comment: "Minutes per image")
    }
}

/// What a slideshow's record in iCloud says about it.
nonisolated struct RemoteShow: Sendable {
    var name: String
    var folder: String?
    var names: [String] = []
    var settings = ShowSettings()
    var hidden = false
    var count = 0
    var done = false
    var created: Date?
    var lastPlayed: Date?
    /// Last change of the details, see `Show.modified`.
    var modified: Date
    /// Version of the images, see `Show.content`.
    var content: Date
}

/// A slideshow in the list. A folder or an album plays straight from Files or Photos
/// (`bookmark`, `album`); with `copy` the images also live as downsized copies in
/// `Library.directory(for:)`, numbered in play order. Single photos and files, and slideshows
/// that came from iCloud, have nothing to open again, so they only exist as copies.
nonisolated struct Show: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// Name of the folder it was made from.
    var folder: String?
    /// The Photos album it plays (`localIdentifier`). Only on the device that picked it.
    var album: String?
    /// Bookmark of the folder it plays. Only on the device that picked it.
    var bookmark: Data?
    /// The folder's path, to recognise the folder when it is picked again.
    var path: String?
    /// Whether the images are kept as copies in the app.
    var copy = true
    /// Images in it: the saved ones once the copies are done, otherwise what the folder or
    /// album held the last time it was opened.
    var count: Int
    var saved = 0
    var bytes: Int64 = 0
    var done = false
    var hasThumb = false
    var created = Date()
    var updated = Date()
    var lastPlayed = Date()
    var settings: ShowSettings
    var hidden = false
    /// Original file names, index-aligned with the saved copies.
    var names: [String] = []
    /// Last change of name, settings, hidden or last played, for resolving iCloud conflicts.
    var modified = Date()
    /// When the images were last saved (picked or picked again), for the same purpose.
    var content = Date()

    init(id: String, name: String, folder: String?, count: Int, settings: ShowSettings) {
        self.id = id
        self.name = name
        self.folder = folder
        self.count = count
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        // Slideshows from before copies became optional all have one.
        copy = try c.decodeIfPresent(Bool.self, forKey: .copy) ?? true
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        saved = try c.decodeIfPresent(Int.self, forKey: .saved) ?? 0
        bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        hasThumb = try c.decodeIfPresent(Bool.self, forKey: .hasThumb) ?? false
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed) ?? Date()
        settings = try c.decodeIfPresent(ShowSettings.self, forKey: .settings) ?? ShowSettings()
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? .distantPast
        content = try c.decodeIfPresent(Date.self, forKey: .content) ?? .distantPast
    }

    /// Brings a slideshow together with its record from iCloud.
    ///
    /// Two halves, each with its own date: the details (name, settings, hidden, last
    /// played) go by `modified`, the images (how many, their file names, whether they are
    /// complete) by `content`. One device may have opened the slideshow last while another
    /// one has the newer images, so each half is taken from the side where it is newer.
    ///
    /// - Returns: `show` is the slideshow as it should be now, nil if the record has nothing
    ///   newer. `resend` says that this device has something newer and should upload it.
    static func merged(_ local: Show?, id: String, with remote: RemoteShow) -> (show: Show?, resend: Bool) {
        let keepDetails = local.map { $0.modified > remote.modified } ?? false
        let keepImages = local.map { $0.content > remote.content } ?? false
        if keepDetails && keepImages { return (nil, true) }
        var s = local ?? Show(id: id, name: remote.name, folder: nil, count: 0, settings: remote.settings)
        if !keepDetails {
            s.name = remote.name
            s.settings = remote.settings
            s.hidden = remote.hidden
            s.created = remote.created ?? s.created
            s.lastPlayed = remote.lastPlayed ?? s.lastPlayed
            s.modified = remote.modified
        }
        if !keepImages {
            // A folder that plays on this device keeps its own name.
            if s.bookmark == nil { s.folder = remote.folder }
            s.names = remote.names
            s.count = remote.count
            s.done = remote.done
            s.content = remote.content
        }
        // Only slideshows with a copy are in iCloud.
        s.copy = true
        return (s, keepDetails || keepImages)
    }

    /// Whether its folder or album can be opened again on this device.
    var hasReference: Bool { album != nil || bookmark != nil }

    /// Plays from the saved copies rather than from the folder or album. Unfinished copies
    /// of a folder or album are skipped: the source has everything.
    var playsFromCopy: Bool { copy && (done || !hasReference) }

    static func newID() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UUID().uuidString.prefix(6)).lowercased()
    }
}

nonisolated enum Format {
    /// Same rounding as the web app, with the decimal separator of the current locale.
    static func bytes(_ b: Int64) -> String {
        let d = Double(b)
        let one = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        if d >= 1e9 { return (d / 1e9).formatted(one) + " GB" }
        if d >= 1e7 { return Int((d / 1e6).rounded()).formatted() + " MB" }
        return (d / 1e6).formatted(one) + " MB"
    }
}
