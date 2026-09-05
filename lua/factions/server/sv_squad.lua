local SFS = SandboxFactionSystem

SFS.SquadOwners    = SFS.SquadOwners or {}
SFS.SquadFollowing = SFS.SquadFollowing or {}
SFS.SquadAttacking = SFS.SquadAttacking or {}

local recruitCooldowns = {}
local commandCooldowns = {}
local followLastOrder  = {}

local function onCooldown(cache, ply, seconds)
    local sid = ply:SteamID()
    local last = cache[sid] or 0
    local now = CurTime()
    if now - last < seconds then return true end
    cache[sid] = now
    return false
end

local function sendChat(ply, key, vars)
    net.Start("SFS_ChatMsg")
    net.WriteUInt(1, 4)
    net.WriteString(vars and SFS.FormatStringFor(ply, key, vars) or SFS.StringFor(ply, key))
    net.Send(ply)
end

local function canRecruitNpc(ply, fac)
    local rank = SFS.GetPlayerRankInFaction(ply:SteamID(), fac)
    if not rank then return false end
    if rank ~= "admin" and rank ~= "mod" then return true end

    local perms = fac.permissions and fac.permissions[rank]
    if not perms or perms.recruitNpc == nil then return true end
    return perms.recruitNpc == true
end

local function setFactionRelationship(npc, factionID, disposition)
    for _, p in ipairs(player.GetAll()) do
        local fac = SFS.GetPlayerFaction(p:SteamID())
        if fac and fac.id == factionID then
            npc:AddEntityRelationship(p, disposition, 99)
        end
    end
end

local function stopFollowing(npc)
    local wasFollowing = SFS.SquadFollowing[npc]
    SFS.SquadFollowing[npc] = nil
    followLastOrder[npc] = nil
    return wasFollowing
end

local function stopAttacking(npc)
    local target = SFS.SquadAttacking[npc]
    if not target then return nil end

    SFS.SquadAttacking[npc] = nil
    npc:SetNWEntity("SFS_SquadEnemy", NULL)

    if IsValid(npc) then
        if IsValid(target) then
            npc:AddEntityRelationship(target, D_NU, 99)
        end
        npc:SetSchedule(SCHED_IDLE_STAND)
    end

    return target
end

