# FluidAudio Diarization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Ignore other speakers` recording preference that uses `FluidAudio` diarization to keep the first substantial speaker in stop-and-paste dictation, while remaining visible but disabled for `WhisperKit` models and surfacing diarization decisions only in the Transcription Lab.

**Architecture:** Keep the existing speech-backend split and build the smallest new seam set needed for V1. Add one `FluidAudio`-only recording session helper that consumes chunked converted audio, produces a final `DiarizationSummary`, extracts filtered audio for ASR, and falls back cleanly to the existing full-audio path; then archive that final summary for lab visualization.

**Tech Stack:** Swift, SwiftUI, AVFoundation, FluidAudio, WhisperKit, XCTest, xcodebuild

---

## File Structure

**Modify:**
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift`
  - Persist the new setting, gate live recording behavior by backend, route eligible recordings through the diarization session, and archive final diarization metadata.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Audio/AudioRecorder.swift`
  - Expose logical chunk delivery from the existing converted 16 kHz mono Float32 stream without changing the final-buffer behavior.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/SpeechModelCatalog.swift`
  - Mark which speech models support speaker filtering and provide picker-level capability checks.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/ModelManager.swift`
  - Expose enough `FluidAudio` access for one recording-scoped diarization/transcription session while leaving WhisperKit on the existing path.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabEntry.swift`
  - Extend the archive schema to include finalized diarization metadata.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabStore.swift`
  - Persist and load diarization summaries alongside existing lab entries and timings.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabController.swift`
  - Expose archived diarization summaries to the lab UI.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift`
  - Add the visible-but-disabled toggle in Recording and render the lab’s diarization timeline/kept-span visualization.
**Create:**
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/FluidAudioSpeechSession.swift`
  - Recording-scoped `FluidAudio` helper that accepts converted chunks, finalizes target-speaker spans, extracts filtered audio, and transcribes it.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/RecordingSessionCoordinator.swift`
  - Thin lifecycle owner that glues `AudioRecorder` chunk delivery to `FluidAudioSpeechSession`.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/DiarizationSummary.swift`
  - Final archived speaker-attribution result for one completed recording.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/FluidAudioSpeechSessionTests.swift`
  - Unit coverage for first-substantial-speaker selection, span merging, and measurable fallback rules.
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/RecordingSessionCoordinatorTests.swift`
  - Unit coverage for chunk accumulation, stop-time finalization, and fallback handoff.

**Test:**
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/AudioRecorderTests.swift`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/SpeechTranscriberTests.swift`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/TranscriptionLabStoreTests.swift`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/TranscriptionLabControllerTests.swift`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/FluidAudioSpeechSessionTests.swift`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/RecordingSessionCoordinatorTests.swift`

---

## Chunk 1: Settings, Capability, And Archive Plumbing

### Task 1: Add failing tests for backend capability and the disabled Recording toggle

**Files:**
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/SpeechModelCatalog.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/SpeechTranscriberTests.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests that prove:
- only `FluidAudio` speech models report speaker-filtering support
- `AppState` persists an `ignoreOtherSpeakers` preference
- the Recording settings presentation helper keeps the toggle visible for all models
- the same helper enables the toggle for `fluid_parakeet-v3`
- the same helper disables the toggle for `openai_whisper-small.en`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-capability-red -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-capability-red-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/SpeechTranscriberTests/testFluidAudioSpeechModelsSupportSpeakerFiltering -only-testing:EchoOneTests/EchoOneTests/testAppStatePersistsIgnoreOtherSpeakersPreference -only-testing:EchoOneTests/EchoOneTests/testRecordingSettingsDisablesIgnoreOtherSpeakersForWhisperModels test
```

Expected:
- the new tests fail because the capability metadata and setting do not exist yet

- [ ] **Step 3: Implement the minimal capability and setting plumbing**

In:
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/SpeechModelCatalog.swift`
  - add a `supportsSpeakerFiltering` property derived from backend
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift`
  - add persisted `ignoreOtherSpeakers`
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift`
  - add a tiny presentation helper for the toggle state, then render the visible toggle in Recording and disable it when the selected speech model does not support speaker filtering

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run the command from Step 2.

Expected:
- all targeted tests pass

- [ ] **Step 5: Commit**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/SpeechModelCatalog.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/SpeechTranscriberTests.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Add speaker filtering setting"
```

---

## Chunk 2: Recorder And FluidAudio Session Core

