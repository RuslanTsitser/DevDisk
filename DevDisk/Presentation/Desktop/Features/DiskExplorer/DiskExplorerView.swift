import SwiftUI

struct DiskExplorerView: View {
    @State private var state: DiskExplorerViewState
    @State private var isFilteringTree = false
    @State private var expandAllRequest = 0
    @State private var shouldExpandAll = false

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
        .confirmationDialog(
            "Delete folder?",
            isPresented: Binding(
                get: { state.directoryPendingDeletion != nil },
                set: { if !$0 { state.cancelDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            if let directory = state.directoryPendingDeletion {
                Button("Move to Trash", role: .destructive) { state.moveDirectoryToTrash(directory) }
                Button("Delete Permanently", role: .destructive) { state.deleteDirectoryPermanently(directory) }
            }
            Button("Cancel", role: .cancel) { state.cancelDeletion() }
        } message: {
            if let directory = state.directoryPendingDeletion {
                Text("\(directory.name) and all of its contents will be deleted. Moving it to the Trash can be undone in Finder; permanent deletion cannot.")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("DevDisk").font(.headline)
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
                    VStack(spacing: 0) {
                        HStack {
                            if isFilteringTree {
                                ProgressView().controlSize(.small)
                                Text("Updating filtered results")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(shouldExpandAll ? "Collapse All" : "Expand All",
                                   systemImage: shouldExpandAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical") {
                                shouldExpandAll.toggle()
                                expandAllRequest += 1
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.bar)
                        Divider()
                        FileOutlineView(
                            root: root,
                            artifacts: Dictionary(uniqueKeysWithValues: state.insights.artifacts.map { ($0.url, $0) }),
                            previousSizes: state.previousDirectorySizes,
                            ecosystemFilter: state.ecosystemFilter,
                            riskFilter: state.riskFilter,
                            artifactKindFilter: state.artifactKindFilter,
                            allowedArtifactURLs: state.filteredArtifactURLs,
                            directoryStatuses: state.visibleDirectoryStatuses,
                            expansionRequest: expandAllRequest,
                            shouldExpandAll: shouldExpandAll,
                            isFiltering: $isFilteringTree,
                            selectedURL: Binding(
                                get: { state.selectedURL },
                                set: { value in state.select(value) }
                            ),
                            requestCleanup: { artifact in state.requestDeletion(of: artifact) }
                        )
                    }
                    .frame(minWidth: 700, maxHeight: .infinity)
                    insightsPane
                        .frame(
                            minWidth: 300,
                            idealWidth: 340,
                            maxWidth: 420,
                            maxHeight: .infinity
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
            } else {
                ContentUnavailableView("Waiting for completed folders", systemImage: "folder.badge.clock")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var insightsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if state.selectedURL != nil {
                        Button("Back", systemImage: "chevron.left") {
                            state.select(nil)
                        }
                        .buttonStyle(.borderless)
                        .help("Back to Developer Insights summary")
                    }
                    Label("Developer Insights", systemImage: "hammer.fill").font(.title3.bold())
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
    }

    private var summary: some View {
        let visibleInsights = state.filteredInsights
        return VStack(alignment: .leading, spacing: 12) {
            metric("Projects", value: visibleInsights.projects.count.formatted())
            metric("Artifacts", value: visibleInsights.artifacts.count.formatted())
            metric(
                state.hasActiveFilters ? "Filtered storage" : "Developer storage",
                value: visibleInsights.allocatedSize.formatted(.byteCount(style: .file))
            )
            if let changes = state.growthSummary {
                metric(
                    "Directory changes",
                    value: "+\(changes.added)  −\(changes.removed)  ↑\(changes.grown)  ↓\(changes.shrunk)"
                )
            } else {
                metric("Directory changes", value: "No previous snapshot")
            }
            Divider()
            Text("Largest artifacts").font(.headline)
            ForEach(state.insights.artifacts.prefix(8)) { artifact in
                Button {
                    state.toggleArtifactFilter(artifact)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: state.insightFilter == .artifact(artifact.url) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(state.insightFilter == .artifact(artifact.url) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text(artifact.project.map { "\($0.name) · \(artifact.name)" } ?? artifact.artifactKind)
                                .lineLimit(1)
                            Text(artifact.project == nil ? artifact.name : artifact.artifactKind)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(artifact.allocatedSize, format: .byteCount(style: .file))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(
                        state.insightFilter == .artifact(artifact.url) ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            Text("Projects").font(.headline)
            ForEach(allProjectSummaries) { summary in
                Button {
                    state.toggleProjectFilter(rootURL: summary.rootURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: state.insightFilter == .project(summary.rootURL) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(state.insightFilter == .project(summary.rootURL) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text(summary.name).lineLimit(1)
                            Text("\(summary.artifactCount.formatted()) artifacts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(summary.allocatedSize, format: .byteCount(style: .file))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(
                        state.insightFilter == .project(summary.rootURL) ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(summary.path)
            }
            Divider()
            Text("Ecosystems").font(.headline)
            ForEach(DeveloperEcosystem.allCases.filter { ecosystem in
                state.insights.artifacts.contains { $0.ecosystems.contains(ecosystem) }
            }) { ecosystem in
                let artifacts = state.insights.storageAccountingArtifacts.filter {
                    $0.ecosystems.contains(ecosystem)
                }
                Button { state.toggleEcosystemFilter(ecosystem) } label: {
                    aggregateFilterRow(
                        ecosystem.title,
                        artifacts: artifacts,
                        previousKey: "ecosystem:\(ecosystem.rawValue)",
                        isActive: state.ecosystemFilter == ecosystem
                    )
                }
                .buttonStyle(.plain)
            }
            Divider()
            Text("Artifact types").font(.headline)
            ForEach(allArtifactTypeSummaries) { summary in
                Button { state.toggleArtifactKindFilter(summary.kind) } label: {
                    aggregateFilterRow(
                        summary.kind,
                        artifacts: summary.artifacts,
                        previousKey: "type:\(summary.kind)",
                        count: summary.count,
                        isActive: state.artifactKindFilter == summary.kind
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func artifactDetails(_ artifact: DeveloperArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(artifact.name).font(.headline).textSelection(.enabled)
            Text(artifact.url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            metric("Category", value: artifact.artifactKind)
            metric("Risk", value: artifact.risk.title)
            metric("Cleanup", value: cleanupConsequence(for: artifact))
            metric("Location source", value: artifact.locationEvidence.kind.title)
            metric("Allocated", value: artifact.allocatedSize.formatted(.byteCount(style: .file)))
            metric("Logical", value: artifact.logicalSize.formatted(.byteCount(style: .file)))
            if let project = artifact.project { metric("Project", value: project.name) }
            Text(artifact.locationEvidence.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let documentationURL = artifact.locationEvidence.documentationURL {
                Link("Open source documentation", destination: documentationURL)
                    .font(.caption)
            }
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
            if state.hasActiveFilters {
                Label(
                    "The tree shows matching artifact subtotals. These values describe the whole folder.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            if node.isDirectory, node.url != state.currentResult?.root.url {
                Button("Refresh Folder", systemImage: "arrow.clockwise") {
                    state.refresh(node)
                }
                .disabled(state.refreshingURL != nil)
                Button("Delete Folder", systemImage: "trash", role: .destructive) {
                    state.requestDeletion(of: node)
                }
                .disabled(state.refreshingURL != nil)
            }
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

    private func cleanupConsequence(for artifact: DeveloperArtifact) -> String {
        if artifact.cleanupPolicy == .safeRebuildable {
            return "Moves to Trash; rebuilt by the tool"
        }
        switch artifact.risk {
        case .redownloadable: return "Read-only; use the owning tool"
        case .toolManaged: return "Read-only; manage in the owning tool"
        case .reviewFirst: return "Read-only; may contain important output"
        case .userData: return "Read-only user data"
        case .rebuildable: return "Read-only without verified project ownership"
        }
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

    private func aggregateFilterRow(
        _ title: String,
        artifacts: [DeveloperArtifact],
        previousKey: String,
        count: Int? = nil,
        isActive: Bool
    ) -> some View {
        let current = artifacts.reduce(0) { $0 + $1.allocatedSize }
        let delta = state.previousCategorySizes[previousKey].map { current - $0.allocatedSize }
        let suffix = delta.map {
            $0 == 0 ? "" : " \($0 > 0 ? "+" : "−")\(abs($0).formatted(.byteCount(style: .file)))"
        } ?? ""
        return HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            Text(title).lineLimit(1)
            Spacer()
            Text("\((count ?? artifacts.count).formatted()) · \(current.formatted(.byteCount(style: .file)))\(suffix)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private var artifactTypeSummaries: [ArtifactTypeSummary] {
        let visibleInsights = state.filteredInsights
        let groups = Dictionary(grouping: visibleInsights.artifacts) { artifact in
            artifact.artifactKind
        }
        var values: [ArtifactTypeSummary] = []
        for (kind, detected) in groups {
            let accounted = DeveloperInsights(projects: [], artifacts: detected).storageAccountingArtifacts
            values.append(ArtifactTypeSummary(kind: kind, count: detected.count, artifacts: accounted))
        }
        values.sort { left, right in
            left.count == right.count ? left.kind < right.kind : left.count > right.count
        }
        return Array(values.prefix(12))
    }

    private var allArtifactTypeSummaries: [ArtifactTypeSummary] {
        let groups = Dictionary(grouping: state.insights.artifacts) { $0.artifactKind }
        var values: [ArtifactTypeSummary] = []
        for (kind, detected) in groups {
            let accounted = DeveloperInsights(projects: [], artifacts: detected).storageAccountingArtifacts
            values.append(ArtifactTypeSummary(kind: kind, count: detected.count, artifacts: accounted))
        }
        values.sort { left, right in
            left.count == right.count ? left.kind < right.kind : left.count > right.count
        }
        return Array(values.prefix(12))
    }

    private var projectSummaries: [ProjectStorageSummary] {
        let grouped = Dictionary(grouping: state.filteredInsights.artifacts.compactMap { artifact in
            artifact.project.map { ($0, artifact) }
        }) { $0.0.rootURL }
        return grouped.compactMap { rootURL, values in
            guard let project = values.first?.0,
                  let largest = values.map(\.1).max(by: { $0.allocatedSize < $1.allocatedSize })
            else { return nil }
            let artifacts = values.map(\.1)
            return ProjectStorageSummary(
                rootURL: rootURL,
                name: project.name,
                path: project.rootURL.path,
                artifactCount: artifacts.count,
                allocatedSize: DeveloperInsights(projects: [project], artifacts: artifacts).allocatedSize,
                largestArtifactURL: largest.url
            )
        }
        .sorted {
            if $0.allocatedSize != $1.allocatedSize { return $0.allocatedSize > $1.allocatedSize }
            return $0.path < $1.path
        }
        .prefix(8)
        .map { $0 }
    }

    private var allProjectSummaries: [ProjectStorageSummary] {
        let grouped = Dictionary(grouping: state.insights.artifacts.compactMap { artifact in
            artifact.project.map { ($0, artifact) }
        }) { $0.0.rootURL }
        return grouped.compactMap { rootURL, values in
            guard let project = values.first?.0,
                  let largest = values.map(\.1).max(by: { $0.allocatedSize < $1.allocatedSize })
            else { return nil }
            let artifacts = values.map(\.1)
            return ProjectStorageSummary(
                rootURL: rootURL, name: project.name, path: project.rootURL.path,
                artifactCount: artifacts.count,
                allocatedSize: DeveloperInsights(projects: [project], artifacts: artifacts).allocatedSize,
                largestArtifactURL: largest.url
            )
        }
        .sorted { $0.allocatedSize == $1.allocatedSize ? $0.path < $1.path : $0.allocatedSize > $1.allocatedSize }
        .prefix(8).map { $0 }
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
            if state.isAnalyzing {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Developer storage").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing…").font(.headline)
                    }
                }
            } else {
                metricHeader(
                    state.hasActiveFilters ? "Filtered developer storage" : "Developer storage",
                    state.filteredInsights.allocatedSize
                )
            }
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

private struct ProjectStorageSummary: Identifiable {
    let rootURL: URL
    let name: String
    let path: String
    let artifactCount: Int
    let allocatedSize: Int64
    let largestArtifactURL: URL
    var id: URL { rootURL }
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
