--[[
    Retail HD UnitFrames - Wizard
    Copyright (c) 2026 NeticSoul. Released under the MIT License (see LICENSE).

    The first-run wizard, shown once (and with /rhd wizard, the options' button or the minimap).
    Every setting is a section: its title on the left (and which frames it is about, under it),
    and a row of selectable picture cards that show what each choice looks like; a click sets it
    through ns.Set, so the frames change at once. Built from plain frames and templates verified
    in Forever.
]]
local _, ns = ...
local L, media, BAR = ns.L, ns.media, ns.BAR

local WIDTH, HEIGHT = 680, 500
local INNER, PAGE_HEIGHT = WIDTH - 56, HEIGHT - 128 -- a page: between the header and the buttons
local LABEL = 160 -- a section's title column; the cards take the rest of the width
local AREA = INNER - LABEL - 16 -- the cards' width
local CARD_WIDTH, CARD_HEIGHT, GAP = 210, 74, 8 -- the widest card
local FOOTER = 22 -- the band at a card's foot, with its caption
local SECTION = CARD_HEIGHT + 16 -- a section: its cards and a margin
local ROW = SECTION + 8 -- sections apart, a discreet line between them
-- Which frames a section is about, where its name does not say it.
local SCOPE = {
    lossAnimation = "scopePlayer",
    groupTab = "scopePlayer",
    threat = "scopeTarget",
    nameBackground = "scopeTarget",
}
local PICTURE_Y = (FOOTER) / 2 -- a card's picture: the middle of the card above its foot band
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BACKDROP = {
    bgFile = WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local GOLD, LIGHT, GREY = { 1, 0.82, 0 }, { 0.8, 0.8, 0.8 }, { 0.35, 0.35, 0.35 }
local HEALTH, POWER = { 1500, 2000 }, { 1200, 2000 } -- the pictures' values
local NO_YES, SHOW_HIDE = { false, true }, { true, false }
local BLACK = { 0, 0, 0 } -- the dark mode presets' color

local wizard, header, step, backButton, nextButton, current
local pages, dots, refreshers = {}, {}, {}
local playerName, playerLevel, playerFaction

local function Refresh()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
end

---------------------------------------------------------------------------------------------------
-- Pictures
---------------------------------------------------------------------------------------------------
-- A texture centered at x, y on parent: a media key, a file, or nil (the caller fills it).
local function Picture(parent, file, width, height, x, y, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    local art = media[file]
    if art then
        texture:SetTexture(art[1])
        texture:SetTexCoord(art[4], art[5], art[6], art[7])
    elseif file then
        texture:SetTexture(file)
    end
    texture:SetSize(width, height)
    texture:SetPoint("CENTER", x, y)
    return texture
end

local function Label(parent, template, text, x, y, point, relativePoint)
    local label = parent:CreateFontString(nil, "OVERLAY", template)
    label:SetPoint(point or "CENTER", parent, relativePoint or "CENTER", x or 0, y or 0)
    label:SetText(text)
    return label
end

local function Mask(parent, file, width, height, x, y, ...)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(width, height)
    mask:SetPoint("CENTER", x, y)
    for i = 1, select("#", ...) do
        select(i, ...):AddMaskTexture(mask)
    end
end

local function Portrait(parent, size, x, y, mask, layer)
    local portrait = Picture(parent, nil, size, size, x, y, layer)
    SetPortraitTexture(portrait, "player")
    Mask(parent, mask or DISC, size, size, x, y, portrait)
end

-- A bar with a dark back and a thin edge, or bare (on the frame art, which has its own back).
-- Returns Fill(file, value, sublevel), which draws a fill cut at value (0 to 1) as a status bar
-- does, and the back.
local function Bar(parent, width, height, x, y, bare)
    local back = Picture(parent, nil, width, height, x, y, "ARTWORK", -2)
    back:SetColorTexture(0.05, 0.05, 0.05, bare and 0 or 1)
    if not bare then
        Picture(parent, nil, width + 2, height + 2, x, y, "ARTWORK", -3):SetColorTexture(0.3, 0.3, 0.3)
    end
    local function Fill(file, value, sublevel)
        local fill = parent:CreateTexture(nil, "ARTWORK", nil, sublevel or 0)
        fill:SetTexture(file)
        fill:SetTexCoord(0, value, 0, 1)
        fill:SetSize(width * value, height)
        fill:SetPoint("LEFT", back, "LEFT")
        return fill
    end
    return Fill, back
end

-- A bar's text in each mode, formatted as the frames do it.
local function BarText(parent, back, mode, values)
    local value, maximum = values[1], values[2]
    local percent = ("%d%%"):format(value * 100 / maximum)
    local function Text(point, x, shown)
        local text = parent:CreateFontString(nil, "OVERLAY", ns.FONT)
        text:SetPoint(point, back, point, x, 0)
        text:SetText(shown)
    end
    if mode == "NUMERIC" then
        Text("CENTER", 0, ("%d / %d"):format(value, maximum))
    elseif mode == "PERCENT" then
        Text("CENTER", 0, percent)
    elseif mode == "BOTH" then
        Text("LEFT", 3, percent)
        Text("RIGHT", -3, value)
    end
end

-- The player's Midnight PvP icon, sized for a portrait of size (the frames' is 60).
local function PvPIcon(parent, size, x, y)
    local atlas = ns.PVP_ATLAS:format(playerFaction)
    local info = C_Texture.GetAtlasInfo(atlas)
    if info then
        local icon = Picture(parent, nil, info.width * size / 60, info.height * size / 60, x, y, "OVERLAY")
        icon:SetAtlas(atlas)
    end
end

-- Forever's own look: the atlas of one of the client's player frame regions, when readable.
local function Copy(texture, key)
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local region = main and main[key]
    local atlas = region and region:GetAtlas()
    if ns.Readable(atlas) and atlas and atlas ~= "" then
        texture:SetAtlas(atlas)
        return true
    end
end

local function ClassColor()
    local _, class = UnitClass("player")
    local color = ns.Readable(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

-- The player frame as a picture, in the addon's own layout (offsets from the art's center), on a
-- frame of its own so any scale keeps it whole. full adds the name, level, PvP icon and texts.
-- Returns the art and the corner, for dark mode.
local function Sample(parent, scale, x, y, full)
    local sample = CreateFrame("Frame", nil, parent)
    sample:SetSize(198, 71)
    sample:SetScale(scale)
    sample:SetPoint("CENTER", x / scale, y / scale)
    Portrait(sample, 60, -61.5, 0, media.playerPortraitMask[1], "BACKGROUND")
    local art = Picture(sample, "player", 198, 71, 0, 0, "BORDER")
    local corner = Picture(sample, "playerCorner", 22, 22, -46.5, -15.5, "OVERLAY")
    local health, healthBack = Bar(sample, 124, 19, 31, -0.5, true)
    local mana, manaBack = Bar(sample, 124, 10, 31, -16, true)
    Mask(sample, media.playerHealthMask[1], 128, 32, 31, -1, health(BAR .. "player-health", HEALTH[1] / HEALTH[2]))
    Mask(sample, media.playerManaMask[1], 128, 16, 31, -17, mana(BAR .. "player-mana", POWER[1] / POWER[2]))
    if full then
        Label(sample, "GameFontNormalSmall", playerName, -28, 23, "TOPLEFT")
        Label(sample, "GameFontNormalSmall", playerLevel, 88, 23, "TOPRIGHT")
        PvPIcon(sample, 60, -92.3, 0)
        BarText(sample, healthBack, "BOTH", HEALTH)
        BarText(sample, manaBack, "BOTH", POWER)
    end
    return art, corner
end

---------------------------------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------------------------------
-- A selectable card: its picture on top, its caption in a band at its foot. The chosen one
-- (isSelected) has a gold edge and a check mark; the card under the mouse a lighter edge.
local function Card(parent, x, y, width, caption, onClick, isSelected)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(width, CARD_HEIGHT)
    card:SetPoint("TOPLEFT", x, y)
    card:SetBackdrop(BACKDROP)
    local band = card:CreateTexture(nil, "BORDER", nil, 1)
    band:SetColorTexture(0, 0, 0, 0.4)
    band:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 3, 3)
    band:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 3)
    band:SetHeight(FOOTER - 3)
    local seam = card:CreateTexture(nil, "BORDER", nil, 2)
    seam:SetColorTexture(1, 1, 1, 0.08)
    seam:SetPoint("BOTTOMLEFT", band, "TOPLEFT")
    seam:SetPoint("BOTTOMRIGHT", band, "TOPRIGHT")
    seam:SetHeight(1)
    local label = Label(card, "GameFontHighlightSmall", caption, 0, FOOTER / 2 - CARD_HEIGHT / 2)
    local check = Picture(card, CHECK, 16, 16, width / 2 - 10, CARD_HEIGHT / 2 - 10, "OVERLAY", 7) -- in the corner
    local over = false
    local function Paint()
        local selected = isSelected and isSelected()
        local edge, text = selected and GOLD or over and LIGHT or GREY, selected and GOLD or LIGHT
        card:SetBackdropBorderColor(edge[1], edge[2], edge[3])
        if selected then
            card:SetBackdropColor(0.22, 0.17, 0.02, 0.9)
        else
            card:SetBackdropColor(0.04, 0.04, 0.05, 0.9)
        end
        label:SetTextColor(text[1], text[2], text[3])
        check:SetShown(selected and true or false)
    end
    card:SetScript("OnEnter", function()
        over = true
        Paint()
    end)
    card:SetScript("OnLeave", function()
        over = false
        Paint()
    end)
    card:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick()
        Refresh()
    end)
    table.insert(refreshers, Paint)
    return card
