# Transcription Stack Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build configurable recording chords, cleanup backend/model selection, OCR-informed cleanup, and conservative correction learning as a stacked series of feature branches.

**Architecture:** Keep the current app structure, but add four durable seams: chord bindings, cleanup backend selection, OCR context collection, and deterministic corrections/learning. Each branch should ship working software on its own and become the base for the next branch.

**Tech Stack:** Swift, SwiftUI, AppKit, CoreGraphics event taps, Accessibility APIs, Vision OCR, WhisperKit, LLM.swift, optional FoundationModels, XCTest

---

## File Map

### Project Generation Rule

- This repo uses `project.yml` with XcodeGen.
- After any task that creates, deletes, or renames Swift files, run `xcodegen generate` before the next `xcodebuild` command so the new files are included in the project.

### Existing Files To Modify

- `EchoOne/AppState.swift`
  Wire new chord actions, cleanup pipeline, OCR context, and post-paste learning into the existing app flow.
- `EchoOne/Input/HotkeyMonitor.swift`
  Convert from Control-only logic into a wrapper around the new chord engine, or replace its internals while preserving the app-facing callback shape.
- `EchoOne/UI/SettingsWindow.swift`
  Add `Shortcuts`, `Cleanup`, `Context`, and `Corrections` sections.
- `EchoOne/UI/OnboardingWindow.swift`
  Keep onboarding minimal while pointing advanced users to settings.
- `EchoOne/Cleanup/TextCleanupManager.swift`
  Move from implicit local-model behavior toward explicit backend/model policy state.
- `EchoOne/Cleanup/TextCleaner.swift`
  Stop owning all cleanup decisions directly; call the deterministic correction layer, optional OCR context provider, and selected cleanup backend.
- `EchoOne/PermissionChecker.swift`
  Add Screen Recording status/open-settings helpers.
- `EchoOne/Input/TextPaster.swift`
  Expose enough paste metadata for the delayed learning branch.
- `.gitignore`
  Keep `docs/superpowers/specs` and `docs/superpowers/plans` tracked.

### New Input Files

- `EchoOne/Input/PhysicalKey.swift`
- `EchoOne/Input/KeyChord.swift`
- `EchoOne/Input/ChordAction.swift`
- `EchoOne/Input/ChordBindingStore.swift`
- `EchoOne/Input/ChordEngine.swift`
- `EchoOne/Input/PasteSession.swift`
- `EchoOne/UI/ShortcutRecorderView.swift`

### New Cleanup Files

- `EchoOne/Cleanup/CleanupBackend.swift`
- `EchoOne/Cleanup/LocalLLMCleanupBackend.swift`
- `EchoOne/Cleanup/FoundationModelsCleanupBackend.swift`
- `EchoOne/Cleanup/FoundationModelAvailabilityProvider.swift`
- `EchoOne/Cleanup/CleanupSettings.swift`
- `EchoOne/Cleanup/CleanupPromptBuilder.swift`
- `EchoOne/Cleanup/CorrectionStore.swift`
- `EchoOne/Cleanup/DeterministicCorrectionEngine.swift`
- `EchoOne/Cleanup/PostPasteLearningCoordinator.swift`

### New OCR/Context Files

- `EchoOne/Context/OCRContext.swift`
- `EchoOne/Context/OCRRequestFactory.swift`
- `EchoOne/Context/WindowCaptureService.swift`
- `EchoOne/Context/FrontmostWindowOCRService.swift`
- `EchoOne/Context/FocusedElementLocator.swift`

### New Test Files

- `EchoOneTests/KeyChordTests.swift`
- `EchoOneTests/ChordEngineTests.swift`
- `EchoOneTests/ChordBindingStoreTests.swift`
- `EchoOneTests/TextCleanupManagerTests.swift`
- `EchoOneTests/TextCleanerTests.swift`
- `EchoOneTests/CleanupPromptBuilderTests.swift`
- `EchoOneTests/CleanupBackendTests.swift`
- `EchoOneTests/OCRContextTests.swift`
- `EchoOneTests/CorrectionStoreTests.swift`
- `EchoOneTests/PostPasteLearningCoordinatorTests.swift`

## Chunk 1: `codex/chord-actions`

