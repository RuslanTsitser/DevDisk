import Foundation

struct StubDiskScanner: DiskScanning {
    let result: FileNode

    func scan(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler
    ) async throws -> FileNode {
        onProgress(
            ScanProgress(
                rootURL: root,
                currentURL: result.url,
                itemsScanned: result.fileCount
            )
        )
        return result
    }

    static let preview = StubDiskScanner(
        result: FileNode(
            id: URL(fileURLWithPath: "/Users/developer"),
            url: URL(fileURLWithPath: "/Users/developer"),
            name: "developer",
            logicalSize: 91_000_000_000,
            allocatedSize: 84_000_000_000,
            fileCount: 420_000,
            artifact: nil,
            children: [
                FileNode(
                    id: URL(fileURLWithPath: "/Users/developer/Projects"),
                    url: URL(fileURLWithPath: "/Users/developer/Projects"),
                    name: "Projects",
                    logicalSize: 55_000_000_000,
                    allocatedSize: 51_000_000_000,
                    fileCount: 300_000,
                    artifact: nil,
                    children: []
                ),
                FileNode(
                    id: URL(fileURLWithPath: "/Users/developer/.pub-cache"),
                    url: URL(fileURLWithPath: "/Users/developer/.pub-cache"),
                    name: ".pub-cache",
                    logicalSize: 12_000_000_000,
                    allocatedSize: 11_000_000_000,
                    fileCount: 80_000,
                    artifact: .init(ecosystem: .flutter, kind: "Pub cache", removalRisk: .redownloadable),
                    children: []
                )
            ]
        )
    )
}
