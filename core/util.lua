-- Guildion -- core/util.lua
-- Time, text and number helpers, and the payload limits the app enforces.
local _, GM = ...

GM.util = {}
local util = GM.util

-- Mirrors ADDON_LIMITS in lib/addon/payload.schema.ts key for key. The recorder
-- stops adding rows at these counts, so an export can never be rejected for its size.
GM.LIMITS = {
  players = 200,
  presence = 2000,
  encounters = 200,
  loot = 2000,
  instances = 20,
  rosterSize = 40,
  textBytes = 100,
  qty = 1000,
  awards = 500, -- Gargul awards the bridge carries in one log (record/gargul.lua)
  rollsPerAward = 40,
  guildMembers = 1000, -- members one guild roster snapshot carries (export/guild.lua)
  guildRanks = 20,
}

-- Unix seconds on the realm's clock. Never os.time(): the player's PC clock can be wrong.
function util.Now()
  return GetServerTime()
end

-- "Name-Realm" -> "Name". The payload carries bare names.
function util.StripRealm(name)
  return (string.match(name, "^([^-]+)")) or name
end

-- The full character name of a unit. WoW Forever names are "First Last", and there UnitName
-- returns the first name alone (the surname lands in the realm slot), while GetUnitName with
-- showRealm answers "First Last". On Classic Era a player of another realm reads "Name-Realm",
-- so callers that store the name still run it through StripRealm, as the raid path does.
function util.UnitFullName(unit)
  if GetUnitName then
    return GetUnitName(unit, true)
  end
  return (UnitName(unit))
end

-- A number that can be compared and printed. The SavedVariables file is plain text the player
-- can edit: "1e999" reads back as an infinity, arithmetic on it spreads NaN, and both pass
-- type(n) == "number". NaN compares false against every bound, so it slips through a clamp.
function util.IsFinite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function util.Clamp(n, lo, hi)
  if n ~= n then
    return lo -- NaN: neither test below would hold, and it would pass straight through
  end
  if n < lo then
    return lo
  end
  if n > hi then
    return hi
  end
  return n
end

-- Cuts text to at most maxBytes without splitting a UTF-8 sequence: the cut moves left
-- while the first dropped byte is a continuation byte (10xxxxxx).
function util.Truncate(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  local cut = maxBytes
  while cut > 0 do
    local dropped = string.byte(text, cut + 1)
    if dropped < 128 or dropped >= 192 then
      break
    end
    cut = cut - 1
  end
  return string.sub(text, 1, cut)
end

-- "812 B", "1.9 KB"
function util.FormatBytes(n)
  if n < 1024 then
    return string.format("%d B", n)
  end
  return string.format("%.1f KB", n / 1024)
end

-- How long a raid took: "45m", "2h 05m".
function util.FormatDuration(seconds)
  if not util.IsFinite(seconds) then
    seconds = 0
  end
  local minutes = math.floor(math.max(0, seconds) / 60)
  if minutes < 60 then
    return string.format("%dm", minutes)
  end
  return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

-- How long a pull took: "3:00", "12:05".
function util.FormatClock(seconds)
  if not util.IsFinite(seconds) then
    seconds = 0
  end
  seconds = math.max(0, seconds)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- What a row shows instead of a date it cannot have: a stored time that is missing or is not
-- a usable number. date() throws on those, and one bad session must not take the list with it.
util.NO_DATE = "unknown"

-- When a raid started, in the player's own time zone: "2026-09-16 18:00". Sorts as text.
function util.FormatDate(time)
  if not util.IsFinite(time) then
    return util.NO_DATE
  end
  return date("%Y-%m-%d %H:%M", time)
end
