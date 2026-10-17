# Finger gesture assessment: updated export

Input: `samples/finger-gesture-export_v2.json`; SHA-256 `449158b74b90386a9f21575c205b58c9c40ba314bc6135b7623820a950e35695`.

17 unique trials: 6 Up, 6 Down, 5 Still. All are left wrist/crown right,
raw acceleration plus device-motion rotation, version 2. Every stream passes
finite-value, monotonic-time, duration and sample-count checks. Both streams
deliver approximately 99.6 Hz with a maximum interval below 10.05 ms.

## Exploratory trial-held-out results

Each fold withholds one complete recording. Standardization/model fitting use
only the other recordings; no fragments of a held-out trial enter training.
Features omit duration, absolute/post-settling event time, static pose and
recording order. Two simple fixed classifiers compare whole-trial statistics
and a label-blind one-second peak window. Scores below are exploratory on one
wearer/batch; choosing methods after seeing these data is not independent
validation.

| Feature window | Classifier | Correct / 17 |
| --- | --- | ---: |
| Whole trial | 3 nearest neighbors | 13 |
| Whole trial | Shrinkage linear discriminant | 14 |
| Peak | 3 nearest neighbors | 14 |
| Peak | Shrinkage linear discriminant | 16 |
| Peak, first/last 300 ms excluded | 3 nearest neighbors | 16 |
| Peak, first/last 300 ms excluded | Shrinkage linear discriminant | 15 |

The conservative boundary-trimmed three-neighbor rule returns a class only
when all three neighbors agree: **12/17 accepted, all 12 correct; five Unsure**
in these held-out folds. Without rejection it gets 16/17 right, including one
Down→Up error. The strongest untrimmed discriminant gets 16/17 but makes a
high-confidence Up→Down error. Confidence alone is not sufficient for TV use.

A separate chronological split trains on the first three recordings per class
and tests the later eight: the fixed peak-window nearest-neighbor baseline gets
8/8 in this same batch. This tiny check is not a new session or a shipping
accuracy claim. Labels were collected in blocks, so collection-state and
posture confounds cannot be ruled out by either split.

## Signal interpretation and limitations

- One Still trial (977E3C15) has considerable early motion; retain it as a
  negative rather than discard an inconvenient sample.
- Several Down trials peak near the beginning. Cropping boundaries changes
  some decisions; capture timing or residual touch movement may contribute.
- Up tends to contain a stronger oscillating rotation burst. The available
  samples show repeatable differences, but do not establish finger-only
  recognition across different days, postures, wrist sides or ordinary activity.
- Offline preprocessing sees a completed hold, including samples after the
  event. These results do not establish real-time streaming detection or latency.
- Unanimous nearest neighbors can still misclassify novel movements; five Still
  trials are not a complete false-positive evaluation.

## Experimental Watch preview

Use the boundary-trimmed, one-second peak-window 42-feature pipeline and three
nearest standardized templates, with unanimous voting. Freeze the 17 numeric
templates in `Sources/Gesture/FingerGestureModel.swift`; training hash is embedded.
The model only applies to the captured wrist/crown/source configuration.
Other configurations and invalid data return Unsure. No test guesses are added
to the labeled recording store, and no preview result sends a TV command.

Python/Swift replay matched every prediction on all 17 records; maximum feature
error was 1.44e-14. This verifies implementation parity on recorded data,
not fresh Watch recognition accuracy. Synthetic-reference tests independently
exercise preprocessing, static-offset removal, invalid data and configuration
rejection. Fresh physical testing remains the next gate.

Try the new **Test gestures** mode with Up, Down and Still in mixed order: hold,
wait for GO, perform one gesture (or stay still), rest, then release after 2–3
seconds. Read one result after release. Record wrong directions and Unsure
outcomes. Live volume integration and while-held streaming remain deferred.

## Reproduce

Install numpy, scipy, scikit-learn and matplotlib in a Python virtualenv, then:

```sh
python scripts/analyze_finger_recordings.py samples/finger-gesture-export_v2.json
```

To regenerate the frozen model explicitly, add
`--emit-swift-model Sources/Gesture/FingerGestureModel.swift`.
The model regeneration uses all 17 trials; held-out scores above refit per fold.

Build verification: 90 macOS tests pass; signed mobile build and nested signatures
pass. Direct Watch installation failed twice because CoreDevice could not form a
tunnel. Install the preview using SamsungTVRemoteWatch + actual Watch + Cmd-R in
Xcode. No fresh hardware preview results are claimed.
