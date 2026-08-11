import Foundation
import SQLite3
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

    func testHistoryKeepsTenSnapshotsAndLoadsPreviousDiff() throws {
        let rootURL = temporaryDirectory.appending(path: "History", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let databaseURL = temporaryDirectory.appending(path: "history.sqlite")
        let store = SQLiteDiskScanStore(databaseURL: databaseURL)

        for index in 1...12 {
            let targetURL = rootURL.appending(path: "target")
            let markerURL = rootURL.appending(path: "Cargo.toml")
            let target = FileNode(id: targetURL, url: targetURL, name: "target",
                                  logicalSize: Int64(index * 10), allocatedSize: Int64(index * 10),
                                  fileCount: 1, children: [])
            let marker = FileNode(id: markerURL, url: markerURL, name: "Cargo.toml",
                                  logicalSize: 0, allocatedSize: 0, fileCount: 1, children: nil)
            let root = FileNode(id: rootURL, url: rootURL, name: "History",
                                logicalSize: Int64(index * 10), allocatedSize: Int64(index * 10),
                                fileCount: 2, children: [marker, target])
            try store.recordSnapshot(
                DiskScanResult(root: root, skippedItemCount: 0, volumeTotalCapacity: nil, volumeAvailableCapacity: nil),
                scannedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index))
            )
        }

        XCTAssertEqual(try scalar(databaseURL, sql: "SELECT COUNT(*) FROM scan_snapshots"), 10)
        let directories = try store.loadPreviousDirectorySizes()
        XCTAssertEqual(
            directories[rootURL.path(percentEncoded: false)]?.allocatedSize,
            110,
            "Stored paths: \(directories.keys.sorted())"
        )
        let categories = try store.loadPreviousCategorySizes()
        XCTAssertEqual(categories["type:Rust Target"]?.allocatedSize, 110)
    }

    func testMigratesV1WithoutLosingLastScan() throws {
        let rootURL = temporaryDirectory.appending(path: "Legacy", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let databaseURL = temporaryDirectory.appending(path: "legacy.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
            CREATE TABLE scans (
                id INTEGER PRIMARY KEY CHECK (id = 1), root_bookmark BLOB NOT NULL,
                scanned_at REAL NOT NULL, skipped_item_count INTEGER NOT NULL,
                volume_total_capacity INTEGER, volume_available_capacity INTEGER,
                root_node_id INTEGER NOT NULL
            );
            CREATE TABLE file_nodes (
                id INTEGER PRIMARY KEY, parent_id INTEGER, url TEXT NOT NULL,
                name TEXT NOT NULL, allocated_size INTEGER NOT NULL,
                file_count INTEGER NOT NULL, is_directory INTEGER NOT NULL
            );
            PRAGMA user_version = 1;
            """, nil, nil, nil), SQLITE_OK)
        let bookmark = try rootURL.bookmarkData(options: [.withSecurityScope])
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "INSERT INTO file_nodes VALUES (1,NULL,?,?,123,3,1)", -1, &statement, nil), SQLITE_OK)
        rootURL.absoluteString.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT)
        }
        "Legacy".withCString {
            sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT)
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        XCTAssertEqual(sqlite3_prepare_v2(database, "INSERT INTO scans VALUES (1,?,0,2,NULL,NULL,1)", -1, &statement, nil), SQLITE_OK)
        bookmark.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        sqlite3_close(database)
        database = nil

        let saved = try XCTUnwrap(SQLiteDiskScanStore(databaseURL: databaseURL).load())
        XCTAssertEqual(saved.result.root.allocatedSize, 123)
        XCTAssertEqual(saved.result.root.logicalSize, 123)
        XCTAssertEqual(saved.result.root.accessStatus, .readable)
        XCTAssertEqual(saved.result.skippedItemCount, 2)
        XCTAssertEqual(try scalar(databaseURL, sql: "PRAGMA user_version"), 2)
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

    private func scalar(_ databaseURL: URL, sql: String) throws -> Int64 {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw NSError(domain: "SQLiteTest", code: 1)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteTest", code: 2)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "SQLiteTest", code: 3)
        }
        return sqlite3_column_int64(statement, 0)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
