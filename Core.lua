--[[
    Retail HD UnitFrames - Core
    Copyright (c) 2026 NeticSoul. Released under the MIT License (see LICENSE).

    The engine: repaints Blizzard's own unit frames and keeps them repainted, layered and placed.

    Rules that keep it free of taint under Forever's secret values:
      * never write a field into a Blizzard table and never call Blizzard's Lua on the unit frames:
        only widget methods, hooksecurefunc and HookScript (state lives in local tables keyed by
        region); the options use Blizzard's Settings and color picker as any addon does;
      * protected regions are only moved, resized, re-layered or re-parented out of combat;
      * secret values only go to setters that accept them (SetValue, SetFormattedText, SetAlpha)
        and to the client's C functions that take them (AbbreviateNumbers).
]]
local _, ns = ...
local media = ns.media

local canaccessvalue = canaccessvalue
local writing = false -- true while we call a setter that our own hooks also watch

-- A value that exists and that this (tainted) code may read.
local function Readable(value)
    return value ~= nil and (not canaccessvalue or canaccessvalue(value))
end
ns.Readable = Readable

-- In combat only unprotected regions may change.
local function Movable(region)
    if not InCombatLockdown() then
        return true
    end
    local isProtected = region.IsProtected
    if not isProtected then
        return false
    end
    local protected = isProtected(region)
    return Readable(protected) and not protected
end
ns.Movable = Movable

---------------------------------------------------------------------------------------------------
-- Textures. A key is a media entry, a file path, or a native atlas. The client re-applies its own
-- atlases on many updates; a SetAtlas hook paints ours back in the same call stack, before any draw.
-- Unpaint gives a region the client's own look back (a setting turned off, live).
---------------------------------------------------------------------------------------------------
local drawn, sized, own = {}, {}, {} -- own: the client's look before the first paint

