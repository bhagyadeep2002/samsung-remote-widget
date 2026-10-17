# Apple Watch motion remote: session handoff

Privacy cleanup (2026-10-17): before any remote was configured, both local branches
were rewritten to remove personal gesture videos, raw sensor exports, per-trial
JSON analysis and sensor plots, and anonymize author/committer identities. Old
commit hashes are superseded. A private backup of the original history and
recordings is stored outside this repository under the user's Documents folder;
never upload it. Ignore rules prevent accidental re-addition of these files.
Historical sample filenames below refer to private inputs absent from a clone.
Aggregate assessment documents, derived numeric classifier templates, signing
identifiers and all application code are preserved. Source behavior is unchanged;
no application or hardware tests were needed or run for this cleanup. Git history,
identity, removed-path and content-preservation checks are recorded by the
cleanup session. The Downloads repository remains an unchanged separate copy.

Repository location (2026-10-17): the Watch working folder was moved to
`~/Desktop/Projects/samsung-tv-remote-widget` and converted from a linked Codex
worktree into an independent Git repository. History, `main`, the active
`feature/apple-watch-motion-remote` branch, source files, samples and ignored
local build outputs were preserved. The separate Downloads working copy has
uncommitted Mac changes and was left untouched; it is no longer the Git storage
for this folder. Continue Watch development from the Desktop Projects folder.
No remote is configured yet. File hashes and pre-commit working status matched
after migration. No application behavior changed or hardware tests were run.

Latest implementation: **live held finger volume is implemented**, following the
user's “do it”. Control TV is the default mode and requires a connection. Hold,
wait for scoped link acknowledgment and GO, make one gesture/rest, keep holding
until automatic recognition (~2.5 s after sensing begins), then release. At most
one step per hold; Still/Unsure send nothing. Test and labeled Record modes remain.
This bounded first version reuses the validated complete-window classifier; no
claim of instantaneous or continuously repeating recognition.

Release/drag/system cancel/inactivity/disconnection/fault/timeout stops locally
and revokes the activation; no release callback classifies or sends in Control TV.
Sensing stops at the first decision, while the held activation remains valid
until release (10 s maximum). Existing motion-scoped permits, 250 ms intent age,
one in-flight send and final socket cancellation gate are reused unchanged.
Missing/busy permits drop the consumed gesture; no queue or retry. Commands
already transmitted/in transit can finish. No Mac transport, TLS, credentials or
phone protocol changes.

Verification: **100 tests pass** (90 prior +10 held-session tests), signed mobile
build and strict nested signatures pass. Tests cover delayed begin after release,
one decision, Still/Unsure, stale/future samples, slow classifier/timers, maximum
hold, old generations, dropped permits and release revocation at the final gate.
Native prefix replay of the 2.5 s sensing window on 16 sufficiently long saved
trials yields 11 correct decisions and 5 Unsure, with no wrong-direction command;
the shorter old Down trial is ineligible. This replay includes training data and
is not fresh hardware validation. New live Watch/TV behavior is pending.
Build: `build/DerivedData-FingerLive`. Updated live Watch app installed successfully
and launched on the physical Watch. Live TV behavior awaits user validation. The existing iPhone app already supports this unchanged scoped
protocol, so no phone reinstall is required for this Watch-only change.

Latest physical validation: after the GO timing correction was installed and
launched, the user was asked to retest Up and Down and reports “done works”.
Record both directions as qualitatively user-confirmed in the completed-hold
preview. No trial counts, latency, Still/ordinary-movement false-positive rate,
or sustained-use accuracy were supplied. The correction delays GO until after
the classifier's discarded leading samples; labels/templates were not reversed.
No TV commands are sent by the finger preview yet. Next milestone is guarded
volume delivery while explicitly held; release must cancel unsent work, so do
not attach a post-release preview result directly to the existing live send path.

Latest physical preview feedback: user reports **Up interpreted as Down**. This
establishes the preview was installed/run through the manual route; earlier CLI
installation failures are historical. Down/Still behavior is not yet known.
Do not treat this as a confirmed global direction inversion or swap model labels.
The existing Python/Swift replay checks establish code parity, not fresh accuracy.

