local SFS = SandboxFactionSystem

local function broadcastFactionSync(faction)
    net.Start("SFS_SyncFaction")
    net.WriteString(faction.id)
    net.WriteString(util.TableToJSON(faction))
    net.Broadcast()
end

local function broadcastFactionRemoved(factionID)
    net.Start("SFS_SyncFaction")
    net.WriteString(factionID)
    net.WriteString("__DELETED__")
    net.Broadcast()
end

local function broadcastChat(msg, msgType)
    msgType = msgType or 0
    for _, ply in ipairs(player.GetAll()) do
        net.Start("SFS_ChatMsg")
        net.WriteUInt(msgType, 4)
        net.WriteString(msg)
        net.Send(ply)
    end
end
local function sendNotify(ply, notifType, message)
    if not IsValid(ply) then return end
    net.Start("SFS_Notify")
    net.WriteString(notifType)
    net.WriteString(message)
    net.Send(ply)
end


function SFS.CreateFaction(owner, name, desc, icon, isPublic)
    local steamid = owner:SteamID()
    if SFS.GetPlayerFaction(steamid) then return false, "already_in_faction" end
    if name:match("[%z%c]") or #name:gsub("%s","") == 0 then return false, "invalid_name" end
    if #name > SFS.Config.MaxFactionNameLength then return false, "name_too_long" end
    if #desc > SFS.Config.MaxFactionDescLength then return false, "desc_too_long" end
    if SFS.GetFactionByName(name) then return false, "name_taken" end

    if icon and icon ~= "" and icon ~= SFS.Config.DefaultIconMaterial then
        if not SFS.Config.AllowImgurPictures then
            icon = SFS.Config.DefaultIconMaterial
        elseif not icon:match("^https?://i%.imgur%.com/") and not icon:match("^https?://imgur%.com/") and not icon:match("^icon16/") then
            icon = SFS.Config.DefaultIconMaterial
        end
    end

    local id = SFS.GenerateFactionID()
    local faction = {
        id          = id,
        name        = name,
        desc        = desc,
        icon        = icon or SFS.Config.DefaultIconMaterial,
        owner       = steamid,
        subowners   = {},
        public      = isPublic == true,
        members     = {},
        ranks       = {
            admin  = { label = "Admin",     color = "255,150,0"   },
            mod    = { label = "Moderator", color = "0,180,255"   },
            member = { label = "Member",    color = "200,200,200" },
        },
        permissions = {
            admin = { approve = true,  kick = true  },
            mod   = { approve = false, kick = true  },
        },
        allies          = {},
        allyRequests    = {},
        requests        = {},
        friendlyFire    = SFS.Config.FriendlyFireDefault,
        haloEnabled     = true,
    }

    SFS.Factions[id] = faction
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastChat(SFS.FormatString("FactionCreated", { factionName = name }))
    SFS:print("Faction created: " .. name .. " by " .. owner:Nick())
    return true, id
end

function SFS.DeleteFaction(factionID, staffNick, reason, ply, isOwnerDisband)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local factionName = faction.name
    SFS.Factions[factionID] = nil
    SFS.SaveFactions()
    broadcastFactionRemoved(factionID)

    if isOwnerDisband then
        broadcastChat(SFS.FormatString("FactionDisbanded", { factionName = factionName }))
    else
        broadcastChat(SFS.FormatString("FactionDeleted", { factionName = factionName, staffName = staffNick, reason = reason }))
        SFS.LogAdminAction(staffNick, "DELETE", factionName, reason)
    end
    SFS:print("Faction deleted: " .. factionName .. " by " .. tostring(staffNick))
    return true
end

function SFS.JoinFaction(ply, factionID)
    local steamid = ply:SteamID()
    if SFS.GetPlayerFaction(steamid) then return false, "already_in_faction" end
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end
    if not faction.public then return false, "not_public" end

    faction.members[steamid] = { rank = "member", joined = os.time() }
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastChat(SFS.FormatString("PlayerJoinedFaction", { playerName = ply:Nick(), factionName = faction.name }))
    SFS:print(ply:Nick() .. " joined faction " .. faction.name)
    return true
