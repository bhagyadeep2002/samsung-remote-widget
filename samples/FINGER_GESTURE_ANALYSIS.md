# Initial finger sensor data assessment

Input: `samples/finger-gesture-export.json` (SHA-256 `4e4a52991afdb1dc4564ba105c3ede06f306e99368331264389bee36a59c560e`).

The export contains one Up trial, one Down trial and zero Still trials. Both
trials pass schema/finite-value/timestamp/duration/sample-count checks. The
recording fix produced raw acceleration plus device-motion rotation on the
left wrist, crown right. F1 acquisition and export are now physically evidenced.

| Label | Duration | Accel samples / Hz | Rotation samples / Hz | Largest sample interval |
| --- | ---: | ---: | ---: | ---: |
| Down | 1.56 s | 156 / 99.6 | 155 / 99.6 | 10.04 ms |
| Up | 3.28 s | 327 / 99.6 | 328 / 99.6 | 10.04 ms |

Streams are monotonic, finite, and have no large gaps or duplicate sample
timestamps. Actual sample timing is approximately 99.6 Hz; requested rate was
100 Hz. Acceleration includes gravity; rotation is bias-corrected device-motion
rotationRate. The two streams keep independent timestamps.

Both trials contain movement. Median-centered acceleration RMS is approximately
0.026 g for Up and 0.028 g for Down; median-centered rotation RMS is approximately
0.113 rad/s for Up and 0.133 rad/s for Down. These are descriptive whole-trial
metrics, affected by differing duration and gesture timing. They are not
classifier features or evidence that direction can be separated reliably.

No classifier was trained: with one example per label there is no independent
training/test split, and without Still there is no false-positive measurement.
The recordings alone also cannot establish whether a peak comes from the
intended finger motion or incidental wrist/touch movement. Do not reuse portions
of one recording as independent held-out trials.

Next: obtain at least four additional Up, four additional Down and five Still
trials. Send recordings from Watch, wait for iPhone counts of Up 5 / Down 5 /
Still 5, and export again to the same JSON path. Existing trial IDs are deduplicated
on iPhone, so resending existing files does not double the counts. If those trials
were already recorded, wait for all transfers before exporting again. Follow
F2 in `FINGER_GESTURE_PLAN.md`; F3 remains pending signal/repeatability evidence.
