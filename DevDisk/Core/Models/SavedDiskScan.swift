import Foundation

struct SavedDiskScan: Sendable {
    let result: DiskScanResult
    let rootURL: URL
    let scannedAt: Date
}
