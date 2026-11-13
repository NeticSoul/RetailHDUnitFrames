--[[
    Retail HD UnitFrames - Media
    Copyright (c) 2026 NeticSoul. Released under the MIT License (see LICENSE).

    Textures: { file, width, height, left, right, top, bottom }. Frames, masks, the corner piece and
    the elite dragons are DragonflightUI's HD (2x) art; glows and bar fills are 1x (soft gradients).
    Third-party art credits are in LICENSE.
]]
local _, ns = ...

local M = "Interface\\AddOns\\RetailHDUnitFrames\\media\\"
-- Bar fills: <family>-<element>, family player|target|small, element health|health-status|mana|
-- mana-status|rage|energy|focus.
ns.BAR = M .. "bars\\"
ns.PVP_ATLAS = "UI-HUD-UnitFrame-Player-PVP-%sIcon" -- Alliance, Horde, FFA: Midnight's own HD icons

ns.media = {
    player = { M .. "player", 198, 71, 0, 396 / 512, 0, 142 / 256 },
    playerFlash = { M .. "player-flash.tga", 192, 71, 0, 192 / 256, 0, 71 / 128 },
    playerStatus = { M .. "player-status", 196, 71, 0, 392 / 512, 0, 142 / 256 },
    playerPortraitMask = { M .. "mask-player-portrait", 60, 60, 0, 1, 0, 1 },
    playerCorner = { M .. "player-corner", 22, 22, 0, 44 / 64, 0, 44 / 64 },
    playerHealthMask = { M .. "mask-player-health", 128, 32, 0, 1, 0, 1 },
    playerManaMask = { M .. "mask-player-mana", 128, 16, 0, 1, 0, 1 },

    target = { M .. "target", 192, 67, 0, 384 / 512, 0, 134 / 256 },
    -- 188 wide on its sheet, but its left line to ring runs 1.25 shorter than the art's: drawn 189.5
    -- wide, every line and the ring land on the art's.
    targetFlash = { M .. "target-flash", 189.5, 67, 0, 376 / 512, 0, 134 / 256 },
    targetType = { M .. "target-type", 135, 18, 0, 270 / 512, 0, 35 / 64 },
    targetHealthMask = { M .. "mask-target-health", 129, 32, 0, 1, 0, 1 }, -- 129 wide, as DragonflightUI
    targetManaMask = { M .. "mask-target-mana", 256, 16, 0, 1, 0, 1 },
    boss = { M .. "boss", 99, 81, 0.001953125, 0.388671875, 0.001953125, 0.31835937 },
    elite = { M .. "boss", 80, 79, 0.001953125, 0.314453125, 0.322265625, 0.630859375 },
    rare = { M .. "boss", 80, 79, 0.00390625, 0.31640625, 0.64453125, 0.953125 },

    -- Target of target, pet and party share one frame art.
    small = { M .. "small", 120, 49, 0, 240 / 256, 0, 98 / 128 },
    smallFlash = { M .. "small-flash.tga", 114, 47, 0, 114 / 128, 0, 47 / 64 },
    smallStatus = { M .. "small-status", 120, 49, 0, 240 / 256, 0, 98 / 128 },
    smallManaMask = { M .. "mask-small-mana", 128, 16, 0, 1, 0, 1 },

    -- Midnight's own art, still in the client where Forever's atlases of the same names now draw
    -- its c60 art: the small frames' health mask (shaped for this art, as DragonflightUI uses it)
    -- and the HD high-level skull (Midnight's is 11x14; a little bigger to fill the name strip).
    smallHealthMask = { "Interface\\HUD\\UIPartyFramePortraitOnHealthMask", 128, 16, 0, 1, 0, 1 },
    skull = { "Interface\\HUD\\UIUnitFrame2x", 12.5, 16, 0.97705078125, 0.98779296875, 0.2548828125, 0.2822265625 },
}
