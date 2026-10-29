# Notch Monster sounds

Nine short stereo cues, generated with [Earshot](https://github.com/Leonxlnx/earshot)'s procedural sound bank and mixed for the arm's fast movement. Earshot is an authoring tool; neither the app nor the website needs Python or a model at runtime.

| Set | Character | Events |
| --- | --- | --- |
| Fuzzy | Soft cloth swish, low gulp, paper crunch | reach, file yank, window fold |
| Rubber | Rounded, falling rubbery pops | reach, file yank, window fold |
| Arcade | Blip, descending zip, short glitch | reach, file yank, window fold |

The reach peaks at -21 dBFS; yanks peak at -14 dBFS. Each cue is under 0.3 seconds, with tapered ends and no clipping. The full set is about 320 KB. The app and browser use the same 48 kHz, stereo, 16-bit WAVs. `audition.wav` plays each set's reach, file, and window cues in table order, with short gaps.

## Reproduce

Pin Earshot to commit `591fa3e028032e6dce56620a20e932e35667e8d8` (0.4.0). Its bank rendering and model-free audit need NumPy, SciPy, SoundFile, soxr, and pyloudnorm. Create an isolated Python 3.12 environment with those dependencies, then run from this repository:

```sh
python scripts/generate_sounds.py --earshot-source /path/to/earshot
```

The script writes `Resources/Sounds`, `website/dist/assets/sounds`, `sound-report.json`, and the audition. `--only arcade-window` can regenerate one cue while refining its mix. The report records every source bank ID, knob, mix offset, duration, file hash, and Earshot audit result. The audit checks signal properties; it does not replace human listening.

All layers come from Earshot's code-synthesized recipes, with no recordings or model downloads. Earshot's MIT notice is included alongside the distributed WAVs as `Earshot-LICENSE.txt`.
