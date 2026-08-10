local SFS = SandboxFactionSystem

SFS.Wars = SFS.Wars or {}

local WAR_DURATION   = SFS.Config.WarDuration or 3600
local WAR_FILE       = "sandbox_factions/wars.dat"
local WAR_CHECK_RATE = 5

local function saveWars()
    if not file.IsDir("sandbox_factions/", "DATA") then file.CreateDir("sandbox_factions/") end
    local data = util.Compress(util.TableToJSON(SFS.Wars))
    file.Write(WAR_FILE, data)
end

local function loadWars()
    if not file.Exists(WAR_FILE, "DATA") then return end
    local raw = file.Read(WAR_FILE, "DATA")
    if not raw or raw == "" then return end
    local dec = util.Decompress(raw)
    if not dec then return end
    local t = util.JSONToTable(dec)
    if t then SFS.Wars = t end
end

local function broadcastWar(war)
    net.Start("SFS_WarSync")
    net.WriteString(util.TableToJSON(war))
    net.Broadcast()
end

local function broadcastWarRemoved(warID)
    net.Start("SFS_WarRemoved")
    net.WriteString(warID)
    net.Broadcast()
end

local function broadcastAllWars()
    net.Start("SFS_WarsFullSync")
    net.WriteString(util.TableToJSON(SFS.Wars))
    net.Broadcast()
end

local function getAllWarMembers(sideTable)
    local members = {}
    for facID, _ in pairs(sideTable) do
        local fac = SFS.GetFactionByID(facID)
        if fac then
            members[fac.owner] = true
            for sid in pairs(fac.subowners or {}) do members[sid] = true end
            for sid in pairs(fac.members or {})   do members[sid] = true end
        end
    end
    return members
end

local function getOnlineWarMembers(sideTable)
    local sideMembers = getAllWarMembers(sideTable)
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and sideMembers[ply:SteamID()] then
            return true
        end
    end
    return false
end

local function endWar(warID, reason, winnerSide)
    local war = SFS.Wars[warID]
    if not war then return end
    war.ended     = true
    war.endReason = reason
    war.winner    = winnerSide
    saveWars()
    broadcastWarRemoved(warID)

    local fac1 = SFS.GetFactionByID(war.side1Leader)
    local fac2 = SFS.GetFactionByID(war.side2Leader)
    local n1 = fac1 and fac1.name or "?"
    local n2 = fac2 and fac2.name or "?"
    local msg
    if reason == "truce" then
        msg = SFS.FormatString("WarEndTruce", { faction1 = n1, faction2 = n2 })
    elseif reason == "time" then
        msg = SFS.FormatString("WarEndTime", { faction1 = n1, faction2 = n2 })
    elseif reason == "wipe" then
        local winName = winnerSide == "side1" and n1 or n2
        msg = SFS.FormatString("WarEndWipe", { winner = winName, faction1 = n1, faction2 = n2 })
    else
        msg = SFS.FormatString("WarEndGeneric", { faction1 = n1, faction2 = n2 })
    end

    for _, ply in ipairs(player.GetAll()) do
        net.Start("SFS_ChatMsg")
        net.WriteUInt(0, 4)
        net.WriteString(msg)
        net.Send(ply)
    end

    net.Start("SFS_WarEndNotify")
    net.WriteString(reason or "generic")
    net.WriteString(winnerSide or "")
    net.Broadcast()

    timer.Simple(30, function()
        if SFS.Wars[warID] and SFS.Wars[warID].ended then
            SFS.Wars[warID] = nil
            saveWars()
        end
    end)
end

function SFS.GetWarByFaction(facID)
    for warID, war in pairs(SFS.Wars) do
        if not war.ended then
            if war.side1[facID] or war.side2[facID] then
                return war, warID
            end
        end
    end
    return nil, nil
end

