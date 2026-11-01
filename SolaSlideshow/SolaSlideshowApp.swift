import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct SolaSlideshowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var library: Library
    @State private var player: Player
    @Environment(\.scenePhase) private var scenePhase

    @State private var message: StartView.Message?
    @State private var waiting: StartView.Waiting?
    @State private var scanTask: Task<Void, Never>?
    @State private var showHelp = false
    @State private var helpStartsHidden = false
    @State private var importing = false
    @State private var importFolder = true
    @State private var pickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pickingAlbum = false
    @State private var albumAccessLimited = false

    init() {
        let lib = Library()
        _library = State(initialValue: lib)
        _player = State(initialValue: Player(library: lib))
        #if DEBUG
        DemoData.seedIfRequested(lib)
        #endif
    }

    var body: some View {
        ZStack {
            StartView(library: library, player: player, message: $message, waiting: waiting,
                      onPick: pick, onStopWaiting: stopWaiting, onOpen: openSaved, onHelp: openHelp, onHidden: openHidden)
                .accessibilityHidden(player.isOpen)

            if player.isOpen {
                PlayerView(player: player, onPick: pick)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Keeps hidden slideshows out of the app switcher.
            if scenePhase != .active && showsHiddenContent {
                Color.black.ignoresSafeArea().zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.isOpen)
        .fontDesign(.rounded)
        .tint(Color.accent)
        .sheet(isPresented: $showHelp) {
            HelpView(library: library, startHidden: helpStartsHidden) { show in
                showHelp = false
                openSaved(show)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: importFolder ? [.folder] : [.image],
                      allowsMultipleSelection: !importFolder) { result in
            handleImport(result)
        }
        .sheet(isPresented: $pickingAlbum) {
            AlbumPicker(limited: albumAccessLimited) { album in
                pickingAlbum = false
                openAlbum(album)
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $photoSelection, matching: .images,
                      preferredItemEncoding: .current)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            begin(items.map { .photo($0) }, folder: nil)
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app locks the hidden slideshows again.
            if phase == .background { showHelp = false }
            if phase == .active { Task { await library.cloud.syncNow() } }
        }
        .onAppear {
            player.onFailure = { text in message = .init(text: text, isError: true) }
        }
    }

    private var showsHiddenContent: Bool {
        if showHelp { return true }
        if player.isOpen, let id = player.showID, library.show(id)?.hidden == true { return true }
        return false
    }

    private func openHelp() {
        helpStartsHidden = false
        showHelp = true
    }

    /// Unlocks the hidden slideshows from the start screen. They open inside the help sheet,
    /// so the same rules lock them again when the app goes to the background.
    private func openHidden() {
        Task {
            guard await Unlock.run() else { return }
            helpStartsHidden = true
            showHelp = true
        }
    }

    // MARK: Picking

    private func pick(_ kind: PickKind) {
        guard waiting == nil else { return }
        if player.isOpen { player.close() }
        message = nil
        library.notice = nil
        switch kind {
        case .folder:
            importFolder = true
            importing = true
        case .files:
            importFolder = false
            importing = true
        case .album:
            Task {
                switch await PhotoAlbums.requestAccess() {
                case .full:
                    albumAccessLimited = false
                    pickingAlbum = true
                case .limited:
                    albumAccessLimited = true
                    pickingAlbum = true
                case .denied:
                    #if targetEnvironment(macCatalyst)
                    message = .init(text: String(localized: "Sola Slideshow has no access to your photos. To choose an album, turn on Sola Slideshow in System Settings › Privacy & Security › Photos."), isError: true)
                    #else
                    message = .init(text: String(localized: "Sola Slideshow has no access to your photos. To choose an album, allow access to all photos in the Settings app under Apps › Sola Slideshow › Photos."), isError: true)
                    #endif
                }
            }
        case .photos:
            pickingPhotos = true
        }
    }

    private func openAlbum(_ album: PhotoAlbum) {
        guard waiting == nil else { return }
        message = nil
        waiting = .init(title: String(localized: "Opening your album…"),
                        text: String(localized: "Photos that are only in iCloud are downloaded while the slideshow plays."),
                        since: Date())
        scanTask = Task {
            let items = await PhotoAlbums.items(inAlbum: album.id)
            guard !Task.isCancelled else { return }
            waiting = nil
            if items.isEmpty {
                message = .init(text: String(localized: "That album has no photos."), isError: true)
            } else {
                begin(items, folder: nil, album: album.id, name: album.title)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        if importFolder {
            let folder = urls[0]
            let access = FolderAccess(folder)
            waiting = .init(title: String(localized: "Opening your folder…"),
                            text: library.cloud.isOn
                                ? String(localized: "Your device reads every file in the folder before the slideshow can start. Big folders or photos that are only in iCloud Drive can take a moment.")
                                : String(localized: "Your device reads every file in the folder before the slideshow can start. Big folders or photos that are only in iCloud Drive can take a moment. Nothing is uploaded."),
                            since: Date())
            scanTask = Task {
                let items = await Images.scan(folder: folder, access: access)
                guard !Task.isCancelled else { return }
                waiting = nil
                if items.isEmpty {
                    message = .init(text: String(localized: "That folder has no images. Choose a folder with JPG, PNG, HEIC or WebP files."), isError: true)
                } else {
                    begin(items, folder: folder.lastPathComponent)
                }
            }
        } else {
            let items = Images.items(fromFiles: urls)
            if items.isEmpty {
                message = .init(text: String(localized: "None of the selected files are images."), isError: true)
            } else {
                begin(items, folder: nil)
            }
        }
    }

    private func stopWaiting() {
        scanTask?.cancel()
        scanTask = nil
        waiting = nil
    }

    // MARK: Playing

    private func begin(_ items: [SourceItem], folder: String?, album: String? = nil, name: String? = nil) {
        message = nil
        let today = Date().formatted(.dateTime.day().month(.abbreviated))
        let label = name.flatMap { $0.isEmpty ? nil : $0 } ?? folder
            ?? String(localized: "Photos, \(today)", comment: "Default name for a slideshow of picked images")
        let show = library.save(items, name: label, folder: folder, album: album)
        player.start(.items(items), label: show.name, showID: show.id, settings: show.settings)
    }

    private func openSaved(_ show: Show) {
        guard let s = library.show(show.id), s.saved > 0 else {
            message = .init(text: show.album != nil
                            ? String(localized: "Nothing from this slideshow is saved yet. Choose the album again to save it.")
                            : String(localized: "Nothing from this slideshow is saved yet. Choose the folder again to save it."), isError: true)
            return
        }
        message = nil
        library.markPlayed(s.id)
        player.start(.stored(id: s.id, count: s.saved), label: s.name, showID: s.id, settings: s.settings)
    }
}
