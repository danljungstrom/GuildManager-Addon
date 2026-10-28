-- Guildion -- ui/widgets.lua
-- Widget factories: a 1.15 port of the JinxCore UI toolkit (jinxaddons repo). Same ui.* names
-- and the same rules, rewritten for the modern client:
--   * the window chrome, the panel buttons, the inset panels, the check boxes and the settings
--     dropdown are the client's own templates (PortraitFrameTemplate, UIPanelButtonTemplate,
--     InsetFrameTemplate, UICheckButtonTemplate, WowStyle1DropdownTemplate), so the addon looks
--     like the client's own windows. Each is asked for under pcall and checked for the parts we
--     use, with our own drawing as the fallback (Attune's recipe on this client). Everything
--     else is ours, on BackdropTemplate (SetBackdrop does not exist without it),
--   * layout is MEASURED: ui.Flow, ui.Stack, ui.Fit and ui.FitButton place things from the
--     widths the client reports; nothing here adds up pixel offsets by hand,
--   * every colour comes from ui/theme.lua,
--   * closures over the frame; scripts are (self, ...) handlers.
local _, GM = ...

GM.ui = {}
local ui = GM.ui
local T = GM.theme

local function SetRGB(setter, target, c, a)
  setter(target, c[1], c[2], c[3], a or 1)
end

-- ---------------------------------------------------------------------------
-- Labels and measuring
-- ---------------------------------------------------------------------------

-- A token the theme does not have raises where the typo is (ui/theme.lua): a fallback colour
-- would make it look like a choice.
function ui.SetColor(fs, token)
  SetRGB(fs.SetTextColor, fs, T.C[token or "text"])
end

-- A FontString with no font object throws on SetText in the game, and the caller's typo is
-- then reported from deep inside a repaint. Named here, where the key is.
local function Font(fontKey)
  local font = T.FONT[fontKey or "normal"]
  assert(font, "no theme font named " .. tostring(fontKey))
  return font
end

function ui.MakeLabel(parent, fontKey, colorToken)
  local fs = parent:CreateFontString(nil, "OVERLAY", Font(fontKey))
  ui.SetColor(fs, colorToken or "text")
  -- Word wrap is on by default: a name too long for a 16 px row would run onto a second line
  -- and draw over the row below it. A boxed label is clipped instead, and ui.Fit cuts it.
  fs:SetWordWrap(false)
  return fs
end

-- One hidden FontString per theme font name, to measure text on without putting it on screen.
local ruler

local function RulerHost()
  if not ruler then
    ruler = CreateFrame("Frame", nil, UIParent)
    ruler:Hide()
    ruler.strings = {}
  end
  return ruler
end

local function RulerString(font)
  local host = RulerHost()
  local fs = host.strings[font]
  if not fs then
    fs = host:CreateFontString(nil, "OVERLAY", font)
    host.strings[font] = fs
  end
  return fs
end

-- The width `text` takes in a font, without putting it on screen: a column is as wide as the
-- widest thing it can hold ("2026-09-16 18:00"), measured, not guessed.
function ui.TextWidth(fontKey, text)
  local fs = RulerString(Font(fontKey))
  fs:SetText(text)
  return fs:GetStringWidth()
end

-- The one borrowed string the fallback below measures on.
local probe

-- The width the text on `fs` would take with nothing bounding it. GetStringWidth answers with
-- the BOX for a label whose width is pinned (SetWidth, or anchors on both sides), so a boxed
-- label asked that way always reads as fitting and is never cut.
local function Unbounded(fs)
  if fs.GetUnboundedStringWidth then
    return fs:GetUnboundedStringWidth()
  end
  -- A client without it: the same text in the same font on the probe, which has no box.
  -- GetFontObject answers with a font OBJECT, so it goes to SetFontObject; CreateFontString
  -- wants a NAME, and the object it would take as one leaves a label with no font at all.
  -- One probe, made once and borrowed by every font: never a widget per measurement.
  if not probe then
    probe = RulerHost():CreateFontString(nil, "OVERLAY", Font())
  end
  probe:SetFontObject(fs:GetFontObject())
  probe:SetText(fs:GetText())
  return probe:GetStringWidth()
end

-- How many bytes the escape starting at `i` takes, and whether a colour is open after it
-- (nil: unchanged). The client draws "|" followed by one of cTHr as a code and never as text.
local function EscapeStep(text, i)
  local code = string.sub(text, i + 1, i + 1)
  if code == "|" then
    return 2, nil -- "||" is ONE drawn pipe: a cut between the two shows a stray code
  end
  if code == "c" then
    return 10, true -- "|cffRRGGBB"
  end
  if code == "r" then
    return 2, false
  end
  if code == "T" then
    -- "|Ttexture:size|t", an inline icon.
    local stop = string.find(text, "|t", i + 2, true)
    return stop and (stop + 2 - i) or (#text + 1 - i), nil
  end
  if code == "H" then
    -- "|Hitem:...|h[Name]|h": the whole link is one unit. A cut anywhere inside it leaves a
    -- hyperlink the client draws as its raw codes.
    local stop = string.find(text, "|h", i + 2, true)
    stop = stop and string.find(text, "|h", stop + 2, true)
    return stop and (stop + 2 - i) or (#text + 1 - i), nil
  end
  return 1, nil
end

-- Byte offsets where `text` may be cut, each with whether a colour code is still open there.
-- A cut never lands inside a UTF-8 sequence or inside an escape: half of either is garbage
-- on screen.
local function SafeCuts(text)
  local cuts, opens = { 0 }, { false }
  local i, open = 1, false
  while i <= #text do
    local step = 1
    local byte = string.byte(text, i)
    if byte == 124 then -- "|"
      local opened
      step, opened = EscapeStep(text, i)
      if opened ~= nil then
        open = opened
      end
    elseif byte >= 240 then
      step = 4
    elseif byte >= 224 then
      step = 3
    elseif byte >= 192 then
      step = 2
    end
    i = i + step
    cuts[#cuts + 1] = i - 1
    opens[#opens + 1] = open
  end
  return cuts, opens
end

-- Puts `text` on `fs`, ending it in "..." when it is wider than `width` pixels. Returns the
-- string shown and whether it was cut. A width of 0 or less (nothing measured yet) leaves
-- the text whole rather than trimming it to nothing.
function ui.Fit(fs, text, width)
  text = text or ""
  fs:SetText(text)
  if not width or width <= 0 or Unbounded(fs) <= width then
    return text, false
  end
  local cuts, opens = SafeCuts(text)
  -- Prefix widths only grow with the cut, so the longest prefix that fits is a binary search.
  local lo, hi, shown = 1, #cuts - 1, ""
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local try = string.sub(text, 1, cuts[mid]) .. "..." .. (opens[mid] and "|r" or "")
    fs:SetText(try)
    if Unbounded(fs) <= width then
      shown, lo = try, mid + 1
    else
      hi = mid - 1
    end
  end
  fs:SetText(shown)
  return shown, true
end

-- Sizes `button` to its label: the measured text plus opts.pad (default the button's own pad,
-- else 16), kept between opts.min and opts.max. A label too long for opts.max is cut inside the
-- button. Returns the width, so a row can go on from it.
function ui.FitButton(button, text, opts)
  opts = opts or {}
  local pad = opts.pad or button.pad or 16
  button:SetText(text or "")
  local width = Unbounded(button.label) + pad
  if opts.max and width > opts.max then
    ui.Fit(button.label, text, opts.max - pad)
    width = opts.max
  end
  if opts.min and width < opts.min then
    width = opts.min
  end
  button:SetWidth(width)
  return width
end

-- ---------------------------------------------------------------------------
-- Flow and Stack: offsets are consequences of measured sizes
-- ---------------------------------------------------------------------------

-- A row across `parent`. opts: left and right insets (default 0), gap between widgets
-- (default 4), y offset (default 0), middle = true to centre the row's widgets vertically
-- instead of hanging them from the parent's top edge.
--   flow:Add(widget [, width])       next from the left; width defaults to the widget's own
--   flow:AddRight(widget [, width])  next from the right
--   flow:Fill(widget [, minWidth])   everything between the two; false when less than
--                                    minWidth is left, and the widget is then unanchored
-- Layout only: a Flow never shows or hides anything. Run it again after a resize.
function ui.Flow(parent, opts)
  opts = opts or {}
  local flow = { x = opts.left or 0, right = opts.right or 0, gap = opts.gap or 4, y = opts.y or 0 }
  local leftPoint = opts.middle and "LEFT" or "TOPLEFT"
  local rightPoint = opts.middle and "RIGHT" or "TOPRIGHT"

  -- How much of the row `widget` takes. A width the caller asked for is a BOX and is applied;
  -- without one, a label is left alone and only measured: SetWidth would pin it to the text it
  -- happens to hold now, and the next run of this row would place its neighbours against that
  -- old string. Rounded up, so a half pixel of text never lands under the widget beside it.
  local function Advance(widget, width)
    if width then
      widget:SetWidth(width)
      return width
    end
    if widget:GetObjectType() == "FontString" then
      return math.ceil(Unbounded(widget))
    end
    width = widget:GetWidth()
    widget:SetWidth(width)
    return width
  end

  function flow.Add(self, widget, width)
    widget:ClearAllPoints()
    widget:SetPoint(leftPoint, parent, leftPoint, self.x, self.y)
    self.x = self.x + Advance(widget, width) + self.gap
    return widget
  end

  function flow.AddRight(self, widget, width)
    widget:ClearAllPoints()
    widget:SetPoint(rightPoint, parent, rightPoint, -self.right, self.y)
    self.right = self.right + Advance(widget, width) + self.gap
    return widget
  end

  function flow.Fill(self, widget, minWidth)
    widget:ClearAllPoints()
    if parent:GetWidth() - self.x - self.right < (minWidth or 1) then
      return false
    end
    widget:SetPoint(leftPoint, parent, leftPoint, self.x, self.y)
    widget:SetPoint(rightPoint, parent, rightPoint, -self.right, self.y)
    return true
  end

  return flow
end

-- A column down `parent`. opts: top, left, right insets (default 0), gap (default 6).
--   stack:Add(widget, height [, stretch])   under the last one; stretch = true also pins
--                                            the right edge, else the widget keeps its width
--   stack:Height(bottom)                     what the column needs, plus a bottom inset
function ui.Stack(parent, opts)
  opts = opts or {}
  local stack = { y = opts.top or 0, left = opts.left or 0, right = opts.right or 0, gap = opts.gap or 6, used = false }

  function stack.Add(self, widget, height, stretch)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", self.left, -self.y)
    if stretch then
      widget:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -self.right, -self.y)
    end
    widget:SetHeight(height)
    self.y = self.y + height + self.gap
    self.used = true
    return widget
  end

  function stack.Height(self, bottom)
    return self.y - (self.used and self.gap or 0) + (bottom or 0)
  end

  return stack
end

-- ---------------------------------------------------------------------------
-- Well: a recessed panel
-- ---------------------------------------------------------------------------

-- A template's parts and its mixin's methods are plain fields of the frame table, and a client
-- may lack any of them: rawget asks for one without going through the widget's methods.
local function Part(frame, key)
  return frame and rawget(frame, key) or nil
end

-- A frame from one of the client's templates, or nil when this client cannot build it: an
-- unknown template is an error from CreateFrame, and one that builds without the parts we use
-- (`parts`, its parentKeys) is no better than none.
local function FromTemplate(kind, name, parent, template, parts)
  local ok, frame = pcall(CreateFrame, kind, name, parent, template)
  if not ok or type(frame) ~= "table" then
    return nil
  end
  for i = 1, #(parts or {}) do
    if not Part(frame, parts[i]) then
      frame:Hide()
      return nil
    end
  end
  return frame
end

-- The client's dark bevelled inset (InsetFrameTemplate), else our own recess in the palette.
-- A column header over a list's well: its height and the gap under it. A tab without a header
-- starts its panel this far down too, so the panel does not jump when the tab changes.
ui.HEADER_H, ui.HEADER_GAP = 14, 2

function ui.MakeWell(parent)
  local inset = FromTemplate("Frame", nil, parent, "InsetFrameTemplate", { "Bg" })
  if inset then
    return inset
  end
  local well = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  well:SetBackdrop(T.BACKDROP.well)
  SetRGB(well.SetBackdropColor, well, T.C.well)
  SetRGB(well.SetBackdropBorderColor, well, T.C.chromeDim)
  return well
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------

local function Dimmed(c, factor)
  return { c[1] * factor, c[2] * factor, c[3] * factor }
end

-- kind: "primary" (the one action a screen is for), "accent" or "quiet" (default).
--   button:SetText(text), button:GetText()
--   button:SetActive(flag)   the CHOSEN one of a group (a tab): marked by colour, never by
--                            its label, so choosing never changes a width
--   button:Enable() / Disable() / SetEnabled(flag) repaint: disabled is the same colours dimmed
-- The factory owns OnEnter, OnLeave, OnMouseDown, OnMouseUp and OnHide; callers set OnClick.
function ui.MakeButton(parent, kind)
  local k = T.BTN[kind or "quiet"]
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetBackdrop(T.BACKDROP.button)
  b:SetHeight(20)
  b.label = b:CreateFontString(nil, "OVERLAY", k.font)
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)

  local function Paint(state)
    local on = b.active and k.on or nil
    local bg = (on and on.bg) or k.bg
    if state == "over" then
      bg = k.over
    elseif state == "down" then
      bg = k.down
    end
    local border = (on and on.border) or k.border
    local text = (on and on.text) or k.text
    if not b:IsEnabled() then
      bg, border, text = Dimmed(bg, T.DIM.surface), Dimmed(border, T.DIM.surface), Dimmed(text, T.DIM.text)
    end
    SetRGB(b.SetBackdropColor, b, bg)
    SetRGB(b.SetBackdropBorderColor, b, border)
    SetRGB(b.label.SetTextColor, b.label, text)
    -- A pressed label sits 1 px lower: a button that does not move when clicked feels dead.
    b.label:SetPoint("CENTER", b, "CENTER", 0, state == "down" and -1 or 0)
    b.state = state
  end

  function b.SetText(self, text)
    self.label:SetText(text)
  end

  function b.GetText(self)
    return self.label:GetText()
  end

  function b.SetActive(self, flag)
    flag = flag and true or false
    if self.active == flag then
      return
    end
    self.active = flag
    Paint("normal")
  end

  -- Paint reads IsEnabled, so it runs after the client's own flag flipped. SetEnabled is
  -- wrapped too: the client's version does not go through the two functions below.
  local enable, disable = b.Enable, b.Disable
  function b.Enable(self)
    enable(self)
    Paint("normal")
  end

  function b.Disable(self)
    disable(self)
    Paint("normal")
  end

  function b.SetEnabled(self, flag)
    if flag then
      self:Enable()
    else
      self:Disable()
    end
  end

  local function PaintIfEnabled(state)
    return function()
      if b:IsEnabled() then
        Paint(state)
      end
    end
  end

  b:SetScript("OnEnter", PaintIfEnabled("over"))
  b:SetScript("OnMouseDown", PaintIfEnabled("down"))
  -- The cursor can leave the button between the press and the release, and no OnLeave follows
  -- a release: the button decides from where the mouse actually is, not from the release.
  b:SetScript("OnMouseUp", function()
    if b:IsEnabled() then
      Paint(b:IsMouseOver() and "over" or "normal")
    end
  end)
  b:SetScript("OnLeave", function()
    Paint("normal")
  end)
  -- Hidden while hovered leaves no OnLeave: reset, so it comes back looking normal.
  b:SetScript("OnHide", function()
    Paint("normal")
  end)

  Paint("normal")
  return b
end

-- ---------------------------------------------------------------------------
-- Panel button: the client's red button
-- ---------------------------------------------------------------------------

-- UIPanelButtonTemplate, the red button the client's own windows wear, with its label as
-- button.label so ui.FitButton measures it. On a client without the template: ui.MakeButton of
-- `kind`. Callers set OnClick; greying out a disabled one is the template's own.
local PANEL_BUTTON = { height = 22, pad = 20 }

function ui.MakePanelButton(parent, kind)
  local b = FromTemplate("Button", nil, parent, "UIPanelButtonTemplate")
  local label = b and (b:GetFontString() or Part(b, "Text"))
  if not label then
    if b then
      b:Hide()
    end
    return ui.MakeButton(parent, kind)
  end
  b.label = label
  b.pad = PANEL_BUTTON.pad
  b:SetHeight(PANEL_BUTTON.height)
  return b
end

-- ---------------------------------------------------------------------------
-- Window: the client's chrome, title, attic, tray, drag, close, ESC, resize grip
-- ---------------------------------------------------------------------------

-- opts = { title, width, height, strata, resizable, minW, minH, portrait,
--          onMoved = fn({ point, relativePoint, x, y }), onResized = fn(width, height) }
--   portrait                            a texture for the round portrait over the top-left
--                                       corner. A window with one also gets the attic, the
--                                       line under the title bar beside the portrait.
--   window:SetHeading(text)             the attic's left: what the window shows now
--   window:SetMeta(text [, markToken])  the attic's right, dim; a token puts a small square of
--                                       that colour in front of it
--   window:TrayAdd(widget, width)       window-level controls in the title bar, laid right
--                                       to left from the close button
--   window:Place({ width, height, point })  a saved size and place, made to fit the screen
-- Content hangs off window.titleBar (below it) and the window's own edges (window.inset in
-- from them), so nothing outside this file knows how tall the head is. window.headHeight is
-- the window's top edge to the titleBar's bottom, for a window sized to its content.
-- A second window that opens over this one takes a higher strata, not a higher level: two
-- windows in one strata interleave, and one window's text shows through the other's fill.
--
-- The chrome is the client's PortraitFrameTemplate (the Character frame's bronze border, title
-- bar, red close button and portrait ring), laid over the window as a child of its own: the
-- window stays our frame, so a client without the template keeps the window and only loses the
-- art. The fallback is Blizzard's dialog border with our own title and close button.
-- CHROME is the template's geometry, which cannot be measured before the client has drawn it:
-- head is where content may start, under the portrait ring (headPlain: under the title bar
-- alone), portraitRoom how far in from the window's left edge the ring reaches.
local CHROME = { head = 58, headPlain = 24, portraitRoom = 60 }
-- The fallback's head: a title line, and the attic under it for a window with a portrait.
local HEAD = { bar = 22, attic = 26, titleY = -5 }
-- The attic's two labels: lifted off the head's bottom edge, apart from each other by gap.
local ATTIC = { y = 6, gap = 4, right = 8 }

local function SetPortrait(chrome, texture)
  local set = Part(chrome, "SetPortraitToAsset") or Part(chrome, "SetPortraitTextureRaw")
  if set then
    set(chrome, texture)
    return
  end
  local tex = Part(Part(chrome, "PortraitContainer"), "portrait") or Part(chrome, "portrait")
  if tex then
    tex:SetTexture(texture)
  end
end

-- The chrome over window `f`, or nil when this client cannot build it.
local function Chrome(f, name, portrait)
  local chrome = FromTemplate("Frame", name .. "Chrome", f, "PortraitFrameTemplate", { "NineSlice", "TitleContainer", "CloseButton" })
  local titleText = Part(Part(chrome, "TitleContainer"), "TitleText")
  if not titleText then
    if chrome then
      chrome:Hide()
    end
    return nil
  end
  chrome:SetAllPoints(f)
  -- The window takes the mouse (the drag, the clicks on its body), not the art laid over it.
  chrome:EnableMouse(false)
  -- At the window's own level, so everything the window holds (a level up) draws over the
  -- chrome's background. The template puts its border hundreds of levels up, and the title bar
  -- and the close button must go above that, or the border covers them.
  chrome:SetFrameLevel(f:GetFrameLevel())
  local border = chrome.NineSlice:GetFrameLevel()
  chrome.TitleContainer:SetFrameLevel(border + 10)
  chrome.CloseButton:SetFrameLevel(border + 11)
  local ring = Part(chrome, "PortraitContainer")
  if portrait then
    SetPortrait(chrome, portrait)
    if ring then
      ring:SetFrameLevel(border - 1) -- under the ring's art, over anything of ours
      ring:EnableMouse(false)
    end
  elseif not (ButtonFrameTemplate_HidePortrait and pcall(ButtonFrameTemplate_HidePortrait, chrome)) and ring then
    -- FrameXML's helper also swaps the corner for one without the ring; without it, the
    -- portrait at least goes.
    ring:Hide()
  end
  chrome.titleText = titleText
  return chrome
end

-- The attic: the line under the title bar, beside the portrait. Its left half says what the
-- window shows (SetHeading), its right half what the window is (SetMeta: the version, that it
-- is recording), each boxed to its half so neither can run into the other.
local function Attic(f, left)
  f.heading = ui.MakeLabel(f.titleBar, "large", "accent")
  f.heading:SetJustifyH("LEFT")
  f.heading:SetPoint("BOTTOMLEFT", f.titleBar, "BOTTOMLEFT", left, ATTIC.y)
  f.heading:SetPoint("BOTTOMRIGHT", f.titleBar, "BOTTOM", -ATTIC.gap, ATTIC.y)
  f.meta = ui.MakeLabel(f.titleBar, "small", "textDim")
  f.meta:SetJustifyH("RIGHT")
  f.meta:SetPoint("BOTTOMLEFT", f.titleBar, "BOTTOM", ATTIC.gap, ATTIC.y)
  f.meta:SetPoint("BOTTOMRIGHT", f.titleBar, "BOTTOMRIGHT", -ATTIC.right, ATTIC.y)
  f.mark = f.titleBar:CreateTexture(nil, "OVERLAY")
  f.mark:SetSize(6, 6)
  f.mark:Hide()

  function f.SetHeading(self, text)
    ui.Fit(self.heading, text, self.heading:GetWidth())
  end

  function f.SetMeta(self, text, markToken)
    self.meta:SetText(text or "")
    if not markToken then
      self.mark:Hide()
      return
    end
    -- The text is right-aligned in its box, so its left end is its measured width away from
    -- the box's right edge: the mark sits just before it, wherever that is.
    SetRGB(self.mark.SetColorTexture, self.mark, T.C[markToken])
    self.mark:ClearAllPoints()
    self.mark:SetPoint("RIGHT", self.meta, "RIGHT", -(self.meta:GetStringWidth() + 5), 0)
    self.mark:Show()
  end
end

function ui.MakeWindow(name, opts)
  assert(name, "MakeWindow needs a name: ESC closes windows by their global name")
  opts = opts or {}
  local minW, minH = opts.minW or 200, opts.minH or 120
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f.inset = 10
  f:SetSize(opts.width or 400, opts.height or 300)
  f:SetPoint("CENTER")
  f:SetFrameStrata(opts.strata or "HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  local attic = opts.portrait ~= nil
  local chrome = Chrome(f, name, opts.portrait)
  f.chrome = chrome

  -- After a drag the client has re-anchored the window to the screen with a single point.
  local function Moved()
    f:StopMovingOrSizing()
    if opts.onMoved then
      local point, _, relativePoint, x, y = f:GetPoint(1)
      opts.onMoved({ point, relativePoint, x, y })
    end
  end

  -- The title bar is the obvious handle, but the body drags too: nobody discovers a 22 px
  -- strip. Children that take the mouse (rows, buttons, boxes) still win the click.
  local function Draggable(handle)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
      f:StartMoving()
    end)
    handle:SetScript("OnDragStop", Moved)
  end

  -- The head: from the window's top edge down to where content may start. With the chrome the
  -- title bar is the template's, and ours is the bare strip under it (the drag handle and the
  -- attic); without it, ours draws the title too.
  f.titleBar = CreateFrame("Frame", nil, f)
  if chrome then
    f.headHeight = attic and CHROME.head or CHROME.headPlain
    f.titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", f.inset, 0)
    f.titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -f.inset, 0)
    f.titleBar:SetHeight(f.headHeight)
    f.title, f.close = chrome.titleText, chrome.CloseButton
  else
    f:SetBackdrop(T.BACKDROP.window)
    SetRGB(f.SetBackdropColor, f, T.C.panelBG)
    SetRGB(f.SetBackdropBorderColor, f, T.C.frame)
    local height = HEAD.bar + (attic and HEAD.attic or 0)
    f.titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", f.inset, -f.inset)
    f.titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -f.inset, -f.inset)
    f.titleBar:SetHeight(height)
    f.headHeight = f.inset + height
    f.title = ui.MakeLabel(f.titleBar, "normal", "accent")
    f.title:SetPoint("TOP", f.titleBar, "TOP", 0, HEAD.titleY)
    f.close = ui.MakeButton(f.titleBar, "quiet")
    f.close:SetText("x")
  end
  Draggable(f.titleBar)
  Draggable(f)
  -- The WINDOW goes: the template's own close hides only its parent, the chrome, and would
  -- leave the window open with no frame around it.
  f.close:SetScript("OnClick", function()
    f:Hide()
  end)

  function f.SetTitle(self, text)
    local set = chrome and Part(chrome, "SetTitle")
    if set then
      set(chrome, text)
    else
      self.title:SetText(text)
    end
  end
  f:SetTitle(opts.title or name)

  if attic then
    Attic(f, chrome and CHROME.portraitRoom - f.inset or ATTIC.right)
  end

  function f.TrayAdd(self, widget, width)
    widget:ClearAllPoints()
    if self.trayEdge then
      widget:SetPoint("RIGHT", self.trayEdge, "LEFT", -4, 0)
    elseif chrome then
      widget:SetPoint("RIGHT", self.close, "LEFT", 0, 0) -- the red X has its margin in its art
    else
      widget:SetPoint("TOPRIGHT", self.titleBar, "TOPRIGHT", -3, -3)
    end
    widget:SetSize(width, 16)
    if chrome then
      -- In the chrome's title bar: as high as the close button, or the border covers it.
      widget:SetFrameLevel(self.close:GetFrameLevel())
    end
    self.trayEdge = widget
    return widget
  end
  if not chrome then
    f:TrayAdd(f.close, 18)
  end

  -- Frames named in UISpecialFrames are hidden by ESC. Listed once, however often a window
  -- of this name is built.
  local listed = false
  for i = 1, #UISpecialFrames do
    listed = listed or UISpecialFrames[i] == name
  end
  if not listed then
    tinsert(UISpecialFrames, name)
  end

  local function Clamped(width, height)
    return GM.util.Clamp(width, minW, UIParent:GetWidth()), GM.util.Clamp(height, minH, UIParent:GetHeight())
  end

  function f.Place(self, saved)
    self:SetSize(Clamped(saved.width, saved.height))
    self:ClearAllPoints()
    if saved.point then
      self:SetPoint(saved.point[1], UIParent, saved.point[2], saved.point[3], saved.point[4])
    else
      self:SetPoint("CENTER")
    end
  end

  if opts.resizable then
    f:SetResizable(true)
    -- SetResizeBounds replaced SetMinResize (patch 10.0, and the Classic clients built
    -- since). Whichever this client has; with neither, the size is still clamped below.
    if f.SetResizeBounds then
      f:SetResizeBounds(minW, minH)
    elseif f.SetMinResize then
      f:SetMinResize(minW, minH)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    -- Inside the chrome's corner, and above its border, which would cover it; without the
    -- chrome, above the body's content.
    local edge = chrome and 4 or 2
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge, edge)
    grip:SetFrameLevel(chrome and chrome.NineSlice:GetFrameLevel() + 1 or f:GetFrameLevel() + 10)
    grip:SetNormalTexture(T.TEX.gripUp)
    grip:SetHighlightTexture(T.TEX.gripOver)
    grip:SetPushedTexture(T.TEX.gripDown)
    grip:SetScript("OnMouseDown", function()
      f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
      -- Sizing from a corner re-anchors the window to a single point, exactly as a drag does,
      -- so the saved place is stale unless this reports it too: the window would jump back to
      -- where it was before the resize at the next /reload.
      Moved()
      local width, height = Clamped(f:GetWidth(), f:GetHeight())
      f:SetSize(width, height)
      if opts.onResized then
        opts.onResized(width, height)
      end
    end)
    f.grip = grip
  end

  f:Hide()
  return f
