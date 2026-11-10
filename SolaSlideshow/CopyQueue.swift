import Foundation

/// Which slideshow gets its copies next. Copies are made one slideshow at a time, in the
/// order they were asked for; `Job` is whatever is needed to make them.
nonisolated struct CopyQueue<Job> {
    /// The slideshows that wait for their turn, the next one first.
    private(set) var waiting: [String] = []
    /// The slideshow whose copies are being made.
    private(set) var running: String?
    private var jobs: [String: Job] = [:]

    var isEmpty: Bool { running == nil && waiting.isEmpty }

    /// Adds a slideshow at the end. One that waits already moves to the end with its new job.
    /// Returns true if the copies being made right now are of this slideshow: they are of
    /// the old images and should be stopped.
    mutating func add(_ id: String, _ job: Job) -> Bool {
        waiting.removeAll { $0 == id }
        waiting.append(id)
        jobs[id] = job
        return running == id
    }

    /// The next slideshow to copy. nil while one is still running, or if none waits.
    mutating func start() -> (id: String, job: Job)? {
        guard running == nil else { return nil }
        while !waiting.isEmpty {
            let id = waiting.removeFirst()
            if let job = jobs.removeValue(forKey: id) {
                running = id
                return (id, job)
            }
        }
        return nil
    }

    /// The running slideshow is done (or was stopped).
    mutating func finished() {
        running = nil
    }

    /// Takes a slideshow out of the queue. Returns true if its copies are being made right
    /// now, so the caller has to stop them.
    mutating func remove(_ id: String) -> Bool {
        waiting.removeAll { $0 == id }
        jobs[id] = nil
        return running == id
    }
}
