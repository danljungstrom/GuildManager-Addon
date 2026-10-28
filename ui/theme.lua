-- Guildion -- ui/theme.lua
-- The "Classic" palette: the game's own look, as the other WoW Forever addons wear it. Windows
-- wear the client's own bronze chrome (ui/widgets.lua), or Blizzard's stone-and-gold dialog
-- border untinted on a client without it; panels are a warm near-black; titles and the primary
-- action are the game's gold (GameFontNormal's yellow); borders on our own controls are bronze. The single source of colour: no other file writes a colour literal
-- (the chat prefix in core/init.lua, which loads before this file, is the one exception).
-- Tokens are shared tables; treat them as read-only.
local _, GM = ...

GM.theme = {}
local T = GM.theme

-- panelBG / titleBG / well are a DEPTH LADDER (window, title bar, recess) and must stay
-- visibly apart in every channel; theme_test pins it. rowHover is the row the mouse is OVER
-- (additive, transient); rowSelect is the row that was CHOSEN (a fill under the text,
-- persistent). Two different questions, so two tokens, and ui.DressRow keeps them apart.
T.C = {
  panelBG = { 0.09, 0.075, 0.055 }, -- #17130e
  titleBG = { 0.065, 0.05, 0.035 }, -- #110d09
  well = { 0.04, 0.03, 0.02 }, -- #0a0805
  rowHover = { 0.20, 0.16, 0.08 }, -- #332914
  rowSelect = { 0.42, 0.32, 0.10 }, -- #6b521a  the chosen row's fill
  rowAlt = { 0.06, 0.048, 0.032 }, -- #0f0c08  zebra fill, even rows on `well`
  hairline = { 0.14, 0.11, 0.07 }, -- #241c12  1px row separator on `well`
  frame = { 1.00, 1.00, 1.00 }, -- #ffffff  the fallback window's dialog border, Blizzard's art untinted
  chrome = { 0.72, 0.58, 0.32 }, -- #b89452  bronze: borders, the dropdown list
  chromeDim = { 0.40, 0.32, 0.18 }, -- #66522e  active tab, quiet button, wells
  accent = { 1.00, 0.82, 0.00 }, -- #ffd100  the game's gold: titles, primary action
  accentSoft = { 1.00, 0.90, 0.55 }, -- #ffe68c  gold text on dark
  text = { 0.93, 0.91, 0.86 }, -- #ede8db
  textDim = { 0.66, 0.62, 0.54 }, -- #a89e8a
  profit = { 0.37, 0.91, 0.48 }, -- #5ee87a  a kill, the recording mark
  loss = { 1.00, 0.36, 0.36 }, -- #ff5c5c  a wipe, a refusal
}

-- How much of a colour a widget keeps. A disabled button is the same colours dimmed per
-- channel (ui.MakeButton): the fill and the border keep more of themselves than the label, so
-- the shape stays a button while the text says "not now".
T.DIM = { surface = 0.55, text = 0.45 }

-- Where a fill is deliberately see-through. The chosen row's fill lies over the zebra stripe
-- and under the row's text: opaque, it would swallow both.
T.ALPHA = { rowSelect = 0.55 }

function T.ToHex(c)
  return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- A token that is not in the palette is a typo, and a fallback colour hides it for ever:
-- "textHi", a token that never existed, painted three cells in the plain text colour for a
-- whole release and looked deliberate. Reading one raises where the typo is instead.
setmetatable(T.C, {
  __index = function(_, token)
    error("no theme colour named " .. tostring(token), 2)
  end,
})

-- "|cffRRGGBBtext|r" in a token's colour.
function T.Colorize(text, token)
  return "|cff" .. T.ToHex(T.C[token]) .. text .. "|r"
end

-- Blizzard font objects; a FontString inherits size and face from them.
T.FONT = {
  normal = "GameFontNormal",
  small = "GameFontNormalSmall",
  hi = "GameFontHighlightSmall",
  large = "GameFontNormalLarge",
}

