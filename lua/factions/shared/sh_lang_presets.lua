local SFS = SandboxFactionSystem

local LANG_DIR = "factions/languages/"
local DEFAULT_LANG_ID = "english"

SFS.LangPresets    = {}
SFS.LangPresetList = {}
SFS.DefaultLangID  = DEFAULT_LANG_ID

function SFS.LoadLangPresets()
    SFS.LangPresets    = {}
    SFS.LangPresetList = {}

    local files = file.Find("lua/" .. LANG_DIR .. "*.lua", "GAME")
    for _, fname in ipairs(files or {}) do
        AddCSLuaFile(LANG_DIR .. fname)
        local data = include(LANG_DIR .. fname)
        if istable(data) then
            local id    = fname:gsub("%.lua$", "")
            local label = data._label or id
            data._label = nil

            SFS.LangPresets[id] = data
            SFS.LangPresetList[#SFS.LangPresetList + 1] = { id = id, label = label }
        else
            SFS:warn("Failed to load language file: " .. fname)
        end
    end

    table.sort(SFS.LangPresetList, function(a, b) return a.label < b.label end)

    if not SFS.LangPresets[DEFAULT_LANG_ID] then
        SFS:warn("Default language file '" .. DEFAULT_LANG_ID .. ".lua' missing or invalid")
    end
end

SFS.LoadLangPresets()

SFS:print("Language presets loaded: " .. table.Count(SFS.LangPresets))
