import Foundation

struct DeveloperArtifactAnalyzer: ArtifactDetecting {
    private struct ProjectContext {
        let project: DeveloperProject
        let path: String
        let rules: [DetectorRule]
    }

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
        let projectContexts = projects.map { project in
            let markerNames = Set(project.markerURLs.map(\.lastPathComponent))
            let rules = projectRules.filter { rule in
                rule.scope == .project
                    && !project.ecosystems.isDisjoint(with: rule.ecosystems)
                    && (rule.projectMarkers.isEmpty || !markerNames.isDisjoint(with: rule.projectMarkers))
            }
            return ProjectContext(
                project: project,
                path: normalized(project.rootURL.path),
                rules: rules
            )
        }
        let projectsByRoot = Dictionary(grouping: projectContexts, by: \.path)
        var artifactsByURL: [URL: DeveloperArtifact] = [:]
        var pending: [(node: FileNode, projects: [ProjectContext])] = [(root, [])]

        while let entry = pending.popLast() {
            let node = entry.node
            let nodePath = normalized(node.url.path)
            var activeProjects = entry.projects
            if let contextsAtNode = projectsByRoot[nodePath] {
                activeProjects.append(contentsOf: contextsAtNode)
            }

            if node.isDirectory {
                for context in activeProjects where nodePath != context.path {
                    guard nodePath.hasPrefix(context.path + "/") else { continue }
                    let relative = String(nodePath.dropFirst(context.path.count + 1))
                    for rule in context.rules {
                        guard matches(relative, suffixes: rule.pathSuffixes),
                              rule.id != "cmake-build" || isConfirmedCMakeBuild(node)
                        else { continue }
                        merge(
                            artifact(for: node, project: context.project, rule: rule),
                            into: &artifactsByURL
                        )
                    }
                }

                if let artifact = systemDetector.detect(node: node) {
                    merge(artifact, into: &artifactsByURL)
                }
            }

            if let children = node.children {
                for child in children.reversed() {
                    pending.append((child, activeProjects))
                }
            }
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
