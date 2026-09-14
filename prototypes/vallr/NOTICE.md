# VALLR research prototype: attribution and license exception

The adapted architecture in `vallr_model.py` is derived from **VALLR: Visual ASR
Language Model for Lip Reading**, by **Marshall Thomas, Edward Fish, and Richard
Bowden** (2025).

- Original implementation: [Models/VALLR.py at the reviewed revision](https://github.com/MarshallT-99/VALLR/blob/9793489136bc00293242a5410def05ba2806e16f/Models/VALLR.py)
- Revision: `9793489136bc00293242a5410def05ba2806e16f`
- Upstream license statement: [README at that revision](https://github.com/MarshallT-99/VALLR/blob/9793489136bc00293242a5410def05ba2806e16f/README.md)
- License: [Creative Commons Attribution-NonCommercial 4.0 International](https://creativecommons.org/licenses/by-nc/4.0/)
- Full license terms: [CC BY-NC 4.0 legal code](https://creativecommons.org/licenses/by-nc/4.0/legalcode)
- Paper: [arXiv:2503.21408](https://arxiv.org/abs/2503.21408)

Changes in this adaptation: retained only the V1 visual encoder, temporal
adapter, phoneme CTC head, and initialization needed to load the released
checkpoint. Training and upstream language-model integration are not included;
the surrounding prototype supplies bounded video input and an explicit JSON
interface for local evaluation. No endorsement by the original authors is
implied.

**The root MIT license does not relicense this adapted VALLR code or its
checkpoint.** Keep this notice and the upstream attribution with redistributions
of the adaptation. The VALLR research experiment is for non-commercial use under
the linked terms. Commercial use requires separate permission from the relevant
rights holders.

The checkpoint, virtual environment, and test recordings are excluded from Git.
Neither the Python prototype nor the checkpoint is bundled with the native Mac
application. The Python folder is a developer evaluation/export tool, not a
runtime requirement for native lip dictation. The native app uses a separately
prepared CoreML model in its local model cache; public model hosting is pending.
Other dependencies and models retain their own licenses.
