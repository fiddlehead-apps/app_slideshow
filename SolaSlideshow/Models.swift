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

/// A saved slideshow. The images themselves live as downsized copies in
/// `Library.directory(for:)`, numbered in play order.
nonisolated struct Show: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// Folder name it was made from; picking the same folder again replaces it.
    var folder: String?
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
