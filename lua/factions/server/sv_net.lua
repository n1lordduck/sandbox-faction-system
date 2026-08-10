local SFS = SandboxFactionSystem

local NET_COOLDOWNS = {}
local NET_CD_TIMES = {
    SFS_CreateFaction       = 3,
    SFS_DeleteFaction       = 3,
    SFS_UpdateFaction       = 2,
    SFS_KickMember          = 1.5,
    SFS_ApproveMember       = 1,
    SFS_DenyMember          = 1,
    SFS_RequestJoin         = 3,
    SFS_JoinPublic          = 3,
    SFS_LeaveFacton         = 3,
    SFS_PromoteMember       = 1.5,
    SFS_SendAllyRequest     = 3,
    SFS_AcceptAllyRequest   = 1.5,
    SFS_DeclineAllyRequest  = 1.5,
    SFS_RemoveAlly          = 2,
    SFS_AdminDeleteFaction  = 2,
    SFS_UpdatePermissions   = 2,
    SFS_ToggleFriendlyFire  = 1,
    SFS_SetMemberRank       = 1.5,
    SFS_TransferOwnership   = 5,
    SFS_UpdateRankLabels    = 2,
    SFS_UpdateStrings       = 2,
    SFS_UpdateGroups        = 2,
    SFS_AddSubOwner         = 1.5,
    SFS_RemoveSubOwner      = 1.5,
    SFS_AdminForceJoin      = 2,
    SFS_AdminForceLeave     = 2,
    SFS_ToggleHalo          = 1,
}

local function checkCooldown(ply, netName)
    local sid = ply:SteamID()
    NET_COOLDOWNS[sid] = NET_COOLDOWNS[sid] or {}
    local last = NET_COOLDOWNS[sid][netName] or 0
    local cd = NET_CD_TIMES[netName] or 1
    local now = CurTime()
    if now - last < cd then
        return false
    end
    NET_COOLDOWNS[sid][netName] = now
    return true
end

local function syncAllToPlayer(ply)
    local json = util.TableToJSON(SFS.Factions)
    net.Start("SFS_SyncAll")
    net.WriteString(json)
    net.Send(ply)
end

local function sendStringsToPlayer(ply)
    net.Start("SFS_UpdateStrings")
    net.WriteString(util.TableToJSON(SFS.Strings))
    net.Send(ply)
end

SFS.PlayerLangPrefs = SFS.PlayerLangPrefs or {}

net.Receive("SFS_SetLangPref", function(_, ply)
    if not IsValid(ply) then return end
    local pref = net.ReadString()
    if pref == "" then
        SFS.PlayerLangPrefs[ply:SteamID64()] = nil
    elseif SFS.LangPresets[pref] then
        SFS.PlayerLangPrefs[ply:SteamID64()] = pref
    end
end)

hook.Add("PlayerDisconnect", "SFS_CleanupLangPref", function(ply)
    SFS.PlayerLangPrefs[ply:SteamID64()] = nil
end)

function SFS.LangFor(ply)
    if not IsValid(ply) then return nil end
    return SFS.PlayerLangPrefs[ply:SteamID64()]
end

function SFS.StringFor(ply, key)
    local lang = SFS.LangFor(ply)
    if lang and SFS.LangPresets[lang][key] then
        return SFS.LangPresets[lang][key]
    end
    return SFS.Strings[key] or key
end

function SFS.FormatStringFor(ply, key, vars)
    local str = SFS.StringFor(ply, key)
    for k, v in pairs(vars or {}) do
        str = str:gsub("{" .. k .. "}", tostring(v))
    end
    str = str:gsub("{addonprefix}", SFS.StringFor(ply, "AddonPrefix"))
    return str
end

function SFS.GetErrorFor(ply, code)
    local key = SFS.ErrorKeys[code]
    if not key then return "Error: " .. tostring(code) end
    return SFS.StringFor(ply, key)
end

local function sendError(ply, code)
    net.Start("SFS_ChatMsg")
    net.WriteUInt(1, 4)
    net.WriteString(SFS.StringFor(ply, "AddonPrefix") .. " " .. SFS.GetErrorFor(ply, code))
    net.Send(ply)
end

net.Receive("SFS_CreateFaction", function(len, ply)
    if not checkCooldown(ply, "SFS_CreateFaction") then return end
    local name     = net.ReadString()
    local desc     = net.ReadString()
    local icon     = net.ReadString()
    local isPublic = net.ReadBool()
    local ok, err  = SFS.CreateFaction(ply, name, desc, icon, isPublic)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_DeleteFaction", function(len, ply)
    if not checkCooldown(ply, "SFS_DeleteFaction") then return end
    local factionID = net.ReadString()
    local faction   = SFS.GetFactionByID(factionID)
    if not faction then return end
    if faction.owner ~= ply:SteamID() then sendError(ply, "no_permission") return end
    SFS.DeleteFaction(factionID, ply:Nick(), "Owner disbanded faction", ply, true)
end)

