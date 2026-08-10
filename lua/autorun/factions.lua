include("factions/shared/sh_framework.lua")
AddCSLuaFile("factions/shared/sh_framework.lua")

include("factions/shared/sh_lang_presets.lua")
AddCSLuaFile("factions/shared/sh_lang_presets.lua")

include("factions/shared/sh_config.lua")
AddCSLuaFile("factions/shared/sh_config.lua")

include("factions/shared/sh_net.lua")
AddCSLuaFile("factions/shared/sh_net.lua")

include("factions/shared/sh_errors.lua")
AddCSLuaFile("factions/shared/sh_errors.lua")

if SERVER then
    include("factions/server/sv_data.lua")
    include("factions/server/sv_factions.lua")
    include("factions/server/sv_net.lua")
    include("factions/server/sv_init.lua")
    include("factions/server/sv_war.lua")
    include("factions/server/sv_war_net.lua")
    include("factions/server/sv_group_perms.lua")

    AddCSLuaFile("factions/client/cl_data.lua")
    AddCSLuaFile("factions/client/cl_halo.lua")
    AddCSLuaFile("factions/client/cl_ping.lua")
    AddCSLuaFile("factions/client/cl_panel.lua")
    AddCSLuaFile("factions/client/cl_keybind.lua")
    AddCSLuaFile("factions/client/cl_notify.lua")
    AddCSLuaFile("factions/client/cl_war_data.lua")
    AddCSLuaFile("factions/client/cl_war_panel.lua")
end

if CLIENT then
    include("factions/client/cl_data.lua")
    include("factions/client/cl_halo.lua")
    include("factions/client/cl_ping.lua")
    include("factions/client/cl_panel.lua")
    include("factions/client/cl_keybind.lua")
    include("factions/client/cl_notify.lua")
    include("factions/client/cl_war_data.lua")
    include("factions/client/cl_war_panel.lua")
end
