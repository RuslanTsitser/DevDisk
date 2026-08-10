import Foundation

struct JSONDiskScanStore: DiskScanStoring {
    private struct Payload: Codable {
        let result: DiskScanResult
        let bookmark: Data
        let scannedAt: Date
    }

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "DevDisk", directoryHint: .isDirectory)
        return directory.appending(path: "last-scan.json")
    }

    func load() throws -> SavedDiskScan? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: fileURL))
        var isStale = false
        let rootURL = try URL(
            resolvingBookmarkData: payload.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            try save(payload.result, rootURL: rootURL, scannedAt: payload.scannedAt)
        }
        return SavedDiskScan(result: payload.result, rootURL: rootURL, scannedAt: payload.scannedAt)
    }

    func save(_ result: DiskScanResult, rootURL: URL, scannedAt: Date) throws {
        let bookmark = try rootURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let data = try JSONEncoder().encode(Payload(result: result, bookmark: bookmark, scannedAt: scannedAt))
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
