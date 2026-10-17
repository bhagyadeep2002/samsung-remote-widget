# Apple Watch volume remote: staged implementation plan

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

Status: M4 app-active motion-to-TV delivery is implemented. User physically
confirmed corrected clockwise + / anticlockwise − in preview, then explicitly
chose opening the app instead of a screen hold as activation. Foreground entry
and connection now start quiet calibration and live gesture delivery. Pause,
inactivity, faults and connection loss cancel the activation. Final build passes;
72 tests pass. Physical live-motion TV behavior and M5 tuning remain pending.

Tappable Watch volume and continued locked-phone use are user-confirmed working.
Fresh reconnect with locked phone is unreliable and explicitly deferred by the
user. Credentials remain WhenUnlockedThisDeviceOnly. New latency measurements,
sustained-use and broader hardware matrix results remain open; no claim of full
M2/M5 hardware acceptance. Updated 2026-10-17.

Latest physical feedback: after completing the manual Xcode update, user says
the permit-refresh change “feels better.” This is qualitative improvement, not
a new timing measurement or p95 pass. Continued volume use with the locked
iPhone was then requested; user reports it works (“works with locked home,”
understood as phone in context). Continued locked-phone operation is now
user-confirmed, with exact duration unspecified. Locked reconnect/relaunch,
sustained operation, offline cancellation and Mac coexistence remain open M2
hardware gates. User subsequently answered yes to the specified radios-off test:
one Watch tap while iPhone Wi-Fi/Bluetooth are disabled, then restore/reconnect,
with no delayed volume change until fresh input. That physical non-replay case
passes; other disconnect races remain separately scoped. Next test reopening
Watch after 10 seconds away with iPhone continuously locked, to force fresh
connection/credential access after lease expiration. Do not silently widen
Keychain accessibility if this fails.

Latest user scope decision (2026-10-17): fresh Watch reconnect with iPhone locked
“not really” works; user explicitly defers this limitation (“not important rn”)
and requests motion now. Keep WhenUnlockedThisDeviceOnly unchanged. Open/unlock
the iPhone app when establishing a fresh TV connection; existing locked-phone
volume use works. Proceed with M3 and M4's diagnostic preview while remaining
M2 measurements/longer hardware checks stay open; this supersedes the blanket
“do not start motion” sequencing above for this authorized prototype. No claim
that every M2 gate passed. Motion-to-TV remains gated on physical direction
validation and its activation/cancellation delivery contract. Hold activation is
a proposed prototype default, subject to the user's physical usability test.

Current interaction decision (2026-10-17, supersedes hold proposals): user
confirmed clockwise + / anticlockwise − after the sign correction, then asked
for app-active twisting without holding/tapping to arm. Implement app-active
automatic calibration and real motion volume. No extra activation touch or
ten-second hold limit; app foreground/connection plus calibration are the scope.
Pause and Recalibrate remain available. Existing sample/range bounds and command
expiry/rate/backlog rules remain. New entry/reconnect calibrates a fresh neutral
pose; no old motion is replayed. This explicitly revises the earlier rule that
wake/reconnect never auto-arm, within the user's foreground-only request.

Read this plan alongside [AGENTS.md](AGENTS.md) and
[WATCH_HANDOFF.md](WATCH_HANDOFF.md). The handoff records history; this plan
updates its open transport proposal using current Apple documentation and the
installed SDK. Current code and later explicit user decisions take precedence.

## 1. Requirements and proposed defaults

### User requirements

- Control the existing Samsung TV from Apple Watch using a wrist twist like
  turning a knob: clockwise increases volume, anticlockwise decreases it.
- Define direction from the wearer's perspective and verify it on their Watch.
  Digital Crown input alone does not satisfy this requirement.
- Preserve the working macOS menu bar app, its signing, credentials, persistent
  connection behavior, and other controls. No extra hardware purchases.
- Establish transport and tappable volume controls before integrating motion.
- Begin with explicit activation and neutral-pose calibration; operate only
  while the Watch app is active. Stop and discard pending gesture work on
  deactivation, cancellation, inactivity, or loss of connection.
- Keep sensor acquisition, deterministic processing, UI, and delivery separate.
  Bound command rate and backlog; preserve TLS pinning and Keychain storage.
- Show actual connection and activation state. A socket send is not proof of TV
  execution; there is no absolute volume readback in the existing protocol code.

### Proposed defaults, subject to the gates below

- Use WatchConnectivity live messages to a companion iPhone app. The iPhone
  owns pairing and the persistent TV WebSocket. The user has an iPhone 15 on
  iOS 27, an Apple Watch SE 3 on watchOS 27, and accepted the relay dependency.
- Start with large Volume + and Volume − buttons. Add a large hold-to-activate
  motion control after the transport gate passes. Release acts as a clutch:
  reposition freely, then hold again to establish a new neutral pose.
- Treat the wearable as a relative detented knob: displacement produces steps;
  holding a fixed angle produces no repeated changes. A reversal deliberately
  produces the opposite direction after hysteresis. Automatic spring-return
  behavior is not part of this default.
- Pair afresh from the iPhone; keep its token and pin there. Transfer only
  nonsecret connection state to Watch. Existing Mac pairing remains separate.
- Select iOS 17+ and watchOS 10+ minimums for the SwiftUI companion and
  single-target Watch app. These are below the user's reported OS versions.
- Haptics acknowledge activation and limited local send events, never confirmed
  TV execution. Keep tappable controls available when motion is unavailable.

Foreground operation, hold activation, phone dependency, and sensitivity are
separate decisions. The iPhone relay is accepted. Whether foreground phone use
is an acceptable fallback if locked/background relay fails, the particular
hold/clutch interaction, and sensitivity remain open for their relevant gates.

Out of scope: background gesture recognition, workouts, extended runtime,
complications, standalone promises, new hardware, cloud relays, keypad/Tata Play
investigation, power-on support, and restoration of widgets or App Groups.

## 2. Platform findings and architecture decision

Checked on 2026-10-17. Links in section 11 are primary Apple sources.

| Finding | Consequence |
| --- | --- |
| Apple TN3135 classifies `URLSessionWebSocketTask` as low-level networking. Ordinary Watch apps cannot use it; permitted cases concern active audio streaming, CallKit calls, or a specific tvOS discovery service. | The Samsung `wss://HOST:8002/api/v2/channels/samsung.remote.control` endpoint is not a supported direct Watch transport for this remote. Do not use audio or call APIs to bypass the restriction. [A1] |
| watchOS 9 fixed earlier accidental access; Simulator allows low-level networking. | A Simulator connection cannot overturn this conclusion. No speculative direct-WebSocket milestone is needed. [A1] |
| `WCSession` connects a Watch app and its paired iOS app; the SDK marks it unavailable on macOS. | A Watch/Mac bridge needs a separately designed network service. It is not supplied by WatchConnectivity. [A2] |
| An active Watch app can wake its reachable iPhone counterpart through `sendMessage`. Delivery is asynchronous and can fail. | An iPhone relay is a documented candidate, but continuous low-latency operation with a locked/background phone remains a hardware gate. Never promise an indefinitely running phone socket. [A3, A4] |
| Local-network access must be established on iPhone. An undetermined request from the background is denied without a prompt. | Enter the host, request access, and pair in foreground iPhone setup before Watch use. Prefer manual IP/hostname entry; no Bonjour discovery or multicast entitlement is needed for this scope. [A5] |
| Core Motion supplies processed attitude and rotation rate; availability and actual update frequency vary. | Check service and reference-frame availability, use sensor timestamps, and verify real Watch samples. Do not depend on a magnetometer or a particular maximum frequency. [A6] |
| A Watch app may become inactive when the wrist lowers, even while its UI remains visible in Always On. | Gate motion on active scene state; visibility is insufficient. Reactivation requires a fresh explicit activation and calibration. [A7] |
| `kSecUseDataProtectionKeychain` is safe across platforms and ignored outside macOS. It does not transfer items between devices. | Keep the Mac query intact, choose iPhone accessibility deliberately, and validate signing and lock behavior on device. [A8] |

**Proposed path:** Watch UI and motion → live WatchConnectivity messages →
iPhone command coordinator → pinned, persistent Samsung WebSocket → TV.
The Mac remains an independent remote and is not required to run.

The Watch owns no TV credentials on this path. Raw motion samples stay on Watch;
only discrete volume intents cross the bridge. iPhone reachability, TV pairing,
and TV channel readiness are three distinct states.

**Decision gate (recorded):** the user has an iPhone 15 on iOS 27, an Apple
Watch SE 3 on watchOS 27, and accepted the paired-iPhone relay dependency.
Standalone operation is not required. A possible alternative is Watch HTTP(S) to
a running Mac service, then the existing TV socket, but that introduces server security,
service discovery, deployment, and Mac-availability work. It is not approved or
specified here. There is no demonstrated Samsung HTTP volume endpoint in this
repository. Do not invent one or silently fall back to direct WebSockets.

### Installed tools and SDK audit

Read-only checks found:

- Active developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Xcode **27.1**, build **27A9275**; XcodeGen **2.46.0**.
- watchOS device and Simulator SDKs **27.0**; iOS device and Simulator SDKs
  **27.1**; macOS SDK **27.0**.
- Installed Watch SDK headers expose `CMMotionManager` device-motion updates,
  reference-frame selection, gyro data, and `WKInterfaceDevice.wristLocation`
  and `crownOrientation`. `WCSession.h` exposes live messages and explicitly
  excludes macOS. Header availability is not runtime or sensor verification.
- `project.yml` currently records Xcode 27.0, Swift 5, and macOS 14. Keep existing
  Mac settings unless an actual generator/build issue requires a documented fix.
- SDK enumeration printed sandbox cache/FSEvents warnings but exited
  successfully. The installed iOS Simulator runtime is 18.6; no watchOS
  Simulator runtime is installed. An iPhone 16e simulator is available, but no
  physical iPhone or Watch was attached. The user's iPhone 15 / iOS 27 and Apple
  Watch SE 3 / watchOS 27 are reported facts, not local installation evidence.
- Automatic signing/provisioning and embedded Watch product signing were later
  verified as recorded in the M1 ledger below.

## 3. Current source baseline and affected files

The repository retains its Mac app and one macOS unit-test target. M1 adds
separate iPhone and Watch shell sources; no TV transport, tappable volume or
motion processing is present on those targets. The existing 17 tests cover
connection mocks and keypad planning, not TLS integration, Watch networking, or
motion. They passed during M1 verification.

