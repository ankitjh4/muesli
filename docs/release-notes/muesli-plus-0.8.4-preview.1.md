# Muesli+ 0.8.4 — Preview 1

First public Muesli+ preview, based on upstream Muesli 0.8.4. This release ships
the tested Apple Silicon **debug build**, with bundle version 0.8.4. It is
ad-hoc signed and **not notarized**. This is not a production-ready release.

## Available in this preview

- Native Hindi-English code-switching with Romanized output: Bodhan Flex recognition followed by local Hindi-span romanization, plus a direct Romanized Hinglish model option. This preserves the language rather than translating Hindi into English; names and numbers need review.
- Online models through OpenRouter for dictation, meetings, and text processing, with dynamic model catalogs. API keys, provider availability, and charges apply. Offline mode uses downloaded local speech and text models.
- Light-first setup, six optional themes, custom status icons, and a white drag-to-Applications installer.
- Personal dictionary, vocabulary suggestions, and optional correction learning.
- Optional app context and on-device screen OCR. Relevant context can be sent to a hosted text model when that mode is selected. No always-on website monitoring is included.
- Menu-bar word count with integer k/m/b/T abbreviations.
- Model-based spelling/grammar cleanup, repetition removal, spoken self-corrections, and list formatting. Enabled by default during fresh setup, dependent on model readiness; **still optional, not mandatory** in this installer.
- Hotkey listeners are recreated when keyboard permissions change, with clearer instructions for stale Accessibility grants after development rebuilds.

## Experimental: silent dictation

English lip-only camera/video input is integrated into the native interface;
Python is not required at runtime. Recognition quality is currently poor and
unreliable. The visual model is **not included in this DMG**, and the hosted model
download is not configured, so a fresh install cannot use it out of the box.
The separately prepared VALLR model has noncommercial terms. Do not rely on
silent dictation for important communication.

## Roadmap / WIP — not shipped as completed capabilities

- Always-listening mode with explicit consent and recording controls.
- Better silent dictation and model delivery.
- Opt-in pre-emptive note-taking from noteworthy browsed material.
- Remote microphones, such as an iPhone in another room. This preview remains a macOS app, not a Windows release.
- Mandatory cleanup, including offline readiness and safe failure behavior.

## Install and permissions

1. Download `Muesli+-0.8.4.dmg`, open it, and drag Muesli+ into Applications.
2. Open the installed copy and follow setup to select/download models.
3. Grant Microphone, Accessibility, and Input Monitoring. Quit and reopen after granting access.
4. Hold **Right Option** to speak, then release to finish. A quick single tap is not hold-to-talk.

If permission is switched on but not recognized, remove the old Muesli entry
from the relevant System Settings privacy list, add the installed copy from
Applications, enable it, and restart the app. Ad-hoc rebuilds can invalidate
previous grants. Do not globally disable Gatekeeper; if macOS blocks this
preview, use its per-app **Open Anyway** flow only if you trust the download.

## Validation and limitations

- Native app build, deep signature validation, disk-image checksum, and visual installer check passed locally.
- 44 focused permission/hotkey tests passed. Physical-key dictation after granting macOS permissions still requires an end-user check.
- App Intents metadata is included, but system Apple Shortcuts execution is not verified for this ad-hoc build.
- Automated tests do not establish real-person lip-reading accuracy or paid-provider transcription quality.
- Downloadable speech/text models are separate from the installer. No personal settings, transcripts, API keys, or experimental model weights are intentionally packaged.
- The historical upstream appcast is unchanged; this GitHub release does not enable automatic in-app updates.

SHA-256 of `Muesli+-0.8.4.dmg`:

```text
7e0728270c7da0a26563e489b6728c8ff3695736256744daa7d13177efec11d2
```