end

function SFS.RequestJoin(ply, factionID)
    local steamid = ply:SteamID()
    if SFS.GetPlayerFaction(steamid) then return false, "already_in_faction" end
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end
    if faction.public then return false, "is_public" end
    if faction.requests[steamid] then return false, "already_requested" end

    faction.requests[steamid] = { nick = ply:Nick(), time = os.time() }
    SFS.SaveFactions()
    broadcastFactionSync(faction)

    net.Start("SFS_ChatMsg")
    net.WriteUInt(0, 4)
    net.WriteString(SFS.FormatStringFor(ply, "RequestSent", { factionName = faction.name }))
    net.Send(ply)

    local function notifyJoinRequest(target)
        if not IsValid(target) then return end
        sendNotify(target, "join_request",
            SFS.FormatStringFor(target, "NotifyJoinRequest", { playerName = ply:Nick(), factionName = faction.name }))
    end

    notifyJoinRequest(SFS.FindPlayerBySteamID(faction.owner))
    if faction.subowners then
        for sid, _ in pairs(faction.subowners) do
            notifyJoinRequest(SFS.FindPlayerBySteamID(sid))
        end
    end
    if faction.members then
        for sid, data in pairs(faction.members) do
            if data.rank == "admin" and faction.permissions and faction.permissions.admin and faction.permissions.admin.approve then
                notifyJoinRequest(SFS.FindPlayerBySteamID(sid))
            end
        end
    end
    SFS:print(ply:Nick() .. " requested to join " .. faction.name)
    return true
end

function SFS.ApproveMember(approver, steamid, factionID)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local approverSID = approver:SteamID()
    local rank = SFS.GetPlayerRankInFaction(approverSID, faction)
    if not rank then return false, "not_member" end

    local canApprove = rank == "owner" or rank == "subowner"
        or (faction.permissions["admin"] and faction.permissions["admin"].approve
            and faction.members[approverSID] and faction.members[approverSID].rank == "admin")
        or (faction.permissions["mod"]   and faction.permissions["mod"].approve
            and faction.members[approverSID] and faction.members[approverSID].rank == "mod")
    if not canApprove then return false, "no_permission" end

    faction.members[steamid] = { rank = "member", joined = os.time() }
    faction.requests[steamid] = nil
    SFS.SaveFactions()
    broadcastFactionSync(faction)

    local targetPly = SFS.FindPlayerBySteamID(steamid)
    if IsValid(targetPly) then
        net.Start("SFS_ChatMsg")
        net.WriteUInt(0, 4)
        net.WriteString(SFS.FormatStringFor(targetPly, "RequestApproved", { factionName = faction.name }))
        net.Send(targetPly)
        broadcastChat(SFS.FormatString("PlayerJoinedFaction", { playerName = targetPly:Nick(), factionName = faction.name }))
        sendNotify(targetPly, "approved", SFS.FormatStringFor(targetPly, "NotifyApproved", { factionName = faction.name }))
    end
    SFS:print(approver:Nick() .. " approved " .. steamid .. " into " .. faction.name)
    return true
end

function SFS.DenyMember(approver, steamid, factionID)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local approverSID = approver:SteamID()
    local rank = SFS.GetPlayerRankInFaction(approverSID, faction)
    if not rank then return false, "not_member" end

    local canApprove = rank == "owner" or rank == "subowner"
        or (faction.permissions["admin"] and faction.permissions["admin"].approve
            and faction.members[approverSID] and faction.members[approverSID].rank == "admin")
        or (faction.permissions["mod"]   and faction.permissions["mod"].approve
            and faction.members[approverSID] and faction.members[approverSID].rank == "mod")
    if not canApprove then return false, "no_permission" end

    faction.requests[steamid] = nil
    SFS.SaveFactions()
    broadcastFactionSync(faction)

    local targetPly = SFS.FindPlayerBySteamID(steamid)
    if IsValid(targetPly) then
        net.Start("SFS_ChatMsg")
        net.WriteUInt(0, 4)
        net.WriteString(SFS.FormatStringFor(targetPly, "RequestDenied", { factionName = faction.name }))
        net.Send(targetPly)
    end
    SFS:print(approver:Nick() .. " denied " .. steamid .. " from " .. faction.name)
    return true
