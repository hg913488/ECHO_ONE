# Transcription Lab Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Settings-based Transcription Lab that archives the last 50 non-empty recordings and lets users rerun them with different speech models, cleanup models, and cleanup prompt text using the original OCR context and without pasting.

**Architecture:** Build a small archive store plus a rerun runner on top of the current `codex/qwen35-integration` seams: `AudioRecorder`, `SpeechTranscriber`, `TextCleaner`, `TextCleanupManager`, and the existing sidebar Settings shell. Use a shared pipeline lock in `AppState` so lab reruns and live dictation cannot overlap.

**Tech Stack:** Swift, SwiftUI, AppKit-hosted settings shell, AVFoundation, WhisperKit, FluidAudio, LLM.swift, XCTest

---

## Chunk 1: Archive Foundation

### Task 1: Add archive entry model and store

**Files:**
- Create: `EchoOne/Lab/TranscriptionLabEntry.swift`
- Create: `EchoOne/Lab/TranscriptionLabStore.swift`
- Test: `EchoOneTests/TranscriptionLabStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests covering:
- entry encode/decode with optional OCR/raw/final text fields
- newest-first ordering
- prune at 51 entries
- audio file deletion when pruning
- clean load from empty storage

- [ ] **Step 2: Run the targeted tests to verify failure**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-tests -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:EchoOneTests/TranscriptionLabStoreTests test`

Expected: FAIL because the archive entry and store do not exist.

- [ ] **Step 3: Write the minimal implementation**

Implement:
- Codable entry model
- JSON index load/save
- capped insert with prune
- audio-file delete on prune

- [ ] **Step 4: Re-run the targeted tests**

Run the same command and expect all store tests to pass.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Lab/TranscriptionLabEntry.swift EchoOne/Lab/TranscriptionLabStore.swift EchoOneTests/TranscriptionLabStoreTests.swift
git commit -m "Add transcription lab archive store"
```

## Chunk 2: Audio Serialization and Live Archival

### Task 2: Add audio serialization helpers

**Files:**
- Modify: `EchoOne/Audio/AudioRecorder.swift`
- Test: `EchoOneTests/AudioRecorderTests.swift`

- [ ] **Step 1: Write the failing test**

Add a round-trip test for converting `[Float]` audio samples to persisted data and back.

- [ ] **Step 2: Run the targeted test to verify failure**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-tests -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:EchoOneTests/AudioRecorderTests test`

Expected: FAIL because no persistence helper exists.

- [ ] **Step 3: Write the minimal implementation**

Add module-internal helpers for serializing and deserializing audio buffers for the archive store.

- [ ] **Step 4: Re-run the targeted tests**

Expect the new audio test to pass.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Audio/AudioRecorder.swift EchoOneTests/AudioRecorderTests.swift
git commit -m "Add audio serialization for transcription lab"
```

### Task 3: Archive live runs from AppState

**Files:**
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOne/Cleanup/TextCleaner.swift`
- Modify: `EchoOne/Lab/TranscriptionLabStore.swift`
- Test: `EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests that verify:
- a live run with non-empty audio archives an entry
- archived entry stores original OCR context when present
- archived entry stores raw and corrected output when present
- a non-empty audio run still archives when speech transcription returns nil
- empty-audio cancellation does not archive

- [ ] **Step 2: Run the targeted tests to verify failure**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-tests -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:EchoOneTests/EchoOneTests test`

Expected: FAIL because AppState does not archive runs.

- [ ] **Step 3: Write the minimal implementation**

Modify the live pipeline to:
- capture the same OCR context already used by cleanup
- persist an archive entry after a non-empty recording completes
- archive even when live transcription failed, with optional text fields
- leave paste behavior unchanged

- [ ] **Step 4: Re-run the targeted tests**

Expect the new archive-behavior tests to pass.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/AppState.swift EchoOne/Cleanup/TextCleaner.swift EchoOneTests/EchoOneTests.swift
git commit -m "Archive live recordings for transcription lab"
```

## Chunk 3: Explicit Experiment Controls

### Task 4: Add explicit cleanup-model selection for reruns

**Files:**
- Modify: `EchoOne/Cleanup/TextCleaner.swift`
- Modify: `EchoOne/Cleanup/TextCleanupManager.swift`
- Test: `EchoOneTests/TextCleanerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests verifying lab cleanup can:
- force fast model
- force full model
- use explicit OCR context through `CleanupPromptBuilder`
- report fallback vs real model execution through `TextCleanerResult.performance`

