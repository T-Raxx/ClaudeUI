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
        Box:AddColorPicker("Col", { Text = "Color", Default = Color3.fromRGB(255,0,0), Callback = fn })  -- stores a Color3 in Flags
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
local RunService       = game:GetService("RunService")

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

    Keybinds   = {},   -- elementos con keybind (para la lista en pantalla)
    Showcase       = nil,   -- panel del modelo 3D girando (wireframe)
    ShowcaseOn     = false,
    ShowcaseSpeed  = 0.6,
    ShowcaseSize   = 190,
    ShowcaseColor  = nil,
    OnOpen         = nil,   -- callback al abrir el menu (para elegir modelo nuevo)
    CapturingKeybind = nil,   -- elemento esperando que apretes una tecla

    Dragging   = nil,
    DragOffset = Vector2.zero,
    ActiveSlider = nil,
    OpenDropdown = nil,
    OpenPicker   = nil,   -- element whose colorpicker popup is open (exclusive with OpenDropdown)
    PickerDrag   = nil,   -- "sv" | "hue" while dragging inside the popup
    Picker       = nil,   -- shared popup singleton (built lazily on first colorpicker open)

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

    -- keybind opcional: caja de tecla a la derecha de la fila
    if opts.Keybind then
        e.HasKeybind = true
        e.KeyFlag    = flag .. "_Key"
        e.ModeFlag   = flag .. "_KeyMode"
        Library.Flags[e.KeyFlag]  = opts.DefaultKey or "None"
        Library.Flags[e.ModeFlag] = opts.KeyMode or "Toggle"
        e.kBox   = e:track(Library:Draw("Square", { Filled = true,  Color = Library.Theme.Element }))
        e.kBoxOl = e:track(Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline }))
        e.kTxt   = e:track(Library:Draw("Text",   { Font = Library.Font, Size = Library.FontSize - 1, Color = Library.Theme.DimText, Center = true }))
        table.insert(Library.Keybinds, e)
    end

    function e:_keyLabel()
        if Library.CapturingKeybind == self then return "..." end
        local k = Library.Flags[self.KeyFlag]
        if not k or k == "None" then return "---" end
        return tostring(k)
    end

    function e:Draw(shown)
        local shownReal = shown and Library:DepsMet(self)
        if not shownReal then
            self:SetShownAll(false)
            if Library.CapturingKeybind == self then Library.CapturingKeybind = nil end
            return false
        end
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
        if self.HasKeybind then
            local txt = self:_keyLabel()
            self.kTxt.Text = txt
            local kw = math.max(self.kTxt.TextBounds.X + 8, 26)
            local kh = 13
            local kx = a.X + a.W - kw
            local ky = a.Y + (self.Height - kh) / 2
            setRect(self.kBox, self.kBoxOl, kx, ky, kw, kh, 3)
            self.kBox.Color = (Library.CapturingKeybind == self) and Library.Theme.Accent or Library.Theme.Element
            self.kTxt.Position = Vector2.new(kx + kw / 2, ky)
            self.kTxt.ZIndex   = 5
            self.kBox.Visible, self.kBoxOl.Visible, self.kTxt.Visible = true, true, true
            self.KeyRect = { x = kx, y = ky, w = kw, h = kh }
        end
        return true
    end

    function e:Set(v)
        Library.Flags[self.Flag] = v and true or false
        Library:SafeCallback(self.Callback, Library.Flags[self.Flag])
        if self.Box.Window then self.Box.Window:Refresh() end
    end

    function e:HandleClick(m)
        local a = self.Abs
        -- la caja de tecla se come el click antes que el toggle
        if self.HasKeybind and self.KeyRect then
            local r = self.KeyRect
            if pointInRect(m.X, m.Y, r.x, r.y, r.w, r.h) then
                Library.CapturingKeybind = self
                if self.Box.Window then self.Box.Window:Refresh() end
                return true
            end
        end
        if pointInRect(m.X, m.Y, a.X, a.Y, a.W, self.Height) then
            self:Set(not Library.Flags[self.Flag])
            return true
        end
        return false
    end

    -- click derecho sobre la caja de tecla: cicla el modo Toggle -> Hold -> Always
    function e:HandleRightClick(m)
        if not (self.HasKeybind and self.KeyRect) then return false end
        local r = self.KeyRect
        if not pointInRect(m.X, m.Y, r.x, r.y, r.w, r.h) then return false end
        local order = { Toggle = "Hold", Hold = "Always", Always = "Toggle" }
        Library.Flags[self.ModeFlag] = order[Library.Flags[self.ModeFlag]] or "Toggle"
        if self.Box.Window then self.Box.Window:Refresh() end
        return true
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
    function e:AddColorPicker(cflag, copts)
        local c = self.Box:AddColorPicker(cflag, copts)
        self:_dependChild(c, true)
        return c
    end
    function e:AddLabel(text)
        local c = self.Box:AddLabel(text)
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
-- COLORPICKER  (shared popup singleton + per-element swatch)
--   One SV grid + hue bar is built once on Library and repositioned for
--   whichever picker opens (like the dropdown overlay). Flags[flag]=Color3.
----------------------------------------------------------------------
function Library:_ensurePicker()
    if self.Picker then return self.Picker end
    local P = {
        GRID = 14, HUE = 24,
        planeW = 140, planeH = 140, hueW = 14, gap = 6, pad = 6,
        cells = {}, hueCells = {},
        X = 0, Y = 0, planeX = 0, planeY = 0, hueX = 0,
    }
    P.bg   = self:Draw("Square", { Filled = true,  Color = self.Theme.Header })
    P.bgOl = self:Draw("Square", { Filled = false, Color = self.Theme.Outline })
    for i = 1, P.GRID * P.GRID do
        P.cells[i] = self:Draw("Square", { Filled = true })
    end
    for i = 1, P.HUE do
        P.hueCells[i] = self:Draw("Square", { Filled = true })
    end
    P.hueOl = self:Draw("Square", { Filled = false, Color = self.Theme.Outline })
    P.svCur = self:Draw("Square", { Filled = false, Color = Color3.new(1, 1, 1) }) -- white ring
    P.svCr2 = self:Draw("Square", { Filled = false, Color = Color3.new(0, 0, 0) }) -- black inner ring
    P.hueCur= self:Draw("Square", { Filled = false, Color = Color3.new(1, 1, 1) })
    self.Picker = P
    return P
