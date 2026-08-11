import Foundation

struct ScannedDirectory: Equatable, Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case scanning
        case completed
        case partial(skippedItemCount: Int)
        case skipped
        case failed(String)
    }

    let url: URL
    let status: Status
    let allocatedSize: Int64?
    let fileCount: Int?

    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    var isHidden: Bool { name.hasPrefix(".") }
}

typealias ScannedDirectoryHandler = @Sendable (ScannedDirectory) -> Void