| Existing file | Planned handling |
| --- | --- |
| `project.yml` | M1 adds companion/Watch schemes, targets, platform-scoped settings, source membership and generated plist properties. Preserve Mac bundle ID `com.indigital.samsungtvremote`, team `43S9G46H25`, sandbox, private Keychain group, and macOS 14 minimum. |
| `Sources/App/*` | Mac only; preserve AppKit UI and sleep/wake handling. Do not include these files in mobile targets. |
| `Sources/Shared/SamsungRemoteKey.swift` | Reuse volume codes. The bridge accepts only the volume subset, not arbitrary keys or JSON. |
| `Sources/Shared/SamsungTVClient.swift` | Share with iPhone after availability audit. Add an explicit volume delivery entry point with freshness/session context, distinct from keypad actions; preserve existing Mac entry points and TLS behavior. |
| `Sources/Shared/PersistentRemoteConnection.swift` | Preserve warm sockets, pairing adoption and serialization. Add opt-in cancellation/deadline checks at the final write boundary plus state observation and mobile lifecycle policy. Keep default Mac behavior compatible. |
| `Sources/Shared/PairingCredentialStore.swift` | Retain Mac service/accounts and storage. Add platform-neutral errors and explicit iPhone accessibility for new items; no migration or change to existing Mac access. |
| `Sources/Shared/SharedPreferences.swift` | Reuse local host storage if useful; persisted status is not a live readiness signal. No cross-device defaults assumptions. |
| `Sources/Shared/TVNumberPadNavigation.swift` | Preserve Mac behavior/tests. Existing client references require membership on iPhone unless dependencies are separated; do not port keypad UI. Watch should not compile this transport stack. |
| `Tests/PersistentRemoteConnectionTests.swift` | Retain all tests; extend for opt-in expiration/cancellation and loss during queued work. |
| `Tests/TVNumberPadNavigationTests.swift` | Retain as regression coverage for shared command changes. |

Proposed new files/directories (names are contracts for planning, not generated
artifacts or a requirement to create empty files):

| Path | Responsibility / first milestone |
| --- | --- |
| `Sources/Watch/WatchRemoteApp.swift`, `VolumeRemoteView.swift`, `WatchRemoteModel.swift` | M1 SwiftUI shell and observable WCSession activation/reachability state; tappable volume remains M2. |
| `Sources/iOS/PhoneRemoteApp.swift`, `TVSetupView.swift`, `PhoneRelayCoordinator.swift` | M1 companion shell and relay lifecycle state; TV setup/pairing remains M2. |
| `Sources/Bridge/VolumeBridgeProtocol.swift` | Versioned value types, volume allowlist, request outcomes and validation; M2. Shared by Watch/iPhone and host tests. |
| `Sources/Watch/WatchVolumeBridge.swift`, `Sources/iOS/PhoneVolumeBridge.swift` | WCSession adapters, activation/deactivation, reachability, message encoding; M2. |
| `Sources/Shared/VolumeCommandDelivery.swift` | Volume admission, bounded queue, permits/session cancellation; M2. Used by iPhone; testable without WCSession. |
| `Sources/Gesture/MotionSample.swift`, `GestureConfiguration.swift`, `WristTwistProcessor.swift` | Framework-independent sample types, coordinate contract, pure state machine; M3. |
| `Sources/Watch/WatchMotionSource.swift`, `MotionActivationControl.swift` | Core Motion adapter, orientation metadata, touch cancellation and integration; M4. |
| `Tests/VolumeBridgeTests.swift`, `VolumeCommandDeliveryTests.swift`, `WristTwistProcessorTests.swift` | Deterministic protocol, deadline/race, and gesture coverage; M2–M4. |
| `Tests/Fixtures/Motion/` | Small sanitized numeric fixtures and metadata once recorded with consent; M5. No tokens, pins, network identifiers, or unrelated recordings. |
| `WATCH_IMPLEMENTATION_PLAN.md`, `WATCH_HANDOFF.md`, `README.md` | Progress ledger, device findings, installation/operating limitations; each milestone. |

### Target boundaries

- Use bundle IDs `com.indigital.samsungtvremote.ios` and
  `com.indigital.samsungtvremote.ios.watchkitapp`. The Watch companion
  identifier points to the iPhone ID. Use Xcode's modern single-target Watch
  `application` target with `WKApplication = true` and
  `WKCompanionAppBundleIdentifier`; do not add legacy `WKWatchKitApp` or
  `WKAppBundleIdentifier` keys. Use XcodeGen's default Watch-content embedding
  under the iPhone app's `Watch/` directory. The earlier probe failed while the
  Watch plist lacked `WKApplication`; the resulting `PlugIns/` workaround was
  based on incomplete metadata. A fresh device build with the marker present
  passes `ValidateEmbeddedBinary` in the default `Watch/` location. The override
  has been removed. Build validation alone does not establish system discovery
  or installation on the physical Watch. Apple documents `WKApplication` as
  the marker for a single-target Watch app [A12].
- Keep current shared transport sources on Mac and iPhone only. Watch includes
  Watch UI, bridge value types/adapters and pure gesture sources. Pure gesture
  and bridge tests can run in a separate host macOS test target without AppKit
  or WCSession. Add mobile tests only where SDK/lifecycle integration needs them.
- Scope macOS deployment, hardened runtime, sandbox/network client entitlements
  to Mac; do not copy them wholesale to iOS/Watch. Generate mobile configuration
  from YAML. Preserve the existing Mac test scheme and all source dependencies.
- iPhone plist: local-network purpose string. Watch plist: motion purpose string
  explaining activated wrist-volume control. Verify actual API authorization and
  error behavior on supported OS versions; never imply all Core Motion APIs use
  one permission model. No microphone, HealthKit, workout, App Group, or speculative
  background-mode capabilities.

## 4. Interfaces and invariants

Interfaces below describe responsibilities and semantics; Swift names may be
adjusted during implementation without changing the guarantees.

| Interface | Inputs / outputs | Required semantics |
| --- | --- | --- |
| `MotionSource.start(generation:onSample:)`, `stop()` | Timestamped `MotionSample`, sensor errors, orientation metadata | One serial acquisition stream; stop releases resources and ignores callbacks from an old generation. No UI or network sends. |
| `MotionSample` | Monotonic seconds, normalized device-to-reference quaternion, rotation rate, gravity, user acceleration | Document units, axis basis and quaternion order. Values are immutable plain numeric types usable in host tests. |
| `WristTwistProcessor.handle(event)` | Activate, sample, deactivate, connection loss, configuration; returns calibration/state updates or `VolumeIntent` | Deterministic, no clock reads, sleeps, Core Motion objects, persistence, or network. Time arrives in events. |
| `VolumeIntent` | Up/down one step, activation generation, sample time | An intent is consumed once. No absolute percentage or accumulated multi-step burst. |
| `VolumeBridge` | Prepare/status, begin activation, refresh permit, step, end activation, close foreground session | Live WCSession adapters use property-list payloads; all callbacks enter a serialized coordinator. No delayed background-transfer API carries commands. |
| `VolumeCommandDelivery` | Validated step plus current session/permit and monotonic relay time | Bounded admission; checks freshness and generation before admission and immediately before every socket write, including after any await. |
| `PersistentRemoteConnection` extension | Optional command validity context, cancellation by session, connection-state events | Reuse authenticated socket; no ambiguous replay. A gesture step requires an already-ready channel; it must not wait through reconnect. Existing Mac batches retain atomic ordering. |
| `TVPairingService` / existing client facade | Host, explicit pair/forget, credential store, state changes | First-use trust only during explicit pairing; pin thereafter. Pin mismatch is a pairing/security error, never silently replaced. |
| `WatchRemoteModel` | Bridge state, gesture state, user/lifecycle events | Main-actor UI; can activate only when active, live relay/session ready, TV ready, and sensors usable. Stops on any lost precondition. |

### Connection, credential and command rules

1. Preserve the saved SHA-256 leaf-certificate pin, token query, channel-connect
   authentication wait, handshake coalescing and pairing-socket adoption. iPhone
   setup approves a separate TV pairing; credentials never traverse WCSession.
2. Preserve the Mac Keychain namespace and entitlement. On iPhone propose
   `WhenUnlockedThisDeviceOnly` initially. Locked-phone testing determines whether
   this prevents required reconnects; widening accessibility to
   `AfterFirstUnlockThisDeviceOnly` is an explicit security/product decision,
   recorded with evidence, not a silent workaround. Never use iCloud sync here.
3. The existing connection actor has an unbounded command array; the keypad
   session adds another queue. Task cancellation alone does not remove requests.
   Neither currently supplies per-gesture expiration. Do not feed motion through
   these queues unchanged. The new volume path bypasses keypad planning and
   carries validity through to the final transport boundary.
4. Use at most one volume write in flight and one replaceable unsent volume
   intent per Watch session. Discard old unsent work on reversal or replacement;
   drop excess displacement rather than accumulating a delayed burst. Enforce
   the command-rate cap at both Watch and relay. Tap requests are also bounded
   and short-lived; buttons have no initial auto-repeat.
5. Once a send begins, execution may be ambiguous. Do not retry on timeout,
   lost reply, or WCSession error. Deduplicate identifiers without resending;
   reconnect prepares future input only. Surface “Send outcome unknown” where
   appropriate, not “TV changed volume.”
6. Transport loss must publish state promptly and invalidate gesture generations
   and permits. The current receive-loop `invalidate` only clears the socket;
   mobile integration must additionally drop gesture work. Any delayed connect,
   receive, permission, or send callback must match the current generation.
7. Keep the socket warm for a live foreground Watch session, not indefinitely
   from iPhone launch. Prepare before enabling controls; suspend/close on session
   end, expired foreground lease, lost reachability, or iOS suspension. Assess
   the current 15-second ping interval on device. Preserve Mac sleep/wake policy.

### Bridge protocol and expiration across devices

Version 1 message header: protocol version, kind, phone-issued foreground-session
ID, activation ID where applicable, monotonically increasing sequence, and unique
request ID. Step payload allows exactly one `up` or `down` and includes an opaque
relay-issued permit ID. No arbitrary host changes, token, pin, raw Samsung
payload, or arbitrary key code is accepted from a step message.

Prepare/status returns a nonsecret pairing/configuration revision and independent
relay/channel state. Begin activation succeeds only for a ready TV and returns a
short-lived permit. End invalidates that activation. Replies echo IDs and report
`sentToSocket`, `expired`, `cancelled`, `notReady`, `rejected`, or `unknown`.
Out-of-order/duplicate/old-session messages cannot create new work. A new TV host,
pairing revision, Watch switch or phone process invalidates old session IDs.

Do not compare Watch uptime with iPhone uptime or rely on matching wall clocks.
The relay stores each permit's immutable deadline using its own monotonic clock;
the Watch echoes its ID. Propose a **500 ms** permit lifetime and refresh no more
often than every **200 ms** while actively held. A refresh issues a new permit;
it never extends an older command's deadline. Keep permit storage bounded and
discard expired IDs. Watch uses its own monotonic age limit for local intents.
For taps, obtain a similarly bounded ready-session permit. Expired permits cause
input to be discarded; never replay it after obtaining a new permit.

