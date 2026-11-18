# Changelog

Every Echo One release. Apple Silicon (M1+), macOS 14.0+, signed with Developer ID and notarized by Apple.

## 2.6.0 (2026-11-17)

### New
- **Voice Agent.** Hold Right Command + Right Shift and talk to the Claude Code or Codex already signed in on your Mac. It answers out loud with an on-device voice, and starts talking while it is still writing. Four access levels, from Ask only to Full.
- **Codex.** Settings → Voice Agent → Agent → Talks to: Claude Code or Codex.
- **Echo Actions.** Say "dark mode", "battery" or "timer 5 minutes" and a script runs straight away, with no AI. Over 30 built in, plus your own scripts in the Raycast script command format. See [ECHO-ACTIONS.md](ECHO-ACTIONS.md).
- **Settings in two tabs,** Dictation and Voice Agent, with more on screen and less scrolling. Donate and Star on GitHub at the bottom.

### Changed
- **One speech model:** Parakeet Ultra, 25 European languages. Whisper and Parakeet v3 are gone.

### Safety
- The Voice Agent is told never to delete: anything it removes should go to the Trash, where Put Back restores it. For Claude Code, delete commands, force-pushes and hard resets are blocked outright.
- It's told to ask out loud before anything that leaves your Mac (sending, pushing, publishing, buying) and never to read a password or key aloud. AI doesn't always follow instructions, so keep backups.
- Your own Echo Actions ask once before their first run, and again after you edit them.
- Say "stop", press Esc or click the reply card to stop it.
- The first time you use the Voice Agent, it shows what it can do on your Mac and asks you to agree to the [terms of use](https://echooneapp.vercel.app/terms/).

### Fixes
- Recordings no longer come out empty when AirPods connect or switch mode while you are talking.

## 2.5.2

### Fixes
- **Deleting a Whisper model now frees its space.** Settings removed only the model's small tokenizer folder and left the model itself (about 466 MB for small.en) on disk. If you deleted a Whisper model before, the leftover is in `~/Library/Application Support/EchoOne/whisper-models/models/argmaxinc/whisperkit-coreml/`.

## 2.5.1

### New
- **Qwen 3.5 2B is the default cleanup and summary model.** In testing on real dictations, Qwen 3.5 0.8B left most text unchanged and wrote broken meeting summaries (copied headings, repeated bullets). 2B removes filler words and writes real summaries. Existing installs keep the model they already selected; pick Qwen 3.5 2B in Settings → Cleanup model. Summaries use 2B whenever it's downloaded.
- **Meeting summaries switch.** Settings → Meeting Transcription → Meeting summaries (on by default). Turning it off hides the Summary tab.
- **Quit Echo One** at the bottom of the Settings sidebar (⌘Q).

### Changes
- The cleanup model now leaves memory as soon as a meeting summary is written. Before, it stayed loaded (about 1.2 GB) until the app quit. With cleanup off, Echo One idles at about 100 MB.
- Signed with Developer ID and notarized by Apple.

## 2.5.0

### New
- **Parakeet Ultra speech model, now the default.** A more accurate drop-in successor to Parakeet v3 (same 25 languages, same speed, ~630 MB). Existing installs keep the model they already selected; pick Ultra in Settings → Speech model.
- **Custom vocabulary.** Words and names listed under Settings → Correction hints → Preferred transcriptions now also bias Parakeet speech models toward those spellings (one-time ~97 MB helper download). Whisper models are unaffected.
- **Meeting Summary tab is back.** Summaries failed before because the summary instructions were sent under the dictation clean-up prompt and transcript chunks overflowed small models. Each request is now sized to the model's context window, long meetings are summarised in parts and merged, and the largest downloaded cleanup model is used.

### Changes
- FluidAudio updated from 0.14.5 to 0.17.7.
- **Removed the Qwen3-ASR 0.6B speech model.** FluidAudio dropped that backend. If it was your selected model, Echo One switches to Parakeet Ultra. The Qwen cleanup models are unchanged.
- A slow summary now reports a timeout instead of "model isn't loaded".

## 2.4.0

### Fixes
- **Dictation, chord hotkey, and paste-into-note now work reliably.** Disabling the App Sandbox fixed a CoreML model-load failure that could leave the speech model stuck and the hotkeys unresponsive.
- **Meeting history sidebar:** opening a past transcript no longer makes its row vanish from the sidebar. Entries stay listed (and are highlighted) while open, in both light and dark appearance.
- **Model management:** deleting the Qwen3 ASR model now actually removes the cached files (it was previously a no-op that left the row marked "loaded").

### Changes
- Removed the meeting **Summary** tab. On-device summary generation was unreliable, so it's hidden pending a rework. Notes and Transcript are unchanged.
