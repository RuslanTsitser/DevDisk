import AppKit
import Foundation

@MainActor
struct MacOSDiskAccessRequester: DiskAccessRequesting {
    func requestDiskAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Allow Full Disk Scan"
        panel.message = "Select Macintosh HD. DevDisk only reads file metadata and stores the scan locally."
        panel.prompt = "Allow and Scan"
        panel.directoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
