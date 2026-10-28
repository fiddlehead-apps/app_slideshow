#if DEBUG
import Foundation

/// Sample slideshows for App Store screenshots, made from the images in the app's
/// Documents/Demo/<folder> (copy them into the simulator's app container first).
/// Only in debug builds, and only with the launch argument `-demoData YES` on an empty list.
enum DemoData {
    static func seedIfRequested(_ library: Library) {
        guard UserDefaults.standard.bool(forKey: "demoData"), library.list(hidden: false).isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let de = Locale.current.language.languageCode?.identifier == "de"
        // Saved one after another (a new save cancels the running one); the last one ends up on top.
        let sets = [("Abend", de ? "Abendlicht" : "Evening light"),
                    ("Sommer", de ? "Sommer am See" : "Summer by the lake"),
                    ("Landschaften", de ? "Landschaften" : "Landscapes")]
        Task {
            for (folder, name) in sets {
                let dir = docs.appendingPathComponent("Demo/\(folder)", isDirectory: true)
                let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                guard !files.isEmpty else { continue }
                _ = library.save(Images.items(fromFiles: files), name: name, folder: nil)
                while library.saving != nil { try? await Task.sleep(for: .milliseconds(200)) }
            }
        }
    }
}
#endif