The relay rechecks the permit after any handshake/admission wait and immediately
before the WebSocket send. Gesture steps never initiate a handshake; a lost
channel ends activation. A control-session heartbeat while the Watch is active
has a separate proposed **2-second** lease for socket maintenance. That longer
lease never authorizes a volume step or extends its permit. Session/permit
refreshes use live messages, not persistent user-info transfers.

On release, synchronously clear Watch pending work and stop sampling, then send
best-effort end activation. At relay receipt, invalidate it before further writes.
A remote process cannot know about release before its message arrives; a step
already in transit or sent cannot be recalled. The finite permit and single
in-flight write bound this race. Acceptance is zero unsent local work after stop,
zero relay writes after cancellation is processed or permit expiry, and at most
one already-started ambiguous send. Do not promise instant remote cancellation.
If measured latency makes these limits unusable, fail the transport gate and
revise the dependency/interaction; do not lengthen queues to disguise it.

## 5. State transitions

Connection and gesture are separate state machines. Readiness requires a recent
live relay reply; a saved token or persisted status is insufficient.

| Connection state | Trigger → next state / action |
| --- | --- |
| `unconfigured` / `needsPairing` | Foreground iPhone setup → `pairing`; Watch shows “Set up on iPhone.” |
| `pairing` | TV approval, pin/token saved, authenticated socket adopted → `ready`; denial/timeout/storage failure → actionable setup error. |
| `relayUnavailable` | Activated WCSession plus live preparation request → `connecting`; no automatic command replay. |
| `connecting` | Verified TV channel and session established → `ready`; failure → `disconnected`/`needsPairing`/pin error. Controls stay disabled. |
| `ready` | Receive failure, reachability loss, TV off, lease expiration, host/credential revision or session change → invalidate gesture first, then `disconnected` or setup state. |
| `disconnected` / error | Explicit retry or foreground preparation → `connecting`; fresh ready state never reactivates motion. |
| Any | Watch inactive/exit → end foreground session, invalidate activation and pending work; reentry prepares a new session. |

| Gesture state | Trigger → next state / action |
| --- | --- |
| `idle` | Hold begins with active scene and ready transport → start sensors and `calibrating`; otherwise remain idle with reason. |
| `calibrating` | Stable sample window and permit received → capture neutral quaternion and `active`; release, timeout or failed precondition → stop, clear, `idle`/`unavailable`. No commands during calibration. |
| `active` | Valid filtered angular displacement crossing → one step intent; no displacement → no command. |
| `active` | Excess off-axis motion, invalid sample/gap or comfortable range limit → invalidate activation and `recenterRequired`; no automatic recenter while sending. |
| `recenterRequired` | Release → `idle`; reposition while inactive, then a new hold/calibration. |
| Any sampling state | Release, touch cancel/drag exit, max hold timeout, view disappearance, scene non-active, disconnect, sensor error or session switch → immediate local stop and invalidation. |
| `unavailable` | Motion unsupported/permission failure → tappable volume remains available if connected; retry only through an explicit activation after resolution. |

All stop paths share one idempotent operation. UI changes on the main actor;
generation checks protect against queued sensor callbacks and late async replies.

## 6. Gesture processing design

### Wearer perspective and coordinates

Tutorial wording proposal: “Imagine a knob in front of you, viewed from your
side looking toward the TV. Turn your watch-wearing hand clockwise to turn the
volume up.” Keep a comfortable raised forearm and the display readable. This
viewing convention is a proposal that must be confirmed by the user, especially
for left-wrist use; do not infer clockwise from a raw positive gyro axis.

Read wrist location and crown orientation. Map the watch-case longitudinal axis
to an estimated forearm axis in the neutral-pose coordinate frame. Store mapping
and direction as configuration, with an explicit inversion correction confirmed
by a silent preview. Wrist/crown metadata does not prove anatomical alignment;
strap placement and posture require real samples.

Use normalized attitude quaternions and relative rotation against calibration,
with documented device-to-reference convention. Maintain quaternion hemisphere
continuity (`q` and `−q` describe the same pose). Extract the twist component about
the calibrated forearm axis using swing/twist decomposition. Unwrap successive
twist angles across ±π, rejecting implausible jumps and stale timestamps. Avoid
subtracting Euler roll directly, which is posture dependent and wraps.

### Proposed deterministic pipeline

1. Start acquisition only on explicit activation; request an available arbitrary
   vertical reference frame, not magnetic north. If the requested frame is absent,
   select a documented available relative frame and record it. Unsupported motion
   falls back to taps rather than silently changing sensor interpretation.
2. Collect a quiet calibration window, average compatible quaternions, and reject
   movement/unstable gravity. Show “Hold still”; never send while calibrating.
3. Transform to relative twist; smooth using sample-time-dependent filtering.
   Reject nonfinite values, duplicate/out-of-order times and excessive sample gaps.
4. Apply a neutral dead zone. Maintain a displacement residual and direction
   anchor. Each detent crossing emits at most one intent at the allowed rate;
   consume that crossing even if delivery is busy so it cannot emerge later.
5. On reversal, drop unsent old-direction work and reset the residual at the
   turning point. Require reversal hysteresis plus a fresh detent before the
   opposite step. No change just because the user stops twisting.
6. Bound off-axis swing and comfortable total twist. Exceeding a limit ends the
   activation and requests release/recenter; it never snaps neutral and emits a
   correction. Returning the wrist while still active intentionally reverses;
   release before returning if no reverse volume change is wanted.
7. Stop invalidates the processor generation, clears anchors/residuals and
   pending intents, and stops the sensor source. New activation starts fresh.

Initial configurable hypotheses, not measured product sensitivity:

| Parameter | Starting value | Validation purpose |
| --- | --- | --- |
| Requested sample frequency | 50 Hz | Measure actual cadence and energy; use timestamps. |
| Quiet calibration | 400 ms; timeout 2 s | Test stillness gate, proposed angular speed <8°/s and user acceleration <0.15 g. |
| Neutral dead zone / detent / reversal hysteresis | 5° / 12° / 3° | Reject jitter while permitting comfortable deliberate steps. |
| Filter time constant | 40 ms | Balance lag and sensor noise with variable sample intervals. |
| Command spacing | ≥250 ms (≤4 steps/s) | Enforced on Watch and iPhone; no catch-up burst. |
| Local intent age / relay permit lifetime | 250 ms / 500 ms | Drop stale work at both boundaries; no cross-device clock comparison. |
| Maximum sample gap | 150 ms | End activation rather than interpreting a late batch. |
| Total twist / off-axis swing limits | ±70° / 35° | Comfortable range and posture rejection; tune on actual wrist. |
| Maximum continuous hold | 10 s | Force a deliberate fresh activation; evaluate usability. |

Specify threshold inclusivity and residual/reset behavior in M3 test vectors.
Keep all values in one configuration type. Normal movements while idle must
produce zero commands regardless of those values.

## 7. Milestones and acceptance gates

Implement one coherent milestone per reviewable change. Read the latest ledger
first. Do not start motion-to-TV integration until M2 passes on hardware.

### M0 — Confirm dependency and lock the target matrix

Dependencies: none. Device and relay decisions needed for the M1 target matrix
are now recorded. Foreground-phone fallback and hold/clutch ergonomics do not
affect this target decision and remain gates before relying on those behaviors.

- Recorded from user: iPhone 15 / iOS 27; Apple Watch SE 3 / watchOS 27; paired
  iPhone relay accepted. Standalone Watch-to-TV operation is not required.
- Select iOS 17 and watchOS 10 minimums, below the reported device OS versions.
  Xcode device SDK builds and automatic iOS provisioning pass. Physical
  development installation remains unverified because the devices are not
  attached to this Mac.
- Keep clockwise/increasing and anticlockwise/decreasing as the user's direction
  requirement. The hold/release clutch remains a prototype proposal pending the
  later activation/usability gate. Whether foreground phone use is an acceptable
  fallback if locked/background relay fails also remains open.

Acceptance: the relay decision and target matrix are recorded. This resolves the
M1 dependency gate, not transport viability. Keep the foreground fallback and
activation ergonomics as separate later decisions; no new purchases.

Affected files: this plan and handoff only.

### M1 — Add isolated companion and Watch shells

Depends on M0. Add target/scoped settings and minimal setup/status UI, with motion
controls absent or disabled. Establish both WCSession delegates and lifecycle
state handling; support iOS session deactivation/reactivation when Watches switch.

Acceptance and result:

- XcodeGen produces an iPhone app embedding the correct Watch product. The
  embedded Watch Info.plist includes `WKApplication = true` and the matching
  companion iPhone bundle ID. iOS and Watch schemes build against Simulator and
  device SDKs. The signed iOS product and embedded Watch app pass nested
  code-signature and embedded-binary validation; both iOS and Watch icon asset
  catalogs compile into the signed products. Also inspect the embedded Watch
  development profile's `ProvisionedDevices` against the actual Watch UDID;
  signature verification alone does not establish device install eligibility.
  This device-authorization check currently fails. The standalone generic watchOS
  device build was a compile check, not a separately provisioned or installed
  Watch app.
- Live status distinguishes an activated bridge from TV readiness. Unsupported
  and unpaired counterpart states are clear. iPhone Simulator install/launch
  passed. The iPhone 15 host app is physically installed/launched. Watch app
  availability and physical Watch launch remain pending; no watchOS Simulator
  runtime is installed.
- Mac still generates/builds, retains identifiers/entitlements, and its existing
  unit suite passes. No AppKit membership in mobile targets; no transport stack
  in Watch. No generated project/plists/entitlements committed.

Result: targets build with signing for the iOS device SDK and compile checks for
iOS Simulator, watchOS device SDK and watchOS Simulator SDK. Automatic signing
provisioned the iOS app, and `codesign --verify --deep --strict` passed for the
iPhone app and embedded Watch app. The iPhone 16e / iOS 18.6 simulator installed
and launched the companion shell. This is simulator/build evidence, not physical
WatchConnectivity or TV evidence.

Affected files: `project.yml`, `Sources/iOS/*`, `Sources/Watch/*`, this plan,
handoff and README. No gesture implementation.

### M2 — Prove secure transport and tappable Watch volume

Depends on M1. Audit/share transport with iPhone; implement foreground host entry,
permission flow, pair/forget, new iPhone Keychain credentials, status and volume
bridge. Add opt-in command validity through the final socket-write boundary.
Implement bounded taps and the activation/session protocol without motion input.

Acceptance in host/integration tests:

- Warm-up/taps coalesce one handshake; pairing socket is adopted; commands are
  ordered on the same channel. Old Mac batch behavior and 17 existing tests pass.