### Task 1: Add the chord domain model and persistence

**Files:**
- Create: `EchoOne/Input/PhysicalKey.swift`
- Create: `EchoOne/Input/KeyChord.swift`
- Create: `EchoOne/Input/ChordAction.swift`
- Create: `EchoOne/Input/ChordBindingStore.swift`
- Test: `EchoOneTests/KeyChordTests.swift`
- Test: `EchoOneTests/ChordBindingStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testPhysicalKeyUsesRawKeyCodesForSideSpecificKeys()
func testKeyChordPreservesSideSpecificModifiers()
func testKeyChordRejectsEmptyChord()
func testBindingStorePersistsPushAndToggleChords()
func testBindingStoreRejectsDuplicateBindings()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/KeyChordTests -only-testing:EchoOneTests/ChordBindingStoreTests`
Expected: FAIL because the new types do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

```swift
enum ChordAction: String, Codable {
    case pushToTalk
    case toggleToTalk
}

struct PhysicalKey: Codable, Hashable {
    let keyCode: UInt16
}

struct KeyChord: Codable, Equatable {
    let keys: Set<PhysicalKey>
}
```

Implement `PhysicalKey` as a raw key-code wrapper so side-specific modifiers are encoded by their distinct hardware key codes, non-modifier keys like Space use the same type, and Globe can be recorded if it surfaces as a key code on the running hardware. Implement `ChordBindingStore` with exactly one binding per action, conflict validation, and `AppStorage`/`UserDefaults` persistence.

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run the same command from Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Input/PhysicalKey.swift EchoOne/Input/KeyChord.swift EchoOne/Input/ChordAction.swift EchoOne/Input/ChordBindingStore.swift EchoOneTests/KeyChordTests.swift EchoOneTests/ChordBindingStoreTests.swift
git commit -m "feat: add chord bindings"
```

### Task 2: Replace Control-only matching with a chord engine

**Files:**
- Create: `EchoOne/Input/ChordEngine.swift`
- Modify: `EchoOne/Input/HotkeyMonitor.swift`
- Modify: `EchoOneTests/HotkeyMonitorTests.swift`
- Test: `EchoOneTests/ChordEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testPrefixChordDoesNotFireEarly()
func testPushToTalkStartsImmediatelyWhenExactChordMatches()
func testToggleToTalkTogglesOnSecondMatch()
func testPushToTalkStopsWhenAnyRequiredKeyReleases()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/ChordEngineTests -only-testing:EchoOneTests/HotkeyMonitorTests`
Expected: FAIL because prefix-aware chord matching does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
enum ChordMatchResult {
    case none
    case prefix
    case exact(ChordAction)
}
```

Update `HotkeyMonitor` to observe `.flagsChanged`, `.keyDown`, and `.keyUp`, convert them into a small synthetic input event type, and delegate matching to `ChordEngine` instead of using `isControlOnly`. Keep `ChordEngine` testable as a pure reducer over synthetic key events so `HotkeyMonitorTests` do not depend on real Accessibility-backed taps. As part of this task, remove the existing 0.3-second hold timer path (`minimumHoldDuration`, `holdTimer`, `startHoldTimer`, `cancelHoldTimer`) and replace it with immediate exact-match start plus key-release stop semantics for both modifier and non-modifier keys.

- [ ] **Step 4: Run the targeted and full test suites**

Run targeted command from Step 2, then:
`xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Input/ChordEngine.swift EchoOne/Input/HotkeyMonitor.swift EchoOneTests/ChordEngineTests.swift EchoOneTests/HotkeyMonitorTests.swift
git commit -m "feat: add chord engine"
```

### Task 3: Add settings/onboarding support for push and toggle chords

**Files:**
- Create: `EchoOne/UI/ShortcutRecorderView.swift`
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Modify: `EchoOne/UI/OnboardingWindow.swift`
- Modify: `EchoOne/AppState.swift`
- Test: `EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing tests**

Add app-state-level tests that assert default bindings are loaded and both actions are wired into recording behavior.

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/EchoOneTests`
Expected: FAIL on missing shortcut defaults or missing recorder wiring.

- [ ] **Step 3: Write the minimal implementation**