end

function Library:_popupSize()
    local P = self.Picker
    return P.pad * 2 + P.planeW + P.gap + P.hueW, P.pad * 2 + P.planeH
end

function Library:_renderPicker(owner)
    local P = self.Picker
    if not P then return end
    local x = owner.Abs.X
    local y = owner.Abs.Y + owner.Height + 3
    P.X, P.Y = x, y
    local popupW, popupH = self:_popupSize()
    setRect(P.bg, P.bgOl, x, y, popupW, popupH, 50)
    P.bgOl.ZIndex = 59
    P.bg.Visible, P.bgOl.Visible = true, true

    local H, S, V = owner.H, owner.S, owner.V
    local planeX, planeY = x + P.pad, y + P.pad
    P.planeX, P.planeY = planeX, planeY
    local G = P.GRID
    local cw, ch = P.planeW / G, P.planeH / G
    for gy = 0, G - 1 do
        for gx = 0, G - 1 do
            local cell = P.cells[gy * G + gx + 1]
            cell.Color    = Color3.fromHSV(H, (gx + 0.5) / G, 1 - (gy + 0.5) / G)
            cell.Position = Vector2.new(planeX + gx * cw, planeY + gy * ch)
            cell.Size     = Vector2.new(cw + 1, ch + 1)
            cell.ZIndex   = 51
            cell.Visible  = true
        end
    end

    local hueX = planeX + P.planeW + P.gap
    P.hueX = hueX
    local HN = P.HUE
    local hh = P.planeH / HN
    for i = 0, HN - 1 do
        local seg = P.hueCells[i + 1]
        seg.Color    = Color3.fromHSV(i / (HN - 1), 1, 1)
        seg.Position = Vector2.new(hueX, planeY + i * hh)
        seg.Size     = Vector2.new(P.hueW, hh + 1)
        seg.ZIndex   = 51
        seg.Visible  = true
    end
    setRect(P.hueOl, nil, hueX, planeY, P.hueW, P.planeH, 52)
    P.hueOl.Visible = true

    -- SV cursor
    local cx = planeX + math.clamp(S, 0, 1) * P.planeW
    local cy = planeY + (1 - math.clamp(V, 0, 1)) * P.planeH
    P.svCur.Position = Vector2.new(cx - 4, cy - 4); P.svCur.Size = Vector2.new(8, 8); P.svCur.ZIndex = 55; P.svCur.Visible = true
    P.svCr2.Position = Vector2.new(cx - 3, cy - 3); P.svCr2.Size = Vector2.new(6, 6); P.svCr2.ZIndex = 56; P.svCr2.Visible = true
    -- hue cursor
    local hy = planeY + math.clamp(H, 0, 1) * P.planeH
    P.hueCur.Position = Vector2.new(hueX - 1, hy - 2); P.hueCur.Size = Vector2.new(P.hueW + 2, 4); P.hueCur.ZIndex = 55; P.hueCur.Visible = true
end

function Library:_hidePicker()
    local P = self.Picker
    if not P then return end
    P.bg.Visible, P.bgOl.Visible, P.hueOl.Visible = false, false, false
    P.svCur.Visible, P.svCr2.Visible, P.hueCur.Visible = false, false, false
    for _, c in ipairs(P.cells) do c.Visible = false end
    for _, c in ipairs(P.hueCells) do c.Visible = false end
end

-- click inside the open popup: returns true to consume (never closes while inside)
function Library:_pickerPopupClick(m)
    local P, owner = self.Picker, self.OpenPicker
    if not (P and owner) then return false end
    local popupW, popupH = self:_popupSize()
    if not pointInRect(m.X, m.Y, P.X, P.Y, popupW, popupH) then return false end
    if pointInRect(m.X, m.Y, P.planeX, P.planeY, P.planeW, P.planeH) then
        self.PickerDrag = "sv"
        owner:SetSV((m.X - P.planeX) / P.planeW, 1 - (m.Y - P.planeY) / P.planeH)
    elseif pointInRect(m.X, m.Y, P.hueX, P.planeY, P.hueW, P.planeH) then
        self.PickerDrag = "hue"
        owner:SetHue((m.Y - P.planeY) / P.planeH)
    end
    return true
end

function Library:_pickerDrag(m)
    local P, owner = self.Picker, self.OpenPicker
    if not (P and owner and self.PickerDrag) then return end
    if self.PickerDrag == "sv" then
        owner:SetSV((m.X - P.planeX) / P.planeW, 1 - (m.Y - P.planeY) / P.planeH)
    elseif self.PickerDrag == "hue" then
        owner:SetHue((m.Y - P.planeY) / P.planeH)
    end
