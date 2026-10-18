import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Start screen: pick a folder or photos, and the list of saved slideshows.
struct StartView: View {
    let library: Library
    let player: Player
    @Binding var message: Message?
    var waiting: Waiting?
    var onPick: (PickKind) -> Void
    var onStopWaiting: () -> Void
    var onOpen: (Show) -> Void
    var onHelp: () -> Void
    var onHidden: () -> Void

    struct Message: Equatable {
        var text: String
        var isError = false
    }

    struct Waiting: Equatable {
        var title: String
        var text: String
        var since: Date
    }

    @State private var hideCandidate: Show?

    var body: some View {
        let shows = library.list(hidden: false)
        GeometryReader { geo in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if shows.isEmpty {
                    PrintsIllustration()
                        .padding(.leading, -6)
                        .padding(.bottom, 28)
                }

                Text("Show a whole folder.")
                    .font(.system(size: 52, weight: .heavy))
                    .tracking(-1.5)
                    .lineSpacing(-4)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 16)
                    .accessibilityAddTraits(.isHeader)

                Text("Pick a folder in Files and every image in it plays full screen.")
                    .font(.system(size: 18))
                    .lineSpacing(4)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: 330, alignment: .leading)
                    .padding(.bottom, 32)

                VStack(spacing: 12) {
                    Button { onPick(.folder) } label: {
                        Label("Choose folder", systemImage: "folder")
                    }
                    .buttonStyle(BigButtonStyle(primary: true))

                    PickPhotosOrFilesMenu(onPick: onPick) {
                        Label("Pick photos or files", systemImage: "photo")
                    }
                    .buttonStyle(BigButtonStyle(primary: false))
                }
                .disabled(waiting != nil)
                .opacity(waiting != nil ? 0.45 : 1)

                if let waiting { waitCard(waiting) }

                if let m = message ?? library.notice.map({ Message(text: $0, isError: true) }) {
                    Text(m.text)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(m.isError ? Color.danger : Color.ink)
                        .padding(.top, 18)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                if !shows.isEmpty { librarySection(shows) }

                // Tapping this line five times asks for Face ID and opens the hidden slideshows.
                Text("Images stay on this device. Nothing is uploaded.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.muted)
                    .contentShape(.rect)
                    .onMultiTap(5, window: .milliseconds(1200), reached: onHidden)
                    .padding(.top, 26)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geo.size.height)
        }
        }
        .background(Color.bg)
        .overlay(alignment: .topTrailing) {
            Button(action: onHelp) {
                Image(systemName: "questionmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.surface, in: .circle)
                    .overlay(Circle().strokeBorder(Color.line, lineWidth: 1.5))
            }
            .padding(.trailing, 16)
            .padding(.top, 4)
            .accessibilityLabel("Help")
        }
        .confirmationDialog("Hide this slideshow?", isPresented: Binding(get: { hideCandidate != nil },
                                                                           set: { if !$0 { hideCandidate = nil } }),
                            titleVisibility: .visible, presenting: hideCandidate) { s in
            Button("Move “\(s.name)” to hidden") {
                withAnimation { library.setHidden(s.id, true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It disappears from this list and only shows up in the hidden slideshows.")
        }
    }

    private func waitCard(_ w: Waiting) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ProgressView().tint(Color.accent).padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: w.since, by: 1)) { ctx in
                    let s = Int(ctx.date.timeIntervalSince(w.since))
                    Text(w.title + (s >= 3 ? "  \(s / 60):" + String(format: "%02d", s % 60) : ""))
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                }
                Text(w.text)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(Color.muted)
                Button("Stop waiting", action: onStopWaiting)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.line, lineWidth: 1.5))
        .padding(.top, 18)
    }

    private func librarySection(_ shows: [Show]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your slideshows")
                .font(.system(size: 21, weight: .heavy))
                .tracking(-0.4)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(shows.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Rectangle().fill(Color.line).frame(height: 1) }
                ShowRow(show: s, library: library, onOpen: onOpen) { hideCandidate = $0 }
            }
            let total = library.usage(hidden: false)
            if total > 0 {
                Text("Saved as copies on this device, using \(Format.bytes(total)).")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 36)
    }
}
