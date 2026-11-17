# Echo Actions

Echo Actions are voice commands that run a script on your Mac straight away, without asking Claude or Codex. Hold the Voice Agent key, say the action's name, and Echo One runs the script and reads out the last line it prints.

An action is one script file. The format is the same as [Raycast script commands](https://github.com/raycast/script-commands), so a Raycast script works as an Echo Action without changes, and an Echo Action works in Raycast.

## Where actions live

- Your own actions: `~/Documents/Echo One Actions/`. Echo One creates this folder. Settings → Voice Agent → Echo Actions can add more folders, such as your Raycast scripts folder.
- Built-in actions ship inside the app. Their source is in [`actions/`](actions/) in this repo.
- Your file wins over a built-in with the same title.
- Files are read each time you press the Voice Agent key. A new file works on the next press, with no restart.
- The first time one of your own actions runs, and again after you edit it, she asks "First time running … Say yes to run it." Built-ins don't ask.

## The format

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open NHL Site
# @raycast.mode compact
# @raycast.description Opens the live NHL site in the browser.
# @echo.phrases open the nhl site, open my hockey site

open "https://example.com" || exit 1
echo "Opened the NHL site."
```

| Line | Required | What it does |
|---|---|---|
| `@raycast.schemaVersion 1` | yes | Always `1`. |
| `@raycast.title` | yes | The name. Saying it runs the action. |
| `@raycast.mode` | yes | `compact` or `fullOutput`: she says the last line. `silent`: the last line shows but isn't spoken. `inline` counts as `compact`. |
| `@echo.phrases` | no | Other ways to say it, comma separated. Echo One only; Raycast ignores it. |
| `@raycast.argument1` | no | The action takes words after its name, as `$1`. See Arguments. |
| `@raycast.needsConfirmation true` | no | She asks "… ? Say yes." first. Use it for anything that can't be undone. |
| `@raycast.currentDirectoryPath` | no | The folder the script runs in. Defaults to the script's own folder. |
| `@raycast.description` | no | Shown in Settings. |

Any language works: start the file with a `#!` line (`#!/bin/bash`, `#!/usr/bin/env python3`, `#!/usr/bin/swift`). `.applescript` files run with `osascript`.

## How a command matches

Echo One lowercases what you said, removes punctuation (`Wi-Fi` becomes `wifi`, `what's` becomes `whats`), and drops a leading "please", "can you", "could you" or "hey" and a trailing "please". Write `@echo.phrases` the same way you'd say them; they're cleaned up the same way.

- An action without arguments runs when what you said is exactly its title or one of its phrases.
- An action with an argument also runs when what you said starts with its title or a phrase. The rest becomes `$1`.
- If several match, the longest phrase wins. "Quit all apps" beats "quit".
- If nothing matches, the command goes to the Voice Agent as normal.

## Arguments

Only `$1` comes from voice: everything after the phrase. "Timer 5 minutes" runs `timer.sh "5 minutes"`. A script with more than one required argument can't be run by voice; Settings shows it as "Needs typing". Optional extra arguments are fine.

Speech-to-text often writes numbers as words, so Echo One turns them into digits before passing them on: "thirty percent" arrives as `30 percent`, "three thousand" as `3000`. Strip what you don't need, as `kill-port.sh` does with `tr -cd '0-9'`.

## Output and exit codes

- She says the **last line** the script prints. Keep it short and spoken: "Volume 30.", not a log line. Don't print paths or URLs.
- The full output goes in the day's Voice Agent transcript.
- Exit `0`: done. Any other exit: she says "That didn't work:" and the last line.
- Exit `75`: "not mine". Echo One hands the command to the Voice Agent instead. `open-app.sh` uses this for "open …" when no app has that name.
- A script that runs longer than 30 seconds is stopped. Anything that should keep going (a timer, `caffeinate`) must run in the background with its output sent to `/dev/null`, or Echo One waits for it:

```bash
nohup caffeinate -di >/dev/null 2>&1 &
```

## Test an action

Run it in Terminal the way Echo One does. The last line printed is what she'll say:

```bash
cd ~/Documents/Echo\ One\ Actions && ./my-action.sh "the words after the name"; echo "exit $?"
```

## For agents building an action

1. Write one file into `~/Documents/Echo One Actions/` named after the title in kebab case, such as `open-nhl-site.sh`, and make it executable (`chmod +x`).
2. Include `schemaVersion`, `title` and `mode`, plus `@echo.phrases` for the two or three most natural ways to say it.
3. End by printing one short spoken sentence. Exit non-zero with a short reason on failure.
4. Add `@raycast.needsConfirmation true` if it deletes, sends, quits or can't be undone.
5. Test it with the command above. Don't run anything destructive to test it.

Examples: every file in [`actions/`](actions/). Good ones to copy: `battery.sh` (reads and speaks), `kill-port.sh` (takes an argument), `empty-trash.sh` (asks first), `open-app.sh` (exit 75), `timer.sh` (runs in the background).