Add a `Shortcuts` settings section, keep onboarding focused on the default behavior, and wire `AppState` to separate push/toggle callbacks without changing the rest of the transcription flow yet.

- [ ] **Step 4: Run the full test suite and build**

Run:
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/UI/ShortcutRecorderView.swift EchoOne/UI/SettingsWindow.swift EchoOne/UI/OnboardingWindow.swift EchoOne/AppState.swift EchoOneTests/EchoOneTests.swift
git commit -m "feat: add shortcut settings"
```

## Chunk 2: `codex/cleanup-model-picker`

### Task 4: Add explicit cleanup settings and local model policy

**Files:**
- Create: `EchoOne/Cleanup/CleanupSettings.swift`
- Modify: `EchoOne/Cleanup/TextCleanupManager.swift`
- Test: `EchoOneTests/TextCleanerTests.swift`
- Test: `EchoOneTests/TextCleanupManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testAutomaticPolicyPrefersFastForShortInput()
func testFastOnlyPolicyAlwaysReturnsFastWhenReady()
func testFullOnlyPolicyAlwaysReturnsFullWhenReady()
func testQuestionSelectionStillFlowsThroughManagerPolicy()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/TextCleanupManagerTests`
Expected: FAIL because explicit policy types do not exist.

- [ ] **Step 3: Write the minimal implementation**

Add a persisted local policy enum and replace `model(for:)` with a manager-owned selection API that takes both `wordCount` and `isQuestion`, so `TextCleaner` no longer needs to bypass manager policy when it sees a question or long input. Make the manager testable with injected fake model handles or a tiny model-provider seam so the tests do not require real GGUF downloads.

- [ ] **Step 4: Run targeted and full tests**

Run targeted command from Step 2, then:
`xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Cleanup/CleanupSettings.swift EchoOne/Cleanup/TextCleanupManager.swift EchoOneTests/TextCleanupManagerTests.swift EchoOneTests/TextCleanerTests.swift
git commit -m "feat: add cleanup model policy"
```

### Task 5: Expose cleanup model policy in settings

**Files:**
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOne/Cleanup/TextCleaner.swift`
- Test: `EchoOneTests/TextCleanerTests.swift`

- [ ] **Step 1: Write the failing test**

Add `TextCleaner`-level tests that verify the selected manager policy is consulted when cleanup runs, including question input and longer text.

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/TextCleanerTests`
Expected: FAIL because `TextCleaner.clean` still bypasses the selected policy.

- [ ] **Step 3: Write the minimal implementation**

Add a model picker under the `Cleanup` section and update `TextCleaner.clean` to delegate all local-model selection back to `TextCleanupManager`, including question input.

- [ ] **Step 4: Run the full test suite and build**

Run:
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/UI/SettingsWindow.swift EchoOne/AppState.swift EchoOne/Cleanup/TextCleaner.swift
git commit -m "feat: add cleanup model picker"
```

## Chunk 3: `codex/foundation-model-cleanup`

### Task 6: Introduce a pluggable cleanup backend layer

