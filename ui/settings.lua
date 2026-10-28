-- Guildion -- ui/settings.lua
-- The settings window, opened from the Settings side tab of the main window, from the minimap
-- button's menu and from the game's Esc > Options page. Every control writes through
-- db.SetSetting the moment it is used and is painted from db.Setting, so the window holds no
-- state of its own.
local _, GM = ...

GM.settings = {}
local settings = GM.settings
local ui = GM.ui
local T = GM.theme

settings.NAME = "GuildionSettings"
settings.APPLIED = "Changes apply at once."
settings.LOCKED = "Saved by a newer version: update the addon."

-- Room around the controls, on top of the window's inset: the client's border is thick, and
-- controls placed at the bare inset read as crammed against it.
local CONTENT_GAP = 14 -- between the title bar and the first control
settings.PAD = 12 -- either side of the controls
settings.BOTTOM = 12 -- under the last line
local PAD, BOTTOM = settings.PAD, settings.BOTTOM
local ROW_GAP = 10
local BESIDE_GAP = 12 -- between the main window's side tabs and this window, room for their art

-- The check boxes, top to bottom: the setting's key and its label.
settings.CHECKS = {
  { key = "autoRecord", label = "Record automatically in a raid" },
  { key = "promptExport", label = "Open the window when a recording ends" },
  { key = "minimapButton", label = "Show the minimap button" },
  { key = "debugDungeon", label = "Also record 5-player dungeons (for testing)" },
}

-- What else has to happen when a setting changes, by key.
local APPLY = {
  autoRecord = function()
    GM.session.Evaluate()
  end,
  debugDungeon = function()
    GM.session.Evaluate()
  end,
  minimapButton = function()
    if GM.minimap then
      GM.minimap.Apply()
    end
  end,
}

local function Set(key, value)
  if GM.db.SetSetting(key, value) and APPLY[key] then
    APPLY[key]()
  end
  settings.Paint()
end

function settings.QualityText(quality)
  if quality >= 5 then
    return T.QUALITY_NAME[5] .. " only"
  end
  return T.QUALITY_NAME[quality] .. " and better"
end

local function QualityItems()
  local items, current = {}, GM.db.Setting("lootQuality")
  for quality = 2, 5 do
    items[#items + 1] = { text = settings.QualityText(quality), value = quality, checked = quality == current }
  end
  return items
end

local function WidestQualityText()
  local widest = 0
  for quality = 2, 5 do
    widest = math.max(widest, ui.TextWidth("small", settings.QualityText(quality)))
  end
  return widest
end

-- Returns the window; the caller publishes it. Nothing here writes settings.frame: a control
-- that throws halfway would leave a shell there that every later Show puts on screen and every
-- Paint writes into, and nothing would ever build the window again.
local function Build()
  local f = ui.MakeWindow(settings.NAME, { title = "Settings", strata = "DIALOG" })
  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", f.titleBar, "BOTTOMLEFT", PAD, -CONTENT_GAP)
  f.content:SetPoint("TOPRIGHT", f.titleBar, "BOTTOMRIGHT", -PAD, -CONTENT_GAP)
  local stack = ui.Stack(f.content, { gap = ROW_GAP })
  local widest = 0

  -- Loot threshold: a label and the dropdown on one line.
  f.lootRow = CreateFrame("Frame", nil, f.content)
  f.lootLabel = ui.MakeLabel(f.lootRow, "normal", "text")
  f.lootLabel:SetText("Record loot:")
  f.lootLabel:SetPoint("LEFT", f.lootRow, "LEFT", 0, 0)
  -- The client's own dropdown where it has one, sized to the widest choice.
  f.loot = ui.MakeDropdown(f.lootRow, { host = f, native = true, textWidth = WidestQualityText() })
  f.loot:SetPoint("LEFT", f.lootLabel, "RIGHT", 8, 0)
  f.loot.provider = QualityItems
  f.loot.onSelect = function(quality)
    Set("lootQuality", quality)
  end
  stack:Add(f.lootRow, math.max(20, f.loot:GetHeight()), true)
  widest = f.lootLabel:GetStringWidth() + 8 + f.loot:GetWidth()

  f.checks = {}
  for i = 1, #settings.CHECKS do
    local spec = settings.CHECKS[i]
    local check = ui.MakeCheckBox(f.content, spec.label)
    check.onToggle = function(checked)
      Set(spec.key, checked)
    end
    stack:Add(check, check:GetHeight())
    f.checks[spec.key] = check
    widest = math.max(widest, check:GetWidth())
  end

  f.note = ui.MakeLabel(f.content, "small", "textDim")
  f.note:SetJustifyH("LEFT")
  stack:Add(f.note, 10, true)
  widest = math.max(widest, ui.TextWidth("small", settings.APPLIED), ui.TextWidth("small", settings.LOCKED))

  -- The window is as large as what is in it: measured, so a longer label widens it.
  local height = stack:Height()
  f.content:SetHeight(height)
  f:SetSize(widest + 2 * PAD + 2 * f.inset, f.headHeight + CONTENT_GAP + height + BOTTOM + f.inset)
  -- The main window's Settings side tab is lit while this window is open, however it closes.
  f:HookScript("OnShow", function()
    GM.main.SettingsShown(true)
  end)
  f:HookScript("OnHide", function()
    GM.main.SettingsShown(false)
  end)
  return f
end

function settings.Paint()
  local f = settings.frame
  if not f or not f:IsShown() then
    return
  end
  local locked = GM.db.locked
  f.loot:Refresh(settings.QualityText(GM.db.Setting("lootQuality")))
  f.loot:SetEnabled(not locked)
  for key, check in pairs(f.checks) do
    check:SetChecked(GM.db.Setting(key))
    check:SetEnabled(not locked)
  end
  ui.SetColor(f.note, locked and "loss" or "textDim")
  ui.Fit(f.note, locked and settings.LOCKED or settings.APPLIED, f.note:GetWidth())
end

function settings.Show()
  local f = settings.frame
  if not f then
    f = Build()
    settings.frame = f
  end
  f:ClearAllPoints()
  -- Beside the main window when that is open, past its side tabs, else in the middle of the
  -- screen.
  local beside = GM.main.frame and GM.main.frame:IsShown() and GM.main.frame
  if beside then
    f:SetPoint("TOPLEFT", beside.sideTabs or beside, "TOPRIGHT", BESIDE_GAP, 0)
  else
    f:SetPoint("CENTER")
  end
  f:Show()
  settings.Paint()
end

function settings.Toggle()
  if settings.frame and settings.frame:IsShown() then
    settings.frame:Hide()
    return
  end
  settings.Show()
end
