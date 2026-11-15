import SwiftUI

@main struct MadarWatchApp: App {
    @StateObject private var store = WatchSnapshotStore()

    var body: some Scene {
        WindowGroup {
            MadarWatchHomeView()
                .environmentObject(store)
        }
    }
}
