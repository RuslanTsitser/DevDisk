import Foundation
import Observation

@MainActor
@Observable
final class DiskExplorerViewState {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
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

    private let scanDisk: ScanDiskUseCase
    private let store: any DiskScanStoring
    private let diskAccessRequester: any DiskAccessRequesting
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var rootAccessURL: URL?
    @ObservationIgnored private var isRootAccessActive = false
    private var directoryUpdates: [URL: ScannedDirectory] = [:]
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
        directoryUpdates = Dictionary(uniqueKeysWithValues: initialDirectories.map { ($0.url, $0) })
        phase = initialPhase
        if let root = Self.rootURL(in: initialPhase) {
            navigationPath = [root]
        }
    }

    var currentRootURL: URL? { Self.rootURL(in: phase) }
    var currentDirectoryURL: URL? { navigationPath.last ?? currentRootURL }
    var canNavigateBack: Bool { navigationPath.count > 1 }

    var currentDirectoryName: String {
        guard let url = currentDirectoryURL else { return "Disk" }
        return url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent
    }

    func appeared() {
        guard !didRestore else { return }
        didRestore = true
        guard case .idle = phase else { return }

        do {
            guard let saved = try store.load() else { return }
            phase = .loaded(saved.result)
            scannedAt = saved.scannedAt
            navigationPath = [saved.result.root.url]
            activateAccess(to: saved.rootURL)
        } catch {
            // A missing or incompatible cache must never block a fresh scan.
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
        case .scanning:
            var itemsByURL: [URL: BrowserItem] = [:]
            if let completedChildren = directoryUpdates[directoryURL]?.node?.children {
                for item in items(from: completedChildren) {
                    itemsByURL[item.url] = item
                }
            }
            for update in directoryUpdates.values
            where update.url != directoryURL
                && update.url.deletingLastPathComponent().standardizedFileURL
                    == directoryURL.standardizedFileURL {
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
        case .idle, .failed:
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
                try store.save(updated, rootURL: updated.root.url, scannedAt: scannedAt ?? Date())
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

    private func startScan(_ url: URL) {
        scanTask?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        refreshingURL = nil
        directoryUpdates = [:]
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
        do {
            let result = try await scanDisk(
                url,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard case .scanning = self?.phase else { return }
                        self?.phase = .scanning(progress)
                    }
                },
                onDirectoryScanned: { [weak self] directory in
                    Task { @MainActor [weak self] in
                        guard case .scanning = self?.phase else { return }
                        self?.directoryUpdates[directory.url] = directory
                    }
                }
            )
            phase = .loaded(result)
            scannedAt = Date()
            try? store.save(result, rootURL: url, scannedAt: scannedAt ?? Date())
        } catch is CancellationError {
            return
        } catch {
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
        case let .loaded(result): result.root.url
        case .idle, .failed: nil
        }
    }
}