end

-- ---------------------------------------------------------------------------
-- Side tab: a square icon tab down a window's right edge
-- ---------------------------------------------------------------------------

-- As the spellbook's skill lines: the icon on the spellbook's tab art, which tucks under the
-- window's border, the chosen one lit. Our own Button with the game's textures: the
-- spellbook's template is wired to the spellbook's own scripts. The name is the tooltip, so a
-- window with side tabs also names the chosen one where it reads without the mouse (main.lua
-- puts it in the attic).
--   tab:SetActive(flag)   the chosen one of the column; tab.active, tab.name
-- ui.SIDE_TAB: the tab's square and the gap between two, for the column; the art's size and
-- offset are the spellbook's own.
ui.SIDE_TAB = { size = 32, gap = 17, art = 64, artX = -3, artY = 11 }

function ui.MakeSideTab(parent, icon, name)
  local S = ui.SIDE_TAB
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(S.size, S.size)
  b.name = name
  b.art = b:CreateTexture(nil, "BACKGROUND")
  b.art:SetTexture(T.TEX.sideTab)
  b.art:SetSize(S.art, S.art)
  b.art:SetPoint("TOPLEFT", b, "TOPLEFT", S.artX, S.artY)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b.icon:SetTexture(icon or T.TEX.unknownItem)
  b.lit = b:CreateTexture(nil, "OVERLAY")
  b.lit:SetAllPoints(b)
  b.lit:SetTexture(T.TEX.tabLit)
  b.lit:SetBlendMode("ADD")
  b.lit:Hide()
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints(b)
  hover:SetTexture(T.TEX.hilight)
  hover:SetBlendMode("ADD")

  function b.SetActive(self, flag)
    self.active = flag and true or false
    self.lit:SetShown(self.active)
  end

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.name)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  b:SetActive(false)
  return b
