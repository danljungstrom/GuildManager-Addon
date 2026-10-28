-- Guildion -- core/db.lua
-- SavedVariables: defaults, versioned migration, settings. GuildionDB is account-wide
-- and is nil until ADDON_LOADED, so everything here runs through GM.OnLoad.
local _, GM = ...

GM.db = {}
local db = GM.db

-- The window's settings and its saved size (0.2.0) are additive: ApplyDefaults fills them into
-- data written by 0.1.0, so the version stays 1. A bump would lock the data for a player who
-- goes back to 0.1.0 after a bad first run of the window.
db.VERSION = 1

-- Defaults must not contain arrays with entries: they would be merged by index.
db.DEFAULTS = {
  settings = {
    lootQuality = 3, -- 3 = Rare: record Rare and better
    autoRecord = true,
    debugDungeon = false, -- also record in a party inside a 5-man dungeon
    minimapButton = true,
    minimapAngle = 220, -- degrees around the minimap, 0 = east, counter-clockwise
    promptExport = true, -- open the window when a raid ends
  },
  window = { width = 560, height = 420 }, -- plus `point` once the player has moved it
  sessions = {},
}

-- db.MIGRATIONS[n] upgrades the data from version n to n + 1, in place.
db.MIGRATIONS = {}

-- Fills missing keys in `target` from `defaults`, recursively. Never overwrites.
function db.ApplyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      db.ApplyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

local function Migrate(data, from)
  for version = from, db.VERSION - 1 do
    local step = db.MIGRATIONS[version]
    if step then
      step(data)
    end
  end
end

function db.Init()
  if type(GuildionDB) ~= "table" then
    GuildionDB = {}
  end
  local data = GuildionDB
  -- A hand-edited file can hold anything: a version that is not a number would make the
  -- comparison below throw, halfway through Init, and wedge every event after it.
  local stored = tonumber(data.version) or 0

  db.data = data
  db.locked = stored > db.VERSION
  if db.locked then
    -- Written by a newer addon. Its shape is unknown: leave it alone and record nothing.
    GM.Print("saved data is from a newer version (v" .. stored .. "). Update the addon; recording is off.")
    return
  end

  if stored > 0 then
    Migrate(data, stored)
  end
  db.ApplyDefaults(data, db.DEFAULTS)
  data.version = db.VERSION
end

-- Per-key rules on top of the type check below. The file is plain text the player can edit,
-- so a value is made safe where it is read, never trusted because it was stored.
local RANGE = {
  lootQuality = function(n)
    return GM.util.Clamp(math.floor(n), 2, 5) -- 2 Uncommon .. 5 Legendary
  end,
  minimapAngle = function(n)
    return n % 360
  end,
}

-- `value` as a safe value for `key`, or nil when it is no value for this key at all: the
-- wrong type, or a number that is not finite (a file holding "1e999", and `% 360` on that is
-- a NaN). Both of those pass a plain type() check.
local function Coerce(key, value)
  local default = db.DEFAULTS.settings[key]
  if type(default) == "number" then
    value = tonumber(value)
    if not GM.util.IsFinite(value) then
      return nil
    end
  elseif type(value) ~= type(default) then
    return nil
  end
  if RANGE[key] then
    return RANGE[key](value)
  end
  return value
end

-- The same, with the default as the answer for anything that is not a value: what a READ of a
-- hand-edited file must do, because the window has to show something.
local function Normalise(key, value)
  local safe = Coerce(key, value)
  if safe == nil then
    return db.DEFAULTS.settings[key]
  end
  return safe
end

-- Locked data was written by a newer addon: its settings may mean something else by now, so
-- the defaults answer.
function db.Setting(key)
  local settings = not db.locked and db.data and db.data.settings
  if type(settings) ~= "table" then
    return db.DEFAULTS.settings[key]
  end
  return Normalise(key, settings[key])
end

-- Stores a setting. Refused (false) for a key this addon does not know, for a value that is
-- none for that key, and while the saved data is locked. A wrong value is NOT stored as the
-- default: that would answer true while quietly turning a stored `false` into `true`.
function db.SetSetting(key, value)
  if db.locked or not db.data or db.DEFAULTS.settings[key] == nil then
    return false
  end
  local safe = Coerce(key, value)
  if safe == nil then
    return false
  end
  db.data.settings[key] = safe
  return true
end

-- The nine anchor names SetPoint takes. Any other string is a Lua error inside the window's
-- build, which leaves /gc dead for every session after the file was touched.
local POINTS = {
  TOPLEFT = true,
  TOP = true,
  TOPRIGHT = true,
  LEFT = true,
  CENTER = true,
  RIGHT = true,
  BOTTOMLEFT = true,
  BOTTOM = true,
  BOTTOMRIGHT = true,
}

-- A saved point is { point, relativePoint, x, y } against the screen.
local function ValidPoint(point)
  if type(point) ~= "table" or not POINTS[point[1]] or not POINTS[point[2]] then
    return false
  end
  return GM.util.IsFinite(point[3]) and GM.util.IsFinite(point[4])
end

-- The window's saved size and place: { width, height, point or nil }, always usable numbers.
-- ui/main.lua clamps them to the screen and to its own minimum.
function db.Window()
  local stored = not db.locked and db.data and db.data.window
  if type(stored) ~= "table" then
    stored = {}
  end
  local default = db.DEFAULTS.window
  return {
    width = GM.util.IsFinite(stored.width) and stored.width or default.width,
    height = GM.util.IsFinite(stored.height) and stored.height or default.height,
    point = ValidPoint(stored.point) and { stored.point[1], stored.point[2], stored.point[3], stored.point[4] } or nil,
  }
end

-- Stores what `fields` names (width, height, point) and keeps the rest. Refused while locked.
function db.SaveWindow(fields)
  if db.locked or not db.data then
    return false
  end
  local window = db.Window()
  db.data.window = {
    width = fields.width or window.width,
    height = fields.height or window.height,
    point = fields.point or window.point,
  }
  return true
end

GM.OnLoad(db.Init)
