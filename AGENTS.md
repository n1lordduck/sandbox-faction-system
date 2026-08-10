# AGENTS.md

Guidance for anyone (human or AI) writing code in this repo. The goal is a codebase that stays readable and cheap to change as it grows, not one that's clever.

## This is a multiplayer addon, not a script

Every net message is bandwidth spent against every connected player. Before adding or touching networking:

- Send the smallest payload that does the job, and to the smallest audience that needs it. Text resolved via `SFS.StringFor(ply, key)` / `SFS.FormatStringFor(ply, key, vars)` is sent to the one player who needs it in their own language - it is never broadcast server-wide, because broadcasts can't carry a per-player language at all. Reserve `net.Broadcast()` for things that are genuinely public state (faction rosters, war declarations), not player-facing messages.
- Don't add a new net string if an existing one can carry the data. Check `shared/sh_net.lua` for what already exists before adding to it.
- Rate-limit anything a player can trigger repeatedly. The faction-wide announcement (`SFS_FactionAnnounce`) has a real per-player cooldown enforced server-side, not just client-side, precisely because a naive implementation is a spam vector the moment a real server tests it.
- Chat/announce cooldowns, war-declaration checks, and similar guards belong on the server, never trusted from the client alone.

## Keep it simple

- Don't build an abstraction, config option, or generic system for a problem that has exactly one real use case today. Three similar lines beat a premature helper.
- Don't add error handling for situations that can't happen given how the code is actually called. Validate at real boundaries (network input, file reads, user text) - not everywhere defensively.
- Reuse the patterns already established (the per-faction rank permission system, the localization layer, the two-tier language resolution) instead of inventing a parallel mechanism for something that fits an existing one.

## The two permission layers are not interchangeable

This addon has two independent permission systems: per-faction rank permissions (`faction.permissions[rank].approve` / `.kick`, set by the faction owner) and server-wide staff usergroup permissions (`SFS.GroupPerms`, `sv_group_perms.lua`). A feature that's supposed to be gated by one is a real bug if it accidentally checks the other, and every gate needs to be mirrored on both the client (for UI visibility) and the server (for actual authorization) - a client-only check is not a permission check.

## Functions

- One function, one job. If a function's name is a verb phrase ("DeclareWar", "ApproveMember", "StringFor"), it should only do what that phrase says - no surprise side effects bolted on because it was convenient to put them there.
- If a function is doing more than one distinct thing, split it. A function that's grown past what fits on one screen is a signal to break it down, not a signal to add another `--` section header inside it.
- Name things for what they do, not how they're currently implemented.

## Comments

- Minimal. Default to none.
- The one exception is a hidden constraint or a WHY the code itself can't express - e.g. why a war can't be declared on a faction with zero online members, or why the offline-target check happens before the war object is even created.
- Never comment WHAT the code does. If a comment is just restating the next line in English, delete it.
- No decorative separators (`──────`, `======`, banner-style dividers) in comments. A plain one-line comment header is enough; this style was removed from the codebase for exactly this reason. Don't reintroduce it.
- No em-dashes. Use a plain hyphen or restructure the sentence.

## Bug fixes vs. features

- A bug fix changes exactly what's needed to fix the bug, in the files where the bug lives. Nothing else.
- If you notice an unrelated improvement, cleanup opportunity, or a feature idea while fixing something, don't fold it into the same change. Fix the bug first, ship that, then do the improvement as its own separate change with its own reasoning. Bundling makes both harder to review and harder to revert independently.

## Localization

- Any string a player can see goes through the language system (`SFS.StringFor` / `SFS.FormatStringFor` server-side, `SFS.CL.StringFor` client-side), never hardcoded in a single language. Broadcasts are the one deliberate exception - they use the server's default language because they have no single recipient to resolve a preference for.

## Maintainability signals worth noticing

- If adding a permission check requires touching both a client file and a server file and they can drift out of sync, that's expected here - make sure both actually got updated, not just the one you were looking at.
- If achieving something requires reading three files to understand what one function does, that function is doing too much or is misnamed.
