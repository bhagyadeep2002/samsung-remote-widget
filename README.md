# Samsung TV Remote for Mac

Apple Watch port: [staged implementation plan](WATCH_IMPLEMENTATION_PLAN.md) and
[project history and handoff](WATCH_HANDOFF.md). The iPhone and Watch connectivity
apps now include iPhone TV pairing and tappable Watch volume, confirmed working
on the user's TV. After testing wrist control, the user chose finger gestures
instead. The current prototype can send one volume step per held finger gesture,
using the recorded examples. Test and labeled Record modes remain available. See
[FINGER_GESTURE_PLAN.md](FINGER_GESTURE_PLAN.md).

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

## Apple Watch volume setup

1. Open the iPhone app with the TV and iPhone on the same Wi-Fi.
2. Enter the TV IP address or hostname, tap **Pair with TV**, allow Local Network
   access, and approve the request on the TV. This creates a separate iPhone
   pairing; Mac credentials do not transfer.
3. Open the Watch app and tap **Connect to TV**. When the TV connection is ready,
   tap the speaker − or + button. Start with the iPhone app open.
4. Existing volume connections work with the iPhone locked. Establishing a fresh
   connection while locked is unreliable and currently deferred: unlock/open the
   iPhone app when connecting. Credentials remain restricted to an unlocked phone.

A sent message does not confirm the TV changed volume. Expired/failed taps are
not replayed; reconnect and make a fresh tap. Leaving the Watch app ends its live
session. TV volume percentages are not available.
Development-signed apps need periodic rebuilding when their profiles expire.

After a volume tap, the Watch shows the last tap-to-reply time and the iPhone's
step-handling/socket-send time. A permit-request time appears if one was needed.
These timings use each device's own clock and do not measure TV execution.

## Finger gesture volume

The current Watch build uses privately recorded finger gestures. The source
videos and raw sensor exports are excluded from this repository. The classifier
is trained on 17 recorded examples;
Up and Down were physically confirmed in preview after correcting GO timing.
Live finger-to-TV behavior still needs hardware validation.

1. Open the Watch app and connect to TV. Unlock/open the iPhone app first if a
   fresh connection fails while the phone is locked.
2. Select **Control TV** and hold **Hold for volume**. Keep still until **GO**.
3. Make one finger gesture, then rest while keeping the control held. The app
   recognizes automatically about 2.5 seconds after sensing begins and sends
   one Up or Down step. Still and Unsure send nothing.
4. When the result appears, release. Release and hold again for another step.
   This first version sends at most one step per hold, with no repeated changes
   from a fixed pose or an already consumed gesture.

Releasing early cancels the hold without classifying or sending. Dragging outside,
leaving the active app, disconnection, sensor failure or a timeout cancels sensing
and unsent work. A command already transmitted may finish. Busy/expired/failed
commands are dropped, never queued for a later hold. No TV volume percentage or
confirmed execution is claimed. A socket send is not TV feedback.

The complete recognition window takes about 2–3 seconds of holding after the
phone link is prepared. This first live version prioritizes the classifier
window the user tested; it is not continuous or instantaneous recognition.
Live sensing stops after the single decision. The activation ends on release or
a ten-second hold timeout. Automatic wrist-twist control stays off.

For preview without TV commands, choose **Test**: hold, wait for GO, perform a
gesture (or stay still), rest, then release after 2–3 seconds. This displays
Up/Down/Still/Unsure after release. Neither Control TV nor Test saves predictions
as true training labels. The model is scoped to the recorded left-wrist,
crown-right, raw-acceleration configuration; other setups need new recordings.
See [the recorded-data assessment](samples/FINGER_GESTURE_ANALYSIS_V2.md).

To collect additional labeled examples instead, choose **Record**:

1. Open the updated Watch app. Choose **Up**, then **hold to record**.
2. Keep still until **GO**, perform one Up gesture as in the video, rest briefly,
   then release after 2–3 seconds. Repeat five times. No haptic plays during
   recording because it would contaminate the sensor signal.
3. Repeat for five **Down** and five **Still** trials. For Still, keep your hand
   still in the same posture. Collect separate trials rather than several
   gestures in one recording.
4. Tap **Send recordings to iPhone**. Open the updated iPhone app and wait until
   its **Finger gesture recordings** section shows all expected counts.
5. Tap **Export gesture recordings** and save/share the JSON for analysis.

In Record mode, release saves a sufficiently long trial. Dragging outside the held control,
leaving the app, an observed disconnection or a sensor error discards an
unfinished trial. Recording automatically ends after four seconds. Touch settling
and the last 100 ms before release are excluded; the file retains actual
acceleration and rotation timestamps. Rotation comes from device motion, without
requiring direct raw gyro access. Acceleration is raw when available, otherwise
gravity plus user acceleration from device motion. Version 2 files identify the
source; update both companion apps before exporting new recordings. The displayed rate is measured, not assumed
from the requested 100 Hz. No background sensing is used.

Each companion app stores its own copies, capped at 60 trials. File transfers can
finish later; these contain sensor examples, never volume commands. Retrying
Send preserves trial IDs, so the phone does not duplicate a trial. **Clear Watch
recordings** deletes local Watch copies and cancels pending transfers; export and
check iPhone counts first. Files contain wrist/crown, device/OS and sensor data,
without TV credentials or network identifiers.

Live recognition sensitivity, response time and false-positive behavior need
physical validation beyond the existing recorded-data evaluation. See the
[finger gesture plan](FINGER_GESTURE_PLAN.md) for milestones and open questions.

## Connection tests

Run the `SamsungTVRemote` scheme's tests in Xcode with **⌘U**, or:

```sh
xcodebuild -project SamsungTVRemote.xcodeproj -scheme SamsungTVRemote -destination 'platform=macOS' test
```

These tests use fake transports to check connection reuse, rapid commands, keepalive recovery, address changes, cancellation of obsolete handshakes, and atomic command batches. Keypad tests cover the photographed layout, consecutive digits, zero, Delete, Done, restart, and recovery after an interrupted sequence. They don't send commands to a real TV or verify its focus behavior or response time.

## Git setup

The Watch development repository is an independent checkout at
`~/Desktop/Projects/samsung-tv-remote-widget`, on
`feature/apple-watch-motion-remote`. The original commit history and `main`
branch are preserved. The separate Downloads copy contains older Mac work and
is not required by this repository.

To connect an empty remote repository and push the Watch branch:

```sh
cd ~/Desktop/Projects/samsung-tv-remote-widget
git remote add origin <REMOTE_URL>
git push -u origin feature/apple-watch-motion-remote
```

Generated Xcode projects, build products and local signing configuration stay
ignored. Run `xcodegen generate` after moving the checkout or cloning it elsewhere.

## Privacy when publishing

Personal gesture videos, raw Watch exports, per-trial JSON reports and sensor
plots are excluded from every published branch's history and ignored for future
commits. Historical references to these filenames describe private local inputs;
they are not files included with a clone. Aggregate assessment documents and the
numeric classifier model remain to document and preserve the working recognizer.
The model contains derived motion features, not raw streams or capture metadata.
Reproducing the recorded-data analysis requires separately supplied recordings;
the deterministic synthetic tests do not require those private files.

Commit authors and committers have been anonymized. This checkout uses the local
Git identity `Project Contributor <contributor@example.invalid>` for new commits;
this identity does not link commits to a GitHub account. Other clones must set
their own preferred private Git identity before committing.

Existing Apple team and bundle identifiers remain in the build specification to
preserve signing and installed-app compatibility. They are identifiers, not
signing credentials. Pairing secrets remain in each platform's Keychain.
