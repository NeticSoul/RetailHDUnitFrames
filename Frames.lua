--[[
    Retail HD UnitFrames - Frames
    Copyright (c) 2026 NeticSoul. Released under the MIT License (see LICENSE).

    DragonflightUI's HD art on Forever's own unit frames: player, pet, target, focus, their
    targets, and party. Player and target bars use the client's pre-70425 ("Beta") geometry, which
    drew this same art (as restored by SeamlessUnitframes, MIT); the small frames' bars, the
    portraits and the glows sit where they were measured on the HD art itself; masks, PvP icon
    and elite dragon follow DragonflightUI; layering and the health-loss bar follow Midnight's own
    frames. Optional pieces: class icons for portraits, the group tab, threat and name background.
]]
local ADDON, ns = ...
local Paint, Fill, Place, Text, Readable = ns.Paint, ns.Fill, ns.Place, ns.Text, ns.Readable
local BAR, PVP_ATLAS = ns.BAR, ns.PVP_ATLAS

local POWER = { MANA = "mana", RAGE = "rage", ENERGY = "energy", FOCUS = "focus" }
local PREDICTION = { "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar" }
local NATIVE_OVERLAYS = { "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar",
    "OverAbsorbGlow", "OverHealAbsorbGlow" }
local DECORATION = { worldboss = "boss", elite = "elite", rareelite = "rare", rare = "rare" }
local DECORATION_X = { boss = 13, elite = 4, rare = 4 } -- from the portrait center, as DragonflightUI
-- How far the small frames' health bars run past the art's window (70 wide) on the left, over its
-- dark left edge by the ring: three units on the target's targets, one on party and pet.
local TOT_EXTEND, SMALL_EXTEND = 3, 1
-- Forever's party bars (its ArtLayoutInfo: health 47,-20 and 70 wide, mana 44,-31) sit this far
-- from the HD art's windows with the art where Midnight puts it, at 1,-2 (measured: health from
-- 44,-18.5 with the extra unit on the left, mana from 41,-29.5).
local PARTY_SHIFT_X, PARTY_SHIFT_Y = 3, -1.5
-- The small frames' mana mask, from the mana bar's corner: it ends half a unit above the window's
-- bottom line, the margin the player's bars have, so the bar's soft edge never reaches the line.
local SMALL_MANA_MASK_X, SMALL_MANA_MASK_Y = -27, 4.5

local owners = {} -- [power bar] = its unit frame

---------------------------------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------------------------------
local function UnitOf(frame)
    local unit = frame.unit
    return Readable(unit) and type(unit) == "string" and unit or nil
end

local function BarsLevel(health, mana)
    return math.max(health:GetFrameLevel(), mana:GetFrameLevel())
end

local function ClassColor(unit)
    if not ns.db.classColor or not unit then
        return
    end
    local online = UnitIsConnected(unit)
    if Readable(online) and not online then
        return -- offline: plain, so the client's grey shows
    end
    local isPlayer = UnitIsPlayer(unit)
    if not Readable(isPlayer) or not isPlayer then
        return
    end
    local _, class = UnitClass(unit)
    return Readable(class) and RAID_CLASS_COLORS[class]
end

local function Health(bar, family, unit)
    local color = ClassColor(unit)
    Fill(bar, BAR .. family .. (color and "-health-status" or "-health"))
    if color then
        bar:SetStatusBarColor(color.r, color.g, color.b)
    else
        bar:SetStatusBarColor(1, 1, 1)
    end
end

local function Power(bar, family, frame, unit)
    owners[bar] = frame
    if not unit then
        return
    end
    local _, token = UnitPowerType(unit)
    if Readable(token) then
        Fill(bar, BAR .. family .. "-" .. (POWER[token] or "mana-status"))
    end
end

-- Heal prediction and absorb overlays stretch one fill over the bar; give them the white fill.
local function PredictionFills(bar, family)
    for _, key in ipairs(PREDICTION) do
        local segment = bar[key]
        if segment and segment.Fill then
            Paint(segment.Fill, BAR .. family .. "-health-status")
        end
    end
end

-- The frame art, also on the client's vehicle and class-resource variants: one look in every state.
local function Art(art, key, ...)
    Paint(art, key, true)
    ns.Darken(art, ...)
    for i = 1, select("#", ...) do
        local variant = select(i, ...)
        if variant then
            Paint(variant, key, true)
            Place(variant, "CENTER", art, "CENTER", 0, 0)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Class icons instead of players' portraits: Forever's own setting (its two CVars, also in its
-- Interface options), turned on and off from our panel and wizard. The client draws the icons.
---------------------------------------------------------------------------------------------------
local portraitFrames = {} -- the unit frames whose portraits we placed

-- The game's setting changed from here: every portrait drawn again by the client's own update
-- (Forever redraws them through its settings panel, which may not see a change made elsewhere).
function ns.UpdatePortraits()
    if type(UnitFramePortrait_Update) ~= "function" then
        return
    end
    for frame in pairs(portraitFrames) do
        if frame.portrait and UnitOf(frame) then
            UnitFramePortrait_Update(frame)
        end
    end
end

-- The portrait fills the transparent hole of the HD ring: centered on it (offsets measured on the
-- art, from its center), sized to cover it as DragonflightUI does, its masks with it, and drawn
-- under the art (Forever draws it above). Forever's own position was made for its c60 art.
local function Portrait(frame, portrait, art, x, y, size)
    if not portrait or not art then
        return
    end
    portraitFrames[frame] = true
    Place(portrait, "CENTER", art, "CENTER", x, y, size, size)
    local count = portrait.GetNumMaskTextures and portrait:GetNumMaskTextures()
    for i = 1, Readable(count) and count or 0 do
        Place(portrait:GetMaskTexture(i), "CENTER", portrait, "CENTER", 0, 0, size, size)
    end
    if ns.Movable(art) then
        portrait:SetDrawLayer("BACKGROUND", 7)
        art:SetDrawLayer("BORDER", 7)
    end
