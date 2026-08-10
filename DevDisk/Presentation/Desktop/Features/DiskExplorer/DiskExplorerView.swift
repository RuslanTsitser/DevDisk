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
        case let .scanning(url):
            ProgressView("Scanning \(url.lastPathComponent)…")
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

#Preview("Loaded") {
    DiskExplorerView(
        state: DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview)
        )
    )
}
