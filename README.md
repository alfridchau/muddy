# NewZMud

A native macOS MUD client, inspired by zMUD and classic Chinese wuxia worlds. Built with SwiftUI, AppKit, and Network.framework. Requires macOS 13 or later and Xcode's Swift toolchain.

## Open the app

```sh
./scripts/build-app.sh
open .build/NewZMud.app
```

You can also open `Package.swift` in Xcode and run the NewZMud target, or use `swift run`. Quit the running app before rebuilding its bundle.

## Connect to the local game

With the game in the sibling `../mud` folder and FluffOS built at `../mud/fluffos/build/bin/driver`, start the server in a separate terminal:

```sh
./scripts/run-local-mud.sh
```

Add a world with host `127.0.0.1` and port `6666` (UTF-8), select it, and click Connect. Follow the prompts shown by the game in the terminal. Password input uses a secure field when the server requests no echo; password replies are excluded from command history, terminal output, and automation, and are never saved. Empty Enter is supported for prompts.

The server also offers GBK Telnet on `5566` and a browser client at `http://127.0.0.1:8888/`. NewZMud currently uses UTF-8, so use `6666`. The browser client's address fields must also be set to the local host if you use it.

The launcher creates `data/.env` from the game's example only when missing and writes a loopback-only configuration to the ignored `log/new-zmud.local.ini`. Stop a foreground server with Control-C. Set `MUD_SERVER_DIR` to use another game directory. The optional AI service is separate.

## Terminal and input

- The native terminal grid renders standard and bright ANSI colors, 256 colors, true color, bold/italic/underline, and background colors. Chinese characters occupy two cells. It handles carriage returns, backspace, tabs, common cursor/erase/scroll commands, saved cursor positions, and alternate screens. Terminal type and actual window dimensions are sent through Telnet.
- Up/Down recall commands and restore an unsent draft when you return to the bottom of history. Tab and Shift-Tab cycle completion candidates from common commands, aliases, recent server words, and command history.
- Command-K focuses input, Command-F filters terminal rows, and Command-N adds a world. The terminal options menu changes text size or clears output.
- Drag to select terminal text; Command-C copies and Command-A selects all when the terminal has focus. A context menu also provides Copy and Select All.
- Scrolling up pauses automatic scrolling. New output leaves your reading position intact; click New output to return to the bottom.
- The selected world, saved worlds, text size, and each world's automation settings persist locally. Command history stays in memory and clears when switching worlds.

## Live game data

GMCP negotiation advertises NewZMud and its supported modules. The character panel accepts `Char.Vitals`, `Char.Status`/`Char.Name`, and `Room.Info`. For 炎黄群侠传 it maps `hp/max_hp`, `neili/max_neili`, `jing/max_jing`, `exp`, room names, areas, and exits. When available, room exits are highlighted and unavailable directions are disabled.

After receiving character or room data, or the game's `Core.Hello`, the client requests `Char.Vitals.Get` every three seconds while connected. Values remain empty until the server supplies them. Name/title only appear if the server sends them. Remote GUI/map download requests are not executed.

## Automation for each world

Open **Automation → Rules and shortcuts…**. Rules are saved separately for the selected world. Enter multiple commands on separate lines or separate them with semicolons.

| Feature | Example |
| --- | --- |
| Alias | Name `greet`, commands `say Hello $*;look $1`, invoked as `greet old man` |
| Trigger | Regex `^你感到饥饿`, commands `eat bread`; capture groups use `$1`…`$9`, `$0` is the full match |
| Timer | Commands `hp`, interval `30` seconds |
| Key binding | F1–F12, or a letter combined with Command, Option, or Control; runs its configured commands |
| Speedwalk | `/walk 2n3e` sends two north commands then three east commands; delay is configurable in Walking |

Aliases and keys work when invoked manually. After signing in, use **Automation → Enable triggers and timers** to start automatic rules for that connection. Triggers match complete incoming lines with ANSI controls removed and have a one-second cooldown. Timers repeat while enabled.

`/stop`, the Stop button, or Command-period cancels queued commands and disables triggers/timers. Password prompts and disconnects also stop automation; reconnecting does not resume it or replay commands. Alias recursion is limited, and queues/paths are limited to 100 commands. Walks use a time delay rather than waiting for a movement acknowledgment, so blocked exits or failed movement can affect the route.

## Connection recovery

When the connection drops, the recovery banner offers **Reconnect now** and keeps the terminal transcript visible. The server may ask you to sign in again. **Automation → Reconnect automatically** is an optional preference for each world; it retries up to five times after 3, 6, 12, 24, and 30 seconds. You can reconnect immediately during the countdown or cancel retries with the connection button. After the retry limit, use Reconnect to try again. Manual Disconnect never reconnects automatically. Credentials and commands are never replayed.

## Offline preview

The 笑傲江湖 world is a local UI preview with sample Chinese rooms and character values. Try `look`, `north`, `inventory`, `score`, or `help`, or use the compass. It does not connect to a game server. Aliases and key bindings can also be tried in the preview; automatic triggers/timers require a real connection.

## Checks and current limits

```sh
swift test
```

Tests cover packet boundaries, Telnet/GMCP framing, ANSI state, wide glyphs, cursor edits, aliases, triggers, paths, history/completion, and live loopback connections with a temporary test server. Network checks verify GMCP updates, timer/trigger actions, stopping on password mode, and reconnecting without replay; they do not create game accounts or access model services.

This is a practical ANSI terminal subset, not a complete xterm/VT emulator. Input uses submitted command lines. Legacy Chinese encodings, MCCP compression, sound, automatic mapping, and zMUD script import remain unimplemented. Unsupported Telnet options are refused. The local app bundle is for development; distribution signing and notarization are not configured.