-- Drawn exactly where placed, not rounded to the pixel grid, as the client draws the player and
-- target bars, masks and art. Party frames round each piece on its own: on a frame that sits
-- half a pixel off, a bar could land a pixel lower than the art's lines and cover the border.
local function Exact(...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region and region.SetSnapToPixelGrid then
            region:SetTexelSnappingBias(0)
            region:SetSnapToPixelGrid(false)
        end
    end
end
ns.Exact = Exact

-- Regions that give way to the client while a test holds (a party frame in a vehicle shows
-- Forever's own frame): the client's atlases and anchors then stand, ours come back after.
local yields = {} -- [region] = test

function ns.Yield(test, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region then
            yields[region] = test
        end
    end
end

local function Yielding(region)
    local test = yields[region]
    return test and test() or false
end

local function Draw(region)
    local key = drawn[region]
    local data = media[key]
    local resize = sized[region] and Movable(region)
    writing = true
    if data then
        region:SetTexture(data[1])
        region:SetTexCoord(data[4], data[5], data[6], data[7])
        if resize then
            region:SetSize(data[2], data[3])
        end
    elseif key:find("\\", 1, true) then
        region:SetTexture(key)
        region:SetTexCoord(0, 1, 0, 1)
    else
        region:SetAtlas(key, resize)
    end
    writing = false
end

local function OnSetAtlas(region)
    if not writing and drawn[region] and not Yielding(region) then
        Draw(region)
    end
end

-- The client's look of a region: its atlas, or else its file, texture coordinates and size (the
-- client may draw a texture from a file, and then GetAtlas gives an empty name). false: unreadable.
local function Look(region)
    local atlas = region:GetAtlas()
    if Readable(atlas) and atlas and atlas ~= "" then
        return { atlas = atlas }
    end
    local file, coords, size = region:GetTexture(), { region:GetTexCoord() }, { region:GetSize() }
    for _, value in ipairs(coords) do
        if not Readable(value) then
            return false
        end
    end
    if Readable(file) and file and Readable(size[1]) and Readable(size[2]) then
        return { file = file, coords = coords, size = size }
    end
    return false
end

function ns.Paint(region, key, size)
    if not region then
        return
    end
    if own[region] == nil then
        own[region] = Look(region)
        hooksecurefunc(region, "SetAtlas", OnSetAtlas)
    end
    drawn[region], sized[region] = key, size or false
    Draw(region)
end

function ns.Unpaint(region)
    if not region or not drawn[region] then
        return
    end
    drawn[region] = nil
    local look, resize = own[region], sized[region] and Movable(region)
    if not look then
        return
    end
    writing = true
    if look.atlas then
        region:SetAtlas(look.atlas, resize)
    else
        region:SetTexture(look.file)
        region:SetTexCoord(unpack(look.coords))
        if resize then
            region:SetSize(look.size[1], look.size[2])
        end
    end
    writing = false
end

---------------------------------------------------------------------------------------------------
-- Status bar fills, kept the same way (the bar's setter and its fill texture's SetAtlas). A fill
-- keeps the client's draw layer: bars sharing a frame level (Midnight's health bar and the red
-- health-loss bar under it) are ordered by it, and a texture swap could reset it.
---------------------------------------------------------------------------------------------------
local fills, watchedFill = {}, {}

local function Apply(bar)
    local before = bar:GetStatusBarTexture()
    local layer, sublevel
    if before then
        layer, sublevel = before:GetDrawLayer()
    end
    writing = true
    bar:SetStatusBarTexture(fills[bar])
    local fill = bar:GetStatusBarTexture()
    Exact(fill)
    local now = fill and fill:GetDrawLayer()
    if Readable(layer) and Readable(now) and now ~= layer and Movable(fill) then
        fill:SetDrawLayer(layer, Readable(sublevel) and sublevel or 0)
    end
    writing = false
    if fill and not watchedFill[fill] then
        watchedFill[fill] = true
        hooksecurefunc(fill, "SetAtlas", function()
            if not writing then
                Apply(bar)
            end
        end)
    end
end

local function OnSetStatusBarTexture(bar)
    if not writing then
        Apply(bar)
    end
end

function ns.Fill(bar, file)
    if not bar or fills[bar] == file then
        return
    end
    if not fills[bar] then
        hooksecurefunc(bar, "SetStatusBarTexture", OnSetStatusBarTexture)
    end
    fills[bar] = file
    Apply(bar)
end

-- Safety net: the client can re-skin a bar without going through hookable Lua (seen on the
-- target-of-target power bar). Our fills are files, so any atlas on a visible bar is the client's.
C_Timer.NewTicker(0.25, function()
    for bar in pairs(fills) do
        local visible = bar:IsVisible()
        if Readable(visible) and visible then
            local fill = bar:GetStatusBarTexture()
            local atlas = fill and fill:GetAtlas()
            if Readable(atlas) and atlas ~= "" then
                Apply(bar)
            end
        end
    end
end)

---------------------------------------------------------------------------------------------------
-- Geometry, kept like the art: when the client re-anchors a region we placed, a SetPoint hook puts
-- it back in the same call stack. Protected regions that cannot move in combat wait for its end.
-- Release hands a region back to the client with the anchors it had before our first Place, so
-- every setting applies without a reload.
---------------------------------------------------------------------------------------------------
local placed, original, hooked = {}, {}, {}
local blocked = false

local function Anchor(region)
    if not Movable(region) then
        blocked = true
        return
    end
    local p = placed[region]
    writing = true
    region:ClearAllPoints()
    region:SetPoint(p[1], p[2], p[3], p[4], p[5])
    local q = p[9] -- a second anchor: the size then comes from the two, whatever the client sets
    if q then
        region:SetPoint(q[1], q[2], q[3], q[4], q[5])
    end
    if p[6] then
        region:SetWidth(p[6])
    end
    if p[7] then
        region:SetHeight(p[7])
    end
    if p[8] then
        region:SetJustifyH(p[8])
    end
    writing = false
end

local function OnSetPoint(region)
    if not writing and placed[region] and not Yielding(region) then
        Anchor(region)
    end
end

-- The client's anchors, or nil when it keeps them secret (it re-anchors such regions itself).
local function Snapshot(region)
    local count = region:GetNumPoints()
    local justify = region.GetJustifyH and region:GetJustifyH()
    if not Readable(count) or (justify ~= nil and not Readable(justify)) then
        return
    end
    local snapshot = { justify = justify }
    for i = 1, count do
        local point = { region:GetPoint(i) }
        for j = 1, 5 do
            if point[j] ~= nil and not Readable(point[j]) then
                return
            end
        end
        snapshot[i] = point
    end
    return snapshot
end

function ns.Place(region, point, relativeTo, relativePoint, x, y, width, height, justify, second)
    if not region or not relativeTo then
        return
    end
    local p = placed[region]
    if not p then
        p = {}
        original[region] = Snapshot(region)
        placed[region] = p
        if not hooked[region] then
            hooked[region] = true
            hooksecurefunc(region, "SetPoint", OnSetPoint)
        end
    end
    p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8] = point, relativeTo, relativePoint, x, y, width, height, justify
    p[9] = second
    Anchor(region)