net.Receive("SFS_AdminDeleteFaction", function(len, ply)
    if not checkCooldown(ply, "SFS_AdminDeleteFaction") then return end
    if not SFS.HasGroupPerm(ply, "delete_faction") then sendError(ply, "no_permission") return end
    local factionID = net.ReadString()
    local reason    = net.ReadString()
    SFS.DeleteFaction(factionID, ply:Nick(), reason, ply, false)
end)

net.Receive("SFS_UpdateFaction", function(len, ply)
    if not checkCooldown(ply, "SFS_UpdateFaction") then return end
    local factionID = net.ReadString()
    local dataJSON  = net.ReadString()
    local data      = util.JSONToTable(dataJSON) or {}
    local ok, err   = SFS.UpdateFaction(ply, factionID, data)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_KickMember", function(len, ply)
    if not checkCooldown(ply, "SFS_KickMember") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local ok, err   = SFS.KickMember(ply, steamid, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_ApproveMember", function(len, ply)
    if not checkCooldown(ply, "SFS_ApproveMember") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local ok, err   = SFS.ApproveMember(ply, steamid, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_DenyMember", function(len, ply)
    if not checkCooldown(ply, "SFS_DenyMember") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local ok, err   = SFS.DenyMember(ply, steamid, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_RequestJoin", function(len, ply)
    if not checkCooldown(ply, "SFS_RequestJoin") then return end
    local factionID = net.ReadString()
    local ok, err   = SFS.RequestJoin(ply, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_JoinPublic", function(len, ply)
    if not checkCooldown(ply, "SFS_JoinPublic") then return end
    local factionID = net.ReadString()
    local ok, err   = SFS.JoinFaction(ply, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_LeaveFacton", function(len, ply)
    if not checkCooldown(ply, "SFS_LeaveFacton") then return end
    local ok, err = SFS.LeaveFaction(ply)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_PromoteMember", function(len, ply)
    if not checkCooldown(ply, "SFS_PromoteMember") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local newRank   = net.ReadString()
    local ok, err   = SFS.SetMemberRank(ply, steamid, factionID, newRank)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_SetMemberRank", function(len, ply)
    if not checkCooldown(ply, "SFS_SetMemberRank") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local newRank   = net.ReadString()
    local ok, err   = SFS.SetMemberRank(ply, steamid, factionID, newRank)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_AddSubOwner", function(len, ply)
    if not checkCooldown(ply, "SFS_AddSubOwner") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local ok, err   = SFS.SetSubOwner(ply, steamid, factionID, true)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_RemoveSubOwner", function(len, ply)
    if not checkCooldown(ply, "SFS_RemoveSubOwner") then return end
    local factionID = net.ReadString()
    local steamid   = net.ReadString()
    local ok, err   = SFS.SetSubOwner(ply, steamid, factionID, false)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_ToggleFriendlyFire", function(len, ply)
    if not checkCooldown(ply, "SFS_ToggleFriendlyFire") then return end
    local factionID = net.ReadString()
    local value     = net.ReadBool()
    local ok, err   = SFS.ToggleFriendlyFire(ply, factionID, value)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_ToggleHalo", function(len, ply)
    if not checkCooldown(ply, "SFS_ToggleHalo") then return end
    local factionID = net.ReadString()
    local value     = net.ReadBool()
    local ok, err   = SFS.ToggleHalo(ply, factionID, value)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_SendAllyRequest", function(len, ply)
    if not checkCooldown(ply, "SFS_SendAllyRequest") then return end
    local factionID       = net.ReadString()
    local targetFactionID = net.ReadString()
    local message         = net.ReadString()
    local ok, err         = SFS.SendAllyRequest(ply, factionID, targetFactionID, message)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_AcceptAllyRequest", function(len, ply)
    if not checkCooldown(ply, "SFS_AcceptAllyRequest") then return end
    local factionID          = net.ReadString()
    local requesterFactionID = net.ReadString()
    local ok, err            = SFS.AcceptAllyRequest(ply, factionID, requesterFactionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_DeclineAllyRequest", function(len, ply)
    if not checkCooldown(ply, "SFS_DeclineAllyRequest") then return end
    local factionID          = net.ReadString()
    local requesterFactionID = net.ReadString()
    local ok, err            = SFS.DeclineAllyRequest(ply, factionID, requesterFactionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_RemoveAlly", function(len, ply)
    if not checkCooldown(ply, "SFS_RemoveAlly") then return end
    local factionID       = net.ReadString()
    local targetFactionID = net.ReadString()
    local ok, err         = SFS.RemoveAlly(ply, factionID, targetFactionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_UpdatePermissions", function(len, ply)
    if not checkCooldown(ply, "SFS_UpdatePermissions") then return end
    local factionID = net.ReadString()
    local permsJSON = net.ReadString()
    local perms     = util.JSONToTable(permsJSON) or {}
    local ok, err   = SFS.UpdatePermissions(ply, factionID, perms)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_TransferOwnership", function(len, ply)
    if not checkCooldown(ply, "SFS_TransferOwnership") then return end
    local factionID  = net.ReadString()
    local targetSID  = net.ReadString()
    local ok, err    = SFS.TransferOwnership(ply, targetSID, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_UpdateRankLabels", function(len, ply)
    if not checkCooldown(ply, "SFS_UpdateRankLabels") then return end
    local factionID  = net.ReadString()
    local labelsJSON = net.ReadString()
    local labels     = util.JSONToTable(labelsJSON) or {}
    local ok, err    = SFS.UpdateRankLabels(ply, factionID, labels)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_UpdateGroups", function(len, ply)
    if not checkCooldown(ply, "SFS_UpdateGroups") then return end
    if not SFS.HasGroupPerm(ply, "edit_groups") then sendError(ply, "no_permission") return end
    local json = net.ReadString()
    local t    = util.JSONToTable(json)
    if not t then return end
    if type(t.superadmin) == "table" then
        local cleaned = {}
        for _, v in ipairs(t.superadmin) do
            if type(v) == "string" and #v > 0 and #v <= 64 then
                cleaned[#cleaned + 1] = v
            end
        end
        SFS.Config.SuperAdminGroups = cleaned
    end
    if type(t.admin) == "table" then
        local cleaned = {}
        for _, v in ipairs(t.admin) do
            if type(v) == "string" and #v > 0 and #v <= 64 then
                cleaned[#cleaned + 1] = v
            end
        end
        SFS.Config.AdminGroups = cleaned
    end
    local data = util.TableToJSON({ superadmin = SFS.Config.SuperAdminGroups, admin = SFS.Config.AdminGroups })
    file.Write("sandbox_factions/groups.json", data)
end)

net.Receive("SFS_UpdateStrings", function(len, ply)
    if not checkCooldown(ply, "SFS_UpdateStrings") then return end
    if not SFS.HasGroupPerm(ply, "edit_strings") then sendError(ply, "no_permission") return end
    local json = net.ReadString()
    local t    = util.JSONToTable(json)
    if not t then return end
    for k, v in pairs(t) do
        if SFS.Strings[k] ~= nil and type(v) == "string" then
            SFS.Strings[k] = v
        end
    end
    local data = util.TableToJSON(SFS.Strings)
    file.Write("sandbox_factions/strings.json", data)
    for _, p in ipairs(player.GetAll()) do
        sendStringsToPlayer(p)
    end
end)

net.Receive("SFS_Ping", function(len, ply)
    local x = net.ReadFloat()
    local y = net.ReadFloat()
    local z = net.ReadFloat()
    if x ~= x or y ~= y or z ~= z then return end
    local absLimit = 32768
    if math.abs(x) > absLimit or math.abs(y) > absLimit or math.abs(z) > absLimit then return end
    local steamid = ply:SteamID()
    local faction = SFS.GetPlayerFaction(steamid)
    if not faction then return end

    local pos = Vector(x, y, z)
    for _, member in ipairs(player.GetAll()) do
        if not IsValid(member) then continue end
        local mSID = member:SteamID()
        if mSID == steamid then continue end
        if faction.owner == mSID
        or (faction.subowners and faction.subowners[mSID])
        or (faction.members  and faction.members[mSID]) then
            net.Start("SFS_PingReceive")
            net.WriteFloat(pos.x) net.WriteFloat(pos.y) net.WriteFloat(pos.z)
            net.WriteString(ply:Nick())
            net.Send(member)
        end
    end
end)

net.Receive("SFS_AdminForceJoin", function(len, ply)
    if not checkCooldown(ply, "SFS_AdminForceJoin") then return end
    if not SFS.HasGroupPerm(ply, "force_join") then sendError(ply, "no_permission") return end
    local targetSID = net.ReadString()
    local factionID = net.ReadString()
    local targetPly = SFS.FindPlayerBySteamID(targetSID)
    if not IsValid(targetPly) then return end
    local ok, err = SFS.AdminForceJoin(ply, targetPly, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_AdminForceLeave", function(len, ply)
    if not checkCooldown(ply, "SFS_AdminForceLeave") then return end
    if not SFS.HasGroupPerm(ply, "force_leave") then sendError(ply, "no_permission") return end
    local targetSID = net.ReadString()
    local factionID = net.ReadString()
    local targetPly = SFS.FindPlayerBySteamID(targetSID)
    if not IsValid(targetPly) then return end
    local ok, err = SFS.AdminForceLeave(ply, targetPly, factionID)
    if not ok then sendError(ply, err) end
end)

net.Receive("SFS_FactionChat", function(len, ply)
    local msg = net.ReadString()
    if not msg or #msg == 0 or #msg > 250 then return end
    local steamid = ply:SteamID()
    local faction = SFS.GetPlayerFaction(steamid)
    if not faction then return end

    local recipients = {}
    for _, p in ipairs(player.GetAll()) do
        if not IsValid(p) then continue end
        local sid = p:SteamID()
        if sid == faction.owner
        or (faction.subowners and faction.subowners[sid])
        or (faction.members   and faction.members[sid]) then
            recipients[#recipients + 1] = p
        end
    end

    for _, p in ipairs(recipients) do
        net.Start("SFS_FactionChat")
        net.WriteString(msg)
        net.WriteString(ply:Nick())
        net.WriteString(faction.name)
        net.Send(p)
    end
end)

local function sendConfigToPlayer(ply)
    local cfg = {
        AllowImgurPictures  = SFS.Config.AllowImgurPictures,
        FriendlyFireDefault = SFS.Config.FriendlyFireDefault,
        FactionMaxAllies    = SFS.Config.FactionMaxAllies,
        WarDuration         = SFS.Config.WarDuration or 3600,
        IconMaxSizeMB       = SFS.Config.IconMaxSizeMB or 20,
    }
    net.Start("SFS_SyncConfig")
    net.WriteString(util.TableToJSON(cfg))
    net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "SFS_SyncOnJoin", function(ply)
    timer.Simple(2, function()
        if IsValid(ply) then
            syncAllToPlayer(ply)
            sendStringsToPlayer(ply)
            sendConfigToPlayer(ply)
        end
    end)
end)

timer.Create("SFS_AutoSave", SFS.Config.SaveInterval, 0, function()
    SFS.SaveFactions()
end)

SFS:print("Net receivers loaded")

hook.Add("PlayerSay", "SFS_InterceptFactionChat", function(ply, text, teamChat)
    local body = text:match("^/p (.+)") or text:match("^/faction (.+)")
    if not body then return end

    local steamid = ply:SteamID()
    local faction = SFS.GetPlayerFaction(steamid)
    if not faction then
        sendError(ply, "not_in_faction")
        return ""
    end

    if #body == 0 or #body > 250 then return "" end

    local recipients = {}
    for _, p in ipairs(player.GetAll()) do
        if not IsValid(p) then continue end
        local sid = p:SteamID()
        if sid == faction.owner
        or (faction.subowners and faction.subowners[sid])
        or (faction.members   and faction.members[sid]) then
            recipients[#recipients + 1] = p
        end
    end

    for _, p in ipairs(recipients) do
        net.Start("SFS_FactionChat")
        net.WriteString(body)
        net.WriteString(ply:Nick())
        net.WriteString(faction.name)
        net.Send(p)
    end

    return ""
end)

local factionAnnounceCD = {}

net.Receive("SFS_FactionAnnounce", function(len, ply)
    local msg = net.ReadString()
    if not msg or #msg == 0 or #msg > 250 then return end

    local sid = ply:SteamID()
    local faction = SFS.GetPlayerFaction(sid)
    if not faction then sendError(ply, "not_in_faction") return end
    local rank = SFS.GetPlayerRankInFaction(sid, faction)
    if rank ~= "owner" and rank ~= "subowner" then sendError(ply, "no_permission") return end

    local now = CurTime()
    if factionAnnounceCD[sid] and now - factionAnnounceCD[sid] < 3600 then
        local remaining = math.ceil(3600 - (now - factionAnnounceCD[sid]))
        local m = math.floor(remaining / 60)
        local s = remaining % 60
        net.Start("SFS_ChatMsg")
        net.WriteUInt(1, 4)
        net.WriteString(string.format("%s Announce cooldown: %02d:%02d remaining.", SFS.StringFor(ply, "AddonPrefix"), m, s))
        net.Send(ply)
        return
    end

    factionAnnounceCD[sid] = now

    for _, p in ipairs(player.GetAll()) do
        if not IsValid(p) then continue end
        net.Start("SFS_FactionAnnounce")
        net.WriteString(faction.name)
        net.WriteString(msg)
        net.Send(p)
    end

    SFS:print("Faction announce by " .. ply:Nick() .. " (" .. faction.name .. "): " .. msg)
end)
