import Foundation

struct StubDiskScanStore: DiskScanStoring {
    var savedScan: SavedDiskScan?
    func load() throws -> SavedDiskScan? { savedScan }
    func save(_ result: DiskScanResult, rootURL: URL, scannedAt: Date) throws {}

    static let empty = StubDiskScanStore(savedScan: nil)
}
