#!/usr/bin/env python3
"""Local, video-only VALLR prototype for Muesli+.

This evaluates the public VALLR stage-one checkpoint. It never opens a
microphone and never uploads camera frames. The public checkpoint emits
phonemes, not final text; optional English reconstruction uses local Ollama.
"""

from __future__ import annotations

import argparse
import gc
import json
import contextlib
import sys
import textwrap
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable, Sequence

import cv2
import numpy as np
import torch

from vallr_model import make_vallr_v1


ROOT = Path(__file__).resolve().parent
DEFAULT_MODEL = ROOT / ".models" / "VALLR.pth"
EXPECTED_MODEL_SHA256 = "967667d61e705b0bc78d40a3ec80dd7ec449aa1d4d90a5e83c0d4289309ef374"
FRAME_COUNT = 16
FRAME_SIZE = 224

PHONEME_VOCABULARY = {
    "<pad>": 0,
    "AA": 1,
    "AE": 2,
    "AH": 3,
    "AO": 4,
    "AW": 5,
    "AY": 6,
    "B": 7,
    "CH": 8,
    "D": 9,
    "DH": 10,
    "EH": 11,
    "ER": 12,
    "EY": 13,
    "F": 14,
    "G": 15,
    "HH": 16,
    "IH": 17,
    "IY": 18,
    "JH": 19,
    "K": 20,
    "L": 21,
    "M": 22,
    "N": 23,
    "NG": 24,
    "OW": 25,
    "OY": 26,
    "P": 27,
    "R": 28,
    "S": 29,
    "SH": 30,
    "T": 31,
    "TH": 32,
    "UH": 33,
    "UW": 34,
    "V": 35,
    "W": 36,
    "Y": 37,
    "Z": 38,
    "ZH": 39,
}
REVERSE_VOCABULARY = {value: key for key, value in PHONEME_VOCABULARY.items()}


class PrototypeError(RuntimeError):
    pass


def choose_device(requested: str) -> torch.device:
    if requested != "auto":
        return torch.device(requested)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def collapse_ctc(indices: Iterable[int]) -> list[str]:
    """Collapse repeated CTC classes and discard the blank class."""
    output: list[str] = []
    previous: int | None = None
    for index in indices:
        if index != previous and index != PHONEME_VOCABULARY["<pad>"]:
            phoneme = REVERSE_VOCABULARY.get(index)
            if phoneme:
                output.append(phoneme)
        previous = index
    return output


def sample_evenly(items: Sequence[np.ndarray], count: int = FRAME_COUNT) -> list[np.ndarray]:
    if len(items) < count:
        raise PrototypeError(
            f"The clip has only {len(items)} frames; at least {count} are required."
        )
    indices = np.linspace(0, len(items) - 1, count).round().astype(int)
    return [items[index] for index in indices]


def largest_face(
    frame: np.ndarray,
    detector: cv2.CascadeClassifier,
    previous: tuple[int, int, int, int] | None,
) -> tuple[tuple[int, int, int, int] | None, bool]:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    faces = detector.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(80, 80),
    )
    if len(faces):
        x, y, width, height = max(faces, key=lambda box: box[2] * box[3])
        current = np.array([x, y, width, height], dtype=np.float64)
        if previous is not None:
            current = (0.75 * np.asarray(previous)) + (0.25 * current)
        return tuple(int(value) for value in current), True
    return previous, False