end

-- A discreet line on a page (separators), from x, y with that size.
local function Line(page, x, y, width, height)
    local line = page:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetSize(width, height)
    line:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
end

-- The next section of a page: its title on the left, which frames it is about right under it,
-- and count cards centered on the rest; discreet lines between sections and before the cards.
-- Returns the x of card i, the cards' y and their width.
local function Row(page, title, count, scope)
    local y = page.y
    page.y = y - ROW
    if y < page.top then
        Line(page, 0, y + (ROW - SECTION) / 2, INNER, 1)
    end
    Line(page, LABEL + 6, y - 10, 1, SECTION - 20)
    local middle = y - SECTION / 2
    local name = Label(page, "GameFontNormalLarge", title, 8, middle + (scope and 1 or 0),
        scope and "BOTTOMLEFT" or "LEFT", "TOPLEFT")
    name:SetWidth(LABEL - 12)
    name:SetJustifyH("LEFT")
    if scope then
        local under = Label(page, "GameFontHighlightSmall", scope, 8, middle - 3, "TOPLEFT", "TOPLEFT")
        under:SetTextColor(0.62, 0.62, 0.62)
    end
    local width = math.min(CARD_WIDTH, (AREA - (count - 1) * GAP) / count)
    local left = INNER - AREA + (AREA - count * width - (count - 1) * GAP) / 2
    return function(i)
        return left + (i - 1) * (width + GAP)
    end, y - (SECTION - CARD_HEIGHT) / 2, width
