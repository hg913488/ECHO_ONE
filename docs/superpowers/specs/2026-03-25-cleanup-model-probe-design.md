# Cleanup Model Probe Design

## Goal

Add a small local command-line probe for Echo One's cleanup models so Bot can reproduce and inspect failures like the Qwen 3 fast-model reasoning leak with exact inputs.

The probe must use the real app cleanup stack rather than a parallel test-only implementation. It should make it easy to compare prompt construction, raw model output, sanitized output, and final cleaned output for the existing fast and full cleanup models.

## Scope

In scope:

- A command-line target in this repo for probing cleanup models
- Loading the existing local cleanup models already used by Echo One
- One-shot invocation for reproducible runs
- Interactive REPL mode for repeated experiments against a loaded model
- Visibility into each stage of cleanup processing

Out of scope:

- Shipping this tool in the normal app UI
- Adding a new debug window
- Generalizing the app architecture beyond what is needed to share cleanup code cleanly
- Fixing the Qwen behavior itself in this spec

## Approaches Considered

### 1. CLI target inside Echo One

Add a small executable target that links against the app's cleanup code.

Pros:

- Exercises the real cleanup path
- Easy to run repeatedly from the terminal
- Easy to script for reproducible cases
- Lowest risk of drift from app behavior

Cons:

- Requires a small amount of code extraction if cleanup behavior is too app-bound

Recommendation: use this approach.

### 2. Standalone Swift script

Pros:

- Fast to throw together

Cons:

- High drift risk
- Duplicates prompt and cleanup wiring
- Harder to keep aligned with app behavior

Rejected because it would create exactly the kind of parallel implementation that makes debugging unreliable.

### 3. In-app debug UI

Pros:

- Nice for manual testing later

Cons:

- More UI work than needed
- Harder to automate and capture reproducible runs
- Slower path to root-cause debugging

Rejected for now. A CLI is the right first tool.

## Design

### Target

Add a new executable target, `CleanupModelProbe`.

It should live in this repo and build with the existing project so it can reuse Echo One cleanup code directly.

### Runtime model selection

The probe should let Bot choose:

- `fast`
- `full`

It should load the same local GGUF files and use the same `TextCleanupManager` / `LLM.swift` integration that the app uses.

### Input modes

The probe should support:

- One-shot mode
- Interactive REPL mode

One-shot mode should be scriptable, for example:

```sh
CleanupModelProbe --model fast --input "Okay, it's running now."
```

Interactive mode should keep the selected model loaded and accept repeated inputs so Bot can iterate quickly without paying repeated load cost.

### Output stages

Each run should print:

- model kind and display name
- selected thinking mode
- resolved prompt text sent to the model
- raw input text
- raw model output
- sanitized output
- final cleaned output
- elapsed time

This is the minimum needed to localize failures like:

- prompt construction is wrong
- Qwen emits reasoning only
- sanitizer removes everything
- post-cleanup corrections mutate or erase output

### Thinking mode controls

The probe must allow explicit thinking-mode selection:

- `none`
- `suppressed`
- `enabled`

Default should be `none` so the tool reproduces current app behavior first. That makes it useful for root-cause debugging instead of immediately masking the bug.

### Prompt controls

The probe should accept:

- default cleanup prompt
- prompt override

This allows direct experiments with prompt wording while still making the default app behavior easy to reproduce.

### Window context controls

The probe should support optional OCR/window-context text:

- inline text flag
- file-backed text flag

That keeps it useful for debugging cases where supporting context changes model behavior.

### Reuse boundary

The probe should reuse existing cleanup logic as much as possible. If the current code does not expose the right stages cleanly, the implementation should extract a small shared helper for "run cleanup pipeline and report all stages" rather than duplicating the cleanup path in the probe target.

The probe should not instantiate the full app.

## Data flow

1. Parse CLI arguments.
2. Load the selected cleanup model.
3. Build the effective cleanup prompt, optionally including supplied window context.
4. Invoke the model with the requested thinking mode.
5. Capture:
   - prompt
   - raw model output
   - sanitized output
   - final cleaned output
6. Print a readable transcript.
7. In interactive mode, repeat from step 3 without unloading the model.

## Error handling

The probe should fail clearly for:

- missing model file
- model load failure
- unsupported model kind
- invalid thinking mode
- invalid input combination

If the model returns empty output, the tool should still print the raw and sanitized stages so the failure is visible rather than collapsed into a generic error.

## Testing

Automated tests should cover:

- argument parsing
- thinking-mode selection
- transcript formatting for one-shot runs
- interactive input loop boundaries where practical
- the shared cleanup-stage helper, especially preservation of raw output vs sanitized/final output

Manual verification should cover:

- probing the fast Qwen 3 model with the known failing input
- comparing `--thinking none` vs `--thinking suppressed`

## Implementation notes

- Keep the code path thin and non-magical.
- Prefer extracting one small shared cleanup-stage runner over moving broad app code.
- Do not change app behavior as part of this tool unless a small extraction is required to share logic cleanly.

## Success criteria

Bot can run a command that reproduces the current Qwen fast-model failure and see, in one terminal transcript, the exact prompt, raw model output, sanitized output, and final cleaned output.
