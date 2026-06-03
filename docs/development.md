# Development

## Cleanup Model Probe

Use the cleanup probe to run the local cleanup models directly and inspect each stage of the cleanup pipeline:

- resolved prompt
- corrected input
- raw model output
- sanitized model output
- final cleaned output

Run it through the wrapper script:

```sh
./scripts/cleanup-model-probe.sh --model fast --input "Okay, it's running now." --thinking none
```

The wrapper builds the `CleanupModelProbe` target on first use and then runs the built executable from `build/cleanup-probe-cli`.

### Common examples

Compare current app behavior against suppressed thinking:

```sh
./scripts/cleanup-model-probe.sh --model fast --input "Okay, it's running now." --thinking none
./scripts/cleanup-model-probe.sh --model fast --input "Okay, it's running now." --thinking suppressed
```

Enter interactive mode and keep the selected model loaded:

```sh
./scripts/cleanup-model-probe.sh --model fast --thinking suppressed
```

Type `:quit` or send EOF to exit interactive mode.

Pass supporting OCR text inline:

```sh
./scripts/cleanup-model-probe.sh --model full --input "ship it" --window-context "PR title: ship qwen cleanup fix"
```

Pass supporting OCR text from a file:

```sh
./scripts/cleanup-model-probe.sh --model full --input "ship it" --window-context-file /tmp/window.txt
```

### Notes

- `--model` accepts `fast` or `full`
- `--thinking` accepts `none`, `suppressed`, or `enabled`
- omitting `--input` starts interactive mode
- if you want a clean rebuild, remove `build/cleanup-probe-cli` before running the wrapper again