end

-- A setting as a section of cards, one per value. draw(card, value, width) draws each picture;
-- isSelected(value) tells the chosen one (by default, the saved value).
local function Choice(page, title, key, values, captions, draw, isSelected)
    local x, y, width = Row(page, title, #values, SCOPE[key] and L[SCOPE[key]])
    for i, value in ipairs(values) do
        local caption = captions and captions[i] or L[key .. value] or L[value]
        draw(Card(page, x(i), y, width, caption, function()
            ns.Set(key, value)
        end, function()
            if isSelected then
                return isSelected(value)
            end
            return ns.Get(key) == value
        end), value, width)
    end
end

-- A name over a health bar, as on the frames; strip: the target's colored name background.
local function NameLine(card, width, strip)
    local fill = Bar(card, width - 36, 12, 0, PICTURE_Y - 10)
    fill(BAR .. "player-health", 0.75)
    if strip then
        Picture(card, "targetType", width - 36, 15, 0, PICTURE_Y + 3, "ARTWORK", -4):SetVertexColor(0.9, 0.1, 0.1)
    end
    Label(card, "GameFontNormalSmall", playerName, 0, PICTURE_Y + 2)
end

-- A health or power bar with its text in each mode.
local function TextCard(file, values)
    return function(card, mode, width)
        local fill, back = Bar(card, width - 20, 14, 0, PICTURE_Y)
        fill(file, values[1] / values[2])
        BarText(card, back, mode, values)
    end
end

---------------------------------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------------------------------
-- rows: how many rows of cards, centered on the page.
local function Page(title, rows)
    local page = CreateFrame("Frame", nil, wizard)
    page:SetPoint("TOPLEFT", 28, -76)
    page:SetPoint("BOTTOMRIGHT", -28, 52)
    page.title = title
    page.y = -math.floor((PAGE_HEIGHT - rows * ROW + (rows > 0 and ROW - SECTION or 0)) / 2)
    page.top = page.y -- the first section has no line above it
    table.insert(pages, page)
    return page
end

local function ShowPage(index)
    current = index
    for i, page in ipairs(pages) do
        page:SetShown(i == index)
        local color = i == index and GOLD or i < index and LIGHT or GREY
        dots[i]:SetVertexColor(color[1], color[2], color[3])
    end
    header:SetText(pages[index].title)
    step:SetText(L.wizardStep:format(index, #pages))
    backButton:SetShown(index > 1)
    nextButton:SetText(index == 1 and L.wizardStart or index == #pages and L.wizardFinish or L.wizardNext)
    Refresh()
end

local function Finish()
    ns.db.wizardDone = true
    wizard:Hide()
end

local function Button(text, point, x, onClick)
    local button = CreateFrame("Button", nil, wizard, "UIPanelButtonTemplate")
    button:SetSize(120, 26)
    button:SetPoint(point, x, 20)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Build()
    local name, level, faction = UnitName("player"), UnitLevel("player"), UnitFactionGroup("player")
    playerName = ns.Readable(name) and name or ""
    playerLevel = ns.Readable(level) and level or ""
    playerFaction = (faction == "Alliance" or faction == "Horde") and faction or "FFA"

    wizard = CreateFrame("Frame", "RetailHDUnitFramesWizard", UIParent)
    wizard:SetSize(WIDTH, HEIGHT)
    wizard:SetPoint("CENTER", 0, 60)
    wizard:SetFrameStrata("DIALOG")
    wizard:SetToplevel(true)
    wizard:EnableMouse(true)
    wizard:SetMovable(true)
    wizard:SetClampedToScreen(true)
    wizard:RegisterForDrag("LeftButton")
    wizard:SetScript("OnDragStart", wizard.StartMoving)
    wizard:SetScript("OnDragStop", wizard.StopMovingOrSizing)
    CreateFrame("Frame", nil, wizard, "DialogBorderOpaqueTemplate"):SetAllPoints(wizard)
    header = Label(wizard, "GameFontNormalLarge", "", 0, -22, "TOP", "TOP")
    for _, side in ipairs({ "LEFT", "RIGHT" }) do -- thin gold rules on both sides of the title
        local rule = wizard:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
        rule:SetSize(70, 1)
        if side == "LEFT" then
            rule:SetPoint("RIGHT", header, "LEFT", -12, 0)
        else
            rule:SetPoint("LEFT", header, "RIGHT", 12, 0)
        end
    end
    local close = CreateFrame("Button", nil, wizard, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", Finish)
    backButton = Button(L.wizardBack, "BOTTOMLEFT", 24, function()
        ShowPage(current - 1)
    end)
    nextButton = Button("", "BOTTOMRIGHT", -24, function()
        if current == #pages then
            Finish()
        else
            ShowPage(current + 1)
        end
    end)

    -- 1. Welcome: the frame itself.
    local welcome = Page("Retail HD UnitFrames", 0)
    Sample(welcome, 1.6, 0, 40, true)
    Label(welcome, "GameFontHighlight", L.wizardWelcome, 0, -45)
    Label(welcome, "GameFontDisableSmall", L.wizardBy, 0, -66)

    -- 2. Texts.
    local texts = Page(L.wizardTexts, 3)
    Choice(texts, L.rowHealth, "health", ns.CHOICES.health, nil, TextCard(BAR .. "player-health", HEALTH))
    Choice(texts, L.rowPower, "power", ns.CHOICES.power, nil, TextCard(BAR .. "player-mana", POWER))
    Choice(texts, L.rowShow, "hover", NO_YES, { L.always, L.mouseover }, function(card, hover, width)
        local fill, back = Bar(card, width - 20, 14, 0, PICTURE_Y)
        fill(BAR .. "player-health", HEALTH[1] / HEALTH[2])
        BarText(card, back, "PERCENT", HEALTH)
        if hover then
            Picture(card, "Interface\\CURSOR\\Point", 20, 20, 30, PICTURE_Y - 8, "OVERLAY", 7)
        end
    end)

    -- 3. Bars: their numbers, color and health loss.
    local bars = Page(L.wizardBars, 3)
    Choice(bars, L.rowNumbers, "abbreviate", ns.CHOICES.abbreviate, nil, function(card, style, width)
        local fill, back = Bar(card, width - 20, 14, 0, PICTURE_Y)
        fill(BAR .. "player-health", 0.75)
        local text = card:CreateFontString(nil, "OVERLAY", ns.FONT)
        text:SetPoint("CENTER", back, "CENTER")
        text:SetText(ns.Abbreviate(ns.EXAMPLE, style))
    end)
    Choice(bars, L.rowClass, "classColor", NO_YES, { L.no, L.yes }, function(card, on, width)
        local fill = Bar(card, width - 20, 14, 0, PICTURE_Y)
        local health = fill(BAR .. (on and "player-health-status" or "player-health"), 0.75)
        if on then
            health:SetVertexColor(ClassColor())
        end
    end)
    Choice(bars, L.rowLoss, "lossAnimation", NO_YES, { L.no, L.yes }, function(card, on, width)
        local fill = Bar(card, width - 20, 14, 0, PICTURE_Y)
        if on then
            fill(BAR .. "player-health", 0.8, -1):SetVertexColor(1, 0, 0)
        end
        fill(BAR .. "player-health", 0.55)
    end)

    -- 4. Level, PvP and portraits: the name line, the portrait with its PvP icon, the class icon.
    local look = Page(L.wizardLook, 3)
    Choice(look, L.rowLevel, "level", ns.CHOICES.level, nil, function(card, style, width)
        local barWidth = width - 40
        local fill = Bar(card, barWidth, 12, 0, PICTURE_Y - 6)
        fill(BAR .. "player-health", 0.75)
        if style == "RETAIL" then
            Label(card, "GameFontNormalSmall", playerName, 2 - barWidth / 2, PICTURE_Y, "BOTTOMLEFT")
            Label(card, "GameFontNormalSmall", playerLevel, barWidth / 2 - 2, PICTURE_Y, "BOTTOMRIGHT")
            return
        end
        Label(card, "GameFontNormalSmall", playerName, 0, PICTURE_Y, "BOTTOM")
        if style == "FOREVER" then
            local x = -barWidth / 2 - 4
            local circle = Picture(card, nil, 24, 24, x, PICTURE_Y - 6, "ARTWORK", 7)
            if not Copy(circle, "LevelBackgroundCircle") then
                circle:SetTexture(DISC)
                circle:SetVertexColor(0.15, 0.15, 0.15)
            end
            Label(card, "GameFontNormalSmall", playerLevel, x, PICTURE_Y - 6)
        end
    end)
    Choice(look, L.rowPvP, "pvp", ns.CHOICES.pvp, nil, function(card, style)
        Portrait(card, 36, 10, PICTURE_Y)
        if style == "RETAIL" then
            PvPIcon(card, 36, 10 - 18.5, PICTURE_Y)
        elseif style == "FOREVER" then
            local badge = Picture(card, nil, 26, 26, -12, PICTURE_Y, "OVERLAY")
            if not Copy(badge, "PvpBackgroundIcon") then
                badge:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. playerFaction)
            end
        end
    end)
    Choice(look, L.rowPortrait, "classIcons", NO_YES, { L.portrait, L.classIcon }, function(card, icon)
        local _, class = UnitClass("player")
        local atlas = icon and ns.Readable(class) and class and GetClassAtlas and GetClassAtlas(class) -- the game's
        if atlas then
            Picture(card, nil, 40, 40, 0, PICTURE_Y):SetAtlas(atlas)
        else
            Portrait(card, 40, 0, PICTURE_Y)
        end
    end)

    -- 5. Extras: pieces of the frames that can be hidden.
    local extras = Page(L.wizardExtras, 3)
    Choice(extras, L.rowGroupTab, "groupTab", SHOW_HIDE, { L.show, L.hide }, function(card, shown, width)
        NameLine(card, width)
        if shown then
            local x = width / 2 - 42
            Picture(card, nil, 46, 13, x, PICTURE_Y + 12, "ARTWORK", 7):SetColorTexture(0.1, 0.1, 0.1, 0.9)
            Label(card, "GameFontHighlightSmall", (GROUP or "Group") .. " 1", x, PICTURE_Y + 12)
        end
    end)
    Choice(extras, L.rowThreat, "threat", SHOW_HIDE, { L.show, L.hide }, function(card, shown, width)
        NameLine(card, width, true)
        if shown then
            Picture(card, nil, 36, 13, 0, PICTURE_Y + 15, "ARTWORK", 7):SetColorTexture(0.75, 0.1, 0.1, 0.9)
            Label(card, "GameFontHighlightSmall", "100%", 0, PICTURE_Y + 15)
        end
    end)
    Choice(extras, L.rowNameBackground, "nameBackground", SHOW_HIDE, { L.show, L.hide }, function(card, shown, width)
        NameLine(card, width, shown)
    end)

    -- 6. Dark mode: the intensity presets (the frame art at each, in black), or a color of one's own.
    local dark = Page(L.wizardDark, 2)
    Choice(dark, L.rowIntensity, "darkMode", ns.CHOICES.darkMode, nil, function(card, mode, width)
        -- on a light scene, as over the game world: dark art on the black card could not be seen
        Picture(card, nil, width - 12, 46, 0, PICTURE_Y, "ARTWORK", -8):SetColorTexture(0.5, 0.52, 0.45)
        local art, corner = Sample(card, 0.45, 0, PICTURE_Y)
        local r, g, b = ns.Tint(mode, BLACK)
        art:SetVertexColor(r or 1, g or 1, b or 1)
        corner:SetVertexColor(r or 1, g or 1, b or 1)
    end, function(mode)
        return ns.db.darkMode == mode and not ns.CustomColor()
    end)
    local x, y, width = Row(dark, L.rowColor, 1)
    local pick = Card(dark, x(1), y, width, L.darkColorButton, function()
        ns.PickColor(Refresh)
    end, ns.CustomColor)
    Picture(pick, nil, width - 12, 46, 0, PICTURE_Y, "ARTWORK", -8):SetColorTexture(0.5, 0.52, 0.45) -- the same scene
    Picture(pick, nil, 46, 24, 0, PICTURE_Y):SetColorTexture(0.8, 0.8, 0.8)
    local swatch = Picture(pick, nil, 42, 20, 0, PICTURE_Y, "OVERLAY")
    table.insert(refreshers, function()
        local color = ns.db.darkColor
        swatch:SetColorTexture(color[1], color[2], color[3])
    end)

    -- 7. Done: where the settings are, any time: /rhd, the options and the minimap.
    local done = Page(L.wizardDone, 0)
    Picture(done, "Interface\\RaidFrame\\ReadyCheck-Ready", 64, 64, 0, 70)
    Label(done, "GameFontHighlightLarge", L.wizardDoneHint, 0, 10)
    Label(done, "GameFontNormalHuge", "/rhd", 0, -28)
    Label(done, "GameFontHighlight", L.wizardDoneMore, 0, -62)

    -- Progress: one dot per page; a click on a dot goes straight to its page.
    for i = 1, #pages do
        local dot = CreateFrame("Button", nil, wizard)
        dot:SetSize(14, 14)
        dot:SetPoint("CENTER", (i - (#pages + 1) / 2) * 16, HEIGHT / 2 - 50)
        dot:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ShowPage(i)
        end)
        dots[i] = Picture(dot, DISC, 8, 8, 0, 0, "OVERLAY")
    end
    -- and, centered under the dots, which step this is
    step = Label(wizard, "GameFontDisableSmall", "", 0, HEIGHT / 2 - 64)
end

function ns.ShowWizard()
    if not wizard then
        Build()
    end
    ShowPage(1)
    wizard:Show()
end
