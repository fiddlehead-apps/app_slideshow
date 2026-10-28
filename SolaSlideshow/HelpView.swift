import LocalAuthentication
import SwiftUI

enum Unlock {
    /// Face ID (or the device passcode as fallback). Fails when the device has no passcode.
    static func run() async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Show hidden slideshows"))) ?? false
    }
}

struct HelpView: View {
    let library: Library
    var onOpen: (Show) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var unlocked: Bool

    init(library: Library, startHidden: Bool = false, onOpen: @escaping (Show) -> Void) {
        self.library = library
        self.onOpen = onOpen
        _unlocked = State(initialValue: startHidden)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("What it does",
                            "Sola Slideshow plays every image in a folder – or photos you pick – full screen.")
                    section("Start a slideshow",
                            "Tap **Choose folder** and pick a folder in Files, for example in iCloud Drive or On My iPhone. Every image in it and in its subfolders plays in name order. With **Pick photos or files** you choose single images from Photos or Files instead.")
                    section("While it plays",
                            "Tap the right edge or swipe left for the next image, tap the left edge or swipe right for the previous one. A tap in the middle shows or hides the controls. The screen stays on as long as the slideshow runs.")
                    section("Settings",
                            "The slider button at the bottom left opens the settings: time per image, image format (all images, or only portrait or only landscape ones), shuffle, fill screen (crops the edges instead of showing the whole image), fading between images, and whether the progress bar runs along the bottom edge. Each slideshow remembers its own settings.")
                    section("Your slideshows",
                            "Every slideshow you start appears on the start screen and plays again with one tap. For that the app keeps copies of the images at screen size, so the folder is not needed anymore. Choosing the same folder again updates its slideshow instead of adding a second one. Use the pencil to rename a slideshow and the bin to delete it.")

                    // Tapping this paragraph five times asks for Face ID and opens the hidden slideshows.
                    section("Private",
                            "Images stay on this device unless you turn on iCloud sync. Nothing goes to a server of ours, there is no account and nothing is tracked.")
                        .contentShape(.rect)
                        .onMultiTap(5, window: .milliseconds(1200)) {
                            Task {
                                if await Unlock.run() { unlocked = true }
                            }
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        section("iCloud",
                                "Off unless you turn it on. Then your slideshows with their saved copies, and the settings for new slideshows, sync through your private iCloud database to your devices with the same Apple Account. The copies count toward your iCloud storage.")
                        CloudSyncToggle(sync: library.cloud)
                            .font(.system(size: 16))
                            .tint(Color.switchOn)
                    }

                    Text("Version \(Self.version)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.muted)
                        .padding(.top, 8)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(Color.bg)
            .navigationTitle("How it works")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $unlocked) {
                HiddenView(library: library, onOpen: onOpen)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.ink)
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(Color.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Slideshows moved out of the start screen. Only reachable through Face ID.
struct HiddenView: View {
    let library: Library
    var onOpen: (Show) -> Void

    var body: some View {
        let shows = library.list(hidden: true)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if shows.isEmpty {
                    Text("No hidden slideshows yet. Tap a slideshow on the start screen five times to hide it.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.muted)
                        .padding(.top, 12)
                } else {
                    ForEach(Array(shows.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Rectangle().fill(Color.line).frame(height: 1) }
                        ShowRow(show: s, library: library, inHidden: true, onOpen: onOpen)
                    }
                    let total = library.usage(hidden: true)
                    if total > 0 {
                        Text("Saved as copies on this device, using \(Format.bytes(total)).")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.muted)
                            .padding(.top, 10)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bg)
        .navigationTitle("Hidden slideshows")
    }
}
