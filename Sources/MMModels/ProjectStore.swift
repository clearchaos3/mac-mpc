import Foundation

/// Reads/writes a project as a `.macmpc` directory bundle:
///
///     MyBeat.macmpc/
///       project.json     — the encoded Project
///       samples/         — copies of every referenced sample
///
/// Samples are copied into the bundle so a project is portable. On load we
/// prefer the sample at its original absolute path, falling back to the
/// bundled copy if the original has moved.
public enum ProjectStore {
    public static let fileExtension = "macmpc"

    public enum StoreError: Error { case noProjectJSON }

    public static func save(_ project: Project, to bundleURL: URL) throws {
        let fm = FileManager.default
        let samplesDir = bundleURL.appendingPathComponent("samples", isDirectory: true)
        try fm.createDirectory(at: samplesDir, withIntermediateDirectories: true)

        for (_, pad) in project.pads {
            guard let url = pad.sampleURL else { continue }
            let dest = samplesDir.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: url, to: dest)
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: bundleURL.appendingPathComponent("project.json"), options: .atomic)
    }

    public static func load(from bundleURL: URL) throws -> Project {
        let fm = FileManager.default
        let jsonURL = bundleURL.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: jsonURL.path) else { throw StoreError.noProjectJSON }

        let data = try Data(contentsOf: jsonURL)
        var project = try JSONDecoder().decode(Project.self, from: data)

        let samplesDir = bundleURL.appendingPathComponent("samples", isDirectory: true)
        for (addr, pad) in project.pads {
            guard let url = pad.sampleURL else { continue }
            if fm.fileExists(atPath: url.path) { continue }
            let fallback = samplesDir.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: fallback.path) {
                project.pads[addr]?.sampleURL = fallback
            }
        }
        return project
    }
}
