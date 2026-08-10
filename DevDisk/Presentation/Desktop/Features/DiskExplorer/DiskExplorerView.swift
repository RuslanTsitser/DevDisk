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
            Task { await state.scan(url) }
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
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("\(progress.itemsScanned.formatted()) items inspected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(root):
            List([root], children: \.children) { node in
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
        case let .failed(message):
            ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle", description: Text(message))
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
            initialPhase: .loaded(emptyRoot)
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
