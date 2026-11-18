<a href="https://echooneapp.vercel.app"><picture><source media="(max-width: 600px)" srcset="./docs/media/readme/hero-sm.webp"><img src="./docs/media/readme/hero.webp" alt="Talk to your Mac. It talks back. A MacBook on a stone desk in a high-rise. Echo One's notch says: I've made the draft to Rob and opened it in TextEdit. It's saved on your desktop. TextEdit shows the draft and the new file sits on the desktop."></picture></a>

<div align="center">

<br>

**Echo One** is free, on-device dictation for Mac. Hold a key, talk, it types.<br>
Plus a voice for the Claude Code or Codex you already have.

<br>

<a href="https://github.com/hg913488/ECHO_ONE/releases/latest/download/EchoOne.dmg"><picture><source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Download_for_Mac-f2f5f4?style=for-the-badge&logo=apple&logoColor=101417"><img src="https://img.shields.io/badge/Download_for_Mac-101417?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac"></picture></a>

```bash
brew install hg913488/tap/echo-one
```

<br>

[![Latest release](https://img.shields.io/github/v/release/hg913488/ECHO_ONE?label=version&color=101417)](https://github.com/hg913488/ECHO_ONE/releases/latest)
&nbsp;
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-101417)
&nbsp;
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1%2B-101417)
&nbsp;
[![License: MIT](https://img.shields.io/badge/License-MIT-00a594)](LICENSE)

</div>

<br>

## Hold two keys. Ask. Hear it answer.

Hold **Right Command + Right Shift** and ask your Mac to do something: *"draft an email to Rob and put it on my desktop"*, *"what's in my notes folder"*, *"rename these screenshots by date"*. Echo One hands it to the Claude Code or Codex already signed in on your Mac, and answers out loud while it works.

No new account and no API key. It runs on the plan you already pay for.

<img src="./docs/media/voice-agent.gif" alt="Holding right Command and right Shift, someone asks Echo One to draft an email to Rob and put it on the desktop. The notch answers out loud, TextEdit opens with the draft, and the file appears on the desktop.">

<sub>The Voice Agent ships in the app. Its source isn't public.</sub>

<br><br>

<picture>
  <source media="(max-width: 600px) and (prefers-color-scheme: dark)" srcset="./docs/media/readme/dictation-dark-sm.webp">
  <source media="(max-width: 600px)" srcset="./docs/media/readme/dictation-light-sm.webp">
  <source media="(prefers-color-scheme: dark)" srcset="./docs/media/readme/dictation-dark.webp">
  <img src="./docs/media/readme/dictation-light.webp" alt="And it types. Anywhere you can type. Hold, talk, let go: hold right Command + right Option and the words land at your cursor, in any app. Fillers out: um and uh are cut, and the punctuation goes in. Stays on your Mac: speech-to-text runs on your Mac, no Claude, no account. You say um hi Priya the drawings are basically done. It types: Hi Priya, the drawings are done.">
</picture>

Slack, Notion, Mail, Terminal: wherever the cursor is. 25 languages with the default Parakeet model, and a small local model can tidy the text as it goes.

<br>

<picture>
  <source media="(max-width: 600px) and (prefers-color-scheme: dark)" srcset="./docs/media/readme/actions-dark-sm.webp">
  <source media="(max-width: 600px)" srcset="./docs/media/readme/actions-light-sm.webp">
  <source media="(prefers-color-scheme: dark)" srcset="./docs/media/readme/actions-dark.webp">
  <img src="./docs/media/readme/actions-light.webp" alt="Echo Actions. Quick jobs, done in about a second. Some things don't need an AI. Say one of these and a prewritten script on your Mac does it straight away. 33 come built in: dark mode, timer 5 minutes, battery, mute, volume to 40, lock screen, empty trash, open downloads, copy last screenshot, keep awake, Wi-Fi off, speed test, kill port 3000 and more.">
</picture>

<img src="./docs/media/echo-actions.gif" alt="Someone says &quot;dark mode&quot;. The notch shows the Echo Action, says &quot;Dark mode is on.&quot;, and the Mac switches to dark mode.">

Add your own, one script file each. They use the same format as Raycast script commands, so your Raycast scripts work by voice too. [How to write one ↓](#write-an-echo-action)

<br>

<picture>
  <source media="(max-width: 600px) and (prefers-color-scheme: dark)" srcset="./docs/media/readme/touch-dark-sm.webp">
  <source media="(max-width: 600px)" srcset="./docs/media/readme/touch-light-sm.webp">
  <source media="(prefers-color-scheme: dark)" srcset="./docs/media/readme/touch-dark.webp">
  <img src="./docs/media/readme/touch-light.webp" alt="What the Voice Agent can touch. Access: you choose what she can touch, from Ask only, Edit files, Sandbox to Full. Ask only reads files and searches the web to answer and can't change anything. Your agent: runs on the agent you already have, no API key needed. Private: dictation never leaves this Mac.">
</picture>

It acts on your Mac from a few spoken words, and speech gets misheard. So it has guard rails:

- **It's told never to delete.** Anything it removes should go to the Trash, where Put Back restores it. For Claude Code, delete commands, force-pushes and hard resets are blocked outright, at every level.
- **It's told to ask before anything leaves your Mac.** Sending, pushing, publishing or buying should wait for you to say yes.
- **It's told never to say a secret out loud.** Passwords and keys should stay off the speaker.
- **AI can still get things wrong.** These rules lower the risk; they don't remove it. Check its work and keep backups.
- **Your own scripts ask first.** A new Echo Action asks before its first run, and again after you edit it.
- **Stop it any time.** Say "stop", press Esc, or click the reply card.

<br>

<picture>
  <source media="(max-width: 600px) and (prefers-color-scheme: dark)" srcset="./docs/media/readme/looks-dark-sm.webp">
  <source media="(max-width: 600px)" srcset="./docs/media/readme/looks-light-sm.webp">
  <source media="(prefers-color-scheme: dark)" srcset="./docs/media/readme/looks-dark.webp">
  <img src="./docs/media/readme/looks-light.webp" alt="Voice Agent ring: three rings to pick from, Echo One, Original and Ember. Each one moves with her voice. Dictation mark: four colours for the mark, Bone, Teal, Ember and Dusk, shown above the Dock while you dictate.">
</picture>

<br>

## Also in the box

**Meetings.** Start a session before a call. When it ends you get a transcript with speakers labelled, notes and a summary, saved as Markdown on your Mac.

**Instruction mode.** Hold Right Control and say what to do with the selected text: *"translate to French"*, *"make this formal"*, *"turn this into bullet points"*. Nothing selected? It writes new text at the cursor.

**Lives in your menu bar.** No Dock icon and no window to manage. Every shortcut can be changed in Settings.

<br>

## Privacy

Dictation, cleanup, meetings and the Voice Agent's voice all run on your Mac. No analytics, no tracking SDK, no Echo One account.

| | Where it runs |
|---|---|
| Speech-to-text | Your Mac (WhisperKit / FluidAudio) |
| Text cleanup and instruction mode | Your Mac (Qwen via LLM.swift) |
| Meeting transcripts and summaries | Your Mac, saved as Markdown |
| Voice Agent: your voice and its reply | Your Mac |
| Voice Agent: the text of your command | Your own Claude Code or Codex, under your own account |
| Echo Actions | Local scripts |
| Analytics and telemetry | None |

The internet is used for one-time model downloads from Hugging Face, the daily update check, and the Voice Agent's request to your own coding agent. The Voice Agent sends the files it reads in your chosen folder to that agent's provider, the same as using it in Terminal.

Don't take our word for it: point Claude at this repo and ask it to check. The prompt and the last result are in the [privacy audit](PRIVACY_AUDIT.md).

<br>

## Install

1. [Download Echo One](https://github.com/hg913488/ECHO_ONE/releases/latest/download/EchoOne.dmg) and drag it to Applications, or run `brew install hg913488/tap/echo-one`.
2. Open it and allow what it asks for:
   - **Microphone**, to hear you.
   - **Accessibility** and **Input Monitoring**, for the shortcuts and to paste.
   - **Automation**, the first time an Echo Action controls another app.
3. Hold Right Command + Right Option and talk.

The Voice Agent needs [Claude Code](https://claude.com/product/claude-code) or [Codex](https://developers.openai.com/codex) installed and signed in. Dictation doesn't.

Apple Silicon (M1 or later), macOS 14 or later. Signed with Developer ID and notarized by Apple. Updates arrive in the app.

<br>

## Write an Echo Action

One script with a few comment lines on top:

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open NHL Site
# @raycast.mode compact
# @echo.phrases open the nhl site, open my hockey site

open "https://example.com"
echo "Opened the NHL site."
```

Save it in `~/Documents/Echo One Actions/` and say its name. She says the last line it prints.

[ECHO-ACTIONS.md](ECHO-ACTIONS.md) explains the format for you or your agent, and [`actions/`](actions/) has every built-in to copy from. In the app, **Copy for Your Agent** puts the guide on your clipboard, ready to paste into Claude, ChatGPT or Codex.

<br>

## FAQ

<details>
<summary><b>Is it really free?</b></summary>
<br>
Yes. No subscription, no trial, no account. If it helps you, you can <a href="https://buymeacoffee.com/echoone">buy me a coffee</a>.
<br><br>
</details>

<details>
<summary><b>What's open source?</b></summary>
<br>
Dictation, meetings, instruction mode and Echo Actions, under the MIT licence. The Voice Agent ships in the app, but its source isn't public. The public code can lag behind the released app: right now it builds 2.5.2 dictation, with the 2.6 Echo Actions runner in `EchoOne/Agent/EchoActions.swift`.
<br><br>
</details>

<details>
<summary><b>Do I need Claude or ChatGPT?</b></summary>
<br>
Only for the Voice Agent. Dictation, meetings and Echo Actions work without either.
<br><br>
</details>

<details>
<summary><b>Does the Voice Agent cost extra?</b></summary>
<br>
No. It uses your existing Claude or ChatGPT plan through the Claude Code or Codex you already have signed in.
<br><br>
</details>

<details>
<summary><b>Which Macs?</b></summary>
<br>
Apple Silicon (M1 or later) on macOS 14 or later.
<br><br>
</details>

<details>
<summary><b>Where are my files?</b></summary>
<br>
Meeting notes go to the folder you pick. Voice Agent transcripts are in <code>~/Documents/Echo One Agent/</code>. Your Echo Actions are in <code>~/Documents/Echo One Actions/</code>.
<br><br>
</details>

<br>

## Build from source

```bash
git clone https://github.com/hg913488/ECHO_ONE.git
open EchoOne.xcodeproj
# Cmd+R to build and run
```

More in [docs/development.md](docs/development.md). What changed in each version: [CHANGELOG.md](CHANGELOG.md).

<br>

## Disclaimer

Echo One is free and comes as is, with no warranty. The Voice Agent acts on your Mac through your own Claude Code or Codex, and AI can get things wrong: you're in charge of what you ask it to do, so check its work and keep backups. Echo One isn't affiliated with Anthropic, OpenAI or Raycast. The full [terms of use](https://echooneapp.vercel.app/terms/).

<br>

## Credits

Echo One is a fork of [Ghost Pepper](https://github.com/matthartman/ghost-pepper) by Matt Hartman (MIT). Speech via [WhisperKit](https://github.com/argmaxinc/WhisperKit) and [FluidAudio](https://github.com/FluidInference/FluidAudio), text cleanup via [LLM.swift](https://github.com/eastriverlee/LLM.swift), updates via [Sparkle](https://sparkle-project.org/). The Echo Actions format comes from [Raycast script commands](https://github.com/raycast/script-commands). Licences for everything Echo One is built on are in [Acknowledgements](EchoOne/Acknowledgements.txt).

<br>

<a href="https://github.com/hg913488/ECHO_ONE/releases/latest/download/EchoOne.dmg"><img src="./docs/media/readme/night.webp" alt="The same MacBook at night. Its desktop is split: Voice Agent, hold right Command + right Shift: ask, your agent does it. Dictation, hold right Command + right Option: talk, it types. Dictation apps type. This one also answers."></a>

<div align="center">

<br>

<a href="https://github.com/hg913488/ECHO_ONE/releases/latest/download/EchoOne.dmg"><picture><source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Download_for_Mac-f2f5f4?style=for-the-badge&logo=apple&logoColor=101417"><img src="https://img.shields.io/badge/Download_for_Mac-101417?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac"></picture></a>

Made by one person. If you like it, [buy me a coffee](https://buymeacoffee.com/echoone), star the repo so more people find it,<br>or share an Echo Action you made in [Discussions](https://github.com/hg913488/ECHO_ONE/discussions).

**[echooneapp.vercel.app](https://echooneapp.vercel.app)**

</div>