### Task 3: Add a failing recorder test for chunk delivery from the existing converted stream

**Files:**
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Audio/AudioRecorder.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/AudioRecorderTests.swift`

- [ ] **Step 1: Write the failing test**

Add a small recorder seam and tests that prove:
- converted Float32 samples can be delivered incrementally to a callback
- the same converted samples still accumulate into the final `audioBuffer`
- no second capture path is introduced

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-recorder-red -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-recorder-red-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/AudioRecorderTests/testConvertedSamplesAreDeliveredToChunkCallback -only-testing:EchoOneTests/AudioRecorderTests/testChunkDeliveryStillAccumulatesFinalAudioBuffer test
```

Expected:
- the new tests fail because `AudioRecorder` has no chunk callback

- [ ] **Step 3: Implement the minimal chunk-delivery seam**

In `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Audio/AudioRecorder.swift`:
- add an optional callback for converted samples
- invoke it from the existing `convert(buffer:using:)` path
- keep `stopRecording()` and `audioBuffer` semantics unchanged

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run the command from Step 2.

Expected:
- both tests pass

- [ ] **Step 5: Commit**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Audio/AudioRecorder.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/AudioRecorderTests.swift
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Expose converted audio chunks"
```

### Task 4: Add failing tests for `FluidAudioSpeechSession` target-speaker and fallback rules

**Files:**
- Create: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/FluidAudioSpeechSession.swift`
- Create: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/RecordingSessionCoordinator.swift`
- Create: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/DiarizationSummary.swift`
- Create: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/FluidAudioSpeechSessionTests.swift`
- Create: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/RecordingSessionCoordinatorTests.swift`

- [ ] **Step 1: Write the failing unit tests**

Add tests that prove:
- the earliest speaker whose cumulative voiced spans reach `0.5s` becomes the target
- the session keeps later spans for that speaker and discards others
- nearby kept spans merge with a small gap tolerance
- the session falls back when no speaker reaches threshold
- the session falls back when kept audio totals less than `0.75s`
- the session falls back when filtered ASR returns an empty result
- the coordinator collects chunks and returns the final `DiarizationSummary`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-session-red -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-session-red-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/FluidAudioSpeechSessionTests -only-testing:EchoOneTests/RecordingSessionCoordinatorTests test
```

Expected:
- the new tests fail because the session and coordinator do not exist yet

- [ ] **Step 3: Implement the minimal `FluidAudio` session core**

In:
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/DiarizationSummary.swift`
  - add the final span and summary types driven by the session rules above
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/FluidAudioSpeechSession.swift`
  - add the smallest testable surface for chunk ingestion, finalized span selection, filtered-audio extraction, and ASR fallback
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/RecordingSessionCoordinator.swift`
  - add a thin owner around one live session, not a general-purpose transcript engine

Keep test seams closure- or protocol-based inside these files rather than pushing speculative abstractions into unrelated types.

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run the command from Step 2.

Expected:
- all targeted tests pass

- [ ] **Step 5: Commit**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/DiarizationSummary.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/FluidAudioSpeechSession.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/RecordingSessionCoordinator.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/FluidAudioSpeechSessionTests.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/RecordingSessionCoordinatorTests.swift
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Add FluidAudio speaker filtering session"
```

### Task 5: Add failing archive tests for finalized diarization metadata

**Files:**
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabEntry.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabStore.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/TranscriptionLabStoreTests.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing archive tests**

Add tests that prove:
- `TranscriptionLabEntry` round-trips a final `DiarizationSummary`
- `TranscriptionLabStore` persists archived diarization summaries
- `AppState.archiveRecordingForLab(...)` can store `speakerFilteringEnabled`, `speakerFilteringRan`, `speakerFilteringUsedFallback`, and finalized kept/discarded spans

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-archive-red -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-archive-red-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/TranscriptionLabStoreTests/testTranscriptionLabEntryRoundTripsDiarizationSummary -only-testing:EchoOneTests/TranscriptionLabStoreTests/testTranscriptionLabStorePersistsDiarizationSummary -only-testing:EchoOneTests/EchoOneTests/testAppStateArchivesRecordingWithDiarizationSummary test
```

Expected:
- the new tests fail because the archive schema does not store the finalized summary yet

- [ ] **Step 3: Implement the minimal archive schema**

In:
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabEntry.swift`
  - add optional archived diarization summary fields
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabStore.swift`
  - persist and load the new fields without changing retention behavior

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run the command from Step 2.

