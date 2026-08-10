local SFS = SandboxFactionSystem

SFS.ErrorKeys = {
    already_in_faction          = "ErrAlreadyInFaction",
    invalid_name                = "ErrInvalidName",
    name_too_long               = "ErrNameTooLong",
    desc_too_long               = "ErrDescTooLong",
    name_taken                  = "ErrNameTaken",
    not_found                   = "ErrNotFound",
    not_public                  = "ErrNotPublic",
    is_public                   = "ErrIsPublic",
    already_requested           = "ErrAlreadyRequested",
    not_member                  = "ErrNotMember",
    no_permission               = "ErrNoPermission",
    cannot_kick                 = "ErrCannotKick",
    cannot_kick_subowner        = "ErrCannotKickSubowner",
    not_in_faction              = "ErrNotInFaction",
    owner_must_disband          = "ErrOwnerMustDisband",
    invalid_rank                = "ErrInvalidRank",
    not_owner                   = "ErrNotOwner",
    same_player                 = "ErrSamePlayer",
    same_faction                = "ErrSameFaction",
    already_allies              = "ErrAlreadyAllies",
    max_allies_reached          = "ErrMaxAllies",
    target_max_allies_reached   = "ErrTargetMaxAllies",
    request_already_sent        = "ErrRequestAlreadySent",
    no_request                  = "ErrNoRequest",
    cannot_war_ally             = "ErrCannotWarAlly",
    not_leader                  = "ErrNotWarLeader",
    already_at_war              = "ErrAlreadyAtWar",
    target_already_at_war       = "ErrTargetAlreadyAtWar",
    target_not_found            = "ErrTargetNotFound",
    cannot_ally_enemy           = "ErrCannotAllyEnemy",
    target_offline              = "ErrTargetOffline",
}

function SFS.GetError(code)
    local key = SFS.ErrorKeys[code]
    if key and SFS.Strings[key] then return SFS.Strings[key] end
    return "Error: " .. tostring(code)
end
