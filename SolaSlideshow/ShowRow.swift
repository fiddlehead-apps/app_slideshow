import SwiftUI

/// Counts quick successive taps. A single (or double) tap runs `single`
/// once the taps stop; reaching `count` taps runs `reached` instead.
struct MultiTap: ViewModifier {
    var count: Int
    var window: Duration
    var single: (() -> Void)?
    var reached: () -> Void

    @State private var taps = 0
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onTapGesture {
            taps += 1
            pending?.cancel()
            if taps >= count {
                taps = 0
                reached()
                return
            }
            pending = Task {
                try? await Task.sleep(for: window)
                guard !Task.isCancelled else { return }
                let n = taps
                taps = 0
                if n <= 2 { single?() }
            }
        }
    }
}

extension View {
    func onMultiTap(_ count: Int, window: Duration, single: (() -> Void)? = nil, reached: @escaping () -> Void) -> some View {
        modifier(MultiTap(count: count, window: window, single: single, reached: reached))
    }
}

/// One saved slideshow in a list: thumbnail, name, status, rename and delete.
struct ShowRow: View {
    let show: Show
    let library: Library
    /// Rows in the hidden section open on the first tap and offer "Unhide".
    var inHidden = false
    var onOpen: (Show) -> Void
    var onFiveTaps: ((Show) -> Void)?

    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var confirmTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 2) {
            mainArea
            if !renaming {
                iconButton("pencil", label: "Rename \(show.name)") {
                    newName = show.name
                    renaming = true
                }
                if inHidden {
                    iconButton("eye", label: "Move \(show.name) back to Your slideshows") {
                        withAnimation { library.setHidden(show.id, false) }
                    }
                }
                deleteButton
            }
        }
        .frame(minHeight: 76)
        .alert("Rename slideshow", isPresented: $renaming) {
            TextField("Slideshow name", text: $newName)
                .submitLabel(.done)
            Button("Cancel", role: .cancel) {}
            Button("Save") { library.rename(show.id, to: newName) }
        }
        .contextMenu {
            Button { newName = show.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
            if inHidden {
                Button { library.setHidden(show.id, false) } label: { Label("Move to Your slideshows", systemImage: "eye") }
            }
            Button(role: .destructive) { Task { await library.delete(show.id) } } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder private var mainArea: some View {
        let content = HStack(spacing: 14) {
            Group {
                if let t = library.thumb(for: show) {
                    Image(uiImage: t).resizable().scaledToFill()
                } else {
                    Color.line
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(show.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color.ink)
                let sub = subtitle
                Text(sub.text)
                    .font(.system(size: 14))
                    .foregroundStyle(sub.live ? Color.accent : Color.muted)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(show) }

        if inHidden {
            content.onTapGesture { onOpen(show) }
        } else {
            content.onMultiTap(5, window: .milliseconds(300), single: { onOpen(show) }) {
                onFiveTaps?(show)
            }
        }
    }

    private var subtitle: (text: String, live: Bool) {
        if let s = library.saving, s.id == show.id { return (String(localized: "Saving \(s.saved) of \(s.total)"), true) }
        if library.isDownloading(show) { return (String(localized: "Loading from iCloud: \(show.saved) of \(show.count)"), true) }
        if !show.done {
            return (show.saved > 0
                    ? String(localized: "\(show.saved) of \(show.count) saved. Choose the folder again to finish.")
                    : String(localized: "Not saved yet. Choose the folder again."), false)
        }
        var bits = [String(localized: "\(show.saved) images"), ShowSettings.intervalLabel(show.settings.interval)]
        if show.settings.shuffle { bits.append(String(localized: "shuffled", comment: "Slideshow plays in random order")) }
        switch show.settings.orientation {
        case .all: break
        case .portrait: bits.append(String(localized: "portrait only", comment: "Part of a slideshow summary: shows only portrait images"))
        case .landscape: bits.append(String(localized: "landscape only", comment: "Part of a slideshow summary: shows only landscape images"))
        }
        let separator = String(localized: "summary.separator", defaultValue: ", ",
                               comment: "Separates the parts of a slideshow summary like “8 images, 5 s, shuffled”")
        return (bits.joined(separator: separator), false)
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(Color.muted)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Like the web app: the first tap turns the bin into a red "Delete" button
    /// for a few seconds, the second tap deletes.
    private var deleteButton: some View {
        Button {
            if confirmDelete {
                confirmTask?.cancel()
                confirmDelete = false
                Task { await library.delete(show.id) }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { confirmDelete = true }
                confirmTask?.cancel()
                confirmTask = Task {
                    try? await Task.sleep(for: .seconds(3.5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.15)) { confirmDelete = false }
                }
            }
        } label: {
            if confirmDelete {
                Text("Delete")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.danger, in: .rect(cornerRadius: 12))
            } else {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(Color.muted)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(confirmDelete ? Text("Confirm delete \(show.name)") : Text("Delete \(show.name)"))
    }
}
