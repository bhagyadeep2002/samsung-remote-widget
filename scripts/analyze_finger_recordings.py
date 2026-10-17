#!/usr/bin/env python3
"""Exploratory, whole-trial-held-out analysis; no deployable recognizer.

Dependencies: numpy scipy scikit-learn matplotlib (install in a virtualenv).
Usage: python scripts/analyze_finger_recordings.py samples/finger-gesture-export_v2.json
Outputs derived JSON and PNG next to input. Optional --emit-swift-model writes
frozen numeric templates to the specified Swift source. No running app state changes.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from scipy.ndimage import gaussian_filter1d
from sklearn.base import clone
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.metrics import confusion_matrix
from sklearn.model_selection import LeaveOneOut
from sklearn.neighbors import KNeighborsClassifier
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

LABELS = ['up', 'down', 'still']
AXES = ['x', 'y', 'z']


def stream(trial, name):
    points = trial[name]
    t = np.array([p['time'] for p in points])
    v = np.array([[p[k] for k in AXES] for p in points])
    assert 20 <= len(t) <= 1000 and np.all(np.isfinite(t)) and np.all(np.isfinite(v))
    assert np.all(np.diff(t) > 0) and t[0] >= 0 and t[-1] <= trial['duration']
    assert t[-1] - t[0] >= .5
    return t, v


def uniform(trial):
    at, av = stream(trial, 'accelerometer')
    gt, gv = stream(trial, 'gyroscope')
    t = np.arange(max(at[0], gt[0]), min(at[-1], gt[-1]), .01)
    a = np.column_stack([np.interp(t, at, av[:, i]) for i in range(3)])
    g = np.column_stack([np.interp(t, gt, gv[:, i]) for i in range(3)])
    # Remove static posture/gravity and constant gyro bias per trial. A 300 ms
    # local mean suppresses slow arm drift; no class/time information is used.
    a = a - gaussian_filter1d(a, sigma=15, axis=0, mode='nearest')
    g = g - np.median(g, axis=0)
    return t, np.column_stack([a, g])


def features(t, values, peak_window):
    if peak_window:
        # Pick the strongest movement using gyro magnitude, before looking at
        # labels. Keep a fixed one-second window; repeat edge samples rather than
        # reveal trial duration through zero padding. Relative peak time excluded.
        energy = gaussian_filter1d(np.sum(values[:, 3:] ** 2, axis=1), sigma=3)
        peak = int(np.argmax(energy))
        indices = np.clip(np.arange(peak - 50, peak + 50), 0, len(t) - 1)
        values = values[indices]
    result = []
    for signal in values.T:
        # Duration, absolute timestamps, static posture and recording order are
        # deliberately absent. Signed extrema retain potential direction signal.
        result.extend([np.sqrt(np.mean(signal ** 2)), np.quantile(signal, .1),
                       np.quantile(signal, .9), np.min(signal), np.max(signal),
                       np.sqrt(np.mean(np.diff(signal) ** 2))])
    # Within-sensor axis relationships, not baseline orientation.
    for block in [values[:, :3], values[:, 3:]]:
        cov = np.cov(block.T)
        for i, j in [(0, 1), (0, 2), (1, 2)]:
            result.append(cov[i, j] / max(1e-9, np.sqrt(cov[i, i] * cov[j, j])))
    return np.array(result)


def evaluate(x, y, model):
    predictions = []
    folds = []
    for train, test in LeaveOneOut().split(x):
        estimator = clone(model)
        estimator.fit(x[train], y[train])
        probabilities = estimator.predict_proba(x[test])[0]
        pred = str(estimator.classes_[np.argmax(probabilities)])
        predictions.append(pred)
        order = np.sort(probabilities)
        # Fixed illustrative rejection; never tuned on the held-out sample.
        accepted = order[-1] >= .75 and order[-1] - order[-2] >= .25
        folds.append({'actual':str(y[test[0]]), 'predicted':pred,
                      'accepted':bool(accepted), 'confidence':float(order[-1])})
    accepted = [f for f in folds if f['accepted']]
    return {'correct':int(np.sum(np.array(predictions) == y)), 'total':len(y),
            'confusion_matrix_labels':LABELS,
            'confusion_matrix':confusion_matrix(y, predictions, labels=LABELS).tolist(),
            'accepted':len(accepted),
            'accepted_correct':sum(f['actual'] == f['predicted'] for f in accepted),
            'accepted_still_as_gesture':sum(f['actual'] == 'still' and f['predicted'] != 'still' for f in accepted),
            'folds':folds}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--emit-swift-model', type=Path, help='Write frozen preview templates to this Swift source file')
    args = parser.parse_args()
    raw = args.input.read_bytes()
    trials = sorted(json.loads(raw), key=lambda r:r['capturedAt'])
    assert len({r['id'] for r in trials}) == len(trials), 'Duplicate trial IDs'
    for r in trials:
        assert r['version'] == 2 and r['acquisition'] == 'rawAccelerometerWithDeviceMotionRotation'
        assert r['label'] in LABELS and .8 <= r['duration'] <= 4
    assert len({(r['wrist'], r['crown'], r['acquisition']) for r in trials}) == 1
    y = np.array([r['label'] for r in trials])
    assert all(np.sum(y == label) >= 3 for label in LABELS)
    prepared = [uniform(r) for r in trials]
    result = {'input':str(args.input), 'sha256':hashlib.sha256(raw).hexdigest(),
              'counts':dict(collections.Counter(y)), 'quality':[], 'models':{},
              'scope':'Exploratory leave-one-whole-trial-out, single wearer and collection session. Not an independent deployment test.'}
    for r in trials:
        q = {'id':r['id'], 'label':r['label'], 'duration':r['duration']}
        for name in ['accelerometer', 'gyroscope']:
            t, v = stream(r, name)
            v = v - np.median(v, axis=0)
            q[name] = {'samples':len(t), 'rate_hz':float((len(t)-1)/(t[-1]-t[0])),
                       'maximum_gap_ms':float(np.max(np.diff(t))*1000),
                       'peak_time':float(t[np.argmax(np.sum(v*v, axis=1))]),
                       'centered_rms':float(np.sqrt(np.mean(np.sum(v*v, axis=1))))}
        result['quality'].append(q)
    # Two fixed, simple baselines; scalers fit only on the training recordings.
    models = {'nearest_3':make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=3)),
              'shrinkage_lda':make_pipeline(StandardScaler(), LinearDiscriminantAnalysis(solver='lsqr', shrinkage='auto'))}
    for peak in [False, True]:
        x = np.vstack([features(t, v, peak) for t, v in prepared])
        name = 'peak_window' if peak else 'whole_trial'
        for model_name, model in models.items():
            result['models'][name + '_' + model_name] = evaluate(x, y, model)
    # Boundary-artifact sensitivity control: rerun fixed classifiers after
    # excluding the first/last 300 ms. Same whole-trial folds, no retuning.
    trimmed = [(t[(t >= .3) & (t <= r['duration']-.3)],
                v[(t >= .3) & (t <= r['duration']-.3)])
               for r, (t, v) in zip(trials, prepared)]
    x = np.vstack([features(t, v, True) for t, v in trimmed])
    for model_name, model in models.items():
        result['models']['boundary_trimmed_peak_' + model_name] = evaluate(x, y, model)
    if args.emit_swift_model:
        scales = StandardScaler().fit(x).scale_
        model_lines = ["// Generated by scripts/analyze_finger_recordings.py; experimental preview only.",
            "// Training source SHA-256: " + result['sha256'],
            "enum FingerGestureModel {", "    struct Template {",
            "        let decision: FingerGestureClassifier.Decision",
            "        let features: [Double]", "    }",
            "    static let scales: [Double] = [" + ', '.join(format(v, '.17g') for v in scales) + "]",
            "    static let templates: [Template] = ["]
        for label, vector in zip(y, x):
            model_lines.append("        Template(decision: ." + str(label) + ", features: [" +
                ', '.join(format(v, '.17g') for v in vector) + "]),")
        model_lines += ["    ]", "}", ""]
        args.emit_swift_model.write_text('\n'.join(model_lines))
    # Honest temporal check: train first 3 of each class, test the later trials.
    # This retains class balance but does not remove class-block collection bias.
    train, test = [], []
    counts = collections.Counter()
    for i, label in enumerate(y):
        (train if counts[label] < 3 else test).append(i)
        counts[label] += 1
    x = np.vstack([features(t, v, True) for t, v in prepared])
    model = clone(models['nearest_3']).fit(x[train], y[train])
    prediction = model.predict(x[test])
    result['later_trial_check'] = {'training_per_class':3,
        'test_ids':[trials[i]['id'] for i in test],
        'correct':int(np.sum(prediction == y[test])), 'total':len(test),
        'confusion_matrix_labels':LABELS,
        'confusion_matrix':confusion_matrix(y[test], prediction, labels=LABELS).tolist()}
    out = args.input.with_name('finger-gesture-assessment-v2.json')
    out.write_text(json.dumps(result, indent=2) + '\n')
    # Same limits for every trace, each trial kept intact. Grey span marks
    # first/last 200 ms, where residual press/release motion can confound data.
    fig, axes = plt.subplots(6, 3, figsize=(16, 16), sharex=True)
    for column, label in enumerate(LABELS):
        selected = [(r, uniform(r)) for r in trials if r['label'] == label]
        for row in range(6):
            ax = axes[row, column]
            if row >= len(selected): ax.axis('off'); continue
            r, (t, values) = selected[row]
            for i, axis in enumerate(AXES):
                ax.plot(t, values[:, i+3], label=axis, linewidth=.9)
            ax.set_ylim(-.65, .65); ax.set_xlim(0, 4)
            ax.axvspan(0, .2, color='grey', alpha=.15)
            ax.axvspan(max(0, r['duration']-.2), r['duration'], color='grey', alpha=.15)
            ax.set_title(f'{label.title()} {row+1} · {r["id"][:8]} · {r["duration"]:.2f}s', fontsize=10)
            ax.grid(alpha=.2)
            if column == 0: ax.set_ylabel('Rotation, rad/s')
            if row == 5: ax.set_xlabel('Seconds after settling')
    axes[0,0].legend(loc='upper right', fontsize=7)
    fig.suptitle('Finger gesture recordings: baseline-centered rotation (not predictions)', fontsize=16)
    fig.tight_layout(rect=(0,0,1,.98))
    fig.savefig(args.input.with_name('finger-gesture-traces-v2.png'), dpi=130)
    plt.close(fig)
    print(json.dumps({k:v for k,v in result.items() if k != 'quality'}, indent=2))


if __name__ == '__main__':
    main()
