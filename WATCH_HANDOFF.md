# Apple Watch motion remote: session handoff

## Start here

Branch: `feature/apple-watch-motion-remote`.

This branch includes the working macOS menu bar app copied from the original
Downloads checkout, plus this plan. The original checkout had these changes
uncommitted; the detached worktree initially contained only the old widget.
The original checkout and installed app were left untouched. No watchOS app or
gesture implementation has been created yet.

Suggested opening prompt for the next session:

> Read WATCH_HANDOFF.md and inspect the current app. Port this Samsung TV remote
> to Apple Watch, starting with volume control using a wrist twist like turning
> a knob: clockwise increases volume, anticlockwise decreases it. Keep the Mac
> app working. First establish a viable Watch-to-TV connection, then implement
> an explicitly activated motion mode with calibration and physical Watch
> testing. No extra hardware purchases. Resolve device and transport questions
> before assuming direct Watch WebSockets or always-on motion are supported.

## User intent and preferences

- Apple Watch remote for the existing Samsung TV.
- Main new interaction: turn the watch-wearing hand as if turning a knob;
  clockwise = volume up, anticlockwise = volume down.
- This means wrist motion, not merely rotating the Digital Crown. Crown input
  could be a useful fallback but does not fulfill the motion request by itself.
- User reported: “everything works perfectly” for the current Mac app, then
  asked how to install it, and considers that project complete.
- No extra hardware. The Watch is the requested target; don't suggest IR hubs.
- User prefers action and simple explanations; avoid repeated technical questions.
- This session is branch preparation only. Implementation belongs to the next
  session.

## Current product and history

- Original desktop widget was replaced with a macOS 14+ menu bar app after
  WidgetKit container-background and App Group issues.
- App has a TV icon and popover, no Dock icon (`LSUIElement`).
- Controls: arrows, OK, Back, Home, power off, volume, mute, play/pause, keypad.
- Pair with the TV by entering its local IP/hostname and approving on the TV.
- Pairing token and SHA-256 TLS certificate pin live in the app's private
  data-protection Keychain. Preferences use `UserDefaults.standard`.
- Keychain error -34018 was fixed with proper signing and an app-private
  `keychain-access-groups` entitlement. Do not restore the old App Group design.
- Persistent authenticated connections removed roughly a second of delay per
  click. Preserve warm connections and ordered command delivery.
- Installed-app instructions: copy the built .app to Applications, quit the
  Xcode instance first, optionally add the installed app to Login Items.

## Source map

| File | Responsibility |
| --- | --- |
| `project.yml` | XcodeGen macOS app and unit-test targets, signing, entitlements |
| `Sources/App/SamsungTVRemoteApp.swift` | MenuBarExtra, AppKit sleep/wake lifecycle |
| `Sources/App/RemoteView.swift` | Popover, pairing/setup, controls and number pad |
| `Sources/Shared/SamsungTVClient.swift` | Pairing, WebSocket transport, certificate pinning, JSON commands |
| `Sources/Shared/PersistentRemoteConnection.swift` | Actor, connection reuse, serial atomic batches, keepalive/reconnect |
| `Sources/Shared/SamsungRemoteKey.swift` | Samsung key codes including KEY_VOLUP/KEY_VOLDOWN |
| `Sources/Shared/PairingCredentialStore.swift` | Per-host token and certificate pin in Keychain |
| `Sources/Shared/SharedPreferences.swift` | TV address and status in standard preferences |
| `Sources/Shared/TVNumberPadNavigation.swift` | TV keypad navigation planner and serialized control session |
| `Tests/` | Fake-transport connection tests and keypad planner tests |

`Sources/App` imports AppKit and cannot simply be included in a watchOS target.
Audit shared APIs, Keychain queries, privacy descriptions, and deployment targets
before sharing them across platforms. The Keychain error wording currently says
macOS. Preferences and credentials do not automatically transfer to the Watch.

## TV protocol and behavior to preserve

- Secure local endpoint:
  `wss://HOST:8002/api/v2/channels/samsung.remote.control`.
- Query includes a base64 client name and the saved token after pairing.
- Wait for `ms.channel.connect` before sending commands.
- Example volume payload:

```json
{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"KEY_VOLUP","Option":"false","TypeOfRemote":"SendRemoteKey"}}
```

- First pairing accepts the TV's self-signed certificate and records its pin;
  subsequent connections verify it. Do not disable TLS verification globally.
- Existing transport coalesces concurrent handshakes, adopts the pairing socket,
  receives in the background, and uses a 15-second keepalive on macOS.
- Failed or ambiguous sends are not replayed; queued commands are dropped.
- A successful send does not prove the TV executed it. There is no measured
  absolute volume readback in this app; don't display an invented volume %.
- Watch lifecycle and power constraints require revisiting the Mac's indefinite
  keepalive behavior.