-- Button kinds: fill, hover, pressed, border, text, font. `on` is the CHOSEN state (the tab
-- you are on) as a brighter fill, a brighter border and accent text. It exists because the
-- alternative, marking the chosen one in its LABEL, changes the label's width and shifts the
-- text inside its own button every time the choice moves. A disabled button is the same
-- colours dimmed per channel (ui.MakeButton), opaque, so nothing behind it shows through.
T.BTN = {
  primary = {
    bg = { 0.36, 0.27, 0.08 },
    over = { 0.48, 0.36, 0.10 },
    down = { 0.26, 0.19, 0.05 },
    border = T.C.accent,
    text = { 1.00, 0.92, 0.70 },
    font = T.FONT.normal,
    on = { bg = { 0.48, 0.36, 0.10 }, border = T.C.accent, text = { 1.00, 0.96, 0.85 } },
  },
  accent = {
    bg = T.C.chromeDim,
    over = { 0.50, 0.40, 0.22 },
    down = { 0.28, 0.22, 0.12 },
    border = T.C.chrome,
    text = T.C.accentSoft,
    font = T.FONT.normal,
    on = { bg = { 0.50, 0.40, 0.22 }, border = T.C.accent, text = T.C.accentSoft },
  },
  quiet = {
    bg = { 0.14, 0.11, 0.07 },
    over = T.C.rowHover,
    down = T.C.titleBG,
    border = T.C.chromeDim,
    text = T.C.text,
    font = T.FONT.small,
    on = { bg = T.C.chromeDim, border = T.C.chrome, text = T.C.accentSoft },
  },
}

-- Blizzard art the game ships, recoloured by SetBackdropColor / SetBackdropBorderColor.
-- `solid` is for a floating list: the tooltip background reads translucent even at alpha 1,
-- and a menu with the window's text showing through it is unreadable.
T.BACKDROP = {
  button = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  },
  well = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  },
  window = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 28,
    insets = { left = 10, right = 10, top = 10, bottom = 10 },
  },
  solid = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  },
}

-- Item quality in Blizzard's own colours, not the palette's: green means uncommon
-- everywhere in this game, and re-tinting it would cost more than it gained. Ours rather than
-- ITEM_QUALITY_COLORS so an item the client has not cached yet can still be coloured later
-- from its quality alone.
T.QUALITY = {
  [0] = { 0.62, 0.62, 0.62 }, -- poor
  [1] = { 1.00, 1.00, 1.00 }, -- common
  [2] = { 0.12, 1.00, 0.00 }, -- uncommon
  [3] = { 0.00, 0.44, 0.87 }, -- rare
  [4] = { 0.64, 0.21, 0.93 }, -- epic
  [5] = { 1.00, 0.50, 0.00 }, -- legendary
}

T.QUALITY_NAME = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

-- Art used by the widgets, Blizzard's own plus the files in media/, named here so a wrong path
-- is one edit: a texture the client cannot find draws nothing, so a bad path is invisible rather
-- than loud (theme_test checks that our own files exist).
T.TEX = {
  arrow = "Interface\\Buttons\\UI-SortArrow",
  cog = "Interface\\Icons\\Trade_Engineering",
  minimapIcon = "Interface\\AddOns\\Guildion\\media\\icon", -- the Spartan helmet, our own file
  -- The same helmet smaller and centred: the window's portrait is masked to a circle, which
  -- cut the icon's full-size helmet off at the ring.
  portrait = "Interface\\AddOns\\Guildion\\media\\portrait",
  minimapRing = "Interface\\Minimap\\MiniMap-TrackingBorder",
  minimapDisc = "Interface\\Minimap\\UI-Minimap-Background",
  minimapGlow = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
  unknownItem = "Interface\\Icons\\INV_Misc_QuestionMark",
  sideTab = "Interface\\SpellBook\\SpellBook-SkillLineTab", -- the spellbook's tab, down a window's right edge
  tabLit = "Interface\\Buttons\\CheckButtonHilight", -- the chosen side tab
  hilight = "Interface\\Buttons\\ButtonHilight-Square", -- an icon button under the mouse
  tabSessions = "Interface\\Icons\\INV_Misc_Book_09", -- the log book
  tabCurrent = "Interface\\Icons\\INV_Sword_04", -- the raid going on now
  gripUp = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
  gripOver = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
  gripDown = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
}