end

function SFS.KickMember(kicker, steamid, factionID)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local kickerSID  = kicker:SteamID()
    local kickerRank = SFS.GetPlayerRankInFaction(kickerSID, faction)
    if not kickerRank then return false, "not_member" end

    local targetRank = SFS.GetPlayerRankInFaction(steamid, faction)
    if not targetRank or targetRank == "owner" then return false, "cannot_kick" end
    if targetRank == "subowner" and kickerRank ~= "owner" then return false, "cannot_kick_subowner" end

    local canKick = kickerRank == "owner" or kickerRank == "subowner"
        or (faction.permissions["admin"] and faction.permissions["admin"].kick
            and faction.members[kickerSID] and faction.members[kickerSID].rank == "admin")
        or (faction.permissions["mod"]   and faction.permissions["mod"].kick
            and faction.members[kickerSID] and faction.members[kickerSID].rank == "mod")
    if not canKick then return false, "no_permission" end

    faction.members[steamid]  = nil
    faction.subowners[steamid] = nil

    SFS.SaveFactions()
    broadcastFactionSync(faction)

    local targetPly = SFS.FindPlayerBySteamID(steamid)
    local nick = IsValid(targetPly) and targetPly:Nick() or steamid
    broadcastChat(SFS.FormatString("PlayerKickedFaction", { playerName = nick, factionName = faction.name }))
    if IsValid(targetPly) then
        sendNotify(targetPly, "kicked", SFS.FormatStringFor(targetPly, "NotifyKicked", { factionName = faction.name }))
    end
    SFS:print(kicker:Nick() .. " kicked " .. steamid .. " from " .. faction.name)
    return true
end

function SFS.LeaveFaction(ply)
    local steamid = ply:SteamID()
    local faction = SFS.GetPlayerFaction(steamid)
    if not faction then return false, "not_in_faction" end
    if faction.owner == steamid then return false, "owner_must_disband" end

    faction.members[steamid]  = nil
    faction.subowners[steamid] = nil

    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastChat(SFS.FormatString("PlayerLeftFaction", { playerName = ply:Nick(), factionName = faction.name }))
    SFS:print(ply:Nick() .. " left faction " .. faction.name)
    return true
end

function SFS.UpdateFaction(owner, factionID, data)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if rank ~= "owner" and rank ~= "subowner" then return false, "no_permission" end

    if data.name then
        if data.name:match("[%z%c]") or #data.name:gsub("%s","") == 0 then return false, "invalid_name" end
        if #data.name > SFS.Config.MaxFactionNameLength then return false, "name_too_long" end
        local existing = SFS.GetFactionByName(data.name)
        if existing and existing.id ~= factionID then return false, "name_taken" end
        faction.name = data.name
    end

    if data.desc then
        if #data.desc > SFS.Config.MaxFactionDescLength then return false, "desc_too_long" end
        faction.desc = data.desc
    end

    if data.icon ~= nil then
        local icon = data.icon
        if icon ~= "" and icon ~= SFS.Config.DefaultIconMaterial then
            if not SFS.Config.AllowImgurPictures then
                icon = SFS.Config.DefaultIconMaterial
            elseif not icon:match("^https?://i%.imgur%.com/") and not icon:match("^https?://imgur%.com/") and not icon:match("^icon16/") then
                icon = SFS.Config.DefaultIconMaterial
            end
        end
        faction.icon = icon
    end

    if data.public ~= nil then faction.public = data.public end

    SFS.SaveFactions()
    broadcastFactionSync(faction)
    SFS:print("Faction " .. faction.name .. " updated by " .. owner:Nick())
    return true
end

