local SFS = SandboxFactionSystem

SFS.Config = {
    MaxFactionNameLength        = 30,
    MaxFactionDescLength        = 60,
    PingKey                     = KEY_B,
    PingDuration                = 8,
    PingMaxDistance             = 3000,
    HaloHealthGreen             = 80,
    HaloHealthYellow            = 30,
    HaloWidth                   = 2,
    HaloAddPixelBorder          = true,
    SaveInterval                = 300,
    IconCacheTime               = 3600,
    AdminLogFile                = "faction_admin_actions.txt",
    SuperAdminGroups            = { "superadmin" },
    AdminGroups                 = { "admin", "superadmin" },
    DefaultIconMaterial         = "icon16/group.png",
    FriendlyFireDefault         = false,
    AllowImgurPictures          = false,
    FactionMaxAllies            = 4,
}

SFS.Strings = {}
for k, v in pairs(SFS.LangPresets[SFS.DefaultLangID] or {}) do SFS.Strings[k] = v end

function SFS.FormatString(key, vars)
    local str = SFS.Strings[key]
    if not str then return key end
    for k, v in pairs(vars) do
        str = str:gsub("{" .. k .. "}", tostring(v))
    end
    str = str:gsub("{addonprefix}", SFS.Strings.AddonPrefix)
    return str
end

SFS:print("Config loaded")

SFS.StringDefaults = {}
for k, v in pairs(SFS.Strings) do SFS.StringDefaults[k] = v end
