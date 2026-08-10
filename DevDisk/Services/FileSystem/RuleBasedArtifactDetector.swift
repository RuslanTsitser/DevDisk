import Foundation

struct RuleBasedArtifactDetector: ArtifactDetecting {
    func detect(url: URL, isDirectory: Bool) -> DeveloperArtifact? {
        guard isDirectory else { return nil }

        let path = url.path(percentEncoded: false)
        let name = url.lastPathComponent

        if path.contains("/Library/Developer/Xcode/DerivedData") {
            return .init(ecosystem: .apple, kind: "Xcode Derived Data", removalRisk: .rebuildable)
        }
        if path.contains("/Library/Developer/CoreSimulator") {
            return .init(ecosystem: .apple, kind: "Simulator data", removalRisk: .reviewFirst)
        }
        if name == ".gradle" {
            return .init(ecosystem: .android, kind: "Gradle data", removalRisk: .redownloadable)
        }
        if name == ".pub-cache" {
            return .init(ecosystem: .flutter, kind: "Pub cache", removalRisk: .redownloadable)
        }
        if name == "node_modules" {
            return .init(ecosystem: .node, kind: "Node dependencies", removalRisk: .redownloadable)
        }
        if name == ".next" || name == ".nuxt" {
            return .init(ecosystem: .web, kind: "Web framework build cache", removalRisk: .rebuildable)
        }
        if path.contains("/Library/Caches/Homebrew") {
            return .init(ecosystem: .homebrew, kind: "Homebrew cache", removalRisk: .redownloadable)
        }
        if name == "target" {
            return .init(ecosystem: .rust, kind: "Rust build output (unconfirmed)", removalRisk: .reviewFirst)
        }

        return nil
    }
}

