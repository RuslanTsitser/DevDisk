import SwiftUI
import UniformTypeIdentifiers

struct DiskExplorerView: View {
    @State private var state: DiskExplorerViewState
    @State private var presentsFolderPicker = false

    init(state: DiskExplorerViewState) {
        _state = State(initialValue: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 860, minHeight: 560)
        .task { state.restoreIfNeeded() }
        .fileImporter(
            isPresented: $presentsFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            state.startScan(url)
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(
                get: { state.pendingDeletion != nil },
                set: { if !$0 { state.cancelDeletion() } }
            ),
            presenting: state.pendingDeletion
        ) { _ in
            Button("Move to Trash", role: .destructive) {
                Task { await state.confirmDeletion() }
            }
            Button("Cancel", role: .cancel) { state.cancelDeletion() }
        } message: { node in
            Text("\(node.name) uses \(node.allocatedSize.formatted(.byteCount(style: .file))). It can be restored from Trash.")
        }
        .alert(
            "Deletion Failed",
            isPresented: Binding(
                get: { state.deletionError != nil },
                set: { if !$0 { state.dismissDeletionError() } }
            )
        ) {
            Button("OK") { state.dismissDeletionError() }
        } message: {
            Text(state.deletionError ?? "Unknown error")
        }
    }

    private var toolbar: some View {
        HStack {
            Text("DevDisk")
                .font(.headline)
            Spacer()
            if state.currentRootURL != nil {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    state.rescan()
                }
                .keyboardShortcut("r")
            }
            Button("Scan Folder or Disk") {
                presentsFolderPicker = true
            }
            .keyboardShortcut("o")
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            ContentUnavailableView(
                "Choose a folder or disk",
                systemImage: "externaldrive",
                description: Text("DevDisk shows directory sizes and recognizes development artifacts.")
            )
        case let .scanning(progress):
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Scanning \(progress.rootURL.lastPathComponent)…")
                            .font(.headline)
                    }
                    Text(progress.currentURL.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack {
                        Text("\(progress.itemsScanned.formatted()) items inspected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel Scan", role: .cancel) {
                            state.cancelScan()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .font(.caption)
                }
                .padding(16)
                Divider()
                if state.scannedDirectories.isEmpty {
                    ContentUnavailableView(
                        "Waiting for the first directory",
                        systemImage: "folder.badge.clock",
                        description: Text("Completed directories will appear here while the scan continues.")
                    )
                } else {
                    List {
                        let visibleDirectories = state.scannedDirectories.filter { !$0.isHidden }
                        let hiddenDirectories = state.scannedDirectories.filter { $0.isHidden }
                        if !visibleDirectories.isEmpty {
                            Section("Folders") {
                                ForEach(visibleDirectories) { directory in
                                    scannedDirectoryRow(directory)
                                }
                            }
                        }
                        if !hiddenDirectories.isEmpty {
                            Section("Hidden Folders") {
                                ForEach(hiddenDirectories) { directory in
                                    scannedDirectoryRow(directory)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(result):
            VStack(spacing: 0) {
                if state.isStale {
                    HStack {
                        Label("Files changed since this scan. Sizes may be outdated.", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        Spacer()
                        Button("Rescan") { state.rescan() }
                    }
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.12))
                }
                scanSummary(result)
                Divider()
                List([result.root], children: \.children) { node in
                    HStack {
                        Image(systemName: node.isDirectory ? "folder" : "doc")
                            .foregroundStyle(node.isDirectory ? .blue : .secondary)
                        Text(node.name)
                            .lineLimit(1)
                        if let artifact = node.artifact {
                            Text(artifact.ecosystem.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Text(node.allocatedSize, format: .byteCount(style: .file))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        if node.url != result.root.url {
                            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                                state.requestDeletion(node)
                            }
                        }
                    }
                }
            }
        case let .failed(message):
            ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private func scanSummary(_ result: DiskScanResult) -> some View {
        HStack(spacing: 24) {
            summaryValue("Scanned files", bytes: result.root.allocatedSize)
            if let used = result.volumeUsedCapacity {
                summaryValue("Entire volume used", bytes: used)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Scope").font(.caption).foregroundStyle(.secondary)
                Text(result.root.url.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let scannedAt = state.scannedAt {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scanned").font(.caption).foregroundStyle(.secondary)
                    Text(scannedAt, format: .dateTime.hour().minute())
                        .font(.caption)
                }
            }
            Spacer()
            if result.skippedItemCount > 0 {
                Label("\(result.skippedItemCount.formatted()) inaccessible items skipped", systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Grant access in System Settings, then scan the disk again.")
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func summaryValue(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes, format: .byteCount(style: .file)).font(.headline).monospacedDigit()
        }
    }

    private func scannedDirectoryRow(_ directory: ScannedDirectory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: directory.isHidden ? "folder.fill.badge.minus" : "folder")
                .foregroundStyle(directory.isHidden ? Color.secondary : Color.blue)
            Text(directory.name)
                .lineLimit(1)
            Spacer()
            directoryStatus(directory)
                .frame(minWidth: 110, alignment: .leading)
            if let fileCount = directory.fileCount {
                Text("\(fileCount.formatted()) files")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 90, alignment: .trailing)
            }
            if let allocatedSize = directory.allocatedSize {
                Text(allocatedSize, format: .byteCount(style: .file))
                    .monospacedDigit()
                    .frame(minWidth: 90, alignment: .trailing)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 90, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func directoryStatus(_ directory: ScannedDirectory) -> some View {
        switch directory.status {
        case .waiting:
            Label("Waiting", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Scanning")
            }
            .foregroundStyle(.blue)
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .partial(skippedItemCount):
            Label("Partial (\(skippedItemCount))", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .skipped:
            Label("Skipped", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(directoryFailureMessage(directory) ?? "The directory could not be scanned.")
        }
    }

    private func directoryFailureMessage(_ directory: ScannedDirectory) -> String? {
        guard case let .failed(message) = directory.status else { return nil }
        return message
    }
}

#Preview("Empty") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            monitor: StubFileChangeMonitor(),
            trashService: StubTrashService(),
            initialPhase: .idle
        )
    )
}

#Preview("Scanning") {
    let root = URL(fileURLWithPath: "/Users/developer")
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            monitor: StubFileChangeMonitor(),
            trashService: StubTrashService(),
            initialScannedDirectories: [
                ScannedDirectory(
                    url: root.appending(path: "Library/Developer/CoreSimulator/Caches"),
                    status: .completed,
                    allocatedSize: 8_400_000_000,
                    fileCount: 42_310
                ),
                ScannedDirectory(
                    url: root.appending(path: "Projects/client-app/node_modules"),
                    status: .scanning,
                    allocatedSize: nil,
                    fileCount: nil
                )
            ],
            initialPhase: .scanning(
                ScanProgress(
                    rootURL: root,
                    currentURL: root.appending(path: "Projects/client-app/node_modules/@types/react"),
                    itemsScanned: 18_642
                )
            )
        )
    )
}

#Preview("Loaded") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            monitor: StubFileChangeMonitor(),
            trashService: StubTrashService(),
            initialPhase: .loaded(StubDiskScanner.preview.result)
        )
    )
}

#Preview("Empty Folder") {
    let emptyRoot = FileNode(
        id: URL(fileURLWithPath: "/Users/developer/EmptyProject"),
        url: URL(fileURLWithPath: "/Users/developer/EmptyProject"),
        name: "EmptyProject",
        logicalSize: 0,
        allocatedSize: 0,
        fileCount: 0,
        artifact: nil,
        children: []
    )

    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            monitor: StubFileChangeMonitor(),
            trashService: StubTrashService(),
            initialPhase: .loaded(
                DiskScanResult(
                    root: emptyRoot,
                    skippedItemCount: 0,
                    volumeTotalCapacity: 494_380_000_000,
                    volumeAvailableCapacity: 94_990_000_000
                )
            )
        )
    )
}

#Preview("Error") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            monitor: StubFileChangeMonitor(),
            trashService: StubTrashService(),
            initialPhase: .failed(
                "DevDisk couldn’t read this location. Choose another folder or review its privacy permissions."
            )
        )
    )
}
