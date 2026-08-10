import Foundation

protocol DiskScanning: Sendable {
    func scan(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler,
        onDirectoryScanned: @escaping ScannedDirectoryHandler
    ) async throws -> DiskScanResult
}
