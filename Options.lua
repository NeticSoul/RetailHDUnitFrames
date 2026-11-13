--[[
    Retail HD UnitFrames - Options
    Copyright (c) 2026 NeticSoul. Released under the MIT License (see LICENSE).

    Saved settings, how each one applies (live), and the one-page panel in Options > AddOns.
    The panel and the first-run wizard both change settings through ns.Set.
]]
local _, ns = ...

local DEFAULTS = {
    health = "BOTH",
    power = "BOTH",
    abbreviate = "SHORT",
    hover = true,
    level = "RETAIL",
    pvp = "RETAIL",
    classColor = false,
    lossAnimation = true,
    classIcons = false,
    groupTab = true,
    threat = true,
    nameBackground = true,
    darkMode = "OFF",
    darkColor = { 0, 0, 0 },
    minimapButton = true,
    wizardDone = false,
}
local TEXT_MODES = { "NONE", "NUMERIC", "PERCENT", "BOTH" }
local CHOICES = {
    health = TEXT_MODES,
    power = TEXT_MODES,
    abbreviate = { "OFF", "SHORT", "LARGE" }, -- 1429200, 1.4M, 1429K
    level = { "RETAIL", "FOREVER", "HIDDEN" },
    pvp = { "RETAIL", "FOREVER", "HIDDEN" },
    darkMode = { "OFF", "LOW", "MEDIUM", "HIGH" },
}
ns.CHOICES = CHOICES
-- How much of the dark mode color goes into the frame art.
local INTENSITY = { LOW = 0.6, MEDIUM = 0.8, HIGH = 0.9 }
-- Saved settings whose default changed: applied once to existing saves.
local VERSION = 2
local MIGRATIONS = { [2] = { hover = true, classColor = false } }

local L = ns.L

-- Settings that are the game's own (CVars): our panel and wizard change them there, not in our save.
local GAME = { classIcons = { "ReplaceMyPlayerPortrait", "ReplaceOtherPlayerPortraits" } }

function ns.Get(key)
    local cvars = GAME[key]
    if not cvars then
        return ns.db[key]
    end
    for _, cvar in ipairs(cvars) do
        if not C_CVar.GetCVarBool(cvar) then
            return false
        end
    end
    return true
end

local function Store(key, value)
    local cvars = GAME[key]
    if not cvars then
        ns.db[key] = value
        return
    end
    for _, cvar in ipairs(cvars) do
        C_CVar.SetCVar(cvar, value and "1" or "0")
    end
end

---------------------------------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------------------------------
local function ValidColor(color)
    if type(color) ~= "table" then
        return false
    end
    for i = 1, 3 do
        if type(color[i]) ~= "number" or color[i] < 0 or color[i] > 1 then
            return false
        end
    end
    return true
end

local function Valid(key, value)
    if key == "darkColor" then
        return ValidColor(value)
    end
    if type(value) ~= type(DEFAULTS[key]) then
        return false
    end
    if not CHOICES[key] then
        return true
    end
    for _, choice in ipairs(CHOICES[key]) do
        if value == choice then
            return true
        end
    end
    return false
end

function ns.InitDB()
    RetailHDUnitFramesDB = type(RetailHDUnitFramesDB) == "table" and RetailHDUnitFramesDB or {}
    local db = RetailHDUnitFramesDB
    for version = (tonumber(db.version) or 1) + 1, VERSION do
        for key, value in pairs(MIGRATIONS[version] or {}) do
            db[key] = value
        end
    end
    db.version = VERSION
    if db.classIcons == true then -- an older save: our own option then, the game's setting now
        Store("classIcons", true)
    end
    for key in pairs(GAME) do
        db[key] = nil
    end
    for key, value in pairs(DEFAULTS) do
        if not GAME[key] and not Valid(key, db[key]) then
            db[key] = type(value) == "table" and { unpack(value) } or value
        end
    end
    ns.db = db
end

-- The dark mode tint of an intensity: a color (the chosen one by default) mixed into white
-- (nothing when off).
function ns.Tint(mode, color)
    local amount = INTENSITY[mode]
    color = color or ns.db.darkColor
    if amount then
        return 1 + (color[1] - 1) * amount, 1 + (color[2] - 1) * amount, 1 + (color[3] - 1) * amount
    end
end

function ns.UpdateTint()
    ns.SetTint(ns.Tint(ns.db.darkMode))
end

-- Dark mode in a picked color, not one of the intensity presets (which are plain black).
function ns.CustomColor()
    local color, black = ns.db.darkColor, DEFAULTS.darkColor
    return ns.db.darkMode ~= "OFF" and (color[1] ~= black[1] or color[2] ~= black[2] or color[3] ~= black[3])
end

-- How each setting applies, live.
local function Relayout()
    ns.RefreshAll(true)
end
local APPLY = {
    health = function()
        ns.UpdateTexts()
    end,
    power = function()
        ns.UpdateTexts()
    end,
    abbreviate = function()
        ns.UpdateTexts()
    end,
    hover = function()
        ns.UpdateTexts()
    end,
    level = Relayout,
    pvp = Relayout,
    classColor = function()
        ns.RefreshAll(false)
    end,
    lossAnimation = Relayout,
    classIcons = function()
        ns.UpdatePortraits()
    end,
    groupTab = Relayout,
    threat = Relayout,
    nameBackground = Relayout,
    minimapButton = function()
        ns.UpdateCompartment()
    end,
    -- An intensity is a preset, in plain black: choosing one drops a picked color.
    darkMode = function()
        ns.db.darkColor = { unpack(DEFAULTS.darkColor) }
        ns.UpdateTint()
    end,
}

