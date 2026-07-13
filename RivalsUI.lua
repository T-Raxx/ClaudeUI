--[[
    RivalsUI  -  Drawing-API retained-mode cheat menu
    ------------------------------------------------------------------
    NO instances. Parented to nothing. Renders straight to the executor
    framebuffer => invisible to game:GetDescendants() / CoreGui tree scans.
    Style: pepsi / Linoria premium (dark, accent, 2 groupbox columns).

    API (see Demo.lua):
        local Library = loadstring(readfile("Scripts/Rivals/RivalsUI.lua"))()
        local Window  = Library:CreateWindow({ Title = "RIVALS", Size = Vector2.new(580, 0) })
        local Tab     = Window:AddTab("Main")
        local Box     = Tab:AddLeftGroupbox("Coins")
        local t = Box:AddToggle("CoinFarm", { Text = "Activar monedas", Default = false, Callback = fn })
        t:AddToggle("BlueOnly", { Text = "Solo monedas azules" })   -- dependent, hidden till parent on
        Box:AddSlider("Speed", { Text = "Velocidad", Min = 1, Max = 10, Default = 3, Callback = fn })
        Box:AddDropdown("Mode", { Text = "Modo", Values = {"A","B"}, Default = "A", Callback = fn })
        Box:AddButton("Do", fn)
        Library:Unload()

    Notes:
        - Toggle key default RightShift  (Library.ToggleKey)
        - If vertical hitboxes feel off on a given executor, set Library.InsetY = 36
------------------------------------------------------------------ ]]

if not Drawing or not Drawing.new then
    return error("RivalsUI: executor sin Drawing API", 0)
end

local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")

local Library = {
    Drawings   = {},
    Connections= {},
    Flags      = {},
    Toggles    = {},
    Options    = {},
    Windows    = {},

    Open       = true,
    Unloaded   = false,

    ToggleKey  = Enum.KeyCode.RightShift,
    InsetY     = 0,   -- set 36 if hitboxes are vertically shifted on your executor

    Dragging   = nil,
    DragOffset = Vector2.zero,
    ActiveSlider = nil,
    OpenDropdown = nil,

    Font       = 2,   -- 0 UI, 1 System, 2 Plain, 3 Monospace
    FontSize   = 13,

    Theme = {
        Accent     = Color3.fromRGB(96, 130, 255),
        Background = Color3.fromRGB(18, 18, 20),
        Header     = Color3.fromRGB(24, 24, 28),
        Section    = Color3.fromRGB(26, 26, 30),
        Element    = Color3.fromRGB(34, 34, 40),
        Outline    = Color3.fromRGB(8, 8, 10),
        Text       = Color3.fromRGB(235, 235, 240),
        DimText    = Color3.fromRGB(150, 150, 160),
    },
}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

local function getMouse()
    local m = UserInputService:GetMouseLocation()
    return Vector2.new(m.X, m.Y - Library.InsetY)
end

function Library:Draw(class, props)
    local obj = Drawing.new(class)
    obj.Visible = false
    if props then
        for k, v in pairs(props) do
            obj[k] = v
        end
    end
    table.insert(self.Drawings, obj)
    return obj
end

function Library:Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(self.Connections, c)
    return c
end

