import Foundation

struct FileNode: Codable, Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let logicalSize: Int64
    let allocatedSize: Int64
    let fileCount: Int
    let artifact: DeveloperArtifact?
    let children: [FileNode]?

    var isDirectory: Bool { children != nil }

    func removing(_ target: URL) -> FileNode? {
        guard url != target else { return nil }
        guard let children else { return self }
        let updatedChildren = children.compactMap { $0.removing(target) }
        return FileNode(
            id: id,
            url: url,
            name: name,
            logicalSize: updatedChildren.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: updatedChildren.reduce(0) { $0 + $1.allocatedSize },
            fileCount: updatedChildren.reduce(0) { $0 + $1.fileCount },
            artifact: artifact,
            children: updatedChildren
        )
    }
}
