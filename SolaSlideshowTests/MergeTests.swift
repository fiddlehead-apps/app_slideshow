import Foundation
import Testing
@testable import SolaSlideshow

/// Which side wins when a slideshow and its record in iCloud differ.
struct MergeTests {
    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    /// A slideshow on this device: 30 images, named "Here".
    private func local(modified: Date, content: Date) -> Show {
        var s = Show(id: "a1", name: "Here", folder: "Folder", count: 30, settings: ShowSettings())
        s.saved = 30
        s.done = true
        s.names = ["here.jpg"]
        s.modified = modified
        s.content = content
        return s
    }

    /// Its record in iCloud: 50 images, named "There", hidden.
    private func remote(modified: Date, content: Date) -> RemoteShow {
        RemoteShow(name: "There", folder: "Other", names: ["there.jpg"], hidden: true, count: 50, done: true,
                   modified: modified, content: content)
    }

    @Test func aSlideshowThatIsNewHereIsTakenAsItIs() throws {
        let result = Show.merged(nil, id: "a1", with: remote(modified: late, content: late))
        let s = try #require(result.show)
        #expect(s.id == "a1")
        #expect(s.name == "There")
        #expect(s.count == 50)
        #expect(s.folder == "Other")
        #expect(s.hidden)
        #expect(s.copy)
        #expect(s.saved == 0, "its images arrive as records of their own")
        #expect(!result.resend)
    }

    @Test func everythingNewerInICloudReplacesWhatIsHere() throws {
        let result = Show.merged(local(modified: early, content: early), id: "a1", with: remote(modified: late, content: late))
        let s = try #require(result.show)
        #expect(s.name == "There")
        #expect(s.count == 50)
        #expect(s.names == ["there.jpg"])
        #expect(s.modified == late)
        #expect(s.content == late)
        #expect(!result.resend)
    }

    @Test func everythingNewerHereStaysAndGoesUp() {
        let result = Show.merged(local(modified: late, content: late), id: "a1", with: remote(modified: early, content: early))
        #expect(result.show == nil)
        #expect(result.resend)
    }

    /// The case that used to lose images: one device picked the folder again (50 images), this
    /// one only opened the slideshow afterwards, which makes its details the newer ones.
    @Test func openingASlideshowHereDoesNotBringBackItsOldImages() throws {
        let result = Show.merged(local(modified: late, content: early), id: "a1", with: remote(modified: early, content: late))
        let s = try #require(result.show)
        #expect(s.name == "Here", "the details are newer here")
        #expect(!s.hidden)
        #expect(s.modified == late)
        #expect(s.count == 50, "the images are newer in iCloud")
        #expect(s.names == ["there.jpg"])
        #expect(s.content == late)
        #expect(result.resend, "the newer details have to go up")
    }

    @Test func newerImagesHereStayWhileTheDetailsComeFromICloud() throws {
        let result = Show.merged(local(modified: early, content: late), id: "a1", with: remote(modified: late, content: early))
        let s = try #require(result.show)
        #expect(s.name == "There")
        #expect(s.hidden)
        #expect(s.count == 30)
        #expect(s.names == ["here.jpg"])
        #expect(s.content == late)
        #expect(result.resend)
    }

    @Test func aFolderThatPlaysHereKeepsItsOwnName() throws {
        var here = local(modified: early, content: early)
        here.bookmark = Data([1])
        here.copy = false
        let s = try #require(Show.merged(here, id: "a1", with: remote(modified: late, content: late)).show)
        #expect(s.folder == "Folder")
        #expect(s.bookmark == Data([1]))
        #expect(s.copy, "being in iCloud means it has a copy")
    }

    @Test func theSameDatesCountAsNotNewerHere() throws {
        let result = Show.merged(local(modified: late, content: late), id: "a1", with: remote(modified: late, content: late))
        #expect(try #require(result.show).name == "There")
        #expect(!result.resend)
    }
}