end

-- ---------------------------------------------------------------------------
-- Rows: hover and selection, as two different things
-- ---------------------------------------------------------------------------

-- Hover is a texture in the HIGHLIGHT layer, which the client shows only while the mouse is
-- over the row: no OnEnter / OnLeave to collide with the row's own scripts. It is a flat
-- rowHover fill, blended additively. Selection is a separate fill under the text that
-- row:SetSelected(flag) toggles: persistent, and visibly not the hover.
-- opts.zebra = the row's POOL index: even rows get the faint rowAlt fill and every row a
-- hairline along its bottom edge, so a dense table reads in lines. Keyed on the pool position,
-- not on the data: the stripes are furniture and must not move when the list scrolls.
function ui.DressRow(row, opts)
  opts = opts or {}
  row.hover = row:CreateTexture(nil, "HIGHLIGHT")
  row.hover:SetAllPoints(row)
  SetRGB(row.hover.SetColorTexture, row.hover, T.C.rowHover)
  row.hover:SetBlendMode("ADD")

  if opts.zebra then
    if opts.zebra % 2 == 0 then
      row.alt = row:CreateTexture(nil, "BACKGROUND")
      row.alt:SetAllPoints(row)
      SetRGB(row.alt.SetColorTexture, row.alt, T.C.rowAlt)
    end
    row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    SetRGB(row.line.SetColorTexture, row.line, T.C.hairline)
  end

  -- BORDER, the layer above BACKGROUND: the selection must draw over the zebra stripe.
  row.selection = row:CreateTexture(nil, "BORDER")
  row.selection:SetAllPoints(row)
  SetRGB(row.selection.SetColorTexture, row.selection, T.C.rowSelect, T.ALPHA.rowSelect)
  row.selection:Hide()

  function row.SetSelected(self, flag)
    self.selection:SetShown(flag and true or false)
  end

  return row
