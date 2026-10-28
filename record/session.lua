-- Guildion -- record/session.lua
-- The session lifecycle: open, close, resume, prune. A session is a plain table inside
-- GuildionDB.sessions (oldest first), so whatever was recorded survives a /reload, a
-- logout or a disconnect the moment it is written. ui/ (PR 4) reads sessions only through
-- this file.
--
-- A stored session (Lua indexes are 1-based here; export/payload.lua makes them 0-based):
--   id, start, stop (nil while open), lastSeen, manual, outsideSince,
--   addon, interface, realm, guild, recorder,
--   instances  = { { id, name, at } },
--   players    = { { n, c, lvl, guild } },
--   presence   = { { p, from, to } }            to is nil while the player is in the group
--   encounters = { { id, name, inst, size, start, stop, kill, roster = { p, ... } } }
--                 a pull a relog interrupted also carries `seen`, and one the officer ended
--                 by hand carries `manual`: internal helpers export/payload.lua never reads
--   loot       = { { t, p, item, qty, enc } }   enc is nil for trash loot
local _, GM = ...

GM.session = {}
local session = GM.session
local util = GM.util

session.IDLE_SECONDS = 1800 -- the 30 minute rules: outside an instance, and offline
session.KEEP = 20 -- sessions kept; older ones are pruned
session.LOGIN_GRACE = 10 -- seconds after the world comes up during which "not in a group" is not trusted
-- Seconds after the world comes up during which the client is still catching up on what was
-- already going on, so a repeated announcement is that catch-up and not something new.
session.ENTER_GRACE = 30

-- Every group question must name the HOME category: IsInRaid() and IsInGroup() with no
-- argument answer for the battleground raid too, and a player can queue one while the guild
-- raid goes on. record/roster.lua asks through this field. The constant is a FrameXML global;
-- 1 is its value, for a client that somehow does not define it.
session.HOME = LE_PARTY_CATEGORY_HOME or 1

local timerArmed = false
-- Both windows stay open until the anchor below sets their real deadline: between ADDON_LOADED
-- and the first PLAYER_ENTERING_WORLD the client is still loading, and nothing it reports about
-- the group or the fight can be trusted yet.
local graceUntil = math.huge
local enteredUntil = math.huge
-- This file is loaded once per login or /reload, so the flag is true for exactly the first
-- PLAYER_ENTERING_WORLD after it: the moment the world is really up.
local graceArmed = true
-- When this login resumed a session: the moment it was last seen before the relog. Cleared once
-- the recorder is seen in the group again. Until then nothing says the raid went on while they
-- were away, so a session the group no longer holds ends here, not at the login: the time
-- offline is not time anyone was in the raid.
local resumedSeen = nil
local listeners = {}

