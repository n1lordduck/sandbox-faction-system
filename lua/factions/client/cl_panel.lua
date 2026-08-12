local SFS = SandboxFactionSystem

local activePanel = nil
local selectedFac = nil

local NET_CD = {}
local NET_CD_TIME = 0.5

local function netCooldown(name)
    local now = RealTime()
    if NET_CD[name] and now - NET_CD[name] < NET_CD_TIME then return false end
    NET_CD[name] = now
    return true
end

local SFS_ICON16_LIST = {
    "icon16/accept.png","icon16/add.png","icon16/anchor.png","icon16/award_star_gold_1.png",
    "icon16/bomb.png","icon16/book.png","icon16/brick.png","icon16/building.png",
    "icon16/bullet_blue.png","icon16/bullet_green.png","icon16/bullet_red.png",
    "icon16/camera.png","icon16/car.png","icon16/chart_bar.png","icon16/clock.png",
    "icon16/cog.png","icon16/comment.png","icon16/connect.png","icon16/controller.png",
    "icon16/cross.png","icon16/crown.png","icon16/database.png","icon16/death.png",
    "icon16/door.png","icon16/emotion_evilgrin.png","icon16/emotion_grin.png",
    "icon16/error.png","icon16/exclamation.png","icon16/eye.png","icon16/fire.png",
    "icon16/flag_blue.png","icon16/flag_green.png","icon16/flag_orange.png",
    "icon16/flag_red.png","icon16/flag_yellow.png","icon16/folder.png",
    "icon16/gun.png","icon16/hand.png","icon16/heart.png","icon16/help.png",
    "icon16/home.png","icon16/key.png","icon16/lightning.png","icon16/lock.png",
    "icon16/map.png","icon16/medal_gold_1.png","icon16/money.png","icon16/music.png",
    "icon16/package.png","icon16/paintbrush.png","icon16/pill.png","icon16/rocket.png",
    "icon16/ruby.png","icon16/shield.png","icon16/skull.png","icon16/star.png",
    "icon16/status_online.png","icon16/stop.png","icon16/sword.png","icon16/tag.png",
    "icon16/tick.png","icon16/trophy.png","icon16/user.png","icon16/user_add.png",
    "icon16/user_delete.png","icon16/user_red.png","icon16/user_suit.png",
    "icon16/users.png","icon16/group.png","icon16/groups.png","icon16/world.png",
    "icon16/wrench.png","icon16/zoom.png",
}

local iconMatCache     = {}
local iconGlobalVersion = 0
local SPINNER_MAT = Material("icon16/arrow_refresh.png")
local iconFetching      = {}

local function isIcon16(url)
    return url and url:sub(1, 7) == "icon16/"
end

local function isURL(url)
    return url and (url:sub(1, 7) == "http://" or url:sub(1, 8) == "https://")
end

local function urlToFilename(url)
    local name = url:gsub("[^%w]", "_"):sub(1, 60)
    return "sfs_icons/" .. name .. ".png"
end