Found an independent cue/preprocessing mismatch: GO appeared as soon as touch
settling finished, while the classifier discards the first 300 ms after settling.
An immediate gesture could therefore be clipped. Move GO to after the discarded
300 ms plus one sample interval. Keep the training templates, feature extraction,
labels and vote unchanged. This fixes the timing contract, not a proven cause of
the reported Up→Down. Both record and test modes use the later cue. Fresh hardware
validation is required; if the error remains, capture fresh labeled Up/Down
trials using the existing recorder/export rather than guessing a label flip.
Verification for the cue correction: all 90 tests pass, signed mobile build and
strict nested signatures pass. The synthetic preprocessing reference remains
unchanged, confirming the model's input calculation was preserved. Corrected
Watch app installed successfully. No physical direction fix is claimed yet.

Current checkpoint: updated export has **17 valid trials (6 Up / 6 Down / 5
Still)**, with ~99.6 Hz sampling and no large gaps. F2 analysis and plots are in
`samples/FINGER_GESTURE_ANALYSIS_V2.md`, `finger-gesture-assessment-v2.json`, and
`finger-gesture-traces-v2.png`. Exploratory whole-trial held-out scores range
13–16/17. The conservative boundary-trimmed 3-neighbor vote accepts 12/17,
all 12 correct, and leaves 5 Unsure. This is one wearer/collection batch with
class-order and boundary-motion confounds, not independent hardware accuracy.

F3 **completed-hold preview** is implemented. Watch defaults to Test gestures:
hold, wait for GO, perform one gesture/rest, release after 2–3 seconds to display
Up/Down/Still/Unsure. It sends **zero TV commands** and does not persist guesses
as labeled training data. Switch Test gestures off to use the labeled recorder.
The model applies only to the recorded left-wrist/crown-right/raw-acceleration
configuration; unsupported sources/orientations return Unsure. Continuous
while-held recognition, real volume integration and broader negatives remain
pending fresh physical preview testing.

Verification: all 90 macOS tests pass (83 prior +7 classifier). Python/Swift
features and predictions match on all 17 records (max feature error 1.45e-14).
Signed iPhone/embedded Watch build and strict nested signatures pass. No Mac
transport or credentials changed. Direct Watch installation failed twice because
CoreDevice could not establish its tunnel (RemotePairingError 1001). This preview
has not been installed or physically tested. Use Xcode's SamsungTVRemoteWatch
scheme, actual Watch destination, Cmd-R. Do not reset/re-pair as a prerequisite.
Build: `build/DerivedData-FingerCapture`. Earlier checkpoints below are history.

Latest physical data checkpoint: user supplied `samples/finger-gesture-export.json`.
It contains **one Up, one Down, zero Still trials**, not the full requested set.
Both records are version 2, raw acceleration + device-motion rotation, left
wrist/crown right, with finite monotonic samples at 99.6 Hz and maximum interval
10.05 ms. Up duration 3.28 s (327 acceleration/328 rotation samples); Down 1.56 s
(156/155). This establishes successful physical capture and iPhone export after
the API fix. It does not establish finger recognition or repeatability. F2
assessment is recorded in `samples/FINGER_GESTURE_ANALYSIS.md`; no classifier was
trained because independent test trials and negative examples are absent.
Next hardware input: at least four additional Up, four additional Down, five
Still; wait for phone counts 5/5/5 before exporting again. If already recorded,
wait for remaining transfers and re-export. F3 stays pending those data.

Sensor availability fix verification: 83 tests pass; signed build and strict
nested signatures pass. Corrected iPhone app installed and launched; corrected
Watch app installed successfully on retry after the first transfer timed out.
User should try a single held Up trial and confirm a Saved result plus nonzero
acceleration/rotation sample rates before collecting the full set. Physical
recording success remains unverified.

Latest hardware correction: user reports “Raw motion sensors unavailable” on the
first finger recording attempt. The raw-pair preflight was too strict; at least
one raw service is unavailable (which one was not measured). The recorder now
uses device-motion rotationRate, plus raw acceleration if available or
`gravity + userAcceleration` otherwise. Version 2 JSON labels this acquisition
source; legacy version 1 remains readable. Update both Watch and phone.
Physical sample acquisition still needs confirmation. See FINGER_GESTURE_PLAN.md.

