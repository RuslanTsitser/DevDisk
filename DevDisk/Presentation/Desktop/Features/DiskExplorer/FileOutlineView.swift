import AppKit
import SwiftUI

struct FileOutlineView: NSViewRepresentable {
    let root: FileNode
    let artifacts: [URL: DeveloperArtifact]
    let previousSizes: [String: DirectorySizeSnapshot]
    let searchQuery: String
    let ecosystemFilter: DeveloperEcosystem?
    let riskFilter: ArtifactRisk?
    let artifactKindFilter: String?
    let directoryStatuses: [URL: ScannedDirectory.Status]
    @Binding var selectedURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = false
        outline.rowSizeStyle = .medium

        let columns: [(String, String, CGFloat)] = [
            ("name", "Name", 330),
            ("allocated", "Allocated", 100),
            ("logical", "Logical", 100),
            ("files", "Files", 70),
            ("modified", "Modified", 120),
            ("growth", "Growth", 100)
        ]
        for value in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(value.0))
            column.title = value.1
            column.width = value.2
            column.minWidth = value.0 == "name" ? 180 : 60
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: value.0,
                ascending: value.0 == "name"
            )
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns.first

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.outlineView = outline
        context.coordinator.rebuild(from: self)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rebuild(from: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FileOutlineView
        weak var outlineView: NSOutlineView?
        private var rootItem: OutlineItem?
        private let bytes = ByteCountFormatter()
        private let date = DateFormatter()
        private var sortKey = "allocated"
        private var sortAscending = false
        private var rebuildTask: Task<Void, Never>?
        private var expansionTasks: [URL: Task<Void, Never>] = [:]
        private var expandedURLs: Set<URL> = []

        init(parent: FileOutlineView) {
            self.parent = parent
            bytes.countStyle = .file
            date.dateStyle = .short
            date.timeStyle = .short
        }

        func rebuild(from parent: FileOutlineView) {
            rebuildTask?.cancel()
            expansionTasks.values.forEach { $0.cancel() }
            expansionTasks.removeAll()
            let configuration = configuration(for: parent)
            let root = parent.root
            let selectedURL = parent.selectedURL
            rebuildTask = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) {
                    OutlineTreeBuilder.makeItem(root, configuration: configuration)
                }
                let value = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self, !Task.isCancelled else { return }
                captureExpandedURLs()
                rootItem = value
                outlineView?.reloadData()
                restoreExpandedItems()
                if let selectedURL, let row = row(for: selectedURL), row >= 0 {
                    outlineView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? OutlineItem ?? rootItem)?.children.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? OutlineItem ?? rootItem)!.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            return item.node.children?.isEmpty == false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            guard !item.hasLoadedChildren else { return true }
            let url = item.node.url
            guard expansionTasks[url] == nil else { return false }
            let node = item.node
            let configuration = configuration(for: parent)
            expansionTasks[url] = Task { [weak self, weak outlineView] in
                let worker = Task.detached(priority: .userInitiated) {
                    OutlineTreeBuilder.makeDirectChildren(node, configuration: configuration)
                }
                let children = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self, !Task.isCancelled else { return }
                expansionTasks[url] = nil
                guard let outlineView, outlineView.row(forItem: item) >= 0 else { return }
                item.replaceChildren(children)
                outlineView.reloadItem(item, reloadChildren: true)
                outlineView.expandItem(item, expandChildren: false)
                for child in children {
                    restoreExpansion(of: child, in: outlineView)
                }
            }
            return false
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let item = item as? OutlineItem, let tableColumn else { return nil }
            let identifier = tableColumn.identifier
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
                ?? makeCell(identifier: identifier)
            let node = item.node
            switch identifier.rawValue {
            case "name":
                cell.imageView?.image = statusIcon(for: node)
                cell.imageView?.imageScaling = .scaleProportionallyDown
                cell.textField?.stringValue = node.name
                if let artifact = parent.artifacts[node.url] {
                    cell.textField?.toolTip = "\(artifact.artifactKind) · \(artifact.risk.title)"
                    cell.textField?.textColor = .controlAccentColor
                } else if node.accessStatus == .inaccessible {
                    cell.textField?.toolTip = "This directory could not be read."
                    cell.textField?.textColor = .systemOrange
                } else if let status = parent.directoryStatuses[node.url] {
                    cell.textField?.toolTip = status.description
                    cell.textField?.textColor = status.textColor
                } else {
                    cell.textField?.toolTip = item.representsFilteredSubtotal
                        ? "Filtered subtotal for matching items in \(node.url.path)"
                        : node.url.path
                    cell.textField?.textColor = .labelColor
                }
            case "allocated":
                cell.textField?.stringValue = bytes.string(fromByteCount: item.allocatedSize)
            case "logical":
                cell.textField?.stringValue = bytes.string(fromByteCount: item.logicalSize)
            case "files":
                cell.textField?.stringValue = item.fileCount.formatted()
            case "modified":
                cell.textField?.stringValue = item.modifiedAt.map { date.string(from: $0) } ?? "—"
            case "growth":
                guard !item.representsFilteredSubtotal, !parent.previousSizes.isEmpty else {
                    cell.textField?.stringValue = "—"
                    cell.textField?.textColor = .secondaryLabelColor
                    break
                }
                let path = node.url.path(percentEncoded: false)
                if let previous = parent.previousSizes[path] {
                    let delta = item.allocatedSize - previous.allocatedSize
                    cell.textField?.stringValue = delta == 0
                        ? "—"
                        : (delta > 0 ? "+" : "−") + bytes.string(fromByteCount: abs(delta))
                    cell.textField?.textColor = delta > 0 ? .systemOrange : .systemGreen
                } else {
                    cell.textField?.stringValue = "New"
                    cell.textField?.textColor = .secondaryLabelColor
                }
            default: break
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView, outlineView.selectedRow >= 0,
                  let item = outlineView.item(atRow: outlineView.selectedRow) as? OutlineItem
            else { return }
            parent.selectedURL = item.node.url
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard let descriptor = outlineView.sortDescriptors.first,
                  let key = descriptor.key
            else { return }
            sortKey = key
            sortAscending = descriptor.ascending
            rebuild(from: parent)
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = text
            cell.addSubview(text)
            if identifier.rawValue == "name" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = image
                cell.addSubview(image)
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 18),
                    image.heightAnchor.constraint(equalToConstant: 18),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6)
                ])
            } else {
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4).isActive = true
                text.alignment = identifier.rawValue == "modified" ? .left : .right
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func row(for url: URL) -> Int? {
            guard let outlineView else { return nil }
            for row in 0..<outlineView.numberOfRows {
                if (outlineView.item(atRow: row) as? OutlineItem)?.node.url == url { return row }
            }
            return nil
        }

        private func captureExpandedURLs() {
            guard let outlineView else { return }
            var values: Set<URL> = []
            for row in 0..<outlineView.numberOfRows {
                guard let item = outlineView.item(atRow: row) as? OutlineItem,
                      outlineView.isItemExpanded(item)
                else { continue }
                values.insert(item.node.url)
            }
            expandedURLs = values
        }

        private func restoreExpandedItems() {
            guard let outlineView, let rootItem else { return }
            for child in rootItem.children {
                restoreExpansion(of: child, in: outlineView)
            }
        }

        private func restoreExpansion(of item: OutlineItem, in outlineView: NSOutlineView) {
            guard expandedURLs.contains(item.node.url) else { return }
            outlineView.expandItem(item, expandChildren: false)
            guard item.hasLoadedChildren else { return }
            for child in item.children {
                restoreExpansion(of: child, in: outlineView)
            }
        }

        private func configuration(for parent: FileOutlineView) -> OutlineBuildConfiguration {
            OutlineBuildConfiguration(
                artifacts: parent.artifacts,
                previousSizes: parent.previousSizes,
                searchQuery: parent.searchQuery,
                ecosystemFilter: parent.ecosystemFilter,
                riskFilter: parent.riskFilter,
                artifactKindFilter: parent.artifactKindFilter,
                sortKey: sortKey,
                sortAscending: sortAscending
            )
        }

        private func statusIcon(for node: FileNode) -> NSImage {
            guard let status = parent.directoryStatuses[node.url],
                  let symbolName = status.symbolName,
                  let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: status.description)
            else {
                return NSWorkspace.shared.icon(forFile: node.url.path)
            }
            return image
        }
    }
}

