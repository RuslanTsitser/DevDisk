import Foundation
import SQLite3

struct SQLiteDiskScanStore: DiskScanStoring {
    private static let schemaVersion: Int32 = 1
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let databaseURL: URL

    private var legacyJSONURL: URL {
        databaseURL.deletingLastPathComponent().appending(path: "last-scan.json")
    }

    init(databaseURL: URL? = nil) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            self.databaseURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "DevDisk", directoryHint: .isDirectory)
                .appending(path: "scan-history.sqlite")
        }
    }

    func load() throws -> SavedDiskScan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        let database = try Database(url: databaseURL)
        try database.prepareSchema()

        guard let metadata = try database.loadMetadata() else { return nil }
        let root = try database.loadTree(rootID: metadata.rootNodeID)

        var isStale = false
        let rootURL = try URL(
            resolvingBookmarkData: metadata.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            let bookmark = try makeBookmark(for: rootURL)
            try database.updateBookmark(bookmark)
        }

        return SavedDiskScan(
            result: DiskScanResult(
                root: root,
                skippedItemCount: metadata.skippedItemCount,
                volumeTotalCapacity: metadata.volumeTotalCapacity,
                volumeAvailableCapacity: metadata.volumeAvailableCapacity
            ),
            rootURL: rootURL,
            scannedAt: metadata.scannedAt
        )
    }

    func save(_ result: DiskScanResult, rootURL: URL, scannedAt: Date) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let database = try Database(url: databaseURL)
        try database.prepareSchema()
        try database.replaceScan(
            result,
            bookmark: makeBookmark(for: rootURL),
            scannedAt: scannedAt
        )
        try? FileManager.default.removeItem(at: legacyJSONURL)
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

private extension SQLiteDiskScanStore {
    struct Metadata {
        let bookmark: Data
        let scannedAt: Date
        let skippedItemCount: Int
        let volumeTotalCapacity: Int64?
        let volumeAvailableCapacity: Int64?
        let rootNodeID: Int64
    }

    final class Database {
        private var handle: OpaquePointer?

        init(url: URL) throws {
            let result = sqlite3_open_v2(
                url.path,
                &handle,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
            guard result == SQLITE_OK else {
                let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                if let handle { sqlite3_close(handle) }
                handle = nil
                throw StoreError.openFailed(message)
            }
            sqlite3_busy_timeout(handle, 5_000)
        }

        deinit {
            if let handle { sqlite3_close(handle) }
        }

        func prepareSchema() throws {
            let version = try scalarInt("PRAGMA user_version")
            guard version == 0 || version == SQLiteDiskScanStore.schemaVersion else {
                throw StoreError.unsupportedSchema(version)
            }

            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS scans (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    root_bookmark BLOB NOT NULL,
                    scanned_at REAL NOT NULL,
                    skipped_item_count INTEGER NOT NULL,
                    volume_total_capacity INTEGER,
                    volume_available_capacity INTEGER,
                    root_node_id INTEGER NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS file_nodes (
                    id INTEGER PRIMARY KEY,
                    parent_id INTEGER,
                    url TEXT NOT NULL,
                    name TEXT NOT NULL,
                    allocated_size INTEGER NOT NULL,
                    file_count INTEGER NOT NULL,
                    is_directory INTEGER NOT NULL
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS file_nodes_parent ON file_nodes(parent_id)")
            if version == 0 {
                try execute("PRAGMA user_version = \(SQLiteDiskScanStore.schemaVersion)")
            }
        }

        func replaceScan(_ result: DiskScanResult, bookmark: Data, scannedAt: Date) throws {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM scans")
                try execute("DELETE FROM file_nodes")
                let rootNodeID = try insertTree(result.root)
                try insertMetadata(
                    result,
                    rootNodeID: rootNodeID,
                    bookmark: bookmark,
                    scannedAt: scannedAt
                )
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }

        func loadMetadata() throws -> Metadata? {
            let statement = try prepare("""
                SELECT root_bookmark, scanned_at, skipped_item_count,
                       volume_total_capacity, volume_available_capacity, root_node_id
                FROM scans WHERE id = 1
                """)
            defer { sqlite3_finalize(statement) }

            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw error(for: result) }

            return Metadata(
                bookmark: data(statement, column: 0),
                scannedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
                skippedItemCount: Int(sqlite3_column_int64(statement, 2)),
                volumeTotalCapacity: optionalInt64(statement, column: 3),
                volumeAvailableCapacity: optionalInt64(statement, column: 4),
                rootNodeID: sqlite3_column_int64(statement, 5)
            )
        }

        func loadTree(rootID: Int64) throws -> FileNode {
            let statement = try prepare("""
                SELECT id, parent_id, url, name, allocated_size, file_count, is_directory
                FROM file_nodes ORDER BY id DESC
                """)
            defer { sqlite3_finalize(statement) }

            var childrenByParent: [Int64: [FileNode]] = [:]
            var root: FileNode?

            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw error(for: result) }

                let nodeID = sqlite3_column_int64(statement, 0)
                let parentID = sqlite3_column_type(statement, 1) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(statement, 1)
                guard let urlText = sqlite3_column_text(statement, 2),
                      let url = URL(string: String(cString: urlText)),
                      let nameText = sqlite3_column_text(statement, 3)
                else {
                    throw StoreError.invalidNode(nodeID)
                }

                let isDirectory = sqlite3_column_int(statement, 6) != 0
                let children = isDirectory
                    ? Array((childrenByParent.removeValue(forKey: nodeID) ?? []).reversed())
                    : nil
                let node = FileNode(
                    id: url,
                    url: url,
                    name: String(cString: nameText),
                    allocatedSize: sqlite3_column_int64(statement, 4),
                    fileCount: Int(sqlite3_column_int64(statement, 5)),
                    children: children
                )

                if let parentID {
                    childrenByParent[parentID, default: []].append(node)
                } else if nodeID == rootID {
                    root = node
                }
            }

            guard let root else { throw StoreError.missingRoot(rootID) }
            return root
        }

