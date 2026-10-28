-- Guildion -- record/gargul.lua
-- The Gargul bridge: the awards Gargul makes during the session, folded into the raid log so
-- the officer does not have to paste a second export. Gargul is read, never written: its
-- AwardHistory is its own SavedVariables table.
--
-- Everything here is read from Gargul's source at commit 087e0c4 (v8.0.0). Gargul publishes no
-- API version and no stability contract, so any release can rename an event or a field, and the
-- failure mode is silent: Gargul wraps a listener in pcall and swallows what it throws. That is
-- why every handler runs inside our own GM.Safely first, and why /gc help says what was found.
--
-- A stored award (GuildionDB, inside the session, so a /reload loses nothing) carries
-- Gargul's own field names, because the app feeds them straight through the parser its pasted
-- exports already use.
local _, GM = ...

GM.gargul = {}
local gargul = GM.gargul
local util = GM.util

-- Identifiers are global keys in one shared registry (Classes/Events.lua L109-110): an
-- identifier another addon uses would silently replace that addon's listener.
gargul.IDENTIFIERS = {
  award = "GuildionAward",
  edit = "GuildionAwardEdit",
  unaward = "GuildionUnaward",
}

-- Bounds for the numbers a record carries. They are wide on purpose: the point is to keep a
-- hand-edited or corrupt value out of the JSON, not to second-guess Gargul.
local MAX_TIME = 4102444800 -- 2100-01-01, the app's own ceiling
local MAX_ITEM_ID = 10000000
local MAX_AMOUNT = 1000000000

local TEXT_BYTES = {
  checksum = 40,
  itemLink = 1000,
  awardedTo = 64,
  awardedBy = 64,
  winnerClass = 20,
  winningRollType = 40,
  rollPlayer = 64,
  rollClass = 20,
  rollClassification = 40,
}

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

-- Gargul, or nil when what is loaded is not a Gargul this bridge can read. _G.Gargul is set at
-- file load (bootstrap.lua L10-11) and _initialized turns true once GL.DB is populated (L23,
-- L71); half of that is "not installed" as far as we are concerned.
function gargul.Addon()
  local GL = _G.Gargul
  if type(GL) ~= "table" or GL._initialized ~= true then
    return nil
  end
  if type(GL.Events) ~= "table" or type(GL.Events.register) ~= "function" then
    return nil
  end
  if type(GL.DB) ~= "table" or type(GL.DB.AwardHistory) ~= "table" then
    return nil
  end
  return GL
end

function gargul.Available()
  return gargul.Addon() ~= nil
end

-- The version string Gargul reports (bootstrap.lua L39), or nil.
function gargul.Version()
  local GL = gargul.Addon()
  if not GL or type(GL.version) ~= "string" or GL.version == "" then
    return nil
  end
  return util.Truncate(GL.version, 40)
end

-- ---------------------------------------------------------------------------
-- Sanitising
-- ---------------------------------------------------------------------------

local function Text(value, maxBytes)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return util.Truncate(value, maxBytes)
end

local function Number(value, lo, hi)
  if not util.IsFinite(value) then
    return nil
  end
  return util.Clamp(value, lo, hi)
end

local function Whole(value, lo, hi)
  local number = Number(value, lo, hi)
  if number == nil then
    return nil
  end
  return math.floor(number)
end

local function Flag(value)
  return value and true or false
end

