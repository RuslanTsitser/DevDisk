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
        .fileImporter(
            isPresented: $presentsFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            state.startScan(url)
        }
    }

    private var toolbar: some View {
        HStack {
            Text("DevDisk")
                .font(.headline)
            Spacer()
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
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning \(progress.rootURL.lastPathComponent)…")
                    .font(.headline)
                Text(progress.currentURL.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("\(progress.itemsScanned.formatted()) items inspected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Cancel Scan", role: .cancel) {
                    state.cancelScan()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(result):
            VStack(spacing: 0) {
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
}

#Preview("Empty") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            initialPhase: .idle
        )
    )
}

#Preview("Scanning") {
    let root = URL(fileURLWithPath: "/Users/developer")
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
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
            initialPhase: .failed(
                "DevDisk couldn’t read this location. Choose another folder or review its privacy permissions."
            )
        )
    )
}