private extension ScannedDirectory.Status {
    var description: String {
        switch self {
        case .waiting: "Waiting to be scanned"
        case .scanning: "Scanning"
        case .cancelled: "Scan cancelled"
        case .completed: "Completed"
        case let .partial(skippedItemCount): "Partially scanned · \(skippedItemCount) unreadable"
        case .skipped: "Skipped"
        case let .failed(message): "Unavailable · \(message)"
        }
    }

    var symbolName: String? {
        switch self {
        case .waiting: "folder.badge.clock"
        case .scanning: "arrow.trianglehead.2.clockwise.rotate.90"
        case .cancelled: "stop.circle"
        case .partial, .failed: "exclamationmark.triangle"
        case .skipped: "minus.circle"
        case .completed: nil
        }
    }

    var textColor: NSColor {
        switch self {
        case .scanning: .controlAccentColor
        case .cancelled, .partial, .failed, .skipped: .systemOrange
        case .waiting: .secondaryLabelColor
        case .completed: .labelColor
        }
    }
}

struct OutlineBuildConfiguration: Sendable {
    let artifacts: [URL: DeveloperArtifact]
    let previousSizes: [String: DirectorySizeSnapshot]
    let searchQuery: String
    let ecosystemFilter: DeveloperEcosystem?
    let riskFilter: ArtifactRisk?
    let artifactKindFilter: String?
    let sortKey: String
    let sortAscending: Bool

    var hasActiveFilters: Bool {
        !searchQuery.isEmpty
            || ecosystemFilter != nil
            || riskFilter != nil
            || artifactKindFilter != nil
    }
}

