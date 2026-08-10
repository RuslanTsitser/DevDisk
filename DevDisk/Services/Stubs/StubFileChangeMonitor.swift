import Foundation

struct StubFileChangeMonitor: FileChangeMonitoring {
    func startMonitoring(_ root: URL, onChange: @escaping @Sendable () -> Void) {}
    func stopMonitoring() {}
}
