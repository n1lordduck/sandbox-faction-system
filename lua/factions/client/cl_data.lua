local SFS = SandboxFactionSystem

SFS.CL = SFS.CL or {}
SFS.CL.Factions      = {}
SFS.CL.IconCache     = {}
SFS.CL.IconLoadQueue = {}
SFS.CL.PingList      = {}
SFS.CL.PingKey       = CreateClientConVar("sfs_ping_key", tostring(SFS.Config.PingKey), true, false, "Faction ping key")
SFS.CL.LangPref      = CreateClientConVar("sfs_lang_pref", "", true, false, "Personal faction language preference override")

function SFS.CL.EffectiveLang()
    local pref = SFS.CL.LangPref:GetString()
    if pref ~= "" and SFS.LangPresets[pref] then return pref end
    return nil
end

function SFS.CL.StringFor(key)
    local lang = SFS.CL.EffectiveLang()
    if lang and SFS.LangPresets[lang][key] then
        return SFS.LangPresets[lang][key]
    end
    return SFS.Strings[key] or key
end

function SFS.CL.GetError(code)
    local key = SFS.ErrorKeys[code]
    if not key then return "Error: " .. tostring(code) end
    return SFS.CL.StringFor(key)
end

local function sendLangPref()
    net.Start("SFS_SetLangPref")
        net.WriteString(SFS.CL.LangPref:GetString())
    net.SendToServer()
end

cvars.AddChangeCallback("sfs_lang_pref", function() sendLangPref() end, "SFS_LangPrefChanged")

hook.Add("InitPostEntity", "SFS_SendLangPrefOnJoin", function()
    timer.Simple(2, sendLangPref)
end)

local _cachedMyFaction   = nil
local _cachedMates       = {}
local _cachedAllies      = {}
local _cachedMySteamID   = nil
local _cacheValid        = false

local function invalidateCache()
    _cacheValid      = false
    _cachedMyFaction = nil
    _cachedMates     = {}
    _cachedAllies    = {}
end

