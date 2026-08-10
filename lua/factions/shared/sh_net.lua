local SFS = SandboxFactionSystem

local netStrings = {
    "SFS_CreateFaction",
    "SFS_DeleteFaction",
    "SFS_UpdateFaction",
    "SFS_KickMember",
    "SFS_ApproveMember",
    "SFS_DenyMember",
    "SFS_RequestJoin",
    "SFS_JoinPublic",
    "SFS_LeaveFacton",
    "SFS_PromoteMember",
    "SFS_SendAllyRequest",
    "SFS_AcceptAllyRequest",
    "SFS_DeclineAllyRequest",
    "SFS_RemoveAlly",
    "SFS_AdminDeleteFaction",
    "SFS_SyncAll",
    "SFS_SyncFaction",
    "SFS_Ping",
    "SFS_PingReceive",
    "SFS_ChatMsg",
    "SFS_UpdateGroups",
    "SFS_AddSubOwner",
    "SFS_RemoveSubOwner",
    "SFS_AdminForceJoin",
    "SFS_AdminForceLeave",
    "SFS_UpdatePermissions",
    "SFS_ToggleFriendlyFire",
    "SFS_SetMemberRank",
    "SFS_TransferOwnership",
    "SFS_UpdateRankLabels",
    "SFS_UpdateStrings",
    "SFS_ToggleHalo",
    "SFS_FactionChat",
    "SFS_Notify",
    "SFS_DeclareWar",
    "SFS_RequestTruce",
    "SFS_WarSync",
    "SFS_WarRemoved",
    "SFS_WarsFullSync",
    "SFS_WarTruceRequest",
    "SFS_SyncConfig",
    "SFS_FactionAnnounce",
    "SFS_WarNotify",
    "SFS_WarEndNotify",
    "SFS_SyncGroupPerms",
    "SFS_SaveGroupPerms",
    "SFS_SetLangPref",
}

if SERVER then
    for _, name in ipairs(netStrings) do
        util.AddNetworkString(name)
    end
    SFS:print("Net strings registered")
end