end

function Groupbox:AddColorPicker(flag, opts)
    opts = opts or {}
    local e = Element.new(self, "ColorPicker")
    e.Flag   = flag
    e.Text   = opts.Text or flag
    e.Indent = opts.Indent or 0
    e.Callback = opts.Callback
    e.Height = 17
    local def = opts.Default or Color3.fromRGB(255, 255, 255)
    e.H, e.S, e.V = def:ToHSV()

    Library.Flags[flag]   = def
    Library.Options[flag] = e

    local SW = 26  -- swatch width
    e.label = e:track(Library:Draw("Text",   { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text }))
    e.sw    = e:track(Library:Draw("Square", { Filled = true, Color = def }))
    e.swOl  = e:track(Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline }))

    function e:_apply(fire)
        local c = Color3.fromHSV(self.H, self.S, self.V)
        Library.Flags[self.Flag] = c
        self.sw.Color = c
        if fire ~= false then Library:SafeCallback(self.Callback, c) end
    end
    function e:Set(c)
        if typeof(c) ~= "Color3" then return end
        self.H, self.S, self.V = c:ToHSV()
        self:_apply(true)
        if self.Box.Window then self.Box.Window:Refresh() end
    end
    function e:SetSV(s, v)
        self.S, self.V = math.clamp(s, 0, 1), math.clamp(v, 0, 1)
        self:_apply(true)
        if self.Box.Window then self.Box.Window:Refresh() end
    end
    function e:SetHue(h)
        self.H = math.clamp(h, 0, 1)
        self:_apply(true)
        if self.Box.Window then self.Box.Window:Refresh() end
    end

    function e:Draw(shown)
        local shownReal = shown and Library:DepsMet(self)
        if not shownReal then
            self:SetShownAll(false)
            if Library.OpenPicker == self then
                Library.OpenPicker = nil; Library.PickerDrag = nil; Library:_hidePicker()
            end
            return false
        end
        local a = self.Abs
        -- external change (config load) -> resync hsv from flag
        local cf = Library.Flags[self.Flag]
        if typeof(cf) == "Color3" and cf ~= self.sw.Color then
            self.H, self.S, self.V = cf:ToHSV()
            self.sw.Color = cf
        end
        self.label.Text = self.Text
        self.label.Position = Vector2.new(a.X, a.Y + (self.Height - Library.FontSize) / 2); self.label.ZIndex = 4
        local sh = 12
        local sx = a.X + a.W - SW
        local sy = a.Y + (self.Height - sh) / 2
        setRect(self.sw, self.swOl, sx, sy, SW, sh, 4)
        self.label.Visible, self.sw.Visible, self.swOl.Visible = true, true, true
        if Library.OpenPicker == self then Library:_renderPicker(self) end
        return true
    end

    function e:Open()
        if Library.OpenDropdown then Library.OpenDropdown:Close() end
        if Library.OpenPicker and Library.OpenPicker ~= self then Library.OpenPicker:Close() end
        Library:_ensurePicker()
        Library.OpenPicker = self
        if self.Box.Window then self.Box.Window:Refresh() end
    end
    function e:Close()
        if Library.OpenPicker == self then
            Library.OpenPicker = nil; Library.PickerDrag = nil
            Library:_hidePicker()
        end
        if self.Box.Window then self.Box.Window:Refresh() end
    end

    function e:HandleClick(m)
        local a = self.Abs
        if pointInRect(m.X, m.Y, a.X + a.W - SW, a.Y, SW, self.Height) then
            if Library.OpenPicker == self then self:Close() else self:Open() end
            return true
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
-- alto del groupbox sin dibujar (para calcular scroll)
function Groupbox:MeasureHeight()
    local pad, titleH = 8, 18
    local bodyH = pad
    for _, e in ipairs(self.Elements) do
        if Library:DepsMet(e) then bodyH = bodyH + e.Height + 6 end
    end
    return titleH + bodyH + 2
end

function Groupbox:Layout(x, y, w, shown, clipTop, clipBottom)
    clipTop = clipTop or -1e9; clipBottom = clipBottom or 1e9
    local pad = 8
    local titleH = 18
    -- header (clip vertical al panel)
    local headerVis = shown and (y + titleH > clipTop) and (y < clipBottom)
    setRect(self.bg, self.bgOl, x, y, w, titleH, 2)
    self.title.Position = Vector2.new(x + 6, y + (titleH - Library.FontSize) / 2)
    self.title.ZIndex = 3
    self.bg.Visible, self.bgOl.Visible, self.title.Visible = headerVis, headerVis, headerVis

    local cy = y + titleH + pad
    for _, e in ipairs(self.Elements) do
        local visible = shown and Library:DepsMet(e)
        if visible then
            local ind = e.Indent or 0
            e.Abs = { X = x + pad + ind, Y = cy, W = w - pad * 2 - ind, H = e.Height }
            local within = (cy + e.Height > clipTop) and (cy < clipBottom)   -- clip por elemento
            e:Draw(within)
            cy = cy + e.Height + 6
        else
            e:Draw(false)
        end
    end
    -- body background (clampeado al clip)
    local bodyTop = y + titleH
    local bodyH = (cy - bodyTop) + 2
    local bt = math.max(bodyTop, clipTop); local bb = math.min(bodyTop + bodyH, clipBottom)
    if shown and bb > bt then setRect(self.bodyBg, nil, x, bt, w, bb - bt, 1); self.bodyBg.Visible = true
    else self.bodyBg.Visible = false end

    local total = titleH + bodyH
    -- outline (clampeado)
    local ot = math.max(y, clipTop); local ob = math.min(y + total, clipBottom)
    if shown and ob > ot then
        self.outline.Position = Vector2.new(x, ot); self.outline.Size = Vector2.new(w, ob - ot)
        self.outline.ZIndex = 6; self.outline.Visible = true
    else self.outline.Visible = false end

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

