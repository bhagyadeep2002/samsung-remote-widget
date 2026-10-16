# Repository instructions

## Read first

- Read `WATCH_HANDOFF.md` for project history, the source map, protocol details,
  known limitations, and the proposed Apple Watch sequence.
- Read `README.md` and `project.yml` before changing targets or build settings.
- Inspect the current source and Git status before editing. The handoff is a
  historical checkpoint; newer code and explicit user decisions take precedence.

## Goal and scope

Port the working Samsung TV remote to Apple Watch, starting with volume control
using a wrist twist like turning a knob: clockwise increases volume and
anticlockwise decreases it. Define direction from the user's perspective and
validate it on their Watch. Digital Crown input alone does not fulfill this goal.

Preserve the working macOS menu bar app. No extra hardware purchases. Start with
foreground Watch operation; background gesture recognition is outside the initial
scope. Do not restore the retired desktop widget or App Group architecture.

These instructions provide context for future work, not authorization to start
implementation when the user's current request is only planning or documentation.

## Planning and implementation workflow

The user wants to use Sol for difficult design decisions and Luna for implementing
a concrete plan. Follow this workflow regardless of the active model; do not
claim to switch models or start other agents automatically.

1. For planning work, produce a repository document with milestones, affected
   files, interfaces, state transitions, acceptance criteria, dependencies and
   unresolved assumptions. Distinguish user requirements from proposed defaults.
2. Establish a viable Watch-to-TV transport and tappable volume controls before
   integrating motion. Check current Apple documentation and installed SDKs.
   WatchConnectivity is a Watch/iPhone channel, not a Watch/Mac bridge.
3. For implementation work, read the latest plan and complete one coherent
   milestone at a time. Keep changes small enough to review and validate.
4. Resolve routine implementation details autonomously. If evidence invalidates
   the planned transport, interaction model or platform assumptions, document the
   evidence and revised approach. Ask the user only when a material product
   decision or dependency needs their input; continue independent useful work.
5. Record completed milestones, verification results and remaining hardware
   questions in the plan or handoff so another session can continue.

`WATCH_HANDOFF.md` is a starting proposal, not a complete implementation spec.
An extensive plan cannot establish gesture sensitivity without physical testing.

## Motion interaction requirements

- Begin with an explicit activation interaction and neutral-pose calibration.
  Hold-to-activate is a proposed starting point, not a confirmed user choice.
- Separate sensor acquisition, deterministic gesture processing, UI, and command
  delivery. Make gesture processing testable using recorded or synthetic samples.
- Account for wrist side, Watch orientation, posture, angle wraparound, sensor
  noise, direction reversals, and recentering without unintended volume changes.
- Use configurable initial thresholds, a dead zone, hysteresis and a bounded
  command rate. Treat numerical sensitivity values as hypotheses until tested.
- Stop motion processing and discard pending gesture commands on deactivation,
  app inactivity, connection loss or cancellation. Bound the backlog so old
  motion cannot produce delayed volume changes after the user stops.
- Show connection/activation state clearly. Do not report an absolute TV volume
  percentage or confirmed execution without actual TV feedback.
- Do not introduce workout sessions or extended runtime as an assumed workaround
  for background execution restrictions.

## Preserve connection and credential behavior

- Reuse authenticated connections and serialize commands. Do not reintroduce a
  fresh pairing/TLS handshake for every volume step.
- Preserve certificate pinning: first-use trust during pairing, then validate
  the saved SHA-256 certificate fingerprint. Never globally disable TLS checks.
- Keep tokens and certificate pins in platform-appropriate Keychain storage.
  Never commit credentials or assume Mac credentials automatically reach Watch.
- Do not replay ambiguous failed sends. Gesture commands must also expire or be
  cancelled before transmission when they become stale.
- Audit shared code for watchOS availability; `Sources/App` imports AppKit and
  belongs to macOS. Reassess lifecycle and keepalive behavior on Watch.
- Do not make Tata Play keypad forwarding a prerequisite for Watch volume work;
  its unresolved hardware behavior is documented in the handoff.

## Project and validation

- `project.yml` is the source of truth for targets, signing and generated
  configuration. Preserve existing Mac bundle IDs and signing settings unless
  the user requests a change. Add appropriate identifiers for new targets.
- Generated Xcode projects, configuration plists, entitlements and build products
  are ignored. Edit the generator specification rather than only generated files.
- When testing or verification is requested, use the existing macOS test suite
  for shared transport changes. Gesture tests should cover jitter, orientation,
  reversal, wraparound, recentering, rate limits, deactivation, disconnect and
  stale-command cancellation. Follow the active session's testing instructions.
- Never represent mock or simulator results as physical Watch/TV verification.
  Report what was run, what passed, and what still needs hardware testing.

Existing macOS build and test commands, when applicable:

```sh
xcodegen generate
xcodebuild -project SamsungTVRemote.xcodeproj -scheme SamsungTVRemote \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath build/DerivedData build test
```

## Communication

Use concise, plain language. Explain consequential design changes and concrete
limitations. Avoid repeated questions and speculative fixes. Ask only for device
details that affect the next decision, and retain answers in the handoff.
