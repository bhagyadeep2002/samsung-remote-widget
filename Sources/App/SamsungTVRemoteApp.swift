import SwiftUI

@main
struct SamsungTVRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
                .frame(minWidth: 420, minHeight: 300)
        }
        .windowResizability(.contentSize)
    }
}
