import unittest
from unittest.mock import patch, MagicMock
from pathlib import Path

import numpy as np

from vallr_prototype import collapse_ctc, sample_evenly, square_face_crop, load_video, PrototypeError


class PrototypeUtilitiesTests(unittest.TestCase):
    def test_import_rejects_overlong_clips_and_releases_capture(self):
        capture = MagicMock()
        capture.isOpened.return_value = True
        capture.get.return_value = 1.0
        capture.read.return_value = (True, np.zeros((4, 4, 3), dtype=np.uint8))
        with patch("vallr_prototype.cv2.VideoCapture", return_value=capture):
            with self.assertRaisesRegex(PrototypeError, "at most 10 seconds"):
                load_video(Path("test.mp4"))
        capture.release.assert_called_once()

    def test_import_rejects_invalid_frame_rate(self):
        capture = MagicMock()
        capture.isOpened.return_value = True
        capture.get.return_value = float("nan")
        with patch("vallr_prototype.cv2.VideoCapture", return_value=capture):
            with self.assertRaisesRegex(PrototypeError, "invalid frame rate"):
                load_video(Path("test.mp4"))
        capture.release.assert_called_once()

    def test_ctc_collapse_removes_repeats_and_blanks(self):
        self.assertEqual(collapse_ctc([0, 16, 16, 0, 18, 18, 0]), ["HH", "IY"])

    def test_even_sampling_uses_both_ends(self):
        frames = [np.full((1, 1, 3), index, dtype=np.uint8) for index in range(32)]
        sampled = sample_evenly(frames, count=16)
        self.assertEqual(int(sampled[0][0, 0, 0]), 0)
        self.assertEqual(int(sampled[-1][0, 0, 0]), 31)
        self.assertEqual(len(sampled), 16)

    def test_face_crop_has_model_dimensions(self):
        frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        crop = square_face_crop(frame, (440, 160, 400, 400))
        self.assertEqual(crop.shape, (224, 224, 3))


if __name__ == "__main__":
    unittest.main()
