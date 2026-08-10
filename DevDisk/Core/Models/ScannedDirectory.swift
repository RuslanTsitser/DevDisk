import Foundation

struct ScannedDirectory: Equatable, Identifiable, Sendable {
    let url: URL
    let allocatedSize: Int64
    let fileCount: Int

    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

typealias ScannedDirectoryHandler = @Sendable (ScannedDirectory) -> Void