end

function ns.Release(region)
    if not region or not placed[region] or not Movable(region) then
        return
    end
    local snapshot = original[region]
    placed[region], original[region] = nil, nil
    if snapshot then
        writing = true
        region:ClearAllPoints()
        for _, p in ipairs(snapshot) do
            region:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end
        if snapshot.justify then
            region:SetJustifyH(snapshot.justify)
        end
        writing = false
    end
end

---------------------------------------------------------------------------------------------------
-- Visibility and layers. Hide parks a region in a hidden frame of ours: hidden for good, whatever
-- the client shows or fades; Unhide gives it back to its own parent.
--
-- Layers above the bars, as in retail: 1 = glows (combat, rest), 2 = names, levels and elite
-- dragon, 3 = icons: the client's groups (attack, leader, rest, raid...) and the retail PvP icon,
-- over the level circle, 4 = damage and healing numbers on the portrait, over every icon.
-- Forever draws all of these below the bars. A region of the client moves into an ordinary frame
-- of ours at that layer; a frame of the client is raised to it. The client keeps showing, fading
-- and coloring them as before.
---------------------------------------------------------------------------------------------------
local hidden = CreateFrame("Frame")
hidden:Hide()
local parents, overlays = {}, {}

function ns.Hide(region)
    if region and not InCombatLockdown() and region:GetParent() ~= hidden then
        parents[region] = region:GetParent()
        region:SetParent(hidden)
    end
end

function ns.Unhide(region)
    if region and parents[region] and not InCombatLockdown() and region:GetParent() == hidden then
        region:SetParent(parents[region])
    end
end

local function Overlay(frame, layer, level)
    local byLayer = overlays[frame] or {}
    overlays[frame] = byLayer
    local overlay = byLayer[layer]
    if not overlay then
        overlay = CreateFrame("Frame", nil, frame)
        overlay:SetAllPoints(frame)
        byLayer[layer] = overlay
    end
    overlay:SetFrameLevel(level + layer)
    return overlay
end