-- fn(s) runs whenever the open session should look at the world again: right after it
-- opened, and after every Evaluate that leaves it open. record/roster.lua hooks in here,
-- so this file knows nothing about the other recorders.
function session.OnRefresh(fn)
  listeners[#listeners + 1] = fn
end

local function Refresh(s)
  for i = 1, #listeners do
    listeners[i](s)
  end
end

local watchers = {}

-- fn(s, what, why) runs after every write to a session: what is "open", "touch" (a recorder
-- wrote something), "close" or "delete", and `why` names the path that did it when there is
-- more than one ("resume": a session found stale at load, closed where it was last seen).
-- This is how ui/ hears about changes, so no recorder ever calls into ui/. It fires often
-- (every roster event): a watcher should only note that something changed and repaint later.
function session.OnChange(fn)
  watchers[#watchers + 1] = fn
end

-- Under GM.Safely: a watcher that throws must not abort the recorder that was writing.
-- A watcher that WRITES (a repaint that touches the session) would be told about that write
-- too, and so on until the stack gives out, filling the chat with the same error. A nested
-- notification is therefore DROPPED, not queued: every watcher has already been told that this
-- session changed, and a repaint is about the session's state now, not about each write that
-- led to it, so nothing a watcher needs is lost.
local notifying = false

local function Changed(s, what, why)
  if notifying then
    return
  end
  notifying = true
  for i = 1, #watchers do
    GM.Safely(watchers[i], s, what, why)
  end
  notifying = false
end

-- The stored list, or nil when there is none to read: locked data was written by a newer addon
-- and never had this addon's defaults applied, so `sessions` can be missing entirely.
local function Sessions()
  local data = GM.db.data
  if GM.db.locked or not data or type(data.sessions) ~= "table" then
    return nil
  end
  return data.sessions
end

function session.All()
  return Sessions() or {}
end

function session.Find(id)
  local sessions = Sessions()
  if not sessions then
    return nil
  end
  for i = #sessions, 1, -1 do
    if sessions[i].id == id then
      return sessions[i]
    end
  end
  return nil
end

-- The session being recorded, or nil. Locked data was written by a newer addon: its shape is
-- unknown, so no recorder gets a table to write into.
function session.Current()
  local data = GM.db.data
  if GM.db.locked or not data or not data.activeId then
    return nil
  end
  return session.Find(data.activeId)
end

-- The newest session, open or closed.
function session.Latest()
  local sessions = Sessions()
  if not sessions then
    return nil
  end
  return sessions[#sessions]
end

-- Every recorder calls this after it wrote something.
function session.Touch(s)
  s.lastSeen = util.Now()
  Changed(s, "touch")
end

-- True while the world has just come up (and until it does). record/encounters.lua asks:
-- announcements that arrive in this window can be the client repeating what was already
-- running, not something that happened now.
function session.JustEntered()
  return util.Now() < enteredUntil
end

-- A stored session is whatever the file holds: the client can die between two writes, and the
-- file is plain text. Anything that reads one for the window goes through this, so a single
-- malformed session cannot throw on every repaint from now on.
local EMPTY = {}

local function List(t)
  if type(t) ~= "table" then
    return EMPTY
  end
  return t
end

-- Whether the session being recorded can still be written into. Reading one is always safe
-- (List above), but Close and Resume WRITE, and neither can do anything sensible with a
-- session whose lists or start time are gone.
local function Usable(s)
  return type(s.presence) == "table"
    and type(s.encounters) == "table"
    and type(s.instances) == "table"
    and type(s.players) == "table"
    and type(s.loot) == "table"
    and tonumber(s.start) ~= nil
end

-- Lets go of the session being recorded: no recorder can write into it any more, so holding on
-- to it would only bring the same error back at every load. The stored table is left exactly as
-- it is, for whoever wants to look at it, and the player is told once.
local function Release()
  GM.db.data.activeId = nil
  GM.Print("the session being recorded cannot be read and was let go. Nothing stored was changed.")
end

function session.Counts(s)
  local kills, wipes = 0, 0
  local encounters = List(s.encounters)
  for i = 1, #encounters do
    local pull = encounters[i]
    if pull.kill then
      kills = kills + 1
    elseif pull.stop then
      wipes = wipes + 1
    end
  end
  return kills, wipes
end

local function InGroup()
  return IsInRaid(session.HOME) or (GM.db.Setting("debugDungeon") and IsInGroup(session.HOME))
end

-- Inside an instance this session records: a raid, or a 5-man dungeon for the debug setting
-- and for a session the player started by hand.
local function InRecordedInstance(s)
  local inside, kind = IsInInstance()
  if not inside then
    return false
  end
  if kind == "raid" then
    return true
  end
  return kind == "party" and (GM.db.Setting("debugDungeon") or (s ~= nil and s.manual))
end

local function NoteInstance(s)
  local name, _, _, _, _, _, _, id = GetInstanceInfo()
  local last = s.instances[#s.instances]
  if (last and last.id == id) or #s.instances >= GM.LIMITS.instances then
    return
  end
  -- The client can answer before it has the name. The app's schema wants one, so the row gets
  -- the same placeholder a nameless pull gets in record/encounters.lua.
  if not name or name == "" then
    name = "Unknown"
  end
  s.instances[#s.instances + 1] = { id = id, name = util.Truncate(name, GM.LIMITS.textBytes), at = util.Now() }
  session.Touch(s)
end

local function NewId()
  local id
  repeat
    id = string.format("%06x", math.random(0, 16777215))
  until not session.Find(id)
  return id
end

-- The oldest sessions, once there are more than KEEP of them. A pruned session is announced
-- like a deleted one: the window is showing a list of these, and one of them may be the row
-- the player has chosen.
local function Prune()
  local sessions = Sessions()
  if not sessions then
    return
  end
  while #sessions > session.KEEP do
    local gone = table.remove(sessions, 1)
    Changed(gone, "delete")
    -- Said in chat: the player may never have exported it, and nothing else would tell them.
    GM.Print(string.format("the oldest stored raid (%s) was removed, to keep the last %d.",
      util.FormatDate(gone.start), session.KEEP))
  end
end

function session.Open(manual)
  if not Sessions() then
    return nil -- locked, or data this addon has not initialised: nowhere to write
  end
  local now = util.Now()
  local s = {
    id = NewId(),
    start = now,
    lastSeen = now,
    manual = manual and true or false,
    addon = GM.version,
    interface = select(4, GetBuildInfo()),
    realm = GetRealmName(),
    guild = GetGuildInfo("player") or "",
    recorder = util.StripRealm(util.UnitFullName("player")),
    instances = {},
    players = {},
    presence = {},
    encounters = {},
    loot = {},
  }
  local sessions = Sessions()
  sessions[#sessions + 1] = s
  GM.db.data.activeId = s.id
  Prune()

  -- Announced before anything is written into it: a watcher told "touch" about a session it
  -- has never heard of has to work out for itself where that session came from.
  Changed(s, "open")
  if InRecordedInstance(s) then
    NoteInstance(s)
  end
  Refresh(s)
  GM.Print("recording started.")
  return s
end

-- Ends the open session at `at` (default: now). Open presence intervals and a pull left
-- open are ended at the same moment; a pull without an ENCOUNTER_END counts as a wipe.
--
-- `at` is often back-dated (the 30 minute rule ends the session where the recorder left the
-- instance), so presence is clipped to it: the app counts a row's whole span as time present,
-- and an interval reaching past the end would count the time the raid was already over. A row
-- that only begins after the end is time outside the session and goes away. Nothing references
-- presence rows by index (they reference players), so dropping one is safe.
function session.Close(at, why)
  local s = session.Current()
  if not s then
    return
  end
  resumedSeen = nil
  if not Usable(s) then
    Release()
    return
  end
  at = math.max(at or util.Now(), s.start)

  local kept = {}
  for i = 1, #s.presence do
    local row = s.presence[i]
    if row.from <= at then
      row.to = math.max(row.from, math.min(row.to or at, at))
      kept[#kept + 1] = row
    end
  end
  s.presence = kept
  local pull = s.encounters[#s.encounters]
  if pull and not pull.stop then
    pull.stop = math.max(pull.start, pull.seen or at)
    pull.kill = false
  end

  s.stop = at
  s.outsideSince = nil
  GM.db.data.activeId = nil

  local kills, wipes = session.Counts(s)
  GM.Print(string.format("Raid logged: %d kills, %d wipes. %s export", kills, wipes, GM.COMMAND))
  Changed(s, "close", why)
end

-- Why the session being recorded cannot be deleted. One text: Delete refuses with it, and the
-- window says the same thing where it greys the button out.
session.RECORDING_REASON = "That session is still being recorded. Stop it first."

-- Removes a stored session for good. The one being recorded is refused: the recorders hold
-- on to it. Returns true, or false and a reason for the player.
function session.Delete(id)
  local sessions = Sessions()
  if not sessions then
    return false, "saved data is from a newer version. Update the addon."
  end
  if id ~= nil and id == GM.db.data.activeId then
    return false, session.RECORDING_REASON
  end
  for i = #sessions, 1, -1 do
    if sessions[i].id == id then
      local s = table.remove(sessions, i)
      Changed(s, "delete")
      return true
    end
  end
  return false, "no such session."
end

-- What the window shows of a session: one row of the Sessions list, the header of the
-- Current tab. `now` (default: the server clock) ends a session that is still open.
function session.Summary(s, now)
  local kills, wipes = session.Counts(s)
  local instances, presence = List(s.instances), List(s.presence)
  local names, seen = {}, {}
  for i = 1, #instances do
    local name = instances[i].name
    if name ~= nil and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  local present = 0
  for i = 1, #presence do
    if not presence[i].to then
      present = present + 1
    end
  end
  local encounters = List(s.encounters)
  local pull = encounters[#encounters]
  -- OPEN is "this is the session being recorded", never "it has no stop time": a session the
  -- client died in the middle of keeps stop = nil for ever, and would otherwise say
  -- "recording" about a raid from last year and grow a second longer every second.
  local data = GM.db.data
  local open = data ~= nil and not GM.db.locked and s.id ~= nil and s.id == data.activeId
  local start = tonumber(s.start) or 0
  local ended = tonumber(s.stop) or (open and (now or util.Now())) or tonumber(s.lastSeen) or start
  return {
    id = s.id,
    start = s.start,
    open = open,
    duration = math.max(0, ended - start),
    instances = names,
    kills = kills,
    wipes = wipes,
    pull = (pull and not pull.stop) and pull.name or nil,
    players = #List(s.players),
    present = present,
    loot = #List(s.loot),
    -- Gargul awards the bridge recorded (record/gargul.lua). Read straight from the stored
    -- list, so a session written before the bridge existed simply counts none.
    awards = #List(s.awards),
  }
end

local function ArmIdleTimer(seconds)
  if timerArmed then
    return
  end
  timerArmed = true
  C_Timer.After(seconds, function()
    timerArmed = false
    session.Evaluate()
  end)
end

-- The one place that decides whether a session opens, goes on or closes. Runs on every
-- event that can change the answer; cheap enough to run often.
function session.Evaluate()
  local data = GM.db.data
  if not data or GM.db.locked then
    return
  end
  local now = util.Now()
  local s = session.Current()
  local inGroup = InGroup()
  local inside = InRecordedInstance(s)

  -- Inside the grace window "not in a group" is only the client still loading, so it must not
  -- lift the hold /gc stop put on auto-record; leaving the instance still does.
  if not (inGroup and inside) and (inGroup or now >= graceUntil) then
    data.suppressAuto = nil
  end

  if not s then
    if inGroup and inside and GM.db.Setting("autoRecord") and not data.suppressAuto then
      session.Open(false)
    end
    return
  end

  if not s.manual and not inGroup then
    if now < graceUntil then
      return -- just logged in: the client may not know the group yet
    end
    if resumedSeen then
      -- The group was gone before this login (disbanded, or the recorder removed while
      -- offline): the session ended when it was last seen.
      session.Close(resumedSeen, "resume")
    else
      session.Close(now)
    end
    return
  end
  if inGroup then
    resumedSeen = nil
  end

  if inside then
    s.outsideSince = nil
    NoteInstance(s)
  elseif not s.manual then
    s.outsideSince = s.outsideSince or now
    local left = s.outsideSince + session.IDLE_SECONDS - now
    if left <= 0 then
      session.Close(s.outsideSince)
      return
    end
    ArmIdleTimer(left + 1)
  end

  Refresh(s)
end

-- /gc start
function session.Start()
  if GM.db.locked then
    GM.Print("recording is off: the saved data is from a newer version.")
    return
  end
  if session.Current() then
    GM.Print("already recording.")
    return
  end
  GM.db.data.suppressAuto = nil
  session.Open(true)
end

-- /gc stop. While the player stays in the raid, auto-record must not reopen a session at
-- the next roster event, so it is held back until they leave the group or the instance.
function session.Stop()
  local s = session.Current()
  if not s then
    GM.Print("not recording.")
    return
  end
  session.Close(util.Now())
  if InGroup() and InRecordedInstance(nil) then
    GM.db.data.suppressAuto = true
  end
end

-- After a /reload or relog: go on with a session seen less than 30 minutes ago, else end it
-- at the last moment it was seen.
function session.Resume()
  local data = GM.db.data
  if GM.db.locked or not data.activeId then
    return
  end
  local s = session.Current()
  if not s then
    data.activeId = nil
    return
  end
  if not Usable(s) then
    Release()
    return
  end
  -- A pull the relog interrupted can only be closed as a wipe, and it ended when the addon
  -- last saw it. Stamp that here, before the first roster or loot event moves lastSeen, or a
  -- one minute pull would become a wipe lasting until the next thing that happened.
  local seen = tonumber(s.lastSeen) or tonumber(s.start)
  local pull = s.encounters[#s.encounters]
  if pull and not pull.stop then
    pull.seen = seen
  end
  if util.Now() - seen >= session.IDLE_SECONDS then
    session.Close(seen, "resume")
    return
  end
  resumedSeen = seen
  GM.Print("recording resumed.")
end

GM.OnLoad(session.Resume)

-- ADDON_LOADED fires during the loading screen, and zoning into a raid can take longer than
-- the grace period, so the window is anchored here: the first moment the client is really in
-- the world. The timer re-checks once it is over, in case no event follows.
-- Whether `stored` names the character logged in now. A session saved by 0.5.0 or older
-- stored the first name only (UnitName on WoW Forever), which is the same recorder.
function session.SameRecorder(stored)
  local full = util.StripRealm(util.UnitFullName("player"))
  if stored == full then
    return true
  end
  return type(stored) == "string" and not string.find(stored, " ", 1, true) and stored == string.match(full, "^%S+")
end

local function AnchorGrace()
  if not graceArmed then
    return
  end
  graceArmed = false
  -- The session is account-wide, so a relog onto another character within the resume window
  -- would go on recording into the first one's raid. The name is certain only now, with the
  -- world up, which is why this is not in Resume.
  local s = session.Current()
  if s and resumedSeen and (not session.SameRecorder(s.recorder) or s.realm ~= GetRealmName()) then
    session.Close(resumedSeen, "resume")
  end
  local now = util.Now()
  graceUntil = now + session.LOGIN_GRACE
  enteredUntil = now + session.ENTER_GRACE
  C_Timer.After(session.LOGIN_GRACE + 1, session.Evaluate)
end

GM.RegisterEvent("PLAYER_ENTERING_WORLD", AnchorGrace)
GM.RegisterEvent("PLAYER_ENTERING_WORLD", session.Evaluate)
GM.RegisterEvent("GROUP_ROSTER_UPDATE", session.Evaluate)
GM.RegisterEvent("ZONE_CHANGED_NEW_AREA", session.Evaluate)

-- Fires on logout AND on /reload, before the SavedVariables file is written: stamp the
-- session so the 30 minute resume rule measures the time offline, not the time since the
-- last roster change.
GM.RegisterEvent("PLAYER_LOGOUT", function()
  local s = session.Current()
  if s then
    session.Touch(s)
  end
end)
