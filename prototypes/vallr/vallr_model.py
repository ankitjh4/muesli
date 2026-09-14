# SPDX-License-Identifier: CC-BY-NC-4.0
"""Minimal VALLR V1 architecture needed by the public visual checkpoint.

Adapted from Models/VALLR.py in the official VALLR research repository:
https://github.com/MarshallT-99/VALLR
Authors: Marshall Thomas, Edward Fish, and Richard Bowden (2025).
Reviewed revision: 9793489136bc00293242a5410def05ba2806e16f.
See NOTICE.md for attribution, changes, and full license links.

VALLR is licensed CC BY-NC 4.0. This prototype is for local, non-commercial
evaluation only.
"""

from __future__ import annotations

import torch
from torch import nn
from torch.nn import init
from transformers import VideoMAEConfig, VideoMAEModel, Wav2Vec2Config, Wav2Vec2ForCTC


class VALLR(nn.Module):
    """VideoMAE visual encoder, temporal adapter, and phoneme CTC head."""

    def __init__(
        self,
        videomae_config: VideoMAEConfig,
        wav2vec_config: Wav2Vec2Config,
        adapter_dim: int = 256,
    ) -> None:
        super().__init__()
        self.videomae = VideoMAEModel(videomae_config)

        feature_size = videomae_config.hidden_size
        self.downsampling = nn.Sequential(
            nn.Conv1d(feature_size, adapter_dim, kernel_size=5, stride=2, padding=2),
            nn.BatchNorm1d(adapter_dim, eps=1e-5, momentum=0.1, affine=True),
            nn.ReLU(),
            nn.Conv1d(adapter_dim, adapter_dim, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm1d(adapter_dim, eps=1e-5, momentum=0.1, affine=True),
            nn.ReLU(),
            nn.Conv1d(adapter_dim, adapter_dim, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm1d(adapter_dim, eps=1e-5, momentum=0.1, affine=True),
            nn.ReLU(),
            nn.Conv1d(adapter_dim, adapter_dim, kernel_size=3, stride=3, padding=1),
            nn.BatchNorm1d(adapter_dim, eps=1e-5, momentum=0.1, affine=True),
            nn.ReLU(),
            nn.AvgPool1d(kernel_size=5, stride=8),
        )

        self.adapter = nn.Sequential(
            nn.Linear(adapter_dim, wav2vec_config.hidden_size),
            nn.ReLU(),
        )

        # The public checkpoint includes this complete module even though only
        # its classification head participates in the forward pass.
        self.wav2vec2 = Wav2Vec2ForCTC(wav2vec_config)
        self.ctc_head = self.wav2vec2.lm_head

        for parameter in self.wav2vec2.parameters():
            parameter.requires_grad = False
        for parameter in self.ctc_head.parameters():
            parameter.requires_grad = True

        self.apply(self._initialize_weights)

    @staticmethod
    def _initialize_weights(module: nn.Module) -> None:
        if isinstance(module, nn.Conv1d):
            init.kaiming_normal_(module.weight, nonlinearity="relu")
            if module.bias is not None:
                init.zeros_(module.bias)
        elif isinstance(module, nn.Linear):
            init.kaiming_uniform_(module.weight, nonlinearity="relu")
            if module.bias is not None:
                init.zeros_(module.bias)

    def forward(self, video_inputs: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        video_features = self.videomae(video_inputs).last_hidden_state
        downsampled = self.downsampling(video_features.permute(0, 2, 1))
        adapted = self.adapter(downsampled.permute(0, 2, 1))
        return self.ctc_head(adapted), adapted


def make_vallr_v1(vocabulary_size: int) -> VALLR:
    video_config = VideoMAEConfig()
    audio_config = Wav2Vec2Config()
    audio_config.vocab_size = vocabulary_size
    return VALLR(video_config, audio_config, adapter_dim=256)
