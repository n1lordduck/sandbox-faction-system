local SFS = SandboxFactionSystem

local pingMat  = Material("icon16/flag_red.png")
local lastPing = 0
local PING_CD  = 1.5

local _inFac    = false
local _facCheck = 0

local _sw, _sh, _cx, _cy = 0, 0, 0, 0

hook.Add("OnScreenSizeChanged", "SFS_Ping_Sz", function(_, _, nw, nh)
    _sw, _sh, _cx, _cy = nw, nh, nw*0.5, nh*0.5
end)
hook.Add("InitPostEntity", "SFS_Ping_Init", function()
    _sw, _sh = ScrW(), ScrH()
    _cx, _cy = _sw*0.5, _sh*0.5
end)

hook.Add("PlayerButtonDown", "SFS_PingKey", function(ply, button)
    if CLIENT and ply ~= LocalPlayer() then return end

    local targetKey = SFS.CL.PingKey:GetInt()

    if button ~= targetKey then return end

    local now = CurTime()
    if now - _facCheck >= 0.5 then
        _facCheck = now
        _inFac = SFS.CL.GetMyFaction() ~= nil
    end
    if not _inFac then return end

    if now - lastPing < PING_CD then return end

    local tr = ply:GetEyeTrace()
    if not tr.Hit then return end

    lastPing = now
    local pos = tr.HitPos

    net.Start("SFS_Ping")
        net.WriteFloat(pos.x) 
        net.WriteFloat(pos.y) 
        net.WriteFloat(pos.z)
    net.SendToServer()

    surface.PlaySound("buttons/button19.wav")

    SFS.CL.PingList[#SFS.CL.PingList + 1] = {
        pos = pos, 
        nick = "You", 
        expire = now + SFS.Config.PingDuration, 
        own = true,
    }
end)

net.Receive("SFS_PingReceive", function()
    local x = net.ReadFloat() local y = net.ReadFloat() local z = net.ReadFloat()
    local nick = net.ReadString()
    SFS.CL.PingList[#SFS.CL.PingList + 1] = {
        pos = Vector(x, y, z), nick = nick,
        expire = CurTime() + SFS.Config.PingDuration, own = false,
    }
    surface.PlaySound("buttons/button9.wav")
end)

hook.Add("PostDrawTranslucentRenderables", "SFS_DrawPings3D", function(depth, sky)
    if depth or sky then return end
    if #SFS.CL.PingList == 0 then return end

    local now    = CurTime()
    local eyePos = LocalPlayer():EyePos()
    local eyeFwd = LocalPlayer():EyeAngles():Forward()
    local invDur = 1 / SFS.Config.PingDuration
    local kept   = {}
    local eyeY   = LocalPlayer():EyeAngles().y

    for i = 1, #SFS.CL.PingList do
        local p = SFS.CL.PingList[i]
        if p.expire <= now then continue end
        kept[#kept + 1] = p
        
        -- Sem limite de distância aqui no 3D, apenas checa se está na frente da câmera
        if (p.pos - eyePos):Dot(eyeFwd) <= 0 then continue end
        
        local a = math.Clamp(((p.expire - now) * invDur) * 255, 0, 255)
        local bob = math.sin(now * 4) * 3
        cam.Start3D2D(p.pos + Vector(0,0,14+bob), Angle(0, eyeY-90, 90), 0.1)
            surface.SetDrawColor(255, 80, 80, a)
            surface.SetMaterial(pingMat)
            surface.DrawTexturedRect(-16, -16, 32, 32)
            draw.SimpleTextOutlined(p.nick, "DermaDefault", 0, 20,
                Color(255,255,255,a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0,0,0,a))
        cam.End3D2D()
    end

    SFS.CL.PingList = kept
end)

local MARGIN = 28
local SZ     = 16
local SZH    = 8
local INV52  = 1 / 52.49


local function borderPos(worldPos)
    local sc = worldPos:ToScreen()
    local sx, sy = sc.x, sc.y
    local onScreen = sc.visible
        and sx >= MARGIN and sx <= (_sw - MARGIN)
        and sy >= MARGIN and sy <= (_sh - MARGIN)
    if onScreen then return sx, sy, true end

    local me    = LocalPlayer()
    local eyeA  = me:EyeAngles()
    local fwd   = eyeA:Forward()
    local right = eyeA:Right()
    local up    = eyeA:Up()
    local delta = (worldPos - me:EyePos()):GetNormalized()
    local dot   = delta:Dot(fwd)
    local projR = delta:Dot(right) * (dot >= 0 and 1 or -1)
    local projU = -delta:Dot(up)   * (dot >= 0 and 1 or -1)

    local ang  = math.atan2(projU, projR)
    local cosA = math.cos(ang)
    local sinA = math.sin(ang)

    local halfW = _cx - MARGIN
    local halfH = _cy - MARGIN
    local tX = halfW / (math.abs(cosA) + 1e-6)
    local tY = halfH / (math.abs(sinA) + 1e-6)
    local t  = math.min(tX, tY)

    local bx = math.Clamp(_cx + cosA * t, MARGIN, _sw - MARGIN)
    local by = math.Clamp(_cy + sinA * t, MARGIN, _sh - MARGIN)
    return bx, by, false
end

hook.Add("HUDPaint", "SFS_PingHUD", function()
    if #SFS.CL.PingList == 0 then return end
    if _sw == 0 then return end

    local now    = CurTime()
    local me     = LocalPlayer()
    local eyePos = me:EyePos()
    local invDur = 1 / SFS.Config.PingDuration

    for i = 1, #SFS.CL.PingList do
        local p = SFS.CL.PingList[i]
        if p.expire <= now then continue end

        -- Verificação de distância removida!
        local dist = eyePos:Distance(p.pos)
        local a = math.Clamp(((p.expire - now) * invDur) * 220, 0, 220)
        
        local bx, by, insideScreen = borderPos(p.pos)

        if insideScreen then
            surface.SetDrawColor(255, 80, 80, a)
            surface.SetMaterial(pingMat)
            surface.DrawTexturedRect(bx - SZH, by - SZH, SZ, SZ)
            local dm = math.floor(dist * INV52 + 0.5)
            draw.SimpleTextOutlined(p.nick .. " [" .. dm .. "m]", "DermaDefault",
                bx, by + SZH + 2, Color(255,255,255,a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP,
                1, Color(0,0,0,a))
        else
            local pa = math.floor(a * (0.75 + math.sin(now*6)*0.25))
            surface.SetDrawColor(255, 80, 80, pa)
            surface.SetMaterial(pingMat)
            surface.DrawTexturedRect(bx - SZH, by - SZH, SZ, SZ)
            local dm = math.floor(dist * INV52 + 0.5)
            draw.SimpleTextOutlined(p.nick, "DermaDefault",
                bx, by - SZH - 2, Color(255,200,200,pa), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM,
                1, Color(0,0,0,pa))
            draw.SimpleTextOutlined(dm .. "m", "DermaDefault",
                bx, by + SZH + 2, Color(255,255,255,pa), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP,
                1, Color(0,0,0,pa))
        end
    end
end)

SFS:print("Ping system loaded")