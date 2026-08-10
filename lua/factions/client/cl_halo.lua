local SFS = SandboxFactionSystem

local HALO_MAX_DIST_SQ   = 2000 * 2000
local INDICATOR_MAX_DIST = 1800
local INDICATOR_MIN_DIST = 80

local matHeart = Material("icon16/heart.png")
local matStar  = Material("icon16/star.png")

local CLR_GREEN  = Color(0,   255, 80)
local CLR_YELLOW = Color(255, 220, 0)
local CLR_RED    = Color(255, 50,  50)

local function getHaloColor(hp)
    if hp >= SFS.Config.HaloHealthGreen  then return CLR_GREEN  end
    if hp >= SFS.Config.HaloHealthYellow then return CLR_YELLOW end
    return CLR_RED
end

local _sw, _sh = 0, 0
local _swHalf, _shHalf = 0, 0

hook.Add("OnScreenSizeChanged", "SFS_UpdateScreenSize", function(_, _, nw, nh)
    _sw, _sh         = nw, nh
    _swHalf, _shHalf = nw * 0.5, nh * 0.5
end)

hook.Add("InitPostEntity", "SFS_InitScreenSize", function()
    _sw, _sh         = ScrW(), ScrH()
    _swHalf, _shHalf = _sw * 0.5, _sh * 0.5
end)

local _haloRenderList = {}

local function buildHaloList()
    local myFaction = SFS.CL.GetMyFaction()
    if not myFaction or myFaction.haloEnabled == false then
        _haloRenderList = {}
        return
    end

    local myPos  = LocalPlayer():GetPos()
    local mates  = SFS.CL.GetFactionMates()
    local allies = SFS.CL.GetAlliesOf()
    local seen   = {}
    local list   = {}

    for i = 1, #mates do
        local ply = mates[i]
        if IsValid(ply) and not seen[ply] then
            if myPos:DistToSqr(ply:GetPos()) <= HALO_MAX_DIST_SQ then
                seen[ply] = true
                list[#list + 1] = { ply = ply, color = getHaloColor(ply:Health()) }
            end
        end
    end

    for i = 1, #allies do
        local ply = allies[i]
        if IsValid(ply) and not seen[ply] then
            if myPos:DistToSqr(ply:GetPos()) <= HALO_MAX_DIST_SQ then
                seen[ply] = true
                list[#list + 1] = { ply = ply, color = getHaloColor(ply:Health()) }
            end
        end
    end

    _haloRenderList = list
end

hook.Add("PreDrawHalos", "SFS_DrawFactionHalos", function()
    buildHaloList()
    if #_haloRenderList == 0 then return end

    for i = 1, #_haloRenderList do
        local e = _haloRenderList[i]
        halo.Add({ e.ply }, e.color, SFS.Config.HaloWidth, SFS.Config.HaloWidth, 1, true, SFS.Config.HaloAddPixelBorder)
    end
end)

local _viewOffset = Vector(0, 0, 64)

hook.Add("HUDPaint", "SFS_FactionIndicators", function()
    local myFaction = SFS.CL.GetMyFaction()
    if not myFaction or myFaction.haloEnabled == false then return end
    if _sw == 0 then return end

    local me    = LocalPlayer()
    local myPos = me:GetPos() + me:GetViewOffset()
    local mates  = SFS.CL.GetFactionMates()
    local allies = SFS.CL.GetAlliesOf()

    local sz     = 14
    local szH    = sz * 0.5
    local inv52  = 1 / 52.49
    local inv100 = 1 / 100
    local invMaxDist = 1 / INDICATOR_MAX_DIST

    for pass = 1, 2 do
        local list   = pass == 1 and mates or allies
        local isMate = pass == 1
        local mat    = isMate and matHeart or matStar

        for i = 1, #list do
            local ply = list[i]
            if not IsValid(ply) then continue end

            local pos  = ply:GetPos() + _viewOffset
            local dist = myPos:Distance(pos)

            if dist < INDICATOR_MIN_DIST or dist > INDICATOR_MAX_DIST then continue end

            local scrPos = pos:ToScreen()
            if scrPos.visible then continue end

            local hp    = ply:Health()
            local hpR   = math.Clamp(hp * inv100, 0, 1)
            local r     = math.floor(255 * (1 - hpR) + 0.5)
            local g     = math.floor(255 * hpR + 0.5)
            local alpha = math.Clamp((1 - dist * invMaxDist), 0.2, 1) * 220

            local ang  = math.atan2(scrPos.y - _shHalf, scrPos.x - _swHalf)
            local cosA = math.cos(ang)
            local sinA = math.sin(ang)
            local ex   = _swHalf + cosA * (_swHalf - 28)
            local ey   = _shHalf + sinA * (_shHalf - 28)
            ex = math.Clamp(ex, 24, _sw - 24)
            ey = math.Clamp(ey, 24, _sh - 24)

            surface.SetDrawColor(r, g, 60, alpha)
            surface.SetMaterial(mat)
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
                ply:Nick(), "DermaDefault",
                ex, ey - sz - 2,
                Color(r, g, 60, alpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM,
                1, Color(0, 0, 0, alpha)
            )
        end
    end
end)

SFS:print("Halo renderer loaded")