function SFS.ToggleFriendlyFire(owner, factionID, value)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if rank ~= "owner" and rank ~= "subowner" then return false, "no_permission" end

    faction.friendlyFire = value == true
    SFS:print("[DEBUG] FriendlyFire for " .. faction.name .. " set to " .. tostring(faction.friendlyFire) .. " by " .. owner:Nick())
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    return true
end

function SFS.ToggleHalo(owner, factionID, value)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if rank ~= "owner" and rank ~= "subowner" then return false, "no_permission" end

    faction.haloEnabled = value == true
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    return true
end

function SFS.SetMemberRank(owner, steamid, factionID, newRank)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID  = owner:SteamID()
    local ownerRank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if ownerRank ~= "owner" and ownerRank ~= "subowner" then return false, "no_permission" end
    if not faction.members[steamid] then return false, "not_member" end
    if newRank ~= "admin" and newRank ~= "mod" and newRank ~= "member" then return false, "invalid_rank" end

    faction.members[steamid].rank = newRank
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    local targetPly = SFS.FindPlayerBySteamID(steamid)
    if IsValid(targetPly) then
        local rankLabel = (faction.ranks and faction.ranks[newRank] and faction.ranks[newRank].label) or newRank
        sendNotify(targetPly, "rank", SFS.FormatStringFor(targetPly, "NotifyPromoted", { rankLabel = rankLabel, factionName = faction.name }))
    end
    return true
end

function SFS.SetSubOwner(owner, steamid, factionID, value)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    if faction.owner ~= ownerSID then return false, "not_owner" end

    if value then
        faction.subowners[steamid] = true
        if faction.members[steamid] then faction.members[steamid] = nil end
    else
        faction.subowners[steamid] = nil
        faction.members[steamid]   = { rank = "member", joined = os.time() }
    end

    SFS.SaveFactions()
    broadcastFactionSync(faction)
    local targetPly = SFS.FindPlayerBySteamID(steamid)
    if IsValid(targetPly) then
        if value then
            sendNotify(targetPly, "rank", SFS.FormatStringFor(targetPly, "NotifySubOwner", { factionName = faction.name }))
        else
            sendNotify(targetPly, "rank", SFS.FormatStringFor(targetPly, "NotifyBackToMember", { factionName = faction.name }))
        end
    end
    return true
end

function SFS.TransferOwnership(owner, targetSID, factionID)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    if faction.owner ~= ownerSID then return false, "not_owner" end
    if targetSID == ownerSID then return false, "same_player" end

    local isSubOwner = faction.subowners and faction.subowners[targetSID]
    local isMember   = faction.members and faction.members[targetSID]
    if not isSubOwner and not isMember then return false, "not_member" end

    faction.members[ownerSID]   = { rank = "member", joined = os.time() }
    faction.subowners[ownerSID] = nil

    faction.owner = targetSID
    faction.subowners[targetSID] = nil
    if faction.members[targetSID] then faction.members[targetSID] = nil end

    SFS.SaveFactions()
    broadcastFactionSync(faction)

    local oldNick    = owner:Nick()
    local targetPly  = SFS.FindPlayerBySteamID(targetSID)
    local targetNick = IsValid(targetPly) and targetPly:Nick() or targetSID
    broadcastChat(SFS.Strings.AddonPrefix .. " " .. oldNick .. " transferred ownership of " .. faction.name .. " to " .. targetNick .. ".", 2)
    return true
end

function SFS.UpdateRankLabels(owner, factionID, labels)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    if faction.owner ~= ownerSID then return false, "not_owner" end

    faction.ranks = faction.ranks or {
        admin  = { label = "Admin",     color = "255,150,0"   },
        mod    = { label = "Moderator", color = "0,180,255"   },
        member = { label = "Member",    color = "200,200,200" },
    }

    if labels.admin  and type(labels.admin)  == "string" and #labels.admin  > 0 and #labels.admin  <= 20 then faction.ranks.admin.label  = labels.admin  end
    if labels.mod    and type(labels.mod)    == "string" and #labels.mod    > 0 and #labels.mod    <= 20 then faction.ranks.mod.label    = labels.mod    end
    if labels.member and type(labels.member) == "string" and #labels.member > 0 and #labels.member <= 20 then faction.ranks.member.label = labels.member end

    SFS.SaveFactions()
    broadcastFactionSync(faction)
    return true
