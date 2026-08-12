import Foundation

enum DeveloperEcosystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case android
    case flutter
    case web
    case node
    case homebrew
    case rust
    case cpp
    case python
    case jvm
    case git
    case docker

    var id: String { rawValue }
    var title: String { rawValue == "cpp" ? "C/C++" : rawValue.capitalized }
}

enum ArtifactRisk: String, Codable, CaseIterable, Identifiable, Sendable {
    case rebuildable
    case redownloadable
    case toolManaged
    case reviewFirst
    case userData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rebuildable: "Rebuildable"
        case .redownloadable: "Redownloadable"
        case .toolManaged: "Tool managed"
        case .reviewFirst: "Review first"
        case .userData: "User data"
        }
    }
}

enum CleanupPolicy: String, Codable, Sendable {
    case safeRebuildable
    case none
}

enum DetectorScope: String, Codable, Sendable {
    case project
    case global
}

struct DetectorRule: Codable, Identifiable, Sendable {
    let id: String
    let scope: DetectorScope
    let ecosystems: Set<DeveloperEcosystem>
    let projectMarkers: Set<String>
    let pathPatterns: Set<String>
    let artifactKind: String
    let risk: ArtifactRisk
    let cleanupPolicy: CleanupPolicy
    let description: String
}

struct DeveloperProject: Identifiable, Hashable, Sendable {
    let rootURL: URL
    let ecosystems: Set<DeveloperEcosystem>
    let markerURLs: Set<URL>

    var id: URL { rootURL }
    var name: String { rootURL.lastPathComponent }
}

struct ArtifactLocationEvidence: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case projectMarker
        case toolConfiguration
        case environment
        case documentedDefault
        case toolMetadata

        var title: String {
            switch self {
            case .projectMarker: "Project marker"
            case .toolConfiguration: "Tool configuration"
            case .environment: "Environment configuration"
            case .documentedDefault: "Documented default"
            case .toolMetadata: "Tool metadata"
            }
        }
    }

    let kind: Kind
    let detail: String
    let documentationURL: URL?
}

struct DeveloperArtifact: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let project: DeveloperProject?
    let ecosystems: Set<DeveloperEcosystem>
    let logicalSize: Int64
    let allocatedSize: Int64
    let artifactKind: String
    let risk: ArtifactRisk
    let cleanupPolicy: CleanupPolicy
    let explanation: String
    let validationMarkerURLs: Set<URL>
    let locationEvidence: ArtifactLocationEvidence

    var name: String { url.lastPathComponent }

    init(
        id: URL,
        url: URL,
        project: DeveloperProject?,
        ecosystems: Set<DeveloperEcosystem>,
        logicalSize: Int64,
        allocatedSize: Int64,
        artifactKind: String,
        risk: ArtifactRisk,
        cleanupPolicy: CleanupPolicy,
        explanation: String,
        validationMarkerURLs: Set<URL>,
        locationEvidence: ArtifactLocationEvidence? = nil
    ) {
        self.id = id
        self.url = url
        self.project = project
        self.ecosystems = ecosystems
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.artifactKind = artifactKind
        self.risk = risk
        self.cleanupPolicy = cleanupPolicy
        self.explanation = explanation
        self.validationMarkerURLs = validationMarkerURLs
        self.locationEvidence = locationEvidence ?? ArtifactLocationEvidence(
            kind: project == nil ? .documentedDefault : .projectMarker,
            detail: project.map { "Detected relative to \($0.name)" } ?? "Detected from a known tool location",
            documentationURL: nil
        )
    }
}

struct DeveloperInsights: Sendable {
    let projects: [DeveloperProject]
    let artifacts: [DeveloperArtifact]

    static let empty = DeveloperInsights(projects: [], artifacts: [])

    /// Artifacts can be nested (for example an Android build inside Flutter's build
    /// directory). Keep all detections for filtering and explanation, while using
    /// only the outermost paths for storage totals so bytes are never counted twice.
    var storageAccountingArtifacts: [DeveloperArtifact] {
        let ordered = artifacts.sorted {
            let leftDepth = $0.url.standardizedFileURL.pathComponents.count
            let rightDepth = $1.url.standardizedFileURL.pathComponents.count
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            return $0.url.path < $1.url.path
        }
        var accepted: [DeveloperArtifact] = []
        for artifact in ordered {
            let path = artifact.url.standardizedFileURL.path
            let isNested = accepted.contains {
                let parent = $0.url.standardizedFileURL.path
                return path.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
            }
            if !isNested { accepted.append(artifact) }
        }
        return accepted
    }

    var allocatedSize: Int64 {
        storageAccountingArtifacts.reduce(0) { partial, artifact in
            let (sum, overflow) = partial.addingReportingOverflow(artifact.allocatedSize)
            return overflow ? .max : sum
        }
    }
}