-- level: the frame level of the frame's bars.
function ns.Layer(frame, level, layer, ...)
    if InCombatLockdown() then
        return
    end
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region then
            if region.SetFrameLevel then
                region:SetFrameLevel(level + layer)
            else
                local overlay = Overlay(frame, layer, level)
                if region:GetParent() ~= overlay then
                    region:SetParent(overlay)
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Dark mode: a vertex color on every piece of frame decoration (art, corner, dragons, level
-- circle), kept when the client recolors one. Off gives each piece back the color it had before
-- it was first tinted (another addon's dark mode included).
---------------------------------------------------------------------------------------------------
local darkened, natural = {}, {}
local tint -- { r, g, b }, or nil when off

local function ApplyTint(region)
    local color = tint or natural[region]
    writing = true
    region:SetVertexColor(color[1], color[2], color[3])
    writing = false
end

local function OnSetVertexColor(region)
    if not writing and tint then
        ApplyTint(region)
    end
end

function ns.Darken(...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region then
            if not darkened[region] then
                darkened[region] = true
                local r, g, b = region:GetVertexColor()
                natural[region] = Readable(r) and Readable(g) and Readable(b) and { r, g, b } or { 1, 1, 1 }
                hooksecurefunc(region, "SetVertexColor", OnSetVertexColor)
            end
            ApplyTint(region)
        end
    end
end

-- r, g, b: the dark mode color, or nil for off.
function ns.SetTint(r, g, b)
    tint = r and { r, g, b } or nil
    for region in pairs(darkened) do
        ApplyTint(region)
    end
end

---------------------------------------------------------------------------------------------------
-- Frames. A layout(frame, full) repaints the unit-dependent parts (fills, colors, PvP icon); with
-- full it also repaints the static art and applies geometry and layers. Combat defers the full pass.
---------------------------------------------------------------------------------------------------
local layouts, pending = {}, {}
local busy = false

-- Frame methods (when present) after which the client re-applies its own art or anchors.
local METHODS = {
    "Show",
    "SetShown",
    "UpdateArt",
    "CheckClassification",
    "CheckFaction",
    "CheckLevel",
    "CheckBattlePet",
    "UpdateHealthBarVisuals",
    "UpdateNameTextAnchors",
    "ToPlayerArt",
    "ToVehicleArt",
    "ToCharacterStyleArt",
}

function ns.Refresh(frame, full)
    local layout = layouts[frame]
    if not layout or busy then
        return
    end
    busy = true
    local ok, err = pcall(layout, frame, full)
    busy = false
    if not ok then
        geterrorhandler()(err)
    end
    if full and InCombatLockdown() then
        pending[frame] = true
    end
end

function ns.RefreshAll(full)
    for frame in pairs(layouts) do
        ns.Refresh(frame, full)
    end
end

function ns.Register(frame, layout)
    if not frame or layouts[frame] then
        return
    end
    layouts[frame] = layout
    for _, name in ipairs(METHODS) do
        if type(frame[name]) == "function" then
            hooksecurefunc(frame, name, function()
                ns.Refresh(frame, true)
            end)
        end
    end
    ns.Refresh(frame, true)
end

function ns.IsRegistered(frame)
    return layouts[frame] ~= nil
end

function ns.RefreshPending()
    for frame in pairs(pending) do
        pending[frame] = nil
        ns.Refresh(frame, true)
    end
    if blocked then
        blocked = false
        for region in pairs(placed) do
            Anchor(region)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Status text: our own strings, fed by the bar's own updates, so Blizzard's status text code never
-- runs on our behalf. Values may be secret: they are only formatted, never compared or computed.
--
-- Optionally each text only while the mouse is over its own bar, as the client's status text does.
-- Entering the unit frame or a bar starts polling IsMouseOver on the frame and on each bar while the
-- mouse is over any of them, as SeamlessDamageMeter does, because a child that takes the mouse (an
-- icon, a bar) swallows OnLeave and a bar of ours takes no mouse at all. A region placed with a
-- secret answers IsMouseOver with a secret: texts hang from regions the client places plainly, and
-- should one turn secret anyway its text follows the whole frame. Hidden texts are not formatted
-- at all; they catch up when shown.
---------------------------------------------------------------------------------------------------
local FONT = TextStatusBarText and "TextStatusBarText" or "GameFontHighlightSmall"
ns.FONT = FONT
local SCALE = CurveConstants and CurveConstants.ScaleTo100
local HAS_PERCENT = {
    health = SCALE and UnitHealthPercent and true,
    power = SCALE and UnitPowerPercent and true,
}
local texts, barsOf, hovered = {}, {}, {}
ns.EXAMPLE = 1429200 -- the number the options show each style with

-- Number styles: the client's own abbreviation (it takes secret values), always with K, M and B
-- (its own names are translated: "mil" in Spanish). SHORT: 1.4M, 52K, 1.5K. LARGE: 1429K, whole
-- below 100K. Breakpoints go from largest to smallest, in pairs as the client's API asks. Each style
-- is tried once: if the client refused it, the style falls back to the client's own abbreviation.
local function Breakpoint(at, name, significandDivisor, fractionDivisor)
    return {
        breakpoint = at,
        abbreviation = name,
        significandDivisor = significandDivisor,
        fractionDivisor = fractionDivisor,
        abbreviationIsGlobal = false,
    }
end

local function Style(data, fallback)
    local candidates = { { breakpointData = data } }
    local ok, config = pcall(CreateAbbreviateConfig, data) -- cached by the client, when it allows
    if ok and config then
        table.insert(candidates, 1, { config = config })
    end
    for _, options in ipairs(candidates) do
        local works, example = pcall(AbbreviateNumbers, ns.EXAMPLE, options)
        if works and type(example) == "string" and example:find("[KMB]$") then
            return function(value)
                return AbbreviateNumbers(value, options)
            end
        end
    end
    return fallback
end

local ABBREVIATE = {
    SHORT = Style({
        Breakpoint(1e10, "B", 1e9, 1), Breakpoint(1e9, "B", 1e8, 10),
        Breakpoint(1e7, "M", 1e6, 1), Breakpoint(1e6, "M", 1e5, 10),
        Breakpoint(1e4, "K", 1e3, 1), Breakpoint(1e3, "K", 1e2, 10),
    }, AbbreviateNumbers),
    LARGE = Style({ Breakpoint(1e8, "M", 1e6, 1), Breakpoint(1e5, "K", 1e3, 1) }, AbbreviateLargeNumbers),
}

-- A number in a style ("OFF" or a missing function: as it is), for the texts and the examples.
function ns.Abbreviate(value, style)
    local abbreviate = ABBREVIATE[style]
    if abbreviate then
        return abbreviate(value)
    end
    return value
end

local function Percent(kind, unit)
    if kind == "health" then
        return UnitHealthPercent(unit, true, SCALE)
    end
    return UnitPowerPercent(unit, nil, false, SCALE)
end

-- A unit's state in place of its health, as the client's raid frames: dead (or a ghost), offline.
-- Shown whatever the text mode and hover: it is a state, not a number.
local function StateLabel(unit)
    local online = UnitIsConnected(unit)
    if Readable(online) and not online then
        return PLAYER_OFFLINE
    end
    local dead = UnitIsDeadOrGhost(unit)
    if Readable(dead) and dead then
        return DEAD
    end
end

local function UpdateText(bar)
    local text = texts[bar]
    local kind = text.kind
    local unit = bar.unit
    if not Readable(unit) or type(unit) ~= "string" then
        unit = nil
    end
    local label = kind == "health" and unit and StateLabel(unit)
    text.holder:SetAlpha((label or text.shown) and 1 or 0)
    text.center:SetText(label or "")
    text.left:SetText("")
    text.right:SetText("")
    local mode = ns.db[kind]
    if label or not text.shown or mode == "NONE" or not unit then
        return
    end
    local current, maximum
    if kind == "health" then
        current, maximum = UnitHealth(unit), UnitHealthMax(unit)
    else
        current, maximum = UnitPower(unit), UnitPowerMax(unit)
        if Readable(maximum) and maximum == 0 then
            return
        end
    end
    local style = ns.db.abbreviate
    local number = ABBREVIATE[style] and "%s" or "%d"
    if mode == "NUMERIC" or not HAS_PERCENT[kind] then
        text.center:SetFormattedText(number .. " / " .. number,
            ns.Abbreviate(current, style), ns.Abbreviate(maximum, style))
    elseif mode == "PERCENT" then
        text.center:SetFormattedText("%.0f%%", Percent(kind, unit))
    else
        text.left:SetFormattedText("%.0f%%", Percent(kind, unit))
        text.right:SetFormattedText(number, ns.Abbreviate(current, style))
    end
end

local function SafeUpdateText(bar)
    pcall(UpdateText, bar)
end

local poller = CreateFrame("Frame")
poller:Hide()

-- Whether the mouse is over a region; nil when its place is secret.
local function Over(region)
    local over = region:IsMouseOver()
    if Readable(over) then
        return over and true or false
    end
end

-- With hover, only the text of the bar under the mouse shows. The frame is polled while the mouse
-- is over it or one of its bars (one may stick out of it), and forgotten once it is not.
local function ShowTexts(frame)
    local hover = ns.db.hover
    local onFrame = hover and Over(frame) or false
    local inside = onFrame
    for _, bar in ipairs(barsOf[frame]) do
        local text = texts[bar]
        local over = false
        if hover then
            over = Over(text.anchor)
            if over == nil then
                over = onFrame -- its place is secret: the whole frame stands for it
            end
        end
        local shown = not hover or over
        inside = inside or over
        if text.shown ~= shown then
            text.shown = shown
            SafeUpdateText(bar) -- shows or hides it (a state label always shows)
        end
    end
    if inside then
        hovered[frame] = true
        poller:Show()
    else
        hovered[frame] = nil
    end
end

poller:SetScript("OnUpdate", function(self)
    for frame in pairs(hovered) do
        ShowTexts(frame)
    end
    if not next(hovered) then
        self:Hide()
    end
end)

local function Hover(frame, region)
    region:HookScript("OnEnter", function()
        ShowTexts(frame)
    end)
end

-- kind: "health" or "power". anchor: the region the text spans; trim cuts its right side and lead
-- its left side, negative ones widen it (a power bar that runs past the health bar, under the
-- ring: texts line up).
function ns.Text(frame, bar, kind, anchor, trim, lead, font)
    if not frame or not bar or not anchor then
        return
    end
    local text = texts[bar]
    if not text then
        if InCombatLockdown() then
            return -- unit frames are protected: hook their scripts after combat (the full pass waits)
        end
        local holder = CreateFrame("Frame", nil, bar) -- a child of the bar: shown and hidden with it
        holder:SetFrameLevel(bar:GetFrameLevel() + 10) -- above every layer
        local function String(point, x)
            local fontString = holder:CreateFontString(nil, "OVERLAY", FONT)
            fontString:SetPoint(point, holder, point, x, 0)
            return fontString
        end
        text = {
            holder = holder,
            kind = kind,
            anchor = anchor,
            center = String("CENTER", 0),
            left = String("LEFT", 3),
            right = String("RIGHT", -3),
        }
        texts[bar] = text
        hooksecurefunc(bar, "SetValue", SafeUpdateText)
        hooksecurefunc(bar, "SetMinMaxValues", SafeUpdateText)
        for _, key in ipairs({ "TextString", "LeftText", "RightText" }) do -- Blizzard's own status text
            local native = bar[key]
            if native and native.SetAlpha then
                native:SetAlpha(0)
            end
        end
        if not barsOf[frame] then
            barsOf[frame] = {}
            Hover(frame, frame)
        end
        table.insert(barsOf[frame], bar)
        if bar:GetScript("OnEnter") then
            Hover(frame, bar) -- a bar with its own mouse handler takes the mouse from the frame
        end
        ShowTexts(frame)
    end
    text.anchor = anchor -- what the mouse must be over: where the bar is drawn
    local object = font or FONT -- a bigger font where the client scales a frame down (small focus)
    if text.font ~= object and _G[object] then
        text.font = object
        text.center:SetFontObject(object)
        text.left:SetFontObject(object)
        text.right:SetFontObject(object)
    end
    text.holder:ClearAllPoints()
    text.holder:SetPoint("TOPLEFT", anchor, "TOPLEFT", lead or 0, 0)
    text.holder:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -(trim or 0), 0)
    SafeUpdateText(bar)
end

function ns.UpdateTexts()
    for frame in pairs(barsOf) do
        ShowTexts(frame)
    end
    for bar in pairs(texts) do
        SafeUpdateText(bar)
    end
end