end

function SFS.SendAllyRequest(owner, factionID, targetFactionID, message)
    local faction = SFS.GetFactionByID(factionID)
    local target  = SFS.GetFactionByID(targetFactionID)
    if not faction or not target then return false, "not_found" end
    if factionID == targetFactionID then return false, "same_faction" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if rank ~= "owner" and rank ~= "subowner" then return false, "no_permission" end

    if faction.allies and faction.allies[targetFactionID] then return false, "already_allies" end

    local existingWar, _ = SFS.GetWarByFaction and SFS.GetWarByFaction(factionID)
    local targetWar,   _ = SFS.GetWarByFaction and SFS.GetWarByFaction(targetFactionID)
    if existingWar and (existingWar.side1[targetFactionID] or existingWar.side2[targetFactionID]) then
        return false, "cannot_ally_enemy"
    end
    if targetWar and (targetWar.side1[factionID] or targetWar.side2[factionID]) then
        return false, "cannot_ally_enemy"
    end
    if table.Count(faction.allies or {}) >= SFS.Config.FactionMaxAllies then return false, "max_allies_reached" end
    if table.Count(target.allies or {}) >= SFS.Config.FactionMaxAllies then return false, "target_max_allies_reached" end

    target.allyRequests = target.allyRequests or {}
    if target.allyRequests[factionID] then return false, "request_already_sent" end

    target.allyRequests[factionID] = {
        fromName = faction.name,
        message  = message and message:sub(1, 100) or "",
        time     = os.time(),
    }

    SFS.SaveFactions()
    broadcastFactionSync(target)

    broadcastChat(SFS.FormatString("AllianceRequested", { factionName = faction.name, targetName = target.name }))

    local function notifyAllianceRequest(recipient)
        if not IsValid(recipient) then return end
        sendNotify(recipient, "alliance", SFS.FormatStringFor(recipient, "NotifyAllianceRequest", { factionName = faction.name }))
    end

    notifyAllianceRequest(SFS.FindPlayerBySteamID(target.owner))
    if target.subowners then
        for sid, _ in pairs(target.subowners) do
            notifyAllianceRequest(SFS.FindPlayerBySteamID(sid))
        end
    end
    SFS:print("Alliance request: " .. faction.name .. " -> " .. target.name)
    return true
end

function SFS.AcceptAllyRequest(owner, factionID, requesterFactionID)
    local faction   = SFS.GetFactionByID(factionID)
    local requester = SFS.GetFactionByID(requesterFactionID)
    if not faction or not requester then return false, "not_found" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)

    local canAccept = rank == "owner" or rank == "subowner"
        or (faction.permissions and faction.permissions["admin"] and faction.permissions["admin"].approve
            and faction.members[ownerSID] and faction.members[ownerSID].rank == "admin")
        or (faction.permissions and faction.permissions["mod"]   and faction.permissions["mod"].approve
            and faction.members[ownerSID] and faction.members[ownerSID].rank == "mod")
    if not canAccept then return false, "no_permission" end

    faction.allyRequests = faction.allyRequests or {}
    if not faction.allyRequests[requesterFactionID] then return false, "no_request" end

    if table.Count(faction.allies or {}) >= SFS.Config.FactionMaxAllies then return false, "max_allies_reached" end
    if table.Count(requester.allies or {}) >= SFS.Config.FactionMaxAllies then return false, "target_max_allies_reached" end

    faction.allies = faction.allies or {}
    requester.allies = requester.allies or {}

    faction.allies[requesterFactionID] = true
    requester.allies[factionID]        = true
    faction.allyRequests[requesterFactionID] = nil

    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastFactionSync(requester)
    broadcastChat(SFS.FormatString("AllianceFormed", { factionName = requester.name, targetName = faction.name }))
    SFS:print("Alliance formed: " .. requester.name .. " <-> " .. faction.name)
    return true
