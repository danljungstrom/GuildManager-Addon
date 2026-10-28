-- Guildion -- ui/current.lua
-- The Current tab: the session being recorded. Where it is and for how long, the pulls, the
-- loot that made it past the quality threshold, and the buttons an officer needs during a
-- raid: Start and Stop, Mark kill and Mark wipe for the boss whose ENCOUNTER_END never came,
-- Export.
local _, GM = ...

GM.currentTab = { key = "current", label = "Current", icon = GM.theme.TEX.tabCurrent }
local tab = GM.currentTab
local ui = GM.ui
local util = GM.util
local T = GM.theme

tab.IDLE = "Not recording."
-- What starts a recording, which depends on the "Record automatically in a raid" setting.
tab.IDLE_HINT = "Starts when your raid group enters a raid, or press Start."
tab.IDLE_HINT_MANUAL = "Automatic recording is off. Press Start to record."
tab.NO_PULLS = "No boss pulled yet."
tab.NO_LOOT = "No loot recorded yet."
tab.STARTED = "Recording started."

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)

-- ---------------------------------------------------------------------------
-- What the tab says, as plain values: what the tests read
-- ---------------------------------------------------------------------------

local function Plural(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

-- The two header lines for a session summary (record/session.lua, session.Summary).
function tab.HeaderText(summary)
  local where = #summary.instances > 0 and table.concat(summary.instances, ", ") or "No instance yet"
  local facts = {
    util.FormatDuration(summary.duration),
    summary.present .. " of " .. summary.players .. " present",
    Plural(summary.kills, "kill", "kills") .. ", " .. Plural(summary.wipes, "wipe", "wipes"),
    Plural(summary.loot, "drop", "drops"),
  }
  -- Beside the loot count, and only once there is one: a guild that does not run Gargul would
  -- otherwise read "0 awards" on every raid it ever records.
  if (summary.awards or 0) > 0 then
    facts[#facts + 1] = Plural(summary.awards, "award", "awards")
  end
  return where, table.concat(facts, "   ")
end

-- One pull: { name, result, token, length }. A pull still open runs until `now`.
function tab.PullRow(pull, now)
  local result, token = "Wipe", "loss"
  if not pull.stop then
    result, token = "in progress", "accent"
  elseif pull.kill then
    result, token = "Kill", "profit"
  end
  return { name = pull.name, result = result, token = token, length = util.FormatClock((pull.stop or now) - pull.start) }
end

-- One drop: { name, quality, icon, who, qty }. An item the client has not cached yet has no
-- name and no quality: it shows as its id, dim, until GET_ITEM_INFO_RECEIVED repaints it.
function tab.LootRow(s, drop)
  local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(drop.item)
  local player = s.players[drop.p]
  return {
    name = name or ("Item " .. drop.item),
    quality = quality,
    icon = icon or (GetItemIcon and GetItemIcon(drop.item)) or T.TEX.unknownItem,
    who = player and player.n or "?",
    qty = drop.qty or 1,
  }
end

local function OpenPull(s)
  local pull = s and s.encounters[#s.encounters]
  return (pull and not pull.stop) and pull or nil
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

-- Measured in tab.Build, not here: while the addon loads the client can still answer 0 for the
-- width of a string, and a column measured then would stay 0 px wide for the whole session.
local RESULT_WIDTH, CLOCK_WIDTH

local function BuildPullRow(parent, poolIndex)
  local row = ui.DressRow(CreateFrame("Button", nil, parent), { zebra = poolIndex })
  row.name = ui.MakeLabel(row, "small", "accentSoft")
  row.name:SetJustifyH("LEFT")
  row.result = ui.MakeLabel(row, "small", "text")
  row.result:SetJustifyH("RIGHT")
  row.length = ui.MakeLabel(row, "small", "textDim")
  row.length:SetJustifyH("RIGHT")
  local flow = ui.Flow(row, { left = 4, right = 4, gap = 6, middle = true })
  flow:AddRight(row.length, CLOCK_WIDTH)
  flow:AddRight(row.result, RESULT_WIDTH)
  row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.name:SetPoint("RIGHT", row.result, "LEFT", -6, 0)
  return row
end

local function FillPullRow(row, pull)
  local text = tab.PullRow(pull, util.Now())
  ui.Fit(row.name, text.name, row.name:GetWidth())
  row.result:SetText(text.result)
  ui.SetColor(row.result, text.token)
  row.length:SetText(text.length)
end

local function BuildLootRow(parent, poolIndex)
  local row = ui.DressRow(CreateFrame("Button", nil, parent), { zebra = poolIndex })
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(12, 12)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- icon files have a border baked in
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.who = ui.MakeLabel(row, "small", "textDim")
  row.who:SetJustifyH("RIGHT")
  row.who:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.name = ui.MakeLabel(row, "small", "text")
  row.name:SetJustifyH("LEFT")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetPoint("RIGHT", row.who, "LEFT", -6, 0)
  return row
end

local function FillLootRow(row, drop)
  local text = tab.LootRow(tab.session, drop)
  row.icon:SetTexture(text.icon)
  -- The looter first: its width decides what is left for the item's name.
  row.who:SetText(text.who)
  local color = text.quality and T.QUALITY[text.quality] or T.C.textDim
  row.name:SetTextColor(color[1], color[2], color[3])
  local label = text.qty > 1 and (text.name .. " x" .. text.qty) or text.name
  ui.Fit(row.name, label, row.name:GetWidth())
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local function Column(panel, title, opts)
  local column = { title = ui.MakeLabel(panel, "small", "textDim") }
  column.title:SetText(title)
  column.list = ui.MakeScrollList(panel, opts)
  column.list.well:SetPoint("TOPLEFT", column.title, "BOTTOMLEFT", 0, -3)
  return column
end

function tab.Build(panel)
  RESULT_WIDTH = ui.TextWidth("small", "in progress")
  CLOCK_WIDTH = ui.TextWidth("small", "000:00")
  tab.panel = panel
  tab.where = ui.MakeLabel(panel, "large", "accent")
  tab.where:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, 0)
  tab.where:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, 0)
  tab.where:SetJustifyH("LEFT")
  tab.facts = ui.MakeLabel(panel, "small", "textDim")
  tab.facts:SetPoint("TOPLEFT", tab.where, "BOTTOMLEFT", 0, -3)
  tab.facts:SetPoint("TOPRIGHT", tab.where, "BOTTOMRIGHT", 0, -3)
  tab.facts:SetJustifyH("LEFT")

  -- Two columns that meet at the panel's centre line: pulls left, loot right.
  tab.pulls = Column(panel, "Pulls", { emptyText = tab.NO_PULLS, buildRow = BuildPullRow, fillRow = FillPullRow })
  tab.pulls.title:SetPoint("TOPLEFT", tab.facts, "BOTTOMLEFT", 0, -8)
  tab.pulls.list.well:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -3, 0)
  tab.loot = Column(panel, "Loot", { emptyText = tab.NO_LOOT, buildRow = BuildLootRow, fillRow = FillLootRow })
  tab.loot.title:SetPoint("TOP", tab.pulls.title, "TOP", 0, 0)
  tab.loot.title:SetPoint("LEFT", panel, "CENTER", 3, 0)
  tab.loot.list.well:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

  -- Nothing recording: the same inset panel the Sessions list sits in, the two lines centred
  -- on it, so both tabs read as one window.
  tab.idleWell = ui.MakeWell(panel)
  -- Level with the Sessions tab's list, below where its column header sits.
  tab.idleWell:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(ui.HEADER_H + ui.HEADER_GAP))
  tab.idleWell:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  tab.idle = ui.MakeLabel(tab.idleWell, "normal", "text")
  tab.idle:SetPoint("BOTTOMLEFT", tab.idleWell, "LEFT", 8, 2)
  tab.idle:SetPoint("BOTTOMRIGHT", tab.idleWell, "RIGHT", -8, 2)
  tab.idle:SetJustifyH("CENTER")
  tab.idleHint = ui.MakeLabel(tab.idleWell, "small", "textDim")
  tab.idleHint:SetPoint("TOPLEFT", tab.idleWell, "LEFT", 8, -2)
  tab.idleHint:SetPoint("TOPRIGHT", tab.idleWell, "RIGHT", -8, -2)
  tab.idleHint:SetJustifyH("CENTER")