**Files:**
- Create: `EchoOne/Cleanup/CleanupBackend.swift`
- Create: `EchoOne/Cleanup/LocalLLMCleanupBackend.swift`
- Modify: `EchoOne/Cleanup/TextCleaner.swift`
- Modify: `EchoOne/Cleanup/TextCleanupManager.swift`
- Test: `EchoOneTests/CleanupBackendTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testLocalBackendUsesSelectedLocalPolicy()
func testCleanerFallsBackToCorrectedRawTextWhenBackendFails()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/CleanupBackendTests`
Expected: FAIL because the backend abstraction does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
protocol CleanupBackend {
    func clean(text: String, prompt: String) async throws -> String
}
```

Move the current `LLM.swift` cleanup behavior behind `LocalLLMCleanupBackend`, make failure explicit with `throws`, and have `TextCleaner` catch backend failure so it can fall back to the deterministic corrected text. Add an injected backend/model-provider seam so these tests can run against fakes instead of real model downloads.

- [ ] **Step 4: Run targeted and full tests**

Run targeted command from Step 2, then:
`xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Cleanup/CleanupBackend.swift EchoOne/Cleanup/LocalLLMCleanupBackend.swift EchoOne/Cleanup/TextCleaner.swift EchoOne/Cleanup/TextCleanupManager.swift EchoOneTests/CleanupBackendTests.swift
git commit -m "refactor: add cleanup backend abstraction"
```

### Task 7: Add the optional Foundation Models backend

**Files:**
- Create: `EchoOne/Cleanup/FoundationModelsCleanupBackend.swift`
- Create: `EchoOne/Cleanup/FoundationModelAvailabilityProvider.swift`
- Modify: `EchoOne/Cleanup/CleanupSettings.swift`
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Modify: `EchoOne/AppState.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testFoundationBackendUnavailableFallsBackToLocal()
func testFoundationBackendAvailabilityReasonIsExposed()
func testFoundationAvailabilityCanBeStubbedInTests()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/CleanupBackendTests`
Expected: FAIL because there is no Foundation Models backend or fallback behavior.

- [ ] **Step 3: Write the minimal implementation**

Guard Foundation Models code with `if #available(macOS 26.0, *)` and `SystemLanguageModel` availability checks so the app still compiles and runs on macOS 14.0+. Put all direct Foundation Models availability reads behind a small injectable provider protocol so the macOS 14-targeted tests can stub available/unavailable states and reasons deterministically, and use a backend factory/provider seam so fallback behavior can be tested without invoking the real system model.

- [ ] **Step 4: Run the full test suite and build**

Run:
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Cleanup/FoundationModelsCleanupBackend.swift EchoOne/Cleanup/FoundationModelAvailabilityProvider.swift EchoOne/Cleanup/CleanupSettings.swift EchoOne/UI/SettingsWindow.swift EchoOne/AppState.swift EchoOneTests/CleanupBackendTests.swift
git commit -m "feat: add foundation models cleanup backend"
```

## Chunk 4: `codex/ocr-context`

Reference implementation notes:

- Use the local ignored reference checkout at `inspo/winby` during implementation.
- Start with:
  - `inspo/winby/Sources/Winby/AppConfig.swift`
  - `inspo/winby/Sources/Winby/WindowManager+Screenshots.swift`
  - `inspo/winby/Sources/Winby/WindowManager+ContentSearch.swift`
  - `inspo/winby/docs/screenshot-capture.md`
- Relevant APIs already exercised there:
  - `CGPreflightScreenCaptureAccess()`
  - Screen Recording settings URL
  - `SCShareableContent`, `SCContentFilter`, `SCScreenshotManager.captureImage`
  - `VNRecognizeTextRequest` in accurate mode

### Task 8: Add permission-aware window capture and OCR services

**Files:**
- Create: `EchoOne/Context/OCRContext.swift`
- Create: `EchoOne/Context/OCRRequestFactory.swift`
- Create: `EchoOne/Context/WindowCaptureService.swift`
- Create: `EchoOne/Context/FrontmostWindowOCRService.swift`
- Modify: `EchoOne/PermissionChecker.swift`
- Test: `EchoOneTests/OCRContextTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testOCRRequestFactoryUsesAccurateRecognitionLevel()
func testOCRRequestFactoryEnablesLanguageCorrection()
func testOCRRequestFactoryAcceptsCustomWords()
func testMissingScreenRecordingPermissionDisablesCapture()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/OCRContextTests`
Expected: FAIL because capture/OCR services do not exist.

- [ ] **Step 3: Write the minimal implementation**

Add an `OCRRequestFactory` that builds the configured `VNRecognizeTextRequest` so tests can assert request settings directly. The factory should accept `customWords` as input even if the initial caller passes an empty list, so branch 5 can plug preferred words in without refactoring the OCR service. Add Screen Recording helpers to `PermissionChecker`, and keep the OCR service injectable with a permission provider and window-capture source so tests do not require real capture permissions.

- [ ] **Step 4: Run targeted and full tests**

Run targeted command from Step 2, then:
`xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Context/OCRContext.swift EchoOne/Context/OCRRequestFactory.swift EchoOne/Context/WindowCaptureService.swift EchoOne/Context/FrontmostWindowOCRService.swift EchoOne/PermissionChecker.swift EchoOneTests/OCRContextTests.swift
git commit -m "feat: add OCR context services"
```

### Task 9: Inject OCR context into the cleanup prompt

**Files:**
- Create: `EchoOne/Cleanup/CleanupPromptBuilder.swift`
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOne/Cleanup/TextCleaner.swift`
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Test: `EchoOneTests/CleanupPromptBuilderTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testBuilderIncludesWindowContentsWrapperWhenContextEnabled()
func testBuilderOmitsWindowContentsWhenContextUnavailable()
func testBuilderTrimsLongOCRContextBeforePromptAssembly()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/CleanupPromptBuilderTests`
Expected: FAIL because prompt assembly still lives inline in the cleanup path.

