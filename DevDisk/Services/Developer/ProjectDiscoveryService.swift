import Foundation

struct ProjectDiscoveryService: ProjectDiscovering {
    private static let markerEcosystems: [String: Set<DeveloperEcosystem>] = [
        "pubspec.yaml": [.flutter],
        "package.json": [.web, .node],
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

    func discoverProjects(in root: FileNode) -> [DeveloperProject] {
        var byRoot: [URL: (ecosystems: Set<DeveloperEcosystem>, markers: Set<URL>)] = [:]
        var pending = [root]
        while let node = pending.popLast() {
            if let ecosystems = Self.markerEcosystems[node.name] {
                let projectRoot = node.url.deletingLastPathComponent()
                byRoot[projectRoot, default: ([], [])].ecosystems.formUnion(ecosystems)
                byRoot[projectRoot, default: ([], [])].markers.insert(node.url)
            } else if node.name.hasSuffix(".xcodeproj") || node.name.hasSuffix(".xcworkspace") {
                let projectRoot = node.url.deletingLastPathComponent()
                byRoot[projectRoot, default: ([], [])].ecosystems.insert(.apple)
                byRoot[projectRoot, default: ([], [])].markers.insert(node.url)
            }
            if let children = node.children { pending.append(contentsOf: children) }
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
}
