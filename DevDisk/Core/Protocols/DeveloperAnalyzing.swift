import Foundation

protocol ProjectDiscovering: Sendable {
    func discoverProjects(in root: FileNode) -> [DeveloperProject]
}

protocol ArtifactDetecting: Sendable {
    func analyze(_ root: FileNode) -> DeveloperInsights
}

protocol CleanupServicing: Sendable {
    func validateForCleanup(_ artifact: DeveloperArtifact) -> Bool
    func moveToTrash(_ artifact: DeveloperArtifact) throws
}
