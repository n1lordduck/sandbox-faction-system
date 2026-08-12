# Sandbox Factions - Architecture

Global namespace: `SandboxFactionSystem` (aliased everywhere as `local SFS = SandboxFactionSystem`). Public API for other addons: `SFA` (see bottom of `sv_init.lua`).

## Load order

`lua/autorun/factions.lua` drives the whole include chain:

```
SHARED (both realms, in this order)
  sh_framework.lua      -- SFS:print/warn/err
  sh_lang_presets.lua   -- loads lua/factions/languages/*.lua into SFS.LangPresets
  sh_config.lua         -- SFS.Config, SFS.Strings (server-default language), SFS.FormatString
  sh_net.lua            -- registers every net string (SERVER only, via util.AddNetworkString)
  sh_errors.lua         -- SFS.ErrorKeys (error code -> lang key) + SFS.GetError

SERVER only
  sv_data.lua           -- factions.dat persistence, rank/perm lookups
  sv_factions.lua       -- core faction CRUD (create/join/kick/promote/ally/...)
  sv_net.lua            -- net.Receive handlers, per-player language resolution
  sv_init.lua           -- convars, debug concommands, SFA public API
  sv_war.lua            -- war state machine + persistence
  sv_war_net.lua        -- war net.Receive handlers
  sv_group_perms.lua    -- staff-level (usergroup) permissions, separate from faction ranks

CLIENT only
  cl_data.lua           -- SFS.CL cache, chat rendering, personal language pref
  cl_halo.lua           -- halo + off-screen indicators for faction mates/allies
  cl_ping.lua           -- ping key + 3D/2D ping rendering
  cl_panel.lua          -- the entire VGUI faction panel (~2000 lines, all tabs)
  cl_keybind.lua        -- toolgun menu entry, !factions chat command, desktop icon
  cl_notify.lua         -- toast notification popups
  cl_war_data.lua       -- SFS.CL.Wars cache
  cl_war_panel.lua      -- War tab UI
```

Because `sh_lang_presets.lua` loads before `sh_config.lua`, `SFS.Strings` (the server-default language table) is built by copying `SFS.LangPresets[SFS.DefaultLangID]` - there's no hardcoded English table duplicated anywhere.

## Data model

Everything lives in two flat tables, both plain Lua tables (JSON-compressed to disk, JSON-decompressed to the wire):

**`SFS.Factions[id]`** (id = `"fac_<time>_<rand>"`):
```lua
{
    id, name, desc, icon, owner,           -- owner = SteamID string
    subowners   = { [steamid] = true },
    members     = { [steamid] = { rank = "admin"|"mod"|"member", joined = unixtime } },
    ranks       = { admin = {label,color}, mod = {...}, member = {...} },  -- custom labels
    permissions = { admin = {approve=bool, kick=bool}, mod = {approve=bool, kick=bool} },
    allies          = { [factionID] = true },
    allyRequests    = { [factionID] = { fromName, message, time } },
    requests        = { [steamid] = { nick, time } },   -- pending join requests
    friendlyFire, haloEnabled, public,
}
```

**`SFS.Wars[warID]`** (id = `"war_<time>_<rand>"`):
```lua
{
    id, side1 = {[facID]=true}, side2 = {[facID]=true},
    side1Leader, side2Leader,             -- the two factions that actually declared
    side1Kills, side2Kills,
    startTime, endTime, truceRequested,   -- "side1" | "side2" | nil
    ended, endReason,                     -- "truce" | "time" | "wipe"
    winner,                               -- "side1" | "side2" | nil
}
```

There is exactly **one rank hierarchy**: `owner` > `subowner` > custom ranks (`admin`, `mod` by default, renameable via `ranks[key].label`) > `member`. Owner/subowner can always do everything; `admin`/`mod` can only do what `faction.permissions[rank][action]` explicitly grants. This is checked independently on **both** client (to decide what UI to show) and server (the actual authority) - see "Permission model" below for why both copies have to agree.

## Persistence

All under `data/sandbox_factions/`:

| File | Written by | Contents |
|---|---|---|
| `factions.dat` | `sv_data.lua` (`SFS.SaveFactions`) | `util.Compress(json(SFS.Factions))` |
| `wars.dat` | `sv_war.lua` | `util.Compress(json(SFS.Wars))` |
| `group_perms.json` | `sv_group_perms.lua` | staff usergroup → action map (see below) |
| `strings.json` | `sv_net.lua` (`SFS_UpdateStrings` handler) | flat override of `SFS.Strings`, reapplied on top of the default-language table at boot |
| `faction_admin_actions.txt` | `sv_data.lua` (`SFS.LogAdminAction`) | plaintext audit log for staff faction-deletions |

Auto-save timer (`SFS_AutoSave`, `sv_net.lua`) runs every `Config.SaveInterval` (300s); every mutating action also saves immediately.

## Networking pattern

Two sync strategies, chosen per message:

- **Full-state broadcast** (`SFS_SyncAll`) - sent once on `PlayerInitialSpawn`. Every client gets the entire `SFS.Factions` table.
- **Delta broadcast** (`SFS_SyncFaction`) - sent after *any* mutation to *one* faction, to *everyone*. Payload is either the updated faction JSON or the literal string `"__DELETED__"`. Clients merge this into their local `SFS.CL.Factions` cache and fire the `SFS_FactionsUpdated` hook, which every open UI element listens to for live refresh.

There is no true delta/diffing - "delta" here just means "resync one faction's full row" rather than the whole table. Wars use the identical pattern (`SFS_WarSync` / `SFS_WarsFullSync` / `SFS_WarRemoved`).

Every mutating net receiver in `sv_net.lua` is rate-limited per player per net-string via `NET_COOLDOWNS` (a plain `{steamid: {netname: lastCurTime}}` table checked in `checkCooldown`). War actions use a separate, smaller cooldown table in `sv_war_net.lua`.

## Permission model

Two **independent** permission layers - don't confuse them:

1. **Faction ranks** (`faction.permissions[rank].approve` / `.kick`) - set per-faction by the owner in Manage Faction → Rank Permissions. Governs join-request approval and member kicking for the `admin`/`mod` ranks. Owner/subowner bypass this entirely and can always do both.
2. **Staff usergroups** (`SFS.GroupPerms[usergroup][action]`, `sv_group_perms.lua`) - server-wide, keyed by GMod usergroup (`superadmin`, `admin`, ...), not faction rank. Governs cross-faction admin actions: `delete_faction`, `force_join`, `force_leave`, `edit_strings`, `edit_groups`, `set_war_duration`, icon-cache actions. Checked via `SFS.HasGroupPerm(ply, action)`. This is what gates the Staff Panel tab and the Strings/Language editor.

**Important invariant**: any check against `faction.permissions[rank][action]` must exist **identically on both realms** - the client uses it to decide whether to even show the relevant button/section (join-request list, kick context menu), and the server independently re-validates before acting. If either side only implements this for one rank name (e.g. checks `"admin"` but forgets `"mod"`), the result is a rank that has the permission granted in the UI but silently can't use it - this exact bug existed in `ApproveMember`/`DenyMember`/`AcceptAllyRequest` (server only checked the `admin` branch) and in the client's request-list/kick-menu gating (checked rank name instead of the permission table at all). Fixed, but worth remembering as the shape of bug this system is prone to if a new permission-gated action is added without mirroring both checks.

## War system

`SFS.DeclareWar(declarerPly, targetFacID)` (`sv_war.lua`):

1. Validates: declarer owns a faction, target exists and isn't the declarer's own faction, neither side already at war, target isn't an ally (checked both directions).
2. **Validates the target faction has at least one member currently online** (`getOnlineWarMembers`) - declaring on an empty/offline faction is rejected with `target_offline` before a war object is ever created. (Without this, the 5-second wipe-check below would auto-win the war on its first tick against a faction that was simply offline.)
3. Builds `side1`/`side2` by adding the declarer's/target's faction plus each side's *direct* allies (one level, not transitive).
4. Creates the war, saves, broadcasts, starts a repeating timer (`WAR_CHECK_RATE = 5s`) that ends the war by:
   - **time** - `os.time() >= endTime`
   - **wipe** - one side has zero currently-online members (checked live, every tick)
   - **truce** - both leaders request it (`SFS.RequestTruce`); a non-leader ally can unilaterally withdraw instead of needing consensus.

