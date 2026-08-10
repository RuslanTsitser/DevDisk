import Foundation

protocol DiskScanStoring: Sendable {
    func load() throws -> SavedDiskScan?
    func save(_ result: DiskScanResult, rootURL: URL, scannedAt: Date) throws
}
