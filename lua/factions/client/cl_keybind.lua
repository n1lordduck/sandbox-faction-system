local SFS = SandboxFactionSystem

hook.Add("PopulateToolMenu", "SFS_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "Factions", "SFS_Settings", "Faction Settings", "", "", function(pnl)
        pnl:ClearControls()
        pnl:Help("Sandbox Factions Settings")
        pnl:Help("Ping Keybind (default: B)")
        local keyBinder = pnl:KeyBinder("Ping Key", "sfs_ping_key")
        keyBinder:SetSize(230, 30)
        pnl:Help("Open faction panel with 'factions' in console or chat.")
    end)
end)

hook.Add("PlayerSay", "SFS_ChatCommands", function(text)
    if text == "!factions" or text == "!faction" then
        SFS.OpenMainPanel()
        return ""
    end
end)

SFS:print("Keybind config loaded")

local _matGun = Material("icon16/gun.png")

list.Set("DesktopWindows", "SFS_FactionPanel", {
    title     = "Factions",
    icon      = "icon16/gun.png",
    width     = 900,
    height    = 620,
    onewindow = true,
    init = function(widgetIcon, window)
        if IsValid(widgetIcon) then
            widgetIcon.Paint = function(self, w, h)
                local hov = self:IsHovered()
                local bg  = hov and Color(70, 95, 135, 230) or Color(25, 30, 42, 210)
                local brd = hov and Color(230, 235, 255, 255) or Color(150, 165, 205, 200)

                draw.RoundedBox(10, 0, 0, w, h, bg)

                surface.SetDrawColor(brd.r, brd.g, brd.b, brd.a)
                surface.DrawOutlinedRect(1, 1, w - 2, h - 2)
                surface.SetDrawColor(brd.r, brd.g, brd.b, math.floor(brd.a * 0.35))
                surface.DrawOutlinedRect(0, 0, w, h)

                surface.SetMaterial(_matGun)
                surface.SetDrawColor(brd.r, brd.g, brd.b, 255)
                surface.DrawTexturedRect(
                    math.floor((w - 22) * 0.5),
                    math.floor((h - 22) * 0.5) - 5,
                    22, 22
                )

                draw.SimpleTextOutlined(
                    "Factions", "DermaDefault",
                    math.floor(w * 0.5), h - 11,
                    Color(215, 222, 255, 255),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
                    1, Color(0, 0, 0, 200)
                )
            end
        end

        if IsValid(window) then
            window:Close()
        end

        SFS.OpenMainPanel()
        surface.PlaySound("buttons/button15.wav")
    end,
})

concommand.Add("sfs_test_notify_rank", function()
    SFS.Notify("rank", "Você foi promovido a Administrador em MinhaFaccao!")
end, nil, "Testa notificação de rank")

concommand.Add("sfs_test_notify_join", function()
    SFS.Notify("join_request", "Jogador123 quer entrar em MinhaFaccao.")
end, nil, "Testa notificação de pedido de entrada")

concommand.Add("sfs_test_notify_alliance", function()
    SFS.Notify("alliance", "FaccaoInimiga quer ser sua aliada!")
end, nil, "Testa notificação de aliança")

concommand.Add("sfs_test_notify_approved", function()
    SFS.Notify("approved", "Seu pedido para entrar em MinhaFaccao foi aceito!")
end, nil, "Testa notificação de pedido aceito")

concommand.Add("sfs_test_notify_kicked", function()
    SFS.Notify("kicked", "Você foi expulso de MinhaFaccao.")
end, nil, "Testa notificação de expulsão")

concommand.Add("sfs_test_notify_all", function()
    SFS.Notify("rank", "Você foi promovido a Administrador em MinhaFaccao!")
    timer.Simple(0.4, function() SFS.Notify("join_request", "Jogador123 quer entrar em MinhaFaccao.") end)
    timer.Simple(0.8, function() SFS.Notify("alliance",     "FaccaoInimiga quer ser sua aliada!") end)
    timer.Simple(1.2, function() SFS.Notify("approved",     "Seu pedido para entrar em MinhaFaccao foi aceito!") end)
    timer.Simple(1.6, function() SFS.Notify("kicked",       "Você foi expulso de MinhaFaccao.") end)
end, nil, "Testa todos os tipos de notificação de uma vez")
