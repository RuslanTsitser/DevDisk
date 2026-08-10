import Foundation

struct DeveloperArtifact: Hashable, Sendable {
    enum Ecosystem: String, Hashable, Sendable {
        case apple = "Apple"
        case android = "Android"
        case flutter = "Flutter"
        case web = "Web"
        case node = "Node.js"
        case homebrew = "Homebrew"
        case rust = "Rust"
        case cpp = "C/C++"
        case other = "Other"
    }

    enum RemovalRisk: String, Hashable, Sendable {
        case rebuildable = "Rebuildable"
        case redownloadable = "Redownloadable"
        case reviewFirst = "Review first"
    }

    let ecosystem: Ecosystem
    let kind: String
    let removalRisk: RemovalRisk
}

