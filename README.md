# Samsung TV Remote for Mac

Apple Watch port planning and next-session context: [WATCH_HANDOFF.md](WATCH_HANDOFF.md).

A macOS menu bar app for controlling a Samsung TV over your home network. Click the TV icon in the menu bar to open the remote. The app runs without a Dock icon and keeps pairing and remote controls in one popover.

Controls include navigation, select, back, home, an in-app number pad, volume, mute, play, pause, and power off. The app does not pair with or imitate the handheld Bluetooth/IR remote.

## Compatibility

Samsung's support site identifies `UA43TE50AAKXXL` with the UT5300L manual. The app uses the local Tizen remote-control WebSocket interface used by community implementations for recent Samsung TVs. Samsung does not publish this interface as a supported third-party macOS API, so the first pairing on this exact model still needs to be confirmed on the TV.

The app sends directional, select, back, home, number-pad, volume, mute, play, pause, and power-off commands. Turning the TV on from standby is not included; that depends on Wake-on-LAN or the TV's network wake setting.

## Build on the Mac

The project targets macOS 14 or later and uses XcodeGen to produce the Xcode project:

```sh
brew install xcodegen
xcodegen generate
open SamsungTVRemote.xcodeproj
```

In Xcode, choose the `SamsungTVRemote` scheme and **My Mac** as the destination. Select your Apple development team under the app target's **Signing & Capabilities**, then build and run with **⌘R**. No App Groups capability or widget extension is required.

The app appears as a **TV icon in the menu bar**, rather than opening a regular window. To keep it installed, find **Samsung TV Remote.app** under Xcode's Products group, choose **Show in Finder**, and copy it to **Applications**. Quit the development copy before opening the copy in Applications. You can add it to **System Settings → General → Login Items** to start it when you log in.

## Pair and use

1. Turn on the TV and keep it on the same home network as the Mac.
2. Open Samsung TV Remote and click its TV icon in the menu bar.
3. Expand **TV setup**, enter the TV's local IP address or network name (without a URL prefix or port), and choose **Pair with TV**.
4. Approve the request on the TV. Allow Local Network access if macOS asks. The app saves the pairing token and TV certificate fingerprint in its own Keychain storage.
5. Use the controls in the popover. The indicator means a saved pairing is available; commands report success or a connection error below the controls.

Click **123** beside Home to open both the app's number pad and the TV's virtual number-entry panel. Click digits **0–9** in the app; it moves the TV's selection with arrows and presses OK for each digit. Click **Done** to move up to the TV's Done button and confirm the number. The delete button navigates to the TV's delete control.

This navigation profile uses the photographed Live TV layout: a single row **1 2 3 4 5 6 7 8 9 0**, Delete to its right, **6 initially selected**, and Done above. It assumes selecting a digit leaves focus on that digit. Direct `KEY_0`–`KEY_9` commands are no longer sent because this TV rejects them. Each complete digit sequence runs in order over the persistent connection, with short pauses for the TV to process its UI.

Start with the TV's number pad closed before opening **123** in the app. The directional-pad icon closes the panel and switches back to arrows; closing the Mac popover also dismisses the TV's panel. Other remote controls dismiss number entry before acting, and the next digit opens a fresh panel.

The TV does not report its selected digit or whether the panel timed out. If the physical remote changes focus, the panel closes unexpectedly, or a number-entry command is interrupted, use **Restart** to close and reopen the panel with 6 selected. Restart discards the current entry. Other TV apps or keypad layouts may need a different navigation profile.

The app connects in the background at launch and when you open the remote, then reuses the authenticated WebSocket for button presses. It also keeps the socket established by pairing, so the first press after pairing needs no additional handshake. Rapid presses stay enabled and are sent sequentially over that connection. A keepalive runs every 15 seconds and reconnects after a lost connection; the app also warms the connection after the Mac wakes from sleep. A cold connection still needs time to authenticate, and response time depends on your network and TV.

If a send fails, the app reports the error and drops waiting commands instead of replaying a button that may already have reached the TV. The next click can establish a fresh connection.

If upgrading from the desktop widget version, remove the old widget and pair again in this app. The menu bar app uses its own preferences and Keychain storage, so it does not depend on the former shared App Group. Regenerate the Xcode project after updating the source to remove the old extension target.

The first pairing accepts the TV's self-signed TLS certificate for the address you entered, then pins its SHA-256 fingerprint. Later connections reject a different certificate. If the TV certificate changes, use **Forget TV…** and pair again. Pair again at the new address if the TV's IP changes.

## Network details

The app uses the TV's secure local WebSocket endpoint on port `8002`, requests on-TV approval, and sends key names such as `KEY_UP` and `KEY_VOLUP`. The TV and Mac need to be reachable on the same local network. macOS may ask for Local Network access the first time the app connects.

Samsung support pages:

- [Model support and downloads for UA43TE50AAKXXL](https://www.samsung.com/bd/support/model/UA43TE50AAKXXL/)
- [Samsung's compatible BN59-01337B basic remote](https://www.samsung.com/in/tv-accessories/tv-remote-bn59-01337b/)
- [Community reference for Samsung's token-paired TV remote interface](https://github.com/sturlese/tvremote-app)

## Connection tests

Run the `SamsungTVRemote` scheme's tests in Xcode with **⌘U**, or:

```sh
xcodebuild -project SamsungTVRemote.xcodeproj -scheme SamsungTVRemote -destination 'platform=macOS' test
```

These tests use fake transports to check connection reuse, rapid commands, keepalive recovery, address changes, cancellation of obsolete handshakes, and atomic command batches. Keypad tests cover the photographed layout, consecutive digits, zero, Delete, Done, restart, and recovery after an interrupted sequence. They don't send commands to a real TV or verify its focus behavior or response time.