Kills are tracked via the `PlayerDeath` hook, matched against whichever war (if any) has the killer and victim on opposite sides, incrementing `side1Kills`/`side2Kills` for the UI's kill-count bar.

## Localization

Three layers, resolved differently depending on **who the message is for**:

- **`SFS.LangPresets[langid]`** - read-only, loaded once from `lua/factions/languages/*.lua` (shared realm), each file a plain `return { ... }` table rather than JSON since Steam Workshop's addon whitelist doesn't allow `.json` under `lua/`. Adding a new language is just dropping in another file with the same key set plus a `_label` field; nothing else needs to change since the admin panel's language dropdown and `Lang.GetAllKeys()`-style lookups are all driven by whatever's discovered on disk.
- **`SFS.Strings`** - the server's *active* default language. Initialized from `LangPresets[SFS.DefaultLangID]` (`"english"`), then overwritten in bulk by whatever the admin last saved via the Strings panel (persisted to `strings.json`, reapplied on boot). There is no per-language override storage - saving always overwrites the single active `SFS.Strings` table, which is why picking a different preset in the admin panel is implemented as "fill every field from that preset, then save" rather than "switch active language ID."
- **`SFS.PlayerLangPrefs[SteamID64]`** - server-side, populated when a client sends `SFS_SetLangPref` (on join, and whenever they change it in Settings). Only affects messages sent to **that one player individually** via `net.Send(ply)` - resolved through `SFS.StringFor(ply, key)` / `SFS.FormatStringFor(ply, key, vars)` / `SFS.GetErrorFor(ply, code)`, all in `sv_net.lua`, falling back to `SFS.Strings` if the player has no preference or their preset lacks that key.

**Broadcast messages cannot be personalized.** Anything sent via `broadcastChat`/`net.Broadcast()` (faction created/disbanded, someone joined/left/kicked, alliance formed, war declared/ended) is formatted **once**, server-side, using `SFS.FormatString` (no `ply` argument, no per-player resolution) and sent identically to every connected client. Making these personalizable would require sending the raw key + args over the wire and formatting client-side per-recipient - a protocol change, not a lookup change. This is a deliberate architectural boundary, not an oversight: it's why `SFS.FormatString` (global) and `SFS.FormatStringFor` (per-player) are two separate functions rather than one.

Client-side, the mirror of this is `SFS.CL.StringFor(key)` / `SFS.CL.GetError(code)` (`cl_data.lua`) - used for the handful of messages the client itself renders locally without a server round-trip (e.g. the `/p` "you are not in a faction" chat error), which *can* respect `SFS.CL.LangPref` (a persisted `FCVAR_ARCHIVE`-style ClientConVar) immediately, with no server involvement at all.

One known gap: `sendNotify(...)` toast popups (join-request/approved/kicked/rank-change) are hardcoded Portuguese strings in `sv_factions.lua`, never routed through the lang-key system at all - unlike the chat-message equivalents of those same events, which are fully localized. Fixing this means adding new keys to all three language files, not just rewiring existing ones.

## Client-side caching

`cl_data.lua` maintains a small derived cache (`_cachedMyFaction`, `_cachedMates`, `_cachedAllies`) recomputed lazily - invalidated on `SFS_FactionsUpdated`/`PlayerDisconnected`, rebuilt on the next `Think` that finds it invalid. This exists purely so the halo renderer (`cl_halo.lua`, runs every frame in `PreDrawHalos`/`HUDPaint`) and the ping system don't re-scan `SFS.CL.Factions` + `player.GetAll()` every single frame.

## Icon caching

Faction icons are either a built-in `icon16/*.png` path or a custom image URL (imgur only, gated by `sfa_allow_imgur_pictures` and size-capped by `sfa_icon_max_size_mb`). Everything lives in `cl_panel.lua`:

- `iconMatCache[url]` / `iconFetching[url]` - module-level, in-memory, keyed by the raw URL. `SFS.CL.GetIconMatSync(url)` returns whatever's cached right now (or the default icon); `SFS.CL.GetIconMatAsync(url, pnl)` kicks off a fetch if needed and, once resolved, sets `pnl._mat` directly and calls `pnl:InvalidateLayout(true)` - every icon-displaying panel's `Paint` reads `self._mat` live, which is what makes an icon pop in once its fetch finishes instead of needing the panel reopened. A panel with a fetch genuinely in flight and nothing cached yet shows a spinning `icon16/arrow_refresh.png` instead of just silently sitting on the default.
- `fetchImageMaterial(url, onReady)` - the actual fetch: memory cache, then on-disk cache (`data/sfs_icons/<hash>.png`, controlled by `sfs_icon_cache`), then `http.Fetch`. A cached file that fails to load as a valid material gets deleted rather than retried forever.
- `urlToFilename(url)` (exposed as `SFS.CL.UrlToIconFilename`) - the one place that turns a URL into its cache filename: `url:lower():gsub("[^%w]", "_"):sub(1, 60) .. ".png"`. The `:lower()` matters - GMod's file system silently lowercases paths on write, so `file.Find` later returns the lowercase name regardless of what case the original URL was in. Every place that needs to compare a URL against an on-disk filename (the Staff Panel's icon browser, the per-icon delete button) goes through this same function instead of recomputing the hash inline, specifically so that fix can't quietly regress in one call site while staying fixed in another.
- `SFS.CL.GetIconFactionName(iconFileName)` (`cl_data.lua`) - reverse lookup for the Staff Panel's icon browser, matching a cached filename back to whichever faction is currently using that URL. Checks a small saved map (`data/sfs_icons/icon_faction_map.json`, rebuilt on every `SFS_FactionsUpdated` from `SFS.CL.Factions`) first, then falls back to scanning `SFS.CL.Factions` directly.

`cl_war_panel.lua` uses the exact same `SFS.CL.GetIconMatSync`/`GetIconMatAsync` pair for the war-entry faction icons rather than keeping its own separate cache - two independent caches for the same URLs used to mean an icon fetched in one panel wouldn't be known about in the other.

## UI structure (`cl_panel.lua`)

One `DFrame` (`SFS.OpenMainPanel`, bound to `!factions`/`/factions`/toolgun menu), with tabs added conditionally:

| Tab | Always shown? | Contents |
|---|---|---|
| Factions | yes | browse all factions, join public / request private |
| War | yes | active wars, kill bars, declare/truce buttons |
| My Faction | only if in one | member list, join-request approval, friendly-fire/halo toggles |
| Manage Faction | only if owner/subowner | rank labels, permissions grid, allies, war declare, announcements |
| Create Faction | only if not in one | - |
| Staff Panel | only if `HasGroupPerm(..., "force_join")` or superadmin | cross-faction admin tools, Strings/Language editor, icon cache browser |
| Settings | yes | client-only convars: notifications, icon cache, ping sound, halo-on-self, personal language override |

Every tab except Factions is lazy: `AddSheet` gets an empty placeholder panel, and the real content is only built the first time that tab is actually selected (`DPropertySheet:OnActiveTabChanged`). Factions is built immediately since `AddSheet` auto-activates whichever sheet is added first. This exists because `DPropertySheet:AddSheet` requires an already-built panel - building all six tabs' full content synchronously on every single panel open (member lists, forms, the whole Settings tab) was the actual cause of a noticeable stutter when opening the panel, not something related to icon loading.

The panel rebuilds itself wholesale (`SFS.OpenMainPanel()` called again) whenever your own faction membership or rank changes while it's open, rather than trying to patch the existing tab set in place. The hook driving this (`SFS_FactionsUpdated` -> `"SFS_RebuildPanel"`) uses one constant name, not a per-panel-instance one - there's only ever one main panel, so each open replaces the previous registration instead of leaking a new uniquely-named hook that only gets cleaned up lazily on its next fire. A tab's own internal content does not automatically refresh just because the outer panel didn't rebuild - if a tab needs to reflect live data changes while it stays open (the Factions browse list, the Staff Panel's icon browser), it registers its own `SFS_FactionsUpdated` hook scoped to that tab's panel.