local function fetchImageMaterial(url, onReady)
    if iconMatCache[url] then onReady(iconMatCache[url]) return end
    if iconFetching[url] then return end
    iconFetching[url] = true

    local fname = urlToFilename(url)
    local fpath = "data/" .. fname

    local useCache = GetConVar("sfs_icon_cache") and GetConVar("sfs_icon_cache"):GetBool()

    if useCache and file.Exists(fname, "DATA") then
        local mat = Material("../data/" .. fname, "noclamp smooth")
        if mat and not mat:IsError() then
            SFS:print("[DEBUG] Icon loaded from cache file: " .. fname)
            iconMatCache[url] = mat
            iconFetching[url] = nil
            onReady(mat)
            return
        end
    end

    if not file.IsDir("sfs_icons", "DATA") then
        file.CreateDir("sfs_icons")
    end

    SFS:print("[DEBUG] Fetching icon via http.Fetch: " .. url)
    http.Fetch(url,
        function(body, size, headers, code)
            SFS:print("[DEBUG] http.Fetch response: code=" .. tostring(code) .. " size=" .. tostring(size))
            if code ~= 200 or not body or #body == 0 then
                SFS:print("[DEBUG] Icon fetch failed: code=" .. tostring(code))
                iconFetching[url] = nil
                onReady(Material(SFS.Config.DefaultIconMaterial))
                return
            end
            local maxBytes = (SFS.Config.IconMaxSizeMB or 20) * 1024 * 1024
            if maxBytes > 0 and #body > maxBytes then
                SFS:print("[DEBUG] Icon too large: " .. math.floor(#body / 1024) .. "KB > limit " .. (SFS.Config.IconMaxSizeMB or 20) .. "MB, skipping: " .. url)
                iconFetching[url] = nil
                onReady(Material(SFS.Config.DefaultIconMaterial))
                return
            end
            if useCache then
                file.Write(fname, body)
                SFS:print("[DEBUG] Icon saved to: " .. fpath)
            else
                SFS:print("[DEBUG] Cache disabled, not saving to disk.")
            end
            local mat = Material("../data/" .. fname, "noclamp smooth")
            if mat and not mat:IsError() then
                iconMatCache[url] = mat
                iconFetching[url] = nil
                onReady(mat)
            else
                SFS:print("[DEBUG] Material() failed after save for: " .. fname)
                iconFetching[url] = nil
                onReady(Material(SFS.Config.DefaultIconMaterial))
            end
        end,
        function(err)
            SFS:print("[DEBUG] http.Fetch error: " .. tostring(err) .. " url=" .. url)
            iconFetching[url] = nil
            onReady(Material(SFS.Config.DefaultIconMaterial))
        end,
        { ["User-Agent"] = "Mozilla/5.0", ["Accept"] = "image/png,image/jpeg,image/*" }
    )
end

local function getIconMat(url)
    if not url or url == "" then
        return Material(SFS.Config.DefaultIconMaterial)
    end
    if isIcon16(url) then
        if not iconMatCache[url] then
            iconMatCache[url] = Material(url)
        end
        return iconMatCache[url]
    end
    if isURL(url) then
        return iconMatCache[url] or Material(SFS.Config.DefaultIconMaterial)
    end
    return Material(SFS.Config.DefaultIconMaterial)
end

local function getIconMatAsync(url, pnl)
    if not url or url == "" then return end
    if not isURL(url) then return end
    if not SFS.Config.AllowImgurPictures then
        SFS:print("[DEBUG] Imgur disabled by server, skipping: " .. url)
        return
    end
    if iconMatCache[url] then
        if IsValid(pnl) then
            pnl._mat = iconMatCache[url]
            pnl:InvalidateLayout(true)
        end
        return
    end
    fetchImageMaterial(url, function(mat)
        iconMatCache[url] = mat
        --// pnl._mat was still whatever getIconMat() returned at panel-creation
        --// time (the default icon, since nothing was cached yet) - Paint reads
        --// pnl._mat every frame, so without this reassignment the panel keeps
        --// showing the default icon forever even though the fetch succeeded.
        if IsValid(pnl) then
            pnl._mat = mat
            pnl:InvalidateLayout(true)
        end
    end)
end

--// Shared with any other panel that needs a faction icon (e.g. cl_war_panel.lua)
--// so there's one fetch+cache path and one live-update fix, not a second
--// parallel cache that can go stale independently.
SFS.CL.GetIconMatSync  = getIconMat
SFS.CL.GetIconMatAsync = getIconMatAsync

local function applyIconToPnl(pnl, url, w, h)
    if isIcon16(url) then
        if IsValid(pnl._img) then pnl._img:Remove() end
        pnl._mat = nil
        local img = vgui.Create("DImage", pnl)
        img:SetPos(0, 0) img:SetSize(w, h)
        img:SetImage(url) img:SetKeepAspect(true)
        pnl._img = img
        pnl.Paint = function() end
    elseif isURL(url) then
        if IsValid(pnl._img) then pnl._img:Remove() pnl._img = nil end
        pnl._mat = getIconMat(url)
        pnl.Paint = function(s, sw, sh)
            --// Still fetching and nothing cached yet - spin instead of just
            --// silently sitting on the default icon with no feedback at all.
            if iconFetching[url] and not iconMatCache[url] then
                surface.SetDrawColor(255, 255, 255, 255)
                surface.SetMaterial(SPINNER_MAT)
                surface.DrawTexturedRectRotated(sw * 0.5, sh * 0.5, sw, sh, (RealTime() * 220) % 360)
                return
            end
            surface.SetMaterial(s._mat or Material(SFS.Config.DefaultIconMaterial))
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(0, 0, sw, sh)
        end
        getIconMatAsync(url, pnl)
    else
        if IsValid(pnl._img) then pnl._img:Remove() pnl._img = nil end
        pnl._mat = Material(SFS.Config.DefaultIconMaterial)
        pnl.Paint = function(s, sw, sh)
            surface.SetMaterial(s._mat)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(0, 0, sw, sh)
        end
    end
end

local function createIconPanel(parent, x, y, w, h, iconUrl)
    iconUrl = iconUrl or SFS.Config.DefaultIconMaterial
    local pnl = vgui.Create("DPanel", parent)
    pnl:SetPos(x, y)
    pnl:SetSize(w, h)
    pnl.Paint = function() end
    applyIconToPnl(pnl, iconUrl, w, h)
    pnl.SetIcon = function(self, newUrl)
        iconUrl = newUrl
        applyIconToPnl(self, newUrl, w, h)
    end
    return pnl
end

hook.Add("SFS_FactionsUpdated", "SFS_ClearIconCache", function()
    iconGlobalVersion = iconGlobalVersion + 1
    iconMatCache = {}
end)

local function openIconPicker(onSelect)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Pick Icon")
    frame:SetSize(520, 400)
    frame:Center()
    frame:MakePopup()
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(4, 4, 4, 4)
    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(FILL)
    grid:SetSpaceX(4)
    grid:SetSpaceY(4)
    for _, iconPath in ipairs(SFS_ICON16_LIST) do
        local btn = vgui.Create("DImageButton", grid)
        btn:SetSize(32, 32)
        btn:SetImage(iconPath)
        btn:SetTooltip(iconPath)
        btn.DoClick = function() onSelect(iconPath) frame:Remove() end
    end
end

local function buildIconRow(parent, currentIcon)
    local pnl = vgui.Create("DPanel", parent)
    pnl:SetSize(730, 26)
    pnl.Paint = function() end

    local entry = vgui.Create("DTextEntry", pnl)
    entry:SetPos(0, 0)
    entry:SetSize(640, 24)
    entry:SetText(currentIcon or "")
    if SFS.Config.AllowImgurPictures then
        entry:SetPlaceholderText("imgur URL or icon16/... path")
    else
        entry:SetPlaceholderText("icon16/... path (imgur disabled by server)")
        entry:SetEnabled(true)
    end

    --// DImage:SetImage() only resolves local material paths - it can't fetch
    --// an actual http(s) URL, so a raw imgur link here just showed nothing.
    --// createIconPanel already knows how to fetch+cache+live-update a URL
    --// (same path the real faction icons use), so reuse that instead.
    local preview = createIconPanel(pnl, 646, 0, 24, 24,
        (currentIcon and currentIcon ~= "") and currentIcon or SFS.Config.DefaultIconMaterial)

    local pickBtn = vgui.Create("DButton", pnl)
    pickBtn:SetPos(676, 0)
    pickBtn:SetSize(54, 24)
    pickBtn:SetText("Browse")
    pickBtn.DoClick = function()
        openIconPicker(function(chosen)
            entry:SetText(chosen)
            preview:SetIcon(chosen)
        end)
    end

    local previewTimerName = "SFS_IconPreview_" .. tostring(entry)
    entry.OnChange = function(s)
        local v = s:GetValue():Trim()
        if v == "" or v:sub(1, 7) == "icon16/" then
            timer.Remove(previewTimerName)
            preview:SetIcon(v ~= "" and v or SFS.Config.DefaultIconMaterial)
        elseif v:sub(1, 7) == "http://" or v:sub(1, 8) == "https://" then
            --// Debounced - typing/pasting a URL fires OnChange per keystroke,
            --// don't kick off an HTTP fetch for every partial/incomplete one.
            timer.Create(previewTimerName, 0.6, 1, function()
                if not IsValid(entry) then return end
                local cur = entry:GetValue():Trim()
                if cur == v then preview:SetIcon(cur) end
            end)
        end
    end

    pnl.GetValue = function() return entry:GetValue():Trim() end
    return pnl
end

local function getMemberRankLabel(faction, rank)
    if rank == "owner"    then return "Owner" end
    if rank == "subowner" then return "Sub-Owner" end
    if faction and faction.ranks and faction.ranks[rank] then
        return faction.ranks[rank].label or rank
    end
    return rank or "Member"
end

local function buildFactionBrowser(sheet)
    local pnl = vgui.Create("DPanel", sheet)
    pnl.Paint = function() end

    local list = vgui.Create("DListView", pnl)
    list:SetPos(8, 8)
    list:SetSize(270, 460)
    list:SetMultiSelect(false)
    list:AddColumn("Faction"):SetWidth(160)
    list:AddColumn("Members"):SetWidth(55)
    list:AddColumn("Type"):SetWidth(55)

    local detail = vgui.Create("DPanel", pnl)
    detail:SetPos(290, 8)
    detail:SetSize(470, 460)
    detail.Paint = function(_, sw, sh)
        surface.SetDrawColor(240, 240, 240)
        surface.DrawRect(0, 0, sw, sh)
        surface.SetDrawColor(180, 180, 180)
        surface.DrawOutlinedRect(0, 0, sw, sh)
    end

    local function showFaction(faction)
        detail:Clear()
        if not faction then return end

        local myFac   = SFS.CL.GetMyFaction()
        local steamid = LocalPlayer():SteamID()
        local isMine  = myFac and myFac.id == faction.id

        local iconPnl = createIconPanel(detail, 8, 8, 48, 48, faction.icon or SFS.Config.DefaultIconMaterial)

        local nameLbl = vgui.Create("DLabel", detail)
        nameLbl:SetPos(64, 8) nameLbl:SetSize(400, 24)
        nameLbl:SetText(faction.name) nameLbl:SetFont("DermaLarge")

        local descLbl = vgui.Create("DLabel", detail)
        descLbl:SetPos(64, 32) descLbl:SetSize(400, 18)
        descLbl:SetText(faction.desc or "") descLbl:SetTextColor(Color(100, 100, 100))

        local pubLbl = vgui.Create("DLabel", detail)
        pubLbl:SetPos(64, 50) pubLbl:SetSize(400, 18)
        pubLbl:SetText(faction.public and "Public" or "Private")
        pubLbl:SetTextColor(faction.public and Color(0, 150, 0) or Color(180, 120, 0))

        local sep = vgui.Create("DPanel", detail)
        sep:SetPos(8, 70) sep:SetSize(454, 1)
        sep.Paint = function(_, sw, sh) surface.SetDrawColor(180, 180, 180) surface.DrawRect(0, 0, sw, sh) end

        local memberList = vgui.Create("DListView", detail)
        memberList:SetPos(8, 78) memberList:SetSize(454, 290)
        memberList:SetMultiSelect(false)
        memberList:AddColumn("Player"):SetWidth(220)
        memberList:AddColumn("Rank"):SetWidth(120)
        memberList:AddColumn("Status"):SetWidth(80)

        local function addRow(sid, rankLabel)
            local onlinePly = nil
            for _, p in ipairs(player.GetAll()) do
                if p:SteamID() == sid then onlinePly = p break end
            end
            local nick   = IsValid(onlinePly) and onlinePly:Nick() or sid
            local status = IsValid(onlinePly) and "Online" or "Offline"
            memberList:AddLine(nick, rankLabel, status)
        end

        addRow(faction.owner, "Owner")
        if faction.subowners then
            for sid, _ in pairs(faction.subowners) do addRow(sid, "Sub-Owner") end
        end
        if faction.members then
            for sid, data in pairs(faction.members) do
                addRow(sid, getMemberRankLabel(faction, data.rank or "member"))
            end
        end

        if not isMine and not myFac then
            local btnY = 380
            if faction.public then
                local btn = vgui.Create("DButton", detail)
                btn:SetPos(8, btnY) btn:SetSize(454, 30)
                btn:SetText("Join Faction")
                btn.DoClick = function()
                    if not netCooldown("joinpublic") then return end
                    net.Start("SFS_JoinPublic") net.WriteString(faction.id) net.SendToServer()
                    if IsValid(activePanel) then activePanel:Remove() end
                end
            else
                local alreadyReq = faction.requests and faction.requests[steamid]
                local btn = vgui.Create("DButton", detail)
                btn:SetPos(8, btnY) btn:SetSize(454, 30)
                btn:SetText(alreadyReq and "Request Sent" or "Request to Join")
                btn:SetEnabled(not alreadyReq)
                btn.DoClick = function()
                    if not netCooldown("reqjoin") then return end
                    net.Start("SFS_RequestJoin") net.WriteString(faction.id) net.SendToServer()
                    btn:SetText("Request Sent")
                    btn:SetEnabled(false)
                end
            end
        end
    end

    local function refreshList()
        list:Clear()
        local rows = {}
        for _, f in pairs(SFS.CL.Factions) do table.insert(rows, f) end
        table.sort(rows, function(a, b) return a.name < b.name end)
        for _, f in ipairs(rows) do
            local mc = table.Count(f.members or {}) + table.Count(f.subowners or {}) + 1
            local ln = list:AddLine(f.name, tostring(mc), f.public and "Public" or "Private")
            ln.faction = f
        end
    end

    list.OnRowSelected = function(_, _, ln)
        if ln and ln.faction then
            local upd = SFS.CL.GetFactionByID(ln.faction.id)
            selectedFac = upd or ln.faction
            showFaction(selectedFac)
        end
    end

    refreshList()

    hook.Add("SFS_FactionsUpdated", "SFS_BrowserTab_" .. tostring(pnl), function()
        if not IsValid(pnl) then hook.Remove("SFS_FactionsUpdated", "SFS_BrowserTab_" .. tostring(pnl)) return end
        refreshList()
        if selectedFac then
            local upd = SFS.CL.GetFactionByID(selectedFac.id)
            if upd then selectedFac = upd showFaction(upd)
            else selectedFac = nil detail:Clear() end
        end
    end)

    return pnl
end

local function buildMyFactionTab(sheet)
    local pnl = vgui.Create("DPanel", sheet)
    pnl.Paint = function() end

    local function rebuild()
        pnl:Clear()
        local myFac = SFS.CL.GetMyFaction()
        if not myFac then
            local lbl = vgui.Create("DLabel", pnl)
            lbl:SetPos(0, 0) lbl:SetSize(770, 476)
            lbl:SetText("You are not in a faction.")
            lbl:SetTextColor(Color(120, 120, 120)) lbl:SetContentAlignment(5)
            return
        end

        local myRank  = SFS.CL.GetMyRank()
        local steamid = LocalPlayer():SteamID()
        local isOwner = myRank == "owner"
        local isSub   = myRank == "subowner"
        local isAdmin = myRank == "admin"
        local isStaff = isOwner or isSub or isAdmin

        local function hasFacPerm(action)
            return myFac.permissions and myFac.permissions[myRank] and myFac.permissions[myRank][action] == true
        end
        local canApprove = isOwner or isSub or hasFacPerm("approve")
        local canKick     = isOwner or isSub or hasFacPerm("kick")

        local memberList = vgui.Create("DListView", pnl)
        memberList:SetPos(8, 8) memberList:SetSize(350, 440)
        memberList:SetMultiSelect(false)
        memberList:AddColumn("Player"):SetWidth(180)
        memberList:AddColumn("Rank"):SetWidth(100)
        memberList:AddColumn("Status"):SetWidth(70)

        local function addRow(sid, rankLabel)
            local onlinePly = nil
            for _, p in ipairs(player.GetAll()) do
                if p:SteamID() == sid then onlinePly = p break end
            end
            local nick   = IsValid(onlinePly) and onlinePly:Nick() or sid
            local status = IsValid(onlinePly) and "Online" or "Offline"
            local ln     = memberList:AddLine(nick, rankLabel, status)
            ln.sid = sid
            return ln
        end

        local function refreshMembers()
            memberList:Clear()
            local curFac = SFS.CL.GetFactionByID(myFac.id) or myFac
            addRow(curFac.owner, "Owner")
            if curFac.subowners then
                for sid, _ in pairs(curFac.subowners) do addRow(sid, "Sub-Owner") end
            end
            if curFac.members then
                for sid, data in pairs(curFac.members) do
                    addRow(sid, getMemberRankLabel(curFac, data.rank or "member"))
                end
            end
        end

        refreshMembers()

        if isOwner or isSub or canKick then
            memberList.OnRowSelected = function(_, _, ln)
                if not ln or not ln.sid then return end
                local sid = ln.sid
                if sid == myFac.owner then return end
                if sid == steamid then return end

                local curFac = SFS.CL.GetFactionByID(myFac.id) or myFac
                local targetIsSubOwner = curFac.subowners and curFac.subowners[sid]
                if targetIsSubOwner and not isOwner then return end

                local menu = DermaMenu()
                --// todo: make this better later
                if isOwner or isSub then
                    menu:AddOption("Set " .. getMemberRankLabel(curFac, "admin"), function()
                        if not netCooldown("promote") then return end
                        net.Start("SFS_PromoteMember") net.WriteString(curFac.id) net.WriteString(sid) net.WriteString("admin") net.SendToServer()
                    end)
                    menu:AddOption("Set " .. getMemberRankLabel(curFac, "mod"), function()
                        if not netCooldown("promote") then return end
                        net.Start("SFS_PromoteMember") net.WriteString(curFac.id) net.WriteString(sid) net.WriteString("mod") net.SendToServer()
                    end)
                    menu:AddOption("Set " .. getMemberRankLabel(curFac, "member"), function()
                        if not netCooldown("promote") then return end
                        net.Start("SFS_PromoteMember") net.WriteString(curFac.id) net.WriteString(sid) net.WriteString("member") net.SendToServer()
                    end)
                    if isOwner then
                        menu:AddOption(targetIsSubOwner and "Remove Sub-Owner" or "Make Sub-Owner", function()
                            if not netCooldown("subowner") then return end
                            net.Start(targetIsSubOwner and "SFS_RemoveSubOwner" or "SFS_AddSubOwner")
                            net.WriteString(curFac.id) net.WriteString(sid) net.SendToServer()
                        end)
                        menu:AddSpacer()
                        menu:AddOption("Transfer Ownership", function()
                            Derma_Query("Transfer ownership of " .. curFac.name .. " to this player?\nThis cannot be undone.", "Confirm Transfer",
                                "Yes, transfer", function()
                                    if not netCooldown("transfer") then return end
                                    net.Start("SFS_TransferOwnership") net.WriteString(curFac.id) net.WriteString(sid) net.SendToServer()
                                end, "Cancel", function() end)
                        end)
                    end
                    menu:AddSpacer()
                end
                menu:AddOption("Kick from Faction", function()
                    if not netCooldown("kick") then return end
                    net.Start("SFS_KickMember") net.WriteString(curFac.id) net.WriteString(sid) net.SendToServer()
                end)
                menu:Open()
            end
        end

        local right = vgui.Create("DPanel", pnl)
        right:SetPos(368, 8) right:SetSize(400, 460)
        right.Paint = function() end

        local function getUpdatedFac()
            return SFS.CL.GetFactionByID(myFac.id) or myFac
        end

        local infoPnl = vgui.Create("DPanel", right)
        infoPnl:SetPos(0, 0) infoPnl:SetSize(400, 64)
        infoPnl.Paint = function(_, sw, sh)
            local curFac = getUpdatedFac()
            surface.SetDrawColor(240, 240, 240) surface.DrawRect(0, 0, sw, sh)
            surface.SetDrawColor(180, 180, 180) surface.DrawOutlinedRect(0, 0, sw, sh)
            draw.SimpleText(curFac.name, "DermaLarge", 68, 8, color_black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(curFac.desc or "", "DermaDefault", 68, 34, Color(100,100,100), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(curFac.public and "Public" or "Private", "DermaDefault", 68, 50,
                curFac.public and Color(0,150,0) or Color(180,120,0), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        local myFacIconPnl = createIconPanel(infoPnl, 6, 6, 52, 52, myFac.icon or SFS.Config.DefaultIconMaterial)

        hook.Add("SFS_FactionsUpdated", "SFS_MyFacIcon_" .. tostring(infoPnl), function()
            if not IsValid(infoPnl) then
                hook.Remove("SFS_FactionsUpdated", "SFS_MyFacIcon_" .. tostring(infoPnl))
                return
            end
            local curFac = getUpdatedFac()
            if IsValid(myFacIconPnl) and myFacIconPnl.SetIcon then
                myFacIconPnl:SetIcon(curFac.icon or SFS.Config.DefaultIconMaterial)
            end
        end)

        local rankLbl = vgui.Create("DLabel", right)
        rankLbl:SetPos(0, 72) rankLbl:SetSize(400, 20)
        rankLbl:SetText("Your rank: " .. getMemberRankLabel(myFac, myRank or "member"))

        local yBtn = 100

        if canApprove and not myFac.public then
            local function hasRequests()
                local curFac = getUpdatedFac()
                return curFac.requests and next(curFac.requests)
            end

            if hasRequests() then
                local reqLbl = vgui.Create("DLabel", right)
                reqLbl:SetPos(0, yBtn) reqLbl:SetSize(400, 20) reqLbl:SetText("Pending join requests:")
                yBtn = yBtn + 22

                local reqList = vgui.Create("DListView", right)
                reqList:SetPos(0, yBtn) reqList:SetSize(400, 100)
                reqList:AddColumn("Player"):SetWidth(300)

                local function refreshRequests()
                    reqList:Clear()
                    local curFac = getUpdatedFac()
                    if curFac.requests then
                        for sid, req in pairs(curFac.requests) do
                            local ln = reqList:AddLine(req.nick or sid)
                            ln.sid = sid
                        end
                    end
                end
                refreshRequests()

                reqList.OnRowSelected = function(_, _, ln)
                    if not ln then return end
                    local curFac = getUpdatedFac()
                    local menu = DermaMenu()
                    menu:AddOption("Approve", function()
                        if not netCooldown("approve_" .. ln.sid) then return end
                        net.Start("SFS_ApproveMember") net.WriteString(curFac.id) net.WriteString(ln.sid) net.SendToServer()
                    end)
                    menu:AddOption("Deny", function()
                        if not netCooldown("deny_" .. ln.sid) then return end
                        net.Start("SFS_DenyMember") net.WriteString(curFac.id) net.WriteString(ln.sid) net.SendToServer()
                    end)
                    menu:Open()
                end

                hook.Add("SFS_FactionsUpdated", "SFS_MyFacRequests_" .. tostring(reqList), function()
                    if not IsValid(reqList) then
                        hook.Remove("SFS_FactionsUpdated", "SFS_MyFacRequests_" .. tostring(reqList))
                        return
                    end
                    refreshRequests()
                end)

                yBtn = yBtn + 110
            end
        end

        if isOwner or isSub then
            local ffBtn = vgui.Create("DButton", right)
            ffBtn:SetPos(0, yBtn) ffBtn:SetSize(195, 26)
            local function updateFFBtn()
                local fac = getUpdatedFac()
                local s = fac.friendlyFire == true
                ffBtn:SetText("Friendly Fire: " .. (s and "ON" or "OFF"))
                ffBtn:SetTextColor(s and Color(200,60,60) or Color(40,160,80))
            end
            updateFFBtn()
            ffBtn.DoClick = function()
                if not netCooldown("ff_toggle") then return end
                local fac = getUpdatedFac()
                local newVal = not (fac.friendlyFire == true)
                net.Start("SFS_ToggleFriendlyFire")
                net.WriteString(fac.id)
                net.WriteBool(newVal)
                net.SendToServer()
            end

            hook.Add("SFS_FactionsUpdated", "SFS_FFBtn_" .. tostring(ffBtn), function()
                if not IsValid(ffBtn) then
                    hook.Remove("SFS_FactionsUpdated", "SFS_FFBtn_" .. tostring(ffBtn))
                    return
                end
                updateFFBtn()
            end)

            local haloBtn = vgui.Create("DButton", right)
            haloBtn:SetPos(201, yBtn) haloBtn:SetSize(199, 26)
            local function updateHaloBtn()
                local fac = getUpdatedFac()
                local s = fac.haloEnabled ~= false
                haloBtn:SetText("Halo: " .. (s and "ON" or "OFF"))
                haloBtn:SetTextColor(s and Color(40,160,80) or Color(150,150,150))
            end
            updateHaloBtn()
            haloBtn.DoClick = function()
                if not netCooldown("halo_toggle") then return end
                local fac = getUpdatedFac()
                net.Start("SFS_ToggleHalo")
                net.WriteString(fac.id)
                net.WriteBool(not (fac.haloEnabled ~= false))
                net.SendToServer()
            end

            hook.Add("SFS_FactionsUpdated", "SFS_HaloBtn_" .. tostring(haloBtn), function()
                if not IsValid(haloBtn) then
                    hook.Remove("SFS_FactionsUpdated", "SFS_HaloBtn_" .. tostring(haloBtn))
                    return
                end
                updateHaloBtn()
            end)

            yBtn = yBtn + 32
        end

        local leaveBtn = vgui.Create("DButton", right)
        leaveBtn:SetPos(0, yBtn) leaveBtn:SetSize(400, 26)
        leaveBtn:SetText(isOwner and "Disband Faction" or "Leave Faction")
        leaveBtn.DoClick = function()
            if not netCooldown("leave") then return end
            if isOwner then
                Derma_Query("Disband " .. myFac.name .. "? This cannot be undone.", "Confirm",
                    "Yes, disband", function()
                        net.Start("SFS_DeleteFaction") net.WriteString(myFac.id) net.SendToServer()
                        if IsValid(activePanel) then activePanel:Remove() end
                    end, "Cancel", function() end)
            else
                Derma_Query("Leave " .. myFac.name .. "?", "Confirm",
                    "Yes", function()
                        net.Start("SFS_LeaveFacton") net.SendToServer()
                        if IsValid(activePanel) then activePanel:Remove() end
                    end, "Cancel", function() end)
            end
        end
    end

    rebuild()

    hook.Add("SFS_FactionsUpdated", "SFS_MyFactionTab_" .. tostring(pnl), function()
        if not IsValid(pnl) then hook.Remove("SFS_FactionsUpdated", "SFS_MyFactionTab_" .. tostring(pnl)) return end
        rebuild()
    end)

    return pnl
end

local function buildManageTab(sheet)
    local pnl = vgui.Create("DPanel", sheet)
    pnl.Paint = function() end

    local myFac  = SFS.CL.GetMyFaction()
    local myRank = SFS.CL.GetMyRank()

    if not myFac or (myRank ~= "owner" and myRank ~= "subowner") then
        local lbl = vgui.Create("DLabel", pnl)
        lbl:SetPos(0, 0) lbl:SetSize(770, 476)
        lbl:SetText("You do not have permission to manage this faction.")
        lbl:SetTextColor(Color(120, 120, 120)) lbl:SetContentAlignment(5)
        return pnl
    end

    local isOwner = myRank == "owner"

    local function getUpdatedFac()
        return SFS.CL.GetFactionByID(myFac.id) or myFac
    end

    local mScroll = vgui.Create("DScrollPanel", pnl)
    mScroll:SetPos(8, 8) mScroll:SetSize(750, 460)

    local form = vgui.Create("DForm", mScroll)
    form:SetPos(0, 0) form:SetSize(730, 750)
    form:SetName("Manage Faction — " .. myFac.name)

    local function makeFormEntry(parent, labelText, defaultVal)
        local wrap = vgui.Create("DPanel", parent)
        wrap:SetTall(46)
        wrap.Paint = function() end
        local lbl = vgui.Create("DLabel", wrap)
        lbl:SetText(labelText)
        lbl:SetPos(0, 2)
        lbl:SetSize(200, 18)
        local ent = vgui.Create("DTextEntry", wrap)
        ent:SetPos(0, 20)
        ent:SetSize(360, 22)
        ent:SetValue(defaultVal or "")
        return wrap, ent
    end

    local nameWrap, nameEntry = makeFormEntry(form, "Name", myFac.name)
    form:AddItem(nameWrap)
    local descWrap, descEntry = makeFormEntry(form, "Description", myFac.desc or "")
    form:AddItem(descWrap)

    local iconRow = buildIconRow(form, myFac.icon or "")
    form:AddItem(iconRow)

    local pubWrap = vgui.Create("DPanel", form)
    pubWrap:SetTall(26)
    pubWrap.Paint = function() end
    local pubCheck = vgui.Create("DCheckBox", pubWrap)
    pubCheck:SetPos(0, 4)
    pubCheck:SetChecked(myFac.public == true)
    local pubLbl = vgui.Create("DLabel", pubWrap)
    pubLbl:SetText("Public faction")
    pubLbl:SetPos(22, 4)
    pubLbl:SetSize(200, 18)
    form:AddItem(pubWrap)

    form:Button("Save Changes", "").DoClick = function()
        if not netCooldown("updatefac") then return end
        local name = nameEntry:GetValue():Trim()
        local desc = descEntry:GetValue():Trim()
        local icon = iconRow:GetValue()
        local pub  = pubCheck:GetChecked()
        if name == "" then return end
        if name:match("[%z%c]") or #name:gsub("%s","") == 0 then
            Derma_Message("Name cannot be empty or contain control characters.", "Invalid Name", "OK")
            return
        end
        net.Start("SFS_UpdateFaction")
        net.WriteString(myFac.id)
        net.WriteString(util.TableToJSON({ name = name, desc = desc, icon = icon, public = pub }))
        net.SendToServer()
    end

    if isOwner then
        form:Help(""):SetText("")

        local rankHeader = vgui.Create("DLabel", form)
        rankHeader:SetText("Custom Rank Names (max 20 chars each)")
        rankHeader:SetFont("DermaDefaultBold")
        form:AddItem(rankHeader)

        local adminRankEntry = form:TextEntry("Admin rank name",  "")
        adminRankEntry:SetPlaceholderText(myFac.ranks and myFac.ranks.admin  and myFac.ranks.admin.label  or "Admin")
        local modRankEntry   = form:TextEntry("Mod rank name",    "")
        modRankEntry:SetPlaceholderText(myFac.ranks and myFac.ranks.mod    and myFac.ranks.mod.label    or "Moderator")
        local memRankEntry   = form:TextEntry("Member rank name", "")
        memRankEntry:SetPlaceholderText(myFac.ranks and myFac.ranks.member and myFac.ranks.member.label or "Member")

        form:Button("Save Rank Names", "").DoClick = function()
            if not netCooldown("ranklabels") then return end
            local labels = {}
            local adminVal  = adminRankEntry:GetValue():Trim()
            local modVal    = modRankEntry:GetValue():Trim()
            local memberVal = memRankEntry:GetValue():Trim()
            if #adminVal  > 0 then labels.admin  = adminVal  end
            if #modVal    > 0 then labels.mod    = modVal    end
            if #memberVal > 0 then labels.member = memberVal end
            net.Start("SFS_UpdateRankLabels")
            net.WriteString(myFac.id)
            net.WriteString(util.TableToJSON(labels))
            net.SendToServer()
        end

        form:Help(""):SetText("")

        local permHeader = vgui.Create("DLabel", form)
        permHeader:SetText("Rank Permissions")
        permHeader:SetFont("DermaDefaultBold")
        form:AddItem(permHeader)

        local permDescLbl = vgui.Create("DLabel", form)
        permDescLbl:SetText("Control what each rank can do in your faction.")
        permDescLbl:SetTextColor(Color(100, 100, 100))
        form:AddItem(permDescLbl)

        local permGrid = vgui.Create("DPanel", form)
        permGrid:SetSize(730, 60)
        permGrid.Paint = function() end

        local ranks = { { key = "admin", label = "Admin" }, { key = "mod", label = "Mod" } }
        local permChecks = {}

        local colW = 365
        for i, rankDef in ipairs(ranks) do
            local xOff = (i - 1) * colW
            local rankLabelEl = vgui.Create("DLabel", permGrid)
            rankLabelEl:SetPos(xOff, 0) rankLabelEl:SetSize(colW, 18)
            rankLabelEl:SetText(getMemberRankLabel(myFac, rankDef.key) .. ":")
            rankLabelEl:SetFont("DermaDefaultBold")

            local permDefs = { { key = "approve", label = "Can approve members" }, { key = "kick", label = "Can kick members" } }
            permChecks[rankDef.key] = {}
            for j, permDef in ipairs(permDefs) do
                local chk = vgui.Create("DCheckBoxLabel", permGrid)
                chk:SetPos(xOff + 8, 18 + (j - 1) * 20)
                chk:SetSize(colW - 8, 18)
                chk:SetText(permDef.label)
                local curVal = myFac.permissions and myFac.permissions[rankDef.key] and myFac.permissions[rankDef.key][permDef.key]
                chk:SetChecked(curVal == true)
                permChecks[rankDef.key][permDef.key] = chk
            end
        end

        form:AddItem(permGrid)

        form:Button("Save Permissions", "").DoClick = function()
            if not netCooldown("perms") then return end
            local perms = {}
            for rankKey, rankChks in pairs(permChecks) do
                perms[rankKey] = {}
                for permKey, chk in pairs(rankChks) do
                    perms[rankKey][permKey] = chk:GetChecked()
                end
            end
            net.Start("SFS_UpdatePermissions")
            net.WriteString(myFac.id)
            net.WriteString(util.TableToJSON(perms))
            net.SendToServer()
        end

        form:Help(""):SetText("")

        local allyHeader = vgui.Create("DLabel", form)
        allyHeader:SetText("Allies")
        allyHeader:SetFont("DermaDefaultBold")
        form:AddItem(allyHeader)

        local allyList = vgui.Create("DListView", form)
        allyList:SetSize(730, 80)
        allyList:AddColumn("Allied Faction"):SetWidth(500)
        form:AddItem(allyList)

        local function refreshAllyList()
            allyList:Clear()
            local curFac = getUpdatedFac()
            for allyID, _ in pairs(curFac.allies or {}) do
                local af = SFS.CL.GetFactionByID(allyID)
                if af then
                    local ln = allyList:AddLine(af.name)
                    ln.allyID = allyID
                end
            end
        end
        refreshAllyList()

        allyList.OnRowSelected = function(_, _, ln)
            if not ln then return end
            local menu = DermaMenu()
            menu:AddOption("Remove Alliance", function()
                if not netCooldown("removeally_" .. tostring(ln.allyID)) then return end
                net.Start("SFS_RemoveAlly") net.WriteString(myFac.id) net.WriteString(ln.allyID) net.SendToServer()
            end)
            menu:Open()
        end

        hook.Add("SFS_FactionsUpdated", "SFS_AllyList_" .. tostring(allyList), function()
            if not IsValid(allyList) then
                hook.Remove("SFS_FactionsUpdated", "SFS_AllyList_" .. tostring(allyList))
                return
            end
            refreshAllyList()
        end)

        local pendingHeader = vgui.Create("DLabel", form)
        pendingHeader:SetText("Pending Alliance Requests (received)")
        pendingHeader:SetFont("DermaDefaultBold")
        form:AddItem(pendingHeader)

        local pendingList = vgui.Create("DListView", form)
        pendingList:SetSize(730, 80)
        pendingList:AddColumn("From Faction"):SetWidth(200)
        pendingList:AddColumn("Message"):SetWidth(480)
        form:AddItem(pendingList)

        local function refreshPendingList()
            pendingList:Clear()
            local curFac = getUpdatedFac()
            for reqFacID, reqData in pairs(curFac.allyRequests or {}) do
                local ln = pendingList:AddLine(reqData.fromName or reqFacID, reqData.message or "")
                ln.reqFacID = reqFacID
            end
        end
        refreshPendingList()

        pendingList.OnRowSelected = function(_, _, ln)
            if not ln then return end
            local menu = DermaMenu()
            menu:AddOption("Accept Alliance", function()
                if not netCooldown("acceptally_" .. tostring(ln.reqFacID)) then return end
                net.Start("SFS_AcceptAllyRequest") net.WriteString(myFac.id) net.WriteString(ln.reqFacID) net.SendToServer()
            end)
            menu:AddOption("Decline", function()
                if not netCooldown("declineally_" .. tostring(ln.reqFacID)) then return end
                net.Start("SFS_DeclineAllyRequest") net.WriteString(myFac.id) net.WriteString(ln.reqFacID) net.SendToServer()
            end)
            menu:Open()
        end

        hook.Add("SFS_FactionsUpdated", "SFS_PendingAllyList_" .. tostring(pendingList), function()
            if not IsValid(pendingList) then
                hook.Remove("SFS_FactionsUpdated", "SFS_PendingAllyList_" .. tostring(pendingList))
                return
            end
            refreshPendingList()
        end)

        local sendReqHeader = vgui.Create("DLabel", form)
        sendReqHeader:SetText("Send Alliance Request")
        sendReqHeader:SetFont("DermaDefaultBold")
        form:AddItem(sendReqHeader)

        local addAllyCombo = vgui.Create("DComboBox", form)
        addAllyCombo:SetSize(500, 24)
        addAllyCombo:SetValue("Select faction...")
        for id, f in pairs(SFS.CL.Factions) do
            if id ~= myFac.id and not (myFac.allies and myFac.allies[id]) then
                addAllyCombo:AddChoice(f.name, id)
            end
        end
        form:AddItem(addAllyCombo)

        local allyMsgEntry = form:TextEntry("Message (optional, max 100 chars)", "")

        local sendAllyBtn = vgui.Create("DButton", form)
        sendAllyBtn:SetSize(200, 24)
        sendAllyBtn:SetText("Send Alliance Request")
        sendAllyBtn.DoClick = function()
            if not netCooldown("sendally") then return end
            local _, fid = addAllyCombo:GetSelected()
            if not fid then return end
            local msg = allyMsgEntry:GetValue():Trim():sub(1, 100)
            net.Start("SFS_SendAllyRequest")
            net.WriteString(myFac.id)
            net.WriteString(fid)
            net.WriteString(msg)
            net.SendToServer()
        end
        form:AddItem(sendAllyBtn)

        form:Help(""):SetText("")

        local warHeader = vgui.Create("DLabel", form)
        warHeader:SetText("War")
        warHeader:SetFont("DermaDefaultBold")
        form:AddItem(warHeader)

        local warContainer = vgui.Create("DPanel", form)
        warContainer:SetSize(730, 100)
        warContainer.Paint = function() end
        form:AddItem(warContainer)

        local function getMyWarState()
            if SFS.CL.GetMyWar then
                return SFS.CL.GetMyWar()
            end
            return nil
        end

        local function rebuildWarSection()
            if not IsValid(warContainer) then return end

            warContainer:Clear()

            if getMyWarState() then
                local inWarLbl = vgui.Create("DLabel", warContainer)
                inWarLbl:SetPos(0, 0)
                inWarLbl:SetSize(700, 20)
                inWarLbl:SetText("Your faction is current in war, you can go to the wars tab to see it.")
                inWarLbl:SetTextColor(Color(180, 60, 60))
                return
            end

            local warDescLbl = vgui.Create("DLabel", warContainer)
            warDescLbl:SetPos(0, 0)
            warDescLbl:SetSize(700, 20)
            warDescLbl:SetText("Select an enemy faction to declare war against, your allies will join automatically.")
            warDescLbl:SetTextColor(Color(100, 100, 100))

            local warTargetCombo = vgui.Create("DComboBox", warContainer)
            warTargetCombo:SetPos(0, 25)
            warTargetCombo:SetSize(500, 24)
            warTargetCombo:SetValue("Select an enemy faction...")

            local function refreshWarCombo()
                local curFac = getUpdatedFac()

                warTargetCombo:Clear()
                warTargetCombo:SetValue("Select an enemy faction...")

                for id, f in pairs(SFS.CL.Factions) do
                    if id == curFac.id then continue end
                    if curFac.allies and curFac.allies[id] then continue end
                    if SFS.CL.GetFactionWarStatus and SFS.CL.GetFactionWarStatus(id) then continue end

                    warTargetCombo:AddChoice(f.name, id)
                end
            end

            refreshWarCombo()

            local declareWarBtn = vgui.Create("DButton", warContainer)
            declareWarBtn:SetPos(0, 55)
            declareWarBtn:SetSize(200, 24)
            declareWarBtn:SetText("Declare war")
            declareWarBtn:SetImage("icon16/bomb.png")

            declareWarBtn.DoClick = function()
                if not netCooldown("declarewar") then return end

                local _, targetFacID = warTargetCombo:GetSelected()
                if not targetFacID then return end

                local targetFac = SFS.CL.GetFactionByID(targetFacID)
                if not targetFac then return end

                Derma_Query(
                    "Declare war against " .. targetFac.name .. "?\nYour allies will join automatically.",
                    "Confirm war",
                    "Yes, declare war!",
                    function()
                        net.Start("SFS_DeclareWar")
                        net.WriteString(targetFacID)
                        net.SendToServer()
                    end,
                    "Cancel",
                    function() end
                )
            end
        end

        rebuildWarSection()

        hook.Add("SFS_WarsUpdated", "SFS_WarContainer_" .. tostring(warContainer), function()
            if not IsValid(warContainer) then
                hook.Remove("SFS_WarsUpdated", "SFS_WarContainer_" .. tostring(warContainer))
                return
            end

            rebuildWarSection()
        end)

        hook.Add("SFS_FactionsUpdated", "SFS_WarContainerFac_" .. tostring(warContainer), function()
            if not IsValid(warContainer) then
                hook.Remove("SFS_FactionsUpdated", "SFS_WarContainerFac_" .. tostring(warContainer))
                return
            end

            rebuildWarSection()
        end)
        if myRank == "owner" or myRank == "subowner" then
            form:Help(""):SetText("")

            local announceHdr = vgui.Create("DLabel", form)
            announceHdr:SetText("Global Faction Announcement (1h cooldown)")
            announceHdr:SetFont("DermaDefaultBold")
            form:AddItem(announceHdr)

            local announceDesc = vgui.Create("DLabel", form)
            announceDesc:SetText("Broadcast a message to all players on the server as your faction.")
            announceDesc:SetTextColor(Color(100, 100, 100))
            form:AddItem(announceDesc)

            local announceEntry = vgui.Create("DTextEntry", form)
            announceEntry:SetSize(740, 24)
            announceEntry:SetPlaceholderText("Type your announcement (max 250 chars)...")
            form:AddItem(announceEntry)

            local announceBtn = vgui.Create("DButton", form)
            announceBtn:SetSize(200, 24)
            announceBtn:SetText("Send Announcement")
            announceBtn:SetImage("icon16/flag_yellow.png")
            announceBtn.DoClick = function()
                if not netCooldown("announce") then return end
                local msg = announceEntry:GetValue():Trim()
                if msg == "" then return end
                if #msg > 250 then
                    Derma_Message("Message too long (max 250 characters).", "Error", "OK")
                    return
                end
                Derma_Query("Send this announcement to ALL players?\n" .. msg, "Confirm Announcement",
                    "Send", function()
                        net.Start("SFS_FactionAnnounce")
                        net.WriteString(msg)
                        net.SendToServer()
                        announceEntry:SetText("")
                    end, "Cancel", function() end)
            end
            form:AddItem(announceBtn)
        end
    end

    return pnl
end

local function buildCreateTab(sheet)
    local pnl = vgui.Create("DPanel", sheet)
    pnl.Paint = function() end

    local myFac = SFS.CL.GetMyFaction()
    if myFac then
        local lbl = vgui.Create("DLabel", pnl)
        lbl:SetPos(0, 0) lbl:SetSize(770, 476)
        lbl:SetText("You are already in a faction. Leave or disband it first.")
        lbl:SetTextColor(Color(120, 120, 120)) lbl:SetContentAlignment(5)
        return pnl
    end

    local form = vgui.Create("DForm", pnl)
    form:SetPos(8, 8) form:SetSize(750, 460)
    form:SetName("Create New Faction")

    local nameEntry = form:TextEntry("Name (letters/numbers/_ only, max 30)")
    local descEntry = form:TextEntry("Description (max 60 chars)")
    local iconRow   = buildIconRow(form, "")
    form:AddItem(iconRow)
    local pubCheck  = form:CheckBox("Public (anyone can join instantly)")

    local errLbl = vgui.Create("DLabel", form)
    errLbl:SetText("") errLbl:SetTextColor(Color(200, 0, 0))
    form:AddItem(errLbl)

    form:Button("Create Faction", "").DoClick = function()
        if not netCooldown("createfac") then return end
        local name = nameEntry:GetValue():Trim()
        local desc = descEntry:GetValue():Trim()
        local icon = iconRow:GetValue()
        local pub  = pubCheck:GetChecked()

        if name == "" then errLbl:SetText("Name is required.") return end
        if name:match("[%z%c]") or #name:gsub("%s","") == 0 then errLbl:SetText("Name cannot be empty or contain control characters.") return end
        if #name > SFS.Config.MaxFactionNameLength then errLbl:SetText("Name too long (max " .. SFS.Config.MaxFactionNameLength .. ").") return end
        if #desc > SFS.Config.MaxFactionDescLength then errLbl:SetText("Description too long (max " .. SFS.Config.MaxFactionDescLength .. ").") return end

        net.Start("SFS_CreateFaction")
        net.WriteString(name) net.WriteString(desc) net.WriteString(icon) net.WriteBool(pub)
        net.SendToServer()
    end

    return pnl
end


local SFS_ICON_CACHE_ENABLED = CreateClientConVar("sfs_icon_cache", "1", true, false, "Cache faction icons to disk")
local SFS_NOTIF_ENABLED      = CreateClientConVar("sfs_notifications", "1", true, false, "Show faction notifications")
local SFS_NOTIF_SOUND        = CreateClientConVar("sfs_notification_sound", "1", true, false, "Play notification sounds")
local SFS_HALO_SELF          = CreateClientConVar("sfs_halo_show_self", "0", true, false, "Show halo on yourself")
local SFS_PING_SOUND         = CreateClientConVar("sfs_ping_sound", "1", true, false, "Play sound on receiving ping")

local function buildSettingsTab(sheet)
    local pnl = vgui.Create("DPanel")
    pnl.Paint = function() end

    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    scroll:DockMargin(8, 8, 8, 8)

    local form = vgui.Create("DForm", scroll)
    form:Dock(TOP)
    form:SetName("User Settings")
    form.Paint = function() end

    local function sectionLabel(text)
        local lbl = vgui.Create("DLabel", form)
        lbl:SetText(text)
        lbl:SetFont("DermaDefaultBold")
        lbl:SetTextColor(Color(60, 80, 140))
        lbl:SetTall(28)
        lbl:DockMargin(0, 8, 0, 0)
        form:AddItem(lbl)
    end

    local function addToggle(label, convar, desc)
        local wrap = vgui.Create("DPanel", form)
        wrap:SetTall(48)
        wrap.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255))
            surface.SetDrawColor(220, 220, 228)
            surface.DrawOutlinedRect(0, 0, w, h)
        end

        local cb = vgui.Create("DCheckBox", wrap)
        cb:SetPos(8, (48 - 16) * 0.5)
        cb:SetConVar(convar)

        local lbl = vgui.Create("DLabel", wrap)
        lbl:SetPos(30, 8)
        lbl:SetSize(500, 18)
        lbl:SetText(label)
        lbl:SetFont("DermaDefaultBold")

        local dlbl = vgui.Create("DLabel", wrap)
        dlbl:SetPos(30, 26)
        dlbl:SetSize(500, 16)
        dlbl:SetText(desc)
        dlbl:SetFont("DermaDefault")
        dlbl:SetTextColor(Color(120, 120, 130))

        form:AddItem(wrap)
        return cb
    end

    sectionLabel("  Notifications")
    addToggle("Show Notifications",  "sfs_notifications",      "Display toast notifications for faction events.")
    addToggle("Notification Sounds", "sfs_notification_sound", "Play a sound when a notification appears.")

    sectionLabel("  Icons & Cache")
    addToggle("Cache Icons to Disk", "sfs_icon_cache", "Save downloaded faction icons to data/sfs_icons/. Disabling means re-downloading every session.")

    local cacheInfoWrap = vgui.Create("DPanel", form)
    cacheInfoWrap:SetTall(58)
    cacheInfoWrap.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255))
        surface.SetDrawColor(220, 220, 228)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    local function getCacheInfo()
        if not file.IsDir("sfs_icons", "DATA") then return 0, 0 end
        local files = file.Find("sfs_icons/*.png", "DATA")
        local count = #(files or {})
        local bytes = 0
        for _, f in ipairs(files or {}) do
            local data = file.Read("sfs_icons/" .. f, "DATA")
            if data then bytes = bytes + #data end
        end
        return count, bytes
    end

    local cacheCount, cacheBytes = getCacheInfo()
    local cacheLbl = vgui.Create("DLabel", cacheInfoWrap)
    cacheLbl:SetPos(8, 6)
    cacheLbl:SetSize(400, 18)
    cacheLbl:SetFont("DermaDefaultBold")
    cacheLbl:SetText(string.format("Cached icons: %d  (%.1f KB)", cacheCount, cacheBytes / 1024))

    local clearBtn = vgui.Create("DButton", cacheInfoWrap)
    clearBtn:SetText("Clear Icon Cache")
    clearBtn:SetPos(8, 28)
    clearBtn:SetSize(140, 24)
    clearBtn.DoClick = function()
        Derma_Query("Delete all locally cached faction icons?\nThey will be re-downloaded when needed.", "Clear Cache",
            "Clear", function()
                if file.IsDir("sfs_icons", "DATA") then
                    local files = file.Find("sfs_icons/*.png", "DATA")
                    for _, f in ipairs(files or {}) do file.Delete("sfs_icons/" .. f) end
                end
                iconMatCache = {}
                local nc, nb = getCacheInfo()
                cacheLbl:SetText(string.format("Cached icons: %d  (%.1f KB)", nc, nb / 1024))
            end,
            "Cancel", function() end
        )
    end

    local refreshCacheBtn = vgui.Create("DButton", cacheInfoWrap)
    refreshCacheBtn:SetText("Refresh")
    refreshCacheBtn:SetPos(156, 28)
    refreshCacheBtn:SetSize(70, 24)
    refreshCacheBtn.DoClick = function()
        local nc, nb = getCacheInfo()
        cacheLbl:SetText(string.format("Cached icons: %d  (%.1f KB)", nc, nb / 1024))
    end

    form:AddItem(cacheInfoWrap)

    sectionLabel("  Ping")
    addToggle("Ping Sound", "sfs_ping_sound", "Play a sound when you receive a faction ping.")

    sectionLabel("  Halo")
    addToggle("Show Halo on Yourself", "sfs_halo_show_self", "Draw the faction halo outline on your own player model.")

    sectionLabel("  Language")

    local langWrap = vgui.Create("DPanel", form)
    langWrap:SetTall(78)
    langWrap.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255))
        surface.SetDrawColor(220, 220, 228)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    local langDesc = vgui.Create("DLabel", langWrap)
    langDesc:SetPos(8, 6)
    langDesc:SetSize(600, 30)
    langDesc:SetWrap(true)
    langDesc:SetText("Overrides the server's default language just for messages sent directly to you (errors, your own join request status). Broadcast messages to everyone always use the server's language. Persists until you change it back.")
    langDesc:SetTextColor(Color(120, 120, 130))
    langDesc:SizeToContentsY()

    local langOptions = {
        { id = "english", label = "English" },
        { id = "ptbr",    label = "Português" },
        { id = "spanish", label = "Español" },
    }

    local btnX, btnY = 8, 42
    for _, opt in ipairs(langOptions) do
        local btn = vgui.Create("DButton", langWrap)
        btn:SetPos(btnX, btnY)
        btn:SetSize(90, 24)
        btn:SetText(opt.label)
        btn.Paint = function(self, w, h)
            local active = SFS.CL.LangPref:GetString() == opt.id
            draw.RoundedBox(4, 0, 0, w, h, active and Color(80, 140, 230) or Color(235, 235, 240))
            surface.SetDrawColor(200, 200, 210)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        btn.DoClick = function()
            RunConsoleCommand("sfs_lang_pref", opt.id)
        end
        btnX = btnX + 96
    end

    local resetLangBtn = vgui.Create("DButton", langWrap)
    resetLangBtn:SetPos(btnX, btnY)
    resetLangBtn:SetSize(150, 24)
    resetLangBtn:SetText("Use Server Default")
    resetLangBtn.DoClick = function()
        RunConsoleCommand("sfs_lang_pref", "")
    end

    form:AddItem(langWrap)

    return pnl