Expected:
- all targeted tests pass

- [ ] **Step 5: Commit**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabEntry.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabStore.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/TranscriptionLabStoreTests.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Archive diarization summaries"
```

---

## Chunk 3: Live App Integration

### Task 5: Add failing integration tests for backend-specific routing and archive behavior

**Files:**
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/ModelManager.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing integration tests**

Add tests that prove:
- `WhisperKit` recordings ignore `ignoreOtherSpeakers` and use the current full-audio path
- `FluidAudio` recordings with `ignoreOtherSpeakers` enabled route through `RecordingSessionCoordinator`
- live archive writes include the final `DiarizationSummary`
- live fallback to full-audio transcription is recorded in the archived summary
- cleanup still runs exactly once on the finalized raw transcript

If the current `AppState` surface is too private, first add the smallest internal helper needed to make the path testable before changing behavior.

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-appstate-red -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-appstate-red-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/EchoOneTests/testWhisperRecordingIgnoresSpeakerFilteringSetting -only-testing:EchoOneTests/EchoOneTests/testFluidAudioRecordingUsesSpeakerFilteringSession -only-testing:EchoOneTests/EchoOneTests/testAppStateArchivesDiarizationFallbackState test
```

Expected:
- the new tests fail because the live path does not route through speaker filtering yet

- [ ] **Step 3: Implement the minimal live integration**

In:
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/ModelManager.swift`
  - expose only the `FluidAudio` access the new session helper needs
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift`
  - create a coordinator only for eligible `FluidAudio` recordings
  - feed recorder chunks into it
  - on stop, choose between filtered-audio transcription and the existing full-audio path based on the session result
  - archive the final `DiarizationSummary`

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run the command from Step 2.

Expected:
- all targeted tests pass

- [ ] **Step 5: Commit**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/AppState.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Transcription/ModelManager.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/EchoOneTests.swift
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Route FluidAudio recordings through speaker filtering"
```

---

## Chunk 4: Lab Visualization And Final Verification

### Task 6: Add failing lab tests for diarization visualization and archived summary display

**Files:**
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabController.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift`
- Modify: `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/TranscriptionLabControllerTests.swift`

- [ ] **Step 1: Write the failing lab tests**

Add tests that prove:
- the controller exposes archived diarized spans and kept/discarded state
- the lab only shows diarization visualization when the entry contains archived diarization metadata

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-lab-red -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-lab-red-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/TranscriptionLabControllerTests test
```

Expected:
- the new tests fail because the controller and UI do not expose diarization metadata yet

- [ ] **Step 3: Implement the minimal lab visualization**

In:
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabController.swift`
  - expose view-ready diarization summary data
- `/Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift`
  - render a compact kept/discarded span visualization only for entries that contain archived summary data
  - do not add new production UI outside the lab

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run the command from Step 2.

Expected:
- all targeted tests pass

- [ ] **Step 5: Commit**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/Lab/TranscriptionLabController.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne/UI/SettingsWindow.swift /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests/TranscriptionLabControllerTests.swift
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Show diarization decisions in transcription lab"
```

### Task 7: Run end-to-end verification

**Files:**
- Verify only

- [ ] **Step 1: Run the focused diarization suite**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-focused-green -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-focused-green-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:EchoOneTests/AudioRecorderTests -only-testing:EchoOneTests/FluidAudioSpeechSessionTests -only-testing:EchoOneTests/RecordingSessionCoordinatorTests -only-testing:EchoOneTests/TranscriptionLabStoreTests -only-testing:EchoOneTests/TranscriptionLabControllerTests -only-testing:EchoOneTests/EchoOneTests test
```

Expected:
- all focused diarization-related tests pass

- [ ] **Step 2: Run the full suite**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-full-green -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-full-green-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation test
```

Expected:
- the full Echo One test suite passes

- [ ] **Step 3: Build the app from a clean derived-data path**

Run:
```sh
xcodebuild -project /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-build-green -clonedSourcePackagesDirPath /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/build/diarization-build-green-source CODE_SIGNING_ALLOWED=NO -skipMacroValidation build
```

Expected:
- clean repo-local build succeeds

- [ ] **Step 4: Commit the final implementation**

```sh
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline status --short
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline add /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOne /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline/EchoOneTests
git -C /Users/jesse/.config/superpowers/worktrees/echo-one/codex-transcription-lab-mainline commit -m "Add FluidAudio speaker filtering"
```
