import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct SolaSlideshowApp: App {
    init() {
        #if DEBUG
        DemoData.seedIfRequested(Library.shared)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    /// Shared by all windows; each window has its own player.
    private let library = Library.shared
    @State private var player = Player(library: .shared)
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
            begin(items.map { .photo($0) }, origin: .picked)
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
                switch await PhotoAlbums.access(ask: true) {
                case .full:
                    albumAccessLimited = false
                    pickingAlbum = true
                case .limited:
                    albumAccessLimited = true
                    pickingAlbum = true
                case .denied:
                    message = .init(text: PhotoAlbums.noAccessText, isError: true)
                }
            }
        case .photos:
            pickingPhotos = true
        }
    }

    private func openAlbum(_ album: PhotoAlbum) {
        guard waiting == nil else { return }
        message = nil
        waiting = opening(album: true)
        scanTask = Task {
            let items = await PhotoAlbums.items(inAlbum: album.id) ?? []
            guard !Task.isCancelled else { return }
            waiting = nil
            if items.isEmpty {
                message = .init(text: String(localized: "That album has no photos."), isError: true)
            } else {
                begin(items, origin: .album(album.id), name: album.title)
            }
        }
    }

    /// The note on the start screen while a folder or album is read.
    private func opening(album: Bool) -> StartView.Waiting {
        if album {
            return .init(title: String(localized: "Opening your album…"),
                         text: String(localized: "Photos that are only in iCloud are downloaded while the slideshow plays."),
                         since: Date())
        }
        return .init(title: String(localized: "Opening your folder…"),
                     text: library.cloud.isOn
                        ? String(localized: "Your device reads every file in the folder before the slideshow can start. Big folders or photos that are only in iCloud Drive can take a moment.")
                        : String(localized: "Your device reads every file in the folder before the slideshow can start. Big folders or photos that are only in iCloud Drive can take a moment. Nothing is uploaded."),
                     since: Date())
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        if importFolder {
            let folder = urls[0]
            let access = FolderAccess(folder)
            waiting = opening(album: false)
            scanTask = Task {
                let items = await Images.scan(folder: folder, access: access)
                guard !Task.isCancelled else { return }
                waiting = nil
                if items.isEmpty {
                    message = .init(text: String(localized: "That folder has no images. Choose a folder with JPG, PNG, HEIC or WebP files."), isError: true)
                } else {
                    begin(items, origin: .folder(folder), name: folder.lastPathComponent)
                }
            }
        } else {
            let items = Images.items(fromFiles: urls)
            if items.isEmpty {
                message = .init(text: String(localized: "None of the selected files are images."), isError: true)
            } else {
                begin(items, origin: .picked)
            }
        }
    }

    private func stopWaiting() {
        scanTask?.cancel()
        scanTask = nil
        waiting = nil
    }

    // MARK: Playing

    private func begin(_ items: [SourceItem], origin: Library.Origin, name: String? = nil) {
        message = nil
        let today = Date().formatted(.dateTime.day().month(.abbreviated))
        let label = name.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "Photos, \(today)", comment: "Default name for a slideshow of picked images")
        let show = library.add(items, name: label, origin: origin)
        player.start(.items(items), label: show.name, showID: show.id, settings: show.settings)
    }

    private func openSaved(_ show: Show) {
        guard let s = library.show(show.id) else { return }
        guard s.playsFromCopy else {
            openSource(of: s)
            return
        }
        guard s.saved > 0 else {
            message = .init(text: String(localized: "None of this slideshow’s images are on this device yet."), isError: true)
            return
        }
        message = nil
        library.markPlayed(s.id)
        player.start(.stored(id: s.id, count: s.saved), label: s.name, showID: s.id, settings: s.settings)
    }

    /// Plays a slideshow straight from its folder or album, with what is in there now.
    private func openSource(of s: Show) {
        guard waiting == nil else { return }
        message = nil
        waiting = opening(album: s.album != nil)
        scanTask = Task {
            let result = await library.source(of: s.id, ask: true)
            guard !Task.isCancelled else { return }
            waiting = nil
            switch result {
            case .success(let items) where !items.isEmpty:
                library.opened(s.id, items)
                // The slideshow as it is now: its name or settings may have changed meanwhile.
                let now = library.show(s.id) ?? s
                player.start(.items(items), label: now.name, showID: now.id, settings: now.settings)
            case .success:
                message = .init(text: s.album != nil
                                ? String(localized: "That album has no photos.")
                                : String(localized: "That folder has no images. Choose a folder with JPG, PNG, HEIC or WebP files."), isError: true)
            case .failure(let error):
                message = .init(text: library.explain(error, for: s), isError: true)
            }
        }
    }
}