function Library:SafeCallback(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[RivalsUI] callback error: " .. tostring(err))
    end
end

-- filled rect + 1px outline as two Squares
function Library:Rect(fill, outline)
    local bg = self:Draw("Square", { Filled = true, Thickness = 1, Color = fill })
    local ol
    if outline then
        ol = self:Draw("Square", { Filled = false, Thickness = 1, Color = outline })
    end
    return bg, ol
end

local function setRect(bg, ol, x, y, w, h, z)
    bg.Position = Vector2.new(x, y);      bg.Size = Vector2.new(w, h); bg.ZIndex = z
    if ol then ol.Position = bg.Position; ol.Size = bg.Size;          ol.ZIndex = z + 1 end
end

----------------------------------------------------------------------
-- dependency check
----------------------------------------------------------------------
function Library:DepsMet(element)
    if not element.Dependencies then return true end
    for _, d in ipairs(element.Dependencies) do
        if Library.Flags[d.Flag] ~= d.Value then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------
-- ELEMENT base
----------------------------------------------------------------------
local Element = {}
Element.__index = Element

function Element.new(box, kind)
    return setmetatable({
        Box = box, Kind = kind,
        Objects = {}, Children = {},
        Dependencies = nil,
        Abs = { X = 0, Y = 0, W = 0, H = 0 },
        Height = 0,
    }, Element)
end

function Element:track(obj)
    table.insert(self.Objects, obj)
    return obj
end

function Element:SetShownAll(shown)
    for _, o in ipairs(self.Objects) do
        o.Visible = shown
    end
end

-- attach a dependent element under this one (shows only when this flag == value)
function Element:_dependChild(child, value)
    child.Dependencies = child.Dependencies or {}
    table.insert(child.Dependencies, { Flag = self.Flag, Value = (value == nil) and true or value })
    child.Indent = (self.Indent or 0) + 14
end

----------------------------------------------------------------------
-- widget builders live on Groupbox; dependents proxy to the box but
-- inherit the parent flag dependency + indent
----------------------------------------------------------------------
local Groupbox = {}
Groupbox.__index = Groupbox

----------------------------------------------------------------------
-- TOGGLE
----------------------------------------------------------------------
function Groupbox:AddToggle(flag, opts)
    opts = opts or {}
    local e = Element.new(self, "Toggle")
    e.Flag  = flag
    e.Text  = opts.Text or flag
    e.Indent = opts.Indent or 0
    e.Callback = opts.Callback
    e.Height = 17

    Library.Flags[flag]   = opts.Default or false
    Library.Toggles[flag] = e

    e.box   = e:track(Library:Draw("Square", { Filled = true, Color = Library.Theme.Element }))
    e.boxOl = e:track(Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline }))
    e.fill  = e:track(Library:Draw("Square", { Filled = true, Color = Library.Theme.Accent }))
    e.label = e:track(Library:Draw("Text", { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text }))

    function e:Draw(shown)
        local shownReal = shown and Library:DepsMet(self)
        if not shownReal then self:SetShownAll(false); return false end
        local a = self.Abs
        local bs = 13
        local by = a.Y + (self.Height - bs) / 2
        setRect(self.box, self.boxOl, a.X, by, bs, bs, 3)
        self.fill.Position = Vector2.new(a.X + 2, by + 2)
        self.fill.Size     = Vector2.new(bs - 4, bs - 4)
        self.fill.ZIndex   = 5
        self.fill.Visible  = Library.Flags[self.Flag] == true
        self.label.Text     = self.Text
        self.label.Position = Vector2.new(a.X + bs + 6, a.Y + (self.Height - Library.FontSize) / 2)
        self.label.ZIndex   = 4
        self.box.Visible, self.boxOl.Visible, self.label.Visible = true, true, true
        return true
    end

    function e:Set(v)
        Library.Flags[self.Flag] = v and true or false
        Library:SafeCallback(self.Callback, Library.Flags[self.Flag])
        if self.Box.Window then self.Box.Window:Refresh() end
    end

    function e:HandleClick(m)
        local a = self.Abs
        if pointInRect(m.X, m.Y, a.X, a.Y, a.W, self.Height) then
            self:Set(not Library.Flags[self.Flag])
            return true
        end
        return false
    end

    -- dependent widgets under this toggle
    function e:AddToggle(cflag, copts)
        copts = copts or {}
        local c = self.Box:AddToggle(cflag, copts)
        self:_dependChild(c, true)
        return c
    end
    function e:AddSlider(cflag, copts)
        local c = self.Box:AddSlider(cflag, copts)
        self:_dependChild(c, true)
        return c
    end
    function e:AddDropdown(cflag, copts)
        local c = self.Box:AddDropdown(cflag, copts)
        self:_dependChild(c, true)
        return c
    end

    table.insert(self.Elements, e)
    return e
end