- Expiry during a suspended connect/admission, cancellation during a queued send,
  receive-loop disconnect, changed host, duplicate/old message and lost reply
  cause no stale/repeated send. Pin mismatch cannot authorize a connection.
- Pairing credentials survive relaunch in the iPhone's private Keychain; secrets
  and token-bearing URLs do not appear in logs, fixtures or Watch messages.

**Mandatory physical transport gate:**

- Pair on the actual TV; observe its approval and actual volume behavior. Send
  10 separated + and 10 separated − taps from Watch at the proposed rate, with
  no duplicate or delayed burst. Record failures and timings, not just totals.
- Confirm a continuous two-minute foreground Watch session with the phone app
  foreground, then background/locked. Include phone relaunch, first unlock after
  reboot, TV off/on, network loss and return, and Watch/iPhone reachability loss.
  Do not force-quit the phone and assume the OS will relaunch it reliably.
- Record send completion separately from observed TV response. Proposed warm
  input-to-socket p95 target: ≤500 ms, measured using Watch elapsed request/reply
  timing and relay duration (no subtraction of device clocks). Record TV reaction
  via observation/video where practical; it is a separate measurement.
- Check Mac and phone pairings coexist and both remotes still work. Verify pin
  rejection with controlled fixtures/integration setup; do not replace the real
  TV certificate to run a test.
- Release/cancel/offline work expires; reconnect accepts only fresh taps. Turn
  off phone radios in Settings for an unavailable-phone check; no standalone
  operation is expected from this relay design.

Pass only for the documented phone operating conditions. If locked/background
relay fails, document the cause and ask whether foreground phone use is an
acceptable product limitation before continuing. A mock or Simulator pass does
not satisfy M2, and a failed latency gate is not fixed with a bigger backlog.

Affected files: shared client/connection/store, bridge protocol/adapters, delivery
coordinator, setup and volume UI, delivery tests and ledger. No motion sends.

### M3 — Implement the pure gesture processor

Depends on M2's accepted transport envelope. Develop numeric types, configuration
and processor independently of Core Motion and networking. All emitted intents
go to a test sink.

Acceptance: deterministic tests cover neutral jitter, calibration movement and
timeout, intended directions, wrist/crown mappings, quaternion sign flips,
±π wraparound, different forearm postures, reversals/hysteresis, stationary hold,
clutch/recenter, range limits, variable timestamps, out-of-order/invalid samples,
rate cap and dropped overspeed displacement. Deactivation, disconnect, old
generations and stale samples emit no subsequent intent; reactivation starts at
zero. Golden traces specify exact intent sequence/times at threshold boundaries.

Affected files: `Sources/Gesture/*`, gesture tests and ledger. No physical
sensitivity claims; synthetic posture coverage verifies math, not comfort.

### M4 — Integrate foreground motion with explicit activation

Depends on M2 hardware gate and M3. Implement Core Motion source, wrist/crown
metadata mapping, calibration UI, touch release/cancellation, and delivery.
Start with a diagnostic dry mode showing direction without TV commands, then
enable actual sends only after direction is confirmed on device.

Acceptance:

- UI clearly shows disconnected, ready, calibrating, active and recenter states.
  Touch down begins calibration; release/drag exit/interruption ends activation.
  Controls remain usable and labelled with VoiceOver; motion is optional input.
- Sampling occurs only during calibration/active hold. All inactive paths stop
  updates, clear pending work and reject late callbacks. Wake/reconnect does not
  auto-arm. No haptic claims actual execution or displays fabricated volume %.
- Fault-injection tests pause bridge/send callbacks, release or disconnect, then
  resume them: old work never enters a new activation. Check the finite in-flight
  exception in section 4 explicitly rather than asserting impossible recall.
- Both apps compile and shared regression tests pass. A device diagnostic proves
  actual sensor data and the configured axis/direction before the first TV step.

Affected files: Watch motion/activation/model/UI, delivery integration, tests and
ledger. Sensitivity and hold ergonomics remain pending M5.

### M5 — Tune on the user's Watch and document release behavior

Depends on M4. Perform the hardware matrix in section 9, tune configuration only
from recorded observations, and save sanitized traces useful for regressions.

Acceptance:

- On the actual wearer's setup, 10 deliberate clockwise and 10 anticlockwise
  trials produce the intended direction; record recognition failures and step
  counts. No opposite-direction result is acceptable without correcting mapping.
- Two minutes of typical idle arm movement produce zero commands. During an
  activated stationary hold, ten five-second trials produce zero steps after
  calibration. Record the posture/thresholds used.
- Release/recenter/rearm works repeatedly without corrective volume changes.
  Ten stop/disconnect trials show no unsent local work after stop and no new
  relay write after cancellation processing or permit expiry. Record any single
  already-started send and observed TV settling time separately.
- Physical test confirms wrist lowering, Always On, cover-screen/Crown exit,
  interruptions and touch cancellation disarm. Taps remain a usable fallback.
- Repeat M2 latency/session checks with motion at the final rate. Record battery,
  temperature and comfort observations over a representative 10-minute session;
  this is a screening test, not an all-day battery claim.
- Final Mac suite/build passes; manually spot-check Mac volume, pairing and
  sleep/wake if transport code changed. Preserve the historical keypad caveat.
- README explains installation, phone dependency, setup, direction, activation,
  clutch, reconnect and real limitations. Ledger separates passed automated,
  simulator and physical checks and lists unsupported/untried configurations.

Affected files: configuration, regression fixtures/tests, README, handoff and
ledger. Additional Watch controls are a later scope decision.

## 8. Verification commands and evidence

For implementation milestones touching project/shared code, run the existing
commands and report actual results:

```sh
xcodegen generate
xcodebuild -project SamsungTVRemote.xcodeproj -scheme SamsungTVRemote \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath build/DerivedData build test
```

After adding targets, list generated schemes/destinations, then build the new
iPhone and Watch schemes against installed simulator destinations. Use actual
destination IDs from `xcodebuild -showdestinations`; do not hardcode an invented
Watch/iPhone model. Build device SDK products as well; an unsigned compile check
does not establish provisioning or installation. Run the pure gesture/bridge
host test scheme and appropriate mobile integration checks from M2 onward.

Inject clocks, readiness, transport and sample streams in meaningful tests. Test
cancellation at await boundaries and immediately before writes, not just that a
queue's count becomes zero. Keep existing keypad/batch tests as regressions.
Use structured, secret-free event timings with request/session IDs for diagnosis.
Record phone/Watch OS, orientation, network conditions and configuration for
physical runs. Never label a UI preview, mock or simulator as hardware evidence.

The original planning-only checks above were followed by the M1 implementation
and verification recorded in the ledger. No TV pairing/volume transport,
physical Watch install, or wrist-motion behavior has been tested.

## 9. Physical assumptions and test matrix

| Unresolved assumption | Required physical observation | Effect if false |
| --- | --- | --- |
| User owns a supported paired iPhone and accepts relay dependency | M0 recorded: iPhone 15/iOS 27, Watch SE 3/watchOS 27, relay accepted | Decision complete; physical compatibility/install still needs device validation. |
| Phone can reach TV and pair independently of Mac | Foreground permission/pair test, same LAN/VLAN, both clients still work | Resolve phone network/TV authorization; do not copy Mac credentials. |
| Live relay works with phone locked/background | M2 two-minute sequence plus reconnect/reboot/first-unlock cases | State precise limitation; ask whether foreground phone use is acceptable if this fails, and assess credential accessibility. |
| Warm relay meets freshness/rate envelope | Request/reply distributions at 1–4 steps/s and induced delays | Revisit architecture or interaction; never accumulate stale steps. |
| Wrist twist axis/sign matches intent | Dry preview for actual wrist, crown orientation and comfortable posture; opposite wrist only if available | Correct mapping/inversion; mark untested configurations rather than claiming support. |
| Hold-to-activate is usable while twisting | Grip, touch retention, screen visibility and VoiceOver trials | Propose another explicit activation/clutch design with the user; retain stop/time limits. |
| Neutral calibration is stable and fast | Repeated seated/standing calibrations, forearm forward/up/down | Tune stability gates, supported posture/tutorial; no automatic axis guessing during sends. |
| Noise/reversal filters feel natural | Slow/fast twists, small tremor, off-axis movement, limit and return trials | Adjust configurable thresholds and add failing traces as regressions. |
| Screen state permits intended foreground gesture | Wrist lower, Always On on/off, cover, Crown exit, interruptions | Disarm as designed; document foreground limitations, no runtime workaround. |
| Stopping cannot leave a delayed burst | Release during send, lost end message, phone suspension and reconnect | Fix final-write validation/permits; no M5 signoff with stale replay. |
| TV responds to volume for the current source/audio path | Observe actual TV volume response, including mute/external output if used | Document TV/audio-route limitation separately from successful socket sends. |
| Hardware/energy remains comfortable | Representative session with actual Watch model and measured cadence | Reduce acquisition/haptics or session limits; do not claim background support. |

Do not ask for a TV model again unless pairing/volume evidence makes it material.
Current handoff identifies a Samsung Wondertainment and Tata Play HD source;
README's model reference alone is not verified hardware identity.

## 10. Progress ledger and handoff contract

| Item | Status as of 2026-10-17 | Evidence / next dependency |
| --- | --- | --- |
| Repository/platform research | Complete | Source/settings, SDK headers and Apple sources checked; target/embed behavior validated with XcodeGen probes. |
| M0 decision/target matrix | Complete for M1 | iPhone 15/iOS 27, Watch SE 3/watchOS 27 and relay acceptance recorded. Foreground fallback and hold/clutch remain later product gates. |
| M1 shells | Implemented; iPhone discovery and legacy wired Watch trust verified; installation pending | Actual Watch model/version and authenticated lockdown session verified via wired iPhone companion proxy. Xcode/CoreDevice still lacks a physical Watch destination. App profile still authorizes only Mac; Watch app install/launch acceptance remains open. |
| M2 taps/transport | Not started | M1 physical install/launch follow-up; actual Watch/iPhone/TV required for transport gate. |
| M3 processor | Not started | Accepted M2 transport envelope. |
| M4 integration | Not started | M2 physical pass and M3 tests. |
| M5 hardware tuning | Not started | M4 and user wearing Watch. |

At each milestone update this ledger with date, changed files, commands and
results, device evidence, chosen defaults, failures, remaining hardware questions
and the next gate. Revise architecture here when evidence invalidates it; put a
short pointer and key findings in the handoff. Keep historical verification
separate from newly run checks. Planning completeness cannot establish motion
sensitivity or make an untested transport ready.

### M1 verification record (2026-10-17)

