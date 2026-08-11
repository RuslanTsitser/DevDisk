import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DiskExplorerViewState {
    enum Phase: Equatable {
        case idle
        case restoring
        case scanning(ScanProgress)
        case stopped(ScanProgress)
        case loaded(DiskScanResult)
        case failed(String)
    }

    struct BrowserItem: Identifiable {
        let url: URL
        let name: String
        let isDirectory: Bool
        let status: ScannedDirectory.Status
        let allocatedSize: Int64?
        let node: FileNode?

        var id: URL { url }
    }

    private(set) var phase: Phase
    private(set) var scannedAt: Date?
    private(set) var navigationPath: [URL] = []
    private(set) var refreshingURL: URL?
    private(set) var refreshError: String?
    private(set) var itemPendingDeletion: BrowserItem?

    private let scanDisk: ScanDiskUseCase
    private let store: any DiskScanStoring
    private let diskAccessRequester: any DiskAccessRequesting
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var scanEventBuffer: ScanEventBuffer?
    @ObservationIgnored private var rootAccessURL: URL?
    @ObservationIgnored private var isRootAccessActive = false
    private var directoryUpdates: [URL: ScannedDirectory] = [:]
    private var directoryChildren: [URL: Set<URL>] = [:]
    @ObservationIgnored private var didRestore = false

    init(
        scanDisk: ScanDiskUseCase,
        store: any DiskScanStoring,
        diskAccessRequester: any DiskAccessRequesting,
        initialDirectories: [ScannedDirectory] = [],
        initialPhase: Phase = .idle
    ) {
        self.scanDisk = scanDisk
        self.store = store
        self.diskAccessRequester = diskAccessRequester
        phase = initialPhase
        directoryUpdates = Dictionary(uniqueKeysWithValues: initialDirectories.map { ($0.url, $0) })
        for directory in initialDirectories {
            directoryChildren[directory.url.deletingLastPathComponent(), default: []]
                .insert(directory.url)
        }
        if let root = Self.rootURL(in: initialPhase) {
            navigationPath = [root]
        }
    }

    var currentRootURL: URL? { Self.rootURL(in: phase) }
    var currentDirectoryURL: URL? { navigationPath.last ?? currentRootURL }
    var canNavigateBack: Bool { navigationPath.count > 1 }

    var currentDirectoryName: String {
        guard let url = currentDirectoryURL else { return "Disk" }
        if url == currentRootURL, url.path == "/.nofollow" { return "Macintosh HD" }
        return url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent
    }

    func appeared() {
        guard !didRestore else { return }
        didRestore = true
        guard case .idle = phase else { return }
        phase = .restoring

        let store = store
        Task { [weak self] in
            let saved: SavedDiskScan?
            do {
                saved = try await Task.detached(priority: .utility) {
                    try store.load()
                }.value
            } catch {
                guard let self, case .restoring = phase else { return }
                phase = .failed("The saved scan could not be loaded: \(error.localizedDescription)")
                return
            }
            guard let self, case .restoring = phase else { return }
            guard let saved else {
                phase = .idle
                return
            }
            phase = .loaded(saved.result)
            scannedAt = saved.scannedAt
            navigationPath = [saved.result.root.url]
            activateAccess(to: saved.rootURL)
        }
    }

    func requestScan() {
        guard let url = diskAccessRequester.requestDiskAccess() else { return }
        activateAccess(to: url)
        startScan(url)
    }

    func rescanRoot() {
        guard let currentRootURL else { return }
        startScan(rootAccessURL ?? currentRootURL)
    }

    func stopScan() {
        guard case let .scanning(progress) = phase else { return }
        scanTask?.cancel()
        scanTask = nil
        scanEventBuffer?.finish()
        scanEventBuffer = nil
        let activeURLs = directoryUpdates.compactMap { url, directory in
            directory.status == .scanning ? url : nil
        }
        for url in activeURLs {
            guard let directory = directoryUpdates[url] else { continue }
            directoryUpdates[url] = ScannedDirectory(
                url: directory.url,
                status: .cancelled,
                node: directory.node
            )
        }
        phase = .stopped(progress)
    }

    func open(_ item: BrowserItem) {
        guard item.isDirectory, navigationPath.last != item.url else { return }
        navigationPath.append(item.url)
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        navigationPath.removeLast()
    }

    func children() -> [BrowserItem] {
        guard let directoryURL = currentDirectoryURL else { return [] }

        switch phase {
        case let .loaded(result):
            return items(from: result.root.node(at: directoryURL)?.children ?? [])
        case .scanning, .stopped:
            var itemsByURL: [URL: BrowserItem] = [:]
            if let completedChildren = directoryUpdates[directoryURL]?.node?.children {
                for item in items(from: completedChildren) {
                    itemsByURL[item.url] = item
                }
            }
            for childURL in directoryChildren[directoryURL] ?? [] {
                guard let update = directoryUpdates[childURL], update.url != directoryURL else {
                    continue
                }
                itemsByURL[update.url] = BrowserItem(
                    url: update.url,
                    name: update.name,
                    isDirectory: true,
                    status: update.status,
                    allocatedSize: update.allocatedSize,
                    node: update.node
                )
            }
            return sorted(Array(itemsByURL.values))
        case .idle, .restoring, .failed:
            return []
        }
    }

    func refresh(_ item: BrowserItem) {
        guard item.isDirectory,
              let node = item.node,
              case let .loaded(result) = phase,
              item.url != result.root.url,
              refreshingURL == nil
        else { return }

        refreshingURL = item.url
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let replacement = try await scanDisk(item.url)
                let updated = result.replacing(replacement)
                phase = .loaded(updated)
                scannedAt = Date()
                let savedAt = scannedAt ?? Date()
                let store = store
                try await Task.detached(priority: .utility) {
                    try store.save(updated, rootURL: updated.root.url, scannedAt: savedAt)
                }.value
            } catch is CancellationError {
                return
            } catch {
                refreshError = "Could not refresh \(node.name): \(error.localizedDescription)"
            }
            refreshingURL = nil
            refreshTask = nil
        }
    }

    func dismissRefreshError() {
        refreshError = nil
    }

    func revealInFinder(_ item: BrowserItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func canDelete(_ item: BrowserItem) -> Bool {
        guard case let .loaded(result) = phase else { return false }
        return item.url != result.root.url && refreshingURL == nil
    }

    func requestDeletion(of item: BrowserItem) {
        guard canDelete(item) else { return }
        itemPendingDeletion = item
    }

    func cancelDeletion() {
        itemPendingDeletion = nil
    }

    func moveToTrash(_ item: BrowserItem) {
        guard itemPendingDeletion?.url == item.url, canDelete(item) else { return }
        itemPendingDeletion = nil
        refreshingURL = item.url

        Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                guard case let .loaded(result) = phase else { return }
                let updated = DiskScanResult(
                    root: result.root.removing(item.url),
                    skippedItemCount: result.skippedItemCount,
                    volumeTotalCapacity: result.volumeTotalCapacity,
                    volumeAvailableCapacity: result.volumeAvailableCapacity
                )
                phase = .loaded(updated)
                let savedAt = scannedAt ?? Date()
                let store = store
                try? await Task.detached(priority: .utility) {
                    try store.save(updated, rootURL: updated.root.url, scannedAt: savedAt)
                }.value
                refreshingURL = nil
            } catch {
                refreshError = "Could not move \(item.name) to the Trash: \(error.localizedDescription)"
                refreshingURL = nil
            }
        }
    }

    private func startScan(_ url: URL) {
        scanTask?.cancel()
        scanEventBuffer?.finish()
        scanEventBuffer = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshingURL = nil
        directoryUpdates = [:]
        directoryChildren = [:]
        navigationPath = [url]
        phase = .scanning(ScanProgress(rootURL: url, currentURL: url, itemsScanned: 0))
        scanTask = Task { [weak self] in
            await self?.scan(url)
        }
    }

    private func activateAccess(to url: URL) {
        if isRootAccessActive {
            rootAccessURL?.stopAccessingSecurityScopedResource()
        }
        rootAccessURL = url
        isRootAccessActive = url.startAccessingSecurityScopedResource()
    }

    private func scan(_ url: URL) async {
        let eventBuffer = ScanEventBuffer { [weak self] progress, directories in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch phase {
                case .scanning:
                    if let progress { phase = .scanning(progress) }
                    for directory in directories {
                        recordDirectory(directory)
                    }
                case .stopped:
                    for directory in directories {
                        let stoppedDirectory = directory.status == .scanning
                            ? ScannedDirectory(url: directory.url, status: .cancelled, node: directory.node)
                            : directory
                        recordDirectory(stoppedDirectory)
                    }
                default:
                    return
                }
            }
        }
        scanEventBuffer = eventBuffer

        do {
            let result = try await scanDisk(
                url,
                onProgress: { progress in
                    eventBuffer.record(progress)
                },
                onDirectoryScanned: { directory in
                    eventBuffer.record(directory)
                }
            )
            eventBuffer.finish()
            scanEventBuffer = nil
            phase = .loaded(result)
            scannedAt = Date()
            let savedAt = scannedAt ?? Date()
            let store = store
            try? await Task.detached(priority: .utility) {
                try store.save(result, rootURL: url, scannedAt: savedAt)
            }.value
        } catch is CancellationError {
            eventBuffer.finish()
            return
        } catch {
            eventBuffer.finish()
            scanEventBuffer = nil
            phase = .failed("The disk could not be scanned: \(error.localizedDescription)")
        }
        scanTask = nil
    }

    private func items(from nodes: [FileNode]) -> [BrowserItem] {
        sorted(nodes.map { node in
            BrowserItem(
                url: node.url,
                name: node.name,
                isDirectory: node.isDirectory,
                status: .completed,
                allocatedSize: node.allocatedSize,
                node: node
            )
        })
    }

    private func recordDirectory(_ directory: ScannedDirectory) {
        directoryUpdates[directory.url] = directory
        directoryChildren[directory.url.deletingLastPathComponent(), default: []]
            .insert(directory.url)
    }

    private func sorted(_ items: [BrowserItem]) -> [BrowserItem] {
        items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            switch ($0.allocatedSize, $1.allocatedSize) {
            case let (left?, right?) where left != right: return left > right
            default: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    private static func rootURL(in phase: Phase) -> URL? {
        switch phase {
        case let .scanning(progress): progress.rootURL
        case let .stopped(progress): progress.rootURL
        case let .loaded(result): result.root.url
        case .idle, .restoring, .failed: nil
        }
    }
}

private final class ScanEventBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let timer: DispatchSourceTimer
    private let deliver: @Sendable (ScanProgress?, [ScannedDirectory]) -> Void
    private var latestProgress: ScanProgress?
    private var directories: [URL: ScannedDirectory] = [:]
    private var isFinished = false

    init(deliver: @escaping @Sendable (ScanProgress?, [ScannedDirectory]) -> Void) {
        self.deliver = deliver
        timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.devdisk.scan-events", qos: .utility)
        )
        timer.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
    }

    func record(_ progress: ScanProgress) {
        lock.withLock {
            guard !isFinished else { return }
            latestProgress = progress
        }
    }

    func record(_ directory: ScannedDirectory) {
        lock.withLock {
            guard !isFinished else { return }
            directories[directory.url] = directory
        }
    }

    func finish() {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        guard shouldFinish else { return }
        timer.cancel()
        flush()
    }

    private func flush() {
        let batch = lock.withLock { () -> (ScanProgress?, [ScannedDirectory]) in
            let batch = (latestProgress, Array(directories.values))
            latestProgress = nil
            directories.removeAll(keepingCapacity: true)
            return batch
        }
        guard batch.0 != nil || !batch.1.isEmpty else { return }
        deliver(batch.0, batch.1)
    }

    deinit {
        timer.cancel()
    }
}