-- One roll of the roll-off the award ended (Classes/RollOff.lua L1157-1166, plus plusOneState
-- added at award time). A roll without a player or an amount says nothing and is dropped.
local function Roll(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local player = Text(entry.player, TEXT_BYTES.rollPlayer)
  local amount = Number(entry.amount, -MAX_AMOUNT, MAX_AMOUNT)
  if not player or not amount then
    return nil
  end
  return {
    player = player,
    class = Text(entry.class, TEXT_BYTES.rollClass),
    amount = amount,
    min = Number(entry.min, -MAX_AMOUNT, MAX_AMOUNT),
    max = Number(entry.max, -MAX_AMOUNT, MAX_AMOUNT),
    time = Whole(entry.time, 0, MAX_TIME),
    classification = Text(entry.classification, TEXT_BYTES.rollClassification),
    priority = Number(entry.priority, -MAX_AMOUNT, MAX_AMOUNT),
  }
end

-- A copy of `entry` holding only the keys the app knows, each one made safe. A copy, never a
-- reference: AwardHistory is Gargul's live saved data, and a record that arrived over addon
-- comms has its itemLink filled in later by mutating the same table (Classes/AwardedLoot.lua
-- L1237-1246). nil when the record names no award at all.
function gargul.Sanitise(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local checksum = Text(entry.checksum, TEXT_BYTES.checksum)
  local itemID = Whole(entry.itemID, 1, MAX_ITEM_ID)
  if not checksum or not itemID then
    return nil
  end

  local rolls, raw = {}, entry.Rolls
  if type(raw) == "table" then
    for i = 1, #raw do
      if #rolls >= GM.LIMITS.rollsPerAward then
        break
      end
      local roll = Roll(raw[i])
      if roll then
        rolls[#rolls + 1] = roll
      end
    end
  end

  return {
    checksum = checksum,
    itemID = itemID,
    itemLink = Text(entry.itemLink, TEXT_BYTES.itemLink),
    awardedTo = Text(entry.awardedTo, TEXT_BYTES.awardedTo),
    awardedBy = Text(entry.awardedBy, TEXT_BYTES.awardedBy),
    timestamp = Whole(entry.timestamp, 0, MAX_TIME),
    received = Flag(entry.received),
    -- A class string, not the class id a pasted export carries (Classes/AwardedLoot.lua L598)
    winnerClass = Text(entry.winnerClass, TEXT_BYTES.winnerClass),
    BRCost = Number(entry.BRCost, -MAX_AMOUNT, MAX_AMOUNT),
    GDKPCost = Number(entry.GDKPCost, -MAX_AMOUNT, MAX_AMOUNT),
    OS = Flag(entry.OS),
    SR = Flag(entry.SR),
    WL = Flag(entry.WL),
    PL = Flag(entry.PL),
    TMB = Flag(entry.TMB),
    isBonusLoot = Flag(entry.isBonusLoot),
    winningRollType = Text(entry.winningRollType, TEXT_BYTES.winningRollType),
    Rolls = rolls,
  }
end

-- ---------------------------------------------------------------------------
-- What a session holds
-- ---------------------------------------------------------------------------

-- The session's awards. A session stored by an older addon has no `awards` key and reads as
-- empty; `create` makes the list on the first write.
local function Awards(s, create)
  if type(s.awards) ~= "table" then
    if not create then
      return nil
    end
    s.awards = {}
  end
  return s.awards
end

function gargul.Count(s)
  local awards = Awards(s, false)
  return awards and #awards or 0
end

-- Stores one award, replacing the row with the same checksum. Refused once the list is full:
-- the cap is the app's, and an export must never be rejected for its size.
local function Store(s, award)
  local awards = Awards(s, true)
  for i = 1, #awards do
    if awards[i].checksum == award.checksum then
      awards[i] = award
      GM.session.Touch(s)
      return true
    end
  end
  if #awards >= GM.LIMITS.awards then
    return false
  end
  awards[#awards + 1] = award
  GM.session.Touch(s)
  return true
end

local function Drop(s, checksum)
  local awards = Awards(s, false)
  if not awards then
    return false
  end
  for i = #awards, 1, -1 do
    if awards[i].checksum == checksum then
      table.remove(awards, i)
      -- Only the session being recorded is touched: lastSeen is the resume clock, and a
      -- closed session's has to stay where it ended.
      if s == GM.session.Current() then
        GM.session.Touch(s)
      end
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The handlers
-- ---------------------------------------------------------------------------

-- Gargul dispatches as listener(event, unpack(args)) (Classes/Events.lua L165), so the award
-- record is the SECOND argument.
local function OnAward(_, entry)
  local s = GM.session.Current()
  if not s then
    return -- nothing is recorded outside a session
  end
  local award = gargul.Sanitise(entry)
  if award then
    Store(s, award)
  end
end

-- An unaward reaches every stored session, not only the one being recorded: the master looter
-- may take back a mis-assigned item in town after the raid's session closed, and the live copy
-- recorded during the raid would otherwise still be exported. The sweep cannot undo it, since
-- an unawarded checksum is simply gone from Gargul's history.
local function OnUnaward(_, entry)
  if type(entry) ~= "table" then
    return
  end
  local checksum = Text(entry.checksum, TEXT_BYTES.checksum)
  if not checksum then
    return
  end
  local sessions = GM.session.All()
  for i = 1, #sessions do
    if type(sessions[i]) == "table" then
      Drop(sessions[i], checksum)
    end
  end
end

-- Gargul's own dispatch wraps a listener in pcall and throws the error away, so a broken bridge
-- would look exactly like an absent one. Ours catches first and prints once per message.
local function Handler(fn)
  return function(event, entry)
    GM.Safely(fn, event, entry)
  end
end

gargul.hooked = false

-- Registers the three listeners. Safe to call again: it does nothing once they are up, and
-- nothing at all while Gargul is not there.
function gargul.Hook()
  if gargul.hooked then
    return true
  end
  local GL = gargul.Addon()
  if not GL then
    return false
  end
  GL.Events:register(gargul.IDENTIFIERS.award, "GL.ITEM_AWARDED", Handler(OnAward))
  GL.Events:register(gargul.IDENTIFIERS.edit, "GL.ITEM_AWARD_EDITED", Handler(OnAward))
  GL.Events:register(gargul.IDENTIFIERS.unaward, "GL.ITEM_UNAWARDED", Handler(OnUnaward))
  gargul.hooked = true
  return true
end

-- ---------------------------------------------------------------------------
-- The export sweep
-- ---------------------------------------------------------------------------

local function SweepInto(found, GL, from, to)
  for _, entry in pairs(GL.DB.AwardHistory) do
    if type(entry) == "table" and util.IsFinite(entry.timestamp) and entry.timestamp >= from and entry.timestamp <= to then
      local award = gargul.Sanitise(entry)
      if award then
        found[#found + 1] = award
      end
    end
  end
end

-- Gargul's own history for the window [from, to]. AwardHistory is a hash keyed by award
-- checksum (Classes/AwardedLoot.lua L618), so it is walked with pairs, never ipairs.
-- The walk runs under GM.Safely because this is third-party data read while the export is
-- being built, and the string carries the raid's attendance and every pull as well: a shape
-- we did not expect costs the awards it reached, never the whole log.
function gargul.Sweep(from, to)
  local found = {}
  local GL = gargul.Addon()
  if not GL then
    return found
  end
  GM.Safely(SweepInto, found, GL, from, to)
  return found
end

local function Order(a, b)
  local at, bt = a.timestamp or 0, b.timestamp or 0
  if at ~= bt then
    return at < bt
  end
  return a.checksum < b.checksum
end

-- What the export carries: the awards recorded live, plus a sweep of Gargul's own history for
-- the session's window. The SWEPT copy wins for a checksum in both, because a comm award's
-- itemLink is dehydrated when the event fires and filled in afterwards. A checksum that was
-- unawarded is gone from the history too, so it stays dropped. Sorted by time, then checksum,
-- so the same session always exports the same bytes.
function gargul.Awards(s, from, to)
  local byChecksum, order = {}, {}
  local function Put(award)
    if byChecksum[award.checksum] == nil then
      order[#order + 1] = award.checksum
    end
    byChecksum[award.checksum] = award
  end

  local stored = Awards(s, false) or {}
  for i = 1, #stored do
    if type(stored[i]) == "table" and type(stored[i].checksum) == "string" then
      Put(stored[i])
    end
  end
  local swept = gargul.Sweep(from, to)
  for i = 1, #swept do
    Put(swept[i])
  end

  local rows = {}
  for i = 1, #order do
    rows[i] = byChecksum[order[i]]
  end
  table.sort(rows, Order)
  -- Over the cap the newest awards go, because the list is sorted oldest first. That matches
  -- Store(), which refuses a new award once the live list is full, so a session that hits the
  -- cap keeps one consistent run of awards from its start rather than a mixture of both ends.
  while #rows > GM.LIMITS.awards do
    table.remove(rows)
  end
  return rows
end

-- Gargul builds its DB on ADDON_LOADED, so PLAYER_LOGIN is the first moment it is ready. The
-- retry when a session opens covers a Gargul enabled later in the same login.
GM.RegisterEvent("PLAYER_LOGIN", gargul.Hook)

-- Again on every world entry: a session resumed after a /reload fires no "open", and Gargul may
-- not be ready yet at PLAYER_LOGIN. Hook() does nothing once the listeners are up.
GM.RegisterEvent("PLAYER_ENTERING_WORLD", gargul.Hook)

GM.session.OnChange(function(_, what)
  if what == "open" then
    gargul.Hook()
  end
end)