def square_face_crop(frame: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    x, y, width, height = box
    center_x = x + width / 2
    center_y = y + height / 2
    side = max(width, height) * 1.22

    left = int(max(0, center_x - side / 2))
    right = int(min(frame.shape[1], center_x + side / 2))
    top = int(max(0, center_y - side / 2))
    bottom = int(min(frame.shape[0], center_y + side / 2))
    crop = frame[top:bottom, left:right]
    if crop.size == 0:
        raise PrototypeError("The detected face crop was empty.")
    return cv2.resize(crop, (FRAME_SIZE, FRAME_SIZE), interpolation=cv2.INTER_AREA)


def prepare_tensor(frames: Sequence[np.ndarray]) -> tuple[torch.Tensor, int]:
    sampled = sample_evenly(frames)
    detector_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    detector = cv2.CascadeClassifier(detector_path)
    if detector.empty():
        raise PrototypeError("OpenCV's face detector could not be loaded.")

    prepared: list[np.ndarray] = []
    face_box: tuple[int, int, int, int] | None = None
    detected_frames = 0
    for frame in sampled:
        face_box, detected = largest_face(frame, detector, face_box)
        if detected:
            detected_frames += 1
        if face_box is None:
            # The checkpoint expects a face crop. A centered square is useful as
            # a visible failure mode, but we report that detection failed.
            height, width = frame.shape[:2]
            side = min(height, width)
            face_box = ((width - side) // 2, (height - side) // 2, side, side)
        crop = square_face_crop(frame, face_box)
        prepared.append(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))

    array = np.asarray(prepared, dtype=np.float32)
    tensor = torch.from_numpy(array).permute(0, 3, 1, 2).unsqueeze(0)
    return tensor, detected_frames


def load_video(path: Path) -> list[np.ndarray]:
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise PrototypeError(f"Could not open video: {path}")
    frames: list[np.ndarray] = []
    try:
        fps = capture.get(cv2.CAP_PROP_FPS)
        if not np.isfinite(fps) or fps <= 0:
            raise PrototypeError("The clip has an invalid frame rate. Export a short, constant-frame-rate video.")
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            if len(frames) >= min(600, int(fps * 10)):
                raise PrototypeError("Use a clip of at most 10 seconds and 600 frames, containing one short English phrase.")
            # Bound retained frame memory without changing the input aspect ratio.
            scale = min(1.0, 640 / max(frame.shape[:2]))
            frames.append(cv2.resize(frame, (round(frame.shape[1] * scale), round(frame.shape[0] * scale))))
    finally:
        capture.release()
    if not frames:
        raise PrototypeError(f"No video frames were decoded from: {path}")
    return frames


def centered_lines(frame: np.ndarray, lines: Sequence[str], y: int) -> None:
    for line in lines:
        size, _ = cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)
        x = max(16, (frame.shape[1] - size[0]) // 2)
        cv2.putText(
            frame,
            line,
            (x, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
        y += 30


def capture_camera(camera_index: int, duration: float) -> tuple[list[np.ndarray], np.ndarray]:
    capture = cv2.VideoCapture(camera_index)
    if not capture.isOpened():
        raise PrototypeError(
            "Could not open the camera. Allow camera access for Terminal/Python in "
            "System Settings → Privacy & Security → Camera."
        )
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    window = "Muesli+ Silent Dictation Prototype"
    cv2.namedWindow(window, cv2.WINDOW_NORMAL)
    recording_started: float | None = None
    frames: list[np.ndarray] = []
    last_frame: np.ndarray | None = None

    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                raise PrototypeError("The camera stopped returning frames.")
            last_frame = frame.copy()
            display = cv2.flip(frame, 1)
            overlay = display.copy()
            cv2.rectangle(overlay, (0, 0), (display.shape[1], 105), (20, 20, 20), -1)
            display = cv2.addWeighted(overlay, 0.74, display, 0.26, 0)

            if recording_started is None:
                centered_lines(display, ["Press SPACE, then silently mouth one short English sentence", "Q quits — microphone is never used"], 38)
            else:
                elapsed = time.monotonic() - recording_started
                remaining = max(0.0, duration - elapsed)
                if len(frames) >= 600:
                    raise PrototypeError("Too many camera frames. Try a shorter capture.")
                scale = min(1.0, 640 / max(frame.shape[:2]))
                frames.append(cv2.resize(frame, (round(frame.shape[1] * scale), round(frame.shape[0] * scale))))
                centered_lines(display, [f"RECORDING LIP MOVEMENT  {remaining:.1f}s", "Face the camera and articulate clearly"], 38)
                cv2.circle(display, (32, 35), 10, (30, 30, 230), -1)
                if elapsed >= duration:
                    break

            cv2.imshow(window, display)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                raise KeyboardInterrupt
            if key == ord(" ") and recording_started is None:
                recording_started = time.monotonic()
    finally:
        capture.release()
        cv2.destroyAllWindows()

    if last_frame is None:
        raise PrototypeError("No camera frame was captured.")
    return frames, last_frame


def load_checkpoint(model_path: Path, device: torch.device):
    if not model_path.is_file():
        raise PrototypeError(
            f"VALLR checkpoint not found at {model_path}. Run ./setup.sh first."
        )
    model = make_vallr_v1(len(PHONEME_VOCABULARY))
    # The pinned PyTorch version supports weights_only, avoiding arbitrary
    # pickle execution from an untrusted checkpoint.
    state = torch.load(model_path, map_location="cpu", weights_only=True)
    model.load_state_dict(state, strict=True)
    model.to(device)
    model.eval()
    return model


def infer_phonemes(
    frames: Sequence[np.ndarray], model_path: Path, requested_device: str
) -> tuple[list[str], str, int, tuple[int, ...]]:
    video, detected_frames = prepare_tensor(frames)
    device = choose_device(requested_device)
    model = load_checkpoint(model_path, device)
    try:
        with torch.inference_mode():
            logits, _ = model(video.to(device))
    except RuntimeError as error:
        if device.type != "mps":
            raise
        print(f"MPS inference failed ({error}); retrying on CPU.")
        del model
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()
        model = load_checkpoint(model_path, torch.device("cpu"))
        device = torch.device("cpu")
        with torch.inference_mode():
            logits, _ = model(video)

    indices = logits.argmax(dim=-1)[0].detach().cpu().tolist()
    shape = tuple(logits.shape)
    phonemes = collapse_ctc(indices)
    del logits, model, video
    if torch.backends.mps.is_available():
        torch.mps.empty_cache()
    gc.collect()
    return phonemes, device.type, detected_frames, shape


def ollama_is_available(model_name: str) -> bool:
    try:
        with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=2) as response:
            data = json.load(response)
        return any(model.get("name") == model_name for model in data.get("models", []))
    except (OSError, urllib.error.URLError, json.JSONDecodeError):
        return False


def reconstruct_with_ollama(phonemes: Sequence[str], model_name: str) -> str:
    if not phonemes:
        return ""
    payload = {
        "model": model_name,
        "stream": False,
        "think": False,
        "keep_alive": "2m",
        "system": (
            "You decode noisy ARPAbet phoneme sequences from an English lip-reading model. "
            "Return only the single most likely natural English sentence. Never explain your answer."
        ),
        "prompt": "Noisy ARPAbet sequence: " + " ".join(phonemes),
        "options": {"temperature": 0.0, "num_predict": 32},
    }
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        result = json.load(response).get("response", "").strip()
    if "</think>" in result:
        result = result.split("</think>", 1)[1].strip()
    return result.strip('"')


def show_result(frame: np.ndarray, phonemes: Sequence[str], transcript: str) -> None:
    display = cv2.flip(frame, 1)
    overlay = display.copy()
    cv2.rectangle(overlay, (0, 0), (display.shape[1], display.shape[0]), (20, 20, 20), -1)
    display = cv2.addWeighted(overlay, 0.82, display, 0.18, 0)

    lines = ["VALLR RESULT"]
    if transcript:
        lines.extend(textwrap.wrap("English: " + transcript, width=68))
    lines.extend(textwrap.wrap("Phonemes: " + (" ".join(phonemes) or "(none)"), width=68))
    lines.append("Press any key to close")
    centered_lines(display, lines, 45)
    cv2.imshow("Muesli+ Silent Dictation Result", display)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


def verify_checkpoint_hash(path: Path) -> bool:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    actual = digest.hexdigest()
    print(f"Checkpoint SHA-256: {actual}")
    return actual == EXPECTED_MODEL_SHA256


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prototype English lip-reading with the public VALLR checkpoint."
    )
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--video", type=Path, help="Use a video file instead of the webcam")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--duration", type=float, default=4.0)
    parser.add_argument("--device", choices=("auto", "mps", "cpu"), default="auto")
    parser.add_argument("--llm", choices=("auto", "ollama", "off"), default="auto")
    parser.add_argument("--ollama-model", default="qwen3.6:27b")
    parser.add_argument("--json", action="store_true", help="Emit a structured result without opening a result window")
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Validate the checkpoint and run one synthetic forward pass without opening the camera",
    )
    return parser.parse_args()


