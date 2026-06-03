# Transcription Lab Design

## Goal

Add a user-facing `Transcription Lab` section to Settings that keeps the last 50 completed recordings with non-empty audio and lets users rerun those recordings with different speech models, cleanup models, and cleanup prompt text without pasting into another app.

## Why

Echo One now has enough moving parts that users need a safe place to understand what each stage is doing:

- what the speech engine heard
- what cleanup changed
- how OCR context affects cleanup
- how different speech and cleanup models behave on real recordings

The lab should turn recent real dictation runs into reusable fixtures instead of forcing users to test by pasting into live apps.

## Scope

In scope:

- persist the 50 most recent completed recordings with non-empty audio
- store the original audio plus the original OCR/window context captured for that recording
- store the original raw transcription and original corrected transcription when available
- add a top-level `Transcription Lab` section in Settings
- let the user select any archived recording and compare:
  - original raw transcription
  - original corrected transcription
  - one experimental rerun raw transcription
  - one experimental rerun corrected transcription
- rerun from saved audio every time
- reuse the original captured OCR context during cleanup reruns
- let users switch speech model and cleanup model explicitly
- let users edit the shared cleanup prompt inline with normal macOS undo behavior
- never paste from the lab
- prevent overlapping live recordings/transcriptions while the lab rerun owns the pipeline

Out of scope for the first pass:

- multiple concurrent experiment variants
- waveform display
- audio playback
- diff highlighting
- manual OCR editing
- export/share

## Current Codebase Reality

This design is intentionally based on `codex/qwen35-integration`, not the older branch:

- Settings already has a roomy sidebar/detail shell.
- OCR context exists through `FrontmostWindowOCRService`, `RecordingOCRPrefetch`, and `CleanupPromptBuilder`.
- Speech models already exist as a real catalog in `SpeechModelCatalog`.
- Cleanup already has explicit fast/full models in `TextCleanupManager`.
- `TextCleaner.cleanWithPerformance` already exposes whether the cleanup backend actually ran or fell back to deterministic corrections by way of `modelCallDuration`.

That means the lab can be built as a small product feature on top of real existing seams instead of inventing speculative abstractions.

## Product Design

### Settings Placement

Add a new top-level Settings section:

- `Transcription Lab`

It should sit alongside the existing sections instead of hiding under `Models` or `Cleanup`.

### Lab Layout

The lab is a comparison workspace inside the existing large Settings shell.

Left side of the detail pane:

- archive list of the 50 most recent recordings
- newest first
- each row shows:
  - relative timestamp
  - duration
  - short preview from the best available original text

Right side of the detail pane:

- `Original` block on top
  - raw transcription
  - corrected transcription
  - metadata summary:
    - speech model
    - cleanup model
    - whether OCR context existed
    - capture time
- `Experiment Controls` block in the middle
  - speech model picker
  - cleanup model picker
  - inline cleanup prompt editor
  - rerun button
  - busy/error state
- `Experiment` block on bottom
  - rerun raw transcription
  - rerun corrected transcription
  - fallback note if cleanup did not actually run

The comparison is strictly one original vs one experiment at a time.

## Archive Semantics

### What gets archived

Archive any completed recording session that produced a non-empty audio buffer, even if:

- the live speech transcription returned no text
- cleanup failed
- the live path fell back to deterministic corrections

Rationale:

- Jesse explicitly wants the lab to use the 50 most recent completed recordings that managed to get any audio.
- audio is the primary source material for reruns.
- failed live transcriptions are still valuable lab fixtures.

### What gets stored

Each archive entry stores:

- stable id
- created-at timestamp
- audio file path
- audio duration
- original OCR/window context, if captured
- original raw transcription, optional
- original corrected transcription, optional
- original speech model id
- original cleanup model policy / selected model summary
- whether the live cleanup path fell back instead of making a real model call

### Retention

- keep newest-first ordering
- prune oldest entries beyond 50
- delete pruned audio files from disk

## Storage Design

Store lab data under Application Support in a dedicated lab directory.

Use:

- one JSON index file for metadata
- one audio file per entry

Do not embed audio blobs directly into the index.

This keeps the implementation simple and debuggable while avoiding a large monolithic store file.

## Pipeline Integration

### Live capture path

After a normal recording finishes and we have a non-empty audio buffer:

1. keep the existing live behavior
2. collect the OCR context captured for that run, if any
3. record the raw and final output actually produced by the live run
4. persist an archive entry regardless of whether the live run fully succeeded

