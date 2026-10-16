enum SamsungRemoteKey: String {
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case select = "KEY_ENTER"
    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case numberPad = "KEY_MORE"
    case digit0 = "KEY_0"
    case digit1 = "KEY_1"
    case digit2 = "KEY_2"
    case digit3 = "KEY_3"
    case digit4 = "KEY_4"
    case digit5 = "KEY_5"
    case digit6 = "KEY_6"
    case digit7 = "KEY_7"
    case digit8 = "KEY_8"
    case digit9 = "KEY_9"
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case powerOff = "KEY_POWEROFF"

    var samsungCode: String { rawValue }

    var digit: Int? {
        switch self {
        case .digit0: 0
        case .digit1: 1
        case .digit2: 2
        case .digit3: 3
        case .digit4: 4
        case .digit5: 5
        case .digit6: 6
        case .digit7: 7
        case .digit8: 8
        case .digit9: 9
        default: nil
        }
    }

    var spokenName: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .numberPad: "Number Pad"
        case .digit0: "0"
        case .digit1: "1"
        case .digit2: "2"
        case .digit3: "3"
        case .digit4: "4"
        case .digit5: "5"
        case .digit6: "6"
        case .digit7: "7"
        case .digit8: "8"
        case .digit9: "9"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .play: "Play"
        case .pause: "Pause"
        case .powerOff: "Power Off"
        }
    }
}
