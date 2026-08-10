import Foundation

struct ScanDiskUseCase: Sendable {
    private let scanner: any DiskScanning

    init(scanner: any DiskScanning) {
        self.scanner = scanner
    }

    func callAsFunction(_ root: URL) async throws -> FileNode {
        try await scanner.scan(root)
    }
}

