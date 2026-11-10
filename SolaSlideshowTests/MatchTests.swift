import Foundation
import Testing
@testable import SolaSlideshow

/// Which slideshow in the list a picked folder or album belongs to.
@MainActor
struct MatchTests {
    private let holiday = URL(fileURLWithPath: "/Volumes/Photos/2024/Urlaub", isDirectory: true)
    private let otherHoliday = URL(fileURLWithPath: "/Volumes/Photos/2023/Urlaub", isDirectory: true)

    private func show(_ id: String, folder: URL? = nil, album: String? = nil) -> Show {
        var s = Show(id: id, name: id, folder: folder?.lastPathComponent, count: 1, settings: ShowSettings())
        s.path = folder.map(Bookmark.path)
        s.bookmark = folder.map { _ in Data([1]) }
        s.album = album
        s.copy = false
        return s
    }

    @Test func theSameFolderIsRecognised() {
        let shows = [show("other", folder: otherHoliday), show("mine", folder: holiday)]
        #expect(Library.match(.folder(holiday), in: shows)?.id == "mine")
    }

    /// What used to go wrong: two folders with the same name overwrote each other.
    @Test func anotherFolderWithTheSameNameIsADifferentSlideshow() {
        let shows = [show("other", folder: otherHoliday)]
        #expect(Library.match(.folder(holiday), in: shows) == nil)
    }

    @Test func aSlideshowWithoutARememberedFolderGoesByTheName() {
        // From before folders were remembered, or received from another device.
        let old = Show(id: "old", name: "Urlaub", folder: "Urlaub", count: 5, settings: ShowSettings())
        #expect(Library.match(.folder(holiday), in: [old])?.id == "old")
        #expect(Library.match(.folder(URL(fileURLWithPath: "/Volumes/Photos/Garten")), in: [old]) == nil)
    }

    @Test func theRememberedFolderWinsOverTheName() {
        let old = Show(id: "old", name: "Urlaub", folder: "Urlaub", count: 5, settings: ShowSettings())
        #expect(Library.match(.folder(holiday), in: [old, show("mine", folder: holiday)])?.id == "mine")
    }

    @Test func aHiddenSlideshowIsNeverTakenOver() {
        var hidden = show("secret", folder: holiday)
        hidden.hidden = true
        var hiddenAlbum = show("secret album", album: "album-1")
        hiddenAlbum.hidden = true
        #expect(Library.match(.folder(holiday), in: [hidden]) == nil)
        #expect(Library.match(.album("album-1"), in: [hiddenAlbum]) == nil)
    }

    @Test func albumsGoByTheirIdentifier() {
        let shows = [show("a", album: "album-1"), show("b", album: "album-2")]
        #expect(Library.match(.album("album-2"), in: shows)?.id == "b")
        #expect(Library.match(.album("album-3"), in: shows) == nil)
    }

    @Test func pickedPhotosAlwaysMakeANewSlideshow() {
        let shows = [show("a", album: "album-1"), show("b", folder: holiday)]
        #expect(Library.match(.picked, in: shows) == nil)
    }
}
