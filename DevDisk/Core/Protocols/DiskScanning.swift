import Foundation

protocol DiskScanning: Sendable {
    func scan(_ root: URL) async throws -> FileNode
}

