import Foundation

protocol FileChangeMonitoring: Sendable {
    func startMonitoring(_ root: URL, onChange: @escaping @Sendable () -> Void)
    func stopMonitoring()
}