----------------------------------------------------------------------
-- SLIDER
----------------------------------------------------------------------
function Groupbox:AddSlider(flag, opts)
    opts = opts or {}
    local e = Element.new(self, "Slider")
    e.Flag  = flag
    e.Text  = opts.Text or flag
    e.Indent= opts.Indent or 0
    e.Min   = opts.Min or 0
    e.Max   = opts.Max or 100
    e.Decimals = opts.Decimals or 0
    e.Suffix   = opts.Suffix or ""
    e.Callback = opts.Callback
    e.Height   = 30

    Library.Flags[flag]   = math.clamp(opts.Default or e.Min, e.Min, e.Max)
    Library.Options[flag] = e

    e.label = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text }))
    e.value = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.DimText }))
    e.track_= e:track(Library:Draw("Square",{ Filled = true, Color = Library.Theme.Element }))
    e.trOl  = e:track(Library:Draw("Square",{ Filled = false, Color = Library.Theme.Outline }))
    e.fill  = e:track(Library:Draw("Square",{ Filled = true, Color = Library.Theme.Accent }))

    local function fmt(v)
        if e.Decimals > 0 then return string.format("%." .. e.Decimals .. "f", v) end
        return tostring(math.floor(v + 0.5))
    end

    function e:Draw(shown)
        local shownReal = shown and Library:DepsMet(self)
        if not shownReal then self:SetShownAll(false); return false end
        local a = self.Abs
        self.label.Text     = self.Text
        self.label.Position = Vector2.new(a.X, a.Y)
        self.label.ZIndex   = 4
        local v = Library.Flags[self.Flag]
        self.value.Text = fmt(v) .. self.Suffix
        self.value.Position = Vector2.new(a.X + a.W - self.value.TextBounds.X, a.Y)
        self.value.ZIndex   = 4
        local ty = a.Y + 16
        local th = 8
        setRect(self.track_, self.trOl, a.X, ty, a.W, th, 3)
        local pct = (v - self.Min) / (self.Max - self.Min)
        pct = math.clamp(pct, 0, 1)
        self.fill.Position = Vector2.new(a.X, ty)
        self.fill.Size     = Vector2.new(a.W * pct, th)
        self.fill.ZIndex   = 5
        self.label.Visible, self.value.Visible = true, true
        self.track_.Visible, self.trOl.Visible, self.fill.Visible = true, true, true
        return true
    end

    function e:UpdateFromMouse(m)
        local a = self.Abs
        local pct = math.clamp((m.X - a.X) / a.W, 0, 1)
        local raw = self.Min + (self.Max - self.Min) * pct
        local step = (self.Decimals > 0) and (10 ^ -self.Decimals) or 1
        raw = math.floor(raw / step + 0.5) * step
        raw = math.clamp(raw, self.Min, self.Max)
        if raw ~= Library.Flags[self.Flag] then
            Library.Flags[self.Flag] = raw
            Library:SafeCallback(self.Callback, raw)
        end
        self:Draw(true)
    end

    function e:Set(v)
        Library.Flags[self.Flag] = math.clamp(v, self.Min, self.Max)
        Library:SafeCallback(self.Callback, Library.Flags[self.Flag])
        if self.Box.Window then self.Box.Window:Refresh() end
    end

    function e:HandleClick(m)
        local a = self.Abs
        if pointInRect(m.X, m.Y, a.X, a.Y + 14, a.W, 12) then
            Library.ActiveSlider = self
            self:UpdateFromMouse(m)
            return true
        end
        return false
    end

    table.insert(self.Elements, e)
    return e
end