local function rebuildCache()
    _cachedMySteamID = LocalPlayer():SteamID()
    _cachedMyFaction = nil
    _cachedMates     = {}
    _cachedAllies    = {}

    for _, faction in pairs(SFS.CL.Factions) do
        if faction.owner == _cachedMySteamID then _cachedMyFaction = faction break end
        if faction.subowners and faction.subowners[_cachedMySteamID] then _cachedMyFaction = faction break end
        if faction.members and faction.members[_cachedMySteamID] then _cachedMyFaction = faction break end
    end

    if not _cachedMyFaction then _cacheValid = true return end

    local myFac  = _cachedMyFaction
    local allPly = player.GetAll()

    for _, ply in ipairs(allPly) do
        if not IsValid(ply) or ply == LocalPlayer() then continue end
        local sid = ply:SteamID()
        if myFac.owner == sid
        or (myFac.subowners and myFac.subowners[sid])
        or (myFac.members  and myFac.members[sid]) then
            _cachedMates[#_cachedMates + 1] = ply
        end
    end

    if myFac.allies then
        local seen = {}
        for _, ply in ipairs(allPly) do
            if not IsValid(ply) or ply == LocalPlayer() then continue end
            local sid = ply:SteamID()
            for allyID in pairs(myFac.allies) do
                local allyFac = SFS.CL.Factions[allyID]
                if allyFac and not seen[sid] then
                    if allyFac.owner == sid
                    or (allyFac.subowners and allyFac.subowners[sid])
                    or (allyFac.members  and allyFac.members[sid]) then
                        seen[sid] = true
                        _cachedAllies[#_cachedAllies + 1] = ply
                    end
                end
            end
        end
    end

    _cacheValid = true
end

hook.Add("SFS_FactionsUpdated", "SFS_InvalidateCache", invalidateCache)

hook.Add("Think", "SFS_RebuildCacheIfNeeded", function()
    if not _cacheValid then rebuildCache() end
end)

hook.Add("PlayerDisconnected", "SFS_InvalidateCacheOnLeave", function()
    invalidateCache()
end)

function SFS.CL.GetMyFaction()
    if not _cacheValid then rebuildCache() end
    return _cachedMyFaction
end

function SFS.CL.GetMyRank()
    local faction = SFS.CL.GetMyFaction()
    if not faction then return nil end
    local steamid = _cachedMySteamID or LocalPlayer():SteamID()
    if faction.owner == steamid then return "owner" end
    if faction.subowners and faction.subowners[steamid] then return "subowner" end
    if faction.members and faction.members[steamid] then
        return faction.members[steamid].rank or "member"
    end
    return nil
end

function SFS.CL.GetFactionByID(id)
    return SFS.CL.Factions[id]
end

function SFS.CL.GetFactionMates()
    if not _cacheValid then rebuildCache() end
    return _cachedMates
end

function SFS.CL.GetAlliesOf()
    if not _cacheValid then rebuildCache() end
    return _cachedAllies
end

function SFS.CL.LoadIcon(url, callback)
    if url == "" or url == SFS.Config.DefaultIconMaterial then
        callback(Material(SFS.Config.DefaultIconMaterial))
        return
    end

    if SFS.CL.IconCache[url] then
        callback(SFS.CL.IconCache[url])
        return
    end

    if SFS.CL.IconLoadQueue[url] then
        SFS.CL.IconLoadQueue[url][#SFS.CL.IconLoadQueue[url] + 1] = callback
        return
    end

    SFS.CL.IconLoadQueue[url] = { callback }
    local mat = Material(url, "noclamp smooth")
    SFS.CL.IconCache[url] = mat
    timer.Simple(0.5, function()
        if SFS.CL.IconLoadQueue[url] then
            for _, cb in ipairs(SFS.CL.IconLoadQueue[url]) do cb(mat) end
            SFS.CL.IconLoadQueue[url] = nil
        end
    end)
end

net.Receive("SFS_SyncAll", function()
    local json = net.ReadString()
    local data = util.JSONToTable(json)
    if data then
        SFS.CL.Factions = data
        SFS:print("Received full faction sync: " .. table.Count(SFS.CL.Factions) .. " factions")
        hook.Run("SFS_FactionsUpdated")
    end
end)

net.Receive("SFS_SyncFaction", function()
    local id   = net.ReadString()
    local json = net.ReadString()
    if json == "__DELETED__" then
        SFS.CL.Factions[id] = nil
        SFS:print("Faction removed: " .. id)
    else
        local faction = util.JSONToTable(json)
        if faction then
            SFS.CL.Factions[id] = faction
            SFS:print("Faction synced: " .. (faction.name or id))
        end
    end
    hook.Run("SFS_FactionsUpdated")
end)

local CLR_PREFIX = Color(220, 50, 50)
local CLR_WHITE  = Color(255, 255, 255)
local CLR_YELLOW = Color(255, 210, 80)
local CLR_ERROR  = Color(255, 100, 100)

local function parseChatMsg(raw, msgType)
    local rawPrefix, rawBody = raw:match("^(%[.-%]) ?(.+)$")
    local prefix = rawPrefix and (rawPrefix .. " ") or ""
    local body   = rawBody or raw

    if msgType == 1 then
        chat.AddText(CLR_PREFIX, prefix, CLR_ERROR, body)
        return
    end

    local highlighted = {}
    for _, f in pairs(SFS.CL.Factions) do
        if body:find(f.name, 1, true) then highlighted[f.name] = true end
    end
    for _, p in ipairs(player.GetAll()) do
        local nick = p:Nick()
        if body:find(nick, 1, true) then highlighted[nick] = true end
    end

    local sorted = {}
    for word in pairs(highlighted) do sorted[#sorted + 1] = word end
    table.sort(sorted, function(a, b) return #a > #b end)

    local hits = {}
    for _, word in ipairs(sorted) do
        local s, e = body:find(word, 1, true)
        if s then hits[#hits + 1] = { s = s, e = e, word = word } end
    end
    table.sort(hits, function(a, b) return a.s < b.s end)

    local pos    = 1
    local pieces = {}
    for _, hit in ipairs(hits) do
        if hit.s >= pos then
            if hit.s > pos then pieces[#pieces + 1] = { t = body:sub(pos, hit.s - 1), c = CLR_WHITE } end
            pieces[#pieces + 1] = { t = hit.word, c = CLR_YELLOW }
            pos = hit.e + 1
        end
    end
    if pos <= #body then pieces[#pieces + 1] = { t = body:sub(pos), c = CLR_WHITE } end

    local args = { CLR_PREFIX, prefix }
    for _, piece in ipairs(pieces) do
        args[#args + 1] = piece.c
        args[#args + 1] = piece.t
    end
    chat.AddText(unpack(args))
end

net.Receive("SFS_ChatMsg", function()
    local msgType = net.ReadUInt(4)
    local msg     = net.ReadString()
    parseChatMsg(msg, msgType)
end)

net.Receive("SFS_UpdateStrings", function()
    local json = net.ReadString()
    local t    = util.JSONToTable(json)
    if t then
        for k, v in pairs(t) do
            if SFS.Strings[k] ~= nil then SFS.Strings[k] = v end
        end
        hook.Run("SFS_StringsUpdated")
    end
end)

net.Receive("SFS_FactionChat", function()
    local msg     = net.ReadString()
    local nick    = net.ReadString()
    local facName = net.ReadString()
    chat.AddText(
        Color(80, 180, 255), "[" .. facName .. "] ",
        Color(255, 220, 100), nick .. ": ",
        Color(220, 220, 220), msg
    )
end)

hook.Add("OnPlayerChat", "SFS_FactionChatCommand", function(ply, msg, teamChat, dead)
    if ply ~= LocalPlayer() then return end
    local body = msg:match("^/p (.+)") or msg:match("^/faction (.+)")
    if not body then return end
    local myFac = SFS.CL.GetMyFaction()
    if not myFac then
        chat.AddText(Color(255, 100, 100), SFS.CL.StringFor("AddonPrefix") .. " " .. SFS.CL.GetError("not_in_faction"))
        return true
    end
    net.Start("SFS_FactionChat")
    net.WriteString(body)
    net.SendToServer()
    return true
end)

SFS:print("Client data module loaded")

net.Receive("SFS_SyncConfig", function()
    local t = util.JSONToTable(net.ReadString()) or {}
    if t.AllowImgurPictures  ~= nil then SFS.Config.AllowImgurPictures  = t.AllowImgurPictures  end
    if t.FriendlyFireDefault ~= nil then SFS.Config.FriendlyFireDefault = t.FriendlyFireDefault end
    if t.FactionMaxAllies    ~= nil then SFS.Config.FactionMaxAllies    = t.FactionMaxAllies    end
    if t.WarDuration         ~= nil then SFS.Config.WarDuration         = t.WarDuration         end
    if t.IconMaxSizeMB       ~= nil then SFS.Config.IconMaxSizeMB       = t.IconMaxSizeMB       end
    hook.Run("SFS_ConfigUpdated")
end)


local ICON_MAP_FILE = "sfs_icons/icon_faction_map.json"

local function saveIconMap()
    if not file.IsDir("sfs_icons", "DATA") then file.CreateDir("sfs_icons") end
    local t = {}
    for id, fac in pairs(SFS.CL.Factions) do
        if fac.icon and fac.icon ~= "" and fac.icon ~= SFS.Config.DefaultIconMaterial then
            t[id] = { name = fac.name, icon = fac.icon }
        end
    end
    file.Write(ICON_MAP_FILE, util.TableToJSON(t))
end

local function loadIconMap()
    if not file.Exists(ICON_MAP_FILE, "DATA") then return {} end
    return util.JSONToTable(file.Read(ICON_MAP_FILE, "DATA")) or {}
end

function SFS.CL.GetIconFactionName(iconFileName)
    local savedMap = loadIconMap()
    local urlKey   = iconFileName:gsub(".png$", ""):gsub("_", "[^%w]")
    for facID, entry in pairs(savedMap) do
        local mapped = entry.icon:gsub("[^%w]", "_"):sub(1, 60) .. ".png"
        if mapped == iconFileName then
            return entry.name
        end
    end
    for facID, fac in pairs(SFS.CL.Factions) do
        if fac.icon and fac.icon ~= "" then
            local mapped = fac.icon:gsub("[^%w]", "_"):sub(1, 60) .. ".png"
            if mapped == iconFileName then
                return fac.name
            end
        end
    end
    return nil
end

hook.Add("SFS_FactionsUpdated", "SFS_SaveIconMap", function()
    saveIconMap()
end)

SFS.CL.GroupPerms = {}

net.Receive("SFS_SyncGroupPerms", function()
    local json = net.ReadString()
    local t    = util.JSONToTable(json)
    if t then
        SFS.CL.GroupPerms = t
        hook.Run("SFS_GroupPermsUpdated")
    end
end)

function SFS.CL.HasGroupPerm(perm)
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    for group, perms in pairs(SFS.CL.GroupPerms) do
        if ply:IsUserGroup(group) and perms[perm] == true then
            return true
        end
    end
    return false
end
