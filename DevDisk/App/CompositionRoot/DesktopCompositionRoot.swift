@MainActor
enum DesktopCompositionRoot {
    static func makeDiskExplorerState() -> DiskExplorerViewState {
        let scanner = FileSystemDiskScanner()
        return DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: scanner),
            store: JSONDiskScanStore(),
            diskAccessRequester: MacOSDiskAccessRequester()
        )
    }
}
