# Security

## Reporting a vulnerability

Open a [GitHub issue](https://github.com/hg913488/echo-one/issues) marked **[Security]**. For sensitive disclosures, email the address in the commit history.

## Privacy guarantees

Echo One is built to keep your data on your machine.

| Surface | Status |
|---|---|
| Speech-to-text | On-device — WhisperKit / FluidAudio / Qwen3-ASR |
| Text cleanup | On-device — Qwen via LLM.swift |
| Audio recording | Local — AVAudioEngine, no streaming |
| Meeting transcription | Local — markdown saved to disk |
| Meeting summaries | On-device LLM |
| Analytics / telemetry | None |
| OAuth tokens | Stored in macOS Keychain |
| Auto-update | Sparkle 2.x with Ed25519 signature verification |

**Optional cloud features (off by default, require your own API key):**
Google Calendar integration, Context Bundler / Zo AI, Trello sync, Granola import.
