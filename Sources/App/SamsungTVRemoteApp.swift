import SwiftUI
import AppKit

@main
struct SamsungTVRemoteApp: App {
    @NSApplicationDelegateAdaptor(RemoteAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Samsung TV Remote", systemImage: "tv") {
            RemoteView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class RemoteAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        warmConnection()
    }

    @objc private func willSleep(_ notification: Notification) {
        Task { await SamsungTVClient.disconnect() }
    }

    @objc private func didWake(_ notification: Notification) {
        warmConnection()
    }

    private func warmConnection() {
        Task { try? await SamsungTVClient.prepare() }
    }
}
