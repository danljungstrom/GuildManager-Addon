-- Guildion -- record/encounters.lua
-- One row per pull, from ENCOUNTER_START / ENCOUNTER_END, with a snapshot of who was there.
-- The ids are Blizzard's raw encounterID and instanceID; the app maps them to bosses.
local _, GM = ...

GM.encounters = {}
local encounters = GM.encounters
local util = GM.util

local function OpenPull(s)
  local pull = s.encounters[#s.encounters]
  if pull and not pull.stop then
    return pull
  end
  return nil
end

-- A pull that never got its ENCOUNTER_END (a disconnect mid-fight): a wipe that ended when
-- the session was last seen. `pull.seen` is that moment frozen by session.Resume, for a pull
-- a relog interrupted; without it the events since the relog would stretch the wipe.
local function CloseStalePull(s)
  local pull = OpenPull(s)
  if not pull then
    return
  end
  pull.stop = math.max(pull.start, pull.seen or s.lastSeen)
  pull.kill = false
end

-- The client can announce the end of a fight twice (a re-sync right after the first one). A
-- second END for the boss that just finished is that echo, not a second kill.
encounters.ECHO_SECONDS = 5

local function JustEnded(s, encounterID)
  local pull = s.encounters[#s.encounters]
  if not pull or not pull.stop or pull.id ~= encounterID then
    return false
  end
  return util.Now() - pull.stop <= encounters.ECHO_SECONDS
end

local function NewPull(s, encounterID, name, groupSize)
  if #s.encounters >= GM.LIMITS.encounters then
    return nil
  end
  local snapshot = GM.roster.Snapshot(s)
  local size = groupSize or 0
  if size < 1 then
    size = #snapshot
  end
  if not name or name == "" then
    name = "Unknown"
  end
  local pull = {
    id = encounterID,
    name = util.Truncate(name, GM.LIMITS.textBytes),
    inst = select(8, GetInstanceInfo()),
    size = util.Clamp(size, 1, GM.LIMITS.rosterSize),
    start = util.Now(),
    roster = snapshot,
  }
  s.encounters[#s.encounters + 1] = pull
  return pull
end

-- A START for the boss the open pull is already on is the client re-announcing that fight only
-- when it cannot be a new pull: while nothing interrupted the pull (no relog stamped it), or
-- right after the world came up, when the client repeats what was already running. Later than
-- that the raid really pulled the same boss again, and the pull the relog cut short is its own
-- wipe: a missed END must not glue two pulls into one row.
local function Reannounced(open)
  return not open.seen or GM.session.JustEntered()
end

-- The last pull, when the officer ended it by hand (MarkResult) and it was this encounter.
-- The game's own ENCOUNTER_END for that fight, if it still comes, replaces the officer's
-- result in the same row: the mark stands in for an event that went missing, it does not
-- compete with one that arrives.
local function MarkedPull(s, encounterID)
  local pull = s.encounters[#s.encounters]
  if pull and pull.manual and pull.id == encounterID then
    return pull
  end
  return nil
end

-- The Current tab's "Mark kill" and "Mark wipe": ends the open pull now, with the officer's
-- result. For a boss whose ENCOUNTER_END never fires. `manual` is an internal helper, like
-- `seen`; export/payload.lua never reads it. Returns whether there was a pull to end.
function encounters.MarkResult(kill)
  local s = GM.session.Current()
  local pull = s and OpenPull(s)
  if not pull then
    return false
  end
  pull.stop = math.max(pull.start, util.Now())
  pull.kill = kill and true or false
  pull.manual = true
  GM.session.Touch(s)
  return true
end

-- ENCOUNTER_START: encounterID, encounterName, difficultyID, groupSize
function encounters.OnStart(_, encounterID, name, _, groupSize)
  local s = GM.session.Current()
  if s then
    local open = OpenPull(s)
    if open and open.id == encounterID and Reannounced(open) then
      return
    end
    CloseStalePull(s) -- before Evaluate: the roster scan it triggers moves lastSeen
  end
  GM.session.Evaluate() -- opens a session when the zone events were missed
  s = GM.session.Current()
  if not s then
    return
  end
  if NewPull(s, encounterID, name, groupSize) then
    GM.session.Touch(s)
  end
end

-- ENCOUNTER_END: encounterID, encounterName, difficultyID, groupSize, success (1 = kill)
function encounters.OnEnd(_, encounterID, name, _, groupSize, success)
  local s = GM.session.Current()
  if not s then
    return
  end
  local pull = OpenPull(s)
  if not pull then
    -- Checked before the echo rule: a real end two seconds after the officer's mark is the
    -- result of that fight, not an echo of it.
    pull = MarkedPull(s, encounterID)
    if pull then
      pull.manual = nil
    elseif JustEnded(s, encounterID) then
      return
    end
  end
  if not pull or pull.id ~= encounterID then
    -- The start was never seen (the addon was enabled mid-fight): a zero-length row still
    -- records the result.
    CloseStalePull(s)
    pull = NewPull(s, encounterID, name, groupSize)
  end
  if not pull then
    return
  end
  pull.stop = util.Now()
  pull.kill = success == 1 or success == true
  GM.session.Touch(s)
end

-- Index of the newest kill that ended at most `seconds` ago, else nil. Loot comes off a dead
-- boss: a wipe in between (the next boss pulled before the corpse was looted) is passed over,
-- and trash loot after a wipe attaches to nothing.
function encounters.RecentlyEnded(s, seconds)
  for i = #s.encounters, 1, -1 do
    local pull = s.encounters[i]
    if pull.stop then
      if util.Now() - pull.stop > seconds then
        return nil
      end
      if pull.kill then
        return i
      end
    end
  end
  return nil
end

GM.RegisterEvent("ENCOUNTER_START", encounters.OnStart)
GM.RegisterEvent("ENCOUNTER_END", encounters.OnEnd)
