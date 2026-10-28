-- Guildion -- ui/minimap.lua
-- The minimap button: left click opens or closes the window, right click opens a small menu,
-- a left drag walks the button around the minimap's rim.
--
-- Deliberately a plain minimap button (a named Button on Minimap wearing the stock tracking
-- ring) and not one of our own widgets: button-collector addons find buttons by exactly that shape.
-- The place is saved as an ANGLE, not a point: the rim is round, and an x/y pair saved at one
-- UI scale lands off the circle at another.
local _, GM = ...

GM.minimap = {}
local minimap = GM.minimap
local ui = GM.ui
local T = GM.theme

minimap.NAME = "GuildionMinimapButton"
minimap.HIDDEN = "minimap button hidden. The settings bring it back: %s, then the Settings tab."

-- The stock button, in LibDBIcon's numbers so ours lines up with every other addon's: a 31 px
-- button, the 53 px ring drawn from TOPLEFT, a 20 px dark disc under a 17 px icon.
local SIZE, RING = 31, 53
local DISC, DISC_X, DISC_Y = 20, 7, -5
local ICON, ICON_X, ICON_Y = 17, 7, -6
local RIM = 5 -- how far the button's centre sits outside the minimap's edge

-- Degrees around (mx, my) at which (cx, cy) lies: 0 = east, counter-clockwise, 0 <= a < 360.
function minimap.AngleFor(cx, cy, mx, my)
  return math.deg(math.atan2(cy - my, cx - mx)) % 360
end

-- The button's centre, relative to the minimap's, for an angle and a radius.
function minimap.Offset(angle, radius)
  local r = math.rad(angle)
  return math.cos(r) * radius, math.sin(r) * radius
end

-- On the rim, where LibDBIcon puts its buttons, whatever size the minimap has.
function minimap.Radius()
  return Minimap:GetWidth() / 2 + RIM
end

function minimap.Position(angle)
  local x, y = minimap.Offset(angle, minimap.Radius())
  minimap.button:ClearAllPoints()
  minimap.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- The cursor is in screen pixels, the minimap's centre in its own scale.
local function CursorAngle()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  return minimap.AngleFor(cx / scale, cy / scale, mx, my)
end

-- Runs every frame only while the button is being dragged.
local function DragTick()
  minimap.angle = CursorAngle()
  minimap.Position(minimap.angle)
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------

function minimap.MenuItems()
  local recording = GM.session.Current() ~= nil
  local items = {
    { text = "Open the window", value = "window" },
    { text = "Settings", value = "settings" },
  }
  -- Locked saved data takes no writes, so neither recording nor hiding would do anything: an
  -- item that silently does nothing is worse than one that is not offered.
  if not GM.db.locked then
    items[#items + 1] = { text = recording and "Stop recording" or "Start recording", value = recording and "stop" or "start" }
    items[#items + 1] = { text = "Hide this button", value = "hide" }
  end
  return items
end

local ACTIONS = {
  window = function()
    GM.main.Show()
  end,
  settings = function()
    GM.settings.Show()
  end,
  start = function()
    GM.session.Start()
  end,
  stop = function()
    GM.session.Stop()
  end,
  hide = function()
    if GM.db.SetSetting("minimapButton", false) then
      GM.Print(string.format(minimap.HIDDEN, GM.COMMAND))
    end
    minimap.Apply()
    GM.settings.Paint()
  end,
}

local function MenuWidth()
  local widest = 0
  for _, text in ipairs({ "Open the window", "Settings", "Start recording", "Stop recording", "Hide this button" }) do
    widest = math.max(widest, ui.TextWidth("small", text))
  end
  return widest + 16 -- the list's padding and the row label's insets, both sides
end

-- ui.MakeDropdown with no visible control: only its list is used, hung under the button.
-- The holder's strata lifts the list above the addon's windows; the button itself sits low.
local function BuildMenu()
  local holder = CreateFrame("Frame", nil, minimap.button)
  holder:SetFrameStrata("FULLSCREEN_DIALOG")
  holder:SetSize(1, 1)
  holder:SetPoint("TOPRIGHT", minimap.button, "BOTTOMRIGHT", 0, 0)
  local menu = ui.MakeDropdown(holder, { host = holder, anchor = holder, listWidth = MenuWidth() })
  menu:SetSize(1, 1)
  menu:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  menu:Hide()
  -- The minimap lives in the screen's top right corner: the list grows to the left.
  menu.list:ClearAllPoints()
  menu.list:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -2)
  menu.provider = minimap.MenuItems
  menu.onSelect = function(value)
    ACTIONS[value]()
  end
  return menu
end

function minimap.ToggleMenu()
  minimap.menu = minimap.menu or BuildMenu()
  if minimap.menu.list:IsShown() then
    minimap.menu:CloseList()
  else
    minimap.menu:OpenList()
  end
end

-- ---------------------------------------------------------------------------
-- The button
-- ---------------------------------------------------------------------------

local function Build()
  local b = CreateFrame("Button", minimap.NAME, Minimap)
  minimap.button = b
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  -- The disc fills the ring's hole, so the square icon never shows the map behind its corners.
  b.disc = b:CreateTexture(nil, "BACKGROUND")
  b.disc:SetTexture(T.TEX.minimapDisc)
  b.disc:SetSize(DISC, DISC)
  b.disc:SetPoint("TOPLEFT", b, "TOPLEFT", DISC_X, DISC_Y)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(T.TEX.minimapIcon)
  b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", ICON_X, ICON_Y)
  -- The ring is off-centre in its own file: anchored TOPLEFT, as every minimap button does.
  b.ring = b:CreateTexture(nil, "OVERLAY")
  b.ring:SetTexture(T.TEX.minimapRing)
  b.ring:SetSize(RING, RING)
  b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b:SetHighlightTexture(T.TEX.minimapGlow)

  b:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      minimap.ToggleMenu()
    else
      GM.main.Toggle()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    if minimap.menu then
      minimap.menu:CloseList()
    end
    GameTooltip:Hide() -- it was anchored to the button and would hang where the button was
    self:SetScript("OnUpdate", DragTick)
  end)
  -- Saved once, where the drag ended, not on every frame of it. Locked saved data refuses the
  -- write; the drag itself is not refused, so the button stays where the player let it go and
  -- is back at the saved angle after the next /reload.
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if not minimap.angle then
      return
    end
    GM.db.SetSetting("minimapAngle", minimap.angle)
    minimap.Position(minimap.angle)
  end)
  b:SetScript("OnEnter", function(self)
    local dim = T.C.textDim
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Guildion")
    if GM.session.Current() then
      GameTooltip:AddLine("Recording", T.C.profit[1], T.C.profit[2], T.C.profit[3])
    end
    GameTooltip:AddLine("Left click: the window", dim[1], dim[2], dim[3])
    GameTooltip:AddLine("Right click: menu", dim[1], dim[2], dim[3])
    GameTooltip:AddLine("Drag: move", dim[1], dim[2], dim[3])
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return b
end

-- Makes the button match the settings: there or not, and where. Built only when wanted.
function minimap.Apply()
  if not GM.db.Setting("minimapButton") then
    if minimap.button then
      minimap.button:Hide()
    end
    return
  end
  local b = minimap.button or Build()
  minimap.Position(GM.db.Setting("minimapAngle"))
  b:Show()
end

GM.OnLoad(minimap.Apply)