----------------------------------------------------------------------
-- DROPDOWN
----------------------------------------------------------------------
function Groupbox:AddDropdown(flag, opts)
    opts = opts or {}
    local e = Element.new(self, "Dropdown")
    e.Flag   = flag
    e.Text   = opts.Text or flag
    e.Indent = opts.Indent or 0
    e.Values = opts.Values or {}
    e.Callback = opts.Callback
    e.IsOpen = false
    e.Height = 30

    Library.Flags[flag]   = opts.Default or e.Values[1]
    Library.Options[flag] = e

    e.label = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text }))
    e.box   = e:track(Library:Draw("Square",{ Filled = true, Color = Library.Theme.Element }))
    e.boxOl = e:track(Library:Draw("Square",{ Filled = false, Color = Library.Theme.Outline }))
    e.value = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text }))
    e.arrow = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.DimText, Text = "v" }))

    -- overlay list (retained, hidden until open)
    e.listBg  = e:track(Library:Draw("Square",{ Filled = true, Color = Library.Theme.Header }))
    e.listOl  = e:track(Library:Draw("Square",{ Filled = false, Color = Library.Theme.Outline }))
    e.items = {}
    for i, val in ipairs(e.Values) do
        e.items[i] = {
            bg   = e:track(Library:Draw("Square",{ Filled = true, Color = Library.Theme.Header })),
            text = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text, Text = tostring(val) })),
            value = val,
        }
    end

    function e:Draw(shown)
        local shownReal = shown and Library:DepsMet(self)
        if not shownReal then self:SetShownAll(false); self.IsOpen = false; return false end
        local a = self.Abs
        self.label.Text = self.Text
        self.label.Position = Vector2.new(a.X, a.Y); self.label.ZIndex = 4
        local by = a.Y + 15
        setRect(self.box, self.boxOl, a.X, by, a.W, 14, 3)
        self.value.Text = tostring(Library.Flags[self.Flag])
        self.value.Position = Vector2.new(a.X + 5, by + 1); self.value.ZIndex = 5
        self.arrow.Position = Vector2.new(a.X + a.W - 12, by + 1); self.arrow.ZIndex = 5
        self.label.Visible, self.box.Visible, self.boxOl.Visible = true, true, true
        self.value.Visible, self.arrow.Visible = true, true

        -- list overlay
        local open = self.IsOpen
        local ih = 16
        setRect(self.listBg, self.listOl, a.X, by + 15, a.W, ih * #self.items, 40)
        self.listBg.Visible, self.listOl.Visible = open, open
        for i, it in ipairs(self.items) do
            local iy = by + 15 + (i - 1) * ih
            it.bg.Position = Vector2.new(a.X, iy); it.bg.Size = Vector2.new(a.W, ih); it.bg.ZIndex = 41
            it.bg.Color = (it.value == Library.Flags[self.Flag]) and Library.Theme.Accent or Library.Theme.Header
            it.text.Position = Vector2.new(a.X + 5, iy + 1); it.text.ZIndex = 42
            it.bg.Visible, it.text.Visible = open, open
        end
        return true
    end

    function e:Open()
        if Library.OpenDropdown and Library.OpenDropdown ~= self then
            Library.OpenDropdown:Close()
        end
        self.IsOpen = true
        Library.OpenDropdown = self
        if self.Box.Window then self.Box.Window:Refresh() end
    end
    function e:Close()
        self.IsOpen = false
        if Library.OpenDropdown == self then Library.OpenDropdown = nil end
        if self.Box.Window then self.Box.Window:Refresh() end
    end
    function e:Set(v)
        Library.Flags[self.Flag] = v
        Library:SafeCallback(self.Callback, v)
        if self.Box.Window then self.Box.Window:Refresh() end
    end

    function e:HandleClick(m)
        local a = self.Abs
        if pointInRect(m.X, m.Y, a.X, a.Y + 15, a.W, 14) then
            if self.IsOpen then self:Close() else self:Open() end
            return true
        end
        return false
    end

    -- priority handler while open
    function e:HandleListClick(m)
        if not self.IsOpen then return false end
        local a = self.Abs
        local ih = 16
        local top = a.Y + 30
        for i, it in ipairs(self.items) do
            local iy = top + (i - 1) * ih
            if pointInRect(m.X, m.Y, a.X, iy, a.W, ih) then
                self:Set(it.value)
                self:Close()
                return true
            end
        end
        return false
    end

    table.insert(self.Elements, e)
    return e
end

----------------------------------------------------------------------
-- BUTTON
----------------------------------------------------------------------
function Groupbox:AddButton(text, callback)
    local e = Element.new(self, "Button")
    e.Text = text
    e.Indent = 0
    e.Callback = callback
    e.Height = 22

    e.box   = e:track(Library:Draw("Square",{ Filled = true, Color = Library.Theme.Element }))
    e.boxOl = e:track(Library:Draw("Square",{ Filled = false, Color = Library.Theme.Outline }))
    e.label = e:track(Library:Draw("Text",  { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text, Center = true }))

    function e:Draw(shown)
        if not shown then self:SetShownAll(false); return false end
        local a = self.Abs
        setRect(self.box, self.boxOl, a.X, a.Y, a.W, self.Height, 3)
        self.label.Text = self.Text
        self.label.Position = Vector2.new(a.X + a.W / 2, a.Y + (self.Height - Library.FontSize) / 2)
        self.label.ZIndex = 5
        self.box.Visible, self.boxOl.Visible, self.label.Visible = true, true, true
        return true
    end

    function e:HandleClick(m)
        local a = self.Abs
        if pointInRect(m.X, m.Y, a.X, a.Y, a.W, self.Height) then
            Library:SafeCallback(self.Callback)
            return true
        end
        return false
    end

    table.insert(self.Elements, e)
    return e
end

----------------------------------------------------------------------
-- LABEL
----------------------------------------------------------------------
function Groupbox:AddLabel(text)
    local e = Element.new(self, "Label")
    e.Text = text
    e.Indent = 0
    e.Height = 16
    e.label = e:track(Library:Draw("Text", { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.DimText }))
    function e:Draw(shown)
        if not shown then self:SetShownAll(false); return false end
        local a = self.Abs
        self.label.Text = self.Text
        self.label.Position = Vector2.new(a.X, a.Y + (self.Height - Library.FontSize) / 2)
        self.label.ZIndex = 4
        self.label.Visible = true
        return true
    end
    function e:HandleClick() return false end
    table.insert(self.Elements, e)
    return e
end

----------------------------------------------------------------------
-- GROUPBOX layout
----------------------------------------------------------------------
function Groupbox:Layout(x, y, w, shown)
    local pad = 8
    local titleH = 18
    -- header
    setRect(self.bg, self.bgOl, x, y, w, titleH, 2)
    self.title.Position = Vector2.new(x + 6, y + (titleH - Library.FontSize) / 2)
    self.title.ZIndex = 3
    self.bg.Visible, self.bgOl.Visible, self.title.Visible = shown, shown, shown

    local cy = y + titleH + pad
    for _, e in ipairs(self.Elements) do
        local visible = shown and Library:DepsMet(e)
        if visible then
            local ind = e.Indent or 0
            e.Abs = { X = x + pad + ind, Y = cy, W = w - pad * 2 - ind, H = e.Height }
            e:Draw(true)
            cy = cy + e.Height + 6
        else
            e:Draw(false)
        end
    end
    -- body background sits behind elements
    local bodyH = (cy - (y + titleH)) + 2
    setRect(self.bodyBg, nil, x, y + titleH, w, bodyH, 1)
    self.bodyBg.Visible = shown

    local total = titleH + bodyH
    -- outline the whole box
    self.outline.Position = Vector2.new(x, y)
    self.outline.Size = Vector2.new(w, total)
    self.outline.ZIndex = 6
    self.outline.Visible = shown

    self.TotalHeight = total
    return total
end

----------------------------------------------------------------------
-- TAB
----------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Tab:_newGroupbox(name, side)
    local gb = setmetatable({
        Name = name, Side = side, Tab = self, Window = self.Window,
        Elements = {},
    }, Groupbox)
    gb.bg     = Library:Draw("Square", { Filled = true, Color = Library.Theme.Header })
    gb.bgOl   = Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline })
    gb.bodyBg = Library:Draw("Square", { Filled = true, Color = Library.Theme.Section })
    gb.outline= Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline })
    gb.title  = Library:Draw("Text",   { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text, Text = name })
    table.insert(self.Groupboxes, gb)
    return gb
