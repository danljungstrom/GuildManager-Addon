-- Guildion -- ui/main.lua
-- The main window's shell: the client's chrome with our helmet as its portrait, the attic
-- (the chosen tab's name, the version and the recording mark), the side tabs down the right
-- edge (the views, then Settings), the status line, and the hooks the rest of ui/ builds into. It knows no tab by name:
-- ui/sessions.lua and ui/current.lua register themselves with main.AddTab, ui/strip.lua builds
-- the footer through main.OnBuild. The window is built on first use: a player who never opens
-- it pays nothing for it.
--
-- ui/ reads sessions only through record/session.lua's API and hears about changes through
-- session.OnChange. No recorder ever calls into ui/.
local _, GM = ...

GM.main = {}
local main = GM.main
local ui = GM.ui

main.NAME = "GuildionWindow"
main.MIN_W, main.MIN_H = 420, 280
-- Short enough to fit the status line at the smallest window: a line cut off in the middle is
-- the one line the player must not miss. main_test measures it.
main.LOCKED = "Saved data is from a newer version of the addon. Update it."

main.tabs = {} -- in AddTab order
main.active = nil -- the chosen tab's key

local builders, painters, layouts = {}, {}, {}
local status = { text = "", token = "textDim" }

-- tab = { key, label, icon, Build = fn(panel), Paint = fn(), Layout = fn() or nil,
--         Select = fn(sessionId) or nil, buttons = { spec, ... } or nil }
-- icon is the texture on the tab's side tab; label is its tooltip and the attic's heading.
-- Build runs once, when the window is built; Paint whenever the tab is on screen and something
-- changed; Layout after a resize; Select when main.Reveal names a session. `buttons` are the
-- tab's actions in the footer; ui/strip.lua describes a spec.
function main.AddTab(tab)
  main.tabs[#main.tabs + 1] = tab
end

-- fn(window) runs once when the window is built, after the tabs. For parts of the window
-- that are not a tab (the footer strip).
function main.OnBuild(fn)
  builders[#builders + 1] = fn
end

-- fn() runs on every paint, after the active tab's own Paint.
function main.OnPaint(fn)
  painters[#painters + 1] = fn
end

-- fn() runs after a resize, after the tabs' own Layout.
function main.OnLayout(fn)
  layouts[#layouts + 1] = fn
end

local function Tab(key)
  for i = 1, #main.tabs do
    if main.tabs[i].key == key then
      return main.tabs[i]
    end
  end
  return nil
end

-- The chosen tab's table, or nil before the window was first shown.
function main.ActiveTab()
  return Tab(main.active)
end

local function Each(list)
  for i = 1, #list do
    list[i]()
  end
end

-- The line above the footer: what just happened, or what to do next. token is a theme
-- colour (default textDim; "loss" for a refusal). While the saved data is locked the line is
-- taken: the player must not miss why nothing works.
function main.SetStatus(text, token)
  status.text, status.token = text or "", token or "textDim"
  main.Paint()
end

-- What the status line says now, whatever put it there. ui/strip.lua asks before taking its
-- own line away, so it never wipes something that happened since.
function main.StatusText()
  return status.text
end

local function PaintStatus(f)
  local text, token = status.text, status.token
  if GM.db.locked then
    text, token = main.LOCKED, "loss"
  end
  ui.SetColor(f.status, token)
  ui.Fit(f.status, text, f.status:GetWidth())
end

local function PaintMeta(f)
  if GM.session.Current() then
    f:SetMeta("v" .. GM.version .. "  recording", "profit")
  else
    f:SetMeta("v" .. GM.version)
  end
end

local ticking = false
local ArmTicker

-- A recording has clocks on screen (the session's length, the pull in progress), so the
-- window repaints once a second while it is open and a session is. No session, no timer.
local function Tick()
  ticking = false
  if not main.frame:IsShown() then
    return
  end
  main.Paint()
end

function ArmTicker()
  if ticking or not GM.session.Current() then
    return
  end
  ticking = true
  C_Timer.After(1, Tick)
end

function main.Paint()
  local f = main.frame
  if not f or not f:IsShown() then
    return
  end
  PaintMeta(f)
  PaintStatus(f)
  local tab = Tab(main.active)
  if tab and tab.Paint then
    tab.Paint()
  end
  Each(painters)
  ArmTicker()
end

local pending = false

-- session.OnChange fires on every roster event. The window notes that something changed and
-- repaints once, on the next frame; hidden, it does not even do that.
function main.RequestPaint()
  if pending or not main.frame or not main.frame:IsShown() then
    return
  end
  pending = true
  C_Timer.After(0, function()
    pending = false
    main.Paint()
  end)
end

function main.Layout()
  for i = 1, #main.tabs do
    if main.tabs[i].Layout then
      main.tabs[i].Layout()
    end
  end
  Each(layouts)
  main.Paint()
end

function main.SetTab(key)
  if not Tab(key) then
    return
  end
  local changed = main.active ~= key
  main.active = key
  for i = 1, #main.tabs do
    local tab = main.tabs[i]
    if tab.button then
      tab.button:SetActive(tab.key == key)
      tab.panel:SetShown(tab.key == key)
    end
  end
  -- The side tabs are icons; the chosen one's name is said where it reads without the mouse.
  main.frame:SetHeading(Tab(key).label)
  if changed then
    status.text, status.token = "", "textDim"
  end
  main.Paint()
end

-- How far below the window's top edge the first side tab hangs: clear of the title bar.
local SIDE_TOP = 40

-- The tabs go down the window's right edge, outside it, as the spellbook's do. Their column is
-- a frame of its own beside the window (f.sideTabs), raised to the window's level so the tab
-- art tucks under the window's border; a window opened beside this one goes beside the column.
local function BuildTabs(f)
  f.sideTabs = CreateFrame("Frame", nil, f)
  f.sideTabs:SetFrameLevel(f:GetFrameLevel())
  f.sideTabs:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
  f.sideTabs:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
  f.sideTabs:SetWidth(ui.SIDE_TAB.size)
  -- The window is clamped to the screen, but the column hangs outside it: widen the clamp to
  -- take the column in, or a window dragged to the right edge pushes the tabs off the screen.
  f:SetClampRectInsets(0, ui.SIDE_TAB.size, 0, 0)
  local stack = ui.Stack(f.sideTabs, { top = SIDE_TOP, gap = ui.SIDE_TAB.gap })
  for i = 1, #main.tabs do
    local tab = main.tabs[i]
    tab.button = ui.MakeSideTab(f.sideTabs, tab.icon, tab.label)
    tab.button:SetScript("OnClick", function()
      main.SetTab(tab.key)
    end)
    stack:Add(tab.button, ui.SIDE_TAB.size)
    tab.panel = CreateFrame("Frame", nil, f.body)
    tab.panel:SetAllPoints(f.body)
    tab.panel:Hide()
    tab.Build(tab.panel)
  end
  -- Settings, last in the column: it opens the settings window and changes nothing in this
  -- one, so it is never the chosen view. It is lit while that window is open
  -- (main.SettingsShown, which ui/settings.lua calls).
  f.settingsTab = ui.MakeSideTab(f.sideTabs, GM.theme.TEX.cog, "Settings")
  f.settingsTab:SetScript("OnClick", function()
    GM.settings.Toggle()
  end)
  stack:Add(f.settingsTab, ui.SIDE_TAB.size)
  f.settingsTab:SetActive(GM.settings and GM.settings.frame and GM.settings.frame:IsShown())
end

-- The settings window says when it opens and closes, so its side tab here lights with it.
function main.SettingsShown(shown)
  if main.frame then
    main.frame.settingsTab:SetActive(shown)
  end
end

local function Build()
  local f = ui.MakeWindow(main.NAME, {
    title = "Guildion",
    portrait = GM.theme.TEX.portrait,
    resizable = true,
    minW = main.MIN_W,
    minH = main.MIN_H,
    onMoved = function(point)
      GM.db.SaveWindow({ point = point })
    end,
    onResized = function(width, height)
      GM.db.SaveWindow({ width = width, height = height })
    end,
  })
  f:Place(GM.db.Window())


  -- Bottom up: the footer on the window's edge, the status line on the footer, and the body
  -- takes what is left between the head and the status line. Every piece hangs off its
  -- neighbour, so a resize needs no arithmetic. The footer stops short of the resize grip.
  f.footer = CreateFrame("Frame", nil, f)
  f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", f.inset, f.inset)
  f.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -f.inset - 8, f.inset)
  f.footer:SetHeight(22)
  f.status = ui.MakeLabel(f, "small", "textDim")
  f.status:SetPoint("BOTTOMLEFT", f.footer, "TOPLEFT", 2, 5)
  f.status:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", -2, 5)
  f.status:SetJustifyH("LEFT")
  f.body = CreateFrame("Frame", nil, f)
  BuildTabs(f)
  f.body:SetPoint("TOPLEFT", f.titleBar, "BOTTOMLEFT", 0, -6)
  f.body:SetPoint("BOTTOMRIGHT", f.status, "TOPRIGHT", 2, 5)
  for i = 1, #builders do
    builders[i](f)
  end

  f:HookScript("OnSizeChanged", main.Layout)
  f:HookScript("OnShow", main.Paint)
  -- The status line says what just happened. Nothing just happened when the window comes back,
  -- so it does not come back with it. (After the builders: the strip clears its own line first.)
  f:HookScript("OnHide", function()
    status.text, status.token = "", "textDim"
  end)
  return f
end

-- The window is published only once Build ran to the end: a tab that throws halfway would
-- otherwise leave a shell on main.frame that every later /gc shows and every export writes
-- into. Nothing beats the next attempt building it again.
function main.Show()
  local f = main.frame
  if not f then
    f = Build()
    main.frame = f
  end
  if not main.active and main.tabs[1] then
    -- First opening: straight to the live view when there is one.
    main.SetTab((GM.session.Current() and Tab("current")) and "current" or main.tabs[1].key)
  end
  f:Show()
end

function main.Toggle()
  if main.frame and main.frame:IsShown() then
    main.frame:Hide()
    return
  end
  main.Show()
end

-- Opens the window on a tab and, when the tab can, on one session.
function main.Reveal(key, sessionId)
  main.Show()
  main.SetTab(key)
  local tab = Tab(key)
  if tab and tab.Select and sessionId then
    tab.Select(sessionId)
  end
end

-- ---------------------------------------------------------------------------
-- The prompt to export: a raid ended, here is its log
-- ---------------------------------------------------------------------------

main.PROMPT = "Raid logged. Export copies it for the raid page."

local waiting -- the session the prompt is held back for while the player is in combat

-- Not for a session the resume path closed (one that went stale while the player was offline:
-- record/session.lua says "resume"), and not for one with nothing in it (a Start and Stop to
-- try the addon out). A raid that really ends in the first seconds after a /reload does prompt.
local function WorthPrompting(s, why)
  if why == "resume" or not GM.db.Setting("promptExport") then
    return false
  end
  return #s.players > 1 or #s.encounters > 0
end

-- Opens the window on the session's row. It never takes the keyboard: the raid may have
-- ended in the middle of a sentence the player is typing.
local function Prompt(id)
  if InCombatLockdown() then
    waiting = id
    return
  end
  waiting = nil
  -- Read again here, not only where the session closed: a prompt held back for a long fight
  -- fires minutes later, and the setting may have been turned off in between.
  if not GM.db.Setting("promptExport") then
    return
  end
  if not GM.session.Find(id) then
    return
  end
  -- Mid-copy the player is one Ctrl+C away from the string they asked for: moving the tab or
  -- the chosen row under them would close the box and throw that away. The line says the raid
  -- was logged; the row is one click away when they are done.
  if GM.strip.mode == "copy" then
    main.SetStatus(main.PROMPT)
    return
  end
  main.Reveal("sessions", id)
  main.SetStatus(main.PROMPT)
end

-- The player exported the session themselves while the prompt waited for combat to end: there
-- is nothing left to offer them. ui/strip.lua says so.
function main.Exported(id)
  if waiting == id then
    waiting = nil
  end
end

GM.RegisterEvent("PLAYER_REGEN_ENABLED", function()
  if waiting then
    Prompt(waiting)
  end
end)

GM.session.OnChange(function(s, what, why)
  if what == "close" and WorthPrompting(s, why) then
    Prompt(s.id)
  end
  main.RequestPaint()
end)