- `xcodegen generate` and `xcodebuild -list -project SamsungTVRemote.xcodeproj`
  passed; the generated project contains the original Mac target plus separate
  iOS and watchOS application targets and schemes.
- Existing macOS build/test command passed: **17 tests, 0 failures**.
- iOS Simulator (iPhone 16e / iOS 18.6), generic iOS device SDK, generic
  watchOS Simulator SDK and generic watchOS device SDK builds passed. The
  watchOS SDK builds were compile checks; no watchOS Simulator runtime exists.
- `xcodebuild -allowProvisioningUpdates` signed the generic iOS device product
  and embedded Watch app. `codesign --verify --deep --strict` passed for both;
  generated companion metadata and bundle IDs were inspected.
- `xcrun simctl install` and `launch` passed for the iPhone 16e Simulator. The
  rendered shell showed WatchConnectivity state separately from TV readiness,
  and a clear no-Watch-paired state. No TV credentials or socket stack are in
  the mobile shell.
- Initial device enumeration found no physical iPhone or Watch attached. This
  left the M1 owned-device install/launch acceptance item open at that time.
  Install the watchOS 27
  runtime in Xcode if Simulator launch coverage is desired; it does not replace
  installing on the user's Watch SE 3.
- Earlier probe history: default `Watch/` embedding initially failed validation
  while the Watch plist lacked `WKApplication`. A `PlugIns/` workaround passed
  validation but was not discovered on the user's iPhone. The fresh-build
  follow-up below invalidates the claim that `PlugIns/` is required.
- The M0 gate is split: relay/device matrix is settled for M1, while foreground
  phone fallback and hold/clutch ergonomics remain later gates.

Next: the user declined the CoreDevice logging profile; do not request its
installation again. They are updating macOS themselves from approximately
26.6.2 to 27. This is planned, not completed, and is not a verified fix. After
restart, check actual macOS/Xcode versions, USB phone connection, and physical
Watch discovery before making further changes. Preserve existing legacy Watch
trust and app targets. If Watch becomes available, register/provision it, verify
its real identifier in the embedded profile, then install/launch M1 shells.

### Physical device follow-up (2026-10-17)

- The iPhone 15 later connected to this Mac and reports Developer Mode enabled.
  `xcrun devicectl list devices` sees it, but does not list the Apple Watch SE 3.
- A device-specific `xcodebuild` with automatic provisioning and device
  registration succeeded. Code-signature verification passed and `devicectl`
  installed the phone app. The earlier claim that this also provisioned the
  embedded Watch app for the owned devices was incorrect: the later profile
  audit below found only the Mac authorized in the Watch profile.
- The first `devicectl device process launch` was denied with the generic iOS
  security/trust error. After the user approved the launch on device, retrying
  `devicectl device process launch` succeeded. The iPhone app now runs on the
  iPhone 15; the initial denial did not require a signing-code change.
- `xcodebuild -showdestinations` for the Watch scheme still lists only generic
  watchOS destinations, not the physical SE 3; `devicectl list devices` likewise
  sees the iPhone but not the Watch. Watch installation/launch remains unverified.
- The user's Device Hub Watch-pair attempt did not complete. Direct Watch pairing
  remains unresolved for direct Xcode deployment. Apple documents installing an
  available companion from the paired iPhone's Watch app [A11]. Do not reset or
  unpair the Watch as a troubleshooting step.
- After the `WKApplication` metadata fix, the user shared the iPhone shell status:
  Watch bridge `Active`, Watch app `Watch app not installed`, and TV `Not paired`.
  This confirms the phone shell is running and reports no installed Watch
  companion; TV pairing is a separate M2 task. The user also reported that the
  companion is absent from the Watch app's Available Apps list.
