import Foundation

protocol DiskScanning: Sendable {
    func scan(
        _ root: URL,
        onProgress: @escaping DiskScanProgressHandler
    ) async throws -> DiskScanResult
}