function SFS.DeclareWar(declarerPly, targetFacID)
    local declSID = declarerPly:SteamID()
    local declFac = SFS.GetPlayerFaction(declSID)
    if not declFac then return false, "not_in_faction" end
    if declFac.owner ~= declSID then return false, "not_owner" end

    local targetFac = SFS.GetFactionByID(targetFacID)
    if not targetFac then return false, "target_not_found" end
    if targetFac.id == declFac.id then return false, "same_faction" end

    if not getOnlineWarMembers({ [targetFacID] = true }) then
        return false, "target_offline"
    end

    local existingWar = SFS.GetWarByFaction(declFac.id)
    if existingWar then return false, "already_at_war" end

    local targetWar = SFS.GetWarByFaction(targetFacID)
    if targetWar then return false, "target_already_at_war" end

    if declFac.allies and declFac.allies[targetFacID] then
        return false, "cannot_war_ally"
    end

    for allyID in pairs(declFac.allies or {}) do
        local af = SFS.GetFactionByID(allyID)
        if af and af.id == targetFacID then
            return false, "cannot_war_ally"
        end
    end
    for allyID in pairs(targetFac.allies or {}) do
        if allyID == declFac.id then
            return false, "cannot_war_ally"
        end
    end

    local side1 = { [declFac.id] = true }
    local side2 = { [targetFacID] = true }

    for allyID in pairs(declFac.allies or {}) do
        local af = SFS.GetFactionByID(allyID)
        if af then side1[allyID] = true end
    end
    for allyID in pairs(targetFac.allies or {}) do
        local af = SFS.GetFactionByID(allyID)
        if af then side2[allyID] = true end
    end

    local warID = "war_" .. os.time() .. "_" .. math.random(1000, 9999)
    local war = {
        id          = warID,
        side1       = side1,
        side2       = side2,
        side1Leader = declFac.id,
        side2Leader = targetFacID,
        side1Kills  = 0,
        side2Kills  = 0,
        startTime   = os.time(),
        endTime     = os.time() + WAR_DURATION,
        truceRequested = nil,
        ended       = false,
    }

    SFS.Wars[warID] = war
    saveWars()
    broadcastWar(war)

    local fac1Name = declFac.name
    local fac2Name = targetFac.name
    local warDur   = SFS.Strings.WarDuration or "1 hour"
    local declMsg  = SFS.FormatString("WarDeclared", { faction1 = fac1Name, faction2 = fac2Name, duration = warDur })
    for _, ply in ipairs(player.GetAll()) do
        net.Start("SFS_ChatMsg")
        net.WriteUInt(0, 4)
        net.WriteString(declMsg)
        net.Send(ply)
    end

    timer.Create(warID .. "_check", WAR_CHECK_RATE, 0, function()
        local w = SFS.Wars[warID]
        if not w or w.ended then
            timer.Remove(warID .. "_check")
            return
        end

        if os.time() >= w.endTime then
            timer.Remove(warID .. "_check")
            endWar(warID, "time", nil)
            return
        end

        local s1HasOnline = getOnlineWarMembers(w.side1)
        local s2HasOnline = getOnlineWarMembers(w.side2)

        if not s1HasOnline and not s2HasOnline then return end
        if not s1HasOnline then
            timer.Remove(warID .. "_check")
            endWar(warID, "wipe", "side2")
            return
        end
        if not s2HasOnline then
            timer.Remove(warID .. "_check")
            endWar(warID, "wipe", "side1")
            return
        end
    end)

    local allSide2Members = getAllWarMembers(war.side2)
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and allSide2Members[ply:SteamID()] then
            net.Start("SFS_WarNotify")
            net.WriteUInt(0, 4)
            net.WriteString(fac1Name)
            net.WriteString(fac2Name)
            net.Send(ply)
        end
    end

    SFS:print("War declared: " .. fac1Name .. " vs " .. fac2Name .. " [" .. warID .. "]")
    return true, warID
end

