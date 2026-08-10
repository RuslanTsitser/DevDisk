import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let logicalSize: Int64
    let allocatedSize: Int64
    let fileCount: Int
    let artifact: DeveloperArtifact?
    let children: [FileNode]?

    var isDirectory: Bool { children != nil }
}

