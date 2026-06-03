# Settings Sidebar And Sound Toggle Design

Date: 2026-03-25

## Goals

- Add one simple user setting to disable Echo One's recording/status sounds.
- Redesign Settings into a large, spacious, modern macOS-style window.
- Keep every existing setting; this is a reorganization, not a pruning pass.
- Move more of the settings content structure into SwiftUI where that makes the implementation cleaner.

## Non-Goals

- No settings removal or behavioral simplification beyond the new sound toggle.
- No feature expansion beyond the sound toggle and the UI restructuring.
- No redesign of onboarding in this pass.

## Current Problems

- Settings are implemented as one long single-page form in [`EchoOne/UI/SettingsWindow.swift`](/Users/jesse/.config/superpowers/worktrees/echo-one/codex-qwen35-integration/EchoOne/UI/SettingsWindow.swift), which has grown into a dense monolith.
- The current window size is small for desktop use and does not feel like a native macOS settings surface.
- Sound effects are always on and have no user control.

## Recommended Approach

Use a macOS-style sidebar settings shell hosted in the existing AppKit window controller, with the content itself restructured into SwiftUI section views.

Why this approach:

- It fits the requested "big and roomy" desktop UX better than top tabs.
- It keeps window lifecycle behavior stable by preserving the current AppKit host.
- It reduces future maintenance cost by splitting the settings content into focused SwiftUI views.
- It allows the sound toggle to land naturally in the `Recording` section without further cluttering one giant form.

## Architecture

### Window Hosting

- Keep `SettingsWindowController` as the owner of the `NSWindow`.
- Increase the default window size substantially, targeting roughly `900x680` to `960x720`.
- Continue reusing a single settings window instance.

### SwiftUI Shell

- Replace the current single-page `SettingsView` body with a sidebar/detail shell.
- Introduce a `SettingsSection` enum to drive selection and labels.
- Create a root view, tentatively `SettingsRootView`, that owns:
  - sidebar list
  - current section selection
  - detail content area

### Section Views

Split the current settings content into dedicated section views:

- `RecordingSettingsView`
  - push-to-talk shortcut
  - toggle-recording shortcut
  - microphone picker
  - live mic preview and level meter
  - speech model picker
  - new `Play sounds` toggle

- `CleanupSettingsView`
  - cleanup enabled
  - cleanup model policy
  - edit cleanup prompt
  - frontmost window OCR toggle
  - post-paste learning toggle
  - screen-recording recovery UI

- `CorrectionsSettingsView`
  - preferred transcriptions editor
  - commonly misheard editor

- `ModelsSettingsView`
  - runtime model inventory
  - active download status
  - download missing models action

- `GeneralSettingsView`
  - launch at login

## Sound Toggle Design

### UX

- Add one master toggle labeled `Play sounds`.
- Place it in `RecordingSettingsView`.
- Default value is `true` so current behavior remains unchanged for existing and new users until they opt out.

### Persistence

- Store the setting in app defaults.
- Load it into `AppState` at startup and bind it directly into the settings UI.

### Behavior

- `SoundEffects` becomes setting-aware and returns immediately when sounds are disabled.
- The change should be applied live; no restart required.

## Data Flow

- `AppState` remains the central owner of settings state exposed to the UI.
- The new sound setting should follow the same pattern as other persisted app preferences:
  - read from defaults on initialization
  - update defaults on change
  - bind SwiftUI controls directly to the state

- Existing helpers should be reused where possible:
  - `MicPreviewController`
  - `SettingsMicMonitor`
  - `ModelInventoryCard`
  - screen recording recovery UI

## Error Handling

- Preserve current error displays for cleanup model loading and permission recovery.
- The redesign should not change any existing permission or model-loading behavior.
- The sound toggle should fail safe: if the setting cannot be loaded, default to sounds enabled.

## Testing

Add or update tests for:

- sound setting default and persistence
- `SoundEffects` honoring the disabled setting
- settings window controller continuing to host and reuse one window
- section-shell construction at a shallow structural level if practical, without brittle UI snapshot tests

Retain existing settings window behavior tests unless the host type changes enough that they need small adjustments.

## Implementation Notes

- Favor extraction over rewrite: move existing blocks into section views with minimal behavioral churn.
- Preserve existing window title and close behavior.
- Keep the first pass visually polished but disciplined; do not add extra controls or new settings categories.
- If needed, use AppKit only for window hosting and keep the section navigation/content layout in SwiftUI.

## Risks

- The biggest risk is turning a structural UI refactor into hidden behavior churn. This should be avoided by reusing existing bindings and helper objects.
- There are existing Swift concurrency warnings in nearby settings code. This pass should avoid broad warning cleanup unless required by the refactor.

## Success Criteria

- Settings opens as a larger, more spacious window with a sidebar section layout.
- All current settings remain available.
- Users can disable Echo One sounds with one toggle.
- Existing settings behaviors still work without regressions.
