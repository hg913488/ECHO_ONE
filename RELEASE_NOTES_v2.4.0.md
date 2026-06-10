# Echo One v2.4.0

## Fixes
- **Dictation, chord hotkey, and paste-into-note now work reliably.** Disabling the App Sandbox fixed a CoreML model-load failure that could leave the speech model stuck and the hotkeys unresponsive.
- **Meeting history sidebar:** opening a past transcript no longer makes its row vanish from the sidebar — entries stay listed (and are highlighted) while open, in both light and dark appearance.
- **Model management:** deleting the Qwen3 ASR model now actually removes the cached files (it was previously a no-op that left the row marked "loaded").

## Changes
- Removed the meeting **Summary** tab. On-device summary generation was unreliable, so it's hidden pending a rework. Notes and Transcript are unchanged.

## Notes
- Apple Silicon (M1+), macOS 14.0+.
- Everything still runs on-device by default — see `PRIVACY_AUDIT.md`.
