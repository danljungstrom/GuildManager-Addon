-- Guildion -- ui/options.lua
-- The entry in the game's own settings (Esc > Options > AddOns): a page that says what the
-- addon is and opens its windows. The settings themselves stay in the addon's settings window,
-- so there is one place that paints and writes them; this page only leads there.
--
-- Registered with the Settings API (1.15 and later); a client without it gets the old
-- interface options list, and a client with neither gets no entry and loses nothing else.
local _, GM = ...

GM.options = {}
local options = GM.options
local ui = GM.ui

options.NAME = "GuildionOptionsPanel"
options.TITLE = "Guildion"
options.ABOUT = "Records a raid and exports it for the Guildion web app."

local INSET = 16

-- The game's settings window covers the screen's middle; it goes, so the window opened from
-- here is not hidden behind it.
local function CloseGameSettings()
  if SettingsPanel and SettingsPanel:IsShown() then
    HideUIPanel(SettingsPanel)
  elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
    HideUIPanel(InterfaceOptionsFrame)
  end
end

local function Build()
  local p = CreateFrame("Frame", options.NAME)
  p:Hide()

  p.title = ui.MakeLabel(p, "large", "accent")
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", INSET, -INSET)
  p.title:SetText(options.TITLE .. " " .. GM.version)

  p.about = ui.MakeLabel(p, "normal", "textDim")
  p.about:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -8)
  p.about:SetText(options.ABOUT)

  p.settings = ui.MakePanelButton(p, "primary")
  ui.FitButton(p.settings, "Open settings", { min = 120 })
  p.settings:SetPoint("TOPLEFT", p.about, "BOTTOMLEFT", 0, -14)
  p.settings:SetScript("OnClick", function()
    CloseGameSettings()
    GM.settings.Show()
  end)

  p.window = ui.MakePanelButton(p, "quiet")
  ui.FitButton(p.window, "Open the window", { min = 120 })
  p.window:SetPoint("LEFT", p.settings, "RIGHT", 8, 0)
  p.window:SetScript("OnClick", function()
    CloseGameSettings()
    GM.main.Show()
  end)

  p.hint = ui.MakeLabel(p, "small", "textDim")
  p.hint:SetPoint("TOPLEFT", p.settings, "BOTTOMLEFT", 0, -10)
  p.hint:SetText("Also " .. GM.COMMAND .. ", and the minimap button.")
  return p
end

-- Which API took the page: "settings", "interface" or nil (none was there).
function options.Register()
  if options.panel then
    return options.via
  end
  local p = Build()
  options.panel = p
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    options.category = Settings.RegisterCanvasLayoutCategory(p, options.TITLE)
    Settings.RegisterAddOnCategory(options.category)
    options.via = "settings"
  elseif InterfaceOptions_AddCategory then
    p.name = options.TITLE
    InterfaceOptions_AddCategory(p)
    options.via = "interface"
  end
  return options.via
end

GM.OnLoad(options.Register)