The live paste behavior does not change.

### Lab rerun path

When the user reruns a saved recording:

1. load archived audio from disk
2. load or switch to the chosen speech model
3. run speech transcription from saved audio
4. build cleanup prompt using:
   - the current shared cleanup prompt text
   - the archived OCR/window context
   - the current correction-store hints
5. run cleanup with the explicitly chosen cleanup model
6. show results in the experiment panel
7. never call the text paster

## Pipeline Ownership

While a lab rerun is running, the lab owns the transcription/cleanup pipeline.

Required behavior:

- ignore new hotkey-triggered recording starts
- do not allow overlapping live transcription/cleanup
- surface a lab busy state in the Settings UI

The simplest correct implementation is a shared pipeline lock owned by `AppState` that both the live recording path and the lab rerun path must acquire.

This is better than trying to infer ownership from `status` strings alone.

## Speech Model Selection

Use the real speech model catalog already in the app:

- `openai_whisper-tiny.en`
- `openai_whisper-small.en`
- `openai_whisper-small`
- `fluid_parakeet-v3`

The lab speech model picker should use the same `SpeechModelCatalog` data source as the rest of the app.

No hidden backend UI is needed. The user chooses the model; the app routes to the correct backend.

## Cleanup Model Selection

The lab cleanup picker should expose explicit model choices:

- `Qwen 3 1.7B (fast cleanup)`
- `Qwen 3.5 4B (full cleanup)`

The lab should not use automatic cleanup model switching. The point is to compare deliberate choices.

## Prompt Editing

The lab prompt editor binds directly to the existing app-wide cleanup prompt.

That matches Jesse’s requested behavior as long as the text view keeps native undo.

The separate prompt-editor window does not need to be removed in this feature. The lab simply adds an inline editing surface that uses the same source of truth.

## OCR Reuse

The lab should reuse the original OCR context captured at recording start.

If no OCR context was captured for the original run:

- do not recapture anything during rerun
- show that the experiment is running without OCR support

This keeps lab reruns faithful to the original recording conditions.

## Fallback and Error Visibility

The lab needs to distinguish three outcomes:

1. speech transcription failed
2. cleanup executed and returned a result
3. cleanup fell back to deterministic corrections because the model path did not actually complete

Do not add a brand-new error channel to `TextCleaner` for this. Instead, reuse the existing `TextCleanerResult.performance.modelCallDuration` signal:

- non-`nil` model-call duration means cleanup model actually ran
- `nil` means deterministic fallback path

The experiment UI should display:

- rerun raw transcription
- rerun corrected transcription
- a small note when corrected output is only deterministic fallback rather than a true cleanup model result

Actual hard failures like missing audio files or model load failures should be shown inline in the lab controls area.

## File Responsibilities

New files:

- `EchoOne/Lab/TranscriptionLabEntry.swift`
  - archive entry model
- `EchoOne/Lab/TranscriptionLabStore.swift`
  - archive persistence, pruning, disk cleanup
- `EchoOne/Lab/TranscriptionLabRunner.swift`
  - rerun orchestration from archived audio plus archived OCR
- `EchoOne/UI/TranscriptionLabView.swift`
  - lab UI inside Settings

Modified files:

- `EchoOne/AppState.swift`
  - capture/archive live results
  - expose pipeline lock and lab runner access
- `EchoOne/Audio/AudioRecorder.swift`
  - audio serialization helpers for archive storage
- `EchoOne/Cleanup/TextCleaner.swift`
  - accept explicit cleanup model choice and explicit OCR context for lab reruns
- `EchoOne/Cleanup/TextCleanupManager.swift`
  - expose cleanup model metadata for lab UI and reruns
- `EchoOne/UI/SettingsWindow.swift`
  - add the `Transcription Lab` section

## Testing Strategy

Add focused tests for:

- archive insert/load/prune behavior
- audio file cleanup on prune
- live archive insertion for non-empty audio
- archive insertion even when live transcription produced no text
- rerun uses archived audio and archived OCR
- rerun uses explicit speech model choice
- rerun uses explicit cleanup model choice
- rerun never pastes
- pipeline lock blocks overlapping lab/live work
- experiment view model distinguishes cleanup fallback from real model output

Prefer unit tests over brittle UI snapshots.

## Delivery Order

1. archive model and store
2. live archival in `AppState`
3. pipeline lock + rerun runner
4. settings lab UI
5. polish and verification

That keeps the riskiest state and concurrency changes testable before the UI is layered on top.
