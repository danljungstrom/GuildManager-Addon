-- Guildion -- export/payload.lua
-- session -> schema v1 table -> JSON -> zlib -> base64 -> "GM1:...". The contract lives in
-- docs/ADDON.md and lib/addon/payload.schema.ts; addon/tests/fixtures/*.gm1.txt prove both
-- sides agree.
local _, GM = ...

GM.payload = {}
local payload = GM.payload
local json = GM.json
local LibDeflate = LibStub("LibDeflate")

payload.SCHEMA_VERSION = 1
payload.PREFIX = "GM1:"
payload.MAX_LENGTH = 256 * 1024 -- the app refuses longer strings before decoding

local function Players(s)
  local rows = {}
  for i = 1, #s.players do
    local p = s.players[i]
    rows[i] = { n = p.n, c = p.c, lvl = GM.util.Clamp(p.lvl, 1, 100), guild = p.guild and true or false }
  end
  return json.Array(rows)
end

local function Presence(s, stop)
  local rows = {}
  for i = 1, #s.presence do
    local row = s.presence[i]
    rows[i] = { p = row.p - 1, from = row.from, to = row.to or math.max(row.from, stop) }
  end
  return json.Array(rows)
end

local function ZeroBased(indexes)
  local list = {}
  for i = 1, #indexes do
    list[i] = indexes[i] - 1
  end
  return json.Array(list)
end

-- A pull still in progress has no result yet and is left out. It can only be the last row,
-- so the loot rows' encounter indexes stay right.
local function Encounters(s)
  local rows = {}
  for i = 1, #s.encounters do
    local pull = s.encounters[i]
    if pull.stop then
      rows[#rows + 1] = {
        id = pull.id,
        name = pull.name,
        inst = pull.inst,
        size = pull.size,
        start = pull.start,
        ["end"] = pull.stop,
        kill = pull.kill and true or false,
        roster = ZeroBased(pull.roster),
      }
    end
  end
  return json.Array(rows)
end

local function Loot(s)
  local rows = {}
  for i = 1, #s.loot do
    local row = s.loot[i]
    rows[i] = { t = row.t, p = row.p - 1, item = row.item, qty = row.qty, enc = row.enc and (row.enc - 1) or json.null }
  end
  return json.Array(rows)
end

local function Instances(s)
  local rows = {}
  for i = 1, #s.instances do
    rows[i] = { id = s.instances[i].id, name = s.instances[i].name, at = s.instances[i].at }
  end
  return json.Array(rows)
end

-- The Gargul awards of the session: what was recorded live, plus a sweep of Gargul's own
-- history for the same window (record/gargul.lua). Copied row by row, because json.Array sets a
-- metatable and the stored rows live in SavedVariables, which holds no metatables. nil when
-- there is nothing to carry, so a log recorded without Gargul is no larger than before.
local function Awards(s, stop)
  local rows = GM.gargul.Awards(s, s.start, stop)
  if #rows == 0 then
    return nil
  end
  local out = {}
  for i = 1, #rows do
    local award = {}
    for key, value in pairs(rows[i]) do
      award[key] = value
    end
    local rolls = {}
    for r = 1, #rows[i].Rolls do
      rolls[r] = rows[i].Rolls[r]
    end
    award.Rolls = json.Array(rolls)
    out[i] = award
  end
  return json.Array(out)
end

-- Which Gargul the bridge read, or null when none was found. The app shows nothing for it: it
-- is there so a silent format change can be told apart from a raid where nothing was awarded.
local function GargulInfo()
  local version = GM.gargul.Version()
  if not version then
    return json.null
  end
  return { version = version }
end

-- When the exported session ends. Only the session the addon is recording is still running: one
-- with no stop that nothing records is a session the client died in the middle of, and it ends
-- where it was last seen, which is the span its row in the window shows. Reading a missing stop
-- as "still open" would date a raid from last year to today and count every hour since then as
-- time the raid was present.
local function EndsAt(s, now)
  if s.stop then
    return s.stop
  end
  if GM.session and GM.session.Current() == s then
    return now or GM.util.Now()
  end
  return s.lastSeen or s.start
end

-- The schema v1 table for a stored session. The session being recorded is exported as if it
-- ended at `now`.
function payload.Build(s, now)
  local stop = math.max(EndsAt(s, now), s.start)
  return {
    v = payload.SCHEMA_VERSION,
    addon = s.addon,
    interface = s.interface,
    realm = s.realm,
    guild = s.guild,
    recorder = s.recorder,
    session = { id = s.id, start = s.start, ["end"] = stop, instances = Instances(s) },
    players = Players(s),
    presence = Presence(s, stop),
    encounters = Encounters(s),
    loot = Loot(s),
    awards = Awards(s, stop),
    gargul = GargulInfo(),
  }
end

-- The uncompressed JSON (/gc export raw).
function payload.Json(s, now)
  return json.Encode(payload.Build(s, now))
end

-- Any payload table as the string the officer pastes into the app, or nil and a reason.
-- `what` names it in the refusal ("log", "guild roster").
function payload.Encode(tbl, what)
  local text = payload.PREFIX .. GM.base64.Encode(LibDeflate:CompressZlib(json.Encode(tbl)))
  if #text > payload.MAX_LENGTH then
    return nil, "the " .. what .. " is too large to export (" .. GM.util.FormatBytes(#text) .. ")."
  end
  return text
end

-- The string the officer pastes into the app, or nil and a reason.
function payload.Export(s, now)
  return payload.Encode(payload.Build(s, now), "log")
end
