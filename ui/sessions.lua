-- Guildion -- ui/sessions.lua
-- The Sessions tab: every stored session, newest first, one 16 px row each. Choosing a row
-- enables Export (the action the screen is for) and Delete (quiet, and asked about first).
local _, GM = ...

GM.sessionsTab = { key = "sessions", label = "Sessions", icon = GM.theme.TEX.tabSessions }
local tab = GM.sessionsTab
local ui = GM.ui
local util = GM.util

tab.selectedId = nil
tab.EMPTY = "No raids recorded yet. Join a raid group and enter an instance, or type " .. GM.COMMAND .. " start."

tab.RECORDING = "recording" -- what the Length column says about the session being recorded

-- Columns, left to right. `sample` is the widest shape the column must hold and `also` names
-- every other literal it can show: a column is as wide as the widest of its sample, its header
-- and those, measured, never a number typed in here. The one column without a sample takes
-- what the others leave, and is cut to fit.
tab.COLUMNS = {
  { key = "date", header = "Date", sample = "0000-00-00 00:00" },
  { key = "instances", header = "Instances" },
  { key = "duration", header = "Length", sample = "00h 00m", also = { tab.RECORDING }, right = true },
  { key = "result", header = "K / W", sample = "00 / 00", right = true },
  { key = "players", header = "Players", sample = "00", right = true },
  { key = "loot", header = "Loot", sample = "000", right = true },
}
local GAP = 8

-- One row of the list, as plain text per column: what the tests read.
function tab.RowText(summary)
  return {
    date = util.FormatDate(summary.start),
    instances = #summary.instances > 0 and table.concat(summary.instances, ", ") or "No instance",
    duration = summary.open and tab.RECORDING or util.FormatDuration(summary.duration),
    result = summary.kills .. " / " .. summary.wipes,
    players = tostring(summary.players),
    loot = tostring(summary.loot),
  }
end

