import Foundation

struct FileSystemDiskScanner: DiskScanning {
    private let detector: any ArtifactDetecting

    init(detector: any ArtifactDetecting) {
        self.detector = detector
    }

    func scan(_ root: URL) async throws -> FileNode {
        let didStartSecurityScope = root.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                root.stopAccessingSecurityScopedResource()
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            try scanNode(root)
        }.value
    }

    private func scanNode(_ url: URL) throws -> FileNode {
        try Task.checkCancellation()

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        let isDirectory = values.isDirectory == true
        let isSymbolicLink = values.isSymbolicLink == true

        guard isDirectory, !isSymbolicLink else {
            return FileNode(
                id: url,
                url: url,
                name: url.lastPathComponent,
                logicalSize: Int64(values.fileSize ?? 0),
                allocatedSize: Int64(values.fileAllocatedSize ?? values.fileSize ?? 0),
                fileCount: 1,
                artifact: detector.detect(url: url, isDirectory: false),
                children: nil
            )
        }

        let childURLs = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        )
        let children = childURLs.compactMap { childURL in
            try? scanNode(childURL)
        }.sorted { $0.allocatedSize > $1.allocatedSize }

        return FileNode(
            id: url,
            url: url,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            logicalSize: children.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            artifact: detector.detect(url: url, isDirectory: true),
            children: children
        )
    }
}
