import Foundation

struct SystemArtifactDetector: Sendable {
    private struct Definition: Sendable {
        let suffix: String
        let ecosystems: Set<DeveloperEcosystem>
        let kind: String
        let risk: ArtifactRisk
        let cleanup: CleanupPolicy
        let explanation: String
    }

    private let definitions: [Definition] = [
        .init(suffix: "/Library/Developer/Xcode/DerivedData", ecosystems: [.apple], kind: "Xcode DerivedData", risk: .rebuildable, cleanup: .safeRebuildable, explanation: "Xcode indexes and build output recreated by Xcode."),
        .init(suffix: "/Library/Developer/Xcode/Archives", ecosystems: [.apple], kind: "Xcode Archives", risk: .reviewFirst, cleanup: .none, explanation: "Archived builds may be required for symbolication or distribution."),
        .init(suffix: "/Library/Developer/Xcode/iOS DeviceSupport", ecosystems: [.apple], kind: "Device Support", risk: .redownloadable, cleanup: .none, explanation: "Support files downloaded for connected Apple devices."),
        .init(suffix: "/Library/Developer/CoreSimulator", ecosystems: [.apple], kind: "CoreSimulator", risk: .toolManaged, cleanup: .none, explanation: "Simulator runtimes and device data. Manage them with Xcode."),
        .init(suffix: "/.gradle/caches", ecosystems: [.android, .jvm], kind: "Gradle Cache", risk: .redownloadable, cleanup: .none, explanation: "Global Gradle artifacts that may need to be downloaded again."),
        .init(suffix: "/.android/avd", ecosystems: [.android], kind: "Android Virtual Devices", risk: .toolManaged, cleanup: .none, explanation: "Android emulator devices. Manage them with Android Studio."),
        .init(suffix: "/Library/Android/sdk", ecosystems: [.android], kind: "Android SDK", risk: .toolManaged, cleanup: .none, explanation: "Installed Android SDKs and system images."),
        .init(suffix: "/Library/Android/sdk/system-images", ecosystems: [.android], kind: "Android System Images", risk: .toolManaged, cleanup: .none, explanation: "Emulator system images managed by the Android SDK Manager."),
        .init(suffix: "/.pub-cache", ecosystems: [.flutter], kind: "Pub Cache", risk: .redownloadable, cleanup: .none, explanation: "Downloaded Dart and Flutter packages."),
        .init(suffix: "/.npm", ecosystems: [.node], kind: "npm Cache", risk: .redownloadable, cleanup: .none, explanation: "npm download cache."),
        .init(suffix: "/Library/pnpm/store", ecosystems: [.node], kind: "pnpm Store", risk: .redownloadable, cleanup: .none, explanation: "Content-addressed pnpm package store."),
        .init(suffix: "/Library/Caches/Yarn", ecosystems: [.node], kind: "Yarn Cache", risk: .redownloadable, cleanup: .none, explanation: "Yarn package cache."),
        .init(suffix: "/Library/Caches/Homebrew", ecosystems: [.homebrew], kind: "Homebrew Cache", risk: .toolManaged, cleanup: .none, explanation: "Homebrew downloads. Prefer brew cleanup."),
        .init(suffix: "/Library/Caches/Homebrew/downloads", ecosystems: [.homebrew], kind: "Homebrew Downloads", risk: .toolManaged, cleanup: .none, explanation: "Homebrew downloads managed by Homebrew."),
        .init(suffix: "/opt/homebrew/Cellar", ecosystems: [.homebrew], kind: "Homebrew Installed Versions", risk: .toolManaged, cleanup: .none, explanation: "Installed formula versions managed by Homebrew."),
        .init(suffix: "/usr/local/Cellar", ecosystems: [.homebrew], kind: "Homebrew Installed Versions", risk: .toolManaged, cleanup: .none, explanation: "Installed formula versions managed by Homebrew."),
        .init(suffix: "/.cargo/registry", ecosystems: [.rust], kind: "Cargo Registry", risk: .redownloadable, cleanup: .none, explanation: "Downloaded Cargo registry packages."),
        .init(suffix: "/.cargo/git", ecosystems: [.rust], kind: "Cargo Git Cache", risk: .redownloadable, cleanup: .none, explanation: "Git dependencies cached by Cargo."),
        .init(suffix: "/.conan", ecosystems: [.cpp], kind: "Conan Cache", risk: .redownloadable, cleanup: .none, explanation: "Conan package cache."),
        .init(suffix: "/.cache/vcpkg", ecosystems: [.cpp], kind: "vcpkg Cache", risk: .redownloadable, cleanup: .none, explanation: "vcpkg package cache."),
        .init(suffix: "/Library/Containers/com.docker.docker", ecosystems: [.docker], kind: "Docker Storage", risk: .toolManaged, cleanup: .none, explanation: "Docker images, containers and volumes. Manage them with Docker."),
        .init(suffix: "/.docker", ecosystems: [.docker], kind: "Docker Configuration", risk: .userData, cleanup: .none, explanation: "Docker configuration and contexts.")
    ]

    func detect(nodes: [FileNode]) -> [DeveloperArtifact] {
        nodes.compactMap { node in
            guard node.isDirectory else { return nil }
            let path = node.url.path(percentEncoded: false)
            guard let definition = definitions.first(where: { path.hasSuffix($0.suffix) }) else {
                return nil
            }
            return DeveloperArtifact(
                id: node.url,
                url: node.url,
                project: nil,
                ecosystems: definition.ecosystems,
                logicalSize: node.logicalSize,
                allocatedSize: node.allocatedSize,
                artifactKind: definition.kind,
                risk: definition.risk,
                cleanupPolicy: definition.cleanup,
                explanation: definition.explanation,
                validationMarkerURLs: []
            )
        }
    }
}
