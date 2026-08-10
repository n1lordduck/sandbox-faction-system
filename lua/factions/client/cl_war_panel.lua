local SFS = SandboxFactionSystem

surface.CreateFont("SFS_WarFacName", { font="Tahoma", size=14, weight=700, antialias=true })
surface.CreateFont("SFS_WarKillNum", { font="Tahoma", size=18, weight=700, antialias=true })
surface.CreateFont("SFS_WarTimer",   { font="Tahoma", size=13, weight=700, antialias=true })
surface.CreateFont("SFS_WarSmall",   { font="Tahoma", size=12, weight=400, antialias=true })
surface.CreateFont("SFS_WarNotice",  { font="Tahoma", size=20, weight=700, antialias=true })

local NET_CD = {}
local function warCD(name)
    local now = RealTime()
    if NET_CD[name] and now - NET_CD[name] < 1.5 then return false end
    NET_CD[name] = now
    return true
end

local function timeLeft(war)
    local r = (war.startTime + (SFS.Config.WarDuration or 3600)) - os.time()
    if r < 0 then r = 0 end
    return string.format("%02d:%02d", math.floor(r / 60), r % 60)
end

local _warIconCache = {}

local function getWarFacMat(fac)
    if not fac or not fac.icon or fac.icon == "" then return Material("icon16/group.png") end
    if fac.icon:sub(1, 7) == "icon16/" then return Material(fac.icon) end
    if _warIconCache[fac.icon] then return _warIconCache[fac.icon] end
    if SFS.Config.AllowImgurPictures then
        local fname = "sfs_icons/" .. fac.icon:gsub("[^%w]", "_"):sub(1, 60) .. ".png"
        if file.Exists(fname, "DATA") then
            local mat = Material("../data/" .. fname, "noclamp smooth")
            if mat and not mat:IsError() then
                _warIconCache[fac.icon] = mat
                return mat
            end
        end
    end
    return Material("icon16/group.png")
end

local function drawSideList(parent, war, sideKey, x, y, w, h)
    local sideFacs = sideKey == "side1" and war.side1 or war.side2
    local leaderID = sideKey == "side1" and war.side1Leader or war.side2Leader
    local list = vgui.Create("DListView", parent)
    list:SetPos(x, y)
    list:SetSize(w, h)
    list:SetMultiSelect(false)
    list:AddColumn("Faction"):SetWidth(w - 50)
    list:AddColumn("Mem."):SetWidth(44)
    for facID in pairs(sideFacs) do
        local fac = SFS.CL.GetFactionByID(facID)
        if not fac then continue end
        local mc  = 1 + table.Count(fac.subowners or {}) + table.Count(fac.members or {})
        local tag = facID == leaderID and ("[Leader] " .. fac.name) or fac.name
        list:AddLine(tag, tostring(mc))
    end
    return list
end

local PAD = 8
local KBH = 24
local NMH = 20
local LH  = 96
local TMH = 20
local BTH = 24
local SEP = 4

local function calcH(hasBtn)
    return PAD + TMH + SEP + KBH + SEP + NMH + SEP + LH + SEP + (hasBtn and (BTH + SEP) or 0) + PAD
end