Latest user decision: the app-active wrist version works but feels janky. User
provided `samples/volume_up.MOV` / `samples/volume_down.MOV` and confirmed these
are **finger gestures with a mostly still wrist**. Hold-to-detect is acceptable
for the initial version. This supersedes the app-active wrist interaction below.
Read [FINGER_GESTURE_PLAN.md](FINGER_GESTURE_PLAN.md) first: F1 adds held labeled
raw sensor capture, F2 checks physical signal separability, F3 adds recognition
and guarded volume only after evidence. The videos alone cannot establish a
finger recognizer. Automatic wrist activation is now off; taps remain usable.
Current capture UI explicitly says recognition is not yet enabled.
F1 recording build passes 80 tests and strict nested signatures; both updated
apps installed and launched successfully on the physical iPhone and Watch.
Use `build/DerivedData-FingerCapture`. Next hardware step: five Up, five Down,
five Still trials, send to iPhone, export JSON. Physical acquisition and signal
separability have not yet been verified. See the finger plan's F1 checkpoint.

## Start here

For the current staged plan, read
[WATCH_IMPLEMENTATION_PLAN.md](WATCH_IMPLEMENTATION_PLAN.md). It updates the
transport proposal below using Apple's watchOS restrictions and is the progress
ledger for M0/M1.

Branch: `feature/apple-watch-motion-remote`.

Latest interaction decision (2026-10-17): user confirmed the corrected physical
preview direction, then questioned having to hold the screen and explicitly
asked for “app is on, twist to change.” **Hold-to-activate is rejected for this
version.** App entering active foreground and completing its TV connection now
starts quiet calibration automatically, then wrist gestures send actual volume.
The user's app-active choice supersedes the earlier proposed hold/clutch gate.
Existing fresh-locked-phone reconnect limitation remains explicitly deferred.

Live motion implementation: new WatchMotionController/MotionControlView replace
WatchMotionPreview/MotionActivationControl. No held touch or ten-second touch
limit. Motion continues only while the app is active, connected and calibrated.
Pause stops locally immediately; Resume/Recalibrate creates a new activation.
Range/off-axis/stale-data faults stop motion and ask for Recalibrate rather than
silently generating a corrective volume change. Ordinary twists while active
can count; user was told this tradeoff. Direction/axis preferences remain saved.

Each calibration has a UUID and monotonically increasing activation sequence
within the phone-issued foreground session. Begin/end and scoped heartbeats
issue immutable 500 ms permits; gestures require cached permits and a local age
under 250 ms. Missing permits/busy link drop the step with zero queued intents.
Both processor and phone cap motion at 4 steps/s. Late begin after end cannot
resurrect a cancelled activation; old end/heartbeat cannot cancel a new one.
The final socket-write validity closure rechecks activation and deadline. No
command replay, handshake per step, credential changes, or background runtime.
One write already started/in transit may still reach TV after pause; it cannot
be recalled. UI reports socket send separately from TV execution.

Verification: 72/72 Mac tests passed (54 prior +18 new). Final signed mobile
build, strict nested signatures and actual-device authorization pass. Lifecycle tests include delayed admission cancellation, only one
already-started write, no follow-up queue, late begin/end/replies, recalibration,
stale intents, scope forgery, rate limits and continuous operation beyond ten
seconds. Added begin/end acknowledgment barriers, old-scope heartbeat rejection,
and invalidation of cached tap permits during motion. These cover Pause/Resume
and tap fallback without late-reply scope confusion. The final iPhone package
installed successfully. Direct Watch installation failed twice with a closed
remote connection/device disconnect; iPhone CLI launch timed out. Watch live-build
installation/launch is unconfirmed. Run SamsungTVRemoteWatch with the actual Watch
destination in Xcode (Cmd-R); do not reset or re-pair. Use
`build/DerivedData-MotionLive`, not the old preview build. Actual automatic
motion-to-TV behavior still needs the user's Watch/TV test; do not mark M5 tuned.

