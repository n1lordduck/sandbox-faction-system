local SFS = SandboxFactionSystem

SFS.Factions  = SFS.Factions  or {}
SFS.PlayerData = SFS.PlayerData or {}

local SAVE_DIR    = "sandbox_factions/"
local FACTION_FILE = SAVE_DIR .. "factions.dat"
local STRINGS_FILE = SAVE_DIR .. "strings.json"

local function ensureDir()
    if not file.IsDir(SAVE_DIR, "DATA") then file.CreateDir(SAVE_DIR) end
end

function SFS.SaveFactions()
    ensureDir()
    local data = util.Compress(util.TableToJSON(SFS.Factions))
    file.Write(FACTION_FILE, data)
    SFS:print("Factions saved (" .. #data .. " bytes compressed)")
end

function SFS.LoadFactions()
    ensureDir()
    if not file.Exists(FACTION_FILE, "DATA") then
        SFS:print("No faction save found, starting fresh")
        return
    end
    local raw = file.Read(FACTION_FILE, "DATA")
    if not raw or raw == "" then SFS:warn("Faction file empty") return end
    local decompressed = util.Decompress(raw)
    if not decompressed then SFS:err("Failed to decompress faction data") return end
    local loaded = util.JSONToTable(decompressed)
    if loaded then
        SFS.Factions = loaded
        SFS:print("Factions loaded: " .. table.Count(SFS.Factions))
    end
end

function SFS.LoadStrings()
    ensureDir()
    if not file.Exists(STRINGS_FILE, "DATA") then
        return
    end
    local raw = file.Read(STRINGS_FILE, "DATA")
    if not raw or raw == "" then
        SFS:warn("Strings file is empty, using defaults")
        return
    end
    local t = util.JSONToTable(raw)
    if t then
        local count = 0
        for k, v in pairs(t) do
            if SFS.Strings[k] ~= nil and type(v) == "string" then
                SFS.Strings[k] = v
                count = count + 1
            end
        end
    else
        SFS:warn("Failed to parse strings.json, using defaults")
    end
end

function SFS.LoadGroups()
    ensureDir()
    local path = SAVE_DIR .. "groups.json"
    if not file.Exists(path, "DATA") then return end
    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return end
    local t = util.JSONToTable(raw)
    if not t then return end
    if type(t.superadmin) == "table" and #t.superadmin > 0 then SFS.Config.SuperAdminGroups = t.superadmin end
    if type(t.admin) == "table"      and #t.admin > 0      then SFS.Config.AdminGroups       = t.admin      end
    SFS:print("Permission groups loaded")
end

function SFS.GetFactionByID(id)   return SFS.Factions[id] end

function SFS.GetFactionByName(name)
    local low = name:lower()
    for _, f in pairs(SFS.Factions) do
        if f.name:lower() == low then return f end
    end
    return nil
end

function SFS.GetPlayerFaction(steamid)
    for _, f in pairs(SFS.Factions) do
        if f.owner == steamid then return f end
        if f.subowners and f.subowners[steamid] then return f end
        if f.members and f.members[steamid] then return f end
    end
    return nil
end

function SFS.GetPlayerRankInFaction(steamid, faction)
    if not faction then return nil end
    if faction.owner == steamid then return "owner" end
    if faction.subowners and faction.subowners[steamid] then return "subowner" end
    if faction.members and faction.members[steamid] then
        return faction.members[steamid].rank or "member"
    end
    return nil
end

function SFS.IsSuperAdmin(ply)
    if not IsValid(ply) then return false end
    for _, g in ipairs(SFS.Config.SuperAdminGroups) do
        if ply:IsUserGroup(g) then return true end
    end
    return false
end

function SFS.IsAdmin(ply)
    if not IsValid(ply) then return false end
    for _, g in ipairs(SFS.Config.AdminGroups) do
        if ply:IsUserGroup(g) then return true end
    end
    return false
end

function SFS.GenerateFactionID()
    return "fac_" .. os.time() .. "_" .. math.random(1000, 9999)
end

function SFS.LogAdminAction(staff, action, factionName, reason)
    local entry = os.date("[%Y-%m-%d %H:%M:%S]") .. " Staff: " .. tostring(staff)
        .. " | Action: " .. tostring(action)
        .. " | Faction: " .. tostring(factionName)
        .. " | Reason: " .. tostring(reason) .. "\n"
    local existing = file.Read(SFS.Config.AdminLogFile, "DATA") or ""
    file.Write(SFS.Config.AdminLogFile, existing .. entry)
    SFS:print("Admin action logged: " .. entry)
end

SFS:print("Data module loaded")