def run(args: argparse.Namespace) -> int:
    if not 0.5 <= args.duration <= 10:
        raise PrototypeError("Camera duration must be between 0.5 and 10 seconds.")
    if not args.model.is_file():
        raise PrototypeError(f"Checkpoint not found: {args.model}. Run ./setup.sh first.")
    if not verify_checkpoint_hash(args.model):
        raise PrototypeError("The checkpoint hash differs from the verified VALLR download.")

    if args.check_only:
        print("Validating the downloaded checkpoint...")
        synthetic = [np.zeros((FRAME_SIZE, FRAME_SIZE, 3), dtype=np.uint8) for _ in range(FRAME_COUNT)]
        phonemes, device, _, shape = infer_phonemes(synthetic, args.model, args.device)
        print(f"Model loaded and completed a forward pass on {device}.")
        print(f"Output tensor: {shape}; synthetic phonemes: {' '.join(phonemes) or '(none)'}")
        return 0

    if args.video:
        frames = load_video(args.video.expanduser().resolve())
        last_frame = frames[-1]
    else:
        frames, last_frame = capture_camera(args.camera, args.duration)

    print(f"Captured {len(frames)} video frames. Running VALLR locally...")
    started = time.monotonic()
    phonemes, device, detected_frames, shape = infer_phonemes(frames, args.model, args.device)
    print(f"Inference device: {device}; output: {shape}; elapsed: {time.monotonic() - started:.2f}s")
    print(f"Face available in {detected_frames}/{FRAME_COUNT} sampled frames")
    print("Raw phonemes:", " ".join(phonemes) or "(none)")

    transcript = ""
    use_ollama = args.llm == "ollama" or (
        args.llm == "auto" and ollama_is_available(args.ollama_model)
    )
    if use_ollama:
        try:
            print(f"Reconstructing English locally with Ollama {args.ollama_model}...")
            transcript = reconstruct_with_ollama(phonemes, args.ollama_model)
            print("English:", transcript or "(none)")
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            print(f"Ollama reconstruction was unavailable: {error}")
    elif args.llm == "ollama":
        print(f"Ollama model {args.ollama_model!r} is not available.")

    if args.json:
        print(json.dumps({
            "schema_version": 1,
            "phonemes": phonemes,
            "transcript": transcript,
            "detected_frames": detected_frames,
            "sampled_frames": FRAME_COUNT,
            "device": device,
        }), file=sys.__stdout__)
    else:
        show_result(last_frame, phonemes, transcript)
    return 0


def main() -> int:
    args = parse_arguments()
    # Keep model diagnostics away from the machine-readable stdout protocol.
    with contextlib.redirect_stdout(sys.stderr if args.json else sys.stdout):
        return run(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Cancelled.", file=sys.stderr)
        raise SystemExit(130)
    except PrototypeError as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(2)