Physical motion direction result (2026-10-17): user says preview seems to work,
except clockwise shows decrease and anticlockwise increase. This is actual
sensor/direction feedback for the current setup; axis and threshold tuning are
not comprehensively accepted. Correct the Watch preview sign using Reverse
direction. New Watch builds default the preview correction to reversed and save
explicit direction choices by wrist/crown/axis, plus the chosen axis. The pure
processor's mathematical sign convention is unchanged. Other configurations
remain unverified. User was told how to flip the existing installed preview
immediately. Corrected clockwise -> + / anticlockwise -> − still needs a quick
physical confirmation before motion-to-TV integration. Signed mobile build and
strict nested signature checks passed; updated iPhone/Watch packages installed,
both apps launched successfully. Existing inversion tests already
cover both signs; no tests were rerun for this defaults/preferences-only change.
No TV sends from motion.

Current motion checkpoint (2026-10-17): user reports fresh reconnect while
phone stays locked “not really” works, explicitly defers it (“not important rn”)
and asks to proceed with motion. Accept that limited operating envelope for
this prototype; unlock/open iPhone when connecting. Keep iPhone Keychain
WhenUnlockedThisDeviceOnly and existing pins/tokens unchanged. Do not restart
that investigation as a prerequisite for the requested direction preview.

M3 pure gesture processor is implemented and tested. M4's **diagnostic preview**
is implemented: hold-to-start, quiet neutral calibration, release/drag-exit/system
cancel stop, ten-second hold cap, live sample-cadence/angle/direction labels,
wrist/crown metadata, case X/Y selection and inversion. Sensor acquisition,
processor, UI and existing TV delivery remain separate. **Motion sends zero TV
commands**; taps still use the existing transport. Actual motion-to-TV delivery
must implement activation-specific cancellation and pass physical direction
validation first. Hold interaction, axis/sign and thresholds remain prototype
hypotheses; no user has yet verified them physically.

Verification: 54/54 Mac tests passed (37 prior +17 gesture), signed iPhone and
embedded Watch build passed; strict nested signatures and actual-device profile
authorization passed. Watch SDK 27.0 exposes the required Core Motion and Watch
orientation APIs; current Apple docs were checked. A watchOS-unavailable
DisclosureGroup was caught by the device build and replaced with a plain
expand/collapse setup button. Use `build/DerivedData-MotionPreview`. Mobile
build installed and launched on both physical devices. No raw motion recordings
or TV changes from motion were made. Next: user holds still, then twists
clockwise/anticlockwise in preview; confirm actual samples, comfortable holding
and the mapping before enabling TV.

Latest user validation (2026-10-17): user completed the manual Xcode Run step
for the permit-refresh optimization, then reports “it feels better.” Record this
as qualitative physical latency improvement; no new timing values, p95 or exact
reduction were supplied. Watch volume remains user-confirmed working. The
user then reports “works with locked home,” understood as the locked-phone
test just requested: continued Watch volume works while iPhone is locked. Exact
duration was not supplied. This verifies continued use of the existing connection;
reconnect/relaunch while locked remains unverified because credentials use
WhenUnlockedThisDeviceOnly. Next test offline/reconnect with no delayed taps.
User then answered yes to the explicit offline test: disable iPhone Wi-Fi and
Bluetooth in Settings, try one Watch tap, restore both/reconnect, and observe
no delayed volume change until a new tap. Record physical non-replay for that
scenario; do not generalize to all disconnect races. Next test a fresh connection:
lock iPhone, leave Watch app for 10 seconds (beyond its 2-second socket lease),
then reopen/connect while iPhone stays locked. This may expose the current
WhenUnlockedThisDeviceOnly credential restriction and needs hardware evidence
before any accessibility/security decision. Sustained operation and Mac
coexistence still need physical acceptance before motion; exact latency
measurements remain open.

Measured M2 tap (2026-10-17): user reports last tap reply **414 ms**, iPhone
send **9 ms**, permit request **239 ms**. This is one sample, not p95 or TV reaction
time. The permit acquisition accounts for 239 ms of that tap-to-reply interval;
175 ms remain for command exchange/handling/reply. Do not infer one-way latency
or confirmed TV execution from those values.

