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
        self.source = source
        self.label = label
        self.showID = showID
        self.settings = settings
        current = nil
        buildOrder(keeping: nil)
        sheetOpen = false
        playing = true
        accumulated = 0
        runningSince = nil
        isOpen = true
        UIApplication.shared.isIdleTimerDisabled = true
        showUI()
        show(pos)
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
        runningSince = nil
        settings = library.defaults
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Texts

    var countText: String {
        guard !order.isEmpty else { return "" }
        let name = name(of: order[pos])
        return "\(pos + 1) of \(order.count)" + (name.isEmpty ? "" : "   " + name)
    }

    var savingText: String? {
        guard let s = library.saving, s.id == showID else { return nil }
        return "Saving for quick access: \(s.saved) of \(s.total)"
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

    private func buildOrder(keeping current: Int?) {
        let n = source?.count ?? 0
        order = Array(0..<n)
        if settings.shuffle {
            order.shuffle()
            if let current, let k = order.firstIndex(of: current) { order.swapAt(0, k) }
            pos = 0
        } else {
            pos = current ?? 0
        }
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
        guard !order.isEmpty else { return }
        pos = wrap(p)
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
                if bad.count >= order.count {
                    close()
                    onFailure?("None of these images could be opened on this device.")
                } else {
                    show(pos + dir)
                }
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

    private var shouldRun: Bool { isOpen && playing && !loading && !sheetOpen && order.count > 1 }

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
        if settings.shuffle != old.shuffle, !order.isEmpty {
            buildOrder(keeping: order[pos])
            preload()
        }
        library.defaults = settings
        if let showID { library.setSettings(showID, settings) }
        if settings.interval != old.interval { updateClock() }
    }
}
