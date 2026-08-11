import SwiftUI

struct DiskExplorerView: View {
    @State private var state: DiskExplorerViewState

    init(state: DiskExplorerViewState) {
        _state = State(initialValue: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 760, minHeight: 520)
        .task { state.appeared() }
        .alert(
            "Refresh Failed",
            isPresented: Binding(
                get: { state.refreshError != nil },
                set: { if !$0 { state.dismissRefreshError() } }
            )
        ) {
            Button("OK") { state.dismissRefreshError() }
        } message: {
            Text(state.refreshError ?? "Unknown error")
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(
                get: { state.itemPendingDeletion != nil },
                set: { if !$0 { state.cancelDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            if let item = state.itemPendingDeletion {
                Button("Move to Trash", role: .destructive) {
                    state.moveToTrash(item)
                }
            }
            Button("Cancel", role: .cancel) { state.cancelDeletion() }
        } message: {
            Text("\(state.itemPendingDeletion?.name ?? "This item") will be moved to the Trash.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("DevDisk")
                .font(.headline)
            Spacer()
            if isRestoring {
                ProgressView()
                    .controlSize(.small)
            } else if isScanning {
                Button("Stop Scan", systemImage: "stop.fill", role: .cancel) {
                    state.stopScan()
                }
                .keyboardShortcut(.cancelAction)
            } else if state.currentRootURL != nil {
                Button("Scan Again", systemImage: "arrow.clockwise") {
                    state.rescanRoot()
                }
                .keyboardShortcut("r")
            } else {
                Button("Scan Disk", systemImage: "internaldrive") {
                    state.requestScan()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .restoring:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading Last Scan")
                    .font(.headline)
                Text("Restoring the saved disk contents…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle:
            ContentUnavailableView {
                Label("See What Uses Your Disk", systemImage: "internaldrive")
            } description: {
                Text("Start a scan, then allow access to Macintosh HD. DevDisk only reads file metadata and keeps the result on this Mac.")
            } actions: {
                Button("Scan Disk") { state.requestScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Scan Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { state.requestScan() }
                    .buttonStyle(.borderedProminent)
            }
        case let .scanning(progress):
            explorer(progress: progress, result: nil)
        case let .stopped(progress):
            explorer(progress: nil, result: nil, stoppedProgress: progress)
        case let .loaded(result):
            explorer(progress: nil, result: result)
        }
    }

    private func explorer(
        progress: ScanProgress?,
        result: DiskScanResult?,
        stoppedProgress: ScanProgress? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let progress {
                scanningHeader(progress)
            } else if let stoppedProgress {
                stoppedHeader(stoppedProgress)
            } else if let result {
                resultHeader(result)
            }
            Divider()
            browserHeader
            Divider()
            browserList
        }
    }

    private func stoppedHeader(_ progress: ScanProgress) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Scan stopped")
                    .font(.headline)
                Text("Completed folders remain available below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(progress.itemsScanned.formatted()) items")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .background(.bar)
    }

    private func scanningHeader(_ progress: ScanProgress) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Scanning disk")
                    .font(.headline)
                Text(displayPath(progress.currentURL))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text("\(progress.itemsScanned.formatted()) items")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .background(.bar)
    }

    private func resultHeader(_ result: DiskScanResult) -> some View {
        HStack(spacing: 24) {
            summaryValue("Scanned content", bytes: result.displayedSize)
            if let used = result.volumeUsedCapacity {
                summaryValue("Used on volume", bytes: used)
            }
            if let scannedAt = state.scannedAt {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last scan").font(.caption).foregroundStyle(.secondary)
                    Text(scannedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                }
            }
            Spacer()
            if result.skippedItemCount > 0 {
                Label("\(result.skippedItemCount.formatted()) unreadable items", systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var browserHeader: some View {
        HStack(spacing: 10) {
            Button("Back", systemImage: "chevron.left") {
                state.navigateBack()
            }
            .labelStyle(.iconOnly)
            .disabled(!state.canNavigateBack)

            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            Text(state.currentDirectoryName)
                .font(.headline)
                .lineLimit(1)
            if let directoryURL = state.currentDirectoryURL {
                Text(displayPath(directoryURL))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var browserList: some View {
        let items = state.children()
        if items.isEmpty {
            ContentUnavailableView(
                isScanning ? "Waiting for contents" : isStopped ? "No completed contents" : "This folder is empty",
                systemImage: isPartialScan ? "folder.badge.clock" : "folder",
                description: Text(
                    isScanning
                        ? "Ready folders will become available while the rest of the disk is scanned."
                        : isStopped
                            ? "Only folders completed before the scan stopped are available."
                            : "No files or folders were found."
                )
            )
        } else {
            List(items) { item in
                itemRow(item)
            }
            .listStyle(.inset)
        }
    }

    private func itemRow(_ item: DiskExplorerViewState.BrowserItem) -> some View {
        HStack(spacing: 10) {
            Button {
                state.open(item)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundStyle(item.isDirectory ? Color.blue : Color.secondary)
                    Text(item.name)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.isDirectory)

            status(item.status)
                .frame(minWidth: 92, alignment: .leading)

            if let size = item.allocatedSize {
                Text(size, format: .byteCount(style: .file))
                    .monospacedDigit()
                    .frame(minWidth: 92, alignment: .trailing)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 92, alignment: .trailing)
            }

            if canRefresh(item) {
                Button("Refresh folder", systemImage: "arrow.clockwise") {
                    state.refresh(item)
                }
                .labelStyle(.iconOnly)
                .disabled(state.refreshingURL != nil)
                .overlay {
                    if state.refreshingURL == item.url {
                        ProgressView().controlSize(.mini)
                    }
                }
            }

            Button("Reveal in Finder", systemImage: "folder") {
                state.revealInFinder(item)
            }
            .labelStyle(.iconOnly)

            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                state.requestDeletion(of: item)
            }
            .labelStyle(.iconOnly)
            .disabled(!state.canDelete(item))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func status(_ status: ScannedDirectory.Status) -> some View {
        switch status {
        case .waiting:
            Label("Waiting", systemImage: "clock").foregroundStyle(.secondary)
        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Scanning")
            }
            .foregroundStyle(.blue)
        case .cancelled:
            Label("Stopped", systemImage: "stop.circle.fill").foregroundStyle(.orange)
        case .completed:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .partial(skippedItemCount):
            Label("Partial", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("\(skippedItemCount) items could not be read")
        case .skipped:
            Label("Skipped", systemImage: "minus.circle").foregroundStyle(.secondary)
        case let .failed(message):
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(message)
        }
    }

    private func summaryValue(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes, format: .byteCount(style: .file))
                .font(.headline)
                .monospacedDigit()
        }
    }

    private var isScanning: Bool {
        if case .scanning = state.phase { return true }
        return false
    }

    private var isRestoring: Bool {
        if case .restoring = state.phase { return true }
        return false
    }

    private var isPartialScan: Bool {
        switch state.phase {
        case .scanning, .stopped: true
        default: false
        }
    }

    private var isStopped: Bool {
        if case .stopped = state.phase { return true }
        return false
    }

    private func displayPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard state.currentRootURL?.path == "/.nofollow", path.hasPrefix("/.nofollow") else {
            return path
        }
        let visiblePath = String(path.dropFirst("/.nofollow".count))
        return visiblePath.isEmpty ? "/" : visiblePath
    }

    private func canRefresh(_ item: DiskExplorerViewState.BrowserItem) -> Bool {
        guard case let .loaded(result) = state.phase else { return false }
        return item.isDirectory && item.url != result.root.url
    }
}

#Preview("First Launch") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            diskAccessRequester: StubDiskAccessRequester.denied
        )
    )
}

#Preview("Last Scan") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            diskAccessRequester: StubDiskAccessRequester.denied,
            initialPhase: .loaded(StubDiskScanner.preview.result)
        )
    )
}