Identified the avoidable permit wait: Watch cached a permit only until request
start +250 ms, conflating the **tap** age limit with the relay's existing **500 ms
permit** lifetime. A 239 ms reply left just 11 ms of cached validity. The loop
also waited another 200 ms after each reply, creating a 439 ms refresh cycle.
Fixed Watch caching to use request start +500 ms, a conservative local bound
because the phone issues the permit after that request starts. Phone expiry is
unchanged and still checked at the final socket write. Actual taps still expire
at 250 ms. Heartbeat cadence now counts request transit toward the 200 ms
interval, with only one heartbeat in flight and no catch-up queue. At the observed
239 ms RTT, refresh starts after the previous reply without another 200 ms wait.
Late/duplicate older replies cannot replace or restore a consumed newer permit.
All 37 tests pass, including the existing Mac suite and the new timing/order
regressions. Signed iPhone/embedded Watch build and strict nested signature
verification pass. iPhone update installed and launched. Two Watch install
attempts failed (immediate disconnect, then tunnel timeout); optimized Watch
installation is unconfirmed. Use SamsungTVRemoteWatch + actual Watch destination
and Run in Xcode, as previously successful. Do not repeat unlock/pair/reset
requests without new evidence. New physical timings are still needed before
claiming a latency improvement.

Latest M2 hardware result (2026-10-17, supersedes the failures below): user
reports the corrected Watch app “works perfectly,” then estimates a 0.6–0.8 s
response delay, apparently on every tap (“everytap?”). This confirms observed
Watch-to-TV volume delivery and resolves the prior no-response/blinking report.
It also provides user evidence that the corrected Watch build was run after the
manual Xcode instruction; CLI installation itself was not verified. Do not claim
precise measured latency, p95, a two-minute test or locked-phone operation.
Phone foreground/background condition is still unspecified for this report.

Code review confirms warm connection reuse and no deliberate 600–800 ms delay.
Some taps need a fresh-permit round trip before their command; current evidence
cannot assign the observed delay to that, WatchConnectivity, socket send or TV
reaction. Added a Watch timing readout: last tap-to-reply duration (Watch clock),
optional permit-request duration (Watch clock), and iPhone step-handler/socket
send duration (iPhone clock). Timings do not compare clocks and do not measure
TV execution or true one-way latency. No command limits, queues, retry policy or
transport changed. Signed mobile build, nested signature verification and all
33 host tests passed. Updated timing builds installed on both actual devices;
both apps launched successfully. Next collect a few tap readings and compare them with the perceived TV response;
keep M2 latency/background/offline gates open before motion.

M2 hardware follow-up (2026-10-17): user confirms iPhone TV pairing succeeds.
On Watch, readiness appears briefly, the Connect button remains visible, volume
buttons blink, and no volume change is observed before the default connect text
returns. Confirmed a UI timing bug: button enabled state was tied to a 250 ms
permit window while heartbeat sleeps 200 ms after each reply, producing gaps
once message latency is included. Connection readiness is now independent from
single-use permits; Connect becomes Disconnect during a live session. A tap with
no current permit may request one once, with the original 250 ms local tap
expiry unchanged. No command is retried and the relay's 500 ms deadline remains.
Heartbeat replies no longer overwrite command results. Stops now retain a
specific reason (Watch paused, phone unreachable, TV lost, session expired);
expired local taps show elapsed milliseconds. The iPhone also shows sent/expired
volume results. No claim yet that the TV volume issue is resolved physically.
Regression verification: 33/33 tests pass, including permit-latency gaps,
late replies, cancellation and unchanged tap deadlines. Mobile rebuild passed;
the iPhone update installed and launched. First Watch update attempt disconnected
immediately after connecting; two subsequent install attempts timed out, including
after user confirmed Watch was awake/connected. Latest failure is CoreDevice
4000 / RemotePairingError 1001 (device tunnel negotiation timeout). CoreDevice
still shows Watch as connecting. Watch installation and physical volume
revalidation are not yet confirmed for this fix. Do not blame device unlock or
repeat pairing/reset requests without new evidence. User can try the existing
SamsungTVRemoteWatch scheme and actual Watch destination with Run in Xcode;
install via CLI when native connectivity recovers. No TV pairing changes needed.

M2 implementation update (2026-10-17): both apps were confirmed present and
reachable, completing M1 connectivity acceptance. iPhone TV pairing and large
Watch volume buttons are now implemented. Shared transport preserves certificate
pinning and Keychain credentials; Watch commands use live, short-lived permits,
no queued taps and no replay. Mac build/tests pass 29/29. Signed mobile builds
and actual-device provisioning checks pass. See the M2 ledger in the plan for
interfaces, defaults and verification. Physical TV pairing, volume response and
locked/background-phone relay are still unverified; motion must wait for that
gate. Use `build/DerivedData-M2`, rather than old M1 products. The iPhone profile
expires October 23 and the Watch profile October 24; rebuild as needed.

