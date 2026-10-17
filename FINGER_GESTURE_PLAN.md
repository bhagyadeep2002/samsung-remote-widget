# Finger gesture prototype

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

## F3 live-volume milestone (authorized: user “do it”)

User confirmed Up and Down in the preview and explicitly requested real TV
volume while held, with release cancelling unsent work. Implement one step per
hold as a proposed bounded first version, using the same frozen classifier.
This is not a continuously repeating/streaming recognizer. Recognition requires
a complete sample window, so keep holding through the automatic result.

- States: idle -> held/preparing link -> held/settling -> held/GO -> one automatic
  decision -> held/waiting for release -> idle. Release/drag/system cancellation,
  inactivity, disconnect, sensor error or timeout -> immediate local cancellation
  and scoped remote end; never classify/send from a release callback.
- Start sensing only after the scoped phone begin is acknowledged. Show GO after
  the corrected 350 ms settling + 310 ms boundary interval. Proposed first live
  recognition window: 2.5 s after sensing starts, with the existing 100 ms release
  trim and 300 ms classifier boundaries. Keep the hold active until release;
  sensing stops after the single decision. Maximum held session: 10 s. Values
  remain hardware hypotheses; no latency claim from offline replay.
- Up/Down emit one fresh intent while still held. Still/Unsure emit none. A pure
  held-session state machine latches every outcome, so a busy link/missing permit
  drops the intent without retries or later recognition. Old generations and
  stale samples/timeouts are rejected. Tests use an injected decision to verify
  lifecycle independently of classification.
- Reuse existing motionBegin/motionEnd/motionStep, activation sequence, cached
  500 ms permits, 250 ms intent freshness, one in-flight send, phone final-write
  gate, TLS pinning and non-replay behavior. Update WatchRemoteModel to use the
  held finger activation as its source. Do not restart the retired wrist knob.
  One write already transmitted cannot be recalled; release prevents unsent work.
- UI: explicit Control TV / Test / Record modes; Control TV requires connection.
  Hold control says keep holding through result; test/record behavior remains.
  Show link/activation and send state without implying confirmed TV execution.
- Files: new `Sources/Gesture/HeldFingerVolumeSession.swift` and lifecycle tests;
  FingerCaptureController/FingerCaptureView for live mode; WatchRemoteModel for
  callbacks/delivery; README and handoff. No phone protocol/credential changes.
- Acceptance: pure hold lifecycle, one-step/Still/Unsure, cancellation before/after
  recognition, fresh samples, busy-link drops, delayed begin replies and final
  write revocation pass; existing 90-test suite passes; signed build passes.
  Actual new live Watch/TV behavior remains a hardware validation step.


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

Current F2 result: `samples/finger-gesture-export_v2.json` contains 17 valid trials
(6 Up / 6 Down / 5 Still), all ~99.6 Hz. Whole-trial held-out exploratory models
score 13–16/17. After removing the first/last 300 ms, the fixed three-neighbor
model scores 16/17, accepting 12/17 with unanimous neighbors (all 12 correct),
leaving five undecided. This is small single-wearer/class-block data, not a
separate-session validation. Some Down movement is near the start and one Still
trial has movement; timing/boundary effects remain possible. No TV integration
is justified by these offline results alone.

F3 preview specification used for this build: after release,
classify a completed trial as Up/Down/Still/Unsure. No volume callback. Keep the
labelled recorder for additional examples; test guesses must never be stored as
true labels. Use the fixed boundary-trimmed, peak-window feature pipeline and
unanimous 3-neighbor vote; the remaining cases display Unsure. Freeze the model
trained on all 17 recordings for fresh physical testing. Scope it to the trained
left-wrist/crown-right/raw-acceleration acquisition configuration. User-facing
instructions ask for varied Up/Down/Still tests, not more training on these same
files. Live while-held recognition and volume delivery remain later gates.

Affected files: `scripts/analyze_finger_recordings.py` and derived sample reports;
`Sources/Gesture/FingerGestureClassifier.swift` (pure preprocessing/vote),
`FingerGestureModel.swift` (frozen numeric templates and source hash);
`FingerCaptureController.swift` / `FingerCaptureView.swift` (test mode), plus
classifier tests and documentation. State: idle -> held settling -> sampling ->
release -> one displayed prediction -> idle. Cancellation discards data; preview
has no command queue or TV send path. Acceptance: Python/Swift feature parity,
recorded-trial replay parity, synthetic stop/invalid-input checks, unchanged
labelled-record export, and signed build. Fresh hardware accuracy is pending.

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

Latest user decision (2026-10-17): live wrist volume works but feels janky.
Replace the knob interaction with the finger motions demonstrated in
`samples/volume_up.MOV` and `samples/volume_down.MOV`. User confirmed these are
finger gestures with the wrist mostly still, and accepts a held screen control
for initial detection. This supersedes the automatic foreground wrist activation.
The previous wrist processor remains as historical/tested code, not an active
fallback. Tappable TV volume and the current authenticated relay remain available.

## F1 hardware correction: raw API availability

User's first capture attempt displays “Raw motion sensors unavailable.” The
combined guard proves at least one direct raw service returned unavailable; it
does not identify which one. Requiring both was a recorder bug: the previous
physical wrist implementation already established working device-motion data.

The recorder now requires device motion for rotationRate, with raw accelerometer
data when available; if raw acceleration is unavailable, it records
`gravity + userAcceleration` from the same device-motion samples. There is no
direct raw gyro requirement. Both services stop on release/cancellation. The
Watch displays the selected source and measured rates. This change does not
establish that processed signals retain enough detail for finger recognition.

