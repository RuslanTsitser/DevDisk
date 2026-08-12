import Foundation

struct ArtifactCleanupService: CleanupServicing {
    func validateForCleanup(_ artifact: DeveloperArtifact) -> Bool {
        guard artifact.cleanupPolicy == .safeRebuildable,
              artifact.risk == .rebuildable,
              FileSystemDiskScanner.logicalPath(artifact.url.path) != "/",
              artifact.url.standardizedFileURL != UserHomeDirectory.current,
              FileManager.default.fileExists(atPath: artifact.url.path)
        else { return false }
        guard let values = try? artifact.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else { return false }

        if artifact.artifactKind == "Xcode Project DerivedData" {
            return validateXcodeProjectDerivedData(artifact)
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
            guard let project = artifact.project else { return false }
            return isConfirmedWebCache(artifact.url, project: project)
        case "Rust Target":
            guard let project = artifact.project else { return false }
            if name == "target" { return true }
            return CargoConfiguration.configuredTarget(projectRoot: project.rootURL)?.url.standardizedFileURL
                == artifact.url.standardizedFileURL
        case "Android Build Output": return name == "build"
        case "CMake Build":
            guard let project = artifact.project,
                  FileManager.default.fileExists(atPath: artifact.url.appending(path: "CMakeFiles").path),
                  let cache = try? String(
                    contentsOf: artifact.url.appending(path: "CMakeCache.txt"),
                    encoding: .utf8
                  ),
                  let sourceLine = cache.split(whereSeparator: \.isNewline).first(where: {
                      $0.hasPrefix("CMAKE_HOME_DIRECTORY:INTERNAL=")
                  }),
                  let separator = sourceLine.firstIndex(of: "=")
            else { return false }
            let sourcePath = String(sourceLine[sourceLine.index(after: separator)...])
            return URL(filePath: sourcePath, directoryHint: .isDirectory).standardizedFileURL
                == project.rootURL.standardizedFileURL
        case "Python Bytecode": return name == "__pycache__"
        default: return false
        }
    }

    private func validateXcodeProjectDerivedData(_ artifact: DeveloperArtifact) -> Bool {
        guard let project = artifact.project else { return false }
        let artifactURL = artifact.url.standardizedFileURL
        let isInsideAllowedRoot = XcodeStorageLocations.allowedDerivedDataURLs(
            homeDirectory: UserHomeDirectory.current
        ).contains { artifactURL.deletingLastPathComponent() == $0.standardizedFileURL }
        guard isInsideAllowedRoot,
              let data = try? Data(contentsOf: artifactURL.appending(path: "info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let workspacePath = info["WorkspacePath"] as? String
        else { return false }
        let workspaceURL = URL(filePath: workspacePath).standardizedFileURL
        let projectRoot = project.rootURL.standardizedFileURL
        return workspaceURL.path.hasPrefix(projectRoot.path + "/")
            && artifact.validationMarkerURLs.contains(workspaceURL)
            && FileManager.default.fileExists(atPath: workspaceURL.path)
    }

    private func markerIsValid(_ marker: String, for kind: String) -> Bool {
        switch kind {
        case "SwiftPM Build": return marker == "Package.swift"
        case "Flutter Build Output": return marker == "pubspec.yaml"
        case "Web Build Cache": return marker == "package.json"
        case "Rust Target": return marker == "Cargo.toml"
        case "Android Build Output":
            return ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"].contains(marker)
        case "CMake Build": return marker == "CMakeLists.txt"
        case "Python Bytecode": return marker == "pyproject.toml" || marker == "requirements.txt"
        default: return false
        }
    }

    private func isConfirmedWebCache(_ url: URL, project: DeveloperProject) -> Bool {
        let packageURL = project.rootURL.appending(path: "package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        var tools: Set<String> = []
        for key in ["dependencies", "devDependencies", "optionalDependencies"] {
            guard let dependencies = package[key] as? [String: Any] else { continue }
            tools.formUnion(dependencies.keys)
        }
        let projectPath = project.rootURL.standardizedFileURL.path
        let artifactPath = url.standardizedFileURL.path
        guard artifactPath.hasPrefix(projectPath + "/") else { return false }
        let relative = String(artifactPath.dropFirst(projectPath.count + 1))
        switch relative {
        case ".next": return tools.contains("next")
        case ".nuxt": return tools.contains("nuxt")
        case ".vite", "node_modules/.vite": return tools.contains("vite")
        case ".turbo": return tools.contains("turbo")
        case ".nx/cache": return tools.contains("nx") || tools.contains { $0.hasPrefix("@nx/") }
        case "node_modules/.cache":
            let producers: Set<String> = [
                "react-scripts", "webpack", "parcel", "@parcel/core", "babel-loader",
                "eslint", "vite", "next", "nuxt"
            ]
            return !tools.isDisjoint(with: producers)
        default: return false
        }
    }
}
