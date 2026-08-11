import Foundation

struct StubDiskScanner: DiskScanning {
    let result: DiskScanResult

    func scan(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler,
        onDirectoryScanned: @escaping ScannedDirectoryHandler
    ) async throws -> DiskScanResult {
        onProgress(
            ScanProgress(
                rootURL: root,
                currentURL: result.root.url,
                itemsScanned: result.root.fileCount
            )
        )
        onDirectoryScanned(
            ScannedDirectory(
                url: result.root.url,
                status: .completed,
                node: result.root
            )
        )
        return result
    }

    static let preview = StubDiskScanner(
        result: DiskScanResult(
            root: FileNode(
                id: URL(fileURLWithPath: "/Users/developer"),
                url: URL(fileURLWithPath: "/Users/developer"),
                name: "developer",
                allocatedSize: 84_000_000_000,
                fileCount: 420_000,
                children: [
                    FileNode(
                        id: URL(fileURLWithPath: "/Users/developer/Projects"),
                        url: URL(fileURLWithPath: "/Users/developer/Projects"),
                        name: "Projects",
                        allocatedSize: 51_000_000_000,
                        fileCount: 300_000,
                        children: []
                    ),
                    FileNode(
                        id: URL(fileURLWithPath: "/Users/developer/.pub-cache"),
                        url: URL(fileURLWithPath: "/Users/developer/.pub-cache"),
                        name: ".pub-cache",
                        allocatedSize: 11_000_000_000,
                        fileCount: 80_000,
                        children: []
                    )
                ]
            ),
            skippedItemCount: 7,
            volumeTotalCapacity: 494_380_000_000,
            volumeAvailableCapacity: 94_990_000_000
        )
    )
}
