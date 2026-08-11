import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum CSVArtifactExporter {
    static func export(_ artifacts: [DeveloperArtifact], growth: (DeveloperArtifact) -> Int64?) throws {
        let panel = NSSavePanel()
        panel.title = "Export Developer Storage Report"
        panel.nameFieldStringValue = "DevDisk-report.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var rows = ["path,project,ecosystems,category,risk,allocated,logical,growth"]
        for artifact in artifacts {
            rows.append([
                artifact.url.path,
                artifact.project?.name ?? "",
                artifact.ecosystems.map(\.title).sorted().joined(separator: ";"),
                artifact.artifactKind,
                artifact.risk.rawValue,
                String(artifact.allocatedSize),
                String(artifact.logicalSize),
                growth(artifact).map(String.init) ?? ""
            ].map(escape).joined(separator: ","))
        }
        guard let data = rows.joined(separator: "\n").data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
    }

    static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