end

local function buildStaffTab(sheet)
    local pnl = vgui.Create("DPanel", sheet)
    pnl.Paint = function() end

    if not SFS.IsSuperAdminCL() then
        local lbl = vgui.Create("DLabel", pnl)
        lbl:SetPos(0, 0) lbl:SetSize(770, 476)
        lbl:SetText("Access denied.")
        lbl:SetTextColor(Color(200, 0, 0)) lbl:SetContentAlignment(5)
        return pnl
    end

    local innerSheet = vgui.Create("DPropertySheet", pnl)
    innerSheet:SetPos(0, 0) innerSheet:SetSize(780, 480)

    local factionListPnl = vgui.Create("DPanel", innerSheet)
    factionListPnl.Paint = function() end

    local fList = vgui.Create("DListView", factionListPnl)
    fList:SetPos(4, 4) fList:SetSize(760, 380)
    fList:SetMultiSelect(false)
    fList:AddColumn("Faction"):SetWidth(160)
    fList:AddColumn("Owner SteamID"):SetWidth(200)
    fList:AddColumn("Members"):SetWidth(70)
    fList:AddColumn("Type"):SetWidth(70)
    fList:AddColumn("FF"):SetWidth(50)
    fList:AddColumn("Halo"):SetWidth(50)

    local function refreshFList()
        fList:Clear()
        for id, f in pairs(SFS.CL.Factions) do
            local mc = table.Count(f.members or {}) + table.Count(f.subowners or {}) + 1
            local ln = fList:AddLine(f.name, f.owner, tostring(mc),
                f.public and "Public" or "Private",
                f.friendlyFire and "ON" or "OFF",
                f.haloEnabled ~= false and "ON" or "OFF")
            ln.factionID   = id
            ln.factionName = f.name
        end
    end

    refreshFList()

    fList.OnRowSelected = function(_, _, ln)
        if not ln then return end
        local menu = DermaMenu()
        menu:AddOption("Delete Faction", function()
            Derma_StringRequest("Delete Faction", "Reason for deleting " .. ln.factionName .. ":", "", function(reason)
                if reason and reason ~= "" then
                    if not netCooldown("admindelete") then return end
                    net.Start("SFS_AdminDeleteFaction")
                    net.WriteString(ln.factionID) net.WriteString(reason) net.SendToServer()
                end
            end)
        end)
        menu:Open()
    end

    innerSheet:AddSheet("Factions", factionListPnl, "icon16/group.png")

    local stringsPnl = vgui.Create("DPanel", innerSheet)
    stringsPnl.Paint = function() end

    local sScroll = vgui.Create("DScrollPanel", stringsPnl)
    sScroll:SetPos(4, 4) sScroll:SetSize(760, 420)

    local sForm = vgui.Create("DForm", sScroll)
    sForm:SetPos(0, 0) sForm:SetSize(740, 550)
    sForm:SetName("Configurable Strings — use {playerName}, {factionName}, {staffName}, {reason}, {addonprefix}, {targetName}")

    local stringKeys = {
        "AddonPrefix",
        "PlayerJoinedFaction", "PlayerLeftFaction", "PlayerKickedFaction",
        "FactionCreated", "FactionDeleted", "FactionDisbanded",
        "RequestSent", "RequestApproved", "RequestDenied",
        "NotifyJoinRequest", "NotifyApproved", "NotifyKicked", "NotifyPromoted", "NotifySubOwner", "NotifyBackToMember", "NotifyAllianceRequest",
        "AllianceRequested", "AllianceFormed", "AllianceBroken",
        "WarDeclared", "WarEndTruce", "WarEndTime", "WarEndWipe", "WarEndGeneric", "WarDuration",
        "ErrAlreadyInFaction", "ErrInvalidName", "ErrNameTooLong", "ErrDescTooLong",
        "ErrNameTaken", "ErrNotFound", "ErrNotPublic", "ErrIsPublic",
        "ErrAlreadyRequested", "ErrNotMember", "ErrNoPermission",
        "ErrCannotKick", "ErrCannotKickSubowner", "ErrNotInFaction",
        "ErrOwnerMustDisband", "ErrInvalidRank", "ErrNotOwner",
        "ErrSamePlayer", "ErrSameFaction", "ErrAlreadyAllies",
        "ErrMaxAllies", "ErrTargetMaxAllies", "ErrRequestAlreadySent",
        "ErrNoRequest", "ErrCannotWarAlly", "ErrNotWarLeader", "ErrAlreadyAtWar", "ErrTargetAlreadyAtWar", "ErrTargetNotFound", "ErrCannotAllyEnemy", "ErrTargetOffline",
    }

    local langRow = vgui.Create("DPanel", sForm)
    langRow:SetSize(720, 30)
    langRow.Paint = function() end

    local langLbl = vgui.Create("DLabel", langRow)
    langLbl:SetPos(5, 7)
    langLbl:SetSize(150, 20)
    langLbl:SetText("Load language preset:")

    local langCombo = vgui.Create("DComboBox", langRow)
    langCombo:SetPos(160, 3)
    langCombo:SetSize(240, 24)
    langCombo:SetValue("Select a preset...")
    for _, preset in ipairs(SFS.LangPresetList or {}) do
        langCombo:AddChoice(preset.label, preset.id)
    end

    sForm:AddItem(langRow)

    local stringEntries = {}
    for _, k in ipairs(stringKeys) do
        local row = vgui.Create("DPanel", sForm)
        row:SetSize(720, 26)
        row.Paint = function() end

        local lbl = vgui.Create("DLabel", row)
        lbl:SetPos(5, 4)
        lbl:SetSize(180, 20)
        lbl:SetText(k)
        lbl:SetTextColor(color_black)

        local entry = vgui.Create("DTextEntry", row)
        entry:SetPos(190, 2)
        entry:SetSize(510, 22)
        entry:SetText(SFS.Strings and SFS.Strings[k] or "")

        sForm:AddItem(row)
        stringEntries[k] = entry
    end

    local function saveStrings()
        if not netCooldown("savestrings") then return end
        local t = {}
        for k, entry in pairs(stringEntries) do
            t[k] = entry:GetValue()
        end
        net.Start("SFS_UpdateStrings")
        net.WriteString(util.TableToJSON(t))
        net.SendToServer()
    end

    langCombo.OnSelect = function(_, _, _, presetID)
        local preset = SFS.LangPresets and SFS.LangPresets[presetID]
        if not preset then return end
        for k, entry in pairs(stringEntries) do
            if IsValid(entry) and preset[k] then
                entry:SetText(preset[k])
            end
        end
        saveStrings()
        Derma_Message("Language preset applied and saved!", "Saved", "OK")
    end

    local strHookName = "SFS_StringsUpdated_Panel_" .. tostring(stringsPnl)
    hook.Add("SFS_StringsUpdated", strHookName, function()
        if not IsValid(stringsPnl) then
            hook.Remove("SFS_StringsUpdated", strHookName)
            return
        end
        for k, entry in pairs(stringEntries) do
            if IsValid(entry) then
                entry:SetText(SFS.Strings and SFS.Strings[k] or "")
            end
        end
    end)

    local spacer = vgui.Create("DPanel", sForm)
    spacer:SetSize(720, 10)
    spacer.Paint = function() end
    sForm:AddItem(spacer)

    sForm:Button("Save Strings", "").DoClick = function()
        saveStrings()
        Derma_Message("Strings saved! They will persist across restarts.", "Saved", "OK")
    end

    sForm:Button("Reset to Defaults", "").DoClick = function()
        Derma_Query("Reset all strings to their default values?", "Confirm Reset",
            "Yes", function()
                if not netCooldown("resetstrings") then return end
                net.Start("SFS_UpdateStrings")
                net.WriteString(util.TableToJSON(SFS.StringDefaults or {}))
                net.SendToServer()
                Derma_Message("Strings reset to defaults.", "Done", "OK")
            end, "Cancel", function() end)
    end

    innerSheet:AddSheet("Strings", stringsPnl, "icon16/page_edit.png")

    local groupsPnl = vgui.Create("DPanel", innerSheet)
    groupsPnl.Paint = function() end

    local gScroll = vgui.Create("DScrollPanel", groupsPnl)
    gScroll:SetPos(4, 4) gScroll:SetSize(760, 420)

    local gForm = vgui.Create("DForm", gScroll)
    gForm:SetPos(0, 0) gForm:SetSize(740, 420)
    gForm:SetName("Permission Groups — GMod usergroup names (e.g. superadmin, admin, vip)")

    local function buildGroupSection(label, groupList)
        local hdr = vgui.Create("DLabel", gForm)
        hdr:SetText(label)
        hdr:SetFont("DermaDefaultBold")
        gForm:AddItem(hdr)

        local listView = vgui.Create("DListView", gForm)
        listView:SetSize(720, 80)
        listView:AddColumn("Usergroup"):SetWidth(680)
        for _, g in ipairs(groupList) do
            local ln = listView:AddLine(g)
            ln.groupName = g
        end
        gForm:AddItem(listView)

        listView.OnRowSelected = function(_, _, ln)
            if not ln then return end
            local menu = DermaMenu()
            menu:AddOption("Remove", function()
                for i, row in ipairs(listView:GetLines()) do
                    if row == ln then table.remove(listView:GetLines(), i) break end
                end
                listView:RemoveLine(ln:GetID())
            end)
            menu:Open()
        end

        local addRow = vgui.Create("DPanel", gForm)
        addRow:SetSize(720, 26)
        addRow.Paint = function() end

        local addEntry = vgui.Create("DTextEntry", addRow)
        addEntry:SetPos(0, 1) addEntry:SetSize(580, 24)
        addEntry:SetPlaceholderText("usergroup name...")

        local addBtn = vgui.Create("DButton", addRow)
        addBtn:SetPos(586, 1) addBtn:SetSize(130, 24)
        addBtn:SetText("Add Group")
        addBtn.DoClick = function()
            local val = addEntry:GetValue():Trim():lower()
            if val == "" then return end
            for _, row in ipairs(listView:GetLines()) do
                if row:GetValue(1) == val then return end
            end
            local ln = listView:AddLine(val)
            ln.groupName = val
            addEntry:SetText("")
        end

        gForm:AddItem(addRow)

        return listView
    end

    local saList = buildGroupSection("SuperAdmin Groups (full access)", SFS.Config.SuperAdminGroups or { "superadmin" })
    local aList  = buildGroupSection("Admin Groups (can force join/leave)", SFS.Config.AdminGroups or { "admin", "superadmin" })

    gForm:Button("Save Groups", "").DoClick = function()
        if not netCooldown("savegroups") then return end
        local saGroups, aGroups = {}, {}
        for _, row in ipairs(saList:GetLines()) do table.insert(saGroups, row:GetValue(1)) end
        for _, row in ipairs(aList:GetLines())  do table.insert(aGroups,  row:GetValue(1)) end
        net.Start("SFS_UpdateGroups")
        net.WriteString(util.TableToJSON({ superadmin = saGroups, admin = aGroups }))
        net.SendToServer()
        Derma_Message("Groups saved! Changes take effect immediately.", "Saved", "OK")
    end

    local warDurHdr = vgui.Create("DLabel", gForm)
    warDurHdr:SetText("War Duration (seconds, requires sfs_faction_war_duration convar)")
    warDurHdr:SetFont("DermaDefaultBold")
    gForm:AddItem(warDurHdr)

    local warDurRow = vgui.Create("DPanel", gForm)
    warDurRow:SetSize(720, 26)
    warDurRow.Paint = function() end

    local warDurEntry = vgui.Create("DTextEntry", warDurRow)
    warDurEntry:SetPos(0, 1)
    warDurEntry:SetSize(120, 24)
    warDurEntry:SetNumeric(true)
    warDurEntry:SetValue(tostring(SFS.Config.WarDuration or 3600))
    warDurEntry:SetPlaceholderText("seconds...")

    local warDurBtn = vgui.Create("DButton", warDurRow)
    warDurBtn:SetPos(126, 1)
    warDurBtn:SetSize(120, 24)
    warDurBtn:SetText("Set War Duration")
    warDurBtn.DoClick = function()
        local val = tonumber(warDurEntry:GetValue()) or 3600
        val = math.max(60, math.floor(val))
        RunConsoleCommand("sfs_faction_war_duration", tostring(val))
        Derma_Message("War duration set to " .. val .. "s. Active wars use old duration.", "Set", "OK")
    end

    gForm:AddItem(warDurRow)

    hook.Add("SFS_ConfigUpdated", "SFS_WarDur_" .. tostring(warDurEntry), function()
        if not IsValid(warDurEntry) then
            hook.Remove("SFS_ConfigUpdated", "SFS_WarDur_" .. tostring(warDurEntry))
            return
        end
        warDurEntry:SetValue(tostring(SFS.Config.WarDuration or 3600))
    end)

    innerSheet:AddSheet("Groups", groupsPnl, "icon16/shield.png")
    local iconsPnl = vgui.Create("DPanel", innerSheet)
    iconsPnl.Paint = function() end

    local iScroll = vgui.Create("DScrollPanel", iconsPnl)
    iScroll:SetPos(4, 36) iScroll:SetSize(756, 390)

    local iStatusLbl = vgui.Create("DLabel", iconsPnl)
    iStatusLbl:SetPos(4, 4) iStatusLbl:SetSize(500, 24)
    iStatusLbl:SetText("")

    local function refreshIconList()
        iScroll:Clear()
        if not file.IsDir("sfs_icons", "DATA") then
            local lbl = vgui.Create("DLabel", iScroll)
            lbl:SetText("No cached icons found.")
            lbl:Dock(TOP) lbl:SetTall(30)
            return
        end
        local files, _ = file.Find("sfs_icons/*.png", "DATA")
        if not files or #files == 0 then
            local lbl = vgui.Create("DLabel", iScroll)
            lbl:SetText("No cached icons found.")
            lbl:Dock(TOP) lbl:SetTall(30)
            return
        end

        iStatusLbl:SetText("Cached icons: " .. #files)



        for _, fname in ipairs(files) do
            local fullPath = "sfs_icons/" .. fname
            local row = vgui.Create("DPanel", iScroll)
            row:SetTall(36)
            row:Dock(TOP)
            row:DockMargin(0, 1, 0, 0)
            row.Paint = function(_, w, h)
                surface.SetDrawColor(235, 235, 235)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(190, 190, 190)
                surface.DrawOutlinedRect(0, 0, w, h)
            end

            local mat = Material("../data/" .. fullPath, "noclamp smooth")
            local img = vgui.Create("DImage", row)
            img:SetPos(4, 4) img:SetSize(28, 28)
            img:SetMaterial(mat)

            local nameLbl = vgui.Create("DLabel", row)
            nameLbl:SetPos(38, 4) nameLbl:SetSize(380, 14)
            nameLbl:SetText(fname)
            nameLbl:SetFont("DermaDefault")

            local facName = SFS.CL.GetIconFactionName and SFS.CL.GetIconFactionName(fname) or "Unknown"
            local facLbl = vgui.Create("DLabel", row)
            facLbl:SetPos(38, 20) facLbl:SetSize(380, 14)
            facLbl:SetText("Faction: " .. facName)
            facLbl:SetFont("DermaDefault")
            facLbl:SetTextColor(Color(100, 100, 120))

            local delBtn = vgui.Create("DButton", row)
            delBtn:SetText("Delete")
            delBtn:SetPos(760 - 70, 6) delBtn:SetSize(64, 24)
            delBtn.DoClick = function()
                file.Delete(fullPath)
                if iconMatCache then
                    for url, _ in pairs(iconMatCache) do
                        local fn = "sfs_icons/" .. url:gsub("[^%w]", "_"):sub(1, 60) .. ".png"
                        if fn == fullPath then iconMatCache[url] = nil break end
                    end
                end
                refreshIconList()
            end
        end
    end

    refreshIconList()

    local clearAllBtn = vgui.Create("DButton", iconsPnl)
    clearAllBtn:SetText("Clear All Icons")
    clearAllBtn:SetPos(620, 4) clearAllBtn:SetSize(120, 26)
    clearAllBtn.DoClick = function()
        Derma_Query("Delete ALL cached faction icons?", "Confirm",
            "Clear", function()
                if file.IsDir("sfs_icons", "DATA") then
                    local files, _ = file.Find("sfs_icons/*.png", "DATA")
                    for _, f in ipairs(files or {}) do file.Delete("sfs_icons/" .. f) end
                end
                iconMatCache = {}
                refreshIconList()
                iStatusLbl:SetText("All icons cleared.")
            end,
            "Cancel", function() end
        )
    end

    local sizeLimitWrap = vgui.Create("DPanel", iconsPnl)
    sizeLimitWrap:SetPos(4, 432) sizeLimitWrap:SetSize(400, 28)
    sizeLimitWrap.Paint = function() end

    local sizeLimitLbl = vgui.Create("DLabel", sizeLimitWrap)
    sizeLimitLbl:SetPos(0, 4) sizeLimitWrap:SetSize(400, 28)
    sizeLimitLbl:SetText("Max icon size (MB, 0=unlimited):")
    sizeLimitLbl:SetSize(200, 22)

    local sizeLimitEntry = vgui.Create("DTextEntry", sizeLimitWrap)
    sizeLimitEntry:SetPos(208, 2) sizeLimitEntry:SetSize(60, 24)
    sizeLimitEntry:SetValue(tostring(SFS.Config.IconMaxSizeMB or 20))
    sizeLimitEntry:SetNumeric(true)

    local sizeLimitSave = vgui.Create("DButton", sizeLimitWrap)
    sizeLimitSave:SetPos(274, 2) sizeLimitSave:SetSize(60, 24)
    sizeLimitSave:SetText("Set")
    sizeLimitSave.DoClick = function()
        local val = tonumber(sizeLimitEntry:GetValue()) or 20
        val = math.Clamp(math.floor(val), 0, 512)
        RunConsoleCommand("sfa_icon_max_size_mb", tostring(val))
    end

    hook.Add("SFS_ConfigUpdated", "SFS_IconSizeLimit_" .. tostring(iconsPnl), function()
        if not IsValid(iconsPnl) then
            hook.Remove("SFS_ConfigUpdated", "SFS_IconSizeLimit_" .. tostring(iconsPnl))
            return
        end
        sizeLimitEntry:SetValue(tostring(SFS.Config.IconMaxSizeMB or 20))
    end)

    local imgurToggle = vgui.Create("DButton", iconsPnl)
    imgurToggle:SetPos(4, 466) imgurToggle:SetSize(200, 26)
    imgurToggle.Paint = function(self, w, h)
        local bg = SFS.Config.AllowImgurPictures and Color(60, 160, 60) or Color(160, 60, 60)
        draw.RoundedBox(4, 0, 0, w, h, bg)
        draw.SimpleText(
            SFS.Config.AllowImgurPictures and "Imgur: ENABLED" or "Imgur: DISABLED",
            "DermaDefaultBold", w*0.5, h*0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end
    imgurToggle.DoClick = function()
        local newVal = SFS.Config.AllowImgurPictures and "0" or "1"
        RunConsoleCommand("sfa_allow_imgur_pictures", newVal)
    end

    hook.Add("SFS_ConfigUpdated", "SFS_IconsTab_Config_" .. tostring(iconsPnl), function()
        if not IsValid(iconsPnl) then
            hook.Remove("SFS_ConfigUpdated", "SFS_IconsTab_Config_" .. tostring(iconsPnl))
            return
        end
        imgurToggle:InvalidateLayout()
    end)

    innerSheet:AddSheet("Icons", iconsPnl, "icon16/pictures.png")

    local permsPnl = vgui.Create("DPanel", innerSheet)
    permsPnl.Paint = function() end

    local pScroll = vgui.Create("DScrollPanel", permsPnl)
    pScroll:Dock(FILL)

    local pForm = vgui.Create("DForm", pScroll)
    pForm:Dock(TOP)
    pForm:SetName("Staff Group Permissions — which usergroups can do what")

    local PERM_DEFS = {
        { key = "delete_faction",   label = "Delete factions" },
        { key = "force_join",       label = "Force player into faction" },
        { key = "force_leave",      label = "Force player out of faction" },
        { key = "clear_icon_cache", label = "Clear all icon cache" },
        { key = "delete_icon",      label = "Delete individual icons" },
        { key = "edit_strings",     label = "Edit configurable strings" },
        { key = "edit_groups",      label = "Edit permission groups" },
        { key = "set_war_duration", label = "Set war duration" },
    }

    local groupsToShow = {}
    for _, g in ipairs(SFS.Config.SuperAdminGroups or {}) do groupsToShow[g] = true end
    for _, g in ipairs(SFS.Config.AdminGroups or {}) do groupsToShow[g] = true end

    local permChecks = {}

    local function buildPermsUI()
        pForm:Clear()

        groupsToShow = {}
        for _, g in ipairs(SFS.Config.SuperAdminGroups or {}) do groupsToShow[g] = true end
        for _, g in ipairs(SFS.Config.AdminGroups or {}) do groupsToShow[g] = true end
        for g in pairs(SFS.CL.GroupPerms or {}) do groupsToShow[g] = true end

        local sortedGroups = {}
        for g in pairs(groupsToShow) do sortedGroups[#sortedGroups+1] = g end
        table.sort(sortedGroups)

        permChecks = {}

        local hdrRow = vgui.Create("DPanel", pForm)
        hdrRow:SetSize(720, 22)
        hdrRow.Paint = function() end
        local colW = math.floor(680 / math.max(1, #sortedGroups))
        for i, g in ipairs(sortedGroups) do
            local lbl = vgui.Create("DLabel", hdrRow)
            lbl:SetPos(140 + (i-1)*colW, 2)
            lbl:SetSize(colW, 18)
            lbl:SetText(g)
            lbl:SetFont("DermaDefaultBold")
        end
        pForm:AddItem(hdrRow)

        for _, permDef in ipairs(PERM_DEFS) do
            local row = vgui.Create("DPanel", pForm)
            row:SetSize(720, 22)
            row.Paint = function() end

            local pLbl = vgui.Create("DLabel", row)
            pLbl:SetPos(0, 2)
            pLbl:SetSize(136, 18)
            pLbl:SetText(permDef.label)
            pLbl:SetTextColor(color_black)

            permChecks[permDef.key] = {}
            for i, g in ipairs(sortedGroups) do
                local chk = vgui.Create("DCheckBox", row)
                chk:SetPos(140 + (i-1)*colW + math.floor(colW*0.5) - 8, 2)
                chk:SetSize(18, 18)
                local val = SFS.CL.GroupPerms and SFS.CL.GroupPerms[g] and SFS.CL.GroupPerms[g][permDef.key]
                chk:SetChecked(val == true)
                permChecks[permDef.key][g] = chk
            end

            pForm:AddItem(row)
        end

        local savePermsBtn = vgui.Create("DButton", pForm)
        savePermsBtn:SetSize(720, 26)
        savePermsBtn:SetText("Save Permissions")
        savePermsBtn:SetImage("icon16/shield.png")
        savePermsBtn.DoClick = function()
            if not netCooldown("saveperms") then return end
            local result = {}
            for _, permDef in ipairs(PERM_DEFS) do
                for g, chk in pairs(permChecks[permDef.key] or {}) do
                    result[g] = result[g] or {}
                    result[g][permDef.key] = chk:GetChecked()
                end
            end
            net.Start("SFS_SaveGroupPerms")
            net.WriteString(util.TableToJSON(result))
            net.SendToServer()
            Derma_Message("Permissions saved.", "Saved", "OK")
        end
        pForm:AddItem(savePermsBtn)
    end

    buildPermsUI()

    hook.Add("SFS_GroupPermsUpdated", "SFS_PermsTab_" .. tostring(permsPnl), function()
        if not IsValid(permsPnl) then
            hook.Remove("SFS_GroupPermsUpdated", "SFS_PermsTab_" .. tostring(permsPnl))
            return
        end
        buildPermsUI()
    end)

    innerSheet:AddSheet("Permissions", permsPnl, "icon16/key.png")

    hook.Add("SFS_FactionsUpdated", "SFS_StaffTab_" .. tostring(pnl), function()
        if not IsValid(pnl) then hook.Remove("SFS_FactionsUpdated", "SFS_StaffTab_" .. tostring(pnl)) return end
        refreshFList()
    end)

    return pnl
end

function SFS.IsSuperAdminCL()
    local ply = LocalPlayer()
    return IsValid(ply) and ply:IsSuperAdmin()
end

--// preferredTab: optional sheet name to land on instead of the first tab
--// (DPropertySheet always selects whatever was added first otherwise) -
--// used so creating/joining a faction lands you on "My Faction" to see the
--// result immediately, instead of back on the generic browse list.
function SFS.OpenMainPanel(preferredTab)
    if IsValid(activePanel) then activePanel:Remove() end

    local frame = vgui.Create("DFrame")
    activePanel = frame
    frame:SetTitle("Factions")
    frame:SetSize(800, 540)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)

    local sheet = vgui.Create("DPropertySheet", frame)
    sheet:Dock(FILL)
    sheet:DockMargin(4, 4, 4, 4)

    local myFac  = SFS.CL.GetMyFaction()
    local myRank = SFS.CL.GetMyRank()

    sheet:AddSheet("Factions",    buildFactionBrowser(sheet), "icon16/group.png")
    sheet:AddSheet("War",   SFS.BuildWarTab(sheet),      "icon16/bomb.png")
    local myFacSheet
    if myFac then
        myFacSheet = sheet:AddSheet("My Faction", buildMyFactionTab(sheet), "icon16/user.png")
    end
    if myFac and (myRank == "owner" or myRank == "subowner") then
        sheet:AddSheet("Manage Faction", buildManageTab(sheet), "icon16/cog.png")
    end
    if not myFac then
        sheet:AddSheet("Create Faction", buildCreateTab(sheet), "icon16/add.png")
    end
    if SFS.IsSuperAdminCL() or (SFS.CL.HasGroupPerm and SFS.CL.HasGroupPerm("force_join")) then
        sheet:AddSheet("Staff Panel", buildStaffTab(sheet), "icon16/shield.png")
    end
    sheet:AddSheet("Settings", buildSettingsTab(sheet), "icon16/cog.png")

    if preferredTab == "My Faction" and myFacSheet then
        sheet:SetActiveTab(myFacSheet.Tab)
    end

    hook.Add("SFS_FactionsUpdated", "SFS_RebuildPanel_" .. tostring(frame), function()
        if not IsValid(frame) then
            hook.Remove("SFS_FactionsUpdated", "SFS_RebuildPanel_" .. tostring(frame))
            return
        end
        timer.Simple(0, function()
            if not IsValid(frame) then return end
            local newMyFac  = SFS.CL.GetMyFaction()
            local newMyRank = SFS.CL.GetMyRank()
            local facIDOld  = myFac  and myFac.id
            local facIDNew  = newMyFac and newMyFac.id
            local changed   = (facIDOld ~= facIDNew) or (newMyRank ~= myRank)
            if changed then
                SFS.OpenMainPanel(facIDOld ~= facIDNew and newMyFac and "My Faction" or nil)
            else
                myFac  = newMyFac
                myRank = newMyRank
            end
        end)
    end)
end

concommand.Add("sfs_clearicons", function()
    if not SFS.IsSuperAdminCL() then print("[Factions] Access denied.") return end
    if not file.IsDir("sfs_icons", "DATA") then print("[Factions] No icon cache found.") return end
    local files, _ = file.Find("sfs_icons/*.png", "DATA")
    local count = #(files or {})
    for _, f in ipairs(files or {}) do file.Delete("sfs_icons/" .. f) end
    iconMatCache = {}
    print("[Factions] Cleared " .. count .. " cached icon(s).")
end, nil, "Clear all cached faction icons (superadmin only)")

concommand.Add("factions",      function() SFS.OpenMainPanel() end, nil, "Open the factions panel")
concommand.Add("factions_open", function() SFS.OpenMainPanel() end)

SFS:print("Main panel loaded")
