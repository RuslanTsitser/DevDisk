import Foundation

struct FileNode: Codable, Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let allocatedSize: Int64
    let fileCount: Int
    let children: [FileNode]?

    var isDirectory: Bool { children != nil }

    func node(at target: URL) -> FileNode? {
        guard url != target else { return self }
        return children?.lazy.compactMap { $0.node(at: target) }.first
    }

    func replacing(_ replacement: FileNode) -> FileNode {
        guard url != replacement.url else { return replacement }
        guard let children else { return self }
        let updatedChildren = children.map { $0.replacing(replacement) }
        return FileNode(
            id: id,
            url: url,
            name: name,
            allocatedSize: updatedChildren.reduce(0) { $0 + $1.allocatedSize },
            fileCount: updatedChildren.reduce(0) { $0 + $1.fileCount },
            children: updatedChildren
        )
    }

    func removing(_ target: URL) -> FileNode {
        guard let children else { return self }
        let updatedChildren = children
            .filter { $0.url != target }
            .map { $0.removing(target) }
        return FileNode(
            id: id,
            url: url,
            name: name,
            allocatedSize: updatedChildren.reduce(0) { $0 + $1.allocatedSize },
            fileCount: updatedChildren.reduce(0) { $0 + $1.fileCount },
            children: updatedChildren
        )
    }
}