-- Quitar un groupbox del tab (para que un modulo pueda soltar lo que inyecto)
function Tab:RemoveGroupbox(gb)
    for i, g in ipairs(self.Groupboxes) do
        if g == gb then table.remove(self.Groupboxes, i); break end
    end
    for _, e in ipairs(gb.Elements) do
        e:Draw(false)
        if e.Flag then Library.Flags[e.Flag] = nil; Library.Toggles[e.Flag] = nil; Library.Options[e.Flag] = nil end
    end
    for _, o in ipairs({ gb.bg, gb.bgOl, gb.bodyBg, gb.outline, gb.title }) do o.Visible = false end
    if self.Window then self.Window:Refresh() end
end

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
        -- Size.Y = altura MAXIMA visible del panel; si el contenido excede -> scroll.
        MaxH = (opts.Size and opts.Size.Y and opts.Size.Y > 0) and opts.Size.Y or 600,
        Scroll = 0, MaxScroll = 0,
        Tabs = {},
        ActiveTab = nil,
    }, Window)

    -- scrollbar (barra lateral cuando hay overflow)
    w.scrollBg  = Library:Draw("Square", { Filled = true, Color = Library.Theme.Header })
    w.scrollBar = Library:Draw("Square", { Filled = true, Color = Library.Theme.Accent })

    w.headerBg = Library:Draw("Square", { Filled = true, Color = Library.Theme.Header })
    w.headerOl = Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline })
    w.bg       = Library:Draw("Square", { Filled = true, Color = Library.Theme.Background })
    w.bgOl     = Library:Draw("Square", { Filled = false, Color = Library.Theme.Outline })
    w.accent   = Library:Draw("Square", { Filled = true, Color = Library.Theme.Accent })
    w.titleTxt = Library:Draw("Text",   { Font = Library.Font, Size = Library.FontSize + 1, Color = Library.Theme.Text, Text = w.Title })

    table.insert(Library.Windows, w)
    return w
end

-- buscar un tab ya creado por nombre (permite que un modulo externo inyecte
-- groupboxes en tabs de la base sin que la base sepa nada del modulo)
function Window:GetTab(name)
    for _, t in ipairs(self.Tabs) do
        if t.Name == name then return t end
    end
    return nil
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

    local colW = (self.W - pad * 2 - gap) / 2
    local panelTop = tabY + tabH

    -- 1) MEDIR alto de contenido de cada columna (tab activo)
    local leftH, rightH = 0, 0
    if self.ActiveTab and open then
        for _, gb in ipairs(self.ActiveTab.Groupboxes) do
            local h = gb:MeasureHeight() + gap
            if gb.Side == "Right" then rightH = rightH + h else leftH = leftH + h end
        end
    end
    local fullH = math.max(leftH, rightH)
    if fullH > 0 then fullH = fullH - gap + pad * 2 end   -- padding sup/inf
    local maxH = self.MaxH or 600
    local visibleH = math.min(fullH, maxH)
    if visibleH < 40 then visibleH = 40 end
    self.MaxScroll = math.max(0, fullH - maxH)
    self.Scroll = math.clamp(self.Scroll or 0, 0, self.MaxScroll)
    local totalH = headerH + tabH + visibleH
    local panelBottom = self.Y + totalH

    -- 2) LAYOUT con scroll + clip
    local startY = panelTop + pad - self.Scroll
    local leftY, rightY = startY, startY
    for _, t in ipairs(self.Tabs) do
        local active = (t == self.ActiveTab) and open
        for _, gb in ipairs(t.Groupboxes) do
            if active then
                if gb.Side == "Right" then
                    local h = gb:Layout(self.X + pad + colW + gap, rightY, colW, true, panelTop, panelBottom)
                    rightY = rightY + h + gap
                else
                    local h = gb:Layout(self.X + pad, leftY, colW, true, panelTop, panelBottom)
                    leftY = leftY + h + gap
                end
            else
                gb:Layout(0, 0, colW, false)
            end
        end
    end

    self.bg.Position = Vector2.new(self.X, self.Y); self.bg.Size = Vector2.new(self.W, totalH); self.bg.ZIndex = 0
    self.bgOl.Position = self.bg.Position; self.bgOl.Size = self.bg.Size; self.bgOl.ZIndex = 9
    self.bg.Visible, self.bgOl.Visible = open, open

    -- scrollbar (cuando hay overflow)
    local hasScroll = open and self.MaxScroll > 0
    if hasScroll then
        local trackH = visibleH
        local barH = math.max(20, trackH * (visibleH / fullH))
        local frac = self.Scroll / self.MaxScroll
        local barY = panelTop + frac * (trackH - barH)
        local sx = self.X + self.W - 5
        self.scrollBg.Position = Vector2.new(sx, panelTop); self.scrollBg.Size = Vector2.new(3, trackH); self.scrollBg.ZIndex = 10; self.scrollBg.Visible = true
        self.scrollBar.Position = Vector2.new(sx, barY); self.scrollBar.Size = Vector2.new(3, barH); self.scrollBar.ZIndex = 11; self.scrollBar.Visible = true
    else
        self.scrollBg.Visible = false; self.scrollBar.Visible = false
    end
    self._panelTop, self._panelBottom = panelTop, panelBottom   -- para el hit-test del wheel
