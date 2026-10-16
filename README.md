# Samsung TV Remote for Mac

A small macOS app for pairing a Samsung TV, plus an interactive desktop widget for quick remote commands. The widget talks to the TV over the home network; it does not pair with or imitate the handheld Bluetooth/IR remote.

## Compatibility

Samsung's support site identifies `UA43TE50AAKXXL` with the UT5300L manual. The app uses the local Tizen remote-control WebSocket interface used by community implementations for recent Samsung TVs. Samsung does not publish this interface as a supported third-party macOS API, so the first pairing on this exact model still needs to be confirmed on the TV.

The initial version sends directional, select, back, home, volume, mute, play, pause, and power-off commands. Turning the TV on from standby is not included; that depends on Wake-on-LAN or the TV's network wake setting.

## Build on the Mac

The project targets macOS 14 or later and uses XcodeGen to produce the Xcode project:

```sh
brew install xcodegen
xcodegen generate
open SamsungTVRemote.xcodeproj
```

Select your Apple development team in Xcode so the app and widget can use their shared App Group. Build and run `SamsungTVRemote` once to install the widget extension.

## Pair and use

1. Turn on the TV and keep it on the same home network as the Mac.
2. Open Samsung TV Remote, enter the TV's local IP address or network name, and choose **Pair with TV**.
3. Approve the request on the TV. The app saves the pairing token and TV certificate fingerprint in the shared Keychain.
4. Add **Samsung TV Remote** from the macOS widget gallery. The small widget has navigation and power-off; the medium widget also has volume and media controls.

The first pairing accepts the TV's self-signed TLS certificate for the address you entered, then pins its SHA-256 fingerprint. Later widget connections reject a different certificate. If the TV address or certificate changes, use **Forget this TV** and pair again.

## Network details

The app uses the TV's secure local WebSocket endpoint on port `8002`, requests on-TV approval, and sends key names such as `KEY_UP` and `KEY_VOLUP`. The TV and Mac need to be reachable on the same local network. macOS may ask for Local Network access the first time the app connects.

Samsung support pages:

- [Model support and downloads for UA43TE50AAKXXL](https://www.samsung.com/bd/support/model/UA43TE50AAKXXL/)
- [Samsung's compatible BN59-01337B basic remote](https://www.samsung.com/in/tv-accessories/tv-remote-bn59-01337b/)
- [Community reference for Samsung's token-paired TV remote interface](https://github.com/sturlese/tvremote-app)
