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
        let logicalSize: Int64?
        let allocatedSize: Int64?
        let fileCount: Int?
        let modifiedAt: Date?
        let accessStatus: FileAccessStatus
        let node: FileNode?

        var id: URL { url }
    }

    private(set) var phase: Phase
    private(set) var scannedAt: Date?
    private(set) var navigationPath: [URL] = []
    private(set) var refreshingURL: URL?
    private(set) var refreshError: String?
    private(set) var artifactPendingDeletion: DeveloperArtifact?
    private(set) var insights: DeveloperInsights = .empty
    private(set) var isAnalyzing = false
    private(set) var previousDirectorySizes: [String: DirectorySizeSnapshot] = [:]
    private(set) var previousCategorySizes: [String: CategorySizeSnapshot] = [:]
    private(set) var selectedURL: URL?
    var searchQuery = ""
    var ecosystemFilter: DeveloperEcosystem?
    var riskFilter: ArtifactRisk?
    var artifactKindFilter: String?

    private let scanDisk: ScanDiskUseCase
    private let store: any DiskScanStoring
    private let diskAccessRequester: any DiskAccessRequesting
    private let artifactAnalyzer: any ArtifactDetecting
    private let cleanupService: any CleanupServicing
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var scanEventBuffer: ScanEventBuffer?
    @ObservationIgnored private var rootAccessURL: URL?
    @ObservationIgnored private var isRootAccessActive = false
    private var directoryUpdates: [URL: ScannedDirectory] = [:]
    private var directoryChildren: [URL: Set<URL>] = [:]
    @ObservationIgnored private var didRestore = false
    @ObservationIgnored private var analysisGeneration = UUID()

    init(
        scanDisk: ScanDiskUseCase,
        store: any DiskScanStoring,
        diskAccessRequester: any DiskAccessRequesting,
        artifactAnalyzer: any ArtifactDetecting = DeveloperArtifactAnalyzer(),
        cleanupService: any CleanupServicing = ArtifactCleanupService(),
        initialDirectories: [ScannedDirectory] = [],
        initialPhase: Phase = .idle
    ) {
        self.scanDisk = scanDisk
        self.store = store
        self.diskAccessRequester = diskAccessRequester
        self.artifactAnalyzer = artifactAnalyzer
        self.cleanupService = cleanupService
        phase = initialPhase
        directoryUpdates = Dictionary(uniqueKeysWithValues: initialDirectories.map { ($0.url, $0) })
        for directory in initialDirectories {
            directoryChildren[Self.directoryKey(directory.url.deletingLastPathComponent()), default: []]
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
            analyze(saved.result)
            loadPreviousSizes()
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
            for childURL in directoryChildren[Self.directoryKey(directoryURL)] ?? [] {
                guard let update = directoryUpdates[childURL], update.url != directoryURL else {
                    continue
                }
                itemsByURL[update.url] = BrowserItem(
                    url: update.url,
                    name: update.name,
                    isDirectory: true,
                    status: update.status,
                    logicalSize: update.node?.logicalSize,
                    allocatedSize: update.allocatedSize,
                    fileCount: update.node?.fileCount,
                    modifiedAt: update.node?.modifiedAt,
                    accessStatus: update.node?.accessStatus ?? .readable,
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
                analyze(updated)
                let savedAt = scannedAt ?? Date()
                let store = store
                let accessURL = rootAccessURL ?? updated.root.url
                try await Task.detached(priority: .utility) {
                    try store.save(updated, rootURL: accessURL, scannedAt: savedAt)
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

    func presentError(_ message: String) {
        refreshError = message
    }

    func revealInFinder(_ item: BrowserItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    var currentResult: DiskScanResult? {
        if case let .loaded(result) = phase { return result }
        return nil
    }

    var outlineRoot: FileNode? {
        if let currentResult { return currentResult.root }
        guard let rootURL = currentRootURL else { return nil }
        let nodes = children().map { item in
            item.node ?? FileNode(
                id: item.url,
                url: item.url,
                name: item.name,
                logicalSize: item.logicalSize ?? 0,
                allocatedSize: item.allocatedSize ?? 0,
                fileCount: item.fileCount ?? 0,
                modifiedAt: item.modifiedAt,
                accessStatus: item.accessStatus,
                children: item.isDirectory ? [] : nil
            )
        }
        return FileNode(
            id: rootURL,
            url: rootURL,
            name: currentDirectoryName,
            logicalSize: nodes.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: nodes.reduce(0) { $0 + $1.allocatedSize },
            fileCount: nodes.reduce(0) { $0 + $1.fileCount },
            children: nodes
        )
    }

    var visibleDirectoryStatuses: [URL: ScannedDirectory.Status] {
        switch phase {
        case .scanning, .stopped:
            return directoryUpdates.mapValues(\.status)
        case .idle, .restoring, .loaded, .failed:
            return [:]
        }
    }

    var selectedNode: FileNode? {
        guard let selectedURL else { return nil }
        return currentResult?.root.node(at: selectedURL)
    }

    var selectedArtifact: DeveloperArtifact? {
        guard let selectedURL else { return nil }
        return insights.artifacts.first { $0.url == selectedURL }
    }

    func select(_ url: URL?) {
        selectedURL = url
    }

    func growth(for url: URL, currentSize: Int64) -> Int64? {
        guard let previous = previousDirectorySizes[url.path(percentEncoded: false)] else { return nil }
        return currentSize - previous.allocatedSize
    }

    var growthSummary: (added: Int, removed: Int, grown: Int, shrunk: Int) {
        guard let root = currentResult?.root else { return (0, 0, 0, 0) }
        var current: [String: Int64] = [:]
        var pending = [root]
        while let node = pending.popLast() {
            if node.isDirectory {
                current[node.url.path(percentEncoded: false)] = node.allocatedSize
            }
            if let children = node.children { pending.append(contentsOf: children) }
        }
        var added = 0
        var grown = 0
        var shrunk = 0
        for (path, size) in current {
            guard let previous = previousDirectorySizes[path] else {
                added += 1
                continue
            }
            if size > previous.allocatedSize { grown += 1 }
            if size < previous.allocatedSize { shrunk += 1 }
        }
        let removed = previousDirectorySizes.keys.lazy.filter { current[$0] == nil }.count
        return (added, removed, grown, shrunk)
    }

    func requestDeletion(of artifact: DeveloperArtifact) {
        guard artifact.url != currentResult?.root.url,
              cleanupService.validateForCleanup(artifact),
              refreshingURL == nil
        else { return }
        artifactPendingDeletion = artifact
    }

    func cancelDeletion() {
        artifactPendingDeletion = nil
    }

    func moveToTrash(_ artifact: DeveloperArtifact) {
        guard artifactPendingDeletion?.url == artifact.url,
              case let .loaded(result) = phase,
              artifact.url != result.root.url,
              cleanupService.validateForCleanup(artifact),
              refreshingURL == nil
        else { return }
        artifactPendingDeletion = nil
        refreshingURL = artifact.url

        Task { [weak self] in
            guard let self else { return }
            do {
                try cleanupService.moveToTrash(artifact)
                let updated = DiskScanResult(
                    root: result.root.removing(artifact.url),
                    skippedItemCount: result.skippedItemCount,
                    volumeTotalCapacity: result.volumeTotalCapacity,
                    volumeAvailableCapacity: result.volumeAvailableCapacity
                )
                phase = .loaded(updated)
                selectedURL = nil
                analyze(updated)
                let savedAt = Date()
                scannedAt = savedAt
                let store = store
                let accessURL = rootAccessURL ?? updated.root.url
                try? await Task.detached(priority: .utility) {
                    try store.save(updated, rootURL: accessURL, scannedAt: savedAt)
                    try store.recordSnapshot(updated, scannedAt: savedAt)
                }.value
                loadPreviousSizes()
                refreshingURL = nil
            } catch {
                refreshError = "Could not move \(artifact.name) to the Trash: \(error.localizedDescription)"
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
        insights = .empty
        isAnalyzing = false
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
            analyze(result)
            let savedAt = scannedAt ?? Date()
            let store = store
            try? await Task.detached(priority: .utility) {
                try store.save(result, rootURL: url, scannedAt: savedAt)
                try store.recordSnapshot(result, scannedAt: savedAt)
            }.value
            loadPreviousSizes()
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
                logicalSize: node.logicalSize,
                allocatedSize: node.allocatedSize,
                fileCount: node.fileCount,
                modifiedAt: node.modifiedAt,
                accessStatus: node.accessStatus,
                node: node
            )
        })
    }

    private func recordDirectory(_ directory: ScannedDirectory) {
        directoryUpdates[directory.url] = directory
        directoryChildren[Self.directoryKey(directory.url.deletingLastPathComponent()), default: []]
            .insert(directory.url)
    }

    private static func directoryKey(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
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

    private func analyze(_ result: DiskScanResult) {
        let analyzer = artifactAnalyzer
        let generation = UUID()
        analysisGeneration = generation
        isAnalyzing = true
        Task { [weak self] in
            let value = await Task.detached(priority: .utility) {
                analyzer.analyze(result.root)
            }.value
            guard let self, analysisGeneration == generation else { return }
            insights = value
            isAnalyzing = false
        }
    }

    private func loadPreviousSizes() {
        let store = store
        Task { [weak self] in
            let values = await Task.detached(priority: .utility) {
                let directories = (try? store.loadPreviousDirectorySizes()) ?? [:]
                let categories = (try? store.loadPreviousCategorySizes()) ?? [:]
                return (directories, categories)
            }.value
            self?.previousDirectorySizes = values.0
            self?.previousCategorySizes = values.1
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
