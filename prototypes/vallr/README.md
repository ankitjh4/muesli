# Muesli+ VALLR prototype

This is an isolated, non-commercial experiment for English visual speech
recognition, retained for developers rather than exposed as user setup.
The app no longer asks users to select a Python environment or prototype folder.
Its built-in lip-dictation pipeline is under development. This prototype never
opens or records the microphone, and its checkpoint remains outside the app.

## Developer-only Core ML conversion

With `coremltools==8.3.0` installed in the prototype environment, run
`./.venv/bin/python export_coreml.py --output .models/VALLR-fp32.mlpackage` from
this directory. The exporter refuses an existing output, verifies the checkpoint,
and checks synthetic numerical parity. The resulting visual model runs through
Apple Core ML without Python. It is still a phoneme model, not a trained English
text decoder. Native input preprocessing and real-video quality require separate
verification. Generated models retain the non-commercial restrictions in
[NOTICE.md](NOTICE.md) and must not be committed to Git.

The downloaded `VALLR.path` file is the official VALLR V1 PyTorch checkpoint.
Despite the `.path` suffix, it is a valid PyTorch archive. `setup.sh` copies it
to the ignored `.models/VALLR.pth` location so the 696 MB checkpoint cannot be
accidentally committed.

## Setup and validation

```sh
cd prototypes/vallr
./setup.sh
.venv/bin/python vallr_prototype.py --check-only
```

If the checkpoint is elsewhere, pass its path to `./setup.sh /path/to/VALLR.pth`.
In the app, select this prepared folder, confirm that you trust its executable,
and choose a video or start a camera test. The app shows phonemes and can
optionally reconstruct an **English guess** with its downloaded local Qwen
language model. No Ollama installation is needed for the app's reconstruction.
Nothing is automatically pasted, saved to history, or learned by the dictionary.

## Test with the Mac camera

```sh
.venv/bin/python vallr_prototype.py
```

The shorter equivalent is `./run.sh`.

Press Space and silently mouth one short English sentence for four seconds.
Press Q or Escape to cancel. macOS may ask Terminal or Python for camera
permission the first time.

To test a previously recorded video without its audio:

```sh
.venv/bin/python vallr_prototype.py --video /absolute/path/to/video.mp4
```

Imported clips are limited to ten seconds and 600 frames. For the native app's
machine-readable protocol, add `--json --llm off`. This emits schema-versioned
JSON on stdout, diagnostics on stderr, and does not open a result window.
Camera capture still opens its explicit preview window. The app allows three
minutes for a test and cancels the helper when its page is closed.

The prototype decodes only video frames. OpenCV cannot request or capture audio
in this program.

## What the result means

The public checkpoint contains VALLR's video-to-phoneme stage. It does not
contain the paper's trained phoneme-to-English LLM adapter. The prototype always
shows the raw ARPAbet phonemes so the visual model can be evaluated honestly.

When the locally installed `qwen3.6:27b` Ollama model is available, the script
also asks it to reconstruct one likely English sentence. Disable that optional
step with `--llm off`. No cloud service is used.

The upstream checkpoint was trained from normal voiced video with the audio
discarded, not from people deliberately mouthing words silently. Real webcam
quality can therefore be substantially worse than the published LRS3 score.

## Provenance and licensing

- Read [NOTICE.md](NOTICE.md) for the pinned source, authors, adaptation details,
  and license terms. The repository's root MIT license does not cover the
  adapted VALLR architecture or checkpoint.
- VALLR paper and implementation: <https://github.com/MarshallT-99/VALLR>
- Watch Your Mouth is not used: it requires depth-camera point clouds and CUDA.
- VALLR is CC BY-NC 4.0. This prototype and its checkpoint are for local,
  non-commercial evaluation only and must not be shipped in a commercial build.
