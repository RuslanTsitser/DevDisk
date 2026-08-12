import Foundation

struct DeveloperArtifactAnalyzer: ArtifactDetecting {
    private struct ProjectContext {
        let project: DeveloperProject
        let path: String
        let rules: [DetectorRule]
        let webTools: Set<String>
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
                rules: rules,
                webTools: Self.webTools(in: project)
            )
        }
        let projectsByRoot = Dictionary(grouping: projectContexts, by: \.path)
        let preparedSystemDetector = systemDetector.prepared(for: projects)
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
                        let isMatch = rule.id == "cmake-build"
                            ? isConfirmedCMakeBuild(node, project: context.project)
                            : matches(relative, rule: rule)
                        guard isMatch,
                              rule.id != "next-cache" || isConfirmedWebCache(relative, tools: context.webTools)
                        else { continue }
                        merge(
                            artifact(
                                for: node,
                                project: context.project,
                                rule: rule,
                                isOwnedByFlutter: activeProjects.contains {
                                    $0.project.ecosystems.contains(.flutter)
                                }
                            ),
                            into: &artifactsByURL
                        )
                    }
                }

                if let artifact = preparedSystemDetector.detect(node: node) {
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
        rule: DetectorRule,
        isOwnedByFlutter: Bool
    ) -> DeveloperArtifact {
        DeveloperArtifact(
            id: node.url,
            url: node.url,
            project: project,
            ecosystems: project.ecosystems.intersection(rule.ecosystems)
                .union(isOwnedByFlutter ? [.flutter] : []),
            logicalSize: node.logicalSize,
            allocatedSize: node.allocatedSize,
            artifactKind: rule.artifactKind,
            risk: rule.risk,
            cleanupPolicy: rule.cleanupPolicy,
            explanation: rule.description,
            validationMarkerURLs: project.markerURLs,
            locationEvidence: ArtifactLocationEvidence(
                kind: .projectMarker,
                detail: "Rule \(rule.id), verified by \(rule.projectMarkers.sorted().joined(separator: ", "))",
                documentationURL: nil
            )
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
            validationMarkerURLs: existing.validationMarkerURLs.union(artifact.validationMarkerURLs),
            locationEvidence: preferred.locationEvidence
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

    private func matches(_ path: String, rule: DetectorRule) -> Bool {
        let normalizedPath = normalized(path)
        if rule.id == "python-cache" {
            return normalizedPath.split(separator: "/").last == "__pycache__"
        }
        return rule.pathPatterns.contains { normalizedPath == normalized($0) }
    }

    private static func webTools(in project: DeveloperProject) -> Set<String> {
        guard let packageURL = project.markerURLs.first(where: { $0.lastPathComponent == "package.json" }),
              let data = try? Data(contentsOf: packageURL),
              let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var names: Set<String> = []
        for key in ["dependencies", "devDependencies", "optionalDependencies"] {
            guard let dependencies = package[key] as? [String: Any] else { continue }
            names.formUnion(dependencies.keys)
        }
        return names
    }

    private func isConfirmedWebCache(_ path: String, tools: Set<String>) -> Bool {
        let value = normalized(path)
        switch value {
        case ".next": return tools.contains("next")
        case ".nuxt": return tools.contains("nuxt")
        case ".vite", "node_modules/.vite": return tools.contains("vite")
        case ".turbo": return tools.contains("turbo")
        case ".nx/cache": return tools.contains("nx") || tools.contains { $0.hasPrefix("@nx/") }
        case "node_modules/.cache":
            let cacheProducers = [
                "react-scripts", "webpack", "parcel", "@parcel/core", "babel-loader",
                "eslint", "vite", "next", "nuxt"
            ]
            return !tools.isDisjoint(with: Set(cacheProducers))
        default: return false
        }
    }

    private func isConfirmedCMakeBuild(_ node: FileNode, project: DeveloperProject) -> Bool {
        guard node.isDirectory else { return false }
        let childNames = Set((node.children ?? []).map(\.name))
        guard childNames.contains("CMakeCache.txt"), childNames.contains("CMakeFiles"),
              let cache = try? String(
                contentsOf: node.url.appending(path: "CMakeCache.txt"),
                encoding: .utf8
              ),
              let sourceLine = cache.split(whereSeparator: \.isNewline).first(where: {
                  $0.hasPrefix("CMAKE_HOME_DIRECTORY:INTERNAL=")
              }),
              let separator = sourceLine.firstIndex(of: "=")
        else { return false }
        let sourcePath = String(sourceLine[sourceLine.index(after: separator)...])
        return URL(filePath: sourcePath, directoryHint: .isDirectory).standardizedFileURL
            == project.rootURL.standardizedFileURL
    }

    private func normalized(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