end

function Tab:AddLeftGroupbox(name)  return self:_newGroupbox(name, "Left")  end
function Tab:AddRightGroupbox(name) return self:_newGroupbox(name, "Right") end

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
local Window = {}
Window.__index = Window

function Library:CreateWindow(opts)
    opts = opts or {}
    local w = setmetatable({
        Title = opts.Title or "RivalsUI",
        X = opts.Position and opts.Position.X or 120,
        Y = opts.Position and opts.Position.Y or 120,
        W = (opts.Size and opts.Size.X) or 580,
        -- Size.Y > 0 => fixed panel height (Linoria-style). 0/nil => auto-fit content.
        H = (opts.Size and opts.Size.Y and opts.Size.Y > 0) and opts.Size.Y or nil,
        Tabs = {},
        ActiveTab = nil,
    }, Window)

    w.headerBg = Library:Draw("Square", { Filled = true, Color = Library.Theme.Header })
    w.headerOl = Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline })
    w.bg       = Library:Draw("Square", { Filled = true, Color = Library.Theme.Background })
    w.bgOl     = Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline })
    w.accent   = Library:Draw("Square", { Filled = true, Color = Library.Theme.Accent })
    w.titleTxt = Library:Draw("Text",   { Font = Library.Font, Size = Library.FontSize + 1, Color = Library.Theme.Text, Text = w.Title })

    table.insert(Library.Windows, w)
    return w