end

-- The target's threat percentage, turned off: hidden for real, not parked, so the client sees it
-- hidden and lays the auras out without its room (its show and hide scripts move them).
local threatHooked = {}

local function ThreatPercent(indicator)
    if not indicator then
        return
    end
    ns.Unhide(indicator) -- parked by an earlier version
    if not threatHooked[indicator] then
        threatHooked[indicator] = true
        indicator:HookScript("OnShow", function(self)
            if not ns.db.threat and ns.Movable(self) then
                self:Hide()
            end
        end)
    end
    local shown = indicator:IsShown()
    if not ns.db.threat and Readable(shown) and shown and ns.Movable(indicator) then
        indicator:Hide()
    end
end

-- A piece of the client kept or parked hidden by a setting, live. Parked, the client still shows
-- and hides it as before: it just cannot be seen.
local function Shown(region, shown)
    if shown then
        ns.Unhide(region)
    else
        ns.Hide(region)
    end
end

-- region gives way (alpha 0) while other shows. Only its alpha: the client keeps showing and
-- hiding both as it likes, so nothing breaks if the client changes how it uses them.
local givingWay = {}

local function GiveWay(region, other)
    if not region or not other or givingWay[region] then
        return
    end
    givingWay[region] = true
    local function Sync()
        local shown = other:IsShown()
        if Readable(shown) then
            region:SetAlpha(shown and 0 or 1)
        end
    end
    hooksecurefunc(other, "Show", Sync)
    hooksecurefunc(other, "Hide", Sync)
    hooksecurefunc(other, "SetShown", Sync)
    Sync()
end

---------------------------------------------------------------------------------------------------
-- Level. "RETAIL": small text beside the name, Forever's level circle hidden. "FOREVER": the
-- client's circle, number and skull, as the client places them. "HIDDEN": no level at all. Names
-- are centered unless RETAIL. All apply live: hidden regions only change parent, the number and
-- skull get their anchors and font back. SetFont, not SetFontObject, so the difficulty color stays.
---------------------------------------------------------------------------------------------------
local fonts = {}

local function RetailLevel()
    return ns.db.level == "RETAIL"
end

local function ShownLevel()
    return ns.db.level ~= "HIDDEN"
end

local function Level(text, circle, skull, ...)
    if not text then
        return
    end
    -- Forever shows the skull but can leave the last unit's level number under it.
    GiveWay(text, skull)
    if not ShownLevel() then
        ns.Hide(text)
        ns.Hide(circle)
        ns.Hide(skull)
        return
    end
    ns.Unhide(text)
    ns.Unhide(skull)
    if RetailLevel() then
        ns.Hide(circle)
        if ns.Movable(text) then
            if fonts[text] == nil then -- the client's font, once (false: unreadable)
                local font, size, flags = text:GetFont()
                fonts[text] = Readable(font) and Readable(size) and { font, size, flags or "" } or false
            end
            text:SetFont(GameFontNormalSmall:GetFont())
        end
        Place(text, ...)
        Paint(skull, "skull", true)
        Place(skull, "LEFT", text, "LEFT", 0, 0) -- where the number starts (it is empty then)
    else
        ns.Unhide(circle)
        ns.Release(text)
        ns.Unpaint(skull)
        ns.Release(skull)
        if fonts[text] and ns.Movable(text) then
            text:SetFont(unpack(fonts[text]))
            fonts[text] = nil
        end
    end
end

---------------------------------------------------------------------------------------------------
-- PvP icon. "RETAIL": Midnight's own HD icons (chosen as Midnight's UnitFrameUtil does) where
-- DragonflightUI shows them: on the ring, mirrored between player and target. Offsets are from
-- the portrait's center (the ring's), calibrated on in-game screenshots so both emblems are
-- vertically centered on their ring and cover 2px of their portrait. A texture of ours, free to
-- change in combat. "FOREVER": the client's badge, untouched. "HIDDEN": none. A unit whose PvP
-- state is secret shows no icon rather than a guess.
---------------------------------------------------------------------------------------------------
local pvpIcons, pvpAtlas = {}, {}

local function PvPAtlas(unit)
    local ffa = UnitIsPVPFreeForAll(unit)
    if not Readable(ffa) then
        return
    end
    if ffa then
        return PVP_ATLAS:format("FFA")
    end
    local flagged, faction = UnitIsPVP(unit), UnitFactionGroup(unit)
    if Readable(flagged) and flagged and Readable(faction) and (faction == "Alliance" or faction == "Horde") then
        return PVP_ATLAS:format(faction)
    end
end

local function UpdatePvP(frame)
    local icon = pvpIcons[frame]
    if not icon then
        return
    end
    local unit = UnitOf(frame)
    local atlas = ns.db.pvp == "RETAIL" and unit and PvPAtlas(unit)
    if atlas and C_Texture.GetAtlasInfo(atlas) then
        if pvpAtlas[icon] ~= atlas then
            pvpAtlas[icon] = atlas
            icon:SetAtlas(atlas, true)
        end
        icon:Show()
    else
        icon:Hide()
    end
end

function ns.UpdatePvP()
    for frame in pairs(pvpIcons) do
        UpdatePvP(frame)
    end
end

-- native: the client's badge; x, y: the icon's center from the portrait's center.
local function PvP(frame, level, native, portrait, x, y, timer)
    local style = ns.db.pvp
    if style == "RETAIL" then
        local icon = pvpIcons[frame]
        if not icon and portrait and not InCombatLockdown() then
            icon = frame:CreateTexture(nil, "OVERLAY")
            pvpIcons[frame] = icon
        end
        Place(icon, "CENTER", portrait, "CENTER", x, y)
        ns.Layer(frame, level, 3, icon) -- with the client's icons, as in Midnight: over the level
        Place(timer, "TOP", icon, "BOTTOM", 0, 2)
    else
        ns.Release(timer)
    end
    if style == "FOREVER" then
        ns.Unhide(native)
    else
        ns.Hide(native)
    end
    UpdatePvP(frame)
