import Foundation

struct ArtifactCleanupService: CleanupServicing {
    func validateForCleanup(_ artifact: DeveloperArtifact) -> Bool {
        guard artifact.cleanupPolicy == .safeRebuildable,
              artifact.risk == .rebuildable,
              artifact.url.path != "/",
              artifact.url.path != FileManager.default.homeDirectoryForCurrentUser.path,
              FileManager.default.fileExists(atPath: artifact.url.path)
        else { return false }
        guard let values = try? artifact.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else { return false }

        if artifact.artifactKind == "Xcode DerivedData" {
            let expected = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Developer/Xcode/DerivedData")
                .standardizedFileURL.path
            return FileSystemDiskScanner.logicalPath(artifact.url.standardizedFileURL.path) == expected
        }

        guard let project = artifact.project else { return false }
        let artifactPath = artifact.url.standardizedFileURL.path
        let projectPath = project.rootURL.standardizedFileURL.path
        guard artifactPath.hasPrefix(projectPath + "/"), matchesSafeType(artifact) else { return false }

        return artifact.validationMarkerURLs.contains { marker in
            marker.deletingLastPathComponent().standardizedFileURL == project.rootURL.standardizedFileURL
                && FileManager.default.fileExists(atPath: marker.path)
                && markerIsValid(marker.lastPathComponent, for: artifact.artifactKind)
        }
    }

    func moveToTrash(_ artifact: DeveloperArtifact) throws {
        guard validateForCleanup(artifact) else { throw CleanupError.validationFailed }
        try FileManager.default.trashItem(at: artifact.url, resultingItemURL: nil)
    }

    enum CleanupError: LocalizedError {
        case validationFailed
        var errorDescription: String? {
            "The artifact changed or is no longer verified as safe to rebuild."
        }
    }

    private func matchesSafeType(_ artifact: DeveloperArtifact) -> Bool {
        let name = artifact.url.lastPathComponent
        switch artifact.artifactKind {
        case "SwiftPM Build": return name == ".build"
        case "Flutter Build Output": return name == "build" || name == ".dart_tool"
        case "Web Build Cache":
            return [".next", ".nuxt", ".vite", ".turbo", "cache", ".cache"].contains(name)
        case "Rust Target": return name == "target"
        case "Android Build Output": return name == "build"
        case "CMake Build":
            return FileManager.default.fileExists(atPath: artifact.url.appending(path: "CMakeCache.txt").path)
                || FileManager.default.fileExists(atPath: artifact.url.appending(path: "CMakeFiles").path)
        case "Python Bytecode": return name == "__pycache__"
        default: return false
        }
    }

    private func markerIsValid(_ marker: String, for kind: String) -> Bool {
        switch kind {
        case "SwiftPM Build": return marker == "Package.swift"
        case "Flutter Build Output": return marker == "pubspec.yaml"
        case "Web Build Cache": return marker == "package.json"
        case "Rust Target": return marker == "Cargo.toml"
        case "Android Build Output":
            return ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pubspec.yaml"].contains(marker)
        case "CMake Build": return marker == "CMakeLists.txt"
        case "Python Bytecode": return marker == "pyproject.toml" || marker == "requirements.txt"
        default: return false
        }
    }
}
