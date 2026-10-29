#!/usr/bin/env python3
"""Render Notch Monster's short UI cues with Earshot's procedural sound bank.

Use the pinned Earshot checkout and dependencies documented in sound-design/README.md.
No models, recordings, or network services are needed to render these recipes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--earshot-source', type=Path, required=True)
parser.add_argument('--only', help='Regenerate one sound while refining the set')
args = parser.parse_args()
sys.path.insert(0, str(args.earshot_source.resolve()))

import numpy as np
from scipy import signal
import soundfile as sf
from earshot.forge import bank, sfx

ROOT = Path(__file__).resolve().parents[1]
SR = 48000
COMMIT = '591fa3e028032e6dce56620a20e932e35667e8d8'
# (bank id, length, offset, relative gain, optional synthesis knobs)
RECIPES = {
    'fuzzy-reach': [('swish/soft', .09, 0, 1, {'apex': .025})],
    'fuzzy-file': [
        ('whoosh_fast/sleeve', .18, 0, 1, {'apex': .045}),
        ('ui_pop/boop', .14, .025, .48, {'pitch': 350}),
    ],
    'fuzzy-window': [
        ('whoosh_fast/sleeve', .24, 0, .8, {'apex': .06}),
        ('swipe/paper', .21, 0, .65, {'apex': .05}),
        ('knock/wood', .10, .045, .26, {}),
        ('knock/plastic', .10, .10, .15, {}),
    ],
    'rubber-reach': [('ui_pop/soft', .10, 0, 1, {'pitch': 630})],
    'rubber-file': [
        ('ui_pop/fall', .18, 0, 1, {'pitch': 420}),
        ('swish/soft', .17, 0, .38, {'apex': .035}),
    ],
    'rubber-window': [
        ('ui_pop/fall', .19, 0, 1, {'pitch': 350}),
        ('ui_pop/boop', .17, .075, .48, {'pitch': 260}),
        ('swish/soft', .24, 0, .35, {'apex': .055}),
    ],
    'arcade-reach': [('ui_pop/blip', .075, 0, 1, {'pitch': 1000})],
    'arcade-file': [
        ('pro_zip/down', .19, 0, .8, {}),
        ('ui_pop/blip', .09, .015, .35, {'pitch': 440}),
    ],
    'arcade-window': [
        ('pro_zip/down_warm', .25, 0, .8, {}),
        ('glitch/chirp', .18, 0, .5, {}),
        ('ui_pop/boop', .14, .08, .3, {'pitch': 330}),
    ],
}

native = ROOT / 'Resources/Sounds'
web = ROOT / 'website/dist/assets/sounds'
design = ROOT / 'sound-design'
for directory in (native, web, design):
    directory.mkdir(parents=True, exist_ok=True)
report_path = design / 'sound-report.json'
report = json.loads(report_path.read_text()) if args.only and report_path.exists() else {
    'generator': 'Earshot 0.4.0 procedural bank + Notch Monster mixes',
    'earshot_commit': COMMIT, 'sample_rate': SR, 'sounds': {}}
if args.only and args.only not in RECIPES:
    raise SystemExit('Unknown sound: ' + args.only)
for name, recipe in RECIPES.items():
    if args.only and args.only != name:
        continue
    layers = []
    for index, (sound_id, duration, offset, gain, knobs) in enumerate(recipe):
        samples, meta = bank.render(sound_id, dur=duration, peak_db=-1, **knobs)
        if samples.ndim == 1:
            samples = np.column_stack((samples, samples))
        layers.append((round(offset * SR), samples * gain))
    length = max(offset + len(samples) for offset, samples in layers)
    mixed = np.zeros((length, 2))
    for offset, samples in layers:
        mixed[offset:offset + len(samples)] += samples
    # Remove inaudible rumble/DC, taper the ends, and leave headroom. These are
    # short feedback sounds; the reach stays much quieter than the yank.
    mixed = signal.sosfilt(signal.butter(2, 45, btype='highpass', fs=SR, output='sos'), mixed, axis=0)
    head, tail = round(.002 * SR), round(.025 * SR)
    mixed[:head] *= np.linspace(0, 1, head)[:, None] ** 2
    mixed[-tail:] *= np.linspace(1, 0, tail)[:, None] ** 3
    target_peak = -21 if name.endswith('reach') else -14
    mixed *= 10 ** (target_peak / 20) / np.max(np.abs(mixed))
    # A short silent tail prevents device truncation of the final samples.
    mixed = np.pad(mixed, ((0, round(.008 * SR)), (0, 0)))
    path = native / f'{name}.wav'
    sf.write(path, mixed, SR, subtype='PCM_16')
    written, _ = sf.read(path)
    audit = sfx.check(written, sr=SR)
    report['sounds'][name] = {
        'recipe': recipe, 'duration_s': len(written) / SR,
        'peak_dbfs': float(20 * np.log10(np.max(np.abs(written)))),
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'audit': audit,
    }
    shutil.copy2(path, web / path.name)
    print(f'{name}: {len(written)/SR:.3f}s; {audit["summary"]}', flush=True)

report_path.write_text(json.dumps(report, indent=2) + '\n')
audition = []
for name in RECIPES:
    written, _ = sf.read(native / f'{name}.wav')
    audition += [written, np.zeros((round(.32 * SR), 2))]
sf.write(design / 'audition.wav', np.concatenate(audition), SR, subtype='PCM_16')
shutil.copy2(args.earshot_source / 'LICENSE', native / 'Earshot-LICENSE.txt')
shutil.copy2(args.earshot_source / 'LICENSE', web / 'Earshot-LICENSE.txt')
failures = [name for name, entry in report['sounds'].items() if not entry['audit']['ok']]
if failures:
    raise SystemExit('Audio audit failed: ' + ', '.join(failures))
