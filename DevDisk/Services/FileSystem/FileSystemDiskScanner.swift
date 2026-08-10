import Foundation

struct FileSystemDiskScanner: DiskScanning {
    private let detector: any ArtifactDetecting

    init(detector: any ArtifactDetecting) {
        self.detector = detector
    }

    func scan(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler
    ) async throws -> DiskScanResult {
        let didStartSecurityScope = root.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let worker = Task.detached(priority: .userInitiated) {
            var context = ScanContext(rootURL: root, onProgress: onProgress)
            let volumeValues = try? root.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            let node = try scanNode(root, context: &context)
            context.report(root, force: true)
            return DiskScanResult(
                root: node,
                skippedItemCount: context.skippedItemCount,
                volumeTotalCapacity: volumeValues?.volumeTotalCapacity.map(Int64.init),
                volumeAvailableCapacity: volumeValues?.volumeAvailableCapacity.map(Int64.init)
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func scanNode(_ url: URL, context: inout ScanContext) throws -> FileNode {
        try Task.checkCancellation()
        context.report(url)

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
        let children = try childURLs.compactMap { childURL in
            do {
                return try scanNode(childURL, context: &context)
            } catch let error as CancellationError {
                throw error
            } catch {
                context.recordSkippedItem()
                return nil
            }
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

    private struct ScanContext {
        let rootURL: URL
        let onProgress: DiskScanProgressHandler
        private(set) var itemsScanned = 0
        private(set) var skippedItemCount = 0

        mutating func recordSkippedItem() {
            skippedItemCount += 1
        }

        mutating func report(_ currentURL: URL, force: Bool = false) {
            if !force {
                itemsScanned += 1
            }

            guard force || itemsScanned == 1 || itemsScanned.isMultiple(of: 100) else {
                return
            }

            onProgress(
                ScanProgress(
                    rootURL: rootURL,
                    currentURL: currentURL,
                    itemsScanned: itemsScanned
                )
            )
        }
    }
}
