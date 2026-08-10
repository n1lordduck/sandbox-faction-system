SandboxFactionSystem = SandboxFactionSystem or {}
SandboxFactionSystem.Version = "[SandboxFactions - 1.0.0]"

SandboxFactionSystem.Colors = {
    Server  = Color(13, 221, 176),
    Client  = Color(6, 240, 37),
    Version = Color(0, 153, 255),
    Warning = Color(255, 200, 0),
    Error   = Color(255, 60, 60),
}

local SFS = SandboxFactionSystem

function SFS:print(arg)
    local msg = ""
    if IsValid(arg) and arg:IsPlayer() then
        msg = " [PLAYER] " .. arg:Nick()
    elseif IsValid(arg) then
        msg = " [ENTITY] " .. arg:GetClass()
    elseif isstring(arg) then
        msg = " " .. tostring(arg)
    else
        msg = " " .. tostring(arg)
    end

    if SERVER then
        MsgC(SFS.Colors.Version, SFS.Version, SFS.Colors.Server, " [SERVER]", color_white, msg, "\n")
    elseif CLIENT then
        MsgC(SFS.Colors.Version, SFS.Version, SFS.Colors.Client, " [CLIENT]", color_white, msg, "\n")
    end
end

function SFS:warn(arg)
    local msg = isstring(arg) and (" " .. arg) or (" " .. tostring(arg))
    if SERVER then
        MsgC(SFS.Colors.Version, SFS.Version, SFS.Colors.Warning, " [WARN][SERVER]", color_white, msg, "\n")
    elseif CLIENT then
        MsgC(SFS.Colors.Version, SFS.Version, SFS.Colors.Warning, " [WARN][CLIENT]", color_white, msg, "\n")
    end
end

function SFS:err(arg)
    local msg = isstring(arg) and (" " .. arg) or (" " .. tostring(arg))
    if SERVER then
        MsgC(SFS.Colors.Version, SFS.Version, SFS.Colors.Error, " [ERROR][SERVER]", color_white, msg, "\n")
    elseif CLIENT then
        MsgC(SFS.Colors.Version, SFS.Version, SFS.Colors.Error, " [ERROR][CLIENT]", color_white, msg, "\n")
    end
end

SFS:print("Framework loaded - " .. SFS.Version)
