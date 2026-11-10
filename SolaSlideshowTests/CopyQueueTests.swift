import Testing
@testable import SolaSlideshow

/// The order in which slideshows get their copies.
struct CopyQueueTests {
    @Test func oneAfterTheOtherInTheOrderTheyCame() {
        var q = CopyQueue<String>()
        #expect(q.isEmpty)
        #expect(!q.add("a", "job a"))
        #expect(!q.add("b", "job b"))

        let first = q.start()
        #expect(first?.id == "a")
        #expect(first?.job == "job a")
        #expect(q.running == "a")
        #expect(q.waiting == ["b"])
        #expect(q.start() == nil, "b waits until a is done")

        q.finished()
        #expect(q.start()?.id == "b")
        q.finished()
        #expect(q.start() == nil)
        #expect(q.isEmpty)
    }

    /// What used to go wrong: picking a second slideshow stopped the copies of the first.
    @Test func aNewSlideshowDoesNotStopTheRunningOne() {
        var q = CopyQueue<String>()
        _ = q.add("a", "job a")
        _ = q.start()
        #expect(!q.add("b", "job b"))
        #expect(q.running == "a")
        #expect(q.waiting == ["b"])
    }

    @Test func pickingTheRunningSlideshowAgainStopsItsOldCopies() {
        var q = CopyQueue<String>()
        _ = q.add("a", "old")
        _ = q.start()
        #expect(q.add("a", "new"), "the copies being made are of the old images")
        #expect(q.waiting == ["a"])
        #expect(q.start() == nil, "not before the old run has stopped")

        q.finished()
        let again = q.start()
        #expect(again?.id == "a")
        #expect(again?.job == "new")
    }

    @Test func aWaitingSlideshowPickedAgainMovesToTheEndWithItsNewImages() {
        var q = CopyQueue<String>()
        _ = q.add("a", "job a")
        _ = q.add("b", "job b")
        _ = q.add("a", "newer a")
        #expect(q.waiting == ["b", "a"])
        #expect(q.start()?.id == "b")
        q.finished()
        #expect(q.start()?.job == "newer a")
    }

    @Test func removingTellsWhetherCopiesHaveToBeStopped() {
        var q = CopyQueue<String>()
        _ = q.add("a", "job a")
        _ = q.add("b", "job b")
        _ = q.start()

        #expect(!q.remove("b"), "b only waited")
        #expect(q.waiting.isEmpty)
        #expect(q.remove("a"), "a is being copied")
        #expect(q.running == "a", "until whoever stops it reports that it has stopped")

        q.finished()
        #expect(q.isEmpty)
        #expect(!q.remove("c"))
    }
}