local function ColumnWidth(column)
  local width = math.max(ui.TextWidth("small", column.sample), ui.TextWidth("small", column.header))
  local also = column.also
  for i = 1, (also and #also or 0) do
    width = math.max(width, ui.TextWidth("small", also[i]))
  end
  return width
end

-- Labels for every column on `host`, the fixed ones placed from both edges and the free one
-- hung between its neighbours, so a resize moves nothing by hand.
local function MakeCells(host, colorToken, inset)
  local cells = {}
  local flow = ui.Flow(host, { left = inset, right = inset, gap = GAP, middle = true })
  local free, leftOf
  for i = 1, #tab.COLUMNS do
    local column = tab.COLUMNS[i]
    local cell = ui.MakeLabel(host, "small", colorToken)
    cell:SetJustifyH(column.right and "RIGHT" or "LEFT")
    cells[column.key] = cell
    if not column.sample then
      free = cell
    elseif not free then
      flow:Add(cell, ColumnWidth(column))
      leftOf = cell
    end
  end
  local rightOf
  for i = #tab.COLUMNS, 1, -1 do
    local column = tab.COLUMNS[i]
    if not column.sample then
      break
    end
    flow:AddRight(cells[column.key], ColumnWidth(column))
    rightOf = cells[column.key]
  end
  free:SetPoint("LEFT", leftOf, "RIGHT", GAP, 0)
  free:SetPoint("RIGHT", rightOf, "LEFT", -GAP, 0)
  return cells
end

local function Items()
  local all, items = GM.session.All(), {}
  for i = #all, 1, -1 do
    items[#items + 1] = all[i]
  end
  return items
end

local function Selected()
  return tab.selectedId and GM.session.Find(tab.selectedId) or nil
end

-- Whether the line on the status bar is the one a row click put there (why Delete is greyed
-- out). That line is this tab's own and stops being true once the recording stops; a line
-- anything else put up, a copy box's above all, is not ours to clear.
local reasonShown = false

-- The one place the chosen session changes. A question or a copy box in the footer was opened
-- about the session that WAS chosen, so it goes when the choice moves: the alternative is Yes
-- deleting one session while another is marked, or Ctrl+C copying the raid the player just
-- left. Returns true when the choice really moved.
function tab.Choose(id)
  if tab.selectedId == id then
    return false
  end
  tab.selectedId = id
  reasonShown = false
  GM.strip.Reset()
  return true
end

local function BuildRow(parent, poolIndex)
  local row = ui.DressRow(CreateFrame("Button", nil, parent), { zebra = poolIndex })
  row.cells = MakeCells(row, "text", 4)
  ui.SetColor(row.cells.date, "accentSoft")
  row:SetScript("OnClick", function(self)
    local moved = tab.Choose(self.sessionId)
    -- Delete is greyed out for the session being recorded and a greyed button cannot say why.
    local s = Selected()
    local recording = s ~= nil and s == GM.session.Current()
    if not (moved or recording or reasonShown) then
      -- The click chose what was already chosen and has nothing to say, so the footer keeps
      -- what it was showing: a copy box and the line naming what is selected for Ctrl+C.
      return
    end
    reasonShown = recording
    -- SetStatus repaints, which is what marks the row.
    GM.main.SetStatus(recording and GM.session.RECORDING_REASON or "")
  end)
  return row
end

local function FillRow(row, s)
  local summary = GM.session.Summary(s)
  local text = tab.RowText(summary)
  row.sessionId = s.id
  for key, cell in pairs(row.cells) do
    if key ~= "instances" then
      cell:SetText(text[key])
    end
  end
  ui.Fit(row.cells.instances, text.instances, row.cells.instances:GetWidth())
  ui.SetColor(row.cells.duration, summary.open and "profit" or "text")
  row:SetSelected(s.id == tab.selectedId)
end

function tab.Build(panel)
  tab.header = CreateFrame("Frame", nil, panel)
  tab.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  tab.header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  tab.header:SetHeight(ui.HEADER_H)
  tab.list = ui.MakeScrollList(panel, { rowHeight = 16, emptyText = tab.EMPTY, buildRow = BuildRow, fillRow = FillRow })
  tab.list.well:SetPoint("TOPLEFT", tab.header, "BOTTOMLEFT", 0, -ui.HEADER_GAP)
  tab.list.well:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  -- The header's cells line up with the rows': it spans the rows' frame, not the well.
  tab.headerRow = CreateFrame("Frame", nil, tab.header)
  tab.headerRow:SetPoint("TOP", tab.header, "TOP", 0, 0)
  tab.headerRow:SetPoint("BOTTOM", tab.header, "BOTTOM", 0, 0)
  tab.headerRow:SetPoint("LEFT", tab.list.rows, "LEFT", 0, 0)
  tab.headerRow:SetPoint("RIGHT", tab.list.rows, "RIGHT", 0, 0)
  tab.headerCells = MakeCells(tab.headerRow, "textDim", 4)
  for i = 1, #tab.COLUMNS do
    tab.headerCells[tab.COLUMNS[i].key]:SetText(tab.COLUMNS[i].header)
  end
end

function tab.Paint()
  if tab.selectedId and not Selected() then
    tab.Choose(nil) -- deleted, or pruned by a newer session, and so is the footer's question
  end
  tab.list:SetItems(Items())
end

-- Chooses a session and brings its row into view. main.Reveal calls this.
function tab.Select(id)
  tab.Choose(id)
  local items = Items()
  tab.list:SetItems(items)
  for i = 1, #items do
    if items[i].id == id then
      tab.list:ScrollTo(i)
    end
  end
  GM.main.Paint()
end

local function Export()
  local s = Selected()
  if s then
    GM.strip.Export(s)
  end
end

local function Delete()
  local s = Selected()
  if not s then
    return
  end
  local id, date = s.id, util.FormatDate(s.start)
  GM.strip.Confirm("Delete the log from " .. date .. "? This cannot be undone.", "Delete", function()
    local ok, reason = GM.session.Delete(id)
    if ok then
      GM.main.SetStatus("Deleted the log from " .. date .. ".")
    else
      GM.main.SetStatus("Not deleted: " .. reason, "loss")
    end
  end)
end

tab.buttons = {
  {
    text = "Export",
    kind = "primary",
    onClick = Export,
    enabled = function()
      return Selected() ~= nil
    end,
  },
  {
    text = "Delete",
    kind = "quiet",
    onClick = Delete,
    enabled = function()
      local s = Selected()
      return s ~= nil and s ~= GM.session.Current()
    end,
  },
  {
    text = "Guild roster",
    kind = "quiet",
    onClick = function()
      GM.strip.ExportGuild()
    end,
    enabled = function()
      return IsInGuild()
    end,
  },
}

-- Joining or leaving a guild changes whether the Guild roster button can work.
GM.RegisterEvent("PLAYER_GUILD_UPDATE", function()
  GM.main.RequestPaint()
end)

GM.main.AddTab(tab)