end

-- ---------------------------------------------------------------------------
-- Scroll list: a well of pooled rows, our own wheel offset and a plain slider
-- ---------------------------------------------------------------------------

-- Deliberately not FauxScrollFrameTemplate: that template brings Blizzard's gold scroll bar
-- into one of our windows. A list is an offset into the data, and the slider and the wheel both
-- just move it.
-- opts = { rowHeight (default 16), pad (default 4), emptyText,
--          buildRow = fn(parent, poolIndex) -> row,   a Button; give it ui.DressRow
--          fillRow = fn(row, item, dataIndex) }
--   list:SetItems(items)   new data; the offset is kept, and pulled back into range
--   list:Paint()           rows for the height there is now; call it after a resize
--   list:ScrollTo(index)   brings that data index into view
--   list.well              the frame to anchor; list.rows, list.bar, list.empty, list.pool
function ui.MakeScrollList(parent, opts)
  local rowHeight, pad = opts.rowHeight or 16, opts.pad or 4
  local list = { items = {}, offset = 0, pool = {} }

  list.well = ui.MakeWell(parent)
  list.bar = CreateFrame("Slider", nil, list.well)
  list.bar:SetOrientation("VERTICAL")
  list.bar:SetWidth(8)
  list.bar:SetPoint("TOPRIGHT", list.well, "TOPRIGHT", -pad, -pad)
  list.bar:SetPoint("BOTTOMRIGHT", list.well, "BOTTOMRIGHT", -pad, pad)
  list.bar:SetValueStep(1)
  list.bar:SetObeyStepOnDrag(true)
  local track = list.bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(list.bar)
  SetRGB(track.SetColorTexture, track, T.C.hairline)
  local thumb = list.bar:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(8, 24)
  SetRGB(thumb.SetColorTexture, thumb, T.C.chromeDim)
  list.bar:SetThumbTexture(thumb)

  -- The rows end where the bar begins: anchored to it, not to a sum of its width and insets.
  list.rows = CreateFrame("Frame", nil, list.well)
  list.rows:SetPoint("TOPLEFT", list.well, "TOPLEFT", pad, -pad)
  list.rows:SetPoint("BOTTOMRIGHT", list.bar, "BOTTOMLEFT", -2, 0)

  list.empty = ui.MakeLabel(list.rows, "small", "textDim")
  list.empty:SetPoint("LEFT", list.rows, "LEFT", 4, 0)
  list.empty:SetPoint("RIGHT", list.rows, "RIGHT", -4, 0)
  list.empty:SetJustifyH("CENTER")
  list.empty:SetText(opts.emptyText or "")

  local function Row(i)
    local row = list.pool[i]
    if row then
      return row
    end
    row = opts.buildRow(list.rows, i)
    row:SetHeight(rowHeight)
    local above = list.pool[i - 1]
    if above then
      row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, 0)
    else
      row:SetPoint("TOPLEFT", list.rows, "TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", list.rows, "TOPRIGHT", 0, 0)
    end
    list.pool[i] = row
    return row
  end

  local painting = false

  function list.Paint(self)
    local visible = math.max(0, math.floor(self.rows:GetHeight() / rowHeight))
    local maxOffset = math.max(0, #self.items - visible)
    self.offset = GM.util.Clamp(self.offset, 0, maxOffset)
    for i = 1, math.max(visible, #self.pool) do
      local item = i <= visible and self.items[self.offset + i] or nil
      if item then
        local row = Row(i)
        opts.fillRow(row, item, self.offset + i)
        row:Show()
      elseif self.pool[i] then
        self.pool[i]:Hide()
      end
    end
    -- Moving the slider to match must not come back here as a scroll.
    painting = true
    self.bar:SetMinMaxValues(0, maxOffset)
    self.bar:SetValue(self.offset)
    self.bar:SetShown(maxOffset > 0)
    painting = false
    self.empty:SetShown(#self.items == 0)
  end

  function list.SetItems(self, items)
    self.items = items or {}
    self:Paint()
  end

  function list.ScrollTo(self, index)
    local visible = math.max(1, math.floor(self.rows:GetHeight() / rowHeight))
    if index <= self.offset then
      self.offset = index - 1
    elseif index > self.offset + visible then
      self.offset = index - visible
    end
    self:Paint()
  end

  list.bar:SetScript("OnValueChanged", function(_, value)
    if painting then
      return
    end
    list.offset = math.floor(value + 0.5)
    list:Paint()
  end)

  -- Three rows per notch. The rows do not take the wheel themselves, so it reaches the well.
  list.well:EnableMouseWheel(true)
  list.well:SetScript("OnMouseWheel", function(_, delta)
    list.bar:SetValue(list.offset - delta * 3)
  end)

  return list
end

-- ---------------------------------------------------------------------------
-- EditBox: flat, in our colours
-- ---------------------------------------------------------------------------

-- `box` must have been created with "BackdropTemplate" and no other template: there is no
-- Blizzard art to strip then, only our own to put on.
function ui.FlattenEditBox(box)
  box:SetBackdrop(T.BACKDROP.button)
  SetRGB(box.SetBackdropColor, box, T.C.well)
  SetRGB(box.SetBackdropBorderColor, box, T.C.chromeDim)
  box:SetFontObject(T.FONT.hi)
  SetRGB(box.SetTextColor, box, T.C.text)
  box:SetTextInsets(6, 6, 0, 0)
  box:SetAutoFocus(false) -- a box that grabs the keyboard when shown eats the player's movement keys
  box:SetMaxLetters(0) -- 0 = no limit: an export string is thousands of characters
  -- A box built from no template has no OnEscapePressed, and a focused one goes on eating the
  -- player's movement keys with no way out. A caller that needs more replaces this script and
  -- must let the keyboard go itself, or hooks it.
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  return box
end

-- ---------------------------------------------------------------------------
-- CheckBox: the client's check box, or a flat square with our own tick, sized to its box plus
-- its label
-- ---------------------------------------------------------------------------

--   check:SetChecked(flag), check:GetChecked()
--   check.onToggle = fn(checked)     after the player clicked
--   check:SetEnabled(flag)           a disabled one is dimmed and takes no click
-- Either way the button is the box AND its words, so a click on the words ticks the box, and
-- the layout sees one widget as wide as both. The client toggles the state BEFORE OnClick
-- runs, so the handler reads it and never keeps a copy.

-- Wraps check's own state changes so the label repaints with them, and reports clicks.
local function CheckBehaviour(check, Sync)
  local setChecked, enable, disable = check.SetChecked, check.Enable, check.Disable
  function check.SetChecked(self, flag)
    setChecked(self, flag and true or false)
    Sync()
  end

  -- Enable and Disable are wrapped too: the client's own versions do not go through
  -- SetEnabled, so a caller using them would leave the box painted as it was.
  function check.Enable(self)
    enable(self)
    Sync()
  end

  function check.Disable(self)
    disable(self)
    Sync()
  end

  function check.SetEnabled(self, flag)
    if flag then
      self:Enable()
    else
      self:Disable()
    end
  end

  check:SetScript("OnClick", function(self)
    Sync()
    if self.onToggle then
      self.onToggle(self:GetChecked() and true or false)
    end
  end)
  Sync()
  return check
end

-- UICheckButtonTemplate, the gold tick. Its art fills the button, so the art goes back into a
-- square at the left and the button grows by the label, which the template keeps as `Text`
-- (current clients) or `text` (older ones). Nil when this client has no such template.
local NATIVE_CHECK = { box = 24, gap = 2 }

local function NativeCheckBox(parent, text)
  local check = FromTemplate("CheckButton", nil, parent, "UICheckButtonTemplate")
  local label = Part(check, "Text") or Part(check, "text")
  if not label then
    if check then
      check:Hide()
    end
    return nil
  end
  local art = { check:GetNormalTexture(), check:GetPushedTexture(), check:GetHighlightTexture(), check:GetCheckedTexture(), check:GetDisabledCheckedTexture() }
  for i = 1, 5 do
    if art[i] then
      art[i]:ClearAllPoints()
      art[i]:SetPoint("LEFT", check, "LEFT", 0, 0)
      art[i]:SetSize(NATIVE_CHECK.box, NATIVE_CHECK.box)
    end
  end
  check.label = label
  label:SetFontObject(Font("normal")) -- measured in the font the rest of the window uses
  label:SetWordWrap(false)
  label:ClearAllPoints()
  label:SetPoint("LEFT", check, "LEFT", NATIVE_CHECK.box + NATIVE_CHECK.gap, 0)
  label:SetText(text)
  check:SetSize(NATIVE_CHECK.box + NATIVE_CHECK.gap + Unbounded(label), NATIVE_CHECK.box)
  return CheckBehaviour(check, function()
    -- The tick and its greyed look are the template's; the label is ours to dim.
    ui.SetColor(label, check:IsEnabled() and "text" or "textDim")
  end)
end

-- Ours: the border is four 1 px textures, since a backdrop edge on a 14 px square draws as a
-- garbled cross. The tick is our texture, shown from GetChecked.
function ui.MakeCheckBox(parent, text)
  local native = NativeCheckBox(parent, text)
  if native then
    return native
  end
  local BOX, GAP = 14, 6
  local check = CreateFrame("CheckButton", nil, parent)

  local fill = check:CreateTexture(nil, "BACKGROUND")
  fill:SetSize(BOX, BOX)
  fill:SetPoint("LEFT", check, "LEFT", 0, 0)
  SetRGB(fill.SetColorTexture, fill, T.C.well)

  local edges = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
  for i = 1, #edges do
    local edge = check:CreateTexture(nil, "BORDER")
    edge:SetPoint(edges[i][1], fill, edges[i][1], 0, 0)
    edge:SetPoint(edges[i][2], fill, edges[i][2], 0, 0)
    edge:SetSize(1, 1) -- the two anchors stretch one of these; the other stays 1 px
    SetRGB(edge.SetColorTexture, edge, T.C.chromeDim)
  end

  check.tick = check:CreateTexture(nil, "ARTWORK")
  check.tick:SetPoint("TOPLEFT", fill, "TOPLEFT", 3, -3)
  check.tick:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -3, 3)
  check.tick:Hide()

  check.label = ui.MakeLabel(check, "normal", "text")
  check.label:SetPoint("LEFT", fill, "RIGHT", GAP, 0)
  check.label:SetText(text)
  -- The label is inside the button, so a click on the words ticks the box.
  check:SetSize(BOX + GAP + Unbounded(check.label), BOX)

  return CheckBehaviour(check, function()
    local enabled = check:IsEnabled()
    SetRGB(check.tick.SetColorTexture, check.tick, enabled and T.C.accent or T.C.chromeDim)
    ui.SetColor(check.label, enabled and "text" or "textDim")
    check.tick:SetShown(check:GetChecked() and true or false)
  end)
end

-- ---------------------------------------------------------------------------
-- Dropdown: a value picker, and a menu, in our own chrome
-- ---------------------------------------------------------------------------

-- Deliberately not UIDropDownMenu: its list is the game's SHARED menu frame, so styling it
-- reaches into every other addon's menus, and using it taints Blizzard's own.
-- opts = { host, anchor, listWidth, native, textWidth }
--   host       the frame the list belongs to (default: parent). Hiding it hides the list.
--   anchor     what the list hangs under (default: the control itself). A menu with no
--              visible control (the minimap button's) anchors it to something else.
--   native     a value picker that may be the client's own menu dropdown
--              (WowStyle1DropdownTemplate, the menu system, which has no shared frame to taint)
--              on a client that has it. Only provider, onSelect, Refresh, SetEnabled and label
--              are common to both: SetItems, OpenList and the list are ours alone.
--   textWidth  the widest value it must show; the control is sized to it
--   dropdown:SetItems({ { text =, value =, checked = }, ... })
--   dropdown.provider = fn() -> items      asked again on every open
--   dropdown.onSelect = fn(value, index)
--   dropdown:OpenList(), dropdown:CloseList(), dropdown:SetText(text)
--   dropdown:Refresh(text)                 shows the current value: `text` on ours, the checked
--                                          item on the client's
-- The CALLER owns the current value: it marks `checked` and hears OnSelect. The widget never
-- decides what is selected, so it cannot disagree with the state it displays.
-- One strata above DIALOG, where the settings window lives: a floating list belongs over every
-- window the addon has, including one opened on top of another.
local LIST_STRATA = "FULLSCREEN_DIALOG"

-- The client's menu dropdown, or nil on a client without the menu system. Its value is the
-- radio the provider marks `checked`; the room beside the text is the arrow's (a guess at the
-- template's insets, wider than ours).
local NATIVE_DROPDOWN = { room = 44 }

local function NativeDropdown(parent, opts)
  local dd = FromTemplate("DropdownButton", nil, parent, "WowStyle1DropdownTemplate", { "SetupMenu", "GenerateMenu" })
  local label = Part(dd, "Text")
  if not label then
    if dd then
      dd:Hide()
    end
    return nil
  end
  dd.label = label
  if opts.textWidth then
    dd:SetWidth(opts.textWidth + NATIVE_DROPDOWN.room)
  end
  dd:SetupMenu(function(_, root)
    local items = dd.provider and dd.provider() or {}
    for i = 1, #items do
      local item = items[i]
      root:CreateRadio(item.text, function()
        return item.checked
      end, function()
        if dd.onSelect then
          dd.onSelect(item.value, i)
        end
      end, item.value)
    end
  end)
  -- The menu is generated again from the provider, so the button shows what is saved now.
  function dd.Refresh(self)
    self:GenerateMenu()
  end
  return dd
end

function ui.MakeDropdown(parent, opts)
  opts = opts or {}
  local native = opts.native and NativeDropdown(parent, opts)
  if native then
    return native
  end
  local ROW, PAD = 16, 4
  local host = opts.host or parent
  local dd = ui.MakeButton(parent, "quiet")
  dd.items, dd.rows = {}, {}

  -- A value reads from the left, like a field; a command's label is centred.
  dd.label:ClearAllPoints()
  dd.label:SetPoint("LEFT", dd, "LEFT", 6, 0)
  dd.label:SetPoint("RIGHT", dd, "RIGHT", -16, 0)
  dd.label:SetJustifyH("LEFT")
  dd.arrow = dd:CreateTexture(nil, "OVERLAY")
  dd.arrow:SetTexture(T.TEX.arrow)
  dd.arrow:SetSize(8, 8)
  dd.arrow:SetPoint("RIGHT", dd, "RIGHT", -5, 0)
  SetRGB(dd.arrow.SetVertexColor, dd.arrow, T.C.textDim)
  if opts.textWidth then
    dd:SetWidth(opts.textWidth + 28) -- the label's inset and the arrow
  end
  dd.Refresh = dd.SetText

  -- A click anywhere else closes the list: a transparent button over the whole screen, one
  -- level under the list. Both sit in LIST_STRATA: a list opened from the settings window
  -- (DIALOG) would otherwise unfold behind it, and a catcher below that window would let the
  -- click that should have closed the list land in it instead. They are hidden whenever the
  -- list is, so nothing of the addon's is covered while it is shut.
  local level = host:GetFrameLevel() + 20
  dd.catcher = CreateFrame("Button", nil, host)
  dd.catcher:SetAllPoints(UIParent)
  dd.catcher:SetFrameStrata(LIST_STRATA)
  dd.catcher:SetFrameLevel(level)
  dd.catcher:RegisterForClicks("AnyUp") -- a right click outside must close the list too
  dd.catcher:Hide()

  dd.list = CreateFrame("Frame", nil, host, "BackdropTemplate")
  dd.list:SetBackdrop(T.BACKDROP.solid)
  SetRGB(dd.list.SetBackdropColor, dd.list, T.C.panelBG)
  SetRGB(dd.list.SetBackdropBorderColor, dd.list, T.C.chrome)
  dd.list:SetFrameStrata(LIST_STRATA)
  dd.list:SetFrameLevel(level + 1)
  dd.list:SetPoint("TOPLEFT", opts.anchor or dd, "BOTTOMLEFT", 0, -2)
  -- A list that opens near an edge must stay on the screen, and it must take the mouse itself:
  -- without that the wheel goes through it and scrolls the table it is floating over.
  dd.list:SetClampedToScreen(true)
  dd.list:EnableMouse(true)
  dd.list:EnableMouseWheel(true)
  dd.list:SetScript("OnMouseWheel", function() end)
  dd.list:Hide()
  -- Whatever hides the list (a pick, a click outside, the window closing) takes the catcher
  -- along, or a screen-sized invisible button goes on eating every click on the screen.
  dd.list:SetScript("OnHide", function()
    dd.catcher:Hide()
  end)

  function dd.CloseList(self)
    self.list:Hide()
    -- Not only through the list's OnHide: hiding a frame whose parent is already hidden fires
    -- no script, and the catcher would be left covering the screen.
    self.catcher:Hide()
  end

  dd.catcher:SetScript("OnClick", function()
    dd:CloseList()
  end)

  function dd.OpenList(self)
    if self.provider then
      self:SetItems(self.provider())
    end
    self.list:Show()
    self.catcher:Show() -- after the list, so the catcher can never outlive it
  end

  local function Row(i)
    local row = dd.rows[i]
    if row then
      return row
    end
    row = CreateFrame("Button", nil, dd.list)
    row:SetHeight(ROW)
    local above = dd.rows[i - 1]
    if above then
      row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, 0)
    else
      row:SetPoint("TOPLEFT", dd.list, "TOPLEFT", PAD, -PAD)
      row:SetPoint("TOPRIGHT", dd.list, "TOPRIGHT", -PAD, -PAD)
    end
    ui.DressRow(row)
    row.label = ui.MakeLabel(row, "small", "text")
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function()
      local item = dd.items[i]
      dd:CloseList()
      if item and dd.onSelect then
        dd.onSelect(item.value, i)
      end
    end)
    dd.rows[i] = row
    return row
  end

  function dd.SetItems(self, items)
    self.items = items or {}
    -- The list's width first, then the rows' text fitted against the width a row really has.
    self.list:SetSize(opts.listWidth or self:GetWidth(), #self.items * ROW + 2 * PAD)
    for i = 1, #self.items do
      local row, item = Row(i), self.items[i]
      ui.Fit(row.label, item.text, row.label:GetWidth())
      ui.SetColor(row.label, item.checked and "accentSoft" or "text")
      row:Show()
    end
    for i = #self.items + 1, #self.rows do
      self.rows[i]:Hide()
    end
  end

  dd:SetScript("OnClick", function()
    if dd.list:IsShown() then
      dd:CloseList()
    else
      dd:OpenList()
    end
  end)

  -- The list is parented to the host, not to the control, so hiding the control on its own
  -- (a tab changing, a row being rebuilt) would leave the list hanging under nothing.
  dd:HookScript("OnHide", function()
    dd:CloseList()
  end)

  return dd
end
