import CoreServices
import Foundation

final class FSEventsFileChangeMonitor: FileChangeMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var rootURL: URL?
    private var didStartSecurityScope = false

    func startMonitoring(_ root: URL, onChange: @escaping @Sendable () -> Void) {
        stopMonitoring()
        didStartSecurityScope = root.startAccessingSecurityScopedResource()
        rootURL = root

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let box = Unmanaged.passRetained(CallbackBox(onChange: onChange))
        var context = FSEventStreamContext(
            version: 0,
            info: box.toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.75,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else {
            box.release()
            return
        }
        lock.withLock { stream = created }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(created)
    }

    func stopMonitoring() {
        let previous = lock.withLock { () -> FSEventStreamRef? in
            defer { stream = nil }
            return stream
        }
        if let previous {
            FSEventStreamStop(previous)
            FSEventStreamInvalidate(previous)
            FSEventStreamRelease(previous)
        }
        if didStartSecurityScope { rootURL?.stopAccessingSecurityScopedResource() }
        didStartSecurityScope = false
        rootURL = nil
    }

    deinit { stopMonitoring() }

    private final class CallbackBox {
        let onChange: @Sendable () -> Void
        init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    }
}