New recordings use JSON version 2 with required `acquisition` metadata:
`rawAccelerometerWithDeviceMotionRotation` or `deviceMotion`. Device-motion
rotation is bias-corrected, not raw gyro. Legacy version 1 raw-pair files still
import/export correctly; source-less version 2 files are rejected. Phone and
Watch must both be updated for version 2 imports. Verification: 83/83 macOS
tests pass, including source selection with device motion, source metadata
round-trip/import/export, legacy compatibility, and source-less/mislabelled schema
rejection. Signed mobile build and strict nested signatures pass. Hardware
capture is pending.

## F1 verification checkpoint

Implemented the held-label recorder, bounded generation-scoped raw buffers,
validation/storage, explicit file transfer, iPhone counts/export, and confirmed
Watch-copy deletion with pending-transfer cancellation. No automatic wrist
activation remains in the foreground/connection path. No classifier or finger
volume sends are enabled; current TV taps keep their original delivery path.

Verification: 80/80 macOS tests passed (72 existing + 8 capture/storage tests),
including settling/release trimming, stale/future/out-of-order rejection,
old-generation callbacks after cancellation, short recordings, sample/file bounds,
invalid/missing streams, duplicate transfer import and export. Signed iPhone and
embedded Watch build passed; strict nested signature verification passed.
Both final apps were successfully installed and launched on the user's physical
iPhone and Watch through CoreDevice. Build: `build/DerivedData-FingerCapture`.
Actual touch behavior, sensor rate/quality, file transfer and exported data remain
unverified until the user performs the five Up/five Down/five Still trial sequence.
F2 is waiting for those physical recordings, not a speculative classifier.

## Evidence and limits

Both videos were inspected as timed frame sequences (up 4.93 s, down 3.70 s).
They demonstrate opposite finger/thumb movements, not a substantial wrist turn.
Video gives no synchronized accelerometer/gyro training data. Core Motion exposes
wrist acceleration and rotation, not arbitrary finger positions. Apple's public
`handGestureShortcut` API exposes the primary action; the installed watchOS 27
SwiftUI interface provides no arbitrary up/down finger-gesture registration.
Do not invent a rule that maps incidental wrist vibration to the demonstrated
finger labels or claim these gestures are already recognized.

## Milestones

### F1: Held, labeled sensor capture (current implementation)

- UI: choose Up, Down or Still, hold a large recording control, wait through a
  short settling interval, perform one example, stay still briefly, then release.
  The Still label supplies negative examples, including ordinary small movements.
  Proposed defaults: 350 ms touch settling, 100 Hz requested accelerometer
  and device-motion rates, four-second recording bound, trim the final 100 ms before
  release. These are acquisition hypotheses; report actual sample timing.
- State: idle -> settling -> recording -> saved on release; drag outside,
  interruption, inactivity, disconnect or sensor fault -> discard -> idle.
  Completion of the four-second limit stops sensors and saves the bounded trial.
  Generation tokens reject late samples. No haptics during acquisition.
- Data: versioned JSON with UUID, label, wrist/crown, device/OS metadata,
  requested interval, actual per-stream timestamps, source metadata and device-axis values. Files
  stay inside the two companion apps until user exports them. No credentials or
  TV/network identifiers are included. Transfer is explicit via Send recordings;
  file transfers may finish later and never represent volume commands.
- Files: `Sources/Bridge/FingerGestureRecording.swift` (schema, deterministic
  buffer/validation and local store); `Sources/Watch/FingerCaptureController.swift`
  (acquisition); `Sources/Watch/FingerCaptureView.swift` (hold interaction);
  `WatchRemoteModel.swift`/`VolumeRemoteView.swift` (cancel old motion, transfer);
  `PhoneRelayCoordinator.swift`/`TVSetupView.swift` (receive/export JSON).
- Acceptance: no auto-start wrist sensing; release/drag/system cancellation stops
  sampling; no guessed volume sends; bound storage/sample count; encode/decode and
  cancellation tests pass; signed Watch/iPhone build passes. Physical recording,
  measured rate, file delivery and signal quality still require the user's Watch.
- Hardware step: collect at least five separate Up, Down and Still trials with
  the Watch on the demonstrated wrist. Export the combined JSON from iPhone.

### F2: Determine whether the two signals are separable

Depends on actual F1 recordings. Inspect signal-to-noise, repeatability, sample
rate, timing gaps and possible touch artifacts. Compare against Still and both
labels using held-out trials. Define features/windowing/unknown rejection from
evidence. Record results and failures. If the signal is insufficient, document
that before choosing a different interaction with the user. Do not presume an
ML classifier can recover finger motion absent a measurable wrist signal.

### F3: Hold-to-detect, then guarded volume

Depends on F2 evidence. Hold -> settle/calibrate -> observe -> classify once per
complete gesture -> rearm only after rest; release/inactivity/disconnect cancels.
Start with visible predicted Up/Down/Unknown and physical confirmation, then
connect accepted events to the existing activation-scoped expiring volume path.
Keep command bounds, zero backlog, TLS pinning and ambiguous-send non-replay.
Tests must cover negatives, opposite gestures, refractory/return motion,
orientation, rate bounds, stale input, release, disconnect and late callbacks.

## Unresolved hardware questions

- Do these two finger motions produce different, repeatable wrist sensor signals?
- Does held touch introduce larger artifacts than the gesture itself?
- Is the delivered sampling rate sufficient on this Watch SE 3?
- Can the user's gesture timing and posture be recognized across separate holds?

References checked against Apple documentation and installed SDK on 2026-10-17:
[Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager),
[actual gyro update intervals](https://developer.apple.com/documentation/coremotion/cmmotionmanager/gyroupdateinterval),
[double-tap integration](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap),
[file receipt](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:)).
