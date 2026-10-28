-- Guildion -- core/commands.lua
-- /gc and /guildion. Loaded last: it talks to every other module.
local _, GM = ...

GM.commands = {}
local commands = GM.commands

-- What follows GM.COMMAND on each help line.
local HELP = {
  ": open or close the window",
  " export: the newest raid log as a string to paste into the app",
  " export raw: the same log as plain JSON (debugging)",
  " export guild: the guild roster, to paste on the roster import page",
  " start: record now, whatever the group or zone",
  " stop: end the recording",
  " help: this list",
}

local function Status()
  local s = GM.session.Current()
  if not s then
    return "v" .. GM.version .. ", not recording, " .. #GM.session.All() .. " sessions stored."
  end
  local kills, wipes = GM.session.Counts(s)
  return string.format("v%s, recording: %d players, %d kills, %d wipes, %d loot.", GM.version, #s.players, kills, wipes, #s.loot)
end

-- Whether the Gargul bridge found anything to read, and how much it has. Gargul publishes no
-- API version and swallows a listener's errors, so an empty `awards` key looks exactly like a
-- raid where nothing was awarded: this line is the only early warning there is.
function commands.GargulStatus()
  if not GM.gargul.Available() then
    return "Gargul: not installed."
  end
  local s = GM.session.Current() or GM.session.Latest()
  local count = s and GM.gargul.Count(s) or 0
  return string.format("Gargul: v%s, %d awards recorded.", GM.gargul.Version() or "?", count)
end

function commands.Help()
  GM.Print(Status())
  GM.Print(commands.GargulStatus())
  for i = 1, #HELP do
    GM.Print(GM.COMMAND .. HELP[i])
  end
end

local function StringFor(s, raw)
  if raw then
    return GM.payload.Json(s)
  end
  return GM.payload.Export(s)
end

-- The window is where an export lands. When it cannot be built at all, the string must still
-- leave the game, and chat is no way out: the client's chat text cannot be selected with the
-- mouse. The only route is an edit box with its text highlighted, so this is Blizzard's own
-- one, built here on demand and needing nothing from ui/, which is what just failed.
local function RescueBox()
  if commands.rescueBox then
    return commands.rescueBox
  end
  local box = CreateFrame("EditBox", "GuildionRescueCopyBox", UIParent, "InputBoxTemplate")
  box:SetAutoFocus(false)
  -- Over everything: what brings this box up can fail with the main window (strata HIGH)
  -- already on screen, and a box behind that is a string the player cannot reach.
  box:SetFrameStrata("FULLSCREEN_DIALOG")
  box:SetFontObject("ChatFontNormal")
  box:SetMaxLetters(0) -- 0 = no limit: a cut export string decodes to nothing, silently
  box:SetSize(420, 24)
  box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    self:Hide()
  end)
  commands.rescueBox = box
  return box
end

-- Last resort for /gc export: say what went wrong, how large the log is, and put it where a
-- Ctrl+C reaches it.
local function Rescue(s, raw, err)
  local text, reason = StringFor(s, raw)
  if not text then
    GM.Print(reason or tostring(err))
    return
  end
  local box = RescueBox()
  box:SetText(text)
  box:SetCursorPosition(0)
  box:HighlightText()
  box:Show()
  box:SetFocus()
  GM.Print(string.format("the window could not be opened (%s). The log (%s) is in the box on screen: Ctrl+C, then ESC.", tostring(err), GM.util.FormatBytes(#text)))
end

-- Exports the session being recorded, else the newest stored one: the window opens where
-- that session lives, with the string in the footer's copy box (ui/strip.lua). A refusal is
-- said in chat too, for the player who typed the command with the window behind something.
function commands.Export(raw)
  local s = GM.session.Current() or GM.session.Latest()
  if not s then
    GM.Print("nothing recorded yet.")
    return
  end
  local ok, err = pcall(function()
    local shown, reason = GM.strip.Export(s, raw)
    if not shown then
      GM.Print(reason)
    end
  end)
  if not ok then
    Rescue(s, raw, err)
  end
end

-- These commands read or write the stored sessions, and while the saved data
-- comes from a newer addon their shape is unknown: db.lua left the file untouched, so there is
-- not even a session list. Same wording as the line db.Init prints at load.
local NEEDS_DATA = { export = true, ["export raw"] = true, start = true, stop = true }

-- What the player typed, as the command table spells it: lower case, no leading or trailing
-- whitespace, and runs of spaces inside collapsed, so "/gc export  raw" is "/gc export raw".
local function Normalise(msg)
  return (string.gsub(string.lower(strtrim(msg or "")), "%s+", " "))
end

local function Dispatch(input)
  if NEEDS_DATA[input] and GM.db.locked then
    GM.Print("saved data is from a newer version. Update the addon; recording is off.")
    return
  end
  if input == "" then
    GM.main.Toggle()
  elseif input == "help" then
    commands.Help()
  elseif input == "export" then
    commands.Export(false)
  elseif input == "export raw" then
    commands.Export(true)
  elseif input == "export guild" then
    GM.strip.ExportGuild()
  elseif input == "start" then
    GM.session.Start()
  elseif input == "stop" then
    GM.session.Stop()
  else
    GM.Print("unknown command: " .. input)
    commands.Help()
  end
end

-- A Lua error thrown inside a slash handler is hidden on this client unless the player turned
-- error reporting on, so a command that throws looks like a command that does nothing. Every
-- command is contained here and says, in one line, which command failed and why -- and that
-- the recording itself is safe, because that is the officer's first question.
function commands.Run(msg)
  local input = Normalise(msg)
  local ok, err = pcall(Dispatch, input)
  if ok then
    return
  end
  GM.Print(string.format("%s failed: %s. What was recorded is still stored.", strtrim(GM.COMMAND .. " " .. input), tostring(err)))
end

GM.RegisterSlash("GUILDION", { GM.COMMAND, "/guildion" }, commands.Run)
