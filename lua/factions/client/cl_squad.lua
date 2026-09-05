local SFS = SandboxFactionSystem

local iconMove   = Material("icon16/flag_green.png")
local iconAttack = Material("icon16/gun.png")
local iconFollow = Material("icon16/user_go.png")
local iconStop   = Material("icon16/stop.png")

local function isOwnSquadNPC(npc)
    local myFaction = SFS.CL.GetMyFaction()
    return myFaction and npc:GetNWString("SFS_SquadFaction", "") == myFaction.id
end

local function canRecruitNpc()
    local fac = SFS.CL.GetMyFaction()
    if not fac then return false end

    local rank = SFS.CL.GetMyRank()
    if rank ~= "admin" and rank ~= "mod" then return true end

    local perms = fac.permissions and fac.permissions[rank]
    if not perms or perms.recruitNpc == nil then return true end
    return perms.recruitNpc == true
end

local lastUsePress = 0

hook.Add("PlayerBindPress", "SFS_SquadRecruitDoubleTap", function(ply, bind, pressed)
    if bind ~= "+use" or not pressed then return end

    local now = CurTime()
    local isDoubleTap = (now - lastUsePress) <= SFS.Config.SquadDoubleTapWindow
    lastUsePress = now
    if not isDoubleTap then return end

    local tr = ply:GetEyeTrace()
    local npc = tr.Entity
    if not IsValid(npc) or not npc:IsNPC() then return end
    if ply:GetPos():DistToSqr(npc:GetPos()) > SFS.Config.SquadRecruitRange ^ 2 then return end

    if isOwnSquadNPC(npc) then
        net.Start("SFS_SquadDismiss")
            net.WriteEntity(npc)
        net.SendToServer()
        surface.PlaySound("buttons/button10.wav")
    elseif canRecruitNpc() then
        net.Start("SFS_SquadRecruit")
            net.WriteEntity(npc)
        net.SendToServer()
        surface.PlaySound("buttons/button14.wav")
    end
end)

local radial = nil
local _keyWasDown = false

local ATTACK_TRACE_DIST = 2000
local ATTACK_TRACE_HULL = 12

local function resolveTargets(ply)
    local eyePos = ply:EyePos()
    local eyeDir = ply:EyeAngles():Forward()

    local tr = util.TraceHull({
        start   = eyePos,
        endpos  = eyePos + eyeDir * ATTACK_TRACE_DIST,
        mins    = Vector(-ATTACK_TRACE_HULL, -ATTACK_TRACE_HULL, -ATTACK_TRACE_HULL),
        maxs    = Vector(ATTACK_TRACE_HULL, ATTACK_TRACE_HULL, ATTACK_TRACE_HULL),
        filter  = ply,
        mask    = MASK_SHOT,
    })

    local ent = tr.Entity
    if not IsValid(ent) or ent == ply then return nil, nil, nil end

    if ent:IsNPC() then
        if isOwnSquadNPC(ent) then
            if IsValid(ent:GetNWEntity("SFS_SquadEnemy")) then
                return ent, "stop", ent
            end
            return nil, nil, ent
        end
        return ent, "attack", nil
    end

    if ent:IsPlayer() then return ent, "attack", nil end

    return nil, nil, nil
end

local function openRadial()
    if IsValid(radial) then return end

    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()

    radial = vgui.Create("SFS_SquadRadial")
    radial.moveTarget = tr.HitPos
    radial.attackTarget, radial.attackMode, radial.followTarget = resolveTargets(ply)

    gui.EnableScreenClicker(true)
    surface.PlaySound("buttons/button15.wav")
end