end

function Window:AddTab(name)
    local t = setmetatable({ Name = name, Window = self, Groupboxes = {} }, Tab)
    t.btnBg   = Library:Draw("Square", { Filled = true, Color = Library.Theme.Header })
    t.btnTxt  = Library:Draw("Text",   { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.DimText, Text = name, Center = true })
    table.insert(self.Tabs, t)
    if not self.ActiveTab then self.ActiveTab = t end
    self:Refresh()
    return t
end

function Window:HandleClick(m)
    local headerH, tabH = 26, 24
    -- title drag
    if pointInRect(m.X, m.Y, self.X, self.Y, self.W, headerH) then
        Library.Dragging = self
        Library.DragOffset = Vector2.new(m.X - self.X, m.Y - self.Y)
        return true
    end
    -- tab buttons
    local tabY = self.Y + headerH
    local tw = self.W / #self.Tabs
    for i, t in ipairs(self.Tabs) do
        local tx = self.X + (i - 1) * tw
        if pointInRect(m.X, m.Y, tx, tabY, tw, tabH) then
            self.ActiveTab = t
            self:Refresh()
            return true
        end
    end
    -- active tab elements
    if self.ActiveTab then
        for _, gb in ipairs(self.ActiveTab.Groupboxes) do
            for _, e in ipairs(gb.Elements) do
                if Library:DepsMet(e) and e.HandleClick and e:HandleClick(m) then
                    return true
                end
            end
        end
    end
    return false
end