local function buildWarEntry(parent, war, yOff, W)
    local fac1 = SFS.CL.GetFactionByID(war.side1Leader)
    local fac2 = SFS.CL.GetFactionByID(war.side2Leader)
    local n1   = fac1 and fac1.name or "?"
    local n2   = fac2 and fac2.name or "?"

    local myFac    = SFS.CL.GetMyFaction()
    local myRank   = myFac and SFS.CL.GetMyRank()
    local isLeader = myFac and myRank == "owner" and
        (war.side1Leader == myFac.id or war.side2Leader == myFac.id)
    local isAlly = myFac and myRank == "owner" and not isLeader and
        (war.side1[myFac.id] or war.side2[myFac.id])
    local showBtn  = isLeader or isAlly
    local entH     = calcH(showBtn)
    local sideW    = math.floor((W - PAD * 2 - 36) * 0.5)
    local s2X      = PAD + sideW + 36

    local entry = vgui.Create("DPanel", parent)
    entry:SetPos(0, yOff)
    entry:SetSize(W, entH)
    entry.Paint = function(_, sw, sh)
        surface.SetDrawColor(218, 218, 218)
        surface.DrawRect(0, 0, sw, sh)
        surface.SetDrawColor(148, 148, 148)
        surface.DrawOutlinedRect(0, 0, sw, sh)
    end

    local cy = PAD

    local timerIco = vgui.Create("DImage", entry)
    timerIco:SetPos(PAD, cy + 2)
    timerIco:SetSize(16, 16)
    timerIco:SetImage("icon16/clock.png")

    local timerLbl = vgui.Create("DLabel", entry)
    timerLbl:SetPos(PAD + 20, cy)
    timerLbl:SetSize(80, TMH)
    timerLbl:SetFont("SFS_WarTimer")
    timerLbl:SetTextColor(Color(50, 50, 50))
    timerLbl:SetText(timeLeft(war))

    local inProgLbl = vgui.Create("DLabel", entry)
    inProgLbl:SetPos(PAD + 106, cy)
    inProgLbl:SetSize(200, TMH)
    inProgLbl:SetFont("SFS_WarSmall")
    inProgLbl:SetTextColor(Color(150, 60, 60))
    inProgLbl:SetText("War in progress")

    hook.Add("Think", "SFS_WTick_" .. war.id .. "_" .. tostring(timerLbl), function()
        if not IsValid(timerLbl) then
            hook.Remove("Think", "SFS_WTick_" .. war.id .. "_" .. tostring(timerLbl))
            return
        end
        timerLbl:SetText(timeLeft(war))
    end)

    cy = cy + TMH + SEP

    local kbW    = W - PAD * 2
    local barPnl = vgui.Create("DPanel", entry)
    barPnl:SetPos(PAD, cy)
    barPnl:SetSize(kbW, KBH)
    barPnl.Paint = function(_, sw, sh)
        local cs1 = war.side1Kills or 0
        local cs2 = war.side2Kills or 0
        local tot = cs1 + cs2
        surface.SetDrawColor(185, 185, 185)
        surface.DrawRect(0, 0, sw, sh)
        if tot > 0 then
            local s1w = math.floor(sw * cs1 / tot)
            if s1w > 0 then
                surface.SetDrawColor(60, 100, 210)
                surface.DrawRect(0, 0, s1w, sh)
            end
            if sw - s1w > 0 then
                surface.SetDrawColor(200, 55, 55)
                surface.DrawRect(s1w, 0, sw - s1w, sh)
            end
        end
        surface.SetDrawColor(118, 118, 118)
        surface.DrawOutlinedRect(0, 0, sw, sh)
        draw.SimpleText(tostring(cs1), "SFS_WarKillNum", 6, sh * 0.5, Color(255,255,255), TEXT_ALIGN_LEFT,   TEXT_ALIGN_CENTER)
        draw.SimpleText("kills",       "SFS_WarSmall",  sw * 0.5, sh * 0.5, Color(40,40,40),  TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(cs2), "SFS_WarKillNum", sw - 6,  sh * 0.5, Color(255,255,255), TEXT_ALIGN_RIGHT,  TEXT_ALIGN_CENTER)
    end

    cy = cy + KBH + SEP

    local ico1 = vgui.Create("DPanel", entry)
    ico1:SetPos(PAD, cy + 2)
    ico1:SetSize(16, 16)
    local m1 = getWarFacMat(fac1)
    ico1.Paint = function(_, w, h)
        surface.SetMaterial(m1) surface.SetDrawColor(255,255,255,255) surface.DrawTexturedRect(0,0,w,h)
    end

    local n1Lbl = vgui.Create("DLabel", entry)
    n1Lbl:SetPos(PAD + 20, cy)
    n1Lbl:SetSize(sideW - 20, NMH)
    n1Lbl:SetFont("SFS_WarFacName")
    n1Lbl:SetTextColor(Color(40, 80, 200))
    n1Lbl:SetText(n1)

    local vsIco = vgui.Create("DImage", entry)
    vsIco:SetPos(PAD + sideW + 10, cy + 2)
    vsIco:SetSize(16, 16)
    vsIco:SetImage("icon16/bomb.png")

    local ico2 = vgui.Create("DPanel", entry)
    ico2:SetPos(s2X, cy + 2)
    ico2:SetSize(16, 16)
    local m2 = getWarFacMat(fac2)
    ico2.Paint = function(_, w, h)
        surface.SetMaterial(m2) surface.SetDrawColor(255,255,255,255) surface.DrawTexturedRect(0,0,w,h)
    end

    local n2Lbl = vgui.Create("DLabel", entry)
    n2Lbl:SetPos(s2X + 20, cy)
    n2Lbl:SetSize(sideW - 20, NMH)
    n2Lbl:SetFont("SFS_WarFacName")
    n2Lbl:SetTextColor(Color(190, 50, 50))
    n2Lbl:SetText(n2)

    cy = cy + NMH + SEP

    drawSideList(entry, war, "side1", PAD, cy, sideW, LH)
    drawSideList(entry, war, "side2", s2X, cy, sideW, LH)

    cy = cy + LH + SEP

    if showBtn then
        local btn = vgui.Create("DButton", entry)
        btn:SetPos(PAD, cy)
        btn:SetSize(kbW, BTH)
        btn:SetImage("icon16/flag_white.png")

        if isAlly then
            btn:SetText("Withdraw from War")
        else
            local mySide = war.side1[myFac.id] and "side1" or "side2"
            if war.truceRequested == mySide then
                btn:SetText("Truce requested — waiting for the other side...")
                btn:SetEnabled(false)
            elseif war.truceRequested and war.truceRequested ~= mySide then
                btn:SetText("Accept Truce (enemy requested)")
            else
                btn:SetText("Request Truce")
            end
        end

        btn.DoClick = function()
            if not warCD("truce_" .. war.id) then return end
            net.Start("SFS_RequestTruce")
            net.WriteString(war.id)
            net.SendToServer()
        end
    end

    return entH
