# Sandbox Factions

<p align="center">
  <img src="https://img.shields.io/badge/language-Lua-blue?style=for-the-badge&logo=lua">
  <img src="https://img.shields.io/badge/status-in%20development-yellow?style=for-the-badge">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/platform-GMod-lightgrey?style=for-the-badge">
</p>

A full-featured faction system for Garry's Mod. Create factions, manage members and ranks, form alliances, declare wars, and see your teammates and allies through walls.

## Mysterious features or weird stuff

This project wasn't public originally, and had many, many changes before coming to the actual version it is right now, so stuff that might seem weird or that is "impossible to exist" in some way is pretty normal, although i tried to manually find those cases and remove them from the codebase.

^ This addon was private and made for my server only, therefore there was a bunch of "ugly" workarounds so i could deliver features on time and other stuff - but they should be gone by now.

## Features

- Public or invite-only factions with a customizable rank hierarchy (Owner, Sub-Owner, and two renameable custom ranks) and a granular per-rank permission system controlling who can approve join requests and who can kick members.
- A separate, server-wide staff permission layer (by GMod usergroup) for cross-faction admin actions, independent of any single faction's own internal ranks.
- Alliances (up to a configurable max per faction) and a full war system: declare war on another faction and its allies are automatically pulled in on both sides, kills are tracked per side, and a war ends by timeout, mutual truce, or by one side running out of online members. Declaring war on a faction with nobody online is blocked outright.
- Faction halos and off-screen indicators for teammates and allies, a ping system, and optional per-faction friendly fire.
- Full multi-language support (English, Portuguese, Spanish out of the box) covering every server-broadcast message and every error. Players can set a personal language preference that overrides the server default for messages sent directly to them - errors, your own join-request status - while broadcast messages to everyone always use the server's configured language.
- An in-game Strings panel for admins to edit any server message by hand, with one-click language presets.

## Installation

Clone (or download and extract) this repository into your server's `garrysmod/addons/` folder - the addon's `lua/` folder needs to sit directly at the addon's root.

```bash
git clone https://github.com/n1lordduck/sandbox-faction-system.git garrysmod/addons/sandbox-factions
```

## Usage

- `!factions` (or `/factions` in chat, or through the sandbox toolgun menu) opens the faction panel.
- Superadmins, or any usergroup granted the relevant staff permission, get an additional Staff Panel tab for cross-faction administration and the Strings/Language editor.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for how the addon is structured internally - the data model, persistence, the two-layer permission system, and the war state machine.

## Directory Structure

* `lua/factions/shared` - config, error messages, language presets, and shared networking setup.
* `lua/factions/server` - faction/war state, persistence, and every `net.Receive` handler.
* `lua/factions/client` - the faction panel, halo/ping rendering, and chat integration.
* `lua/factions/languages` - the shipped translation files (`english.json`, `ptbr.json`, `spanish.json`). Adding a new language is just dropping in another JSON file with the same key set.

## License

This project is licensed under the MIT License - see [LICENSE](./LICENSE).
