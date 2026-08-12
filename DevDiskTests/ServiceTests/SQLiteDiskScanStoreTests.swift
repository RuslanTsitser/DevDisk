import Foundation
import XCTest
@testable import DevDisk

final class SQLiteDiskScanStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadReturnsNilBeforeFirstSave() throws {
        let store = SQLiteDiskScanStore(
            databaseURL: temporaryDirectory.appending(path: "scan.sqlite")
        )

        XCTAssertNil(try store.load())
    }

    func testSaveAndLoadRoundTrip() throws {
        let rootURL = temporaryDirectory.appending(path: "Root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let folderURL = rootURL.appending(path: "Folder", directoryHint: .isDirectory)
        let fileURL = folderURL.appending(path: "report.txt", directoryHint: .notDirectory)
        let file = FileNode(
            id: fileURL,
            url: fileURL,
            name: "report.txt",
            allocatedSize: 4_096,
            fileCount: 1,
            children: nil
        )
        let folder = FileNode(
            id: folderURL,
            url: folderURL,
            name: "Folder",
            allocatedSize: 4_096,
            fileCount: 1,
            children: [file]
        )
        let root = FileNode(
            id: rootURL,
            url: rootURL,
            name: "Root",
            allocatedSize: 4_096,
            fileCount: 1,
            children: [folder]
        )
        let result = DiskScanResult(
            root: root,
            skippedItemCount: 3,
            volumeTotalCapacity: 100_000,
            volumeAvailableCapacity: 40_000
        )
        let scannedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = SQLiteDiskScanStore(
            databaseURL: temporaryDirectory.appending(path: "scan.sqlite")
        )

        try store.save(result, rootURL: rootURL, scannedAt: scannedAt)
        let saved = try XCTUnwrap(store.load())

        XCTAssertEqual(saved.result, result)
        XCTAssertEqual(
            saved.rootURL.resolvingSymlinksInPath(),
            rootURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(saved.scannedAt, scannedAt)
    }

    func testNewSaveReplacesPreviousScan() throws {
        let rootURL = temporaryDirectory.appending(path: "Root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let store = SQLiteDiskScanStore(
            databaseURL: temporaryDirectory.appending(path: "scan.sqlite")
        )
        let first = result(rootURL: rootURL, name: "First")
        let second = result(rootURL: rootURL, name: "Second")

        try store.save(first, rootURL: rootURL, scannedAt: .distantPast)
        try store.save(second, rootURL: rootURL, scannedAt: .distantFuture)

        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.result, second)
        XCTAssertEqual(saved.scannedAt, .distantFuture)
    }

    private func result(rootURL: URL, name: String) -> DiskScanResult {
        DiskScanResult(
            root: FileNode(
                id: rootURL,
                url: rootURL,
                name: name,
                allocatedSize: 0,
                fileCount: 0,
                children: []
            ),
            skippedItemCount: 0,
            volumeTotalCapacity: nil,
            volumeAvailableCapacity: nil
        )
    }
}
