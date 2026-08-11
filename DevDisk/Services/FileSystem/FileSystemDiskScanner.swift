import Foundation

struct FileSystemDiskScanner: DiskScanning {
    private let detector: any ArtifactDetecting

    init(detector: any ArtifactDetecting) {
        self.detector = detector
    }

    func scan(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler,
        onDirectoryScanned: @escaping ScannedDirectoryHandler
    ) async throws -> DiskScanResult {
        let didStartSecurityScope = root.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let worker = Task.detached(priority: .userInitiated) {
            let rootVolumeURL = try? root.resourceValues(forKeys: [.volumeURLKey]).volume
            var context = ScanContext(
                rootURL: root,
                rootVolumeURL: rootVolumeURL,
                onProgress: onProgress,
                onDirectoryScanned: onDirectoryScanned
            )
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
            .fileAllocatedSizeKey,
            .fileResourceIdentifierKey,
            .volumeIdentifierKey,
            .volumeURLKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        let isDirectory = values.isDirectory == true
        let isSymbolicLink = values.isSymbolicLink == true
        let isRootChildDirectory = context.isRootChild(url) && isDirectory && !isSymbolicLink

        if isRootChildDirectory {
            context.reportDirectory(url, status: .scanning)
        }

        if context.shouldExclude(url, values: values) {
            if isRootChildDirectory { context.reportDirectory(url, status: .skipped) }
            throw TraversalError.excluded
        }
        if !isSymbolicLink, !context.registerIfNew(values) {
            if isRootChildDirectory { context.reportDirectory(url, status: .skipped) }
            throw TraversalError.excluded
        }

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

        let skippedBeforeScan = context.skippedItemCount
        let childURLs = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if url == context.rootURL {
            for childURL in childURLs {
                let childValues = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if childValues?.isDirectory == true, childValues?.isSymbolicLink != true {
                    context.reportDirectory(childURL, status: .waiting)
                }
            }
        }
        let children = try childURLs.compactMap { childURL in
            do {
                return try scanNode(childURL, context: &context)
            } catch let error as CancellationError {
                throw error
            } catch TraversalError.excluded {
                return nil
            } catch {
                context.recordSkippedItem()
                if context.isRootChild(childURL) {
                    context.reportDirectory(childURL, status: .failed(error.localizedDescription))
                }
                return nil
            }
        }.sorted { $0.allocatedSize > $1.allocatedSize }

        let node = FileNode(
            id: url,
            url: url,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            logicalSize: children.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            artifact: detector.detect(url: url, isDirectory: true),
            children: children
        )
        if isRootChildDirectory {
            let skippedInDirectory = context.skippedItemCount - skippedBeforeScan
            let status: ScannedDirectory.Status = skippedInDirectory == 0
                ? .completed
                : .partial(skippedItemCount: skippedInDirectory)
            context.reportDirectory(
                url,
                status: status,
                allocatedSize: node.allocatedSize,
                fileCount: node.fileCount
            )
        }
        return node
    }

    private enum TraversalError: Error {
        case excluded
    }

    private struct ScanContext {
        let rootURL: URL
        let rootVolumeURL: URL?
        let onProgress: DiskScanProgressHandler
        let onDirectoryScanned: ScannedDirectoryHandler
        private(set) var itemsScanned = 0
        private(set) var skippedItemCount = 0
        private var visitedItems: Set<FileIdentity> = []

        init(
            rootURL: URL,
            rootVolumeURL: URL?,
            onProgress: @escaping DiskScanProgressHandler,
            onDirectoryScanned: @escaping ScannedDirectoryHandler
        ) {
            self.rootURL = rootURL
            self.rootVolumeURL = rootVolumeURL
            self.onProgress = onProgress
            self.onDirectoryScanned = onDirectoryScanned
        }

        func shouldExclude(_ url: URL, values: URLResourceValues) -> Bool {
            guard url != rootURL else { return false }

            if rootURL.path == "/" {
                if url.path == "/.nofollow" || url.path == "/System/Volumes/Data" {
                    return true
                }
            }

            guard let rootVolumeURL, let itemVolumeURL = values.volume else { return false }
            let standardizedItemVolume = itemVolumeURL.standardizedFileURL
            return standardizedItemVolume != rootVolumeURL.standardizedFileURL
                && url.standardizedFileURL == standardizedItemVolume
        }

        mutating func registerIfNew(_ values: URLResourceValues) -> Bool {
            guard let fileIdentifier = values.fileResourceIdentifier else { return true }
            let identity = FileIdentity(
                volume: String(reflecting: values.volumeIdentifier),
                file: String(reflecting: fileIdentifier)
            )
            return visitedItems.insert(identity).inserted
        }

        mutating func recordSkippedItem() {
            skippedItemCount += 1
        }

        func isRootChild(_ url: URL) -> Bool {
            url.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL
        }

        func reportDirectory(
            _ url: URL,
            status: ScannedDirectory.Status,
            allocatedSize: Int64? = nil,
            fileCount: Int? = nil
        ) {
            onDirectoryScanned(
                ScannedDirectory(
                    url: url,
                    status: status,
                    allocatedSize: allocatedSize,
                    fileCount: fileCount
                )
            )
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

    private struct FileIdentity: Hashable {
        let volume: String
        let file: String
    }
}
