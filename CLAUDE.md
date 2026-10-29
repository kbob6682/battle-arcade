# Battle Arcade

## Project
- Engine: Godot 4.7.2 (standard build, GDScript), installed with winget. Godot 4 APIs only; never Godot 3 syntax.
- Renderer: Compatibility. The target is the web export, with thread support turned off (GitHub Pages can't send the headers threaded web builds need).
- Godot CLI: `C:\Users\Caleb\AppData\Local\Microsoft\WinGet\Links\godot_console.exe`
- Backend: a Cloudflare Worker in `worker/` (TypeScript, Wrangler). Durable Objects handle room codes and WebRTC signalling. D1 holds profiles, PIN sign-in, stats and match results.
- Networking: peer-to-peer WebRTC (`WebRTCPeerConnection` / `WebRTCMultiplayerPeer`), Google's public STUN servers, no TURN for now.
- Hosting: GitHub Pages, published from this repo on GitHub.
- Design doc: `Design Doc.md` in the vault project folder (see Vault docs).

## Repo layout
- The Godot project is at the repo root (`project.godot`).
- `core/`: lobby, room codes, networking, messages, the opponent interface and bot base, profiles client.
- `games/<game_name>/`: one folder per mini game (scenes, scripts, data), e.g. `games/gem_battle/`.
- `ui/`, `assets/` (art, audio, fonts), `addons/`, `docs/` (repo-only technical notes, never copies of vault notes).
- `worker/`: the Cloudflare Worker. Keep a `.gdignore` file in it so Godot doesn't import it.

## How I work
- I'm new to game dev but an experienced network engineer. Explain Godot-specific concepts briefly when you first use them.
- Work in small, playable increments. Propose a plan and wait for approval before multi-file changes.
- After code changes, run a headless check: `"C:\Users\Caleb\AppData\Local\Microsoft\WinGet\Links\godot_console.exe" --path . --headless --quit`, and fix any errors before handing back. For the Worker, run its type check and tests.
- I playtest in the editor and the browser and report results. Don't claim something works visually or over the network; tell me what to check.
- Commit after each working step with a clear message. Never force-push or rewrite history.
- Ask before adding a Godot addon or an npm dependency, and say why it's needed.

## Testing multiplayer
- WebRTC works natively in web exports. Desktop and editor runs need the webrtc-native GDExtension in `addons/`. Ask me before adding it.
- For quick tests, run two instances from the editor (Debug > Customize Run Instances). Before calling a networking step done, test a web export in two browser windows, then on two computers.
- Run the Worker locally with `npx wrangler dev`. Only deploy when I ask.

## Architecture rules
- The core app is built once. Each mini game plugs in through one shared interface: start with a seed, send and receive messages, report a result. Adding a game must not change lobby or networking code.
- A game talks to an "opponent" that is either the remote peer or a local bot, through the same messages. Every mini game ships with Easy, Medium and Hard bots.
- Each player's game is in charge of its own board, tower or tank, and only small messages are sent. The host sends a shared random seed at the start, and anything both sides must agree on uses a seeded `RandomNumberGenerator`.
- Messages are small and typed, and carry a message type and a protocol version.
- Both clients report each match result, and the Worker counts it only if the reports agree. Bot matches never affect rankings.
- Emotes and quick chat are preset IDs only. Never add free-text chat.
- Use Input Map actions only; never hard-code keys. Keyboard and mouse now, controllers later.

## Cost rules
- $0: free tiers only (Cloudflare free plan, GitHub Pages). Never suggest adding a payment card or upgrading to Workers Paid. Tell me if a design would go over a free-tier limit.

## Kids' data and security
- Players are kids aged 10 to 16. Collect the minimum: player name, colour, PIN hash, stats and badges. No email, no real names, no free text.
- Never store a PIN. Store only a salted, slow hash (PBKDF2 through Web Crypto in the Worker). Lock the account for a few minutes after several wrong PINs. After sign-in, use tokens, not PINs.
- Stats, badges and rankings attach to a hidden random player ID, never to the name. Sign-in methods are stored separately and linked to that ID.
- Never put secrets, tokens, API keys or Cloudflare account IDs in code, config examples or commits. Use `wrangler secret` and a gitignored `.dev.vars`. Never ask me to paste secrets into the chat.

## Vault docs
My notes for this project live in my Obsidian vault at `C:\Users\Caleb\Documents\The Diagram - Dev\54 Game Development\Projects\Battle Arcade`, attached through `.claude/settings.local.json`. They are the source of truth: don't keep copies of them in this repo.
- Read `Design Doc.md` and `00 Overview.md` before planning features.
- At the end of each session, or when I say we're done, add an entry at the top of `Devlog.md` in the format already used there (goal, done, what broke, commits, next).
- When a design choice is made or changed, add a row to the Decisions table in `00 Overview.md`.
- Keep the Open Items list and Milestones table in `00 Overview.md` current: tick items when they're done, and add new ones as `- [ ] ... #task/project`.
- Ask before changing `Design Doc.md`, and show me the change first.
- Only edit notes in that folder, and don't create new notes there without asking. Keep each note's frontmatter, use `[[wikilinks]]`, and never write passwords, keys or other secrets into the vault.

## Code conventions
- GDScript with static typing everywhere (`var speed: float`, `func f(x: int) -> void`).
- snake_case for files, functions and variables; PascalCase for classes and node names.
- One script per scene root where possible; prefer composition (child component nodes) and signals over deep inheritance and `get_parent()` chains.
- Autoloads only for true app-wide services (networking, session, profile). Mini games must not reach into each other.
- Don't edit `.tscn` files for scenes I'm laying out visually unless I ask. Tell me which scene to close first.
- Never commit `.godot/`, export builds, `node_modules/`, `.wrangler/`, `.dev.vars` or `.claude/settings.local.json`.

## Scope
Phase 1 (core app) was signed off on 2026-10-26. Phase 2 (Gem Battle, Drop and Swap with bots, in `games/gem_battle/`) is built; playtesting and tuning with the kids continue. Phase 3 is Tug of War, Classic mode first, with Easy, Medium and Hard bots, in `games/tug_of_war/` (chosen before Tower Toss on 2026-10-29). Every game plugs in through the existing mini game interface; change core code only if the interface is missing something every game would need, and say so first. Don't start profiles, rankings, badges, emotes, Tug of War Chaos mode or other mini games until I ask. Later phases follow the Development Plan in the design doc, one game at a time.

## Current focus
Phase 3: Tug of War Classic is built and needs playtesting; Gem Battle tuning (Step 7) continues alongside.
