-- Guildion -- record/loot.lua
-- Loot rows from CHAT_MSG_LOOT. The chat line is localized, so the patterns are built from
-- the client's own format strings (LOOT_ITEM and friends), never from English text.
local _, GM = ...

GM.loot = {}
local loot = GM.loot
local util = GM.util

loot.ATTACH_SECONDS = 300 -- loot within 5 minutes of a pull's end belongs to that pull

-- Turns a printf-style format ("%s receives loot: %sx%d.") into an anchored Lua pattern
-- plus the argument position of each capture. Handles positional arguments ("%2$s"), which
-- some locales use to reorder the sentence.
-- The directive at `i`: its last byte, the argument it names (nil when it names none) and
-- "s" or "d". "%2$s" is the second argument; "%3d" is a width, and the argument is simply the
-- next one in order.
local function Directive(format, i)
  local _, stop, position, kind = string.find(format, "^%%(%d+)%$([sd])", i)
  if stop then
    return stop, tonumber(position), kind
  end
  local plain
  _, stop, plain = string.find(format, "^%%[%-%+ #0]*%d*%.?%d*([sd])", i)
  if stop then
    return stop, nil, plain
  end
  return nil
end

function loot.PatternFromFormat(format)
  local parts, order = { "^" }, {}
  local i = 1
  while i <= #format do
    local stop, position, kind = Directive(format, i)
    if stop then
      order[#order + 1] = position or (#order + 1)
      parts[#parts + 1] = kind == "d" and "(%d+)" or "(.+)"
      i = stop + 1
    elseif string.sub(format, i, i + 1) == "%%" then
      parts[#parts + 1] = "%%"
      i = i + 2
    else
      parts[#parts + 1] = (string.gsub(string.sub(format, i, i), "%p", "%%%0"))
      i = i + 1
    end
  end
  parts[#parts + 1] = "$"
  return table.concat(parts), order
end

-- Captures in argument order: Match("%2$s by %1$s", "X by Y") -> "Y", "X"
local function Match(text, pattern, order)
  local captures = { string.match(text, pattern) }
  if #captures == 0 then
    return nil
  end
  local args = {}
  for i = 1, #captures do
    args[order[i]] = captures[i]
  end
  return args
end

-- Most specific first: the single-item pattern also matches a "x2" line.
local SHAPES = {
  { global = "LOOT_ITEM_SELF_MULTIPLE", self = true },
  { global = "LOOT_ITEM_SELF", self = true },
  { global = "LOOT_ITEM_MULTIPLE", self = false },
  { global = "LOOT_ITEM", self = false },
}

local compiled

local function Compile()
  compiled = {}
  for i = 1, #SHAPES do
    local format = _G[SHAPES[i].global]
    if format then
      local pattern, order = loot.PatternFromFormat(format)
      compiled[#compiled + 1] = { pattern = pattern, order = order, self = SHAPES[i].self }
    end
  end
end

-- "Brisa receives loot: [link]x2." -> "Brisa", link, 2. The name is nil for the player's
-- own loot. nil when the line is not a loot line (rolls, money, "creates", ...).
function loot.Parse(text)
  if not compiled then
    Compile()
  end
  for i = 1, #compiled do
    local args = Match(text, compiled[i].pattern, compiled[i].order)
    if args and compiled[i].self then
      return nil, args[1], tonumber(args[2]) or 1
    elseif args then
      return args[1], args[2], tonumber(args[3]) or 1
    end
  end
  return nil
end

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

-- Item quality (0 poor .. 5 legendary): from the item cache, else from the link colour.
-- nil when neither knows.
function loot.Quality(link)
  local _, _, quality = GetItemInfo(link)
  if quality then
    return quality
  end
  -- Newer clients colour a link by quality instead of by hex: "|cnIQ4:|Hitem:...".
  local named = tonumber(string.match(link, "|cnIQ(%d+):"))
  if named then
    return named
  end
  local hex = string.match(link, "(|c%x%x%x%x%x%x%x%x)|Hitem:")
  for index, color in pairs(ITEM_QUALITY_COLORS) do
    if color.hex == hex then
      return index
    end
  end
  return nil
end

-- CHAT_MSG_LOOT: text, ... (the other arguments are not reliable for the looter's name)
function loot.OnChat(_, text)
  local s = GM.session.Current()
  if not s or #s.loot >= GM.LIMITS.loot then
    return
  end
  local name, link, qty = loot.Parse(text)
  local item = link and tonumber(string.match(link, "|Hitem:(%d+)"))
  if not item then
    return
  end
  -- An unknown quality is recorded: losing an epic is worse than keeping a green.
  local quality = loot.Quality(link)
  if quality and quality < GM.db.Setting("lootQuality") then
    return
  end

  name = name or util.StripRealm(util.UnitFullName("player"))
  local player = GM.roster.IndexOf(s, name)
  if not player then
    -- The looter may have joined since the last scan. While the client is still loading a
    -- name the scan answers nothing at all, and then the chat line is all there is: record the
    -- looter from it rather than lose an epic, and let a later scan fill in class and level.
    if GM.roster.Update(s) then
      player = GM.roster.IndexOf(s, name)
    else
      player = GM.roster.EnsureName(s, name)
    end
  end
  if not player then
    return
  end

  s.loot[#s.loot + 1] = {
    t = util.Now(),
    p = player,
    item = item,
    qty = util.Clamp(qty, 1, GM.LIMITS.qty),
    enc = GM.encounters.RecentlyEnded(s, loot.ATTACH_SECONDS),
  }
  GM.session.Touch(s)
end

GM.RegisterEvent("CHAT_MSG_LOOT", loot.OnChat)
