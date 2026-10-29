import AppKit

enum FileDropAction: String, CaseIterable, Identifiable {
    case trash
    case raycast

    var id: String { rawValue }
    var title: String { self == .trash ? "Move to Trash" : "Send to Raycast" }
}

enum RaycastHandoff {
    enum SetupFailure: LocalizedError {
        case missingCompanion, couldNotOpenInstructions

        var errorDescription: String? {
            switch self {
            case .missingCompanion: "The companion is missing. Rebuild or reinstall Notch Monster."
            case .couldNotOpenInstructions: "The setup files were copied, but the instructions could not be opened."
            }
        }
    }

    enum Failure: LocalizedError {
        case notInstalled, invalidFiles, couldNotOpen

        var errorDescription: String? {
            switch self {
            case .notInstalled: "Install Raycast to use this action. Your files were kept."
            case .invalidFiles: "One of these files is no longer available. Your files were kept."
            case .couldNotOpen: "Could not open Raycast. Your files were kept."
            }
        }
    }

    static func url(for files: [URL]) throws -> URL {
        guard !files.isEmpty, files.allSatisfy(\.isFileURL) else { throw Failure.invalidFiles }
        let paths = files.map { $0.standardizedFileURL.path }
        let context = try JSONSerialization.data(withJSONObject: ["paths": paths])
        var components = URLComponents()
        components.scheme = "raycast"
        components.host = "extensions"
        components.path = "/notchmonster/notch-monster/file-actions"
        components.queryItems = [URLQueryItem(name: "context", value: String(decoding: context, as: UTF8.self))]
        guard let url = components.url else { throw Failure.couldNotOpen }
        return url
    }

    @MainActor
    static func send(_ files: [URL]) throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.raycast.macos") != nil else {
            throw Failure.notInstalled
        }
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw Failure.invalidFiles
        }
        guard NSWorkspace.shared.open(try url(for: files)) else { throw Failure.couldNotOpen }
    }

    @MainActor
    static func showSetup() throws {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("Raycast") else {
            throw SetupFailure.missingCompanion
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let destination = support.appendingPathComponent("Notch Monster/Raycast", isDirectory: true)
        try copyCompanion(from: source, to: destination)
        guard NSWorkspace.shared.open(destination.appendingPathComponent("README.md")) else {
            throw SetupFailure.couldNotOpenInstructions
        }
    }

    static func copyCompanion(from source: URL, to destination: URL) throws {
        // Refresh only the source files shipped by this app. Keep installed
        // dependencies and Raycast's generated files in this writable folder.
        let relativePaths = ["package.json", "package-lock.json", "tsconfig.json", "README.md", "src/file-actions.tsx", "assets/icon.png"]
        let files = try relativePaths.map { path in
            (path, try Data(contentsOf: source.appendingPathComponent(path)))
        }
        for (path, data) in files {
            let output = destination.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .atomic)
        }
    }
}
