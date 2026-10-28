-- Guildion -- core/init.lua
-- Bootstrap: the shared namespace, event dispatch, the OnLoad queue, chat output, slash
-- registration. Every other file starts with `local _, GM = ...` and hangs its module on GM.
local ADDON_NAME, GM = ...

_G.Guildion = GM

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

GM.name = ADDON_NAME
GM.version = GetMetadata(ADDON_NAME, "Version") or "dev"
-- The short slash command. Every text that names the command (chat lines, the help, the
-- window's status line) reads it from here, so renaming it, should another addon turn out to
-- own "/gc", is this one line. "/guildion" always works.
GM.COMMAND = "/gc"
GM.eventHandlers = {}
GM.loadQueue = {}
GM.loaded = false

function GM.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ADDON_NAME .. "|r: " .. tostring(msg))
end

-- How often each error message was seen this login. A stormable event would otherwise fill
-- the chat frame with the same line; the tally keeps the repeats reachable for a debug command.
GM.errors = {}

-- Every handler runs under pcall: one that throws must not stop the others from seeing the
-- event, and an error inside OnEvent would otherwise be swallowed by the client's error frame.
local function Safely(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then
    return
  end
  local message = tostring(err)
  local seen = (GM.errors[message] or 0) + 1
  GM.errors[message] = seen
  if seen == 1 then
    GM.Print("error: " .. message)
  end
end

-- The same guard for callbacks that are not event handlers: record/session.lua tells the
-- window about changes through it, so a bug in ui/ can never stop a recorder mid-write.
GM.Safely = Safely

local frame = CreateFrame("Frame", ADDON_NAME .. "EventFrame")
GM.eventFrame = frame

frame:SetScript("OnEvent", function(_, event, ...)
  local list = GM.eventHandlers[event]
  if not list then
    return
  end
  for i = 1, #list do
    Safely(list[i], event, ...)
  end
end)

-- fn(event, ...) is called for every `event`; handlers run in registration order.
function GM.RegisterEvent(event, fn)
  local list = GM.eventHandlers[event]
  if not list then
    list = {}
    GM.eventHandlers[event] = list
    frame:RegisterEvent(event)
  end
  list[#list + 1] = fn
end

-- Runs fn once our SavedVariables exist (ADDON_LOADED for this addon), or at once if that
-- already happened. Before that moment GuildionDB is nil.
function GM.OnLoad(fn)
  if GM.loaded then
    Safely(fn)
    return
  end
  GM.loadQueue[#GM.loadQueue + 1] = fn
end

-- `id` becomes the SLASH_<id>N globals and the SlashCmdList key, so it must be unique across
-- every addon the player runs: use the uppercase addon name.
function GM.RegisterSlash(id, commands, fn)
  for i = 1, #commands do
    _G["SLASH_" .. id .. i] = commands[i]
  end
  SlashCmdList[id] = fn
end

-- Registered first, so the load queue runs before any ADDON_LOADED handler added later.
GM.RegisterEvent("ADDON_LOADED", function(_, addon)
  if addon ~= ADDON_NAME or GM.loaded then
    return
  end
  GM.loaded = true
  local queue = GM.loadQueue
  GM.loadQueue = {}
  for i = 1, #queue do
    Safely(queue[i])
  end
end)
