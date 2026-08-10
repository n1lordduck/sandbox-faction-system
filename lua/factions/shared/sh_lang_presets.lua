local SFS = SandboxFactionSystem

local LANG_DIR = "lua/factions/languages/"
local DEFAULT_LANG_ID = "english"

SFS.LangPresets    = {}
SFS.LangPresetList = {}
SFS.DefaultLangID  = DEFAULT_LANG_ID

function SFS.LoadLangPresets()
    SFS.LangPresets    = {}
    SFS.LangPresetList = {}

    local files = file.Find(LANG_DIR .. "*.json", "GAME")
    for _, fname in ipairs(files or {}) do
        local raw = file.Read(LANG_DIR .. fname, "GAME")
        local data = raw and util.JSONToTable(raw)
        if data then
            local id    = fname:gsub("%.json$", "")
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
        SFS:warn("Default language file '" .. DEFAULT_LANG_ID .. ".json' missing or invalid")
    end
end

SFS.LoadLangPresets()

SFS:print("Language presets loaded: " .. table.Count(SFS.LangPresets))
