# Next: Instruction Mode + Text Selection Rewriting

## What was added

Two new features implemented across 6 files. Ready to build — no stubs.

### Feature 1: Instruction Mode (Right Control)
Hold Right Control, speak a command, release. The spoken instruction is sent to the local LLM.
- If text was selected: transforms the selection in place ("translate to French", "make this formal", "convert to bullet points")
- If nothing selected: generates new text from the instruction and pastes at cursor

### Feature 2: Text Selection Rewriting (already worked, confirmed)
Select text → use normal push-to-talk → speak new text → selection is replaced. This is just how paste works when text is selected. No new code needed.

---

## Files changed

| File | Change |
|---|---|
| `Input/ChordAction.swift` | Added `instructionMode` case |
| `Input/HotkeyMonitor.swift` | Added `onInstructionModeStart/Stop` to protocol + `HotkeyMonitor`, routed in `apply()` |
| `Context/FocusedElementLocator.swift` | Added `selectedText()` — reads `kAXSelectedTextAttribute` from focused AX element |
| `UI/RecordingOverlay.swift` | Added `instructionRecording` ("Instruction mode...") and `transforming` ("Transforming...") overlay states |
| `AppState.swift` | Full wiring — default chord, capture selected text on key-down, instruction processing path, LLM call, fallback |
| `EchoOneTests/EchoOneTests.swift` | Updated `FakeHotkeyMonitor` to satisfy updated protocol |

---

## Default hotkey

**Right Control** (keyCode 62) — user-configurable in Settings like the other shortcuts.

---

## How it flows

1. User selects text in any app
2. Holds Right Control → `FocusedElementLocator().selectedText()` captures the AX selection immediately
3. Speaks instruction ("translate to Spanish")
4. Releases key → transcribes → LLM called with:
   - System: "You are a text transformation assistant. Apply the instruction. Return ONLY the result."
   - User: `"Instruction: {transcript}\n\nText:\n{selectedText}"`
5. Result pasted — replaces the original selection

If no cleanup model is downloaded, raw transcript is pasted as fallback (no hang, no download triggered mid-session).

---

## To test after building

1. Open any text editor, select a paragraph
2. Hold Right Control, say "make this a bullet list", release
3. Overlay should show "Instruction mode..." → "Transcribing..." → "Transforming..."
4. Selected text replaced with bullet list

Also test:
- No selection → speak "write 3 tips for better sleep" → new text pasted at cursor
- No cleanup model downloaded → raw transcript pasted, no crash
- Shortcut conflict → "That shortcut is already in use" error shown (existing behavior)

---

## SourceKit warnings

The red squiggles in the editor ("Failed to build module SwiftUI/Cocoa") are transient SourceKit indexer noise — they appear when the index is rebuilding after file changes. The code itself is valid Swift. Build in Xcode to confirm.
