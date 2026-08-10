local SFS = SandboxFactionSystem

CreateConVar("sfa_allow_imgur_pictures",  "0", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Allow custom imgur images for faction icons")
CreateConVar("sfa_friendly_fire_default", "0", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Default friendly fire state (0=off, 1=on)")
CreateConVar("sfa_faction_max_allies",    "4",  FCVAR_ARCHIVE + FCVAR_NOTIFY, "Maximum allies a faction can have")
CreateConVar("sfa_icon_max_size_mb",      "20",   FCVAR_ARCHIVE + FCVAR_NOTIFY, "Maximum faction icon file size in MB (0 = unlimited)")
CreateConVar("sfs_faction_war_duration",   "3600", FCVAR_ARCHIVE + FCVAR_NOTIFY, "War duration in seconds (default 3600 = 1 hour)")

local function broadcastConfig()
    local cfg = {
        AllowImgurPictures = SFS.Config.AllowImgurPictures,
        FriendlyFireDefault = SFS.Config.FriendlyFireDefault,
        FactionMaxAllies = SFS.Config.FactionMaxAllies,
        WarDuration = SFS.Config.WarDuration or 3600,
    }
    net.Start("SFS_SyncConfig")
    net.WriteString(util.TableToJSON(cfg))
    net.Broadcast()
end

cvars.AddChangeCallback("sfa_allow_imgur_pictures",  function(_, _, new)
    SFS.Config.AllowImgurPictures  = tobool(new)
    broadcastConfig()
end)
cvars.AddChangeCallback("sfa_friendly_fire_default", function(_, _, new)
    SFS.Config.FriendlyFireDefault = tobool(new)
    broadcastConfig()
end)
cvars.AddChangeCallback("sfa_faction_max_allies",    function(_, _, new)
    SFS.Config.FactionMaxAllies    = tonumber(new) or 4
    broadcastConfig()
end)
cvars.AddChangeCallback("sfa_icon_max_size_mb", function(_, _, new)
    SFS.Config.IconMaxSizeMB = tonumber(new) or 20
    broadcastConfig()
end)
cvars.AddChangeCallback("sfs_faction_war_duration", function(_, _, new)
    SFS.Config.WarDuration = math.max(60, tonumber(new) or 3600)
    broadcastConfig()
end)

SFS.Config.AllowImgurPictures  = GetConVar("sfa_allow_imgur_pictures"):GetBool()
SFS.Config.FriendlyFireDefault = GetConVar("sfa_friendly_fire_default"):GetBool()
SFS.Config.FactionMaxAllies    = GetConVar("sfa_faction_max_allies"):GetInt()
SFS.Config.IconMaxSizeMB       = GetConVar("sfa_icon_max_size_mb"):GetInt()
SFS.Config.WarDuration         = math.max(60, GetConVar("sfs_faction_war_duration"):GetInt())

SFS.LoadFactions()
SFS.LoadGroups()
SFS.LoadStrings()
local function findPlayerPartial(name)
    local low = name:lower()
    for _, p in ipairs(player.GetAll()) do
        if p:Nick():lower():find(low, 1, true) then return p end
    end
    return nil
end

concommand.Add("sfa_fetch_factions", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    local count = table.Count(SFS.Factions)
    SFS:print("=== sfa_fetch_factions: " .. count .. " faction(s) ===")
    for id, f in pairs(SFS.Factions) do
        local memberCount = table.Count(f.members or {}) + table.Count(f.subowners or {}) + 1
        local allyCount   = table.Count(f.allies or {})
        local reqCount    = table.Count(f.requests or {})
        SFS:print(string.format("  [%s] name=%s owner=%s members=%d allies=%d joinreqs=%d public=%s ff=%s",
            id, f.name, f.owner, memberCount, allyCount, reqCount,
            tostring(f.public), tostring(f.friendlyFire)))
    end
    return util.TableToJSON(SFS.Factions)
end, nil, "Fetch and print all factions data")

concommand.Add("sfa_debug_strings", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    SFS:print("=== CURRENT STRINGS ===")
    for k, v in pairs(SFS.Strings) do
        SFS:print("  " .. k .. " = " .. tostring(v))
    end
end, nil, "Print all current faction strings")

concommand.Add("sfa_force_request_to_join", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    local pName = args[1] local fName = args[2]
    if not pName or not fName then SFS:warn("Usage: sfa_force_request_to_join <player> <faction>") return end
    local target = findPlayerPartial(pName)
    if not IsValid(target) then SFS:warn("Player not found: " .. pName) return end
    local faction = SFS.GetFactionByName(fName)
    if not faction then SFS:warn("Faction not found: " .. fName) return end
    local steamid = target:SteamID()
    if SFS.GetPlayerFaction(steamid) then SFS:warn(target:Nick() .. " already in a faction") return end
    if faction.requests[steamid] then SFS:warn(target:Nick() .. " already has a pending request") return end
    faction.requests[steamid] = { nick = target:Nick(), time = os.time() }
    SFS.SaveFactions()
    net.Start("SFS_SyncFaction") net.WriteString(faction.id) net.WriteString(util.TableToJSON(faction)) net.Broadcast()
end, nil, "Force a join request from a player to a faction")

concommand.Add("sfa_create_debug_faction", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    local factionName = args[1] local isPublicStr = args[2]
    if not factionName then SFS:warn("Usage: sfa_create_debug_faction <factionName> <yes/no>") return end
    local isPublic = isPublicStr and (isPublicStr:lower() == "yes" or isPublicStr == "1")
    if SFS.GetFactionByName(factionName) then SFS:warn("Faction already exists: " .. factionName) return end
    local id = "fac_debug_" .. os.time() .. "_" .. math.random(1000, 9999)
    local faction = {
        id = id, name = factionName, desc = "Debug faction", icon = SFS.Config.DefaultIconMaterial,
        owner = "STEAM_0:0:00000000", subowners = {}, public = isPublic,
        members = {
            ["STEAM_0:0:11111111"] = { rank = "admin",  joined = os.time() },
            ["STEAM_0:0:22222222"] = { rank = "mod",    joined = os.time() },
            ["STEAM_0:0:33333333"] = { rank = "member", joined = os.time() },
        },
        ranks = {
            admin  = { label = "Admin",     color = "255,150,0"   },
            mod    = { label = "Moderator", color = "0,180,255"   },
            member = { label = "Member",    color = "200,200,200" },
        },
        permissions = { admin = { approve = true, kick = true }, mod = { approve = false, kick = true } },
        allies = {}, allyRequests = {}, requests = {}, friendlyFire = false, haloEnabled = true,
    }
    SFS.Factions[id] = faction
    SFS.SaveFactions()
    net.Start("SFS_SyncFaction") net.WriteString(id) net.WriteString(util.TableToJSON(faction)) net.Broadcast()
end, nil, "Create a debug faction with mock data")

concommand.Add("sfa_force_player_rank", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    local pName = args[1] local newRank = args[2]
    if not pName or not newRank then SFS:warn("Usage: sfa_force_player_rank <player> <admin|mod|member>") return end
    if not ({ admin = true, mod = true, member = true })[newRank] then SFS:warn("Invalid rank") return end
    local target = findPlayerPartial(pName)
    if not IsValid(target) then SFS:warn("Player not found: " .. pName) return end
    local steamid = target:SteamID()
    local faction = SFS.GetPlayerFaction(steamid)
    if not faction then SFS:warn(target:Nick() .. " not in any faction") return end
    if faction.owner == steamid then SFS:warn("Cannot change owner rank") return end
    faction.members[steamid] = faction.members[steamid] or { joined = os.time() }
    faction.members[steamid].rank = newRank
    SFS.SaveFactions()
    net.Start("SFS_SyncFaction") net.WriteString(faction.id) net.WriteString(util.TableToJSON(faction)) net.Broadcast()
end, nil, "Set the rank of a player in their faction")

concommand.Add("faction_debug_list", function(ply)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    SFS:print("=== FACTION LIST ===")
    for id, f in pairs(SFS.Factions) do
        SFS:print(id .. " | " .. f.name .. " | Owner: " .. f.owner .. " | Members: " .. table.Count(f.members) .. " | FF: " .. tostring(f.friendlyFire))
    end
end, nil, "List all factions")

concommand.Add("faction_save", function(ply)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    SFS.SaveFactions()
end, nil, "Manually save all factions")

concommand.Add("faction_reload", function(ply)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    SFS.LoadFactions()
    SFS.LoadStrings()
    local json = util.TableToJSON(SFS.Factions)
    local strJson = util.TableToJSON(SFS.Strings)
    for _, p in ipairs(player.GetAll()) do
        net.Start("SFS_SyncAll") net.WriteString(json) net.Send(p)
        net.Start("SFS_UpdateStrings") net.WriteString(strJson) net.Send(p)
    end
end, nil, "Reload factions from disk and re-sync")

concommand.Add("faction_delete", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    local fName = args[1]
    if not fName then SFS:warn("Usage: faction_delete <factionName>") return end
    local faction = SFS.GetFactionByName(fName)
    if not faction then SFS:warn("Faction not found: " .. fName) return end
    SFS.DeleteFaction(faction.id, "SERVER_CONSOLE", "Debug deletion", nil, false)
end, nil, "Delete a faction by name")

concommand.Add("sfa_force_alliance_request", function(ply, cmd, args)
    if IsValid(ply) and not SFS.IsSuperAdmin(ply) then return end
    local fac1Name = args[1]
    local fac2Name = args[2]
    local message  = table.concat(args, " ", 3)
    if not fac1Name or not fac2Name then
        SFS:warn("Usage: sfa_force_alliance_request <faction1> <faction2> [message]")
        return
    end
    local fac1 = SFS.GetFactionByName(fac1Name)
    local fac2 = SFS.GetFactionByName(fac2Name)
    if not fac1 then SFS:warn("Faction not found: " .. fac1Name) return end
    if not fac2 then SFS:warn("Faction not found: " .. fac2Name) return end
    if fac1.id == fac2.id then SFS:warn("Cannot request alliance with itself") return end
    if fac1.allies and fac1.allies[fac2.id] then SFS:warn("Factions are already allies") return end
    fac2.allyRequests = fac2.allyRequests or {}
    if fac2.allyRequests[fac1.id] then SFS:warn("Alliance request already exists") return end
    fac2.allyRequests[fac1.id] = {
        fromName = fac1.name,
        message  = message and message:sub(1, 100) or "",
        time     = os.time(),
    }
    SFS.SaveFactions()
    net.Start("SFS_SyncFaction") net.WriteString(fac2.id) net.WriteString(util.TableToJSON(fac2)) net.Broadcast()
end, nil, "Force an alliance request between two factions")

SFS:print("Server init complete")

SFA = SFA or {}

SFA.GetFaction         = SFS.GetFactionByID
SFA.GetPlayerFaction   = SFS.GetPlayerFaction
SFA.GetPlayerRank      = SFS.GetPlayerRankInFaction
SFA.GetAllFactions     = function() return SFS.Factions end
SFA.IsAdmin            = SFS.IsAdmin
SFA.IsSuperAdmin       = SFS.IsSuperAdmin
SFA.GetWarByFaction    = SFS.GetWarByFaction
SFA.GetAllWars         = function() return SFS.Wars end
SFA.IsAtWar            = function(facID)
    local w = SFS.GetWarByFaction(facID)
    return w ~= nil
end
SFA.HasGroupPerm    = SFS.HasGroupPerm
SFA.AreAllied = function(facID1, facID2)
    local f = SFS.GetFactionByID(facID1)
    return f and f.allies and f.allies[facID2] == true
end

hook.Run("SFA.APIReady")
SFS:print("Public API (SFA) ready")
