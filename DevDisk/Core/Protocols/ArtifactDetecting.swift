import Foundation

protocol ArtifactDetecting: Sendable {
    func detect(url: URL, isDirectory: Bool) -> DeveloperArtifact?
}

