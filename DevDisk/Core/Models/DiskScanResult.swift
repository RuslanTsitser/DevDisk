import Foundation

struct DiskScanResult: Codable, Equatable, Sendable {
    let root: FileNode
    let skippedItemCount: Int
    let volumeTotalCapacity: Int64?
    let volumeAvailableCapacity: Int64?

    var volumeUsedCapacity: Int64? {
        guard let volumeTotalCapacity, let volumeAvailableCapacity else { return nil }
        return max(0, volumeTotalCapacity - volumeAvailableCapacity)
    }

    var displayedSize: Int64 {
        guard let volumeUsedCapacity else { return root.allocatedSize }
        return min(root.allocatedSize, volumeUsedCapacity)
    }

    func replacing(_ replacement: DiskScanResult) -> DiskScanResult {
        return DiskScanResult(
            root: root.replacing(replacement.root),
            skippedItemCount: max(skippedItemCount, replacement.skippedItemCount),
            volumeTotalCapacity: volumeTotalCapacity,
            volumeAvailableCapacity: volumeAvailableCapacity
        )
    }
}
