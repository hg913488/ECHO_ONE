# Speaker Identities Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable recognized voices for transcription-lab speaker tagging, with local/global naming controls and speaker labels directly on the lab timeline.

**Architecture:** Keep the existing lab archive format unchanged. Add one global recognized-voices store plus one lab-scoped speaker-snapshot store, resolve names after reruns using extracted speaker embeddings, and surface those resolved names in the lab UI and a new settings pane.

**Tech Stack:** Swift, SwiftUI, Codable JSON stores, FluidAudio diarizer embeddings, XCTest, xcodebuild

---

## Chunk 1: Persistence And Matching

### Task 1: Add the failing store tests

**Files:**
- Create: `EchoOneTests/RecognizedVoiceStoreTests.swift`
- Create: `EchoOneTests/TranscriptionLabSpeakerProfileStoreTests.swift`
- Test: `EchoOneTests/RecognizedVoiceStoreTests.swift`
- Test: `EchoOneTests/TranscriptionLabSpeakerProfileStoreTests.swift`

- [ ] **Step 1: Write the failing tests**
- [ ] **Step 2: Run the new store tests and verify they fail for missing types**
- [ ] **Step 3: Add `RecognizedVoiceProfile`, `RecognizedVoiceStore`, `TranscriptionLabSpeakerProfile`, and `TranscriptionLabSpeakerProfileStore`**
- [ ] **Step 4: Run the store tests and verify they pass**
- [ ] **Step 5: Commit**

### Task 2: Add the failing matching tests

**Files:**
- Create: `EchoOne/SpeakerIdentity/SpeakerIdentityMatcher.swift`
- Create: `EchoOneTests/SpeakerIdentityMatcherTests.swift`
- Test: `EchoOneTests/SpeakerIdentityMatcherTests.swift`

- [ ] **Step 1: Write tests for auto-match, auto-create, and explicit global update behavior**
- [ ] **Step 2: Run the matcher tests and verify they fail**
- [ ] **Step 3: Implement minimal matching and embedding averaging logic**
- [ ] **Step 4: Run the matcher tests and verify they pass**
- [ ] **Step 5: Commit**

## Chunk 2: Lab Identity Resolution

### Task 3: Add the failing controller tests

**Files:**
- Modify: `EchoOne/Lab/TranscriptionLabController.swift`
- Modify: `EchoOneTests/TranscriptionLabControllerTests.swift`

- [ ] **Step 1: Add tests for resolved speaker names, local rename state, and promote-global affordances**
- [ ] **Step 2: Run the controller tests and verify they fail**
- [ ] **Step 3: Extend `TranscriptionLabController` with speaker profile view state and rename/update actions**
- [ ] **Step 4: Run the controller tests and verify they pass**
- [ ] **Step 5: Commit**

### Task 4: Add the failing app-state tests

**Files:**
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Add tests proving lab reruns create or match recognized voices and snapshot lab speaker profiles**
- [ ] **Step 2: Run the focused app-state tests and verify they fail**
- [ ] **Step 3: Wire the new stores and speaker-identity resolution into lab reruns**
- [ ] **Step 4: Run the focused app-state tests and verify they pass**
- [ ] **Step 5: Commit**

## Chunk 3: UI

### Task 5: Add the failing settings and timeline tests where practical

**Files:**
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Modify: `EchoOneTests/TranscriptionLabControllerTests.swift`
- Test: `EchoOneTests/MeetingTranscriptWindowPresentationTests.swift`

- [ ] **Step 1: Add view-model-level tests for timeline label inputs and recognized-voice section data**
- [ ] **Step 2: Run the focused tests and verify they fail**
- [ ] **Step 3: Add the `Recognized Voices` settings section**
- [ ] **Step 4: Add lab speaker editor rows, resolved speaker transcript rendering, and direct timeline labels for all speakers**
- [ ] **Step 5: Run the focused tests and verify they pass**
- [ ] **Step 6: Commit**

## Chunk 4: Verification And Release

### Task 6: Verify the whole slice

**Files:**
- Modify: `EchoOne.xcodeproj` (only if required by compiler errors)

- [ ] **Step 1: Run the focused test suites**

```bash
xcodebuild test -project EchoOne.xcodeproj -scheme EchoOne -destination 'platform=macOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:EchoOneTests/RecognizedVoiceStoreTests -only-testing:EchoOneTests/TranscriptionLabSpeakerProfileStoreTests -only-testing:EchoOneTests/SpeakerIdentityMatcherTests -only-testing:EchoOneTests/TranscriptionLabControllerTests -only-testing:EchoOneTests/EchoOneTests
```

- [ ] **Step 2: Run a release build**

```bash
xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Release -destination 'platform=macOS,arch=arm64' -skipMacroValidation DEVELOPMENT_TEAM=87WJ58S66M CODE_SIGN_IDENTITY='Apple Development' build
```

- [ ] **Step 3: Copy the built app into `/Applications/EchoOne.app`**

```bash
ditto build/Build/Products/Release/EchoOne.app /Applications/EchoOne.app
```

- [ ] **Step 4: Confirm the installed app is signed and reflects the fresh build**
- [ ] **Step 5: Commit**
