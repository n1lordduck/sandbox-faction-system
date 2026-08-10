local SFS = SandboxFactionSystem

SFS.CL.Wars = {}

local function getWarBySide(facID)
    for warID, war in pairs(SFS.CL.Wars) do
        if not war.ended then
            if war.side1 and war.side1[facID] then return war, "side1", warID end
            if war.side2 and war.side2[facID] then return war, "side2", warID end
        end
    end
    return nil, nil, nil
end

function SFS.CL.GetActiveWars()
    local active = {}
    for _, war in pairs(SFS.CL.Wars) do
        if not war.ended then active[#active + 1] = war end
    end
    return active
end

function SFS.CL.GetMyWar()
    local myFac = SFS.CL.GetMyFaction()
    if not myFac then return nil, nil, nil end
    return getWarBySide(myFac.id)
end

function SFS.CL.GetFactionWarStatus(facID)
    return getWarBySide(facID)
end

net.Receive("SFS_WarsFullSync", function()
    local json = net.ReadString()
    local t    = util.JSONToTable(json)
    if t then
        SFS.CL.Wars = t
        hook.Run("SFS_WarsUpdated")
    end
end)

net.Receive("SFS_WarSync", function()
    local json = net.ReadString()
    local war  = util.JSONToTable(json)
    if war and war.id then
        SFS.CL.Wars[war.id] = war
        hook.Run("SFS_WarsUpdated")

        local myFac = SFS.CL.GetMyFaction()
        if myFac then
            if war.side1 and war.side1[myFac.id] or war.side2 and war.side2[myFac.id] then
                if not war.ended then
                    surface.PlaySound("buttons/button10.wav")
                end
            end
        end
    end
end)

net.Receive("SFS_WarRemoved", function()
    local warID = net.ReadString()
    if SFS.CL.Wars[warID] then
        SFS.CL.Wars[warID].ended = true
        hook.Run("SFS_WarsUpdated")
        timer.Simple(5, function()
            SFS.CL.Wars[warID] = nil
            hook.Run("SFS_WarsUpdated")
        end)
    end
end)

net.Receive("SFS_WarTruceRequest", function()
    local warID   = net.ReadString()
    local facName = net.ReadString()
    surface.PlaySound("buttons/button15.wav")
    SFS.Notify("alliance", facName .. " requested a truce! Click Request Truce to accept.")
    hook.Run("SFS_WarsUpdated")
end)

net.Receive("SFS_WarNotify", function()
    local t        = net.ReadUInt(4)
    local aggressor = net.ReadString()
    local target    = net.ReadString()
    surface.PlaySound("buttons/button10.wav")
    if SFS.Notify then
        SFS.Notify("warning", aggressor .. " declared war on " .. target .. "!")
    end
end)

net.Receive("SFS_WarEndNotify", function()
    local reason     = net.ReadString()
    local winnerSide = net.ReadString()
    surface.PlaySound("buttons/button3.wav")
end)

SFS:print("War client data loaded")
