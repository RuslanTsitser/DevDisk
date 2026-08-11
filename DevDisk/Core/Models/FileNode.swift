import Foundation

enum FileAccessStatus: String, Codable, Hashable, Sendable {
    case readable
    case partial
    case inaccessible
}

struct FileNode: Codable, Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let logicalSize: Int64
    let allocatedSize: Int64
    let fileCount: Int
    let modifiedAt: Date?
    let accessStatus: FileAccessStatus
    let children: [FileNode]?

    var isDirectory: Bool { children != nil }

    init(
        id: URL,
        url: URL,
        name: String,
        logicalSize: Int64? = nil,
        allocatedSize: Int64,
        fileCount: Int,
        modifiedAt: Date? = nil,
        accessStatus: FileAccessStatus = .readable,
        children: [FileNode]?
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.logicalSize = logicalSize ?? allocatedSize
        self.allocatedSize = allocatedSize
        self.fileCount = fileCount
        self.modifiedAt = modifiedAt
        self.accessStatus = accessStatus
        self.children = children
    }

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
            logicalSize: updatedChildren.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: updatedChildren.reduce(0) { $0 + $1.allocatedSize },
            fileCount: updatedChildren.reduce(0) { $0 + $1.fileCount },
            modifiedAt: modifiedAt,
            accessStatus: accessStatus,
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
            logicalSize: updatedChildren.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: updatedChildren.reduce(0) { $0 + $1.allocatedSize },
            fileCount: updatedChildren.reduce(0) { $0 + $1.fileCount },
            modifiedAt: modifiedAt,
            accessStatus: accessStatus,
            children: updatedChildren
        )
    }
}