enum OutlineTreeBuilder {
    static func makeItem(
        _ node: FileNode,
        configuration: OutlineBuildConfiguration
    ) -> OutlineItem? {
        guard !Task.isCancelled else { return nil }
        if !configuration.hasActiveFilters {
            return OutlineItem(
                node: node,
                children: makeDirectChildren(node, configuration: configuration),
                configuration: configuration
            )
        }
        let children = (node.children ?? [])
            .compactMap { makeItem($0, configuration: configuration) }
            .sorted { orderedBefore($0, $1, configuration: configuration) }
        guard !Task.isCancelled else { return nil }
        let artifact = configuration.artifacts[node.url]
        let matchesSearch = configuration.searchQuery.isEmpty
            || node.name.localizedCaseInsensitiveContains(configuration.searchQuery)
            || node.url.path.localizedCaseInsensitiveContains(configuration.searchQuery)
        let matchesEcosystem: Bool
        if let ecosystem = configuration.ecosystemFilter {
            matchesEcosystem = artifact?.ecosystems.contains(ecosystem) == true
        } else {
            matchesEcosystem = true
        }
        let matchesRisk = configuration.riskFilter == nil || artifact?.risk == configuration.riskFilter
        let matchesKind = configuration.artifactKindFilter == nil
            || artifact?.artifactKind == configuration.artifactKindFilter
        guard (matchesSearch && matchesEcosystem && matchesRisk && matchesKind) || !children.isEmpty else {
            return nil
        }
        return OutlineItem(
            node: node,
            children: children,
            configuration: configuration,
            usesNodeMetrics: matchesSearch && matchesEcosystem && matchesRisk && matchesKind
        )
    }

    fileprivate static func makeDirectChildren(
        _ node: FileNode,
        configuration: OutlineBuildConfiguration
    ) -> [OutlineItem] {
        (node.children ?? [])
            .compactMap { child in
                guard !Task.isCancelled else { return nil }
                return OutlineItem(node: child, configuration: configuration)
            }
            .sorted { orderedBefore($0, $1, configuration: configuration) }
    }

    fileprivate static func orderedBefore(
        _ lhs: OutlineItem,
        _ rhs: OutlineItem,
        configuration: OutlineBuildConfiguration
    ) -> Bool {
        let left = lhs.node
        let right = rhs.node
        if left.isDirectory != right.isDirectory { return left.isDirectory }
        let result: ComparisonResult
        switch configuration.sortKey {
        case "name": result = left.name.localizedStandardCompare(right.name)
        case "logical": result = compare(lhs.logicalSize, rhs.logicalSize)
        case "files": result = compare(Int64(lhs.fileCount), Int64(rhs.fileCount))
        case "modified":
            result = compare(
                lhs.modifiedAt?.timeIntervalSinceReferenceDate ?? -.greatestFiniteMagnitude,
                rhs.modifiedAt?.timeIntervalSinceReferenceDate ?? -.greatestFiniteMagnitude
            )
        case "growth":
            result = compare(growth(left, configuration) ?? .min, growth(right, configuration) ?? .min)
        default: result = compare(lhs.allocatedSize, rhs.allocatedSize)
        }
        if result == .orderedSame {
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        return configuration.sortAscending ? result == .orderedAscending : result == .orderedDescending
    }

    private static func growth(_ node: FileNode, _ configuration: OutlineBuildConfiguration) -> Int64? {
        configuration.previousSizes[node.url.path(percentEncoded: false)].map {
            node.allocatedSize - $0.allocatedSize
        }
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

final class OutlineItem: NSObject, @unchecked Sendable {
    let node: FileNode
    let allocatedSize: Int64
    let logicalSize: Int64
    let fileCount: Int
    let modifiedAt: Date?
    let representsFilteredSubtotal: Bool
    private let configuration: OutlineBuildConfiguration
    private var cachedChildren: [OutlineItem]?

    var hasLoadedChildren: Bool { cachedChildren != nil }

    var children: [OutlineItem] {
        cachedChildren ?? []
    }

    func replaceChildren(_ children: [OutlineItem]) {
        cachedChildren = children
    }

    init(
        node: FileNode,
        children: [OutlineItem]? = nil,
        configuration: OutlineBuildConfiguration,
        usesNodeMetrics: Bool = true
    ) {
        self.node = node
        self.configuration = configuration
        cachedChildren = children
        if usesNodeMetrics || children == nil {
            allocatedSize = node.allocatedSize
            logicalSize = node.logicalSize
            fileCount = node.fileCount
            modifiedAt = node.modifiedAt
            representsFilteredSubtotal = false
        } else {
            let includedChildren = children ?? []
            allocatedSize = Self.sum(includedChildren.map(\.allocatedSize))
            logicalSize = Self.sum(includedChildren.map(\.logicalSize))
            fileCount = Self.sum(includedChildren.map(\.fileCount))
            modifiedAt = includedChildren.compactMap(\.modifiedAt).max()
            representsFilteredSubtotal = true
        }
    }

    private static func sum(_ values: [Int64]) -> Int64 {
        values.reduce(0) { partial, value in
            let (result, overflow) = partial.addingReportingOverflow(value)
            return overflow ? .max : result
        }
    }

    private static func sum(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let (result, overflow) = partial.addingReportingOverflow(value)
            return overflow ? .max : result
        }
    }
}
