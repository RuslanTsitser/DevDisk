import Foundation

struct StubDiskScanStore: DiskScanStoring {
    var savedScan: SavedDiskScan?
    func load() throws -> SavedDiskScan? { savedScan }
    func save(_ result: DiskScanResult, rootURL: URL, scannedAt: Date) throws {}
    func recordSnapshot(_ result: DiskScanResult, scannedAt: Date) throws {}
    func loadPreviousDirectorySizes() throws -> [String: DirectorySizeSnapshot] { [:] }
    func loadPreviousCategorySizes() throws -> [String: CategorySizeSnapshot] { [:] }

    static let empty = StubDiskScanStore(savedScan: nil)
}
