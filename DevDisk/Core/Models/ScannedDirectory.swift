import Foundation

struct ScannedDirectory: Equatable, Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case scanning
        case cancelled
        case completed
        case partial(skippedItemCount: Int)
        case skipped
        case failed(String)
    }

    let url: URL
    let status: Status
    let node: FileNode?

    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    var isHidden: Bool { name.hasPrefix(".") }
    var allocatedSize: Int64? { node?.allocatedSize }
    var fileCount: Int? { node?.fileCount }
}

typealias ScannedDirectoryHandler = @Sendable (ScannedDirectory) -> Void