- [ ] **Step 2: Run the targeted tests to verify failure**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-tests -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:EchoOneTests/TextCleanerTests test`

Expected: FAIL because the cleaner does not expose a lab rerun path with explicit model choice.

- [ ] **Step 3: Write the minimal implementation**

Add a lab-specific cleaning call that accepts:
- explicit cleanup model kind
- explicit OCR context
- explicit prompt text

Do not disturb the existing live cleanup path.

- [ ] **Step 4: Re-run the targeted tests**

Expect all cleaner tests to pass.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Cleanup/TextCleaner.swift EchoOne/Cleanup/TextCleanupManager.swift EchoOneTests/TextCleanerTests.swift
git commit -m "Add explicit cleanup controls for transcription lab"
```

### Task 5: Add shared pipeline lock and lab runner

**Files:**
- Create: `EchoOne/Lab/TranscriptionLabRunner.swift`
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOne/Transcription/ModelManager.swift`
- Test: `EchoOneTests/TranscriptionLabRunnerTests.swift`
- Test: `EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests verifying:
- lab rerun retranscribes from archived audio
- lab rerun reuses archived OCR context
- lab rerun respects chosen speech model
- lab rerun never invokes paste
- lab rerun blocks a new live recording start while in flight
- live work blocks a lab rerun if recording/transcription already owns the pipeline

- [ ] **Step 2: Run the targeted tests to verify failure**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-tests -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:EchoOneTests/TranscriptionLabRunnerTests -only-testing:EchoOneTests/EchoOneTests test`

Expected: FAIL because the runner and pipeline lock do not exist.

- [ ] **Step 3: Write the minimal implementation**

Implement:
- a shared AppState-owned pipeline lock
- lab rerun runner that loads archived audio, switches speech model, retranscribes, and runs cleanup
- explicit busy-state result for the UI

- [ ] **Step 4: Re-run the targeted tests**

Expect the rerun and lock tests to pass.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Lab/TranscriptionLabRunner.swift EchoOne/AppState.swift EchoOne/Transcription/ModelManager.swift EchoOneTests/TranscriptionLabRunnerTests.swift EchoOneTests/EchoOneTests.swift
git commit -m "Add transcription lab rerun pipeline"
```

## Chunk 4: Settings UI

### Task 6: Add Transcription Lab section to Settings

**Files:**
- Create: `EchoOne/UI/TranscriptionLabView.swift`
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Test: `EchoOneTests/TranscriptionLabViewTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests for:
- archive list displays newest-first entries
- selected entry populates original raw/corrected content
- changing prompt updates the shared `cleanupPrompt`
- rerun result populates experiment raw/corrected output
- fallback state is visible when cleanup model did not actually run

- [ ] **Step 2: Run the targeted tests to verify failure**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-tests -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:EchoOneTests/TranscriptionLabViewTests test`

Expected: FAIL because the lab view and settings section do not exist.

- [ ] **Step 3: Write the minimal implementation**

Add:
- new sidebar section `Transcription Lab`
- archive list
- original panel
- experiment controls
- experiment results
- inline prompt editor bound to `AppState.cleanupPrompt`

Do not remove the existing separate prompt-editor window in this feature.

- [ ] **Step 4: Re-run the targeted tests**

Expect the lab view tests to pass.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/UI/TranscriptionLabView.swift EchoOne/UI/SettingsWindow.swift EchoOneTests/TranscriptionLabViewTests.swift
git commit -m "Add transcription lab settings UI"
```

## Chunk 5: Full Verification

### Task 7: Run full verification and fix fallout

**Files:**
- Modify: only files needed for actual fallout

- [ ] **Step 1: Run the full suite**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/transcription-lab-full -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`

Expected: PASS.

- [ ] **Step 2: Fix the smallest real failures**

If failures appear, fix root causes only.

- [ ] **Step 3: Re-run the full suite**

Run the same command again and confirm it passes cleanly.

- [ ] **Step 4: Build a signed local app for live validation**

Run:

```bash
xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/transcription-lab-signed -skipMacroValidation CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Developer ID Application: Jesse Vincent (87WJ58S66M)' DEVELOPMENT_TEAM=87WJ58S66M build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit final fallout fixes**

```bash
git add <touched files>
git commit -m "Polish transcription lab integration"
```