- [ ] **Step 3: Write the minimal implementation**

Move prompt assembly into `CleanupPromptBuilder`, add a `Context` settings section, collect OCR text only when enabled and permitted, and inject it using the exact `<WINDOW CONTENTS>` wrapper from the spec.

- [ ] **Step 4: Run the full test suite and build**

Run:
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Cleanup/CleanupPromptBuilder.swift EchoOne/AppState.swift EchoOne/Cleanup/TextCleaner.swift EchoOne/UI/SettingsWindow.swift EchoOneTests/CleanupPromptBuilderTests.swift
git commit -m "feat: inject OCR context into cleanup"
```

## Chunk 5: `codex/preferred-transcriptions`

### Task 10: Add the correction store and deterministic correction engine

**Files:**
- Create: `EchoOne/Cleanup/CorrectionStore.swift`
- Create: `EchoOne/Cleanup/DeterministicCorrectionEngine.swift`
- Modify: `EchoOne/Cleanup/TextCleaner.swift`
- Test: `EchoOneTests/TextCleanerTests.swift`
- Test: `EchoOneTests/CorrectionStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testPreferredTranscriptionsPreserveConfiguredPhrase()
func testCommonlyMisheardReplacementAppliesBeforeCleanup()
func testPreferredTranscriptionsWinOverBroadReplacement()
func testDeterministicCorrectionsStillApplyWhenNoCleanupBackendIsAvailable()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/CorrectionStoreTests`
Expected: FAIL because the store and deterministic correction engine do not exist.

- [ ] **Step 3: Write the minimal implementation**

Persist both lists locally, apply them deterministically before any backend call, re-apply protected preferred phrases after cleanup when necessary, and keep the deterministic correction layer active even when no cleanup backend/model is available.

- [ ] **Step 4: Run targeted and full tests**

Run targeted command from Step 2, then:
`xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Cleanup/CorrectionStore.swift EchoOne/Cleanup/DeterministicCorrectionEngine.swift EchoOne/Cleanup/TextCleaner.swift EchoOneTests/CorrectionStoreTests.swift EchoOneTests/TextCleanerTests.swift
git commit -m "feat: add deterministic transcription corrections"
```

### Task 11: Add corrections UI and feed preferred words into OCR

**Files:**
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Modify: `EchoOne/Context/FrontmostWindowOCRService.swift`
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOne/Cleanup/CorrectionStore.swift`
- Modify: `EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing tests**

Add `CorrectionStoreTests` and `EchoOneTests` coverage that preferred words are forwarded into the OCR configuration and that correction settings round-trip through app state/store persistence.

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/CorrectionStoreTests -only-testing:EchoOneTests/EchoOneTests`
Expected: FAIL because the UI wiring and OCR custom words integration do not exist.

- [ ] **Step 3: Write the minimal implementation**

Add a `Corrections` settings section with editor affordances for both lists and route preferred words into OCR `customWords`.

- [ ] **Step 4: Run the full test suite and build**

