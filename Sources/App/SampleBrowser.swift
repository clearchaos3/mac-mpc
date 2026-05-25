import Foundation
import Observation
import MMAudio
import MMModels

struct BrowserEntry: Hashable, Identifiable {
    enum Kind: Hashable { case folder, file, parent }
    let url: URL
    let kind: Kind
    let displayName: String

    var id: URL { url }

    static func parent(_ url: URL) -> BrowserEntry {
        BrowserEntry(url: url, kind: .parent, displayName: "..")
    }
}

/// Browser state — current folder, entries, highlight, auto-preview.
/// One instance lives on `AppState`. The browser sheet observes it.
@MainActor
@Observable
final class SampleBrowser {

    /// Folder shown in the list.
    private(set) var currentDirectory: URL

    /// Entries shown in the list (".." parent + folders + audio files).
    private(set) var entries: [BrowserEntry] = []

    /// Index into `entries` of the currently highlighted row.
    var highlightedIndex: Int = 0 {
        didSet {
            if highlightedIndex != oldValue { autoPreview() }
        }
    }

    /// Auto-preview while scrolling. On by default — matches MPC behaviour.
    var previewOnHighlight: Bool = true

    /// Root the user starts from. Defaults to `~/Music`.
    let rootDirectory: URL

    private weak var audio: AudioEngine?

    init(audio: AudioEngine, root: URL? = nil) {
        self.audio = audio
        let home = FileManager.default.homeDirectoryForCurrentUser
        let resolvedRoot = root ?? home.appendingPathComponent("Music", isDirectory: true)
        self.rootDirectory = resolvedRoot
        self.currentDirectory = resolvedRoot
        refresh()
    }

    // MARK: - Navigation

    func reset() {
        currentDirectory = rootDirectory
        refresh()
    }

    func navigate(to url: URL) {
        currentDirectory = url
        highlightedIndex = 0
        refresh()
    }

    /// Quick-jump locations shown in the browser header. Splice appears only
    /// if `~/Splice` exists.
    var quickLocations: [(name: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var locs: [(String, URL)] = [
            ("Home", home),
            ("Music", home.appendingPathComponent("Music", isDirectory: true)),
        ]
        let splice = home.appendingPathComponent("Splice", isDirectory: true)
        if FileManager.default.fileExists(atPath: splice.path) {
            locs.append(("Splice", splice))
        }
        return locs
    }

    func refresh() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: currentDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var folders: [BrowserEntry] = []
        var files: [BrowserEntry] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                folders.append(BrowserEntry(url: url, kind: .folder, displayName: url.lastPathComponent))
            } else if SampleLoader.isSupported(url) {
                files.append(BrowserEntry(url: url, kind: .file, displayName: url.lastPathComponent))
            }
        }
        folders.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        files.sort   { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var combined: [BrowserEntry] = []
        // Show ".." parent unless we're at the user's home directory.
        let home = FileManager.default.homeDirectoryForCurrentUser
        if currentDirectory.standardizedFileURL != home.standardizedFileURL {
            combined.append(.parent(currentDirectory.deletingLastPathComponent()))
        }
        combined.append(contentsOf: folders)
        combined.append(contentsOf: files)

        entries = combined
        highlightedIndex = entries.isEmpty ? 0 : min(highlightedIndex, entries.count - 1)
    }

    func nudge(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let next = max(0, min(entries.count - 1, highlightedIndex + delta))
        highlightedIndex = next
    }

    /// Drill into a folder / go up / preview file.
    func activate(_ entry: BrowserEntry) -> URL? {
        switch entry.kind {
        case .folder, .parent:
            currentDirectory = entry.url
            highlightedIndex = 0
            refresh()
            return nil
        case .file:
            return entry.url
        }
    }

    /// What the highlighted row resolves to.
    var highlightedEntry: BrowserEntry? {
        guard entries.indices.contains(highlightedIndex) else { return nil }
        return entries[highlightedIndex]
    }

    private func autoPreview() {
        guard previewOnHighlight,
              let e = highlightedEntry,
              e.kind == .file
        else { return }
        audio?.preview(url: e.url)
    }
}