function SFS.RequestTruce(requesterPly, warID)
    local war = SFS.Wars[warID]
    if not war or war.ended then return false, "no_war" end

    local sid = requesterPly:SteamID()
    local fac = SFS.GetPlayerFaction(sid)
    if not fac then return false, "not_in_faction" end
    if fac.owner ~= sid then return false, "not_owner" end

    local onSide1 = war.side1[fac.id]
    local onSide2 = war.side2[fac.id]
    if not onSide1 and not onSide2 then return false, "not_in_war" end

    local mySide      = onSide1 and "side1" or "side2"
    local theirSide   = onSide1 and "side2" or "side1"
    local myLeaderID  = onSide1 and war.side1Leader or war.side2Leader
    local isLeader    = fac.id == myLeaderID

    if not isLeader then
        war[mySide][fac.id] = nil
        SFS.Wars[warID] = war
        saveWars()
        broadcastWar(war)

        local msg = SFS.Strings.AddonPrefix .. " " .. fac.name .. " withdrew from the war."
        for _, p in ipairs(player.GetAll()) do
            net.Start("SFS_ChatMsg")
            net.WriteUInt(0, 4)
            net.WriteString(msg)
            net.Send(p)
        end

        SFS:print(fac.name .. " (ally) withdrew from war " .. warID)
        return true, "withdrew"
    end

    local theirLeaderID  = onSide1 and war.side2Leader or war.side1Leader
    if war.truceRequested and war.truceRequested ~= mySide then
        endWar(warID, "truce", nil)
        timer.Remove(warID .. "_check")
        return true, "war_ended"
    end

    war.truceRequested = mySide
    SFS.Wars[warID]    = war
    saveWars()
    broadcastWar(war)

    local leaderFac      = SFS.GetFactionByID(theirLeaderID)
    local leaderOwnerPly = leaderFac and SFS.FindPlayerBySteamID(leaderFac.owner)
    if IsValid(leaderOwnerPly) then
        net.Start("SFS_WarTruceRequest")
        net.WriteString(warID)
        net.WriteString(fac.name)
        net.Send(leaderOwnerPly)
    end

    SFS:print("Truce requested by " .. requesterPly:Nick() .. " (leader) in war " .. warID)
    return true, "truce_requested"
end

hook.Add("PlayerDeath", "SFS_WarKillTrack", function(victim, inflictor, attacker)
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if not IsValid(victim) or victim == attacker then return end

    local victimSID   = victim:SteamID()
    local attackerSID = attacker:SteamID()

    local vFac = SFS.GetPlayerFaction(victimSID)
    local aFac = SFS.GetPlayerFaction(attackerSID)
    if not vFac or not aFac then return end
    if vFac.id == aFac.id then return end

    for warID, war in pairs(SFS.Wars) do
        if war.ended then continue end
        local attackerInS1 = war.side1[aFac.id]
        local attackerInS2 = war.side2[aFac.id]
        local victimInS1   = war.side1[vFac.id]
        local victimInS2   = war.side2[vFac.id]

        if attackerInS1 and victimInS2 then
            war.side1Kills = war.side1Kills + 1
            SFS.Wars[warID] = war
            saveWars()
            broadcastWar(war)
        elseif attackerInS2 and victimInS1 then
            war.side2Kills = war.side2Kills + 1
            SFS.Wars[warID] = war
            saveWars()
            broadcastWar(war)
        end
    end
end)

hook.Add("PlayerInitialSpawn", "SFS_WarSyncNewPlayer", function(ply)
    timer.Simple(2, function()
        if not IsValid(ply) then return end
        net.Start("SFS_WarsFullSync")
        net.WriteString(util.TableToJSON(SFS.Wars))
        net.Send(ply)
    end)
end)

loadWars()

for warID, war in pairs(SFS.Wars) do
    if not war.ended then
        local remaining = war.endTime - os.time()
        if remaining <= 0 then
            endWar(warID, "time", nil)
        else
            timer.Create(warID .. "_check", WAR_CHECK_RATE, 0, function()
                local w = SFS.Wars[warID]
                if not w or w.ended then timer.Remove(warID .. "_check") return end
                if os.time() >= w.endTime then
                    timer.Remove(warID .. "_check")
                    endWar(warID, "time", nil)
                    return
                end
                local s1Has = getOnlineWarMembers(w.side1)
                local s2Has = getOnlineWarMembers(w.side2)
                if not s1Has and not s2Has then return end
                if not s1Has then timer.Remove(warID .. "_check") endWar(warID, "wipe", "side2") return end
                if not s2Has then timer.Remove(warID .. "_check") endWar(warID, "wipe", "side1") return end
            end)
        end
    end
end

SFS:print("War system loaded")