end

----------------------------------------------------------------------
-- SHOWCASE  (modelo 3D girando, wireframe, SOLO con Drawing)
--   Library:ShowcaseFromModel(model) -> extrae las aristas de la caja de
--   cada parte visible, en espacio local del modelo.
--   Se rota y se proyecta a mano cada frame: cero ViewportFrame, cero
--   instancias -> la UI sigue siendo invisible a un scan del arbol.
--   El modelo lo elige quien use la lib (la lib no sabe nada del juego).
----------------------------------------------------------------------
local SHOW_MAXLINES = 180
local BOX_EDGES = {
    { 1, 2 }, { 3, 4 }, { 1, 3 }, { 2, 4 },   -- cara -Z
    { 5, 6 }, { 7, 8 }, { 5, 7 }, { 6, 8 },   -- cara +Z
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },   -- union
}
local function boxCorners(cf, size)
    local x, y, z = size.X / 2, size.Y / 2, size.Z / 2
    return {
        cf * Vector3.new(-x, -y, -z), cf * Vector3.new(x, -y, -z),
        cf * Vector3.new(-x,  y, -z), cf * Vector3.new(x,  y, -z),
        cf * Vector3.new(-x, -y,  z), cf * Vector3.new(x, -y,  z),
        cf * Vector3.new(-x,  y,  z), cf * Vector3.new(x,  y,  z),
    }
end

function Library:_ensureShowcase()
    if self.Showcase then return self.Showcase end
    local S = { lines = {}, edges = {}, angle = 0, Title = "" }
    S.bg    = self:Draw("Square", { Filled = true,  Color = self.Theme.Background, Transparency = 0.85 })
    S.bgOl  = self:Draw("Square", { Filled = false, Color = self.Theme.Outline })
    S.hdr   = self:Draw("Square", { Filled = true,  Color = self.Theme.Accent })
    S.title = self:Draw("Text",   { Font = self.Font, Size = self.FontSize, Color = self.Theme.Text, Center = true })
    self.Showcase = S
    return S
end

