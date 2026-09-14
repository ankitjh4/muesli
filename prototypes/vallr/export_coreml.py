"""Developer-only conversion; the resulting Core ML model needs no Python.

Install coremltools==8.3.0 in the prototype environment. This converts the
verified research checkpoint, not the unavailable trained English decoder.
The resulting model retains the CC BY-NC 4.0 restrictions in NOTICE.md.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

from vallr_prototype import DEFAULT_MODEL, load_checkpoint, verify_checkpoint_hash


class PhonemeModel(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, video):
        logits, _ = self.model(video)
        return logits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Output already exists; choose a new output path.")
    if not verify_checkpoint_hash(args.model):
        raise SystemExit("Checkpoint does not match the verified research download.")
    torch.set_num_threads(4)
    torch.manual_seed(42)
    model = PhonemeModel(load_checkpoint(args.model, torch.device("cpu"))).eval()
    sample = torch.rand(1, 16, 3, 224, 224) * 255
    print("Tracing fixed-size video → phoneme logits", flush=True)
    with torch.inference_mode():
        traced = torch.jit.trace(model, sample, check_trace=False)
    print("Converting to Core ML (float32 baseline)", flush=True)
    converted = ct.convert(
        traced,
        inputs=[ct.TensorType(name="video", shape=sample.shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="phoneme_logits", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT32,
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    converted.author = "Marshall Thomas, Edward Fish, Richard Bowden; Core ML adaptation for Muesli+"
    converted.license = "CC BY-NC 4.0; see prototypes/vallr/NOTICE.md"
    converted.short_description = "Experimental English visual phoneme recognition; not a text decoder"
    converted.user_defined_metadata["input_layout"] = "N,T,C,H,W; 16 RGB face frames; 224x224; float pixels 0..255, matching prototype"
    converted.user_defined_metadata["source_revision"] = "9793489136bc00293242a5410def05ba2806e16f"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(args.output))
    print(f"Saved {args.output}; checking numerical parity", flush=True)
    results = []
    for label, tensor in [("random", sample), ("zero", torch.zeros_like(sample))]:
        with torch.inference_mode():
            expected = model(tensor).numpy()
        actual = converted.predict({"video": tensor.numpy()})["phoneme_logits"]
        error = float(np.max(np.abs(expected - actual)))
        matches = bool(np.array_equal(expected.argmax(-1), actual.argmax(-1)))
        results.append({"fixture": label, "shape": list(actual.shape), "max_absolute_error": error, "argmax_matches": matches})
        print(json.dumps(results[-1]), flush=True)
        if not np.isfinite(actual).all() or not matches or not np.allclose(expected, actual, atol=0.01, rtol=0.001):
            raise SystemExit("Core ML parity failed; do not ship this artifact.")
    report = args.output.with_suffix(".parity.json")
    report.write_text(json.dumps(results, indent=2) + "\n")
    print("Core ML synthetic parity passed. Real-video accuracy remains unverified.", flush=True)


if __name__ == "__main__":
    main()
