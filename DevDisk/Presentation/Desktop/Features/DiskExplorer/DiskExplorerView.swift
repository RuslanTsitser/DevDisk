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
        .frame(minWidth: 1_080, minHeight: 640)
        .task { state.appeared() }
        .alert(
            "Operation Failed",
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
            "Move rebuildable artifact to Trash?",
            isPresented: Binding(
                get: { state.artifactPendingDeletion != nil },
                set: { if !$0 { state.cancelDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            if let artifact = state.artifactPendingDeletion {
                Button("Move to Trash", role: .destructive) { state.moveToTrash(artifact) }
            }
            Button("Cancel", role: .cancel) { state.cancelDeletion() }
        } message: {
            if let artifact = state.artifactPendingDeletion {
                Text("\(artifact.name) uses \(artifact.allocatedSize.formatted(.byteCount(style: .file))). The project marker will be checked again before deletion.")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("DevDisk").font(.headline)
            if state.currentRootURL != nil {
                TextField("Search files and paths", text: $state.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                ecosystemPicker
                riskPicker
                artifactTypePicker
            }
            Spacer()
            if !state.insights.artifacts.isEmpty {
                Button("Export CSV", systemImage: "square.and.arrow.up") { exportCSV() }
            }
            if isRestoring {
                ProgressView().controlSize(.small)
            } else if isScanning {
                Button("Stop Scan", systemImage: "stop.fill", role: .cancel) { state.stopScan() }
                    .keyboardShortcut(.cancelAction)
            } else if state.currentRootURL != nil {
                Button("Scan Again", systemImage: "arrow.clockwise") { state.rescanRoot() }
                    .keyboardShortcut("r")
            } else {
                Button("Scan Disk", systemImage: "internaldrive") { state.requestScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private var ecosystemPicker: some View {
        Picker("Ecosystem", selection: $state.ecosystemFilter) {
            Text("All ecosystems").tag(DeveloperEcosystem?.none)
            ForEach(DeveloperEcosystem.allCases) { value in
                Text(value.title).tag(DeveloperEcosystem?.some(value))
            }
        }
        .labelsHidden()
        .frame(width: 145)
    }

    private var riskPicker: some View {
        Picker("Risk", selection: $state.riskFilter) {
            Text("All risks").tag(ArtifactRisk?.none)
            ForEach(ArtifactRisk.allCases) { value in
                Text(value.title).tag(ArtifactRisk?.some(value))
            }
        }
        .labelsHidden()
        .frame(width: 135)
    }

    private var artifactTypePicker: some View {
        Picker("Artifact type", selection: $state.artifactKindFilter) {
            Text("All artifact types").tag(String?.none)
            ForEach(Set(state.insights.artifacts.map(\.artifactKind)).sorted(), id: \.self) { value in
                Text(value).tag(String?.some(value))
            }
        }
        .labelsHidden()
        .frame(width: 170)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .restoring:
            loadingView
        case .idle:
            ContentUnavailableView {
                Label("See What Development Uses", systemImage: "internaldrive")
            } description: {
                Text("Choose Macintosh HD or a folder. DevDisk reads metadata locally and explains developer storage without uploading file names.")
            } actions: {
                Button("Scan Disk") { state.requestScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Scan Failed", systemImage: "exclamationmark.triangle")
            } description: { Text(message) } actions: {
                Button("Try Again") { state.requestScan() }.buttonStyle(.borderedProminent)
            }
        case let .scanning(progress): explorer(header: AnyView(scanningHeader(progress)))
        case let .stopped(progress): explorer(header: AnyView(stoppedHeader(progress)))
        case let .loaded(result): explorer(header: AnyView(resultHeader(result)))
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Loading Last Scan").font(.headline)
            Text("Restoring the saved disk contents…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func explorer(header: AnyView) -> some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let root = state.outlineRoot {
                HSplitView {
                    FileOutlineView(
                        root: root,
                        artifacts: Dictionary(uniqueKeysWithValues: state.insights.artifacts.map { ($0.url, $0) }),
                        previousSizes: state.previousDirectorySizes,
                        searchQuery: state.searchQuery,
                        ecosystemFilter: state.ecosystemFilter,
                        riskFilter: state.riskFilter,
                        artifactKindFilter: state.artifactKindFilter,
                        selectedURL: Binding(
                            get: { state.selectedURL },
                            set: { value in state.select(value) }
                        )
                    )
                    .frame(minWidth: 700)
                    insightsPane
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                }
            } else {
                ContentUnavailableView("Waiting for completed folders", systemImage: "folder.badge.clock")
            }
        }
    }

    private var insightsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Developer Insights", systemImage: "hammer.fill").font(.title3.bold())
                if let artifact = state.selectedArtifact {
                    artifactDetails(artifact)
                } else if let node = state.selectedNode {
                    nodeDetails(node)
                } else {
                    summary
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            metric("Projects", value: state.insights.projects.count.formatted())
            metric("Artifacts", value: state.insights.artifacts.count.formatted())
            metric(
                "Developer storage",
                value: state.insights.allocatedSize.formatted(.byteCount(style: .file))
            )
            let changes = state.growthSummary
            metric(
                "Directory changes",
                value: "+\(changes.added)  −\(changes.removed)  ↑\(changes.grown)  ↓\(changes.shrunk)"
            )
            Divider()
            Text("Largest artifacts").font(.headline)
            ForEach(state.insights.artifacts.prefix(8)) { artifact in
                Button {
                    state.select(artifact.url)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(artifact.name).lineLimit(1)
                            Text(artifact.artifactKind).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(artifact.allocatedSize, format: .byteCount(style: .file))
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
            Divider()
            Text("Ecosystems").font(.headline)
            ForEach(DeveloperEcosystem.allCases.filter { ecosystem in
                state.insights.artifacts.contains { $0.ecosystems.contains(ecosystem) }
            }) { ecosystem in
                let artifacts = state.insights.storageAccountingArtifacts.filter {
                    $0.ecosystems.contains(ecosystem)
                }
                aggregateMetric(
                    ecosystem.title,
                    artifacts: artifacts,
                    previousKey: "ecosystem:\(ecosystem.rawValue)"
                )
            }
            Divider()
            Text("Artifact types").font(.headline)
            ForEach(artifactTypeSummaries) { summary in
                aggregateMetric(
                    summary.kind,
                    artifacts: summary.artifacts,
                    previousKey: "type:\(summary.kind)",
                    count: summary.count
                )
            }
        }
    }

    private func artifactDetails(_ artifact: DeveloperArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(artifact.name).font(.headline).textSelection(.enabled)
            Text(artifact.url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            metric("Category", value: artifact.artifactKind)
            metric("Risk", value: artifact.risk.title)
            metric("Allocated", value: artifact.allocatedSize.formatted(.byteCount(style: .file)))
            metric("Logical", value: artifact.logicalSize.formatted(.byteCount(style: .file)))
            if let project = artifact.project { metric("Project", value: project.name) }
            Text(artifact.explanation).font(.callout).foregroundStyle(.secondary)
            HStack {
                ForEach(artifact.ecosystems.sorted { $0.title < $1.title }) { value in
                    Text(value.title).font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
            }
            if artifact.cleanupPolicy == .safeRebuildable {
                Button("Move Rebuildable Data to Trash", systemImage: "trash", role: .destructive) {
                    state.requestDeletion(of: artifact)
                }
                .disabled(state.refreshingURL != nil)
            } else {
                Label("Read-only recommendation", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func nodeDetails(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(node.name).font(.headline).textSelection(.enabled)
            Text(node.url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            metric("Allocated", value: node.allocatedSize.formatted(.byteCount(style: .file)))
            metric("Logical", value: node.logicalSize.formatted(.byteCount(style: .file)))
            metric("Files", value: node.fileCount.formatted())
            metric("Access", value: node.accessStatus.rawValue.capitalized)
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Label("Regular filesystem items are read-only in DevDisk.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func aggregateMetric(
        _ title: String,
        artifacts: [DeveloperArtifact],
        previousKey: String,
        count: Int? = nil
    ) -> some View {
        let current = artifacts.reduce(0) { $0 + $1.allocatedSize }
        let delta = state.previousCategorySizes[previousKey].map { current - $0.allocatedSize }
        let suffix = delta.map {
            $0 == 0 ? "" : " \($0 > 0 ? "+" : "−")\(abs($0).formatted(.byteCount(style: .file)))"
        } ?? ""
        return metric(
            title,
            value: "\((count ?? artifacts.count).formatted()) · \(current.formatted(.byteCount(style: .file)))\(suffix)"
        )
    }

    private var artifactTypeSummaries: [ArtifactTypeSummary] {
        let accounting = state.insights.storageAccountingArtifacts
        let groups = Dictionary(grouping: state.insights.artifacts) { artifact in
            artifact.artifactKind
        }
        var values: [ArtifactTypeSummary] = []
        for (kind, detected) in groups {
            let accounted = accounting.filter { artifact in artifact.artifactKind == kind }
            values.append(ArtifactTypeSummary(kind: kind, count: detected.count, artifacts: accounted))
        }
        values.sort { left, right in
            left.count == right.count ? left.kind < right.kind : left.count > right.count
        }
        return Array(values.prefix(12))
    }

    private func scanningHeader(_ progress: ScanProgress) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Scanning disk").font(.headline)
                Text(displayPath(progress.currentURL)).font(.caption.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("\(progress.itemsScanned.formatted()) items").font(.caption).monospacedDigit()
        }
        .padding(12).background(.bar)
    }

    private func stoppedHeader(_ progress: ScanProgress) -> some View {
        HStack {
            Label("Scan stopped", systemImage: "stop.circle.fill").foregroundStyle(.orange)
            Text("Completed folders remain available.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(progress.itemsScanned.formatted()) items").font(.caption).monospacedDigit()
        }
        .padding(12).background(.bar)
    }

    private func resultHeader(_ result: DiskScanResult) -> some View {
        HStack(spacing: 24) {
            metricHeader("Scanned", result.displayedSize)
            if let used = result.volumeUsedCapacity { metricHeader("Used on volume", used) }
            metricHeader("Developer storage", state.insights.allocatedSize)
            Spacer()
            if result.skippedItemCount > 0 {
                Label("\(result.skippedItemCount.formatted()) unreadable", systemImage: "exclamationmark.shield")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12).background(.bar)
    }

    private func metricHeader(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes, format: .byteCount(style: .file)).font(.headline).monospacedDigit()
        }
    }

    private func exportCSV() {
        do {
            try CSVArtifactExporter.export(state.insights.artifacts) { artifact in
                state.growth(for: artifact.url, currentSize: artifact.allocatedSize)
            }
        } catch {
            state.presentError("Could not export CSV: \(error.localizedDescription)")
        }
    }

    private var isScanning: Bool { if case .scanning = state.phase { true } else { false } }
    private var isRestoring: Bool { if case .restoring = state.phase { true } else { false } }

    private func displayPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard state.currentRootURL?.path == "/.nofollow", path.hasPrefix("/.nofollow") else { return path }
        let visible = String(path.dropFirst("/.nofollow".count))
        return visible.isEmpty ? "/" : visible
    }
}

private struct ArtifactTypeSummary: Identifiable {
    let kind: String
    let count: Int
    let artifacts: [DeveloperArtifact]
    var id: String { kind }
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
