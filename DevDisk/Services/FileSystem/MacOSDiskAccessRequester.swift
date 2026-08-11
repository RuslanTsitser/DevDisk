import AppKit
import Foundation

@MainActor
struct MacOSDiskAccessRequester: DiskAccessRequesting {
    private let bookmarkKey = "macintosh-hd-security-scoped-bookmark"

    func restoredMacintoshHDURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale { saveBookmark(for: url) }
        return url
    }

    func requestMacintoshHDAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Allow Access to Macintosh HD"
        panel.message = "DevDisk scans file sizes locally. Your files never leave this Mac."
        panel.prompt = "Grant Access"
        panel.directoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        saveBookmark(for: url)
        return url
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveBookmark(for url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }
}