end

---------------------------------------------------------------------------------------------------
-- The player's gold corner piece on the ring (it also closes the tip of the portrait hole).
-- Like retail, it gives way to Forever's crossed swords while those show in combat.
---------------------------------------------------------------------------------------------------
local corner

local function Corner(frame, art, attack, level)
    if not corner then
        if InCombatLockdown() then
            return
        end
        corner = art:CreateTexture(nil, "OVERLAY")
        GiveWay(corner, attack)
    end
    Paint(corner, "playerCorner", true)
    ns.Darken(corner)
    Place(corner, "CENTER", art.FrameTexture, "CENTER", -46.5, -15.5)
    ns.Layer(frame, level, 2, corner)
end

---------------------------------------------------------------------------------------------------
-- Player. In a vehicle the client switches to its vehicle art and the vehicle's unit: the frame
-- keeps this same look and shows the vehicle's health and power.
---------------------------------------------------------------------------------------------------
local function Player(frame, full)
    local art, content = frame.PlayerFrameContainer, frame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local bars = main and main.HealthBarsContainer
    local health = bars and bars.HealthBar
    local mana = main and main.ManaBarArea and main.ManaBarArea.ManaBar
    if not (art and health and mana) then
        return
    end
    local unit = UnitOf(frame)
    Health(health, "player", unit)
    Power(mana, "player", frame, unit)
    UpdatePvP(frame)
    if not full then
        return
    end
    local contextual = content.PlayerFrameContentContextual

    Art(art.FrameTexture, "player", art.VehicleFrameTexture, art.AlternatePowerFrameTexture)
    ns.Darken(main.LevelBackgroundCircle)
    Paint(art.PlayerPortraitMask, "playerPortraitMask", true)
    Paint(art.FrameFlash, "playerFlash", true)
    Paint(main.StatusTexture, "playerStatus", true)
    Paint(bars.HealthBarMask, "playerHealthMask", true)
    Paint(mana.ManaBarMask, "playerManaMask", true)
    PredictionFills(health, "player")
    -- Midnight's red health-loss bar: its health fill tinted red, under the health bar (its fill
    -- keeps the client's draw layer), so only the part just lost shows, sliding out. The client
    -- only shows, hides and fills it, never fades it: the option turns it off through its alpha.
    local loss = bars.PlayerFrameHealthBarAnimatedLoss
    if loss then
        Fill(loss, BAR .. "player-health")
        loss:SetStatusBarColor(1, 0, 0)
        loss:SetAlpha(ns.db.lossAnimation and 1 or 0)
    end

    Place(bars, "TOPLEFT", main, "TOPLEFT", 85, -41, 124, 19)
    Place(health, "TOPLEFT", bars, "TOPLEFT", 0, 0, 124, 19)
    Place(bars.HealthBarMask, "TOPLEFT", health, "TOPLEFT", -2, 6, 128, 32)
    Place(mana, "TOPLEFT", main.ManaBarArea, "TOPLEFT", 85, -61, 124, 10)
    Place(mana.ManaBarMask, "TOPLEFT", mana, "TOPLEFT", -2, 2, 128, 16)
    Portrait(frame, art.PlayerPortrait, art.FrameTexture, -61.5, 0, 60)
    -- Glows on the art itself, where their lines meet the art's (offsets measured on the textures).
    Place(art.FrameFlash, "CENTER", art.FrameTexture, "CENTER", -2, 1)
    Place(main.StatusTexture, "CENTER", art.FrameTexture, "CENTER", -1.5, 1)
    if RetailLevel() then
        Place(PlayerName, "LEFT", main, "TOPLEFT", 88, -33, 96, nil, "LEFT")
    else
        Place(PlayerName, "BOTTOM", health, "TOP", 0, 2, 116, nil, "CENTER")
    end
    -- Name and level on one line, by their middles (8 above the health bar), whatever their heights.
    Level(PlayerLevelText, main.LevelBackgroundCircle, nil, "RIGHT", main, "TOPLEFT", 204, -33, nil, nil, "RIGHT")
    if contextual and contextual.AttackIcon and ns.Movable(contextual.AttackIcon) then
        contextual.AttackIcon:SetDrawLayer("OVERLAY", 2)
    end

    local level = BarsLevel(health, mana)
    PvP(frame, level, main.PvpBackgroundIcon, art.PlayerPortrait, -30.8, 0, PlayerPVPTimerText)
    ns.Layer(frame, level, 1, art.FrameFlash, main.StatusTexture)
    ns.Layer(frame, level, 2, ns.db.pvp == "FOREVER" and main.PvpBackgroundIcon or nil, PlayerPVPTimerText,
        PlayerName, ShownLevel() and PlayerLevelText or nil,
        ns.db.level == "FOREVER" and main.LevelBackgroundCircle or nil)
    ns.Layer(frame, level, 3, contextual) -- attack, leader, rest and group icons
    ns.Layer(frame, level, 4, main.HitIndicator) -- damage and healing numbers on the portrait
    Corner(frame, art, contextual and contextual.AttackIcon, level)
    ns.Hide(contextual and contextual.PlayerPortraitCornerIcon) -- Forever's own (other art), under ours
    Shown(contextual and contextual.GroupIndicator, ns.db.groupTab) -- the raid group tab

    Text(frame, health, "health", health)
    Text(frame, mana, "power", mana)
end

---------------------------------------------------------------------------------------------------
-- Target and focus. Their health bar is secure and the client may resize it in combat, where we
-- cannot undo it, so an ordinary bar of ours draws the health, mirrored from the native one.
---------------------------------------------------------------------------------------------------
local visuals = {}
local TARGET_HEALTH_WIDTH = 126.5

