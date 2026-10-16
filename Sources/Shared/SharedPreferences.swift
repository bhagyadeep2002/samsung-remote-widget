import Foundation

enum SharedPreferences {
    static let defaults = UserDefaults.standard

    private enum Key {
        static let host = "tvHost"
        static let status = "connectionStatus"
    }

    static var host: String {
        defaults.string(forKey: Key.host) ?? ""
    }

    static var status: String {
        defaults.string(forKey: Key.status) ?? "Enter your TV address and pair."
    }

    static func saveHost(_ host: String) {
        defaults.set(host, forKey: Key.host)
    }

    static func saveStatus(_ status: String) {
        defaults.set(status, forKey: Key.status)
    }
}
