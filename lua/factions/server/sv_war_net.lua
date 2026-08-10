local SFS = SandboxFactionSystem

local WAR_NET_CD  = {}
local WAR_CD_TIME = {
    SFS_DeclareWar    = 5,
    SFS_RequestTruce  = 3,
}

local function warCooldown(ply, name)
    local sid = ply:SteamID()
    WAR_NET_CD[sid] = WAR_NET_CD[sid] or {}
    local last = WAR_NET_CD[sid][name] or 0
    local cd   = WAR_CD_TIME[name] or 2
    local now  = CurTime()
    if now - last < cd then return false end
    WAR_NET_CD[sid][name] = now
    return true
end

local function sendWarError(ply, code)
    net.Start("SFS_ChatMsg")
    net.WriteUInt(1, 4)
    net.WriteString(SFS.StringFor(ply, "AddonPrefix") .. " " .. SFS.GetErrorFor(ply, code))
    net.Send(ply)
end

net.Receive("SFS_DeclareWar", function(_, ply)
    if not warCooldown(ply, "SFS_DeclareWar") then return end
    local targetFacID = net.ReadString()
    local ok, err = SFS.DeclareWar(ply, targetFacID)
    if not ok then sendWarError(ply, err) end
end)

net.Receive("SFS_RequestTruce", function(_, ply)
    if not warCooldown(ply, "SFS_RequestTruce") then return end
    local warID = net.ReadString()
    local ok, res = SFS.RequestTruce(ply, warID)
    if not ok then sendWarError(ply, res) end
end)

SFS:print("War network handlers loaded")