## Known setup and keypad caveat

- Samsung Wondertainment TV; README references `UA43TE50AAKXXL`, but confirm
  actual hardware if it matters rather than treating that reference as proof.
- HDMI source is a **Tata Play HD** box, not Binge+/Android.
- Direct network digit commands produced “Not available.” We implemented arrows
  and OK on the TV's virtual number bar instead.
- Photographed layout: `1 2 3 4 5 6 7 8 9 0`, Delete to the right, Done above;
  initial focus on 6. Planner tracks focus locally with timed steps.
- User later still reported “Not available” on selecting digits. We suggested
  checking Samsung SmartThings as a diagnostic; no specific result was supplied.
  Their subsequent overall report was “everything works perfectly.” Preserve
  both facts: don't claim verified Tata Play digit forwarding or reopen that
  investigation as a prerequisite for Watch volume control.
- TV focus is not observable here; timeout or physical remote use can invalidate
  the keypad assumptions. There is an explicit Restart control.

## Proposed Watch implementation sequence (not yet approved technical choices)

1. Inspect installed SDK support and ask only necessary device questions: Watch
   model/watchOS, paired iPhone availability, and whether standalone operation is
   required. No versions have been supplied yet.
2. Prove the transport on a real Watch before building gesture UX. Investigate
   direct local networking and secure WebSocket support under current watchOS
   constraints. An available Foundation API alone does not establish that this
   endpoint is usable on a Watch.
3. If a companion is needed, consider an iPhone relay via WatchConnectivity and
   explain the dependency. WatchConnectivity connects the Watch and paired iOS
   app; it is not a direct Watch-to-Mac bridge. A Mac relay would require a
   separate network design and a running Mac, which the user has not chosen.
4. Add watchOS targets without removing or breaking the macOS target. Keep
   platform-independent commands and gesture processing separate from UI and
   device networking. Pair securely on the selected transport path.
5. Deliver tappable volume +/- first, establish latency and error behavior, then
   add motion. Avoid debugging networking and sensor recognition simultaneously.
6. Prototype Core Motion wrist rotation while the app is active. Define what
   clockwise means from the user's perspective; account for wrist side, Watch
   orientation and forearm posture. Do not hardcode an unverified raw axis sign.
7. Use an explicit activation control and neutral-pose calibration. Suggested
   initial mode: hold a large on-screen control while twisting, release to stop.
   This is a proposal, not a user-specified requirement.
8. Convert relative angular displacement to discrete volume steps. Use a dead
   zone, hysteresis, smoothing and a bounded command rate. Let the user reposition
   their wrist without accidentally undoing volume changes; design a clutch or
   recenter interaction. Tune thresholds on hardware rather than inventing a
   universal sensitivity.
9. Stop sampling and discard unsent gesture steps on release, view exit, app
   inactivity, connection loss or cancellation. Limit backlog so delayed motion
   cannot keep increasing volume after the user stops. Give clear connection
   feedback and restrained haptics for sent steps, without claiming TV receipt.
10. Keep the first scope foreground volume control. Always-on background motion,
    workout sessions and extended runtime are not requested and must not be
    assumed available or used as lifecycle workarounds.

## Verification and existing build

Generate the ignored Xcode project from the source of truth:

```sh
xcodegen generate
xcodebuild -project SamsungTVRemote.xcodeproj -scheme SamsungTVRemote \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath build/DerivedData build test
```

- Last prior-session result: 17 mock tests passed (8 connection, 9 keypad).
  They were not rerun during this branch-preparation session and do not prove
  TV behavior or Watch support.
- Project uses Swift 5, macOS 14 deployment, automatic signing; existing team
  `43S9G46H25` is recorded in the YAML. Generated plist, entitlements, projects
  and build products are ignored. No tokens or certificate pins belong in Git.
- Add deterministic gesture tests when implementing: neutral jitter, direction,
  left/right orientation, reversals, angle wraparound, recentering, rate caps,
  activation/deactivation, disconnect, and stale-command cancellation.
- Simulator/mocks cannot establish real wrist recognition. Verify on the user's
  Watch and TV: deliberate twist changes volume in the intended direction,
  normal movement does nothing outside activation, releasing stops promptly,
  and offline/reconnect never replays stale volume adjustments.

## References for the next session

Consult current documentation and the installed SDK before choosing architecture:

- [Apple CMMotionManager](https://developer.apple.com/documentation/coremotion/cmmotionmanager)
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Apple watchOS networking guidance](https://developer.apple.com/videos/play/wwdc2019/716/)
- [Samsung WebSocket community implementation and command reference](https://github.com/xchwarze/samsung-tv-ws-api)

This TV protocol is a community-documented interface, not a supported Samsung
third-party watchOS SDK.