M2 installation checkpoint: final iPhone package installed and launched on the
physical iPhone 15. The first Watch update lost its Xcode connection; after the
user confirmed it was connected/awake, retry installed M2 on the physical Watch
successfully; direct process launch also succeeded. The separate Watch-destination build timed out while reconnecting;
the successfully installed package is the already-validated embedded Watch app
from the signed iPhone build. No resets or pairing changes were made. TV hardware
acceptance remains open.

The following installation investigation is historical and superseded by the
M1 success and M2 update above.

Latest update (2026-10-17, supersedes the blockers below): user reports native
Xcode pairing now works but opening the Watch app gives an integrity error.
Confirmed macOS 27.0.1 / Xcode 27.1 and physical Watch SE 3 connected in
CoreDevice. Built `SamsungTVRemoteWatch` for its actual destination using
automatic provisioning/device registration in `build/DerivedData-M1-PhysicalWatch`.
Decoded profile explicitly authorizes this Watch; signature verification passed.
Direct Watch installation and process launch both succeeded. The iPhone
companion was also rebuilt, installed and launched; its embedded Watch profile
authorizes the Watch.
The new profile expires 2026-10-24 14:42:28 UTC; a new development build is needed
after expiry. User now confirms both apps are present and reachable, completing
M1 physical connectivity acceptance. Next is M2: secure TV pairing on iPhone,
tappable Watch volume and physical relay validation, including locked-phone
behavior. M2 remains unstarted; no TV or motion functionality was added in this fix.

The working macOS menu bar app remains intact. M1 adds isolated iPhone and
watchOS shell targets with live WatchConnectivity activation/reachability status;
TV pairing, volume controls, and gesture implementation have not started. The
user has an iPhone 15 on iOS 27 and an Apple Watch SE 3 on watchOS 27, and accepts
the paired-iPhone relay dependency. Targets use iOS 17 / watchOS 10 minimums.

Build/signature and Simulator checks passed; Mac suite passed 17/17. Restoring
standard `Watch/` embedding with `WKApplication` made the companion appear in
Available Apps on the user's iPhone. Physical discovery now passes, but tapping
Install fills the circle and returns to Install; Watch launch remains pending.

Latest blocker (2026-10-17): decoded the profile from the actual embedded Watch
bundle. Its only authorized device is this Mac; the actual Watch is absent.
The iPhone host profile separately includes the iPhone. Earlier nested signature
checks passed, but that did not establish Watch device authorization. Xcode's
device tools still expose no physical Watch; watchOS DDI is installed/usable.

Latest retry: legacy wired Watch trust now succeeds. A separate fresh
connection (autopair disabled) verified an authenticated Watch session and the
expected identity. The first script reported `SessionActive` only because it
validated the same active session twice; this was corrected with fresh-session
verification. Developer trust records are outside Git with mode 0600.

Next: user declined installing the diagnostic logging profile; respect that
choice and do not request it again. It was opened for review only, with no
installation confirmed. They are updating macOS themselves from approximately
26.6.2 to 27. The update is pending and is not a confirmed pairing fix. After
restart, verify OS/Xcode versions, wired iPhone connection and native Watch
discovery. Existing legacy Watch trust is verified; preserve its records. If
Watch appears, provision its actual identifier and inspect the embedded Watch
profile before installing/launching. M1 physical acceptance remains open.

Pairing follow-up: user screenshot confirms Device Hub stays at `Waiting to
pair` after Watch approval. A first-person Xcode 27 forum report describes the
same symptom and reports success by temporarily powering off iPhone, pairing
Watch directly with Mac, then turning iPhone back on:
https://developer.apple.com/forums/thread/837517. The user tried it: with iPhone off, Mac disappeared from the Watch device list
on the same Wi-Fi. The workaround failed here; restore iPhone power. Mac logs
show its manual-pairing Bonjour listener ready and advertising; Wi-Fi IPv6 is
Automatic with a link-local address and the application firewall is disabled.
No network settings changed. Check whether Mac reappears with iPhone back on;
Watch discovery/registration remains unresolved. Do not erase/unpair Watch.

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
- User owns an iPhone 15 on iOS 27 and an Apple Watch SE 3 on watchOS 27. They
  accepted using the iPhone as the Watch relay. Whether foreground phone use is
  acceptable if locked/background relay fails is still unanswered and belongs
  to the M2 transport gate. Hold-to-activate/release-as-clutch also remains a
  proposal pending activation/usability evidence.
