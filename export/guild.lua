-- Guildion -- export/guild.lua
-- The guild roster as a snapshot for the app's roster import: the same GM1 envelope as a raid
-- log, with kind "guild" (docs/ADDON.md, lib/addon/payload.schema.ts). Read on demand
-- (/gc export guild, the Sessions tab's Guild roster button) and never stored.
--
-- The client lists offline members only while the roster panel's "Show offline members" is
-- ticked, and counts and indexes over that list. The read turns it on, asks the server for a
-- fresh roster, waits for its answer (or WAIT_SECONDS, then uses what the client has), reads,
-- and puts the player's own setting back.
local _, GM = ...

GM.guild = {}
local guild = GM.guild
local util = GM.util
local json = GM.json

guild.KIND = "guild"
guild.WAIT_SECONDS = 5

local pending -- callbacks waiting for the roster; nil while no request is out
local restoreOffline -- the player's own setting, put back after the read
local waitToken -- the timeout belonging to the request that is out

local function AskServer()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif GuildRoster then
    GuildRoster()
  end
end

-- Rank names by 0-based index, as a 1-based list reaching at least `highest` (the highest rank
-- a member holds, 1-based): the guild control API first, then the names the rows carry, then
-- "Rank N" for a rank nothing names.
local function Ranks(rowRanks, highest)
  local ranks, top = {}, highest
  local count = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
  for i = 1, math.min(count, GM.LIMITS.guildRanks) do
    ranks[i] = GuildControlGetRankName(i)
    top = math.max(top, i)
  end
  for index, name in pairs(rowRanks) do
    if index <= GM.LIMITS.guildRanks then
      if not ranks[index] or ranks[index] == "" then
        ranks[index] = name
      end
      top = math.max(top, index)
    end
  end
  for i = 1, top do
    if not ranks[i] or ranks[i] == "" then
      ranks[i] = "Rank " .. i
    end
    ranks[i] = util.Truncate(ranks[i], GM.LIMITS.textBytes)
  end
  return ranks
end

-- The roster as the client holds it now, or nil and a reason.
function guild.Read()
  local name = GetGuildInfo("player")
  if not name or name == "" then
    return nil, "the guild's name is not known yet. Try again in a moment."
  end
  local total = GetNumGuildMembers() or 0
  if total == 0 then
    return nil, "the guild roster has not loaded yet. Try again in a moment."
  end
  local members, seen, rowRanks, highest = {}, {}, {}, 1
  -- Fewer members in the snapshot than the client counted, other than a deliberate duplicate-name
  -- drop: rows the client did not give us, rows we cannot use, or the cap.
  local missing = false
  for i = 1, total do
    if #members >= GM.LIMITS.guildMembers then
      missing = true
      break
    end
    local full, rankName, rankIndex, level, _, _, note, _, _, _, token = GetGuildRosterInfo(i)
    if not full or full == "" then
      missing = true
    end
    local usable = full and full ~= "" and rankIndex and rankIndex + 1 <= GM.LIMITS.guildRanks and token and token ~= ""
    if full and full ~= "" and not usable then
      missing = true
    end
    if usable then
      local n = util.Truncate(util.StripRealm(full), 48)
      local key = string.lower(n)
      if not seen[key] then
        seen[key] = true
        members[#members + 1] = {
          n = n,
          rank = rankIndex,
          lvl = util.Clamp(level or 1, 1, 100),
          c = token,
          note = util.Truncate(note or "", GM.LIMITS.textBytes),
        }
        if rankName and rankName ~= "" then
          rowRanks[rankIndex + 1] = rankName
        end
        highest = math.max(highest, rankIndex + 1)
      end
    end
  end
  table.sort(members, function(a, b)
    return a.n < b.n
  end)
  local snap = {
    guild = util.Truncate(name, GM.LIMITS.textBytes),
    realm = GetRealmName(),
    recorder = util.StripRealm(util.UnitFullName("player")),
    takenAt = util.Now(),
    total = total,
    partial = missing,
    ranks = Ranks(rowRanks, highest),
    members = members,
  }
  if #members == 0 then
    return nil, "the guild roster has not loaded yet. Try again in a moment."
  end
  if missing then
    GM.Print(string.format("the export holds %d of %d guild members; some were still loading. Export again in a moment.", #members, total))
  end
  return snap
end

local function Finish(failure)
  if not pending then
    return
  end
  local callbacks = pending
  pending, waitToken = nil, nil
  local ok, snap, why = true, nil, failure
  if not failure then
    ok, snap, why = pcall(guild.Read)
  end
  if restoreOffline ~= nil then
    SetGuildRosterShowOffline(restoreOffline)
    restoreOffline = nil
  end
  if not ok then
    snap, why = nil, "the guild roster could not be read: " .. tostring(snap)
  end
  for i = 1, #callbacks do
    GM.Safely(callbacks[i], snap, why)
  end
end

-- Reads the roster and calls onReady(snapshot) or onReady(nil, reason). A request made while
-- one is out waits for the same answer.
function guild.Request(onReady)
  if not IsInGuild() then
    GM.Safely(onReady, nil, "you are not in a guild.")
    return
  end
  if pending then
    pending[#pending + 1] = onReady
    return
  end
  pending = { onReady }
  if GetGuildRosterShowOffline and SetGuildRosterShowOffline then
    restoreOffline = GetGuildRosterShowOffline() and true or false
    SetGuildRosterShowOffline(true)
  end
  local token = {}
  waitToken = token
  C_Timer.After(guild.WAIT_SECONDS, function()
    if waitToken == token then
      Finish()
    end
  end)
  local asked, err = pcall(AskServer)
  if not asked then
    Finish("the guild roster could not be requested: " .. tostring(err))
  end
end

-- The payload table for a snapshot. `partial` tells the app the list may be short.
function guild.Build(snap)
  local rows = {}
  for i = 1, #snap.members do
    local m = snap.members[i]
    rows[i] = { n = m.n, rank = m.rank, lvl = m.lvl, c = m.c, note = m.note }
  end
  local ranks = {}
  for i = 1, #snap.ranks do
    ranks[i] = snap.ranks[i]
  end
  return {
    v = GM.payload.SCHEMA_VERSION,
    kind = guild.KIND,
    addon = GM.version,
    interface = select(4, GetBuildInfo()),
    realm = snap.realm,
    guild = snap.guild,
    recorder = snap.recorder,
    takenAt = snap.takenAt,
    partial = snap.partial and true or false,
    ranks = json.Array(ranks),
    members = json.Array(rows),
  }
end

-- The string for the app's roster import, or nil and a reason.
function guild.Export(snap)
  return GM.payload.Encode(guild.Build(snap), "guild roster")
end

GM.RegisterEvent("GUILD_ROSTER_UPDATE", function()
  Finish()
end)
