import SwiftUI

enum PickKind { case folder, photos, files }

/// "Pick photos or files": a menu that asks where the images come from.
struct PickPhotosOrFilesMenu<Label: View>: View {
    var onPick: (PickKind) -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { onPick(.photos) }
            Button("Files", systemImage: "folder") { onPick(.files) }
        } label: {
            label
        }
    }
}

struct PlayerView: View {
    @Bindable var player: Player
    /// "Choose another folder" / "Pick photos or files" from the settings sheet.
    var onPick: (PickKind) -> Void

    @State private var pendingPick: PickKind?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let slide = player.current {
                SlideView(image: slide.image, fill: player.settings.fill)
                    .id(slide.id)
                    .transition(.opacity)
            }

            if player.loading && player.current == nil {
                ProgressView().tint(.white).controlSize(.large)
            }

            // Taps and swipes on the picture: the outer bands go back/forward,
            // the middle shows or hides the controls.
            GeometryReader { geo in
                Color.clear
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { v in
                                let dx = v.translation.width, dy = v.translation.height
                                if abs(dx) > 50 && abs(dx) > abs(dy) {
                                    player.go(dx < 0 ? 1 : -1)
                                } else if abs(dx) < 14 && abs(dy) < 14 {
                                    let x = v.location.x, w = geo.size.width
                                    if x < w * 0.28 { player.go(-1) }
                                    else if x > w * 0.72 { player.go(1) }
                                    else { player.toggleUI() }
                                }
                            }
                    )
            }
            .ignoresSafeArea()

            controls
                .opacity(player.uiVisible ? 1 : 0)
                .allowsHitTesting(player.uiVisible)

            if player.settings.progress {
                VStack {
                    Spacer()
                    ProgressBar(player: player)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(player.uiVisible ? .automatic : .hidden)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $player.sheetOpen, onDismiss: {
            if let k = pendingPick {
                pendingPick = nil
                onPick(k)
            }
        }) {
            SettingsSheet(player: player) { kind in
                pendingPick = kind
                player.sheetOpen = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Slideshow")
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayLabel)
                        .font(.system(size: 16, weight: .semibold))
                    Text(player.countText)
                        .font(.system(size: 14).monospacedDigit())
                        .opacity(0.75)
                    if let s = player.savingText {
                        Text(s)
                            .font(.system(size: 14).monospacedDigit())
                            .opacity(0.6)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                RoundButton(systemImage: "xmark", label: "Close slideshow") { player.close() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .background(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            Spacer(minLength: 0)

            HStack(spacing: 18) {
                RoundButton(systemImage: "slider.horizontal.3", label: "Settings") { player.sheetOpen.toggle() }
                RoundButton(systemImage: "chevron.left", label: "Previous image") { player.go(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button { player.togglePlay() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 66, height: 66)
                        .background(.white, in: .circle)
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(player.playing ? "Pause" : "Play")
                RoundButton(systemImage: "chevron.right", label: "Next image") { player.go(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .foregroundStyle(.white)
    }
}

/// One picture: either fitted on a blurred copy of itself, or filling the screen.
private struct SlideView: View {
    let image: UIImage
    let fill: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !fill {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 1.2, height: geo.size.height * 1.2)
                        .blur(radius: 44)
                        .saturation(1.35)
                        .colorMultiply(Color(white: 0.5))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct ProgressBar: View {
    let player: Player

    var body: some View {
        TimelineView(.animation(paused: player.runningSince == nil)) { ctx in
            let f = player.progress(at: ctx.date)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.12))
                Rectangle()
                    .fill(.white.opacity(player.playing ? 0.8 : 0.35))
                    .scaleEffect(x: f, y: 1, anchor: .leading)
            }
            .frame(height: 3)
        }
    }
}

struct RoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: .circle)
                .environment(\.colorScheme, .dark)
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

private struct SettingsSheet: View {
    let player: Player
    var onPick: (PickKind) -> Void

    var body: some View {
        // Read here so the sheet redraws when a setting changes (values read only
        // inside Toggle bindings or ForEach rows would not be tracked).
        let current = player.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 20, weight: .heavy))
                    .padding(.bottom, 16)

                Text("Time per image")
                    .font(.system(size: 15))
                    .opacity(0.7)
                    .padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(ShowSettings.intervals, id: \.self) { s in
                        let on = current.interval == s
                        Button { player.change { $0.interval = s } } label: {
                            Text(ShowSettings.intervalLabel(s))
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .foregroundStyle(on ? .black : .white)
                                .background(on ? Color.white : Color.white.opacity(0.1), in: .capsule)
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.bottom, 18)

                toggle("Shuffle", nil, \.shuffle, current)
                toggle("Fill screen", "Crops edges instead of showing the whole image", \.fill, current)
                toggle("Fade between images", nil, \.fade, current)
                toggle("Progress bar", "Thin line at the bottom that runs until the next image", \.progress, current)

                VStack(spacing: 10) {
                    sheetButton("Choose another folder") { onPick(.folder) }
                    PickPhotosOrFilesMenu(onPick: onPick) { sheetLabel("Pick photos or files") }
                        .foregroundStyle(.white)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private func toggle(_ title: String, _ detail: String?, _ key: WritableKeyPath<ShowSettings, Bool>,
                        _ current: ShowSettings) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.1))
            Toggle(isOn: Binding(get: { current[keyPath: key] },
                                 set: { v in player.change { $0[keyPath: key] = v } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17))
                    if let detail {
                        Text(detail).font(.system(size: 13)).opacity(0.6)
                    }
                }
            }
            .tint(.switchOn)
            .frame(minHeight: 52)
        }
    }

    private func sheetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { sheetLabel(title) }
            .foregroundStyle(.white)
    }

    private func sheetLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}
