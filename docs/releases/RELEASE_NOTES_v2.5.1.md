# Echo One v2.5.1

## New
- **Qwen 3.5 2B is the default cleanup and summary model.** In testing on real dictations, Qwen 3.5 0.8B left most text unchanged and wrote broken meeting summaries (copied headings, repeated bullets). 2B removes filler words and writes real summaries. Existing installs keep the model they already selected; pick Qwen 3.5 2B in Settings → Cleanup model. Summaries use 2B whenever it's downloaded.
- **Meeting summaries switch.** Settings → Meeting Transcription → Meeting summaries (on by default). Turning it off hides the Summary tab.
- **Quit Echo One** at the bottom of the Settings sidebar (⌘Q).

## Changes
- The cleanup model now leaves memory as soon as a meeting summary is written. Before, it stayed loaded (about 1.2 GB) until the app quit. With cleanup off, Echo One idles at about 100 MB.
- Signed with Developer ID and notarized by Apple.

## Notes
- Apple Silicon (M1+), macOS 14.0+.
- Everything still runs on-device by default — see `PRIVACY_AUDIT.md`.
