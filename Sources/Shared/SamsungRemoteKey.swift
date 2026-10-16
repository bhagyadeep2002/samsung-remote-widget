import AppIntents

enum SamsungRemoteKey: String, AppEnum {
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case select = "KEY_ENTER"
    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case powerOff = "KEY_POWEROFF"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Samsung TV button")

    static var caseDisplayRepresentations: [SamsungRemoteKey: DisplayRepresentation] = [
        .up: DisplayRepresentation(title: "Up"),
        .down: DisplayRepresentation(title: "Down"),
        .left: DisplayRepresentation(title: "Left"),
        .right: DisplayRepresentation(title: "Right"),
        .select: DisplayRepresentation(title: "Select"),
        .back: DisplayRepresentation(title: "Back"),
        .home: DisplayRepresentation(title: "Home"),
        .volumeUp: DisplayRepresentation(title: "Volume Up"),
        .volumeDown: DisplayRepresentation(title: "Volume Down"),
        .mute: DisplayRepresentation(title: "Mute"),
        .play: DisplayRepresentation(title: "Play"),
        .pause: DisplayRepresentation(title: "Pause"),
        .powerOff: DisplayRepresentation(title: "Power Off")
    ]

    private static let spokenNames: [SamsungRemoteKey: String] = [
        .up: "Up",
        .down: "Down",
        .left: "Left",
        .right: "Right",
        .select: "Select",
        .back: "Back",
        .home: "Home",
        .volumeUp: "Volume Up",
        .volumeDown: "Volume Down",
        .mute: "Mute",
        .play: "Play",
        .pause: "Pause",
        .powerOff: "Power Off"
    ]

    var samsungCode: String {
        rawValue
    }

    var spokenName: String {
        Self.spokenNames[self] ?? rawValue
    }
}
