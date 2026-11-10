import Foundation
import Testing
@testable import SolaSlideshow

struct ModelsTests {
    private func show(_ json: String) throws -> Show {
        try JSONDecoder().decode(Show.self, from: Data(json.utf8))
    }

    @Test func slideshowsFromBeforeCopiesWereOptionalKeepTheirCopy() throws {
        let s = try show(#"{"id":"a1","name":"Urlaub","folder":"Urlaub","count":3,"saved":3,"done":true}"#)
        #expect(s.copy)
        #expect(!s.hasReference)
        #expect(s.playsFromCopy)
        #expect(s.settings == ShowSettings())
    }

    @Test func onlyIDAndNameAreNeeded() throws {
        let s = try show(#"{"id":"a1","name":"Urlaub"}"#)
        #expect(s.count == 0)
        #expect(s.names.isEmpty)
        #expect(throws: (any Error).self) { _ = try show(#"{"name":"Urlaub"}"#) }
    }

    @Test func aFolderOrAlbumPlaysFromItsSourceUntilTheCopyIsDone() {
        var s = Show(id: "a1", name: "Urlaub", folder: nil, count: 10, settings: ShowSettings())
        s.album = "album-1"
        s.copy = false
        #expect(s.hasReference)
        #expect(!s.playsFromCopy)

        s.copy = true
        s.done = false
        #expect(!s.playsFromCopy, "an unfinished copy of an album is skipped, the album has everything")

        s.done = true
        #expect(s.playsFromCopy)
    }

    @Test func pickedPhotosAlwaysPlayFromTheirCopy() {
        var s = Show(id: "a1", name: "Photos", folder: nil, count: 10, settings: ShowSettings())
        s.done = false
        #expect(!s.hasReference)
        #expect(s.playsFromCopy, "there is nothing else to play them from")
    }

    @Test func theNewFieldsSurviveSavingAndLoading() throws {
        var s = Show(id: "a1", name: "Urlaub", folder: "Urlaub", count: 10, settings: ShowSettings())
        s.bookmark = Data([1, 2, 3])
        s.path = "/Users/me/Urlaub"
        s.copy = false
        let back = try JSONDecoder().decode(Show.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func settingsFallBackToTheDefaults() throws {
        let empty = try JSONDecoder().decode(ShowSettings.self, from: Data("{}".utf8))
        #expect(empty == ShowSettings())

        let odd = try JSONDecoder().decode(ShowSettings.self, from: Data(#"{"interval":0,"orientation":"diagonal","shuffle":true}"#.utf8))
        #expect(odd.interval == ShowSettings().interval)
        #expect(odd.orientation == .all)
        #expect(odd.shuffle)
    }

    @Test func imageFormats() {
        #expect(ImageShape(width: 100, height: 100) == .square)
        #expect(ImageShape(width: 100, height: 102) == .square)
        #expect(ImageShape(width: 100, height: 150) == .portrait)
        #expect(ImageShape(width: 150, height: 100) == .landscape)

        #expect(OrientationFilter.all.allows(nil))
        #expect(OrientationFilter.all.allows(.square))
        #expect(OrientationFilter.portrait.allows(.portrait))
        #expect(!OrientationFilter.portrait.allows(.square))
        #expect(!OrientationFilter.landscape.allows(nil))
    }
}
