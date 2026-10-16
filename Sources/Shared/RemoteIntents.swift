import AppIntents
import WidgetKit

struct SendRemoteKeyIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Samsung TV"
    static var description = IntentDescription("Send a remote-control command to your paired Samsung TV.")

    @Parameter(title: "Remote button")
    var key: SamsungRemoteKey

    init() {
        key = .home
    }

    init(key: SamsungRemoteKey) {
        self.key = key
    }

    func perform() async -> some IntentResult {
        do {
            try await SamsungTVClient.send(key)
            SharedPreferences.saveStatus("Sent \(key.spokenName).")
        } catch {
            SharedPreferences.saveStatus(error.localizedDescription)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct OpenRemoteSetupIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Up Samsung TV Remote"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
