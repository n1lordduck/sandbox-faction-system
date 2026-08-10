local SFS = SandboxFactionSystem

local PERMS_FILE = "sandbox_factions/group_perms.json"

SFS.GroupPerms = {
    superadmin = {
        delete_faction   = true,
        force_join       = true,
        force_leave      = true,
        clear_icon_cache = true,
        delete_icon      = true,
        edit_strings     = true,
        edit_groups      = true,
        set_war_duration = true,
    },
    admin = {
        delete_faction   = false,
        force_join       = true,
        force_leave      = true,
        clear_icon_cache = false,
        delete_icon      = false,
        edit_strings     = false,
        edit_groups      = false,
        set_war_duration = false,
    },
}

local function saveGroupPerms()
    if not file.IsDir("sandbox_factions/", "DATA") then file.CreateDir("sandbox_factions/") end
    file.Write(PERMS_FILE, util.TableToJSON(SFS.GroupPerms))
end

local function loadGroupPerms()
    if not file.Exists(PERMS_FILE, "DATA") then return end
    local t = util.JSONToTable(file.Read(PERMS_FILE, "DATA"))
    if not t then return end
    for group, perms in pairs(t) do
        SFS.GroupPerms[group] = SFS.GroupPerms[group] or {}
        for perm, val in pairs(perms) do
            SFS.GroupPerms[group][perm] = val
        end
    end
end

function SFS.HasGroupPerm(ply, perm)
    if not IsValid(ply) then return false end
    for group, perms in pairs(SFS.GroupPerms) do
        if ply:IsUserGroup(group) and perms[perm] == true then
            return true
        end
    end
    return false
end

local function broadcastGroupPerms()
    net.Start("SFS_SyncGroupPerms")
    net.WriteString(util.TableToJSON(SFS.GroupPerms))
    net.Broadcast()
end

net.Receive("SFS_SaveGroupPerms", function(len, ply)
    if not SFS.IsSuperAdmin(ply) then return end
    local json = net.ReadString()
    local t    = util.JSONToTable(json)
    if not t then return end
    SFS.GroupPerms = t
    saveGroupPerms()
    broadcastGroupPerms()
    SFS:print("Group permissions updated by " .. ply:Nick())
end)

hook.Add("PlayerInitialSpawn", "SFS_SyncGroupPermsNew", function(ply)
    timer.Simple(2.5, function()
        if not IsValid(ply) then return end
        net.Start("SFS_SyncGroupPerms")
        net.WriteString(util.TableToJSON(SFS.GroupPerms))
        net.Send(ply)
    end)
end)

loadGroupPerms()
broadcastGroupPerms()
SFS:print("Group permissions loaded")