-- Heal prediction and absorbs on that bar of ours, as the client draws them on the player's: its
-- colors on our HD fill, the raid frames' shield and absorb art, the glows when they overflow.
-- As SeamlessUnitframes (MIT): the client's calculator applies its own clamps (heals and absorbs
-- stay inside the bar, heals and heal absorbs cancel out), and each value it gives, secret or
-- not, goes straight to a bar; nothing is read or combined here. Each bar starts where the one
-- before ends and is as wide as the health bar; the health mask clips them like the fill.
local PREDICTION_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }

local function PredictionColor(name, r, g, b)
    local color = _G[name]
    if Readable(color) and type(color) == "table" and type(color.GetRGB) == "function" then
        return color:GetRGB()
    end
    return r, g, b
end

local function ClampMode(calculator, setter, enum, value)
    if Enum[enum] and Enum[enum][value] ~= nil and type(calculator[setter]) == "function" then
        calculator[setter](calculator, Enum[enum][value])
    end
end

local function PredictionBar(visual, texture, reverse, r, g, b)
    local bar = CreateFrame("StatusBar", nil, visual)
    bar:SetStatusBarTexture(texture)
    bar:SetStatusBarColor(r, g, b)
    bar:GetStatusBarTexture():AddMaskTexture(visual.mask)
    ns.Exact(bar:GetStatusBarTexture())
    if reverse then
        bar:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function PredictionGlow(owner, visual, file, side, x)
    local glow = owner:CreateTexture(nil, "OVERLAY") -- on a prediction bar: above every fill
    glow:SetTexture(file)
    glow:SetBlendMode("ADD")
    glow:AddMaskTexture(visual.mask)
    glow:SetWidth(16)
    local other = side == "RIGHT" and "LEFT" or "RIGHT"
    glow:SetPoint("TOP" .. other, visual, "TOP" .. side, x, 0)
    glow:SetPoint("BOTTOM" .. other, visual, "BOTTOM" .. side, x, 0)
    glow:SetAlpha(0)
    return glow
end

local function Chain(bar, previous, reverse) -- from the previous fill's end, the health bar's width
    local from = reverse and "RIGHT" or "LEFT"
    bar:ClearAllPoints()
    bar:SetPoint("TOP" .. from, previous, "TOPRIGHT")
    bar:SetPoint("BOTTOM" .. from, previous, "BOTTOMRIGHT")
    bar:SetWidth(TARGET_HEALTH_WIDTH)
end

local function UpdatePrediction(frame)
    local visual = visuals[frame]
    local prediction = visual and visual.prediction
    local unit = UnitOf(frame)
    if not prediction or not unit then
        return
    end
    local fill = visual:GetStatusBarTexture()
    if fill ~= prediction.fill then -- the fill the chain hangs on
        prediction.fill = fill
        Chain(prediction.mine, fill)
        Chain(prediction.healAbsorb, fill, true)
    end
    local calculator = prediction.calculator
    UnitGetDetailedHealPrediction(unit, "player", calculator)
    local maximum = calculator:GetMaximumHealth()
    local _, mine, others = calculator:GetIncomingHeals()
    local absorb, overAbsorb = calculator:GetDamageAbsorbs()
    local healAbsorb, overHealAbsorb = calculator:GetHealAbsorbs()
    for _, pair in ipairs({ { prediction.mine, mine }, { prediction.others, others }, { prediction.absorb, absorb },
        { prediction.healAbsorb, healAbsorb } }) do
        pair[1]:SetMinMaxValues(0, maximum)
        pair[1]:SetValue(pair[2])
    end
    prediction.overAbsorb:SetAlphaFromBoolean(overAbsorb, 1, 0)
    prediction.overHealAbsorb:SetAlphaFromBoolean(overHealAbsorb, 1, 0)
end

local predictionEvents

