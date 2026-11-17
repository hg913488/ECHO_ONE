# Echo One v2.5.0

## New
- **Parakeet Ultra speech model, now the default.** A more accurate drop-in successor to Parakeet v3 (same 25 languages, same speed, ~630 MB). Existing installs keep the model they already selected; pick Ultra in Settings → Speech model.
- **Custom vocabulary.** Words and names listed under Settings → Correction hints → Preferred transcriptions now also bias Parakeet speech models toward those spellings (one-time ~97 MB helper download). Whisper models are unaffected.
- **Meeting Summary tab is back.** Summaries failed before because the summary instructions were sent under the dictation clean-up prompt and transcript chunks overflowed small models. Each request is now sized to the model's context window, long meetings are summarised in parts and merged, and the largest downloaded cleanup model is used.

## Changes
- FluidAudio updated from 0.14.5 to 0.17.7.
- **Removed the Qwen3-ASR 0.6B speech model.** FluidAudio dropped that backend. If it was your selected model, Echo One switches to Parakeet Ultra. The Qwen cleanup models are unchanged.
- A slow summary now reports a timeout instead of "model isn't loaded".

## Notes
- Apple Silicon (M1+), macOS 14.0+.
- Everything still runs on-device by default — see `PRIVACY_AUDIT.md`.
