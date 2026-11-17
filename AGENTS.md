# AGENTS.md

Echo One is a macOS dictation app with a Voice Agent. Build notes for working on the app itself are in [docs/development.md](docs/development.md).

## Building an Echo Action

Echo Actions are voice commands that run one script each. To write one for a user, read [ECHO-ACTIONS.md](ECHO-ACTIONS.md) and follow it: the file format, how arguments arrive, what gets spoken, and how to test. Save the script in the user's `~/Documents/Echo One Actions/` folder. The built-ins in [`actions/`](actions/) are working examples to copy from.
