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
        guard Self.contains(target, in: url) else { return nil }
        var current = self
        while current.url.standardizedFileURL != target.standardizedFileURL {
            guard let next = current.children?.first(where: {
                Self.contains(target, in: $0.url)
            }) else { return nil }
            current = next
        }
        return current
    }

    func replacing(_ replacement: FileNode) -> FileNode {
        guard url.standardizedFileURL != replacement.url.standardizedFileURL else {
            return replacement
        }
        guard let children, Self.contains(replacement.url, in: url) else { return self }
        var didReplace = false
        let updatedChildren = children.map { child in
            guard Self.contains(replacement.url, in: child.url) else { return child }
            didReplace = true
            return child.replacing(replacement)
        }
        guard didReplace else { return self }
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
        guard let children, Self.contains(target, in: url), url != target else { return self }
        var didRemove = false
        let updatedChildren = children.compactMap { child -> FileNode? in
            if child.url.standardizedFileURL == target.standardizedFileURL {
                didRemove = true
                return nil
            }
            guard Self.contains(target, in: child.url) else { return child }
            let updated = child.removing(target)
            didRemove = updated != child
            return updated
        }
        guard didRemove else { return self }
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

    private static func contains(_ target: URL, in ancestor: URL) -> Bool {
        let targetPath = target.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        if targetPath == ancestorPath { return true }
        let prefix = ancestorPath == "/" ? "/" : ancestorPath + "/"
        return targetPath.hasPrefix(prefix)
    }
}
