-- Guildion -- record/roster.lua
-- Reads the group, keeps the session's player table, and turns joins and leaves into
-- presence intervals. "Present" means in the group, online or not.
local _, GM = ...

GM.roster = {}
local roster = GM.roster
local util = GM.util

-- Derived lookups for one session, rebuilt from the stored rows whenever another session
-- table shows up (a new session, or the same one after a /reload). Never saved.
local cache = { session = nil, byName = {}, open = {} }

-- The app treats names as unique ignoring case. string.lower folds ASCII only, which is
-- enough: the game itself capitalises names one way.
local function Key(name)
  return string.lower(name)
end

local function Cache(s)
  if cache.session == s then
    return cache
  end
  cache = { session = s, byName = {}, open = {} }
  for i = 1, #s.players do
    cache.byName[Key(s.players[i].n)] = i
  end
  for i = 1, #s.presence do
    if not s.presence[i].to then
      cache.open[s.presence[i].p] = i
    end
  end
  return cache
end

-- GetGuildInfo(unit) answers only for units the client can see, so false means "not seen
-- in the recorder's guild YET"; a later scan can still turn it true.
local function SameGuild(unit)
  local mine = GetGuildInfo("player")
  return mine ~= nil and GetGuildInfo(unit) == mine
end

-- One raid member, or nil while the client is still loading that row.
local function RaidMember(i, zone)
  local name, _, _, level, _, class, memberZone, online = GetRaidRosterInfo(i)
  if not name or name == UNKNOWNOBJECT then
    return nil
  end
  return {
    name = util.StripRealm(name),
    class = class,
    level = level,
    guild = SameGuild("raid" .. i),
    -- Right after a join, and for a moment after the recorder's own login, the client has the
    -- member but not their zone. Counting them as here keeps a pull's roster complete; the
    -- alternative drops a raider who really is standing on the boss.
    here = (online and (memberZone == nil or memberZone == zone)) and true or false,
  }
end

local function ScanRaid(skipUnloaded)
  local list = {}
  local zone = GetRealZoneText()
  for i = 1, GetNumGroupMembers() do
    local member = RaidMember(i, zone)
    if member then
      list[#list + 1] = member
    elseif not skipUnloaded then
      return nil
    end
  end
  return list
end

local function ScanUnits(units, skipUnloaded)
  local list = {}
  for i = 1, #units do
    local full = util.UnitFullName(units[i])
    local name = full and util.StripRealm(full)
    if not name or name == UNKNOWNOBJECT then
      if not skipUnloaded then
        return nil
      end
    else
      local _, class = UnitClass(units[i])
      list[#list + 1] = {
        name = name,
        class = class,
        level = UnitLevel(units[i]),
        guild = SameGuild(units[i]),
        here = UnitIsConnected(units[i]) and true or false,
      }
    end
  end
  return list
end

-- The group right now: { { name, class, level, guild, here } }, or nil while the client is
-- still loading names (another GROUP_ROSTER_UPDATE follows). `here` = online and in the
-- recorder's zone (raid), or online (party, where the API has no zone per member).
-- `skipUnloaded` answers with the members the client does know instead of nil.
function roster.Scan(skipUnloaded)
  if IsInRaid(GM.session.HOME) then
    return ScanRaid(skipUnloaded)
  end
  local units = { "player" }
  for i = 1, GetNumSubgroupMembers() do
    units[#units + 1] = "party" .. i
  end
  return ScanUnits(units, skipUnloaded)
end

-- The player's index, adding them when new. nil once the player table is full.
local function Ensure(s, c, member)
  local key = Key(member.name)
  local index = c.byName[key]
  if not index then
    if #s.players >= GM.LIMITS.players then
      return nil
    end
    index = #s.players + 1
    s.players[index] = { n = member.name, c = member.class or "UNKNOWN", lvl = member.level or 0, guild = false }
    c.byName[key] = index
  end

  local player = s.players[index]
  if member.class and player.c == "UNKNOWN" then
    player.c = member.class
  end
  if member.level and member.level > 0 then
    player.lvl = member.level -- offline members can report level 0
  end
  player.guild = player.guild or member.guild
  return index
end

-- Writes a scan into the session: a player row and an open interval per member. `closeMissing`
-- also ends the interval of everyone the scan did not list, which only a complete scan may do:
-- in a partial one a member the client has not loaded yet would look like a leaver.
local function Apply(s, list, closeMissing)
  local now = util.Now()
  local c = Cache(s)
  local seen = {}

  for i = 1, #list do
    local index = Ensure(s, c, list[i])
    if index then
      seen[index] = true
      if not c.open[index] and #s.presence < GM.LIMITS.presence then
        s.presence[#s.presence + 1] = { p = index, from = now }
        c.open[index] = #s.presence
      end
    end
  end

  if closeMissing then
    for index, row in pairs(c.open) do
      if not seen[index] then
        s.presence[row].to = math.max(now, s.presence[row].from)
        c.open[index] = nil
      end
    end
  end

  if s.guild == "" then
    s.guild = GetGuildInfo("player") or ""
  end
  GM.session.Touch(s)
end

-- A battleground or arena puts the recorder in a second, instance group, and the unit ids and
-- GetRaidRosterInfo answer for that one. Nothing in it belongs to the raid log.
local function InPvPInstance()
  local kind = select(2, IsInInstance())
  return kind == "pvp" or kind == "arena"
end

-- Diffs the group against the open presence intervals. Returns the scan, or nil when the
-- group could not be read (nothing is changed then).
function roster.Update(s)
  if InPvPInstance() then
    return nil
  end
  local list = roster.Scan()
  if not list then
    return nil
  end
  Apply(s, list, true)
  return list
end

-- The player's index, adding them from a name alone. For a looter the group scan has not
-- delivered yet: class and level stay unknown until a scan upgrades them. nil at the cap.
function roster.EnsureName(s, name)
  return Ensure(s, Cache(s), { name = util.StripRealm(name), guild = false })
end

-- Player indexes of everyone online and in the instance, ascending, at most 40: the roster
-- of a pull.
function roster.Snapshot(s)
  local list = roster.Update(s)
  if not list and not InPvPInstance() then
    -- A pull happens now and is snapshotted once. One member the client has not loaded yet
    -- must not turn the whole roster of the fight into an empty list, so the members it does
    -- know are recorded; the presence diff stays strict and runs again on the next event.
    list = roster.Scan(true) or {}
    Apply(s, list, false)
  end
  list = list or {}
  local c = Cache(s)
  local indexes = {}
  -- Two group members can share one player row (the same name on two realms), and the pull's
  -- roster is a list of player rows: each one belongs in it once.
  local added = {}
  for i = 1, #list do
    local index = c.byName[Key(list[i].name)]
    if list[i].here and index and not added[index] and #indexes < GM.LIMITS.rosterSize then
      added[index] = true
      indexes[#indexes + 1] = index
    end
  end
  table.sort(indexes)
  return indexes
end

function roster.IndexOf(s, name)
  return Cache(s).byName[Key(util.StripRealm(name))]
end

GM.session.OnRefresh(roster.Update)
