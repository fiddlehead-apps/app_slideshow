import Observation
import SwiftUI
import UIKit

/// Plays one slideshow: either images that were just picked, or the saved
/// copies of a slideshow from the library.
@Observable
final class Player {
    enum Source {
        case items([SourceItem])
        case stored(id: String, count: Int)

        var count: Int {
            switch self {
            case .items(let a): a.count
            case .stored(_, let n): n
            }
        }
    }

    struct Slide: Identifiable, Equatable {
        let id = UUID()
        let index: Int
        let image: UIImage
    }

    private(set) var isOpen = false
    private(set) var label = ""
    private(set) var showID: String?
    private(set) var order: [Int] = []
    private(set) var pos = 0
    private(set) var current: Slide?
    private(set) var settings = ShowSettings()
    private(set) var playing = true
    private(set) var loading = false
    private(set) var uiVisible = true
    /// Nothing in the slideshow has the chosen format (portrait or landscape only).
    private(set) var noMatches = false
    var sheetOpen = false {
        didSet {
            guard sheetOpen != oldValue else { return }
            updateClock()
            showUI()
        }
    }

    /// Called when nothing in the slideshow could be opened.
    var onFailure: ((String) -> Void)?

    private let library: Library
    private var source: Source?
    private var dir = 1
    private var token = 0
    private var loads: [Int: Task<UIImage?, Never>] = [:]
    private var bad = Set<Int>()
    /// Just-picked images found to have the wrong format once loaded (their format isn't known before).
    private var skipped = Set<Int>()
    /// Formats of a saved slideshow's images, loaded when a format is chosen.
    private var shapes: [ImageShape?]?
    // Time shown so far for the current image: `accumulated` plus the time since `runningSince`.
    private var accumulated: TimeInterval = 0
    private(set) var runningSince: Date?
    private var advanceTask: Task<Void, Never>?
    private var uiTask: Task<Void, Never>?

    init(library: Library) {
        self.library = library
    }

    // MARK: Opening and closing

    func start(_ source: Source, label: String, showID: String?, settings: ShowSettings) {
        token += 1
        loads.values.forEach { $0.cancel() }
        loads = [:]
        bad = []
        skipped = []
        shapes = nil
        noMatches = false
        self.source = source
        self.label = label
        self.showID = showID
        self.settings = settings
        current = nil
        sheetOpen = false
        playing = true
        accumulated = 0
        runningSince = nil
        isOpen = true
        UIApplication.shared.isIdleTimerDisabled = true
        showUI()
        applyOrder(keeping: nil)
    }

