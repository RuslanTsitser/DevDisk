import Foundation
import Observation

@MainActor
@Observable
final class DiskExplorerViewState {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case loaded(DiskScanResult)
        case failed(String)
    }

    private(set) var phase: Phase
    private let scanDisk: ScanDiskUseCase
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(scanDisk: ScanDiskUseCase, initialPhase: Phase = .idle) {
        self.scanDisk = scanDisk
        phase = initialPhase
    }

    func startScan(_ url: URL) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.scan(url)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
    }

    private func scan(_ url: URL) async {
        phase = .scanning(
            ScanProgress(rootURL: url, currentURL: url, itemsScanned: 0)
        )
        do {
            let result = try await scanDisk(url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard case .scanning = self?.phase else { return }
                    self?.phase = .scanning(progress)
                }
            }
            phase = .loaded(result)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("The selected location could not be scanned: \(error.localizedDescription)")
        }
        scanTask = nil
    }
}