- M1 implementation is present in this worktree; M2 TV pairing and tappable
  volume are the next implementation milestone.

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
| `Sources/iOS/` | M1 iPhone companion shell and WatchConnectivity lifecycle coordinator |
| `Sources/Watch/` | M1 Watch shell and WatchConnectivity lifecycle model |

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

## Watch implementation sequence and current state

1. **M0 decision and M1 shells are implemented.** The iPhone relay and device
   versions are recorded in the plan. The generated Watch app is a modern
   single-target watchOS application whose companion identifier points to the
   iPhone target. The iPhone app is installed/launched on the iPhone 15. The
   user's prior shell screenshot showed Watch bridge `Active`, Watch app `Watch
   app not installed`, and TV `Not paired`. A later package audit fixed a
   malformed Watch icon-catalog platform value, rebuilt the signed package, and
   reinstalled/launched the host; the user reported discovery still failed.
   The latest fresh package restores default `Watch/` embedding with the
   `WKApplication` marker and passes validation. It is installed/launched on
   iPhone. Discovery now passes; installation resets to Install. The embedded
   Watch profile authorizes only this Mac; resolve registration/provisioning
   before retrying. Physical Watch launch remains pending.
2. **M2 follows the M1 Watch launch check:** pair securely on the iPhone and
   build a freshness-bounded WatchConnectivity volume bridge with large tap
   controls. Keep TV readiness separate from iPhone/Watch reachability. Prove
   pairing, latency, send outcome and stale-command handling on the actual TV
   before adding motion.
3. Investigate locked/background phone behavior during the M2 physical gate. If
   it fails, get the user's decision on whether foreground iPhone use is an
   acceptable fallback; do not assume it.
4. After M2 passes, implement deterministic motion processing and tests, then
   integrate Core Motion with explicit activation, calibration, lifecycle stop,
   orientation handling, and physical tuning as separate plan milestones.
5. Hold-to-activate/release-as-clutch remains a proposed interaction, not a user
   decision. Sensitivity and wrist-direction mapping require actual Watch tests.
6. Keep the first scope foreground volume control. Always-on background motion,
   workouts and extended runtime are not requested and must not be assumed as
   lifecycle workarounds.

## Verification and existing build

Generate the ignored Xcode project from the source of truth:

```sh
xcodegen generate
xcodebuild -project SamsungTVRemote.xcodeproj -scheme SamsungTVRemote \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath build/DerivedData build test
```

- M1 verification reran the existing Mac suite: 17 tests passed (8 connection,
  9 keypad). It does not prove TV behavior, physical Watch installation, or
  WatchConnectivity operation on the owned devices.
- iOS Simulator and generic iOS/watchOS SDK builds passed. The iPhone 16e
  Simulator installed/launched the iPhone shell; there is no watchOS Simulator
  runtime installed. Generic iOS signing and nested iPhone/Watch code-signature
  verification passed. The iPhone 15 app was also installed and launched after
  the user approved its first launch. After the user's screenshot reported
  `Watch app not installed`, a clean asset-catalog audit found that the Watch
  icon manifest used `platform: "watchOS"`; Xcode 27.1 warned that this value
  was unknown and omitted the Watch `Assets.car`. Changing it to `watchos`
  produced a Watch `Assets.car` and removed those asset warnings. The current
  build includes `WKApplication = true`, has the matching companion identifier,
  passes embedded-binary and nested signature validation, and is installed and
  launched on the iPhone 15. The user confirmed this icon update did not fix
  discovery. A subsequent fresh build removed the `PlugIns/` override and passed
  validation with the Watch app under `Watch/`. It was installed/launched on the
  iPhone 15. The user now sees the app in Available Apps, but installation
  resets. The embedded Watch profile contains only the Mac's device identifier;
  device authorization and physical Watch launch remain open. See the plan.
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
