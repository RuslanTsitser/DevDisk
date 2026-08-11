import Foundation

protocol ScanHistoryStoring: Sendable {
    func recordSnapshot(_ result: DiskScanResult, scannedAt: Date) throws
    func loadPreviousDirectorySizes() throws -> [String: DirectorySizeSnapshot]
    func loadPreviousCategorySizes() throws -> [String: CategorySizeSnapshot]
}

protocol DiskScanStoring: ScanHistoryStoring {
    func load() throws -> SavedDiskScan?
    func save(_ result: DiskScanResult, rootURL: URL, scannedAt: Date) throws
}
