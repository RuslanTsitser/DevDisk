import Foundation
import Observation

@MainActor
@Observable
final class DiskExplorerViewState {
    enum Phase: Equatable {
        case accessRequired
        case idle
        case scanning(ScanProgress)
        case cancelled(ScanProgress)
        case loaded(DiskScanResult)
        case failed(String)
    }

    private(set) var phase: Phase
    private(set) var isStale = false
    private(set) var scannedAt: Date?
    private(set) var pendingDeletion: FileNode?
    private(set) var deletionError: String?
    private(set) var scannedDirectories: [ScannedDirectory]
    private let scanDisk: ScanDiskUseCase
    private let store: any DiskScanStoring
    private let monitor: any FileChangeMonitoring
    private let trashService: any FileTrashing
    private let diskAccessRequester: any DiskAccessRequesting
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var didRestore = false

    init(
        scanDisk: ScanDiskUseCase,
        store: any DiskScanStoring,
        monitor: any FileChangeMonitoring,
        trashService: any FileTrashing,
        diskAccessRequester: any DiskAccessRequesting,
        initialScannedDirectories: [ScannedDirectory] = [],
        initialPhase: Phase = .idle
    ) {
        self.scanDisk = scanDisk
        self.store = store
        self.monitor = monitor
        self.trashService = trashService
        self.diskAccessRequester = diskAccessRequester
        scannedDirectories = initialScannedDirectories
        phase = initialPhase
    }

    var currentRootURL: URL? {
        switch phase {
        case let .loaded(result): result.root.url
        case let .cancelled(progress): progress.rootURL
        default: nil
        }
    }

    func appeared() {
        guard !didRestore else { return }
        didRestore = true
        guard case .idle = phase else { return }
        do {
            guard let saved = try store.load() else {
                if let root = diskAccessRequester.restoredMacintoshHDURL() {
                    startScan(root)
                } else {
                    phase = .accessRequired
                }
                return
            }
            phase = .loaded(saved.result)
            scannedAt = saved.scannedAt
            isStale = true
            startMonitoring(saved.rootURL)
        } catch {
            if let root = diskAccessRequester.restoredMacintoshHDURL() {
                startScan(root)
            } else {
                phase = .accessRequired
            }
        }
    }

    func requestMacintoshHDAccess() {
        guard let url = diskAccessRequester.requestMacintoshHDAccess() else { return }
        startScan(url)
    }

    func openFullDiskAccessSettings() {
        diskAccessRequester.openFullDiskAccessSettings()
    }

    func startScan(_ url: URL) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.scan(url)
        }
    }

    func cancelScan() {
        guard case let .scanning(progress) = phase else { return }
        scanTask?.cancel()
        scanTask = nil
        scannedDirectories = scannedDirectories.map { directory in
            guard case .scanning = directory.status else { return directory }
            return ScannedDirectory(
                url: directory.url,
                status: .cancelled,
                allocatedSize: directory.allocatedSize,
                fileCount: directory.fileCount
            )
        }
        phase = .cancelled(progress)
    }

    func rescan() {
        guard let currentRootURL else { return }
        startScan(currentRootURL)
    }

    func requestDeletion(_ node: FileNode) {
        guard node.url != currentRootURL else { return }
        pendingDeletion = node
    }

    func cancelDeletion() {
        pendingDeletion = nil
    }

    func confirmDeletion() async {
        guard let node = pendingDeletion, case let .loaded(result) = phase else { return }
        pendingDeletion = nil
        monitor.stopMonitoring()
        do {
            try await trashService.moveToTrash(node.url)
            guard let updated = result.removing(node.url) else { return }
            phase = .loaded(updated)
            scannedAt = Date()
            isStale = true
            try store.save(updated, rootURL: updated.root.url, scannedAt: scannedAt ?? Date())
            startMonitoring(updated.root.url)
        } catch {
            deletionError = "Could not move \(node.name) to Trash: \(error.localizedDescription)"
            startMonitoring(result.root.url)
        }
    }

    func dismissDeletionError() {
        deletionError = nil
    }

    private func scan(_ url: URL) async {
        monitor.stopMonitoring()
        isStale = false
        scannedDirectories = []
        phase = .scanning(
            ScanProgress(rootURL: url, currentURL: url, itemsScanned: 0)
        )
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
                        self?.recordScannedDirectory(directory)
                    }
                }
            )
            phase = .loaded(result)
            scannedAt = Date()
            try? store.save(result, rootURL: url, scannedAt: scannedAt ?? Date())
            startMonitoring(url)
        } catch is CancellationError {
            if case .scanning = phase {
                phase = .cancelled(
                    ScanProgress(rootURL: url, currentURL: url, itemsScanned: 0)
                )
            }
        } catch {
            phase = .failed("The selected location could not be scanned: \(error.localizedDescription)")
        }
        scanTask = nil
    }

    private func startMonitoring(_ root: URL) {
        monitor.startMonitoring(root) { [weak self] in
            Task { @MainActor [weak self] in
                guard case .loaded = self?.phase else { return }
                self?.isStale = true
            }
        }
    }

    private func recordScannedDirectory(_ directory: ScannedDirectory) {
        if let index = scannedDirectories.firstIndex(where: { $0.id == directory.id }) {
            scannedDirectories[index] = directory
        } else {
            scannedDirectories.append(directory)
            scannedDirectories.sort {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}
