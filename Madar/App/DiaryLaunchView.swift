import SwiftUI
import MadarCore
import MadarDesign

/// B2-1 (10 Nov): the four-step welcome is gone. The diary opens on today's page; every source and
/// calendar choice keeps its agreed default and stays in Settings. The first open only records that
/// the diary was entered, so an imported or restored diary behaves the same as a new one.
struct DiaryLaunchView: View {
    @Bindable var app: AppSession
    var body: some View {
        DiaryHomeView(app: app)
            .task {
                guard (try? AppDiaryService(app: app).hasWelcomed()) == false else { return }
                try? await app.executeDiaryCommand("diary.completeWelcome", payload: [:])
            }
    }
}
