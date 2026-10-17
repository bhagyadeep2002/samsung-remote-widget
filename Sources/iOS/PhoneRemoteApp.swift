import SwiftUI
import UIKit

@MainActor
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    let relay = PhoneRelayCoordinator()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Install the live-message delegate even on a Watch-initiated background launch.
        relay.activate()
        return true
    }
}

@main
struct PhoneRemoteApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            TVSetupView(relay: delegate.relay)
        }
    }
}