- A fresh package audit found the Watch `AppIcon.appiconset` declared
  `platform: "watchOS"`. Xcode 27.1's asset compiler warned `Unknown platform
  value "watchOS"` and `The app icon set "AppIcon" has an unassigned child`, and
  emitted no Watch `Assets.car`. Changed the platform value to lowercase
  `watchos`. The next build emitted a Watch `Assets.car` (~504 KB) with no such
  warnings; the iOS catalog also compiles. This establishes a second packaging
  defect, but there is not yet evidence that it caused the Watch app discovery
  failure.
- Rebuilt with the connected iPhone 15 destination; the Watch plist contains
  `WKApplication = true` and the matching companion identifier, Xcode's
  `ValidateEmbeddedBinary` passed, and nested `codesign --verify --deep --strict`
  passed. `devicectl` installed and launched the updated iPhone host app. The
  user then confirmed the companion still did not appear. The icon correction
  did not resolve discovery.
- Revisited the earlier embedding decision with complete Watch metadata. Removed
  the custom `copy.destination: plugins` dependency override in `project.yml`.
  Generated and built from a fresh derived-data directory,
  `build/DerivedData-M1-WatchEmbedding`, against the connected iPhone 15.
  `ValidateEmbeddedBinary` accepted the product in
  `Samsung TV Remote.app/Watch/Samsung TV Remote Watch.app`; `BUILD SUCCEEDED`.
  Inspected the generated copy phase (`dstSubfolderSpec = 16`,
  `$(CONTENTS_FOLDER_PATH)/Watch`), verified `WKApplication`, companion ID and
  Watch `Assets.car`, confirmed no `PlugIns/` payload in this fresh product, and
  passed nested `codesign --verify --deep --strict`. `devicectl` installed and
  launched this build on the iPhone 15.
- Plan correction: the initial validation error did not establish that Xcode
  requires `PlugIns/`; it occurred before `WKApplication` was added. Current
  evidence supports the default `Watch/` package. Physical discovery must still
  be checked against this latest install; do not claim this fixes it until the
  user observes the app. M2 remains unstarted. Do not repeat Device Hub pairing
  steps, reset/unpair the Watch, or change the relay architecture without new
  evidence.

### Watch discovery passes; installation provisioning follow-up (2026-10-17)

- User confirms Samsung TV Remote now appears in Available Apps. Tapping Install
  fills the circle and returns to Install. This is physical discovery evidence
  for the restored `Watch/` package, not a successful Watch installation.
- Decoded `embedded.mobileprovision` from the actual embedded Watch bundle in
  `build/DerivedData-M1-WatchEmbedding/Build/Products/Debug-iphoneos/` using
  `security cms -D`. Its sole `ProvisionedDevices` entry matches this Mac's
  hardware identifier according to `xcdevice list`. Neither the physical Watch
  nor iPhone is authorized there. The host profile separately includes iPhone.
  No provisioning credentials or full device identifiers are saved here.
- `xcdevice list`, `xctrace list devices`, `devicectl list devices`, and the Watch
  scheme's `-showdestinations` still expose no physical Watch. The watchOS DDI is
  installed and reported usable; installing a Simulator runtime does not resolve
  device registration. `devicectl device pairings list` returned an internal
  argument validation error and provided no Watch identifier.
- Corrected acceptance: embedded validation and nested signature checks verify
  bundle/signature structure; they did not prove authorization for this Watch.
  Apple documents missing device IDs in profiles as an installation failure
  [A14]. The profile mismatch is a confirmed blocker consistent with the symptom;
  the Watch's actual installer error has not been captured.
- Next dependency: inspect the current Device Hub Watch status/error from the
  previously stalled pairing. Resolve discovery, provision the actual Watch,
  rebuild, inspect the embedded profile against its identifier, then retry.
  No further package-layout or motion changes are justified by this evidence.

### Device Hub pairing stall evidence (2026-10-17)

- User supplied a Device Hub screenshot showing `Waiting to pair`, with only
  iPhone available, and reports confirming pairing on Watch returns no result.
  This narrows the dependency to the developer-pairing handshake before Xcode
  has a registered Watch destination. No app code change follows from it.
- A first-person Apple Developer Forums report describes the same Xcode 27 /
  watchOS 27 symptom: the Mac is visible in Watch Developer Mode, but approving
  pairing produces no PIN in Device Hub. The reporter resolved it by completely
  powering off iPhone, pairing the powered-on Watch directly with the Mac, then
  powering iPhone back on: https://developer.apple.com/forums/thread/837517.
  This is an anecdotal workaround from a beta configuration, not an Apple
  guarantee or a confirmed diagnosis for this user's devices.
- Next controlled trial: power off iPhone temporarily; keep Mac and Watch on
  the same Wi-Fi, Watch unlocked and Developer Mode enabled; reopen nearby
  pairing in Device Hub and approve from Watch. If a code appears, complete
  pairing, restore iPhone power, then inspect Xcode's Watch destination and
  provision/rebuild. This has not yet been tried by the user. Do not erase or
  unpair Watch from iPhone, or assume the forum's proposed stale-state cause.

### Phone-off pairing trial failed (2026-10-17)

- User tried the phone-off trial and reports the Mac no longer appears in
  Watch's developer device list despite the same Wi-Fi. The forum workaround
  did not help this setup; do not repeat it as a fix. Restore iPhone power.
- Read-only Mac checks show `remotepairingd` started its manual-pairing Bonjour
  listener, reached `ready`, and started advertising on Wi-Fi. Wi-Fi IPv6 is
  Automatic and `en0` has a link-local IPv6 address; the Mac application firewall
  is disabled. `scutil --nwi` listing no routable IPv6 state alone does not prove
  IPv6 is disabled. No network settings or firewall rules were changed.
- These observations do not establish Watch-side discovery or a successful
  handshake. First check whether the Mac reappears when iPhone is powered back
  on; preserve the existing phone/Watch pairing and avoid broad reset steps.

### Further pairing investigation and service restart (2026-10-17)

- Apple lists macOS 26.6+ as supported for Xcode 27.1; this Mac's 26.6.2 version
  does not itself require an OS upgrade. No published fix was established in
  the checked Xcode 27.1 release notes. An Apple Developer Forums first-person
  report reproduces the same Watch confirmation/no-code loop on macOS 26.6.2
  (https://developer.apple.com/forums/thread/845536); this is corroboration,
  not proof of the cause or a fix for this system.
- Bonjour queries confirmed the Mac's pairable-host advertisement on Wi-Fi.
  Discovered remote-pairing device advertisements resolved to the iPhone; they
  did not yield a Watch identifier or justify pairing another unknown endpoint.
- The embedded Watch profile has `LocalProvision = true` and a seven-day term,
  confirming free Personal Team provisioning. The only cached Watch app profile
  authorizes the Mac. No alternate valid Watch profile was found. Simulator
  signing does not supply real Watch device authorization; no paid membership
  or TestFlight dependency is introduced.
- Mac logs contain repeated wireless pairing-session peer errors with private
  error details. These logs do not identify the precise Watch-side cause.
  Gracefully terminated only the current user's DeviceHub and remotepairingd
  processes and reopened DeviceHub. The iPhone became available/paired again.
  No Xcode editor, saved trust credentials, network settings, profiles, phone
  pairing, or Watch data were reset.
- A fresh Watch-side approval is needed after this service restart. Asked the
  user whether a pairing code appears, Mac appears with no code, or Mac remains
  absent. The subsequent 40-second capture recorded no matching pairing events,
  and the final device list still showed only iPhone and Simulator. No user
  result for the fresh attempt has arrived; no successful handshake is claimed.

### Verified pairing-process restart correction (2026-10-17)

- User retried Watch selection, passcode and confirmation; still no result.
  The log again shows listener ready, then a private peer error and no registered
  Watch. The exact underlying error remains unavailable in normal logs.
- Verified process IDs/start times after the earlier SIGTERM request. Both
  DeviceHub and remotepairingd retained their original process IDs: the earlier
  claimed graceful restart had not actually occurred. That retry was not valid
  evidence about a freshly restarted service. Corrected this with the user.
- Fully stopped those two current-user processes with SIGKILL. remotepairingd
  relaunched with a new PID. The first immediate DeviceHub reopen raced process
  exit (Launch Services -600); the subsequent open succeeded. iPhone recovered
  to available/paired without clearing trust or phone/Watch pairing. Verified
  both replacement processes have new PIDs; one fresh pairing attempt is now
  required.

### Verified restart failed; wired companion check is next (2026-10-17)

- User confirms the same Watch confirmation/no-code result after both processes
  actually restarted. That controlled restart did not resolve the issue.
- `ioreg -p IOUSB` shows no attached iPhone/iPad/Apple mobile device, while
  CoreDevice lists iPhone connected over its network path. No wired companion
  path is currently established. Next, use an existing data-capable USB-C cable,
  unlock/trust iPhone, and enumerate devices/Watch destinations again; Apple's
  device setup documents connecting the paired phone for dependent Watch apps:
  https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html.
- An alternate-network trial using iPhone Personal Hotspot is supported as a
  network setup (Apple Watch can join a hotspot), but is not a proven fix. Do not
  ask the user to change both USB and Wi-Fi at once. Trial wired companion first;
  no new hardware purchase, OS upgrade or broad reset is proposed.

### Wired companion route reaches the real Watch (2026-10-17)

- After user connected a data cable, `ioreg` showed an active iPhone USB device,
  `xcdevice` reported interface `usb`, and CoreDevice details reported transport
  `wired`, paired and connected. Watch scheme destinations still had no physical
  Watch, so a cable alone did not establish Xcode Watch discovery.
- Used pymobiledevice3 in an isolated `uvx` environment (no repository dependency
  changes) to read `com.apple.companion_proxy` from the already-trusted iPhone.
  Its paired-device registry returned exactly one Watch identifier. Queried only
  model/version metadata: `Watch7,14`, watchOS `27.0`, build `24R364`, and the
  user's Watch name. Full identifiers and developer trust records remain outside
  repository documents; do not commit them or print private pairing keys.
- Started a temporary companion forward to Watch lockdownd port 62078 through
  iPhone USB. A no-autopair connection read the same live Watch model/version.
  Verified its UniqueDeviceID matches the phone companion registry before a
  standard trust attempt. Forwarding was stopped in `finally` in each trial.
- Standard trust pairing through this route returned `PasswordRequiredError`
  with `PasswordProtected` for the Watch. This is a concrete Watch-side error;
  no successful trust pairing, Watch installation or provisioning is claimed.
  Asked the user to unlock Watch and keep it on-wrist; retry after their answer.
  Temporary developer-record storage uses a dedicated user directory with
  restrictive umask. No TV credential handling changes.
- Primary implementation inspected:
  https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/companion.py.
  This third-party diagnostic uses Apple's device services; it does not remove
  signing or device-authorization requirements. Whether legacy wired trust makes
  the Watch usable by modern Xcode is still unproven.

### Unlocked Watch still rejects wired trust (2026-10-17)

- User explicitly confirmed Watch is unlocked. Retried a bounded standard
  lockdownd trust request over the verified iPhone USB companion proxy. Same
  `PasswordRequiredError` / `PasswordProtected` response. Do not attribute this
  solely to a locked screen or ask the user to keep repeating the unlock step.
- A separate read-only call retrieved Watch's public key successfully (no key
  bytes printed). The legacy trust/pair request is rejected even though
  model/version metadata and that read work. That access does not authorize
  app installation or establish modern CoreDevice developer trust. Temporary
  forwards were closed; no successful Watch trust record or profile is claimed.
- Tried Xcode's supported build flow with the now-known Watch UDID explicitly
  selected as watchOS destination and automatic provisioning/registration
  allowed. It failed before building: `Unable to find a device matching the
  provided destination specifier`. A known identifier alone does not make the
  Watch a usable Xcode destination. No new app was installed from this attempt.
- Next controlled test: move Mac and Watch to iPhone Personal Hotspot, keep
  iPhone powered on, then try modern Device Hub pairing once. This changes the
  local network path without resetting devices; it is unverified. Apple's
  supported hotspot instructions explicitly include Apple Watch:
  https://support.apple.com/en-gb/109321. A developer-reported hotspot workaround
  exists in https://developer.apple.com/forums/thread/813066, but does not
  establish the cause of this user's issue or guarantee success.

### User-requested retry establishes legacy Watch trust (2026-10-17)

- On `try again`, the wired endpoint still identified as Watch7,14 / watchOS 27.0.
  This time the trust request saved a developer trust record. A redundant second
  `validate_pairing()` call returned `SessionActive`, which the diagnostic script
  initially printed as an error. Inspected library source: validation starts a
  new session, so repeating it on the same active session was the script error.
- Corrected verification by opening a separate fresh proxy connection with
  autopair disabled. It reported `paired = true`, an authenticated session, and
  UniqueDeviceID matching the phone registry Watch. This is physical legacy
  trust evidence, not an install or modern CoreDevice pairing claim. Saved
  developer record has mode 0600 in the dedicated user diagnostic directory;
  no certificates/private keys or full device identifiers are committed.
- Re-enumerated CoreDevice, xcdevice and Watch destinations after trust; none
  lists physical Watch. A read-only native MobileDevice probe found the attached
  iPhone but returned no paired-Watch object, matching Xcode's missing destination.
- Queried Watch's `EnableWifiConnections`: false. Tried enabling the standard
  developer wireless-connections preference through the authenticated session;
  Watch returned `SetProhibited`. No wireless setting was changed or restriction
  bypassed. All temporary companion forwards were closed after each attempt.
- Current Mac Wi-Fi address/router remain the original LAN values, not the
  standard iPhone Personal Hotspot subnet. Next remains the separate-network
  test previously proposed. No new Watch provisioning profile or application
  was installed; no TV or motion verification occurred.

### Personal Hotspot connection established (2026-10-17)

- User reported both devices ready on Personal Hotspot. Mac network settings
  now show iPhone's hotspot subnet/router, confirming the Mac network changed.
  iPhone remains visible by USB; passive CoreDevice, xcdevice and Watch scheme
  destination checks still list no physical Watch.
- Asked for one modern Nearby Device pairing attempt on this alternate network
  and captured pairing events for 45 seconds. No matching events were recorded;
  final CoreDevice enumeration still showed only iPhone and Simulator. No user
  handshake result has arrived yet, so the active pairing result remains pending.

### Hotspot retry unresolved; detailed CoreDevice logging needed (2026-10-17)

- On the user's next `try again`, Mac remained on the verified iPhone hotspot.
  CoreDevice, xcdevice and Watch destinations still showed no physical Watch.
  Recent pairing logs show listener ready/cancelled and a peer error redacted as
  `<private>`; they do not establish the underlying error code or cause.
- Queried `DeveloperModeStatus` through authenticated device services: both
  iPhone and physical Watch returned true. Do not ask the user to enable it
  again. Legacy Watch trust remains verified; all temporary forwards closed.
- Checked Xcode's `xcsigningtool` and documented xcodebuild options; no supported
  separate free-team device-registration CLI was established. Did not invoke
  undocumented account-registration methods or modify developer account assets.
- Inspected the CMS-signed local profile supplied with CoreDevice at
  `/Library/Developer/PrivateFrameworks/CoreDevice.framework/Resources/CoreDeviceHostLogging.mobileconfig`.
  Its sole payload type is `com.apple.system.logging`; it enables debug logging
  and private data for DeviceKit, CoreDevice and remotepairing subsystems. It
  does not change networking, device trust or app provisioning. Logs can contain
  private connection data; keep captures local and remove this diagnostic profile
  after the investigation. Do not commit raw captures or pair records.
- Opened that profile for user review. macOS requires the user to approve its
  installation in System Settings; opening it does not establish installation.
  After approval, reproduce once and inspect the detailed pairing error.
  `devicectl diagnose --help` recommends this host profile; Apple DTS also asks
  for CoreDevice logging in https://developer.apple.com/forums/thread/811726.

### User declines diagnostic profile and plans macOS update (2026-10-17)

- User explicitly declined installing the CoreDevice Host Logging Profile. It
  was opened for review only; no installation was confirmed. Do not ask for it
  again or install it automatically. No diagnostic logs have been uploaded.
- User is choosing to update Mac from approximately macOS 26.6.2 to macOS 27.
  Do not initiate or manage the OS upgrade on their behalf. Completion and exact
  new build are pending; no evidence yet establishes that it fixes pairing.
- Resume after restart by checking actual OS/Xcode versions and native Watch
  discovery with the paired iPhone connected by USB and Watch unlocked. Keep
  the existing trust records, default `Watch/` embedding and M1 app targets.
  If the Watch appears, use automatic provisioning and inspect the embedded
  profile for its actual identifier before installing. M2 remains unstarted.

### Physical Watch integrity error resolved (2026-10-17)

- User reports Xcode pairing now succeeds and the Watch icon appears, but launch
  gives “integrity could not be verified.” Mac now reports macOS 27.0.1 and
  Xcode 27.1; native CoreDevice enumeration shows both physical devices connected.
- Built the Watch scheme for the actual Watch destination with
  `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` into
  `build/DerivedData-M1-PhysicalWatch`. Build passed. Decoded the actual output
  profile and confirmed the physical Watch identifier is authorized. Full device
  identifiers and profile contents remain outside documentation/Git.
- `codesign --verify --deep --strict` passed with access to the Mac trust store.
  Direct `devicectl` Watch install and process launch both succeeded. This proves
  physical installation/launch, but visible bridge state awaits user confirmation.
- Rebuilt and installed the iPhone companion from the same derived-data directory;
  decoded its embedded Watch profile and confirmed actual Watch authorization.
  Existing older derived-data packages may still contain unauthorized profiles;
  use this new build or a fresh device-specific build for subsequent installs.
- Development profile expires 2026-10-24 14:42:28 UTC. Rebuild/reinstall after
  expiry. No application code or target settings changed; no Mac regression
  suite rerun was needed for this signing/install operation. No TV or motion
  behavior was tested. M2 remains unstarted.

### M2 implementation and validation (2026-10-17)

- Shared the existing TV client with iPhone, keeping AppKit in the Mac target.
  Reused pairing, token/pin storage, authenticated socket adoption and channel
  reuse. iPhone Keychain inserts use `WhenUnlockedThisDeviceOnly`, as proposed;
  Mac namespace and access behavior are preserved. No credentials cross WCSession.
- Added iPhone host entry, explicit Pair/Cancel/Forget, saved-pairing status and
  independent live-TV readiness. Configuration operations are serialized against
  live preparation and volume sends. Pairing must be initiated in the foreground;
  backgrounding during pairing cancels it. The app delegate initializes WCSession
  on background launches as well as foreground launches.
- Added `Sources/Bridge/VolumeBridge.swift`: versioned Codable messages inside a
  live property-list payload, phone-issued session IDs, monotonic sequences,
  request IDs, bounded immutable permits, lease/cancellation gate, and reply
  timeout. Only prepare/heartbeat/end and single up/down taps are accepted.
  Motion activation IDs/begin/refresh semantics remain for the motion milestone;
  a foreground session is the activation scope for this tap-only implementation.
- Phone permit lifetime is 500 ms, foreground lease 2 s, heartbeat interval
  200 ms, Watch intent validity 250 ms measured from the request start on Watch,
  and rate cap 8 sends/s on each side. Heartbeat round trips additionally limit
  attainable tap rate. These are initial defaults requiring device measurement.
- The tap path has one in-flight write and **zero queued taps**, a stricter
  initial bound than the plan's optional replaceable pending intent. It bypasses
  keypad queues, requires an already-authenticated socket, and rechecks the live
  gate at the socket-write boundary. Reconnect never sends a previous tap.
  Duplicate/out-of-order requests, expired permits and old-session end messages
  cannot create new volume work. No automatic repeat or absolute TV volume UI.
- Receive-loop/keepalive failure revokes permits synchronously. Reachability loss,
  Watch exit/inactivity and configuration changes end the session. The phone
  closes its warm socket after lease expiration; mobile keepalive cannot reconnect
  an idle socket indefinitely. Mac keeps its existing maintenance policy.
- Watch presents large up/down buttons, explicit Connect, TV readiness and separate
  bridge status. Replies describe a socket send, expiration/cancellation, or an
  unknown outcome; no reply claims the TV executed a command. Failed taps are
  never retried. No motion acquisition, workout or extended-runtime code added.
- Verification: Mac build/tests passed **29/29** (17 existing, 12 new). New cases
  cover cold/suspended handshakes, concurrent input rejection, failed-write
  non-replay, receive-loss permit revocation, stale write admission, permit expiry,
  immutable deadlines, rate limits/reversal, old/duplicate messages, lease expiry,
  bounded permit storage and cancellation/new-session invalidation. These are
  deterministic/fake-transport checks, not physical TV evidence.
- Signed iPhone build including Watch passed using the installed iOS 27.1 and
  watchOS 27.0 SDKs. Actual iPhone/Watch identifiers are authorized in the output
  profiles; nested strict signature checks passed. Build directory:
  `build/DerivedData-M2`. Current iPhone profile expires 2026-10-23 19:33:53 UTC;
  Watch profile expires 2026-10-24 14:42:28 UTC. Refresh development builds as needed.
- Remaining M2 gate: approve separate iPhone pairing on the actual TV; test 10
  separated taps each direction, two minutes of foreground use, locked/background
  phone, offline/reconnect and Mac coexistence. Record reaction/latency and verify
  no stale bursts. `WhenUnlockedThisDeviceOnly` may prevent reconnect while locked;
  do not widen Keychain accessibility without the explicit decision described above.
  M2 is **not hardware-accepted** yet. No simulator runtime or test can establish it.

### M2 physical deployment checkpoint

- Final M2 iPhone app installed and launched successfully on the physical iPhone.
- First direct Watch update failed when its remote install connection closed
  (`IXRemoteErrorDomain` 6); an app query timed out establishing the device tunnel.
  A separate physical-Watch-destination build timed out waiting for the connection.
- User confirmed Watch was connected and awake. Retried the already-validated,
  actual-device-authorized embedded Watch package from the signed iPhone build;
  direct installation and process launch then succeeded. No reset/unpair or
  profile changes needed.
- TV pairing, actual volume changes, latency and background/locked relay remain
  pending physical acceptance. No commands have been sent to the TV in this session.

### M2 readiness/permit regression follow-up (2026-10-17)

- User confirms TV pairing on iPhone, then reports blinking Watch volume buttons,
  a persistent Connect button while ready, no observed TV change, and eventual
  return to the default connect text. TV volume hardware acceptance fails.
- Deterministic reproduction: a permit requested at t=0 is locally expired at
  t=250 ms; with a 100 ms reply, sleeping another 200 ms starts the next heartbeat
  at t=300 ms. The previous UI toggled button enablement during this normal gap.
- Added `WatchVolumeAdmission` to separate a live session from ephemeral command
  authorization. UI readiness no longer depends on each heartbeat's permit.
  Connect is replaced by Disconnect while connected. Heartbeats update permits
  without erasing send/error text. Lifecycle/reachability loss still ends the
  session, but now displays its reason instead of generic setup text.
- Fresh tap admission first uses an available permit. If none is current, it
  requests one once and checks the **original tap time** before sending. The
  250 ms local and 500 ms relay limits are unchanged; there is no retry/replay,
  increased backlog, or extended deadline. A slow request is dropped with elapsed
  milliseconds displayed. This is a permit acquisition for a new tap, never a
  resend of an old or ambiguous command.
- Host tests pass **33/33**: added latency-gap readiness, late-reply/expired-tap,
  cancellation/session replacement, and single-use/deadline regressions. Signed
  iPhone/embedded Watch rebuild passed. Hardware revalidation remains required;
  fixes to proven UI bugs do not establish that relay latency or TV response passes.
- Updated iPhone app installed and launched. First Watch deployment attempt lost
  the Xcode device connection immediately after connecting. Two retries timed out,
  including after user confirmed Watch awake/connected; latest failure is
  CoreDevice 4000 / RemotePairingError 1001 (tunnel negotiation). Native Watch
  state remains connecting. Fixed Watch build installation and physical volume
  validation remain pending. Preserve pairing; do not repeat unlock questions
  without new evidence. Xcode Run with SamsungTVRemoteWatch/actual Watch is the
  manual installation route once its native connection recovers.

### M2 volume works; latency investigation (2026-10-17)

- User reports volume “works perfectly” after the fix, then estimates a 0.6–0.8 s
  delay, apparently every tap (“everytap?”). Functional TV delivery is now
  user-confirmed. Exact latency and test conditions are not yet measured; this
  does not establish the warm input-to-socket p95 target or full M2 acceptance.
- Inspected the live path: authenticated socket is reused. There is no deliberate
  600–800 ms sleep in tap delivery. A missing/expired local permit can add one
  fresh-permit exchange; assigning the delay to that or to TV execution would be
  speculation without measurements.
- Added optional `relayMilliseconds` in replies, measured on the iPhone from
  step-handler entry through socket-send completion. Watch measures tap-to-reply
  duration and, when needed, permit-request round trip using its own uptime.
  The readout labels the last tap and explicitly excludes measured TV response.
  These metrics include scheduling/transit/acknowledgment costs and do not give
  synchronized one-way timing or confirmed TV execution. No credentials in metrics.
- Existing protocol peers can omit the optional timing field. Command deadlines,
  session leases, single in-flight write/no backlog and no replay stay unchanged.
  Next collect a few readings under known foreground/locked-phone conditions;
  optimize the measured bottleneck before motion. Full M2 acceptance remains open.
- Timing-build verification: signed iPhone/embedded Watch build passed; strict
  nested signatures passed; existing 33 tests passed. Both actual devices accepted
  installation and both apps launched successfully. No actual tap readings
  collected yet.

### M2 measured permit acquisition optimization (2026-10-17)

- User sample: tap-to-reply **414 ms**, iPhone handler/socket-send **9 ms**, fresh
  permit request **239 ms**. The residual **175 ms** includes command transit,
  handling and reply. Do not infer one-way transit, TV reaction or p95 from this.
- Found two causes of poor permit availability: Watch's cached permit deadline
  used the 250 ms *tap* lifetime instead of the relay's existing 500 ms *permit*
  lifetime, and refresh waited 200 ms **after** a reply. A 239 ms round trip left
  only 11 ms of local permit availability and a 439 ms request-start cadence.
- `VolumeBridgeTiming` distinguishes tap lifetime (250 ms), permit lifetime
  (500 ms) and minimum heartbeat start interval (200 ms). The Watch caches a
  permit until request start +500 ms. This is no later than actual phone expiry,
  since the phone issues it after the request starts. No cross-device clock
  comparison. The relay still enforces its immutable deadline before writing.
- Refresh now subtracts time already spent awaiting the previous reply from the
  200 ms interval; only one heartbeat is in flight, no burst/catch-up scheduling.
  Fast links remain limited to five periodic heartbeats/s. At a 239 ms round
  trip, another request starts immediately after its predecessor completes.
- A fresh tap can consume a prefetched permit with no extra exchange. Missing
  permits still use the existing one-time admission path with the **original**
  250 ms tap deadline. No queue, replay, retry, lease or relay lifetime increase.
  Older/duplicate heartbeat replies cannot replace a newer or consumed permit.
- Added deterministic regression cases for the measured 239 ms schedule, fast
  link rate bounds, conservative permit expiry, and reordered/duplicate replies.
  Updated previous admission cases to distinguish permit validity from tap age.
  New physical readings and the rest of the M2 hardware gates remain required.
- Verification: **37/37 tests passed**, signed iPhone/embedded Watch build passed,
  strict nested signature verification passed. Updated iPhone installed/launched.
  Watch installs failed twice (immediate disconnect, then device tunnel timeout).
  Optimized Watch installation and new physical readings are unconfirmed; use
  Xcode Run with SamsungTVRemoteWatch + actual Watch, as previously successful.
  Preserve pairing and avoid repeated unlock questions without new evidence.

### M3 deterministic processor completed (2026-10-17)

- Added framework-independent `Sources/Gesture/MotionSample.swift`,
  `GestureConfiguration.swift`, and `WristTwistProcessor.swift`. Watch and Mac
  test targets include them; the Mac application and iPhone transport do not.
- Hamilton quaternions (x,y,z,w), normalized/hemisphere-aligned, device-to-reference
  contract. Neutral-relative rotation is inverse(neutral) * current; swing/twist
  projection about a configurable case axis, unwrapped angles and sample-time
  exponential filtering avoid Euler-angle subtraction. Case X is a proposed
  forearm axis; case Y and inversion are available in the forthcoming preview.
  Wrist/crown mapping is a hypothesis, not anatomical or hardware validation.
- States: idle -> quiet calibration -> active; invalid/stale/gapped samples,
  calibration timeout, hold limit or swing/twist limits -> release/recenter.
  End/disconnect resets generation/anchors. Old-generation events cannot emit.
- Defaults follow section 6: 50 Hz request, 400 ms quiet calibration / 2 s timeout,
  5-degree dead zone, 12-degree detents, 3-degree reversal hysteresis, 40 ms filter,
  250 ms minimum intent spacing, 150 ms sample age/gap, 70-degree twist,
  35-degree swing and 10-second hold cap. All are unmeasured hypotheses.
  A detent crossing consumes displacement even if rate limited; no catch-up work.
- Mac build and tests passed **52/52**, including 15 new gesture tests for jitter,
  stationary poses, proposed wrist/crown/inversion and axis mappings, synthetic
  postures, quaternion signs, wraparound, reversals, drop-on-rate-limit, bounds,
  calibration movement/timeout/spread, invalid/out-of-order/stale samples,
  release/recenter, old generation and watchdogs. One initial synthetic test used
  an implausible 22-degree/20 ms jump and correctly hit jump rejection; corrected
  that fixture to a gradual intended twist. No sensitivity was tuned from mocks.
- Output goes only to tests. Proceed next with M4's sensor/hold **preview only**;
  actual TV motion delivery awaits the physical direction and activation gate.

### M4 diagnostic sensor/hold preview (2026-10-17)

- Added `Sources/Watch/WatchMotionSource.swift`, `WatchMotionPreview.swift`,
  `MotionActivationControl.swift`; integrated into Watch model/view. Acquisition
  runs at requested 50 Hz on OperationQueue.main without spawning a task per
  sample. Generation guards reject callbacks after stop; processor freshness
  checks discard late samples. Initial cached samples before activation are
  ignored without aborting calibration. No raw samples are persisted/transferred.
- Source checks device-motion/reference availability, prefers arbitrary vertical,
  falls back only to corrected arbitrary vertical, and stops the manager on
  release/error. Adapter conjugates Core Motion reference-to-device attitude to
  the processor's device-to-reference contract. This convention, case axis,
  proposed wrist/crown sign and anatomical alignment require physical preview;
  synthetic posture tests establish the math contract, not actual sensor mapping.
- Hold control starts on touch down, stops on release/drag-out/system cancellation,
  and cannot rearm within the same touch after a watchdog stop. Accessibility
  action offers explicit start/stop with the same ten-second cap. Runtime
  watchdog checks sample age, calibration timeout and hold limit every 50 ms.
  Inactive scene/connection loss explicitly stops the preview in the model;
  reconnect/wake does not arm motion automatically.
- UI shows calibration/active/recenter/stop reason, signed relative angle and
  last would-raise/would-lower intent. Haptics are calibration/preview feedback,
  never TV execution. Setup reads wrist/crown orientation and exposes inversion
  and case X/Y choice. Release is the clutch before returning to neutral.
- Dry preview has no command sender. Tappable remote remains available.
  Activation IDs and activation-specific bridge cancellation for **actual motion
  delivery are not implemented yet**; do not route preview intents through tap
  delivery unchanged. M4 is diagnostic-stage code complete, not fully accepted.
- Final Mac build/tests **54/54 passed**: 17 gesture tests plus all 37 prior tests.
  Added exact first-detent boundary and cached-preactivation-sample regressions;
  detent comparison has 1e-9 degree numerical tolerance. Signed iPhone/embedded
  Watch build, strict nested signatures, and actual-device authorization passed.
  Preview installed and launched on both physical devices. Sensor capture and
  direction tests remain user-operated physical checks.
  Device compile rejected watchOS-unavailable DisclosureGroup; replaced with
  a plain setup toggle. Build directory `build/DerivedData-MotionPreview`.
- Physical sample availability/cadence, hold ergonomics, axis/sign, posture and
  sensitivity are unverified. Need user clockwise -> + and anticlockwise -> −
  in the preview before the first motion TV step. No simulated result substitutes
  for this gate. Fresh locked-phone reconnect remains explicitly deferred by user.

### M4 physical preview sign correction (2026-10-17)

- User reports the preview works but clockwise decreases and anticlockwise
  increases. Initial sign mapping is physically reversed on their setup; retain
  the axis/math contract and use the existing explicit inversion correction.
- Watch preview now defaults inversion on for this prototype and persists an
  explicit choice per wrist/crown/axis; selected axis is also saved on Watch.
  This changes no processor math or TV transport. Direction changes stop sensing
  and require fresh hold/calibration. Other orientations remain unverified.
- User can correct the already-installed build via Motion setup -> Reverse
  direction immediately. Need clockwise -> + / anticlockwise -> − confirmation
  before actual motion commands. TV delivery/activation cancellation is still
  the next implementation stage. Existing 54-test result includes both signs;
  no extra tests or rerun for this preferences/default-only change. Signed mobile
  build and strict nested signature checks passed; both updates installed;
  both apps launched successfully.

### M4 actual app-active motion delivery (2026-10-17)

- User confirmed the corrected physical preview direction. They rejected the
  proposed screen-hold interaction and requested “app is on, twist to change.”
  App active/connected entry now begins calibration automatically and gestures
  then send TV volume. This explicit choice supersedes hold-specific proposals.
- Renamed Watch preview to `WatchMotionController`; it still separates acquisition
  and pure processing from callback-based delivery. `MotionControlView` replaces
  the held-touch control with visible on/off, calibration, direction and delivery
  states, Pause/Resume and Recalibrate. Existing sign/axis preferences preserved.
  Automatic foreground configuration sets maximumHold to infinity; default pure
  hold configuration retains its old limit for historical tests. No extended
  runtime, workout or background sensing. Inactive scenes stop sensing/commands.
- Disconnection ends the foreground session and activation. Pause/recalibrate,
  orientation-setting changes, sample/calibration faults and range/off-axis
  limits stop the activation synchronously. Range faults require Recalibrate;
  there is no silent corrective neutral snap. Normal twists while active count,
  a tradeoff explained to the user. Future tuning remains M5 hardware work.
- Added optional activationID/activationSequence to the version-1 wire and
  motionBegin/motionEnd/motionStep kinds. A foreground-session activation sequence
  watermark rejects end-before-begin and older activation messages. Each permit
  is bound to its activation; a motion permit cannot be used as a tap permit.
  End invalidates admitted work at the final write boundary. A newer heartbeat
  cannot extend an older command deadline. Scope storage and permits stay bounded.
- Watch caches one motion permit. No waiting for reconnection/new permits per
  gesture, no unsent queue, no catch-up/replay. Both gesture processor and phone
  enforce >=250 ms between motion steps; local sample age <=250 ms and immutable
  relay permit deadline 500 ms. Busy/stale/unpermitted gestures are dropped.
- Wire send runs on MainActor and checks local activation validity immediately
  before the synchronous WCSession send. Phone rechecks the lock-protected scope
  from its persistent actor immediately before socket send. At most one already
  started/in-transit write can survive local stop; receipt/permit deadlines bound
  that distributed cancellation race. No absolute volume/execution confirmation.
- Heartbeat waits for motionBegin acknowledgment before scoped refresh, avoiding
  refresh overtaking begin. Replies from a previous motion/tap scope cannot stop
  a newer activation. Rejected step admissions advance deduplication state so a
  delayed duplicate cannot later become executable after a rate limit clears.
- Verification: **72 tests pass**, including 18 new deterministic/fake-transport
  cases covering late begin/end/replies, final-boundary pause cancellation,
  recalibration/old-generation rejection, scoped permits, rate/dedup/non-replay,
  one in-flight exception/zero backlog, and >10-second stationary foreground
  operation. Added begin/end acknowledgment barriers, new-begin supersession of
  old ends, foreground reset, and cached tap-permit invalidation tests. Tap fallback
  waits for end acknowledgment; late heartbeats from a previous scope are ignored
  even if the current scope is again a tap session. Signed iPhone/embedded Watch
  final build, strict nested signatures and actual-device authorization pass.
  Final iPhone package installed successfully. Direct Watch install failed twice
  (remote connection closed/device disconnected); iPhone CLI launch timed out.
  Live Watch installation/launch remains unconfirmed. Use Xcode's
  SamsungTVRemoteWatch scheme and actual Watch destination, Cmd-R; no reset or
  re-pair requested. Build output: `build/DerivedData-MotionLive`. M5 hardware tuning and
  actual no-hold TV volume test remain pending.

## 11. Primary references

- [A1 — Apple TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos), checked 2026-10-17; current page revision lists 2026-07-16.
- [A2 — WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession), companion architecture, session activation and transfer choices.
- [A3 — sendMessage(_:replyHandler:errorHandler:)](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)), live messaging, wake behavior and failure semantics.
- [A4 — WCSession.isReachable](https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable), counterpart readiness requirements.
- [A5 — Apple TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), outgoing local TCP and iOS foreground permission setup.
- [A6 — Getting processed device-motion data](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data), relative frames, timestamps and stopping acquisition; [CMMotionManager](https://developer.apple.com/documentation/coremotion/cmmotionmanager).
- [A7 — Designing your app for the Always On state](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state), active versus visible app lifecycle.
- [A8 — kSecUseDataProtectionKeychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain) and [kSecAttrAccessible](https://developer.apple.com/documentation/security/ksecattraccessible), platform Keychain behavior and accessibility choices.
- [A9 — Setting up a watchOS project](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project), Watch-only versus companion project structure.
- [A10 — XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md), dependency embedding destinations and copy paths.
- [A11 — Download apps on your Apple Watch](https://support.apple.com/en-us/109023), installing an available companion app from the paired iPhone's Watch app.
- [A12 — WKApplication](https://developer.apple.com/documentation/bundleresources/information-property-list/wkapplication), the watchOS Info.plist marker for a single-target Watch app.
- [A13 — Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), Xcode's single-image app icon workflow for watchOS and iOS.

- [A14 — Apple TN2319: Installation Failure Troubleshooting](https://developer.apple.com/library/archive/technotes/tn2319/), development profile device authorization and embedded Watch bundle inspection.

Local evidence: `project.yml`; `Sources/iOS/*`; `Sources/Watch/*`; the seven
`Sources/Shared` files; both Mac app files; existing test sources; installed
`CMMotionManager.h`, `WKInterfaceDevice.h`, `WCSession.h` and `SecItem.h` in the
active Xcode SDKs. Apple's constraints inform the proposed relay; its end-to-end
viability is still an M2 hardware question.