function Window:Refresh()
    if Library.Unloaded then return end
    local open = Library.Open
    local headerH, tabH, pad, gap = 26, 24, 8, 8

    -- header
    self.headerBg.Position = Vector2.new(self.X, self.Y); self.headerBg.Size = Vector2.new(self.W, headerH); self.headerBg.ZIndex = 2
    self.headerOl.Position = self.headerBg.Position; self.headerOl.Size = self.headerBg.Size; self.headerOl.ZIndex = 7
    self.accent.Position = Vector2.new(self.X, self.Y); self.accent.Size = Vector2.new(self.W, 2); self.accent.ZIndex = 8
    self.titleTxt.Position = Vector2.new(self.X + 8, self.Y + (headerH - (Library.FontSize + 1)) / 2); self.titleTxt.ZIndex = 3
    self.headerBg.Visible, self.headerOl.Visible = open, open
    self.accent.Visible, self.titleTxt.Visible = open, open

    -- tab buttons
    local tabY = self.Y + headerH
    local tw = self.W / math.max(#self.Tabs, 1)
    for i, t in ipairs(self.Tabs) do
        local tx = self.X + (i - 1) * tw
        t.btnBg.Position = Vector2.new(tx, tabY); t.btnBg.Size = Vector2.new(tw, tabH); t.btnBg.ZIndex = 2
        t.btnBg.Color = (t == self.ActiveTab) and Library.Theme.Section or Library.Theme.Header
        t.btnTxt.Position = Vector2.new(tx + tw / 2, tabY + (tabH - Library.FontSize) / 2); t.btnTxt.ZIndex = 3
        t.btnTxt.Color = (t == self.ActiveTab) and Library.Theme.Text or Library.Theme.DimText
        t.btnBg.Visible, t.btnTxt.Visible = open, open
    end

    -- content columns
    local contentY = tabY + tabH + pad
    local colW = (self.W - pad * 2 - gap) / 2
    local leftY, rightY = contentY, contentY

    for _, t in ipairs(self.Tabs) do
        local active = (t == self.ActiveTab) and open
        for _, gb in ipairs(t.Groupboxes) do
            if active then
                if gb.Side == "Right" then
                    local h = gb:Layout(self.X + pad + colW + gap, rightY, colW, true)
                    rightY = rightY + h + gap
                else
                    local h = gb:Layout(self.X + pad, leftY, colW, true)
                    leftY = leftY + h + gap
                end
            else
                gb:Layout(0, 0, colW, false)
            end
        end
    end

    -- window body background: fixed panel height if set, else fit to tallest column
    local totalH
    if self.H then
        totalH = self.H
    else
        local bottom = math.max(leftY, rightY) + pad - gap
        totalH = (bottom - self.Y)
        if totalH < headerH + tabH + 40 then totalH = headerH + tabH + 40 end
    end
    self.bg.Position = Vector2.new(self.X, self.Y); self.bg.Size = Vector2.new(self.W, totalH); self.bg.ZIndex = 0
    self.bgOl.Position = self.bg.Position; self.bgOl.Size = self.bg.Size; self.bgOl.ZIndex = 9
    self.bg.Visible, self.bgOl.Visible = open, open
end

----------------------------------------------------------------------
-- global input
----------------------------------------------------------------------
function Library:Toggle(state)
    if state == nil then state = not self.Open end
    self.Open = state
    if not state and self.OpenDropdown then self.OpenDropdown:Close() end
    for _, w in ipairs(self.Windows) do w:Refresh() end
end

Library:Connect(UserInputService.InputBegan, function(input, gpe)
    if Library.Unloaded then return end
    if input.KeyCode == Library.ToggleKey then
        Library:Toggle()
        return
    end
    if not Library.Open then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local m = getMouse()
        if Library.OpenDropdown then
            if Library.OpenDropdown:HandleListClick(m) then return end
            -- click on the closed box toggles; anything else closes
            if not Library.OpenDropdown:HandleClick(m) then
                Library.OpenDropdown:Close()
            end
            return
        end
        for _, w in ipairs(Library.Windows) do
            if w:HandleClick(m) then return end
        end
    end
end)

Library:Connect(UserInputService.InputChanged, function(input)
    if Library.Unloaded or not Library.Open then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        local m = getMouse()
        if Library.Dragging then
            local w = Library.Dragging
            w.X = m.X - Library.DragOffset.X
            w.Y = m.Y - Library.DragOffset.Y
            w:Refresh()
        elseif Library.ActiveSlider then
            Library.ActiveSlider:UpdateFromMouse(m)
        end
    end
end)

Library:Connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        Library.Dragging = nil
        Library.ActiveSlider = nil
    end
end)

----------------------------------------------------------------------
-- UNLOAD
----------------------------------------------------------------------
function Library:Unload()
    if self.Unloaded then return end
    self.Unloaded = true
    for _, c in ipairs(self.Connections) do
        pcall(function() c:Disconnect() end)
    end
    for _, d in ipairs(self.Drawings) do
        pcall(function() d.Visible = false; d:Remove() end)
    end
    table.clear(self.Drawings)
    table.clear(self.Connections)
    table.clear(self.Windows)
    table.clear(self.Flags)
    table.clear(self.Toggles)
    table.clear(self.Options)
end

return Library
