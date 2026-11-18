import SwiftUI

@main
struct MissionTokenLiveApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("MissionTokenLive") {
            ContentRoot()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra {
            MenuBarPanel().environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