local function closeRadial()
    if not IsValid(radial) then return end

    local hovered = radial.hovered
    local moveTarget = radial.moveTarget
    local attackTarget = radial.attackTarget
    local attackMode = radial.attackMode
    local followTarget = radial.followTarget

    radial:Remove()
    radial = nil
    gui.EnableScreenClicker(false)

    if hovered == "move" then
        net.Start("SFS_SquadCommand")
            net.WriteUInt(1, 8)
            net.WriteVector(moveTarget)
        net.SendToServer()
        surface.PlaySound("buttons/button9.wav")
    elseif hovered == "attack" and IsValid(attackTarget) then
        if attackMode == "stop" then
            net.Start("SFS_SquadCommand")
                net.WriteUInt(4, 8)
                net.WriteEntity(attackTarget)
            net.SendToServer()
            surface.PlaySound("buttons/button10.wav")
        else
            net.Start("SFS_SquadCommand")
                net.WriteUInt(2, 8)
                net.WriteEntity(attackTarget)
            net.SendToServer()
            surface.PlaySound("buttons/button17.wav")
        end
    elseif hovered == "follow" and IsValid(followTarget) then
        net.Start("SFS_SquadCommand")
            net.WriteUInt(3, 8)
            net.WriteEntity(followTarget)
        net.SendToServer()
        surface.PlaySound("buttons/button8.wav")
    end
end

hook.Add("Think", "SFS_SquadRadialKey", function()
    if vgui.GetKeyboardFocus() ~= nil or gui.IsGameUIVisible() then
        if IsValid(radial) then closeRadial() end
        _keyWasDown = false
        return
    end

    local isDown = input.IsKeyDown(SFS.CL.SquadKey:GetInt())

    if isDown and not _keyWasDown then
        openRadial()
    elseif not isDown and _keyWasDown then
        closeRadial()
    end

    _keyWasDown = isDown
end)