local function Notify(key)
    if Settings and Settings.NotifyUpdate then
        Settings.NotifyUpdate("RHDUF_" .. key:upper())
    end
end

-- Changes a setting, applies it, and keeps the panel in step.
function ns.Set(key, value)
    Store(key, value)
    APPLY[key]()
    Notify(key)
end

-- Picking a color turns dark mode on (Medium) when it is off, at the current intensity otherwise;
-- cancelling restores both. after: called once the color changed (the wizard redraws).
function ns.PickColor(after)
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
        return
    end
    local db = ns.db
    local previousColor, previousMode = { unpack(db.darkColor) }, db.darkMode
    local function Use(color, mode)
        db.darkColor, db.darkMode = color, mode
        ns.UpdateTint()
        Notify("darkMode")
        if after then
            after()
        end
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = db.darkColor[1],
        g = db.darkColor[2],
        b = db.darkColor[3],
        hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            Use({ r, g, b }, db.darkMode == "OFF" and "MEDIUM" or db.darkMode)
        end,
        cancelFunc = function()
            Use(previousColor, previousMode)
        end,
    })
end

---------------------------------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------------------------------
local category

function ns.InitOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return
    end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Retail HD UnitFrames")

    local function Setting(key, varType)
        return Settings.RegisterProxySetting(category, "RHDUF_" .. key:upper(), varType, L[key], DEFAULTS[key],
            function()
                return ns.Get(key)
            end,
            function(value)
                Store(key, value)
                APPLY[key]()
            end)
    end
    -- example(choice): shown beside each choice's name.
    local function Dropdown(key, example)
        Settings.CreateDropdown(category, Setting(key, Settings.VarType.String), function()
            local container = Settings.CreateControlTextContainer()
            for _, choice in ipairs(CHOICES[key]) do
                local label = L[key .. choice] or L[choice]
                container:Add(choice, example and label .. "  (" .. example(choice) .. ")" or label)
            end
            return container:GetData()
        end, L[key .. "Tip"])
    end
    local function Checkbox(key)
        Settings.CreateCheckbox(category, Setting(key, Settings.VarType.Boolean), L[key .. "Tip"])
    end
    local function Button(name, text, tip, onClick)
        if CreateSettingsButtonInitializer and layout and layout.AddInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tip, true))
        end
    end

    -- The wizard opens over the panel (a higher strata); the panel follows its changes live.
    Button(L.wizardLaunch, L.wizardLaunchButton, L.wizardLaunchTip, function()
        ns.ShowWizard()
    end)
    Dropdown("health")
    Dropdown("power")
    Dropdown("abbreviate", function(style)
        return ns.Abbreviate(ns.EXAMPLE, style)
    end)
    Checkbox("hover")
    Dropdown("level")
    Dropdown("pvp")
    Checkbox("classIcons")
    Checkbox("classColor")
    Checkbox("lossAnimation")
    Checkbox("groupTab")
    Checkbox("threat")
    Checkbox("nameBackground")
    Dropdown("darkMode")
    Button(L.darkColor, L.darkColorButton, L.darkColorTip, function()
        ns.PickColor()
    end)
    Checkbox("minimapButton")
    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if category then
        Settings.OpenToCategory(category:GetID())
    end
end

---------------------------------------------------------------------------------------------------
-- Minimap: an entry in the minimap's addons menu (the addon compartment), with the addon's icon.
-- Left click opens the options, right click the wizard. The compartment has no way to remove an
-- entry: turning the option off takes our own entry back out of its list, live.
---------------------------------------------------------------------------------------------------
local entry

local function Entry()
    entry = entry or {
        text = "Retail HD UnitFrames",
        icon = "Interface\\AddOns\\RetailHDUnitFrames\\media\\icon",
        func = function(_, input)
            if input and input.buttonName == "RightButton" then
                ns.ShowWizard()
            else
                ns.OpenOptions()
            end
        end,
        funcOnEnter = function(button)
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            GameTooltip:SetText("Retail HD UnitFrames")
            GameTooltip:AddLine(L.minimapLeft, 1, 1, 1)
            GameTooltip:AddLine(L.minimapRight, 1, 1, 1)
            GameTooltip:Show()
        end,
        funcOnLeave = function()
            GameTooltip:Hide()
        end,
    }
    return entry
end

function ns.UpdateCompartment()
    local menu = AddonCompartmentFrame
    if not (menu and menu.RegisterAddon and type(menu.registeredAddons) == "table") then
        return
    end
    local list, index = menu.registeredAddons, nil
    for i, data in ipairs(list) do
        if data == entry then
            index = i
        end
    end
    if ns.db.minimapButton and not index then
        menu:RegisterAddon(Entry())
    elseif not ns.db.minimapButton and index then
        table.remove(list, index)
        if menu.UpdateDisplay then
            menu:UpdateDisplay()
        end
    end
end

-- /rhd opens the panel; /rhd wizard (or its translation) shows the first-run wizard again.
SLASH_RETAILHDUNITFRAMES1 = "/rhd"
SLASH_RETAILHDUNITFRAMES2 = "/retailhd"
SlashCmdList.RETAILHDUNITFRAMES = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "wizard" or command == L.wizardCommand then
        ns.ShowWizard()
    else
        ns.OpenOptions()
    end
end
