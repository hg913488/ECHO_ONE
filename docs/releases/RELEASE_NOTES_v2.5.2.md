# Echo One v2.5.2

## Fixes
- **Deleting a Whisper model now frees its space.** Settings removed only the model's small tokenizer folder and left the model itself (about 466 MB for small.en) on disk. If you deleted a Whisper model before, the leftover is in `~/Library/Application Support/EchoOne/whisper-models/models/argmaxinc/whisperkit-coreml/`.

## Notes
- Apple Silicon (M1+), macOS 14.0+.
- Signed with Developer ID and notarized by Apple.
- Everything still runs on-device by default — see `PRIVACY_AUDIT.md`.
