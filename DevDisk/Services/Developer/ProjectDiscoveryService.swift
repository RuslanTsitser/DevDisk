import Foundation

struct ProjectDiscoveryService: ProjectDiscovering {
    private let excludedUserPaths: [String]

    init(homeDirectory: URL = UserHomeDirectory.current) {
        excludedUserPaths = Self.excludedUserRoots.map {
            homeDirectory.standardizedFileURL.appending(path: $0).path
        }
    }

    private static let generatedOrDependencyDirectories: Set<String> = [
        ".build", ".cache", ".cargo", ".conan", ".dart_tool", ".git", ".gradle", ".npm",
        ".pub-cache", "build", "Cache", "Caches", "CMakeFiles", "CoreSimulator", "DerivedData",
        "node_modules", "Pods", "target"
    ]

    private static let markerEcosystems: [String: Set<DeveloperEcosystem>] = [
        "pubspec.yaml": [.flutter],
        "package.json": [.node],
        "Cargo.toml": [.rust],
        "CMakeLists.txt": [.cpp],
        "build.gradle": [.android, .jvm],
        "build.gradle.kts": [.android, .jvm],
        "settings.gradle": [.android, .jvm],
        "settings.gradle.kts": [.android, .jvm],
        "pom.xml": [.jvm],
        "Package.swift": [.apple],
        "Podfile": [.apple],
        "pyproject.toml": [.python],
        "requirements.txt": [.python],
        ".git": [.git]
    ]

    private static let packageExtensions = [".app", ".bundle", ".framework", ".xcframework", ".simruntime"]
    private static let excludedSystemRoots = ["/Applications", "/Library", "/System", "/private", "/opt/homebrew"]
    private static let excludedUserRoots = [
        "Library/Application Support", "Library/Caches", "Library/Containers",
        "Library/Developer", "Library/Group Containers", "Library/Logs", "Library/WebKit",
        ".android", ".cache", ".cargo", ".claude", ".cocoapods", ".codex",
        ".cursor", ".docker", ".gradle", ".local", ".npm", ".pub-cache", ".rustup",
        ".vscode", "fvm/versions"
    ]

    func discoverProjects(in root: FileNode) -> [DeveloperProject] {
        var byRoot: [URL: (ecosystems: Set<DeveloperEcosystem>, markers: Set<URL>)] = [:]
        var pending = [root]
        while let node = pending.popLast() {
            if var ecosystems = Self.markerEcosystems[node.name] {
                if node.name == "package.json", Self.isWebPackage(at: node.url) {
                    ecosystems.insert(.web)
                }
                let projectRoot = node.url.deletingLastPathComponent()
                byRoot[projectRoot, default: ([], [])].ecosystems.formUnion(ecosystems)
                byRoot[projectRoot, default: ([], [])].markers.insert(node.url)
            } else if node.name.hasSuffix(".xcodeproj") || node.name.hasSuffix(".xcworkspace") {
                let projectRoot = node.url.deletingLastPathComponent()
                byRoot[projectRoot, default: ([], [])].ecosystems.insert(.apple)
                byRoot[projectRoot, default: ([], [])].markers.insert(node.url)
            }
            if let children = node.children, shouldTraverse(node) {
                pending.append(contentsOf: children)
            }
        }

        return byRoot.map { rootURL, value in
            var ecosystems = value.ecosystems
            if ecosystems.contains(.flutter) {
                ecosystems.formUnion([.apple, .android])
            }
            return DeveloperProject(
                rootURL: rootURL,
                ecosystems: ecosystems,
                markerURLs: value.markers
            )
        }.sorted { $0.rootURL.path < $1.rootURL.path }
    }

    private func shouldTraverse(_ node: FileNode) -> Bool {
        guard !Self.generatedOrDependencyDirectories.contains(node.name) else { return false }
        guard !Self.packageExtensions.contains(where: { node.name.hasSuffix($0) }) else { return false }

        let path = FileSystemDiskScanner.logicalPath(node.url.standardizedFileURL.path)
        if Self.excludedSystemRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }
        return !excludedUserPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func isWebPackage(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        var dependencies: Set<String> = []
        for key in ["dependencies", "devDependencies", "optionalDependencies"] {
            guard let values = package[key] as? [String: Any] else { continue }
            dependencies.formUnion(values.keys)
        }
        let webPackages: Set<String> = [
            "react", "react-dom", "react-scripts", "next", "vue", "nuxt", "vite",
            "webpack", "parcel", "@parcel/core", "turbo", "nx", "remotion", "@remotion/cli"
        ]
        return !dependencies.isDisjoint(with: webPackages)
            || dependencies.contains { $0.hasPrefix("@nx/") || $0.hasPrefix("@angular/") }
    }
}
