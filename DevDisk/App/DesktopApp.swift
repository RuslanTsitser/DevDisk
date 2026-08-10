import SwiftUI

@main
struct DesktopApp: App {
    var body: some Scene {
        WindowGroup {
            DiskExplorerView(state: DesktopCompositionRoot.makeDiskExplorerState())
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
        }
    }
}