local function ringSlice(cx, cy, rOuter, rInner, aStart, aEnd)
    local segments = 24
    local verts = {}

    for i = 0, segments do
        local a = math.rad(Lerp(i / segments, aStart, aEnd))
        verts[#verts + 1] = { x = cx + math.cos(a) * rOuter, y = cy + math.sin(a) * rOuter }
    end

    for i = segments, 0, -1 do
        local a = math.rad(Lerp(i / segments, aStart, aEnd))
        verts[#verts + 1] = { x = cx + math.cos(a) * rInner, y = cy + math.sin(a) * rInner }
    end

    surface.DrawPoly(verts)
end

local PANEL = {}

function PANEL:Init()
    local outer = SFS.Config.SquadRadialOuterRadius
    self:SetSize(outer * 2 + 20, outer * 2 + 20)
    self:Center()
    self:SetMouseInputEnabled(false)
    self:SetKeyboardInputEnabled(false)
    self.hovered = nil
end

function PANEL:Think()
    local w, h = self:GetSize()
    local cx, cy = w / 2, h / 2
    local mx, my = self:ScreenToLocal(gui.MousePos())
    local dx, dy = mx - cx, my - cy
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < SFS.Config.SquadRadialDeadzone then
        self.hovered = nil
        return
    end

    if dx < 0 then
        self.hovered = "move"
    elseif dy < 0 then
        self.hovered = "attack"
    else
        self.hovered = "follow"
    end

    if self.hovered == "attack" and not IsValid(self.attackTarget) then
        self.hovered = nil
    elseif self.hovered == "follow" and not IsValid(self.followTarget) then
        self.hovered = nil
    end
end

local function drawShadow(cx, cy, radius)
    local layers = 5
    for i = layers, 1, -1 do
        local grow = i * 3
        local a = 16 * (layers - i + 1)
        draw.RoundedBox(radius + grow, cx - radius - grow, cy - radius - grow + 3, (radius + grow) * 2, (radius + grow) * 2, Color(0, 0, 0, a))
    end
end

local function drawIcon(mat, x, y, size, col)
    surface.SetMaterial(mat)
    surface.SetDrawColor(col.r, col.g, col.b, col.a)
    surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
end

function PANEL:Paint(w, h)
    local cx, cy = w / 2, h / 2
    local outer = SFS.Config.SquadRadialOuterRadius
    local inner = SFS.Config.SquadRadialInnerRadius

    drawShadow(cx, cy, outer)
    draw.RoundedBox(outer, cx - outer, cy - outer, outer * 2, outer * 2, Color(22, 22, 27, 235))

    local moveCol = self.hovered == "move" and Color(70, 130, 220, 255) or Color(40, 40, 48, 235)
    surface.SetDrawColor(moveCol)
    ringSlice(cx, cy, outer - 6, inner, 90, 270)

    local ATTACK_MODE_INFO = {
        attack = { hoverCol = Color(210, 60, 60, 255),  icon = iconAttack, labelKey = "SquadRadialAttack" },
        stop   = { hoverCol = Color(210, 150, 60, 255), icon = iconStop,   labelKey = "SquadRadialStop" },
    }
    local attackInfo = ATTACK_MODE_INFO[self.attackMode] or ATTACK_MODE_INFO.attack

    local attackCol
    if not self.attackTarget then
        attackCol = Color(30, 30, 35, 235)
    elseif self.hovered == "attack" then
        attackCol = attackInfo.hoverCol
    else
        attackCol = Color(40, 40, 48, 235)
    end
    surface.SetDrawColor(attackCol)
    ringSlice(cx, cy, outer - 6, inner, -90, 0)

    local followCol
    if not self.followTarget then
        followCol = Color(30, 30, 35, 235)
    elseif self.hovered == "follow" then
        followCol = Color(70, 170, 120, 255)
    else
        followCol = Color(40, 40, 48, 235)
    end
    surface.SetDrawColor(followCol)
    ringSlice(cx, cy, outer - 6, inner, 0, 90)

    local labelDist = (outer + inner) / 2
    local diagDist = labelDist * 0.7071

    local moveIconCol = self.hovered == "move" and Color(255, 255, 255, 255) or Color(200, 200, 205, 255)
    local attackIconCol = not self.attackTarget and Color(90, 90, 95, 255) or (self.hovered == "attack" and Color(255, 255, 255, 255) or Color(200, 200, 205, 255))
    local followIconCol = not self.followTarget and Color(90, 90, 95, 255) or (self.hovered == "follow" and Color(255, 255, 255, 255) or Color(200, 200, 205, 255))

    drawIcon(iconMove, cx - labelDist, cy - 8, 26, moveIconCol)
    drawIcon(attackInfo.icon, cx + diagDist, cy - diagDist - 8, 26, attackIconCol)
    drawIcon(iconFollow, cx + diagDist, cy + diagDist - 8, 26, followIconCol)

    draw.SimpleText(SFS.CL.StringFor("SquadRadialGo"), "DermaDefault", cx - labelDist, cy + 16, moveIconCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(SFS.CL.StringFor(attackInfo.labelKey), "DermaDefault", cx + diagDist, cy - diagDist + 16, attackIconCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(SFS.CL.StringFor("SquadRadialFollow"), "DermaDefault", cx + diagDist, cy + diagDist + 16, followIconCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("SFS_SquadRadial", PANEL, "EditablePanel")

local matSquadIcon = Material("icon16/cog.png")

local SQUAD_HALO_MAX_DIST_SQ = 2000 * 2000
local SQUAD_INDICATOR_MAX_DIST = 1800
local SQUAD_INDICATOR_MIN_DIST = 80

local CLR_GREEN  = Color(0,   255, 80)
local CLR_YELLOW = Color(255, 220, 0)
local CLR_RED    = Color(255, 50,  50)

local function getHaloColor(hp)
    if hp >= SFS.Config.HaloHealthGreen  then return CLR_GREEN  end
    if hp >= SFS.Config.HaloHealthYellow then return CLR_YELLOW end
    return CLR_RED
end

local _sqSw, _sqSh, _sqSwHalf, _sqShHalf = 0, 0, 0, 0

hook.Add("OnScreenSizeChanged", "SFS_Squad_UpdateScreenSize", function(_, _, nw, nh)
    _sqSw, _sqSh = nw, nh
    _sqSwHalf, _sqShHalf = nw * 0.5, nh * 0.5
end)

hook.Add("InitPostEntity", "SFS_Squad_InitScreenSize", function()
    _sqSw, _sqSh = ScrW(), ScrH()
    _sqSwHalf, _sqShHalf = _sqSw * 0.5, _sqSh * 0.5
end)

local function getMySquadNPCs()
    local myFaction = SFS.CL.GetMyFaction()
    if not myFaction then return {} end

    local myPos = LocalPlayer():GetPos()
    local list = {}

    for _, npc in ipairs(ents.GetAll()) do
        if IsValid(npc) and npc:IsNPC() and npc:GetNWString("SFS_SquadFaction", "") == myFaction.id then
            if myPos:DistToSqr(npc:GetPos()) <= SQUAD_HALO_MAX_DIST_SQ then
                list[#list + 1] = npc
            end
        end
    end

    return list
end

hook.Add("PreDrawHalos", "SFS_DrawSquadHalos", function()
    local squad = getMySquadNPCs()
    if #squad == 0 then return end

    for i = 1, #squad do
        local npc = squad[i]
        halo.Add({ npc }, getHaloColor(npc:Health()), SFS.Config.HaloWidth, SFS.Config.HaloWidth, 1, true, SFS.Config.HaloAddPixelBorder)
    end
end)

local _squadViewOffset = Vector(0, 0, 24)

hook.Add("HUDPaint", "SFS_SquadIndicators", function()
    if _sqSw == 0 then return end

    local squad = getMySquadNPCs()
    if #squad == 0 then return end

    local me    = LocalPlayer()
    local myPos = me:GetPos() + me:GetViewOffset()

    local sz    = 14
    local szH   = sz * 0.5
    local inv52 = 1 / 52.49
    local invMaxDist = 1 / SQUAD_INDICATOR_MAX_DIST

    for i = 1, #squad do
        local npc = squad[i]
        local pos  = npc:GetPos() + _squadViewOffset
        local dist = myPos:Distance(pos)

        if dist < SQUAD_INDICATOR_MIN_DIST or dist > SQUAD_INDICATOR_MAX_DIST then continue end

        local scrPos = pos:ToScreen()
        if scrPos.visible then continue end

        local hp    = npc:Health()
        local hpR   = math.Clamp(hp / 100, 0, 1)
        local r     = math.floor(255 * (1 - hpR) + 0.5)
        local g     = math.floor(255 * hpR + 0.5)
        local alpha = math.Clamp((1 - dist * invMaxDist), 0.2, 1) * 220

        local ang  = math.atan2(scrPos.y - _sqShHalf, scrPos.x - _sqSwHalf)
        local cosA = math.cos(ang)
        local sinA = math.sin(ang)
        local ex   = _sqSwHalf + cosA * (_sqSwHalf - 28)
        local ey   = _sqShHalf + sinA * (_sqShHalf - 28)
        ex = math.Clamp(ex, 24, _sqSw - 24)
        ey = math.Clamp(ey, 24, _sqSh - 24)

        surface.SetDrawColor(r, g, 60, alpha)
        surface.SetMaterial(matSquadIcon)
        surface.DrawTexturedRect(ex - szH, ey - szH, sz, sz)

        local distM = math.floor(dist * inv52 + 0.5)
        draw.SimpleTextOutlined(
            distM .. "m", "DermaDefault",
            ex, ey + sz,
            Color(255, 255, 255, alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP,
            1, Color(0, 0, 0, alpha)
        )
        draw.SimpleTextOutlined(
            npc:GetClass(), "DermaDefault",
            ex, ey - sz - 2,
            Color(r, g, 60, alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM,
            1, Color(0, 0, 0, alpha)
        )
    end
end)

SFS:print("Squad client loaded")
