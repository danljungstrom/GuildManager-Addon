-- Guildion -- ui/strip.lua
-- The footer strip of the main window. One strip, three modes, one state machine:
--   "buttons"  the active tab's actions (tab.buttons),
--   "confirm"  a question with Yes and Cancel, for the one destructive action (Delete),
--   "copy"     the export string in a single-line edit box, selected, ready for Ctrl+C.
-- An addon cannot write to the clipboard. The only way out of the game is an edit box with
-- its text selected and the player pressing Ctrl+C, so "copy" is where an export ends.
-- Anything that closes the window, and any change of tab, puts the strip back to "buttons".
local _, GM = ...

GM.strip = {}
local strip = GM.strip
local ui = GM.ui

strip.mode = "buttons"
strip.COPIED = "%s selected, Ctrl+C, then paste on the raid page"

local host -- the window's footer frame
local shownFor -- the tab key the buttons were last laid out for
strip.confirmBar, strip.copyBar = {}, {} -- the widgets of the two other modes
local confirm, copy = strip.confirmBar, strip.copyBar

local function ActiveButtons()
  local tab = GM.main.ActiveTab()
  return tab and tab.buttons or {}
end

-- spec = { text, kind, onClick = fn(), enabled = fn() -> flag or nil }. The button is made
-- once per spec and kept on it: the client's red panel button, or one of ours of `kind` on a
-- client without it.
local function ButtonFor(spec)
  if not spec.button then
    spec.button = ui.MakePanelButton(host, spec.kind)
    ui.FitButton(spec.button, spec.text)
    spec.button:SetScript("OnClick", function()
      spec.onClick()
    end)
  end
  return spec.button
end

-- Hides everything that does not belong to `mode`, and only that: a hidden edit box gives the
-- keyboard and its selection back, and the layout runs again on every resize. Hiding the copy
-- box for an instant there would leave the status line promising a Ctrl+C that copies nothing.
local function HideOthers(mode)
  local keep = {}
  if mode == "buttons" then
    local specs = ActiveButtons()
    for i = 1, #specs do
      if specs[i].button then
        keep[specs[i].button] = true -- the other tabs' buttons still go
      end
    end
  end
  for i = 1, #GM.main.tabs do
    local specs = GM.main.tabs[i].buttons or {}
    for j = 1, #specs do
      if specs[j].button and not keep[specs[j].button] then
        specs[j].button:Hide()
      end
    end
  end
  if mode ~= "confirm" then
    confirm.question:Hide()
    confirm.yes:Hide()
    confirm.cancel:Hide()
  end
  if mode ~= "copy" then
    copy.back:Hide()
    copy.box:Hide()
  end
end

local function ShowIn(flow, how, widget, ...)
  flow[how](flow, widget, ...)
  widget:Show()
end

-- Places what the mode shows; everything else is hidden. Run again after a resize.
function strip.Layout()
  if not host then
    return
  end
  HideOthers(strip.mode)
  local flow = ui.Flow(host, { middle = true })
  if strip.mode == "confirm" then
    ShowIn(flow, "AddRight", confirm.cancel)
    ShowIn(flow, "AddRight", confirm.yes)
    if flow:Fill(confirm.question, 60) then
      ui.Fit(confirm.question, confirm.text, confirm.question:GetWidth())
      confirm.question:Show()
    else
      confirm.question:Hide() -- too narrow for it: the buttons alone, rather than a cut question
    end
    return
  end
  if strip.mode == "copy" then
    ShowIn(flow, "AddRight", copy.back)
    ShowIn(flow, "Fill", copy.box)
    return
  end
  local specs = ActiveButtons()
  for i = 1, #specs do
    ShowIn(flow, "Add", ButtonFor(specs[i]))
  end
end

-- The line strip.Copy put up, while it is still the one showing. Copy mode ends by many routes
-- (Back, ESC, another row, a change of tab, the window closing), and "… selected, Ctrl+C …"
-- with no box to copy from would be a lie on all but the first two.
local copyStatus

local function DropCopyStatus()
  if copyStatus and GM.main.StatusText() == copyStatus then
    GM.main.SetStatus("")
  end
  copyStatus = nil
end

local function SetMode(mode)
  local leavingCopy = strip.mode == "copy" and mode ~= "copy"
  strip.mode = mode
  if mode ~= "copy" and copy.box then
    copy.box:ClearFocus()
  end
  if leavingCopy then
    DropCopyStatus()
  end
  strip.Layout()
  strip.Paint()
end

-- Back to the tab's buttons. Safe to call at any time, in any mode.
function strip.Reset()
  confirm.onYes = nil
  SetMode("buttons")
end

-- Asks before something that cannot be undone. onYes runs only on the Yes button.
function strip.Confirm(question, yesText, onYes)
  confirm.text, confirm.onYes = question, onYes
  ui.FitButton(confirm.yes, yesText)
  SetMode("confirm")
