import Foundation

struct ScanDiskUseCase: Sendable {
    private let scanner: any DiskScanning

    init(scanner: any DiskScanning) {
        self.scanner = scanner
    }

    func callAsFunction(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler = { _ in }
    ) async throws -> FileNode {
        try await scanner.scan(root, onProgress: onProgress)
    }
}
