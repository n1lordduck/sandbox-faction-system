local SFS = SandboxFactionSystem

local NOTIFS       = {}
local NOTIF_W      = 320
local NOTIF_H      = 64
local NOTIF_PAD    = 8
local NOTIF_DUR    = 6
local NOTIF_ANIM   = 0.35
local NOTIF_MARGIN = 12

local TYPES = {
    rank = {
        icon  = "icon16/award_star_gold_1.png",
        bar   = Color(255, 180, 0),
        bg    = Color(30,  25,  10),
        title = "Faction Promotion",
        sound = "buttons/button17.wav",
    },
    join_request = {
        icon  = "icon16/user_add.png",
        bar   = Color(60,  160, 255),
        bg    = Color(10,  20,  35),
        title = "Join Request",
        sound = "buttons/button15.wav",
    },
    alliance = {
        icon  = "icon16/connect.png",
        bar   = Color(80,  220, 120),
        bg    = Color(10,  30,  18),
        title = "Alliance Request",
        sound = "buttons/button14.wav",
    },
    approved = {
        icon  = "icon16/tick.png",
        bar   = Color(100, 230, 100),
        bg    = Color(10,  28,  10),
        title = "Request Accepted!",
        sound = "buttons/button24.wav",
    },
    kicked = {
        icon  = "icon16/user_delete.png",
        bar   = Color(220, 60,  60),
        bg    = Color(30,  10,  10),
        title = "Kicked from Faction",
        sound = "buttons/button11.wav",
    },
}

local matIcons = {}
local function getIcon(path)
    if not matIcons[path] then matIcons[path] = Material(path) end
    return matIcons[path]
end

local function getTargetY(idx)
    return ScrH() - NOTIF_MARGIN - (NOTIF_H + NOTIF_PAD) * idx
end

local function removeNotif(id)
    for _, n in ipairs(NOTIFS) do
        if n.id == id and not n.removing then
            n.removing    = true
            n.removeStart = CurTime()
        end
    end
end

function SFS.Notify(notifType, message, duration)
    local cfg = TYPES[notifType]
    if not cfg then return end
    if GetConVar("sfs_notifications") and not GetConVar("sfs_notifications"):GetBool() then return end
    duration = duration or NOTIF_DUR

    local id  = tostring(CurTime()) .. tostring(math.random(10000))
    local now = CurTime()

    table.insert(NOTIFS, 1, {
        id          = id,
        cfg         = cfg,
        message     = message,
        startTime   = now,
        duration    = duration,
        removing    = false,
        removeStart = nil,
    })

    if not GetConVar("sfs_notification_sound") or GetConVar("sfs_notification_sound"):GetBool() then
        surface.PlaySound(cfg.sound)
    end

    timer.Simple(duration, function() removeNotif(id) end)
end

surface.CreateFont("SFS_NotifTitle", {
    font      = "Roboto",
    size      = 14,
    weight    = 700,
    antialias = true,
    fallback  = "DermaDefaultBold",
})
surface.CreateFont("SFS_NotifBody", {
    font      = "Roboto",
    size      = 13,
    weight    = 400,
    antialias = true,
    fallback  = "DermaDefault",
})

hook.Add("HUDPaint", "SFS_DrawNotifications", function()
    local now    = CurTime()
    local sw, sh = ScrW(), ScrH()
    local baseX  = sw - NOTIF_W - NOTIF_MARGIN

    local kept = {}
    for _, n in ipairs(NOTIFS) do
        if not n.removing or (now - n.removeStart) < NOTIF_ANIM then
            kept[#kept + 1] = n
        end
    end
    NOTIFS = kept

    for idx, n in ipairs(NOTIFS) do
        local cfg = n.cfg

        local slide, alpha
        if n.removing then
            local t = math.Clamp((now - n.removeStart) / NOTIF_ANIM, 0, 1)
            local ease = t * t
            slide = ease * (NOTIF_W + NOTIF_MARGIN + 20)
            alpha = math.floor((1 - t) * 255)
        else
            local t = math.Clamp((now - n.startTime) / NOTIF_ANIM, 0, 1)
            local ease = 1 - (1 - t) * (1 - t)
            slide = (1 - ease) * (NOTIF_W + NOTIF_MARGIN + 20)
            alpha = math.floor(ease * 255)
        end

        local x = baseX + slide
        local y = getTargetY(idx)

        local progress = n.removing and 0
            or math.Clamp(1 - ((now - n.startTime) / n.duration), 0, 1)

        draw.RoundedBox(8, x, y, NOTIF_W, NOTIF_H,
            Color(cfg.bg.r, cfg.bg.g, cfg.bg.b, math.floor(alpha * 0.96)))

        local bw = 4
        surface.SetDrawColor(cfg.bar.r, cfg.bar.g, cfg.bar.b, math.floor(alpha * 0.22))
        surface.DrawRect(x + bw, y + 2, NOTIF_W - bw - 2, NOTIF_H - 4)

        local barH = math.floor((NOTIF_H - 4) * progress)
        surface.SetDrawColor(cfg.bar.r, cfg.bar.g, cfg.bar.b, math.floor(alpha * 0.15))
        surface.DrawRect(x + bw, y + 2 + (NOTIF_H - 4 - barH), NOTIF_W - bw - 2, barH)

        surface.SetDrawColor(cfg.bar.r, cfg.bar.g, cfg.bar.b, alpha)
        surface.DrawRect(x, y + 8, bw, NOTIF_H - 16)

        surface.SetDrawColor(50, 50, 60, alpha)
        surface.DrawOutlinedRect(x, y, NOTIF_W, NOTIF_H)

        local iconX = x + bw + 10
        local iconY = y + (NOTIF_H - 16) * 0.5
        surface.SetMaterial(getIcon(cfg.icon))
        surface.SetDrawColor(cfg.bar.r, cfg.bar.g, cfg.bar.b, alpha)
        surface.DrawTexturedRect(iconX, iconY, 16, 16)

        local textX = iconX + 22

        draw.SimpleText(cfg.title, "SFS_NotifTitle", textX, y + 10,
            Color(cfg.bar.r, cfg.bar.g, cfg.bar.b, alpha),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local maxW = NOTIF_W - (textX - x) - 8
        surface.SetFont("SFS_NotifBody")
        local tw = surface.GetTextSize(n.message)
        local fitted = n.message
        if tw > maxW then
            while #fitted > 1 and surface.GetTextSize(fitted .. "...") > maxW do
                fitted = fitted:sub(1, -2)
            end
            fitted = fitted .. "..."
        end

        draw.SimpleText(fitted, "SFS_NotifBody", textX, y + 30,
            Color(210, 210, 220, alpha),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
end)

net.Receive("SFS_Notify", function()
    local notifType = net.ReadString()
    local message   = net.ReadString()
    SFS.Notify(notifType, message)
end)

SFS:print("Notification system loaded")

local function facNameColor(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + string.byte(name, i)) % 360 end
    
    local clr = HSVToColor(h, 0.7, 1) 
    return clr
end

net.Receive("SFS_FactionAnnounce", function()
    local facName = net.ReadString()
    local msg     = net.ReadString()
    local clr     = facNameColor(facName)
    chat.AddText(
        Color(200, 200, 200),  "[",
        clr,                   facName,
        Color(200, 200, 200),  "] ",
        Color(255, 230, 120),  msg
    )
    surface.PlaySound("buttons/button15.wav")
end)