-- Extrae la geometria de un Model cualquiera y la normaliza a caja unitaria.
function Library:ShowcaseFromModel(model, title)
    local S = self:_ensureShowcase()
    S.edges = {}
    S.Title = title or (model and model.Name) or ""
    if not model then return end
    local okBox, cf, size = pcall(function() local a, b = model:GetBoundingBox() return a, b end)
    if not okBox or not cf then return end
    local scale = math.max(size.X, size.Y, size.Z)
    if scale <= 0 then return end
    scale = 1 / scale
    -- partes visibles ordenadas por volumen: las grandes primero (si hay que
    -- recortar por el cap de lineas, que sobrevivan las que definen la silueta)
    local parts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 1 then
            parts[#parts + 1] = { p = d, vol = d.Size.X * d.Size.Y * d.Size.Z }
        end
    end
    table.sort(parts, function(a, b) return a.vol > b.vol end)
    for _, entry in ipairs(parts) do
        if #S.edges >= SHOW_MAXLINES then break end
        local local_cf = cf:ToObjectSpace(entry.p.CFrame)
        local c = boxCorners(local_cf, entry.p.Size)
        for _, e in ipairs(BOX_EDGES) do
            if #S.edges >= SHOW_MAXLINES then break end
            S.edges[#S.edges + 1] = { c[e[1]] * scale, c[e[2]] * scale }
        end
    end
end

function Library:_hideShowcase()
    local S = self.Showcase
    if not S then return end
    S.bg.Visible, S.bgOl.Visible, S.hdr.Visible, S.title.Visible = false, false, false, false
    for _, l in ipairs(S.lines) do l.Visible = false end
end

-- proyeccion perspectiva a mano (no usa la camara del juego)
function Library:_renderShowcase(dt)
    local S = self.Showcase
    if not (S and self.Open and self.ShowcaseOn and #S.edges > 0) then self:_hideShowcase() return end
    local w = self.Windows[1]
    if not w then self:_hideShowcase() return end

    local size = self.ShowcaseSize or 190
    local x = w.X + w.W + 8            -- pegado al costado derecho de la ventana
    local y = w.Y
    local hdrH = 18
    setRect(S.bg, S.bgOl, x, y, size, size + hdrH, 12)
    S.bgOl.ZIndex = 15
    S.hdr.Position = Vector2.new(x, y); S.hdr.Size = Vector2.new(size, 2); S.hdr.ZIndex = 16
    S.title.Text = S.Title
    S.title.Position = Vector2.new(x + size / 2, y + 3); S.title.ZIndex = 14
    S.bg.Visible, S.bgOl.Visible, S.hdr.Visible, S.title.Visible = true, true, true, true

    S.angle = (S.angle + (dt or 0.016) * (self.ShowcaseSpeed or 0.6)) % (math.pi * 2)
    local a = S.angle
    local ca, sa = math.cos(a), math.sin(a)
    local tilt = 0.35
    local ct, st = math.cos(tilt), math.sin(tilt)
    local cx, cy = x + size / 2, y + hdrH + size / 2
    local focal = size * 1.15
    local dist = 2.6
    local col = self.ShowcaseColor or self.Theme.Accent

    local function project(v)
        local rx = v.X * ca + v.Z * sa          -- yaw
        local rz = -v.X * sa + v.Z * ca
        local ry = v.Y * ct - rz * st           -- pitch
        local rz2 = v.Y * st + rz * ct
        local z = rz2 + dist
        if z < 0.1 then return nil end
        local k = focal / z
        return Vector2.new(cx + rx * k, cy - ry * k)
    end

    for i, e in ipairs(S.edges) do
        local line = S.lines[i]
        if not line then
            line = self:Draw("Line", { Thickness = 1, Color = col })
            S.lines[i] = line
        end
        local p1, p2 = project(e[1]), project(e[2])
        if p1 and p2 then
            line.From, line.To = p1, p2
            line.Color = col; line.ZIndex = 13; line.Visible = true
        else
            line.Visible = false
        end
    end
    for i = #S.edges + 1, #S.lines do S.lines[i].Visible = false end
end

----------------------------------------------------------------------
-- KEYBIND LIST  (panel en pantalla con los binds activos)
--   Library:KeybindList({ Enabled = bool, X = n, Y = n })
--   Lee Library.Keybinds. No sabe nada del juego.
----------------------------------------------------------------------
function Library:_ensureKbList()
    if self.KbList then return self.KbList end
    local K = { rows = {}, MAXROWS = 12 }
    K.bg    = self:Draw("Square", { Filled = true,  Color = self.Theme.Background, Transparency = 0.75 })
    K.bgOl  = self:Draw("Square", { Filled = false, Color = self.Theme.Outline })
    K.hdr   = self:Draw("Square", { Filled = true,  Color = self.Theme.Accent })
    K.title = self:Draw("Text",   { Font = self.Font, Size = self.FontSize, Color = self.Theme.Text, Text = "Keybinds" })
    for i = 1, K.MAXROWS do
        K.rows[i] = {
            name = self:Draw("Text", { Font = self.Font, Size = self.FontSize - 1, Color = self.Theme.Text }),
            key  = self:Draw("Text", { Font = self.Font, Size = self.FontSize - 1, Color = self.Theme.DimText }),
        }
    end
    self.KbList = K
    return K
end

function Library:_hideKbList()
    local K = self.KbList
    if not K then return end
    K.bg.Visible, K.bgOl.Visible, K.hdr.Visible, K.title.Visible = false, false, false, false
    for _, r in ipairs(K.rows) do r.name.Visible, r.key.Visible = false, false end
end

function Library:KeybindList(opts)
    opts = opts or {}
    if not opts.Enabled then self:_hideKbList(); return end
    local K = self:_ensureKbList()
    -- solo los que tienen tecla asignada
    local live = {}
    for _, e in ipairs(self.Keybinds) do
        local k = self.Flags[e.KeyFlag]
        if k and k ~= "None" and #live < K.MAXROWS then live[#live + 1] = e end
    end
    if #live == 0 then self:_hideKbList(); return end

    local pad, rowH, hdrH = 6, 14, 16
    local x, y = opts.X or 12, opts.Y or 12
    -- ancho segun el contenido
    local w = 90
    for _, e in ipairs(live) do
        K.rows[1].name.Text = e.Text
        local need = K.rows[1].name.TextBounds.X + 60
        if need > w then w = need end
    end
    local h = hdrH + pad + #live * rowH + pad

    setRect(K.bg, K.bgOl, x, y, w, h, 90)
    K.bgOl.ZIndex = 93
    K.hdr.Position = Vector2.new(x, y); K.hdr.Size = Vector2.new(w, 2); K.hdr.ZIndex = 94
    K.title.Position = Vector2.new(x + pad, y + 1); K.title.ZIndex = 92
    K.bg.Visible, K.bgOl.Visible, K.hdr.Visible, K.title.Visible = true, true, true, true

    for i, r in ipairs(K.rows) do
        local e = live[i]
        if e then
            local ry = y + hdrH + pad + (i - 1) * rowH
            local mode = self.Flags[e.ModeFlag] or "Toggle"
            local on   = self.Flags[e.Flag] == true
            r.name.Text     = e.Text
            r.name.Color    = on and self.Theme.Text or self.Theme.DimText
            r.name.Position = Vector2.new(x + pad, ry); r.name.ZIndex = 92
            r.key.Text      = "[" .. tostring(self.Flags[e.KeyFlag]) .. "] " .. mode:sub(1, 1)
            r.key.Color     = on and self.Theme.Accent or self.Theme.DimText
            r.key.Position  = Vector2.new(x + w - pad - r.key.TextBounds.X, ry); r.key.ZIndex = 92
            r.name.Visible, r.key.Visible = true, true
        else
            r.name.Visible, r.key.Visible = false, false
        end
    end
end

-- aplicar una tecla apretada/soltada a los keybinds registrados
function Library:_fireKeybinds(keyName, pressed)
    for _, e in ipairs(self.Keybinds) do
        if self.Flags[e.KeyFlag] == keyName then
            local mode = self.Flags[e.ModeFlag] or "Toggle"
            if mode == "Toggle" then
                if pressed then e:Set(not self.Flags[e.Flag]) end
            elseif mode == "Hold" then
                e:Set(pressed)
            elseif mode == "Always" then
                if pressed and not self.Flags[e.Flag] then e:Set(true) end
            end
        end
    end
end

----------------------------------------------------------------------
-- PROMPT  (notificacion modal centrada en pantalla)
--   Library:Prompt({
--       Title   = "Aviso",
--       Lines   = { "texto", { Text = "rojo", Color = Color3.new(1,0,0) } },
--       Buttons = { { Text = "Cargar", Accent = true, Callback = fn }, { Text = "Cancelar" } },
--   })
--   Se dibuja encima de todo, funciona con el menu cerrado y consume
--   todos los clicks mientras esta abierta (modal real).
----------------------------------------------------------------------
local PROMPT_MAXLINES, PROMPT_MAXBTN = 22, 3

function Library:_ensurePrompt()
    if self.PromptUI then return self.PromptUI end
    local P = { lines = {}, buttons = {}, BtnRects = {}, Open = false }
    P.dim    = self:Draw("Square", { Filled = true,  Color = Color3.new(0, 0, 0), Transparency = 0.55 })
    P.bg     = self:Draw("Square", { Filled = true,  Color = self.Theme.Background })
    P.bgOl   = self:Draw("Square", { Filled = false, Color = self.Theme.Outline })
    P.accent = self:Draw("Square", { Filled = true,  Color = self.Theme.Accent })
    P.title  = self:Draw("Text",   { Font = self.Font, Size = self.FontSize + 3, Color = self.Theme.Text, Center = true })
    for i = 1, PROMPT_MAXLINES do
        P.lines[i] = self:Draw("Text", { Font = self.Font, Size = self.FontSize, Color = self.Theme.DimText })
    end
    for i = 1, PROMPT_MAXBTN do
        P.buttons[i] = {
            bg = self:Draw("Square", { Filled = true,  Color = self.Theme.Element }),
            ol = self:Draw("Square", { Filled = false, Color = self.Theme.Outline }),
            tx = self:Draw("Text",   { Font = self.Font, Size = self.FontSize, Color = self.Theme.Text, Center = true }),
        }
    end
    self.PromptUI = P
    return P
end

function Library:Prompt(opts)
    opts = opts or {}
    local P = self:_ensurePrompt()
    local pad, lineH, gap, btnH = 14, 16, 12, 24
    local titleH = self.FontSize + 8

    P.title.Text = tostring(opts.Title or "Aviso")
    local maxW = P.title.TextBounds.X

    local n = 0
    for _, ln in ipairs(opts.Lines or {}) do
        if n >= PROMPT_MAXLINES then break end
        n = n + 1
        local o = P.lines[n]
        if type(ln) == "table" then
            o.Text  = tostring(ln.Text or "")
            o.Color = ln.Color or self.Theme.DimText
        else
            o.Text  = tostring(ln)
            o.Color = self.Theme.DimText
        end
        if o.TextBounds.X > maxW then maxW = o.TextBounds.X end
    end
    for i = n + 1, PROMPT_MAXLINES do P.lines[i].Visible = false end

    local btns = opts.Buttons or { { Text = "OK" } }
    local nb   = math.min(#btns, PROMPT_MAXBTN)
    local w    = math.clamp(maxW + pad * 2, 320, 760)
    local h    = pad + titleH + 6 + n * lineH + gap + btnH + pad

    local cam = workspace.CurrentCamera
    local vp  = (cam and cam.ViewportSize) or Vector2.new(1920, 1080)
    local x   = math.floor(vp.X / 2 - w / 2)
    local y   = math.floor(vp.Y / 2 - h / 2)
    P.X, P.Y, P.W, P.H = x, y, w, h

    P.dim.Position = Vector2.new(0, 0); P.dim.Size = Vector2.new(vp.X, vp.Y); P.dim.ZIndex = 100; P.dim.Visible = true
    setRect(P.bg, P.bgOl, x, y, w, h, 101)
    P.bgOl.ZIndex   = 108
    P.accent.Position = Vector2.new(x, y); P.accent.Size = Vector2.new(w, 2); P.accent.ZIndex = 109
    P.bg.Visible, P.bgOl.Visible, P.accent.Visible = true, true, true
    P.title.Position = Vector2.new(x + w / 2, y + pad); P.title.ZIndex = 102; P.title.Visible = true

    local ly = y + pad + titleH + 6
    for i = 1, n do
        local o = P.lines[i]
        o.Position = Vector2.new(x + pad, ly); o.ZIndex = 102; o.Visible = true
        ly = ly + lineH
    end

    P.BtnRects = {}
    local bw = (w - pad * 2 - (nb - 1) * 8) / math.max(nb, 1)
    local by = y + h - pad - btnH
    for i = 1, PROMPT_MAXBTN do
        local b = P.buttons[i]
        if i <= nb then
            local bx = x + pad + (i - 1) * (bw + 8)
            setRect(b.bg, b.ol, bx, by, bw, btnH, 103)
            b.ol.ZIndex = 104
            b.bg.Color  = btns[i].Accent and self.Theme.Accent or self.Theme.Element
            b.tx.Text   = tostring(btns[i].Text or "OK")
            b.tx.Position = Vector2.new(bx + bw / 2, by + (btnH - self.FontSize) / 2)
            b.tx.ZIndex = 105
            b.bg.Visible, b.ol.Visible, b.tx.Visible = true, true, true
            P.BtnRects[i] = { x = bx, y = by, w = bw, h = btnH, cb = btns[i].Callback }
        else
            b.bg.Visible, b.ol.Visible, b.tx.Visible = false, false, false
        end
    end

    P.Open = true
    self.PromptOpen = true
    return P
end

function Library:ClosePrompt()
    local P = self.PromptUI
    if not P then return end
    P.Open = false
    self.PromptOpen = false
    P.dim.Visible, P.bg.Visible, P.bgOl.Visible, P.accent.Visible, P.title.Visible = false, false, false, false, false
    for _, o in ipairs(P.lines) do o.Visible = false end
    for _, b in ipairs(P.buttons) do b.bg.Visible, b.ol.Visible, b.tx.Visible = false, false, false end
end

function Library:_promptClick(m)
    local P = self.PromptUI
    if not (P and P.Open) then return false end
    for _, r in ipairs(P.BtnRects) do
        if pointInRect(m.X, m.Y, r.x, r.y, r.w, r.h) then
            local cb = r.cb
            self:ClosePrompt()
            self:SafeCallback(cb)
            return true
        end
    end
    return true   -- modal: come todo lo demas
end

----------------------------------------------------------------------
-- global input
----------------------------------------------------------------------
function Library:Toggle(state)
    if state == nil then state = not self.Open end
    local wasOpen = self.Open
    self.Open = state
    if state and not wasOpen then self:SafeCallback(self.OnOpen) end
    if not state then
        self:_hideShowcase()
        if self.OpenDropdown then self.OpenDropdown:Close() end
        if self.OpenPicker then self.OpenPicker:Close() end
    end
    for _, w in ipairs(self.Windows) do w:Refresh() end
end

Library:Connect(UserInputService.InputBegan, function(input, gpe)
    if Library.Unloaded then return end
    -- prompt modal: prioridad absoluta, incluso con el menu cerrado
    if Library.PromptOpen then
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Library:_promptClick(getMouse())
        elseif input.KeyCode == Enum.KeyCode.Escape then
            Library:ClosePrompt()
        end
        return
    end
    -- captura de keybind: la proxima tecla queda bindeada (Escape = limpiar)
    if Library.CapturingKeybind then
        local e = Library.CapturingKeybind
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local kc = input.KeyCode
            Library.Flags[e.KeyFlag] = (kc == Enum.KeyCode.Escape) and "None" or kc.Name
            Library.CapturingKeybind = nil
            for _, w in ipairs(Library.Windows) do w:Refresh() end
            return
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            Library.Flags[e.KeyFlag] = "None"
            Library.CapturingKeybind = nil
            for _, w in ipairs(Library.Windows) do w:Refresh() end
            return
        end
    end
    if input.KeyCode == Library.ToggleKey then
        Library:Toggle()
        return
    end
    -- keybinds de features: andan SIEMPRE, con el menu abierto o cerrado
    if input.UserInputType == Enum.UserInputType.Keyboard and not gpe then
        Library:_fireKeybinds(input.KeyCode.Name, true)
    end
    -- click derecho sobre una caja de tecla: ciclar modo
    if Library.Open and input.UserInputType == Enum.UserInputType.MouseButton2 then
        local m = getMouse()
        for _, w in ipairs(Library.Windows) do
            if w.ActiveTab then
                for _, gb in ipairs(w.ActiveTab.Groupboxes) do
                    for _, e in ipairs(gb.Elements) do
                        if e.HandleRightClick and Library:DepsMet(e) and e:HandleRightClick(m) then return end
                    end
                end
            end
        end
    end
    if not Library.Open then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local m = getMouse()
        if Library.OpenPicker then
            if Library:_pickerPopupClick(m) then return end
            -- click on the swatch toggles; anything else closes
            if not Library.OpenPicker:HandleClick(m) then
                Library.OpenPicker:Close()
            end
            return
        end
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
        elseif Library.PickerDrag then
            Library:_pickerDrag(m)
        end
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        local m = getMouse()
        for _, w in ipairs(Library.Windows) do
            if (w.MaxScroll or 0) > 0 and pointInRect(m.X, m.Y, w.X, w.Y, w.W, w.bg.Size.Y) then
                w.Scroll = math.clamp((w.Scroll or 0) - input.Position.Z * 45, 0, w.MaxScroll)
                w:Refresh()
                return
            end
        end
    end
end)

-- unico loop por frame de la lib: solo para el modelo girando
Library:Connect(RunService.RenderStepped, function(dt)
    if Library.Unloaded then return end
    if Library.ShowcaseOn and Library.Open then
        pcall(function() Library:_renderShowcase(dt) end)
    end
end)

Library:Connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        Library.Dragging = nil
        Library.ActiveSlider = nil
        Library.PickerDrag = nil
    elseif input.UserInputType == Enum.UserInputType.Keyboard and not Library.Unloaded then
        Library:_fireKeybinds(input.KeyCode.Name, false)   -- soltar tecla: apaga los Hold
    end
end)

----------------------------------------------------------------------
-- UNLOAD
----------------------------------------------------------------------
function Library:Unload()
    if self.Unloaded then return end
    self.Unloaded = true
    self.PromptOpen = false
    self.PromptUI   = nil
    self.KbList     = nil
    self.Showcase   = nil
    self.CapturingKeybind = nil
    table.clear(self.Keybinds)
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
