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

    func removing(_ target: URL) -> DiskScanResult? {
        guard let updatedRoot = root.removing(target) else { return nil }
        return DiskScanResult(
            root: updatedRoot,
            skippedItemCount: skippedItemCount,
            volumeTotalCapacity: volumeTotalCapacity,
            volumeAvailableCapacity: volumeAvailableCapacity
        )
    }
}