local function squadFor(ply, factionID)
    local squad = {}
    local radiusSqr = SFS.Config.SquadCommandRadius ^ 2

    for npc, factionID2 in pairs(SFS.SquadOwners) do
        if factionID2 == factionID and IsValid(npc) and npc:GetPos():DistToSqr(ply:GetPos()) <= radiusSqr then
            squad[#squad + 1] = npc
        end
    end

    return squad
end

net.Receive("SFS_SquadRecruit", function(_, ply)
    if onCooldown(recruitCooldowns, ply, 1) then return end

    local npc = net.ReadEntity()
    if not IsValid(ply) or not IsValid(npc) then return end
    if not npc:IsNPC() or npc:Health() <= 0 then return end
    if SFS.SquadOwners[npc] then
        sendChat(ply, "SquadAlreadyRecruited")
        return
    end
    if ply:GetPos():DistToSqr(npc:GetPos()) > SFS.Config.SquadRecruitRange ^ 2 then
        sendChat(ply, "SquadTooFar")
        return
    end

    local fac = SFS.GetPlayerFaction(ply:SteamID())
    if not fac then
        sendChat(ply, "SquadNoFaction")
        return
    end
    if not canRecruitNpc(ply, fac) then
        sendChat(ply, "SquadNoPermission")
        return
    end

    SFS.SquadOwners[npc] = fac.id
    npc:SetNWString("SFS_SquadFaction", fac.id)
    setFactionRelationship(npc, fac.id, D_LI)

    sendChat(ply, "SquadRecruited", { npcClass = npc:GetClass(), factionName = fac.name })
end)

net.Receive("SFS_SquadDismiss", function(_, ply)
    if onCooldown(recruitCooldowns, ply, 1) then return end

    local npc = net.ReadEntity()
    if not IsValid(ply) or not IsValid(npc) then return end

    local fac = SFS.GetPlayerFaction(ply:SteamID())
    if not fac or SFS.SquadOwners[npc] ~= fac.id then return end

    setFactionRelationship(npc, fac.id, D_NU)
    stopAttacking(npc)
    stopFollowing(npc)

    SFS.SquadOwners[npc] = nil
    npc:SetNWString("SFS_SquadFaction", "")

    sendChat(ply, "SquadDismissed", { npcClass = npc:GetClass(), factionName = fac.name })
end)

net.Receive("SFS_SquadCommand", function(_, ply)
    if onCooldown(commandCooldowns, ply, 0.5) then return end

    local cmdType = net.ReadUInt(8)
    if not IsValid(ply) then return end

    local fac = SFS.GetPlayerFaction(ply:SteamID())
    if not fac then return end

    local squad = squadFor(ply, fac.id)
    if #squad == 0 then return end

    if cmdType == 1 then
        local pos = net.ReadVector()
        local interruptedMyFollow = false

        for _, npc in ipairs(squad) do
            if stopFollowing(npc) == ply then interruptedMyFollow = true end
            stopAttacking(npc)
            npc:SetLastPosition(pos)
            npc:SetSchedule(SCHED_FORCED_GO_RUN)
        end

        if interruptedMyFollow then
            sendChat(ply, "SquadFollowInterrupted")
        end
    elseif cmdType == 2 then
        local target = net.ReadEntity()
        if not IsValid(target) then return end

        if target:IsPlayer() then
            local targetFac = SFS.GetPlayerFaction(target:SteamID())
            if targetFac and targetFac.id == fac.id then return end
        elseif target:IsNPC() then
            if SFS.SquadOwners[target] == fac.id then return end
        else
            return
        end

        for _, npc in ipairs(squad) do
            stopAttacking(npc)

            SFS.SquadAttacking[npc] = target
            npc:SetNWEntity("SFS_SquadEnemy", target)
            npc:AddEntityRelationship(target, D_HT, 99)
            npc:UpdateEnemyMemory(target, target:GetPos())
            npc:SetEnemy(target)
            npc:SetSchedule(SCHED_CHASE_ENEMY)
        end
    elseif cmdType == 4 then
        local npc = net.ReadEntity()
        if not IsValid(npc) or SFS.SquadOwners[npc] ~= fac.id then return end
        if not SFS.SquadAttacking[npc] then return end

        stopAttacking(npc)
        sendChat(ply, "SquadAttackStopped", { npcClass = npc:GetClass() })
    elseif cmdType == 3 then
        local npc = net.ReadEntity()
        if not IsValid(npc) or SFS.SquadOwners[npc] ~= fac.id then return end

        if SFS.SquadFollowing[npc] == ply then
            stopFollowing(npc)
            sendChat(ply, "SquadFollowOff", { npcClass = npc:GetClass() })
        else
            SFS.SquadFollowing[npc] = ply
            sendChat(ply, "SquadFollowOn", { npcClass = npc:GetClass() })
        end
    end
end)

timer.Create("SFS_SquadTick", SFS.Config.SquadFollowTickInterval, 0, function()
    for npc, ply in pairs(SFS.SquadFollowing) do
        if not IsValid(npc) or not IsValid(ply) then
            SFS.SquadFollowing[npc] = nil
            followLastOrder[npc] = nil
            continue
        end

        if SFS.SquadAttacking[npc] then continue end

        local plyPos = ply:GetPos()
        local dist = npc:GetPos():Distance(plyPos)

        if dist <= SFS.Config.SquadFollowStopDist then continue end
        if dist > SFS.Config.SquadCommandRadius then continue end

        local lastOrder = followLastOrder[npc]
        if lastOrder and plyPos:DistToSqr(lastOrder) < SFS.Config.SquadFollowReorderDist ^ 2 then continue end

        followLastOrder[npc] = plyPos
        npc:SetLastPosition(plyPos)
        npc:SetSchedule(SCHED_FORCED_GO_RUN)
    end

    for npc, target in pairs(SFS.SquadAttacking) do
        if not IsValid(npc) then
            SFS.SquadAttacking[npc] = nil
            continue
        end

        local targetDead = not IsValid(target) or (target:IsPlayer() and not target:Alive()) or target:Health() <= 0
        if targetDead then
            stopAttacking(npc)
        end
    end
end)

hook.Add("EntityRemoved", "SFS_SquadCleanup", function(ent)
    SFS.SquadOwners[ent] = nil
    SFS.SquadFollowing[ent] = nil
    SFS.SquadAttacking[ent] = nil
    followLastOrder[ent] = nil
end)

hook.Add("PlayerInitialSpawn", "SFS_SquadLikeOnJoin", function(ply)
    timer.Simple(3, function()
        if not IsValid(ply) then return end

        local fac = SFS.GetPlayerFaction(ply:SteamID())
        if not fac then return end

        for npc, factionID in pairs(SFS.SquadOwners) do
            if factionID == fac.id and IsValid(npc) then
                npc:AddEntityRelationship(ply, D_LI, 99)
            end
        end
    end)
end)

SFS:print("Squad system loaded")
