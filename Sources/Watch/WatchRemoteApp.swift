import SwiftUI

@main
struct WatchRemoteApp: App {
    @StateObject private var model = WatchRemoteModel()

    var body: some Scene {
        WindowGroup {
            VolumeRemoteView(model: model)
        }
    }
}