end

local function Select(box)
  -- From the start: SetText leaves the cursor at the end of a string far wider than the
  -- box, scrolled out of sight. The player should see what they are about to copy.
  box:SetCursorPosition(0)
  box:HighlightText()
end

-- Shows `text` selected and focused, ready for Ctrl+C, and says so in the status line.
function strip.Copy(text, status)
  copy.text = text
  SetMode("copy")
  copy.box:SetText(text)
  Select(copy.box)
  copy.box:SetFocus()
  GM.main.SetStatus(status)
  copyStatus = status
end

-- Exports a session into the copy box: the GM1 string, or the plain JSON with raw. Opens the
-- window where the session lives. Returns true, or false and the reason (also shown).
function strip.Export(s, raw)
  local text, reason
  if raw then
    text = GM.payload.Json(s)
  else
    text, reason = GM.payload.Export(s)
  end
  -- Current is the live view, so only the session being recorded belongs there. A stale one
  -- (no stop, but nothing recording it any more) is a row on Sessions, which is where the
  -- player pressed Export; Current would answer them with "Not recording."
  GM.main.Reveal(s == GM.session.Current() and "current" or "sessions", s.id)
  if not text then
    GM.main.SetStatus(reason, "loss")
    return false, reason
  end
  strip.Copy(text, string.format(strip.COPIED, GM.util.FormatBytes(#text)))
  GM.main.Exported(s.id) -- a prompt still waiting for combat to end has nothing left to offer
  return true
end

strip.GUILD_COPIED = "%d members (%s) selected, Ctrl+C, then paste in the app"

local function WindowShown()
  return GM.main.frame and GM.main.frame:IsShown()
end

-- Reads the guild roster and puts the snapshot in the copy box, on the Sessions tab. The read
-- waits for the server, so the status line says so meanwhile. Whatever the player did in the
-- meantime (another tab, closing the window), the answer lands on Sessions; a success opens a
-- closed window, a failure then goes to chat only and leaves the window alone.
function strip.ExportGuild()
  GM.main.Reveal("sessions")
  strip.Reset()
  GM.main.SetStatus("Reading the guild roster…")
  GM.guild.Request(function(snap, why)
    local text, reason
    if snap then
      text, reason = GM.guild.Export(snap)
    else
      reason = why
    end
    if not text then
      if WindowShown() then
        GM.main.Reveal("sessions")
        GM.main.SetStatus(reason, "loss")
      else
        GM.Print(reason)
      end
      return
    end
    GM.main.Reveal("sessions")
    strip.Copy(text, string.format(strip.GUILD_COPIED, #snap.members, GM.util.FormatBytes(#text)))
  end)
end

-- Enabled states follow the data on every paint; a change of tab starts over.
function strip.Paint()
  if not host then
    return
  end
  if shownFor ~= GM.main.active then
    shownFor = GM.main.active
    strip.Reset()
    return
  end
  local specs = ActiveButtons()
  for i = 1, #specs do
    if specs[i].button and specs[i].enabled then
      specs[i].button:SetEnabled(specs[i].enabled() and true or false)
    end
  end
end

local function BuildConfirm()
  confirm.question = ui.MakeLabel(host, "small", "text")
  confirm.question:SetJustifyH("LEFT")
  confirm.yes = ui.MakePanelButton(host, "primary")
  confirm.yes:SetScript("OnClick", function()
    local onYes = confirm.onYes
    strip.Reset()
    if onYes then
      onYes()
    end
  end)
  confirm.cancel = ui.MakePanelButton(host, "quiet")
  ui.FitButton(confirm.cancel, "Cancel")
  confirm.cancel:SetScript("OnClick", strip.Reset)
end

local function BuildCopy()
  copy.back = ui.MakePanelButton(host, "quiet")
  ui.FitButton(copy.back, "Back")
  copy.back:SetScript("OnClick", strip.Reset)
  copy.box = ui.FlattenEditBox(CreateFrame("EditBox", nil, host, "BackdropTemplate"))
  copy.box:SetHeight(20)
  -- ESC with the box focused comes here and not to the window: one ESC leaves copy mode,
  -- the next one closes the window.
  copy.box:SetScript("OnEscapePressed", strip.Reset)
  -- Typing must not change the string: put it back and select it again.
  copy.box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(copy.text)
      Select(self)
    end
  end)
  -- A click inside the box drops the selection and leaves Ctrl+C with nothing to copy,
  -- while the status line still says the string is selected. Select it again.
  copy.box:SetScript("OnMouseUp", Select)
end

GM.main.OnBuild(function(f)
  host = f.footer
  BuildConfirm()
  BuildCopy()
  f:HookScript("OnHide", strip.Reset)
end)
GM.main.OnPaint(strip.Paint)
GM.main.OnLayout(strip.Layout)