local function Prediction(visual)
    if type(CreateUnitHealPredictionCalculator) ~= "function" or type(UnitGetDetailedHealPrediction) ~= "function" then
        return
    end
    local calculator = CreateUnitHealPredictionCalculator()
    ClampMode(calculator, "SetIncomingHealClampMode", "UnitIncomingHealClampMode", "MissingHealth")
    ClampMode(calculator, "SetDamageAbsorbClampMode", "UnitDamageAbsorbClampMode", "MissingHealth")
    ClampMode(calculator, "SetHealAbsorbClampMode", "UnitHealAbsorbClampMode", "CurrentHealth")
    ClampMode(calculator, "SetHealAbsorbMode", "UnitHealAbsorbMode", "ReducedByIncomingHeals")
    if type(calculator.SetIncomingHealOverflowPercent) == "function" then
        calculator:SetIncomingHealOverflowPercent(1)
    end
    local fill = BAR .. "target-health-status"
    local prediction = { calculator = calculator }
    -- (the color last: a call's three values only spread as the last argument)
    prediction.mine = PredictionBar(visual, fill, false, PredictionColor("HEALTHBAR_MY_HEAL_PREDICTION_COLOR", 0, 0.83, 0.77))
    prediction.others = PredictionBar(visual, fill, false,
        PredictionColor("HEALTHBAR_OTHER_HEAL_PREDICTION_COLOR", 0, 0.63, 0.56))
    prediction.absorb = PredictionBar(visual, "Interface\\RaidFrame\\Shield-Fill", false,
        PredictionColor("HEALTHBAR_TOTAL_ABSORB_COLOR", 1, 1, 1))
    prediction.healAbsorb = PredictionBar(visual, "Interface\\RaidFrame\\Absorb-Fill", true, -- eats health from its end
        PredictionColor("HEALTHBAR_HEAL_ABSORB_COLOR", 1, 1, 1))
    Chain(prediction.others, prediction.mine:GetStatusBarTexture())
    Chain(prediction.absorb, prediction.others:GetStatusBarTexture())
    prediction.overAbsorb = PredictionGlow(prediction.absorb, visual, "Interface\\RaidFrame\\Shield-Overshield", "RIGHT", -7)
    prediction.overHealAbsorb = PredictionGlow(prediction.healAbsorb, visual, "Interface\\RaidFrame\\Absorb-Overabsorb",
        "LEFT", 7)
    visual.prediction = prediction
    if not predictionEvents then
        predictionEvents = CreateFrame("Frame")
        for _, event in ipairs(PREDICTION_EVENTS) do
            predictionEvents:RegisterUnitEvent(event, "target", "focus")
        end
        predictionEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        predictionEvents:RegisterEvent("PLAYER_FOCUS_CHANGED")
        predictionEvents:SetScript("OnEvent", function()
            for frame in pairs(visuals) do
                UpdatePrediction(frame)
            end
        end)
    end
end

local function Visual(frame, main, source)
    local visual = visuals[frame]
    if not visual then
        if InCombatLockdown() then
            return
        end
        visual = CreateFrame("StatusBar", nil, main)
        visual:SetStatusBarTexture(BAR .. "target-health")
        local mask = visual:CreateMaskTexture()
        local data = ns.media.targetHealthMask
        mask:SetTexture(data[1])
        mask:SetSize(data[2], data[3])
        mask:SetPoint("TOPLEFT", visual, "TOPLEFT", -1, 6)
        visual:GetStatusBarTexture():AddMaskTexture(mask)
        visual.mask = mask
        hooksecurefunc(source, "SetMinMaxValues", function(_, low, high)
            visual:SetMinMaxValues(low, high)
        end)
        hooksecurefunc(source, "SetValue", function(_, value)
            visual:SetValue(value)
        end)
        visual:SetMinMaxValues(source:GetMinMaxValues())
        visual:SetValue(source:GetValue())
        visuals[frame] = visual
        Prediction(visual)
    end
    local fill = source:GetStatusBarTexture()
    if fill then
        fill:SetAlpha(0)
    end
    for _, key in ipairs(NATIVE_OVERLAYS) do
        if source[key] then
            source[key]:SetAlpha(0)
        end
    end
    return visual
end

local TEXT_Y = 1 -- target and focus name and level, from the strip's middle

local function Target(frame, full)
    local art, content = frame.TargetFrameContainer, frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local bars = main and main.HealthBarsContainer
    local health, mana = bars and bars.HealthBar, main and main.ManaBar
    if not (art and health and mana) then
        return
    end
    local unit = UnitOf(frame)
    local visual = Visual(frame, main, health)
    Health(visual or health, "target", unit)
    Power(mana, "target", frame, unit)
    UpdatePvP(frame)
    if not full then
        return
    end
    local contextual = content.TargetFrameContentContextual
    local shown = visual or health

    Art(art.FrameTexture, "target")
    ns.Darken(art.BossPortraitFrameTexture, main.LevelBackgroundCircle)
    Paint(art.Flash, "targetFlash", true)
    Paint(main.ReputationColor, "targetType", true)
    Paint(mana.ManaBarMask, "targetManaMask", true)
    local boss = unit and UnitIsBossMob(unit)
    local class = unit and UnitClassification(unit)
    local decoration = (Readable(boss) and boss and "boss") or (Readable(class) and DECORATION[class])
    if decoration then
        Paint(art.BossPortraitFrameTexture, decoration, true)
        Place(art.BossPortraitFrameTexture, "CENTER", art.Portrait, "CENTER", DECORATION_X[decoration], 1)
    end

    -- Pixel-fitted on the HD art: each bar fills its window exactly, from the left border to the
    -- ring (half a unit wider on the left than the Beta geometry; the mana mask one unit wider on
    -- the left, its cut at the ring unchanged). Measured at the art's 2x resolution.
    local width = TARGET_HEALTH_WIDTH
    Place(bars, "BOTTOMRIGHT", art, "LEFT", 149, -10, width, 20)
    Place(health, "TOPLEFT", bars, "TOPLEFT", 0, 0, width, 20)
    Place(bars.TempMaxHealthLoss, "TOPLEFT", bars, "TOPLEFT", 0, 0, width, 20)
    Place(visual, "BOTTOMRIGHT", art, "LEFT", 149, -10, width, 20)
    Place(mana, "TOPRIGHT", art, "LEFT", 157, -11, 134.5, 10)
    Place(mana.ManaBarMask, "TOPLEFT", mana, "TOPLEFT", -62.5, 3, 260, 16) -- cuts the bar's end at the ring
    Portrait(frame, art.Portrait, art.FrameTexture, 61.75, 1.25, 56)
    Place(art.Flash, "CENTER", art.FrameTexture, "CENTER", 0.25, 1.5) -- on the art: lines on lines (measured)
    ns.Exact(art.FrameTexture, art.Flash, mana.ManaBarMask) -- not rounded apart to the pixel grid
    Place(main.ReputationColor, "TOPRIGHT", main, "TOPRIGHT", -75, -25)
    if ns.Movable(main.ReputationColor) then -- the colored strip behind the name: alpha only, the
        main.ReputationColor:SetAlpha(ns.db.nameBackground and 1 or 0) -- name and level hang on it
    end
    -- Name and level 1 above the strip's middle: at the player's height (17 above both frames'
    -- middles, the same 232x100 frame), so side by side they line up.
    if RetailLevel() then
        Place(main.Name, "RIGHT", main.ReputationColor, "RIGHT", -6, TEXT_Y, 100, nil, "CENTER")
    else
        Place(main.Name, "CENTER", main.ReputationColor, "CENTER", 0, TEXT_Y, 125, nil, "CENTER")
    end
    Level(main.LevelText, main.LevelBackgroundCircle, contextual and contextual.HighLevelTexture, "LEFT",
        main.ReputationColor, "LEFT", 6, TEXT_Y, nil, nil, "LEFT")
    Place(bars.DeadText, "CENTER", shown, "CENTER", 0, 0)
    if bars.DeadText then -- our health text says it (dead, ghost, offline), as on every frame
        bars.DeadText:SetAlpha(0)
    end
    Place(bars.UnconsciousText, "CENTER", shown, "CENTER", 0, 0)
    local combo = frame == TargetFrame and ComboFrame or nil
    Place(combo, "CENTER", art.Portrait, "CENTER", 0, 2) -- combo points on the portrait (Forever's Beta)

    local level = BarsLevel(health, mana)
    PvP(frame, level, contextual and contextual.PvpBackgroundIcon, art.Portrait, 32.2, 2)
    ns.Layer(frame, level, 1, art.Flash)
    ns.Layer(frame, level, 2, art.BossPortraitFrameTexture, main.Name, ShownLevel() and main.LevelText or nil,
        ns.db.level == "FOREVER" and main.LevelBackgroundCircle or nil, bars.DeadText, bars.UnconsciousText)
    ns.Layer(frame, level, 3, contextual, combo) -- skull, raid icon and combo points
    ThreatPercent(frame.threatNumericIndicator) -- the threat percentage above the name

    local small = frame.smallSize -- Edit Mode's small focus: the client enlarges its own text
    local font = Readable(small) and small and "TextStatusBarTextLarge" or nil
    Text(frame, health, "health", shown, nil, nil, font)
    Text(frame, mana, "power", mana, 8, nil, font) -- the bar runs 8px past the health bar, under the ring
    UpdatePrediction(frame)
end

---------------------------------------------------------------------------------------------------
-- Target of target, target of focus and pet: one small art.
---------------------------------------------------------------------------------------------------
local function Small(frame, full)
    local pet = frame == PetFrame
    local health = pet and PetFrameHealthBar or frame.HealthBar
    local mana = pet and PetFrameManaBar or frame.ManaBar
    if not (health and mana) then
        return
    end
    local unit = UnitOf(frame)
    Health(health, "small", unit)
    Power(mana, "small", frame, unit)
    if not full then
        return
    end
    local border = pet and PetFrameTexture or frame.FrameTexture
    local portrait = pet and PetPortrait or frame.Portrait
    local healthMask = pet and PetFrameHealthBarMask or health.HealthBarMask

    local manaMask = pet and PetFrameManaBarMask or mana.ManaBarMask
    Art(border, "small")
    Paint(healthMask, "smallHealthMask", true)
    Paint(manaMask, "smallManaMask", true)
    Portrait(frame, portrait, border, -34.75, 1.25, 37)
    if portrait then
        Place(pet and PetName or frame.Name, "TOPLEFT", portrait, "TOPRIGHT", 2, 0, 68, nil, "LEFT")
    end
    if pet then
        Paint(PetFrameFlash, "smallFlash", true)
        Paint(PetAttackModeTexture, "smallStatus", true)
        Place(PetAttackModeTexture, "CENTER", border, "CENTER", 0, 1) -- glows on the art (measured)
        Place(PetFrameFlash, "CENTER", border, "CENTER", -1.5, 1.5)
    else
        Place(border, "CENTER", frame, "CENTER", 0, 0) -- the art centered on its frame, as in Midnight
    end
    -- The bars fill the art's windows (measured on the HD art, from its center: health 70x10 at
    -- 19,3, here longer on the left so it covers the window's dark left edge by the ring; mana 74x7
    -- under it); masks as DragonflightUI, where they were. The target's targets hang them on the
    -- frame, not on the art: Forever may hang its art on the health bar, and a loop of anchors
    -- would leave both bars without a place.
    local extend = pet and SMALL_EXTEND or TOT_EXTEND
    Place(health, "CENTER", pet and border or frame, "CENTER", 19 - extend / 2, 3, 70 + extend, 10)
    Place(healthMask, "TOPLEFT", health, "TOPLEFT", extend - 29, 3)
    Place(mana, "TOPLEFT", health, "BOTTOMLEFT", extend - 4, -1, 74, 7)
    Place(manaMask, "TOPLEFT", mana, "TOPLEFT", SMALL_MANA_MASK_X, SMALL_MANA_MASK_Y)
    ns.Exact(border, healthMask, manaMask, pet and PetFrameFlash, pet and PetAttackModeTexture)

    if pet then
        local level = BarsLevel(health, mana)
        ns.Layer(frame, level, 1, PetFrameFlash, PetAttackModeTexture)
        ns.Layer(frame, level, 2, PetName)
        ns.Layer(frame, level, 3, PetFrameHappiness)
        ns.Layer(frame, level, 4, PetHitIndicator)
        Text(frame, health, "health", health)
        Text(frame, mana, "power", mana, nil, 4 - SMALL_EXTEND) -- the mana bar starts further left
    end
end

---------------------------------------------------------------------------------------------------
-- Party members (pooled frames). The character style keeps this same look; in a vehicle a member
-- gets Forever's own frame (see ForeverVehicle).
---------------------------------------------------------------------------------------------------
-- The party's PvP icon: the client's own (Midnight's icons, drawn at a smaller scale). "RETAIL":
-- beside the portrait as on the player, its offset scaled to the 37px portrait (-30.8 at 60px) and
-- divided by the icon's own scale; "FOREVER": where the client puts it (shifted with the HD art);
-- "HIDDEN": parked.
local PARTY_PVP_X = -30.8 * 37 / 60

local function PartyPvP(icon, portrait, overlay, shifted)
    if not icon or not portrait then
        return
    end
    local style = ns.db.pvp
    if style == "HIDDEN" then
        ns.Hide(icon)
        return
    end
    ns.Unhide(icon)
    if style == "RETAIL" then
        local scale = icon.GetScale and icon:GetScale()
        scale = Readable(scale) and type(scale) == "number" and scale > 0 and scale or 1
        Place(icon, "CENTER", portrait, "CENTER", PARTY_PVP_X / scale, 0)
    elseif shifted then
        Place(icon, "CENTER", overlay, "TOPLEFT", 24 + PARTY_SHIFT_X, -68 + PARTY_SHIFT_Y) -- its template's place
    else
        ns.Release(icon)
    end
end

-- The overlay's icons at their template's places (point, relative point, x, y), to shift with the art.
local OVERLAY_ICONS = {
    LeaderIcon = { "BOTTOM", "TOP", -10, -6 },
    GuideIcon = { "BOTTOM", "TOP", -10, -6 },
    Disconnect = { "LEFT", "LEFT", -7, -1 },
    RoleIcon = { "TOPRIGHT", "TOPRIGHT", -5, -5 },
}

-- Party aggro. Forever (as Midnight) hands each party frame's Flash to the client as its threat
-- indicator, but never gives it a unit nor the threat event, so it never lights up. The red some
-- times seen there is the debuff glow (red: a debuff of no type), which the client does run. So
-- this is our own glow, the same art in the same place, leaving the client's untouched: the
-- member's threat on any mob, in the client's colors (yellow, orange, red). The game only knows
-- the threat of mobs the player fights too, and no addon may ask whom a mob targets (UnitIsUnit
-- only compares a unit with the player or the target): a member's aggro shows once you are in
-- that fight. A secret status (restricted maps) is skipped.
local aggro = {} -- [party frame] = its aggro glow

local function UpdateAggro()
    for frame, glow in pairs(aggro) do
        local unit, status = UnitOf(frame), nil
        local visible = frame:IsVisible()
        if unit and Readable(visible) and visible and IsThreatWarningEnabled() then
            status = UnitThreatSituation(unit)
        end
        if Readable(status) and status and status > 0 then
            glow:SetVertexColor(GetThreatStatusColor(status))
            glow:Show()
        else
            glow:Hide()
        end
    end
end
C_Timer.NewTicker(0.2, UpdateAggro)

local function AggroGlow(frame)
    local glow = aggro[frame]
    if not glow then
        glow = frame:CreateTexture(nil, "ARTWORK", nil, 2) -- over the debuff glow
        glow:Hide()
        aggro[frame] = glow
    end
    return glow
end

-- Forever puts the bars back at its own places on every group update, in combat too, when they
-- cannot be moved. So the bars stay there and the art moves instead, with what sits on it (the
-- overlay's icons, the name, the glows): Midnight's places, where the art was measured, shifted by
-- Forever's. The bars land exactly in its windows (health 16.5 under the art's top; one unit longer
-- on the left, as on the target's targets) in and out of combat. The glows hang by their corner, as
-- Forever hangs them: its anchor then replaces ours, never adds to it.
local function HDParty(frame, bars, health, mana, overlay, glow)
    local x, y = PARTY_SHIFT_X, PARTY_SHIFT_Y
    Art(frame.Texture, "small", frame.VehicleTexture)
    Portrait(frame, frame.Portrait, frame.Texture, -34.75, 1.25, 37)
    Paint(frame.Flash, "smallFlash", true)
    Paint(overlay.Status, "smallStatus", true)
    Paint(glow, "smallFlash", true)
    Paint(bars.HealthBarMask, "smallHealthMask", true)
    Paint(mana.ManaBarMask, "smallManaMask", true)

    Place(frame.Texture, "TOPLEFT", frame, "TOPLEFT", 1 + x, -2 + y)
    Place(frame.Name, "TOPLEFT", frame, "TOPLEFT", 46 + x, -6 + y, 57)
    for key, p in pairs(OVERLAY_ICONS) do
        Place(overlay[key], p[1], overlay, p[2], p[3] + x, p[4] + y)
    end
    PartyPvP(overlay.PVPIcon, frame.Portrait, overlay, true)
    Place(frame.Flash, "TOPLEFT", frame.Texture, "TOPLEFT", 1.5, 0.5) -- measured on the art
    Place(glow, "TOPLEFT", frame.Texture, "TOPLEFT", 1.5, 0.5) -- where the Flash sits
    Place(overlay.Status, "TOPLEFT", frame.Texture, "TOPLEFT", 0, 1)
    Place(bars, "TOPLEFT", frame, "TOPLEFT", 45 - SMALL_EXTEND + x, -18.5 + y, 70, 10) -- Forever's own
    -- The health bar runs from the container's left to one unit past its right, by two anchors:
    -- Forever sets its width to the container's on every update (its max health loss), in combat too.
    Place(health, "TOPLEFT", bars, "TOPLEFT", 0, 0, nil, nil, nil, { "BOTTOMRIGHT", bars, "BOTTOMRIGHT", SMALL_EXTEND, 0 })
    Place(bars.HealthBarMask, "TOPLEFT", bars, "TOPLEFT", SMALL_EXTEND - 29, 3)
    Place(mana, "TOPLEFT", bars, "BOTTOMLEFT", SMALL_EXTEND - 4, -1, 74, 7)
    Place(mana.ManaBarMask, "TOPLEFT", mana, "TOPLEFT", SMALL_MANA_MASK_X, SMALL_MANA_MASK_Y)
end

-- In a vehicle a member's frame is Forever's own, its art and places, as SeamlessUnitframes does:
-- Forever moves the bars there itself, in combat too, when nobody else may move them, and only its
-- own vehicle art fits those places. The pieces Forever re-sets give way while the frame is in a
-- vehicle (its state changes before any of them); the rest is handed back here. Leaving the
-- vehicle, Forever puts the bars where ours are, and the HD look comes back.
local artHooked = {}

local function InVehicle(frame)
    local state = frame.state
    return Readable(state) and state == "vehicle"
end

local function ForeverVehicle(frame, health, overlay, glow)
    ns.Darken(frame.VehicleTexture)
    ns.Unpaint(frame.VehicleTexture)
    ns.Release(frame.VehicleTexture)
    ns.Release(frame.Portrait)
    for key in pairs(OVERLAY_ICONS) do
        if key ~= "RoleIcon" then -- Forever re-anchors that one itself
            ns.Release(overlay[key])
        end
    end
    PartyPvP(overlay.PVPIcon, frame.Portrait, overlay, false)
    Place(health, "TOPLEFT", health:GetParent(), "TOPLEFT", 0, 0, 70, 10) -- its template's size
    local atlas = frame.Flash:GetAtlas() -- the aggro glow as Forever's vehicle glow
    if Readable(atlas) and atlas and atlas ~= "" then
        Paint(glow, atlas, true)
    end
    Place(glow, "TOPLEFT", frame.Flash, "TOPLEFT", 0, 0)
end

local function Party(frame, full)
    local bars, mana, overlay = frame.HealthBarContainer, frame.ManaBar, frame.PartyMemberOverlay
    local health = bars and bars.HealthBar
    if not (health and mana and overlay) then
        return
    end
    local unit = UnitOf(frame)
    Health(health, "small", unit)
    Power(mana, "small", frame, unit)
    if not full then
        return
    end
    if not artHooked[frame] then -- every art switch lays the frame out again
        artHooked[frame] = true
        for _, method in ipairs({ "ToVehicleArt", "ToPlayerArt" }) do
            if type(frame[method]) == "function" then
                hooksecurefunc(frame, method, function()
                    ns.Refresh(frame, true)
                end)
            end
        end
        ns.Yield(function()
            return InVehicle(frame)
        end, frame.Flash, overlay.Status, overlay.RoleIcon, frame.Name, bars, bars.HealthBarMask, mana, mana.ManaBarMask)
    end
    local glow = AggroGlow(frame)
    ns.Darken(frame.PetFrame and frame.PetFrame.Texture) -- the party pet keeps Forever's art, darkened too
    PredictionFills(health, "small")
    if InVehicle(frame) then
        ForeverVehicle(frame, health, overlay, glow)
    else
        HDParty(frame, bars, health, mana, overlay, glow)
    end
    ns.Exact(frame.Texture, frame.VehicleTexture, frame.Flash, overlay.Status, glow, bars.HealthBarMask, mana.ManaBarMask)

    local level = BarsLevel(health, mana)
    ns.Layer(frame, level, 1, frame.Flash, overlay.Status, glow)
    ns.Layer(frame, level, 2, frame.Name)
    ns.Layer(frame, level, 3, overlay) -- role, leader and PvP icons

    Text(frame, health, "health", health)
    Text(frame, mana, "power", mana, nil, 4 - SMALL_EXTEND) -- the mana bar starts further left
end

---------------------------------------------------------------------------------------------------
-- Registration and the client's update functions that re-apply its own art.
---------------------------------------------------------------------------------------------------
local PLAYER_UPDATES = {
    "PlayerFrame_ToPlayerArt",
    "PlayerFrame_ToVehicleArt",
    "PlayerFrame_UpdateLevel",
    "PlayerFrame_UpdatePlayerNameTextAnchor",
    "PlayerFrame_UpdateHealthBarVisuals",
    "PlayerFrame_UpdateManaBarVisuals",
    "PlayerFrame_UpdateFlashTextureVisuals",
    "PlayerFrame_UpdateStatusTextureVisuals",
    "PlayerFrame_UpdatePvPStatus",
}

local function PartyMember(frame)
    if not PartyFrame or not Readable(frame) then
        return false
    end
    for i = 1, 4 do
        if PartyFrame["MemberFrame" .. i] == frame then
            return true
        end
    end
    return false
end

local function RegisterAll()
    ns.Register(PlayerFrame, Player)
    ns.Register(PetFrame, Small)
    ns.Register(TargetFrame, Target)
    ns.Register(FocusFrame, Target)
    ns.Register(TargetFrameToT, Small)
    ns.Register(FocusFrameToT, Small)
    if PartyFrame then
        for i = 1, 4 do
            ns.Register(PartyFrame["MemberFrame" .. i], Party)
        end
    end
end

local function OnUnitFrame(frame, full)
    if not ns.IsRegistered(frame) and PartyMember(frame) then
        ns.Register(frame, Party)
    end
    ns.Refresh(frame, full)
end

local function Hook(name, handler)
    if type(_G[name]) == "function" then
        hooksecurefunc(name, handler)
    end
end

local function HookClient()
    Hook("UnitFrame_Initialize", function(frame)
        OnUnitFrame(frame, true)
    end)
    Hook("UnitFrame_Update", function(frame)
        OnUnitFrame(frame, false)
    end)
    Hook("UnitFrameManaBar_UpdateType", function(bar)
        local frame = owners[bar]
        if frame then
            ns.Refresh(frame, false)
        end
    end)
    if FocusFrame and type(FocusFrame.SetSmallSize) == "function" then
        hooksecurefunc(FocusFrame, "SetSmallSize", function()
            ns.Refresh(FocusFrame, true)
        end)
    end
    for _, name in ipairs(PLAYER_UPDATES) do
        Hook(name, function()
            ns.Refresh(PlayerFrame, true)
        end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            ns.InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        ns.UpdateTint()
        ns.InitOptions()
        ns.UpdateCompartment()
        HookClient()
        RegisterAll()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("UNIT_FACTION") -- PvP flag and faction changes
        self:RegisterEvent("PLAYER_FLAGS_CHANGED")
        if not ns.db.wizardDone then
            C_Timer.After(2, ns.ShowWizard) -- first run: once the UI has settled
        end
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ToTPowerBarFix") then
            print("|cff82c5ffRetail HD UnitFrames|r: " .. ns.L.totFix)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.RefreshPending()
    elseif event == "UNIT_FACTION" or event == "PLAYER_FLAGS_CHANGED" then
        ns.UpdatePvP()
    else -- entering the world, group changes: party frames may be new
        RegisterAll()
        ns.RefreshAll(true)
    end
end)
