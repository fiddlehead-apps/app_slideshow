import Testing
@testable import SolaSlideshow

/// The order in which slideshows get their copies.
struct CopyQueueTests {
    @Test func oneAfterTheOtherInTheOrderTheyCame() {
        var q = CopyQueue<String>()
        #expect(q.isEmpty)
        let stopA = q.add("a", "job a")
        let stopB = q.add("b", "job b")
        #expect(!stopA)
        #expect(!stopB)

        let first = q.start()
        #expect(first?.id == "a")
        #expect(first?.job == "job a")
        #expect(q.running == "a")
        #expect(q.waiting == ["b"])
        let tooEarly = q.start()
        #expect(tooEarly == nil, "b waits until a is done")

        q.finished()
        let second = q.start()
        #expect(second?.id == "b")
        q.finished()
        let third = q.start()
        #expect(third == nil)
        #expect(q.isEmpty)
    }

    /// What used to go wrong: picking a second slideshow stopped the copies of the first.
    @Test func aNewSlideshowDoesNotStopTheRunningOne() {
        var q = CopyQueue<String>()
        _ = q.add("a", "job a")
        _ = q.start()
        let stop = q.add("b", "job b")
        #expect(!stop)
        #expect(q.running == "a")
        #expect(q.waiting == ["b"])
    }

    @Test func pickingTheRunningSlideshowAgainStopsItsOldCopies() {
        var q = CopyQueue<String>()
        _ = q.add("a", "old")
        _ = q.start()
        let stop = q.add("a", "new")
        #expect(stop, "the copies being made are of the old images")
        #expect(q.waiting == ["a"])
        let tooEarly = q.start()
        #expect(tooEarly == nil, "not before the old run has stopped")

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
        let first = q.start()
        #expect(first?.id == "b")
        q.finished()
        let second = q.start()
        #expect(second?.job == "newer a")
    }

    @Test func removingTellsWhetherCopiesHaveToBeStopped() {
        var q = CopyQueue<String>()
        _ = q.add("a", "job a")
        _ = q.add("b", "job b")
        _ = q.start()

        let stopB = q.remove("b")
        #expect(!stopB, "b only waited")
        #expect(q.waiting.isEmpty)
        let stopA = q.remove("a")
        #expect(stopA, "a is being copied")
        #expect(q.running == "a", "until whoever stops it reports that it has stopped")

        q.finished()
        #expect(q.isEmpty)
        let stopC = q.remove("c")
        #expect(!stopC)
    }
}