end

function SFS.BuildWarTab(sheet)
    local pnl = vgui.Create("DPanel", sheet)
    pnl:Dock(FILL)
    pnl.Paint = function() end

    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    scroll:GetVBar():SetWide(8)

    local inner = vgui.Create("DPanel", scroll)
    inner:Dock(TOP)
    inner:SetTall(0)
    inner.Paint = function() end

    local W = 0

    local function populate()
        if not IsValid(inner) then return end
        inner:Clear()

        if W < 50 then W = IsValid(pnl) and (pnl:GetWide() - 20) or 740 end

        local wars = SFS.CL.GetActiveWars()
        local yOff = 6

        local hdr = vgui.Create("DLabel", inner)
        hdr:SetPos(4, yOff)
        hdr:SetSize(W - 8, 18)
        hdr:SetFont("SFS_WarFacName")
        hdr:SetTextColor(Color(60, 60, 60))
        yOff = yOff + 24

        if #wars > 0 then
            hdr:SetText("Active wars: " .. #wars)
            for _, war in ipairs(wars) do
                local h = buildWarEntry(inner, war, yOff, W)
                yOff = yOff + h + 6
            end
        else
            hdr:SetText("No active wars.")
            hdr:SetTextColor(Color(200, 30, 130))
            local sub = vgui.Create("DLabel", inner)
            sub:SetPos(0, yOff)
            sub:SetSize(W, 24)
            sub:SetFont("SFS_WarSmall")
            sub:SetTextColor(Color(200, 40, 140))
            sub:SetText("Declare war from the Manage Faction tab.")
            sub:SetContentAlignment(5)
            yOff = yOff + 30
        end

        inner:SetTall(yOff + 8)
    end

    pnl.PerformLayout = function(self, w, h)
        W = w - 20
        populate()
        pnl.PerformLayout = nil
    end

    local hk = "SFS_WarTab_" .. tostring(pnl)
    hook.Add("SFS_WarsUpdated",     hk, function()
        if not IsValid(pnl) then hook.Remove("SFS_WarsUpdated", hk) return end
        if W < 50 then W = pnl:GetWide() - 20 end
        populate()
    end)
    hook.Add("SFS_FactionsUpdated", hk, function()
        if not IsValid(pnl) then hook.Remove("SFS_FactionsUpdated", hk) return end
        if W < 50 then W = pnl:GetWide() - 20 end
        populate()
    end)

    return pnl
end

SFS:print("War panel loaded")
