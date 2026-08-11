import Foundation

struct DeveloperArtifactAnalyzer: ArtifactDetecting {
    private let projectDiscovery: any ProjectDiscovering
    private let projectRules: [DetectorRule]
    private let systemDetector: SystemArtifactDetector

    init(
        projectDiscovery: any ProjectDiscovering = ProjectDiscoveryService(),
        projectRules: [DetectorRule] = DetectorRuleLoader.loadBundledRules(),
        systemDetector: SystemArtifactDetector = SystemArtifactDetector()
    ) {
        self.projectDiscovery = projectDiscovery
        self.projectRules = projectRules
        self.systemDetector = systemDetector
    }

    func analyze(_ root: FileNode) -> DeveloperInsights {
        let projects = projectDiscovery.discoverProjects(in: root)
        let nodes = flatten(root)
        var artifactsByURL: [URL: DeveloperArtifact] = [:]

        for project in projects {
            let projectPath = normalized(project.rootURL.path)
            for node in nodes where node.isDirectory
                && normalized(node.url.path).hasPrefix(projectPath + "/") {
                let relative = String(normalized(node.url.path).dropFirst(projectPath.count + 1))
                for rule in projectRules where rule.scope == .project {
                    guard !project.ecosystems.isDisjoint(with: rule.ecosystems),
                          matches(relative, suffixes: rule.pathSuffixes),
                          rule.projectMarkers.isEmpty || !Set(project.markerURLs.map(\.lastPathComponent)).isDisjoint(with: rule.projectMarkers),
                          rule.id != "cmake-build" || isConfirmedCMakeBuild(node)
                    else { continue }
                    merge(
                        artifact(for: node, project: project, rule: rule),
                        into: &artifactsByURL
                    )
                }
            }
        }

        for artifact in systemDetector.detect(nodes: nodes) {
            merge(artifact, into: &artifactsByURL)
        }

        return DeveloperInsights(
            projects: projects,
            artifacts: artifactsByURL.values.sorted {
                if $0.allocatedSize != $1.allocatedSize { return $0.allocatedSize > $1.allocatedSize }
                return $0.url.path < $1.url.path
            }
        )
    }

    private func artifact(
        for node: FileNode,
        project: DeveloperProject,
        rule: DetectorRule
    ) -> DeveloperArtifact {
        DeveloperArtifact(
            id: node.url,
            url: node.url,
            project: project,
            ecosystems: project.ecosystems.intersection(rule.ecosystems).union(
                project.ecosystems.contains(.flutter) ? [.flutter] : []
            ),
            logicalSize: node.logicalSize,
            allocatedSize: node.allocatedSize,
            artifactKind: rule.artifactKind,
            risk: rule.risk,
            cleanupPolicy: rule.cleanupPolicy,
            explanation: rule.description,
            validationMarkerURLs: project.markerURLs
        )
    }

    private func merge(
        _ artifact: DeveloperArtifact,
        into values: inout [URL: DeveloperArtifact]
    ) {
        guard let existing = values[artifact.url] else {
            values[artifact.url] = artifact
            return
        }
        let preferred = riskRank(artifact.risk) > riskRank(existing.risk) ? artifact : existing
        values[artifact.url] = DeveloperArtifact(
            id: preferred.id,
            url: preferred.url,
            project: preferred.project ?? existing.project ?? artifact.project,
            ecosystems: existing.ecosystems.union(artifact.ecosystems),
            logicalSize: preferred.logicalSize,
            allocatedSize: preferred.allocatedSize,
            artifactKind: preferred.artifactKind,
            risk: preferred.risk,
            cleanupPolicy: preferred.risk == .rebuildable
                && existing.cleanupPolicy == .safeRebuildable
                && artifact.cleanupPolicy == .safeRebuildable
                    ? .safeRebuildable
                    : .none,
            explanation: preferred.explanation,
            validationMarkerURLs: existing.validationMarkerURLs.union(artifact.validationMarkerURLs)
        )
    }

    private func riskRank(_ risk: ArtifactRisk) -> Int {
        switch risk {
        case .userData: 5
        case .reviewFirst: 4
        case .toolManaged: 3
        case .redownloadable: 2
        case .rebuildable: 1
        }
    }

    private func flatten(_ root: FileNode) -> [FileNode] {
        var result: [FileNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            if let children = node.children { pending.append(contentsOf: children) }
        }
        return result
    }

    private func matches(_ path: String, suffixes: Set<String>) -> Bool {
        let normalizedPath = normalized(path)
        return suffixes.contains { suffix in
            let value = normalized(suffix)
            return normalizedPath == value || normalizedPath.hasSuffix("/" + value)
        }
    }

    private func isConfirmedCMakeBuild(_ node: FileNode) -> Bool {
        guard node.isDirectory else { return false }
        var pending = node.children ?? []
        while let child = pending.popLast() {
            if child.name == "CMakeCache.txt" || child.name == "CMakeFiles" { return true }
            if let children = child.children { pending.append(contentsOf: children) }
        }
        return false
    }

    private func normalized(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