    func close() {
        token += 1
        isOpen = false
        sheetOpen = false
        advanceTask?.cancel()
        uiTask?.cancel()
        loads.values.forEach { $0.cancel() }
        loads = [:]
        source = nil
        order = []
        current = nil
        showID = nil
        loading = false
        noMatches = false
        shapes = nil
        runningSince = nil
        settings = library.defaults
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Texts

    var countText: String {
        guard !order.isEmpty else { return "" }
        let name = name(of: order[pos])
        return String(localized: "\(pos + 1) of \(order.count)", comment: "Position in the slideshow")
            + (name.isEmpty ? "" : "   " + name)
    }

    var savingText: String? {
        guard let s = library.saving, s.id == showID else { return nil }
        return String(localized: "Saving for quick access: \(s.saved) of \(s.total)")
    }

    var displayLabel: String {
        if let id = showID, let s = library.show(id) { return s.name }
        return label
    }

    private func name(of index: Int) -> String {
        switch source {
        case .items(let a): return index < a.count ? a[index].name : ""
        case .stored(let id, _):
            guard let names = library.show(id)?.names, index < names.count else { return "" }
            return names[index]
        case nil: return ""
        }
    }

    // MARK: Navigation

    /// The images to play, in play order. A saved slideshow leaves out images of the other
    /// format right away; just-picked images are skipped once they turn out to be the wrong one.
    private func buildOrder(keeping keep: Int?) {
        let n = source?.count ?? 0
        let filter = settings.orientation
        if filter != .all, case .stored = source, let shapes {
            order = (0..<n).filter { $0 < shapes.count && filter.allows(shapes[$0]) }
        } else {
            order = (0..<n).filter { !skipped.contains($0) }
        }
        if settings.shuffle {
            order.shuffle()
            if let keep, let k = order.firstIndex(of: keep) { order.swapAt(0, k) }
            pos = 0
        } else {
            // The kept image, or the next one after it that is still in the slideshow.
            pos = keep.flatMap { k in order.firstIndex { $0 >= k } } ?? 0
        }
    }

    /// Builds the order and shows its first image. With a format chosen, a saved slideshow
    /// first needs its images' formats, which takes a moment the first time.
    private func applyOrder(keeping keep: Int?) {
        token += 1
        let my = token
        if settings.orientation != .all, case .stored(let id, let n) = source, (shapes?.count ?? -1) < n {
            loading = true
            updateClock()
            Task {
                let s = await library.shapes(id, count: n)
                guard my == token else { return }
                shapes = s
                finishOrder(keeping: keep)
            }
        } else {
            finishOrder(keeping: keep)
        }
    }

    private func finishOrder(keeping keep: Int?) {
        if let slide = current, slide.index == keep, case .items = source,
           !settings.orientation.allows(slide.image.shape) {
            skipped.insert(slide.index)
        }
        buildOrder(keeping: keep)
        noMatches = order.isEmpty && (source?.count ?? 0) > 0
        if noMatches {
            showNoMatches()
        } else if let slide = current, !order.isEmpty, order[pos] == slide.index {
            // The image on screen stays: just carry on from here.
            loading = false
            updateClock()
            preload()
        } else {
            show(pos)
        }
    }

    private func showNoMatches() {
        noMatches = true
        loading = false
        withAnimation { current = nil }
        updateClock()
        showUI()
    }

    private func wrap(_ p: Int) -> Int {
        let n = order.count
        return n == 0 ? 0 : ((p % n) + n) % n
    }

    func go(_ d: Int) {
        dir = d
        show(pos + d)
        showUI()
    }

    func togglePlay() {
        playing.toggle()
        updateClock()
        showUI()
    }

    private func show(_ p: Int) {
        guard !order.isEmpty, !noMatches else { return }
        if order.allSatisfy({ bad.contains($0) || skipped.contains($0) }) {
            // Only unreadable ones left closes the slideshow, see below.
            if !skipped.isEmpty { showNoMatches() }
            return
        }
        pos = wrap(p)
        // Past images already known to be unreadable or of the wrong format.
        while bad.contains(order[pos]) || skipped.contains(order[pos]) { pos = wrap(pos + dir) }
        token += 1
        let my = token, idx = order[pos]
        loading = true
        updateClock()
        Task {
            let img = await image(for: idx)
            guard my == token else { return }
            loading = false
            guard let img else {
                bad.insert(idx)
                if order.allSatisfy(bad.contains) {
                    close()
                    onFailure?(String(localized: "None of these images could be opened on this device."))
                } else {
                    show(pos + dir)
                }
                return
            }
            if case .items = source, !settings.orientation.allows(img.shape) {
                skipped.insert(idx)
                show(pos + dir)
                return
            }
            withAnimation(settings.fade ? .easeInOut(duration: 0.9) : nil) {
                current = Slide(index: idx, image: img)
            }
            accumulated = 0
            runningSince = nil
            updateClock()
            preload()
        }
    }

    private func image(for index: Int) async -> UIImage? {
        if let t = loads[index] { return await t.value }
        guard let source else { return nil }
        let maxPixel = Images.maxEdge
        let task: Task<UIImage?, Never>
        switch source {
        case .items(let items):
            let item = items[index]
            task = Task {
                guard let data = try? await item.data() else { return nil }
                return await Images.display(data: data, maxPixel: maxPixel)
            }
        case .stored(let id, _):
            let url = library.imageURL(id, index)
            task = Task { await Images.display(url: url, maxPixel: maxPixel) }
        }
        loads[index] = task
        let img = await task.value
        if img == nil, loads[index] == task { loads[index] = nil }
        return img
    }

    /// Loads the next image ahead of time and forgets everything but the
    /// previous, current and next one.
    private func preload() {
        guard order.count > 1 else { return }
        let keep: Set<Int> = [order[wrap(pos - 1)], order[pos], order[wrap(pos + 1)]]
        for (i, t) in loads where !keep.contains(i) {
            t.cancel()
            loads[i] = nil
        }
        let next = order[wrap(pos + dir)]
        Task { _ = await image(for: next) }
    }

    // MARK: Timing

    private var shouldRun: Bool { isOpen && playing && !loading && !sheetOpen && !noMatches && order.count > 1 }

    /// How much of the current image's time has passed, 0…1.
    func progress(at date: Date) -> Double {
        let e = accumulated + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
        return min(1, e / Double(settings.interval))
    }

    private func updateClock() {
        advanceTask?.cancel()
        advanceTask = nil
        let now = Date()
        if shouldRun {
            if runningSince == nil { runningSince = now }
            let elapsed = accumulated + now.timeIntervalSince(runningSince!)
            let remaining = max(0, Double(settings.interval) - elapsed)
            advanceTask = Task {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                dir = 1
                show(pos + 1)
            }
        } else if let s = runningSince {
            accumulated += now.timeIntervalSince(s)
            runningSince = nil
        }
    }

    // MARK: Controls visibility

    func showUI() {
        uiTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { uiVisible = true }
        guard playing, !sheetOpen else { return }
        uiTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { uiVisible = false }
        }
    }

    func toggleUI() {
        if uiVisible {
            uiTask?.cancel()
            withAnimation(.easeInOut(duration: 0.3)) { uiVisible = false }
        } else {
            showUI()
        }
    }

    // MARK: Settings

    func change(_ edit: (inout ShowSettings) -> Void) {
        let old = settings
        edit(&settings)
        if settings.orientation != old.orientation {
            skipped = []
            noMatches = false
            applyOrder(keeping: current?.index)
        } else if settings.shuffle != old.shuffle, !order.isEmpty {
            buildOrder(keeping: order[pos])
            preload()
        }
        library.defaults = settings
        if let showID { library.setSettings(showID, settings) }
        if settings.interval != old.interval { updateClock() }
    }
}