Run:
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/UI/SettingsWindow.swift EchoOne/Context/FrontmostWindowOCRService.swift EchoOne/AppState.swift EchoOne/Cleanup/CorrectionStore.swift EchoOneTests/CorrectionStoreTests.swift EchoOneTests/EchoOneTests.swift
git commit -m "feat: add corrections settings"
```

## Chunk 6: `codex/learn-misheard`

### Task 12: Add paste metadata capture and the delayed learning coordinator

**Files:**
- Create: `EchoOne/Input/PasteSession.swift`
- Create: `EchoOne/Context/FocusedElementLocator.swift`
- Create: `EchoOne/Cleanup/PostPasteLearningCoordinator.swift`
- Modify: `EchoOne/Input/TextPaster.swift`
- Modify: `EchoOne/AppState.swift`
- Test: `EchoOneTests/PostPasteLearningCoordinatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testCoordinatorStartsLearningPassAfterPasteDelay()
func testCoordinatorRejectsLargeRewriteDiffs()
func testCoordinatorStoresHighConfidenceNarrowReplacement()
func testCoordinatorUsesInjectedSchedulerInsteadOfRealSleep()
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/PostPasteLearningCoordinatorTests`
Expected: FAIL because the learning coordinator does not exist.

- [ ] **Step 3: Write the minimal implementation**

Introduce a `PasteSession` contract that captures pasted text, timestamp, frontmost app bundle identifier, frontmost window identifier if available, window frame, and focused-element frame snapshot at paste time. Have `TextPaster` expose a completion hook that hands off a `PasteSession`, and give `PostPasteLearningCoordinator` an injected scheduler/clock so the 15-second delay is testable without real sleeps. Use that session to revisit the destination, prefer OCR on the saved focused-element region when it still makes sense, fall back to the saved window region when focus has moved, and only persist narrow, high-confidence replacements.

- [ ] **Step 4: Run targeted and full tests**

Run targeted command from Step 2, then:
`xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/Input/PasteSession.swift EchoOne/Context/FocusedElementLocator.swift EchoOne/Cleanup/PostPasteLearningCoordinator.swift EchoOne/Input/TextPaster.swift EchoOne/AppState.swift EchoOneTests/PostPasteLearningCoordinatorTests.swift
git commit -m "feat: add post-paste learning"
```

### Task 13: Add user-facing learning controls and final verification

**Files:**
- Modify: `EchoOne/UI/SettingsWindow.swift`
- Modify: `EchoOne/Cleanup/CorrectionStore.swift`
- Modify: `EchoOne/Cleanup/PostPasteLearningCoordinator.swift`
- Modify: `EchoOne/AppState.swift`
- Modify: `EchoOneTests/EchoOneTests.swift`

- [ ] **Step 1: Write the failing tests**

Add `EchoOneTests` and `PostPasteLearningCoordinatorTests` coverage for learning enablement/disablement and rejection of ambiguous OCR corrections even when learning is on.

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test -only-testing:EchoOneTests/PostPasteLearningCoordinatorTests -only-testing:EchoOneTests/EchoOneTests`
Expected: FAIL because learning controls are not wired into the coordinator.

- [ ] **Step 3: Write the minimal implementation**

Add settings for learning behavior, keep automatic learning conservative, and default to discarding ambiguous candidates.

- [ ] **Step 4: Run the complete verification suite**

Run:
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -derivedDataPath build/test-derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project EchoOne.xcodeproj -scheme EchoOne -configuration Debug -derivedDataPath build/derived -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`

Smoke-check:
- launch the built app
- verify push-to-talk and toggle-to-talk both trigger
- verify Screen Recording status messaging
- verify cleanup backend/model switching
- verify OCR context injection and delayed learning flow on a manual correction

Expected: PASS / BUILD SUCCEEDED / manual smoke path works.

- [ ] **Step 5: Commit**

```bash
git add EchoOne/UI/SettingsWindow.swift EchoOne/Cleanup/CorrectionStore.swift EchoOne/Cleanup/PostPasteLearningCoordinator.swift EchoOne/AppState.swift EchoOneTests/EchoOneTests.swift
git commit -m "feat: finalize transcription learning controls"
```

## Execution Notes

- Run `xcodegen generate` after every task that creates, deletes, or renames Swift files.
- Create a fresh implementation worktree before branch 1 execution.
- Stack branches in order:
  - `codex/chord-actions`
  - `codex/cleanup-model-picker`
  - `codex/foundation-model-cleanup`
  - `codex/ocr-context`
  - `codex/preferred-transcriptions`
  - `codex/learn-misheard`
- After each chunk, request review before moving to the next chunk.
- Keep commits narrow. Do not mix branch-N work into branch-(N+1).
