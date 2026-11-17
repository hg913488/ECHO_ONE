# Privacy Audit

Echo One claims to be 100% local by default. This file is both the audit prompt and the record of the most recent verification.

## How to verify

Paste the following prompt into Claude Code (or any AI assistant with codebase access) from the repo root:

> Review the Echo One codebase and confirm that all default features run 100% locally with no network calls. Specifically verify:
>
> 1. **Speech-to-text** — transcription runs entirely on-device (WhisperKit, FluidAudio Parakeet). No audio is sent to any server.
> 2. **Text cleanup** — the local Qwen LLM cleans up transcriptions on-device. No text is sent to any API.
> 3. **Audio recording** — mic and system audio capture use AVAudioEngine and ScreenCaptureKit only. No audio is streamed or uploaded.
> 4. **Meeting transcription & summarization** — chunked transcription, markdown storage, and LLM summary generation all happen locally. No meeting content leaves the device.
> 5. **OCR & screen capture** — Vision framework runs on-device. Screenshots are processed locally and never transmitted.
> 6. **File storage** — all meeting notes, transcripts, and summaries are saved as local markdown files. No cloud sync, no remote backup.
> 7. **No analytics or telemetry** — confirm there are no tracking SDKs (Firebase, Mixpanel, Sentry, Amplitude, PostHog, Datadog, Segment, etc.) anywhere in the codebase.
>
> For each item, check the relevant source files and confirm no `URLSession`, `URLRequest`, or HTTP URL strings exist in the core feature code. List any cloud-connected features separately and confirm they are all opt-in (disabled by default, require user-provided API keys).
>
> Output your findings as a checklist with pass/fail for each item.

---

## Most recent audit

**Date:** 2026-04-13
**Auditor:** Claude Code (Opus 4.6)
**Commit:** (run `git rev-parse --short HEAD` to fill in)

### Core features (must be 100% local)

| # | Feature | Files checked | Result |
|---|---------|--------------|--------|
| 1 | Speech-to-text | `SpeechTranscriber.swift`, `ChunkedTranscriptionPipeline.swift` | :white_check_mark: Pass — no network calls. Inference runs via WhisperKit/FluidAudio on-device. |
| 2 | Text cleanup | `MeetingSummaryGenerator.swift`, `TextCleanupManager.swift` (inference path only) | :white_check_mark: Pass — LLM inference via LLM.swift, fully on-device. `TextCleanupManager` has model download code but that is user-initiated, not part of inference. |
| 3 | Audio recording | `Audio/AudioRecorder.swift`, `Audio/SystemAudioRecorder.swift`, `Audio/DualStreamCapture.swift` | :white_check_mark: Pass — AVAudioEngine (mic) and ScreenCaptureKit (system audio). No network calls. |
| 4 | Meeting transcription & storage | `MeetingSession.swift`, `MeetingTranscript.swift`, `MeetingMarkdownWriter.swift`, `MeetingHistory.swift`, `MeetingTranscriptSettings.swift` | :white_check_mark: Pass — all local file I/O. Markdown written to user-chosen directory. |
| 5 | OCR & screen capture | `Input/WindowCaptureService.swift`, Vision framework usage | :white_check_mark: Pass — Apple Vision framework, on-device only. |
| 6 | File storage | `MeetingMarkdownWriter.swift`, `MeetingHistory.swift` | :white_check_mark: Pass — local filesystem only. No iCloud, CloudKit, or remote sync. |
| 7 | No analytics or telemetry | Entire `EchoOne/` directory | :white_check_mark: Pass — no Firebase, Mixpanel, Sentry, Amplitude, PostHog, Datadog, or Segment SDKs found. |

### Cloud-connected features (all opt-in)

These features require explicit user action and API keys. They are **disabled by default**.

| Feature | Trigger | API key required |
|---------|---------|-----------------|
| Zo AI chat | User configures API key in Settings | Yes (`zoApiKey`) |
| Trello integration | User configures API key + token in Settings | Yes (`trelloApiKey`, `trelloToken`) |
| Granola meeting import | User clicks Import and enters API key | Yes (`granolaApiKey`) |
| Model downloads | User selects a model to download | No (public Hugging Face URLs) |
| Sparkle update check | Automatic, checks GitHub appcast.xml 1x/24h | No |

### Voice Agent and Echo Actions (from 2.6)

The Voice Agent talks to a coding agent you already have installed and signed in: Claude Code or Codex. It is off until you use its shortcut. Its source isn't public, so this section describes what it sends rather than an audit you can rerun.

| What | Where it goes |
|------|---------------|
| Your voice | Transcribed on-device, like dictation. The audio never leaves the Mac. |
| The spoken reply | Spoken on-device. |
| The text of your command | Your own Claude Code or Codex, under your own account, to Anthropic or OpenAI. Echo One has no server and no account of its own. |
| Files the agent reads | The agent reads files in the folder you choose and sends what it reads to its provider as part of the conversation, the same as using it in Terminal. Ask only and Sandbox limit what it can reach. |
| Transcripts | Markdown files in `~/Documents/Echo One Agent/`. Local only. |

Echo Actions run local scripts and send nothing anywhere by themselves. A script can, if it's written to: the built-in Search Google and Search YouTube actions open a search in your browser, and Speed Test uses Apple's `networkQuality` servers. The runner is `EchoOne/Agent/EchoActions.swift`.

### Verdict

:white_check_mark: **All default features run 100% locally. No user data leaves the device unless the user explicitly configures a cloud integration.**