end

function SFS.DeclineAllyRequest(owner, factionID, requesterFactionID)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if rank ~= "owner" and rank ~= "subowner" then return false, "no_permission" end

    faction.allyRequests = faction.allyRequests or {}
    if not faction.allyRequests[requesterFactionID] then return false, "no_request" end

    faction.allyRequests[requesterFactionID] = nil
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    return true
end

function SFS.RemoveAlly(owner, factionID, targetFactionID)
    local faction = SFS.GetFactionByID(factionID)
    local target  = SFS.GetFactionByID(targetFactionID)
    if not faction or not target then return false, "not_found" end

    local ownerSID = owner:SteamID()
    local rank = SFS.GetPlayerRankInFaction(ownerSID, faction)
    if rank ~= "owner" and rank ~= "subowner" then return false, "no_permission" end

    faction.allies = faction.allies or {}
    target.allies  = target.allies or {}
    faction.allies[targetFactionID] = nil
    target.allies[factionID]        = nil
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastFactionSync(target)
    broadcastChat(SFS.FormatString("AllianceBroken", { factionName = faction.name, targetName = target.name }))
    return true
end

local VALID_PERM_RANKS = { admin = true, mod = true }
local VALID_PERM_KEYS  = { approve = true, kick = true }

function SFS.UpdatePermissions(owner, factionID, perms)
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end

    local ownerSID = owner:SteamID()
    if faction.owner ~= ownerSID then return false, "not_owner" end

    for rankKey, rankPerms in pairs(perms) do
        if VALID_PERM_RANKS[rankKey] and type(rankPerms) == "table" then
            faction.permissions[rankKey] = faction.permissions[rankKey] or {}
            for permKey, permVal in pairs(rankPerms) do
                if VALID_PERM_KEYS[permKey] and type(permVal) == "boolean" then
                    faction.permissions[rankKey][permKey] = permVal
                end
            end
        end
    end

    SFS.SaveFactions()
    broadcastFactionSync(faction)
    return true
end

function SFS.FindPlayerBySteamID(steamid)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == steamid then return ply end
    end
    return nil
end

function SFS.AdminForceJoin(admin, targetPly, factionID)
    if not SFS.IsAdmin(admin) then return false, "no_permission" end
    local steamid = targetPly:SteamID()
    if SFS.GetPlayerFaction(steamid) then return false, "already_in_faction" end
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end
    faction.members[steamid] = { rank = "member", joined = os.time() }
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastChat(SFS.FormatString("PlayerJoinedFaction", { playerName = targetPly:Nick(), factionName = faction.name }))
    SFS:print("[ADMIN] " .. admin:Nick() .. " forced " .. targetPly:Nick() .. " into " .. faction.name)
    return true
end

function SFS.AdminForceLeave(admin, targetPly, factionID)
    if not SFS.IsAdmin(admin) then return false, "no_permission" end
    local steamid = targetPly:SteamID()
    local faction = SFS.GetFactionByID(factionID)
    if not faction then return false, "not_found" end
    faction.members[steamid]   = nil
    faction.subowners[steamid] = nil
    SFS.SaveFactions()
    broadcastFactionSync(faction)
    broadcastChat(SFS.FormatString("PlayerLeftFaction", { playerName = targetPly:Nick(), factionName = faction.name }))
    SFS:print("[ADMIN] " .. admin:Nick() .. " forced " .. targetPly:Nick() .. " out of " .. faction.name)
    return true
end

hook.Add("PlayerShouldTakeDamage", "SFS_FriendlyFire", function(ply, attacker)
    if not IsValid(ply) or not IsValid(attacker) then return end
    if not attacker:IsPlayer() or ply == attacker then return end

    local plyFac    = SFS.GetPlayerFaction(ply:SteamID())
    local attackFac = SFS.GetPlayerFaction(attacker:SteamID())
    if not plyFac or not attackFac then return end
    if plyFac.id ~= attackFac.id then return end

    if plyFac.friendlyFire == true then return end
    return false
end)

SFS:print("Faction logic loaded")
