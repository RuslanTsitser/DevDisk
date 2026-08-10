import Foundation

struct DiskScanResult: Equatable, Sendable {
    let root: FileNode
    let skippedItemCount: Int
    let volumeTotalCapacity: Int64?
    let volumeAvailableCapacity: Int64?

    var volumeUsedCapacity: Int64? {
        guard let volumeTotalCapacity, let volumeAvailableCapacity else { return nil }
        return max(0, volumeTotalCapacity - volumeAvailableCapacity)
    }
}