        func updateBookmark(_ bookmark: Data) throws {
            let statement = try prepare("UPDATE scans SET root_bookmark = ? WHERE id = 1")
            defer { sqlite3_finalize(statement) }
            bind(bookmark, to: 1, in: statement)
            try stepDone(statement)
        }

        private func insertTree(_ root: FileNode) throws -> Int64 {
            let statement = try prepare("""
                INSERT INTO file_nodes (
                    parent_id, url, name, allocated_size, file_count, is_directory
                ) VALUES (?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }

            var rootID: Int64?
            var pending: [(node: FileNode, parentID: Int64?)] = [(root, nil)]

            while let next = pending.popLast() {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                if let parentID = next.parentID {
                    sqlite3_bind_int64(statement, 1, parentID)
                } else {
                    sqlite3_bind_null(statement, 1)
                }
                bind(next.node.url.absoluteString, to: 2, in: statement)
                bind(next.node.name, to: 3, in: statement)
                sqlite3_bind_int64(statement, 4, next.node.allocatedSize)
                sqlite3_bind_int64(statement, 5, Int64(next.node.fileCount))
                sqlite3_bind_int(statement, 6, next.node.isDirectory ? 1 : 0)
                try stepDone(statement)

                let nodeID = sqlite3_last_insert_rowid(handle)
                if rootID == nil { rootID = nodeID }
                if let children = next.node.children {
                    for child in children.reversed() {
                        pending.append((child, nodeID))
                    }
                }
            }

            guard let rootID else { throw StoreError.emptyTree }
            return rootID
        }

        private func insertMetadata(
            _ result: DiskScanResult,
            rootNodeID: Int64,
            bookmark: Data,
            scannedAt: Date
        ) throws {
            let statement = try prepare("""
                INSERT INTO scans (
                    id, root_bookmark, scanned_at, skipped_item_count,
                    volume_total_capacity, volume_available_capacity, root_node_id
                ) VALUES (1, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }

            bind(bookmark, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, scannedAt.timeIntervalSinceReferenceDate)
            sqlite3_bind_int64(statement, 3, Int64(result.skippedItemCount))
            bind(result.volumeTotalCapacity, to: 4, in: statement)
            bind(result.volumeAvailableCapacity, to: 5, in: statement)
            sqlite3_bind_int64(statement, 6, rootNodeID)
            try stepDone(statement)
        }

        private func bind(_ value: String, to index: Int32, in statement: OpaquePointer?) {
            _ = value.withCString {
                sqlite3_bind_text(statement, index, $0, -1, SQLiteDiskScanStore.transient)
            }
        }

        private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer?) {
            _ = value.withUnsafeBytes {
                sqlite3_bind_blob(
                    statement,
                    index,
                    $0.baseAddress,
                    Int32($0.count),
                    SQLiteDiskScanStore.transient
                )
            }
        }

        private func bind(_ value: Int64?, to index: Int32, in statement: OpaquePointer?) {
            if let value {
                sqlite3_bind_int64(statement, index, value)
            } else {
                sqlite3_bind_null(statement, index)
            }
        }

        private func data(_ statement: OpaquePointer?, column: Int32) -> Data {
            guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }

        private func optionalInt64(_ statement: OpaquePointer?, column: Int32) -> Int64? {
            sqlite3_column_type(statement, column) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, column)
        }

        private func scalarInt(_ sql: String) throws -> Int32 {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else { throw error(for: result) }
            return sqlite3_column_int(statement, 0)
        }

        private func execute(_ sql: String) throws {
            let result = sqlite3_exec(handle, sql, nil, nil, nil)
            guard result == SQLITE_OK else { throw error(for: result) }
        }

        private func prepare(_ sql: String) throws -> OpaquePointer? {
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
            guard result == SQLITE_OK else { throw error(for: result) }
            return statement
        }

        private func stepDone(_ statement: OpaquePointer?) throws {
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else { throw error(for: result) }
        }

        private func error(for code: Int32) -> StoreError {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            return .sqlite(code, message)
        }
    }

    enum StoreError: LocalizedError {
        case openFailed(String)
        case sqlite(Int32, String)
        case unsupportedSchema(Int32)
        case invalidNode(Int64)
        case missingRoot(Int64)
        case emptyTree

        var errorDescription: String? {
            switch self {
            case let .openFailed(message): "Could not open scan database: \(message)"
            case let .sqlite(code, message): "Scan database error \(code): \(message)"
            case let .unsupportedSchema(version): "Unsupported scan database version: \(version)"
            case let .invalidNode(id): "Scan database contains an invalid node: \(id)"
            case let .missingRoot(id): "Scan database root is missing: \(id)"
            case .emptyTree: "Cannot save an empty scan tree"
            }
        }
    }
}