end

local function Newest(list)
  local out = {}
  for i = #list, 1, -1 do
    out[#out + 1] = list[i]
  end
  return out
end

local function SetRecording(flag)
  tab.where:SetShown(flag)
  tab.facts:SetShown(flag)
  tab.pulls.title:SetShown(flag)
  tab.pulls.list.well:SetShown(flag)
  tab.loot.title:SetShown(flag)
  tab.loot.list.well:SetShown(flag)
  tab.idleWell:SetShown(not flag)
  tab.idle:SetShown(not flag)
  tab.idleHint:SetShown(not flag and not GM.db.locked)
end

function tab.Paint()
  local s = GM.session.Current()
  tab.session = s
  SetRecording(s ~= nil)
  if not s then
    ui.Fit(tab.idle, tab.IDLE, tab.idle:GetWidth())
    local hint = GM.db.Setting("autoRecord") and tab.IDLE_HINT or tab.IDLE_HINT_MANUAL
    ui.Fit(tab.idleHint, hint, tab.idleHint:GetWidth())
    return
  end
  local where, facts = tab.HeaderText(GM.session.Summary(s))
  ui.Fit(tab.where, where, tab.where:GetWidth())
  ui.Fit(tab.facts, facts, tab.facts:GetWidth())
  tab.pulls.list:SetItems(Newest(s.encounters))
  tab.loot.list:SetItems(Newest(s.loot))
end

-- ---------------------------------------------------------------------------
-- The footer's buttons
-- ---------------------------------------------------------------------------

local function Mark(kill)
  return function()
    local pull = OpenPull(GM.session.Current())
    if pull and GM.encounters.MarkResult(kill) then
      GM.main.SetStatus(pull.name .. " marked as a " .. (kill and "kill" or "wipe") .. ".")
    end
  end
end

local function Recording()
  return GM.session.Current() ~= nil
end

local function PullOpen()
  return OpenPull(GM.session.Current()) ~= nil
end

tab.buttons = {
  {
    text = "Export",
    kind = "primary",
    onClick = function()
      local s = GM.session.Current()
      if s then
        GM.strip.Export(s)
      end
    end,
    enabled = Recording,
  },
  {
    text = "Start",
    kind = "accent",
    onClick = function()
      GM.session.Start()
      -- Said in the window as well as in chat: an officer who pressed a button in the window
      -- is looking at the window, not at the chat frame. Mark and Delete answer there too.
      if GM.session.Current() then
        GM.main.SetStatus(tab.STARTED)
      end
    end,
    enabled = function()
      return not Recording() and not GM.db.locked
    end,
  },
  {
    text = "Stop",
    kind = "quiet",
    onClick = function()
      GM.session.Stop()
    end,
    enabled = Recording,
  },
  { text = "Mark kill", kind = "quiet", onClick = Mark(true), enabled = PullOpen },
  { text = "Mark wipe", kind = "quiet", onClick = Mark(false), enabled = PullOpen },
}

-- An item the client had to fetch has arrived: its name and colour can be shown now.
GM.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
  GM.main.RequestPaint()
end)

GM.main.AddTab(tab)
