--[[
    RivalsVisuals  -  update visual clientside (build 0.7)
    ------------------------------------------------------------------
    Mundo (lighting/fog/atmosfera/tinte/cielo/nubes) + clima custom
    (lluvia / lluvia fuerte / nieve). CERO hooks: solo escribe
    propiedades de Lighting/Terrain y crea efectos propios.

    GOTCHA LightingController: el juego tiene PlayerScripts.Controllers.
    LightingController que en cambio de mapa hace:
        _LoadMapLightingAssets(profile) -> clona LightingProfiles2[p] a
            Lighting (o Terrain si es Clouds), todo con Name="LightingController"
        _LoadMapLightingModule(profile) -> escribe LightingProperties,
            TerrainProperties, TerrainMaterials, SoundServiceProperties
    Es POR EVENTO (solo al cambiar de perfil), NO por frame -> alcanza con
    re-aplicar lo nuestro en loop y escribir solo si el valor difiere.
    Sus _assets se destruyen por referencia, no por nombre.

    GOTCHA texturas de particulas: se usan rutas rbxasset:// que vienen con
    el cliente (no assets de catalogo) -> no dependen de red ni pueden 404.
------------------------------------------------------------------ ]]

local Lighting   = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Terrain    = workspace:FindFirstChildOfClass("Terrain")

-- Texturas de particulas del PROPIO juego (ya cargadas, no dependen de red ni
-- pueden faltar). sparkles_main.dds del cliente es un GLOW redondo: estirado con
-- Squash da "lineas random", no lluvia. streaks = trazo real de gota.
local TEX_RAIN = "rbxassetid://13911374915"   -- "streaks"
local TEX_SNOW = "rbxassetid://15414665346"   -- "dots"

local V = {
    Conns   = {},
    Loaded  = false,
    Flags   = nil,
    _orig   = {},    -- [instancia] = { prop = valorOriginal }
    _made   = {},    -- instancias que creamos nosotros (se destruyen al unload)
    _lastWx = nil,
    Settings = {
        Enabled = false,
        -- mundo
        Fullbright = false,
        Ambient = Color3.fromRGB(120, 120, 125),
        Brightness = 3,
        ClockTime = 12,
        Exposure = 0,
        NoShadows = false,
        -- fog / atmosfera
        NoFog = false,
        FogStart = 0,
        FogEnd = 2500,
        FogColor = Color3.fromRGB(190, 195, 210),
        Atmosphere = false,
        AtmDensity = 0.3,
        AtmOffset = 0.25,
        AtmGlare = 0,
        AtmHaze = 0,
        AtmColor = Color3.fromRGB(199, 199, 199),
        AtmDecay = Color3.fromRGB(106, 112, 125),
        -- tinte / post
        Tint = false,
        TintBrightness = 0,
        TintContrast = 0,
        TintSaturation = 0,
        TintColor = Color3.fromRGB(255, 255, 255),
        MenuBloom = false,          -- bloom SOLO con el menu abierto (vive en Settings)
        MenuBloomIntensity = 0.7,
        MenuBloomSize = 24,
        MenuBloomThreshold = 0.9,
        Blur = false,
        BlurSize = 4,
        SunRays = false,
        SunRaysIntensity = 0.05,
        SunRaysSpread = 0.5,
        -- cielo
        NoSky = false,
        Clouds = false,           -- toggle: off = nubes del juego intactas
        NoClouds = false,
        CloudCover = 0.5,
        CloudDensity = 0.7,
        CloudColor = Color3.fromRGB(255, 255, 255),
        -- clima
        Weather = false,
        WeatherMode = "Lluvia",   -- Lluvia | Lluvia fuerte | Nieve
        WeatherTransparency = 0.35,
        WeatherGlow = 0.15,
        WeatherDensity = 1,
        WeatherSpeed = 1,
        WeatherSize = 1,
        WeatherColor = Color3.fromRGB(220, 230, 255),
        WeatherArea = 90,
    },
}

function V:_flag(k, d)
    if self.Flags then local v = self.Flags["Vis_" .. k]; if v ~= nil then return v end end
    local s = self.Settings[k]
    if s ~= nil then return s end
    return d
end
function V:BindFlags(ft) self.Flags = ft end

----------------------------------------------------------------------
-- escritura con memoria: guarda el original la primera vez y solo
-- escribe si el valor actual difiere (le gana al LightingController sin
-- pelear cada frame por nada)
----------------------------------------------------------------------
function V:_set(obj, prop, val)
    if not obj then return end
    local ok, cur = pcall(function() return obj[prop] end)
    if not ok then return end
    local mem = self._orig[obj]
    if not mem then mem = {}; self._orig[obj] = mem end
    if mem[prop] == nil then mem[prop] = cur end
    if cur ~= val then pcall(function() obj[prop] = val end) end
end

function V:_restoreAll()
    for obj, props in pairs(self._orig) do
        for prop, val in pairs(props) do
            pcall(function() obj[prop] = val end)
        end
    end
    table.clear(self._orig)
end

-- crear (una vez) un efecto propio. Se nombra como los del juego para no
-- cantar en un scan del arbol de Lighting.
function V:_fx(class, parent)
    self._fxCache = self._fxCache or {}
    local got = self._fxCache[class]
    if got and got.Parent then return got end
    local inst = Instance.new(class)
    inst.Name = "LightingController"
    inst.Parent = parent or Lighting
    self._fxCache[class] = inst
    table.insert(self._made, inst)
    return inst
end

----------------------------------------------------------------------
-- MUNDO
----------------------------------------------------------------------
function V:_applyWorld()
    if self:_flag("Fullbright", false) then
        self:_set(Lighting, "Ambient", Color3.fromRGB(255, 255, 255))
        self:_set(Lighting, "OutdoorAmbient", Color3.fromRGB(255, 255, 255))
        self:_set(Lighting, "Brightness", 1)
        self:_set(Lighting, "GlobalShadows", false)
    else
        self:_set(Lighting, "Ambient", self:_flag("Ambient", self.Settings.Ambient))
        self:_set(Lighting, "OutdoorAmbient", self:_flag("Ambient", self.Settings.Ambient))
        self:_set(Lighting, "Brightness", self:_flag("Brightness", 3))
        self:_set(Lighting, "GlobalShadows", not self:_flag("NoShadows", false))
    end
    self:_set(Lighting, "ClockTime", self:_flag("ClockTime", 12))
    self:_set(Lighting, "ExposureCompensation", self:_flag("Exposure", 0))
end

----------------------------------------------------------------------
-- FOG / ATMOSFERA
----------------------------------------------------------------------
function V:_applyFog()
    if self:_flag("NoFog", false) then
        self:_set(Lighting, "FogStart", 0)
        self:_set(Lighting, "FogEnd", 1e6)
    else
        self:_set(Lighting, "FogStart", self:_flag("FogStart", 0))
        self:_set(Lighting, "FogEnd", self:_flag("FogEnd", 2500))
        self:_set(Lighting, "FogColor", self:_flag("FogColor", self.Settings.FogColor))
    end
    -- OJO: la sola PRESENCIA de un Atmosphere anula FogStart/FogEnd/FogColor.
    -- Density=0 no alcanza: hay que DESTRUIRLO o el fog queda muerto para siempre
    -- (ese era el bug de "fog no funciona" tras tocar el toggle de atmosfera).
    if self:_flag("Atmosphere", false) then
        local a = self:_fx("Atmosphere")
        a.Density = self:_flag("AtmDensity", 0.3)
        a.Offset  = self:_flag("AtmOffset", 0.25)
        a.Glare   = self:_flag("AtmGlare", 0)
        a.Haze    = self:_flag("AtmHaze", 0)
        a.Color   = self:_flag("AtmColor", self.Settings.AtmColor)
        a.Decay   = self:_flag("AtmDecay", self.Settings.AtmDecay)
    else
        self:_killAtmosphere()
    end
end

function V:_killAtmosphere()
    local a = self._fxCache and self._fxCache.Atmosphere
    if not a then return end
    for i, inst in ipairs(self._made) do
        if inst == a then table.remove(self._made, i) break end
    end
    pcall(function() a:Destroy() end)
    self._fxCache.Atmosphere = nil
end

----------------------------------------------------------------------
-- TINTE / POST
----------------------------------------------------------------------
function V:_applyTint()
    local cc = self:_fx("ColorCorrectionEffect")
    cc.Enabled = self:_flag("Tint", false)
    if cc.Enabled then
        cc.Brightness = self:_flag("TintBrightness", 0)
        cc.Contrast   = self:_flag("TintContrast", 0)
        cc.Saturation = self:_flag("TintSaturation", 0)
        cc.TintColor  = self:_flag("TintColor", Color3.new(1, 1, 1))
    end
    local bu = self:_fx("BlurEffect")
    bu.Enabled = self:_flag("Blur", false)
    if bu.Enabled then bu.Size = self:_flag("BlurSize", 4) end
    local sr = self:_fx("SunRaysEffect")
    sr.Enabled = self:_flag("SunRays", false)
    if sr.Enabled then
        sr.Intensity = self:_flag("SunRaysIntensity", 0.05)
        sr.Spread    = self:_flag("SunRaysSpread", 0.5)
    end
end

----------------------------------------------------------------------
-- CIELO / NUBES
----------------------------------------------------------------------
function V:_applySky()
    -- skybox del juego (Sky llamado "LightingController")
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then
        local off = self:_flag("NoSky", false)
        self:_set(sky, "CelestialBodiesShown", not off)
        self:_set(sky, "StarCount", off and 0 or 3000)
    end
    if not Terrain then return end
    local clouds = Terrain:FindFirstChildOfClass("Clouds")
    if not self:_flag("Clouds", false) then
        -- toggle off = nubes del juego intactas (_restoreAll devuelve lo que tocamos)
        return
    end
    if not clouds then clouds = self:_fx("Clouds", Terrain) end
    self:_set(clouds, "Enabled", not self:_flag("NoClouds", false))
    self:_set(clouds, "Cover", self:_flag("CloudCover", 0.5))
    self:_set(clouds, "Density", self:_flag("CloudDensity", 0.7))
    self:_set(clouds, "Color", self:_flag("CloudColor", Color3.new(1, 1, 1)))
end

-- Bloom del MENU: es estetica de la UI, no del mundo -> vive en Settings, no
-- depende del master de visuales y solo prende con el menu abierto (igual que
-- el "GlowyBackgroundBlur - MainGui" que ya usa el juego).
function V:_applyMenuFX()
    local want = self:_flag("MenuBloom", false) and (self._lib and self._lib.Open) or false
    if not want then
        local b = self._fxCache and self._fxCache.BloomEffect
        if b then b.Enabled = false end
        return
    end
    local bl = self:_fx("BloomEffect")
    bl.Enabled   = true
    bl.Intensity = self:_flag("MenuBloomIntensity", 0.7)
    bl.Size      = self:_flag("MenuBloomSize", 24)
    bl.Threshold = self:_flag("MenuBloomThreshold", 0.9)
end

----------------------------------------------------------------------
-- CLIMA
--   Part anclado arriba de la camara + ParticleEmitter. Sigue a la
--   camara cada frame -> el clima te acompana por todo el mapa sin
--   tocar nada del juego.
----------------------------------------------------------------------
--[[ La lluvia se veia como "lineas random" por DOS motivos:
     1) Rotation = NumberRange.new(0,360) -> cada gota rotada al azar. La lluvia
        real cae toda en la misma direccion -> rotacion FIJA por modo.
     2) textura de glow redondo estirada con Squash -> trazo sucio, no gota.
     La nieve se comia el color del user porque LightEmission=0.8 la hacia emitir
     luz blanca propia. Con glow bajo el color manda, y la sutileza sale de
     glow/transparencia (sliders), NO de forzar gris. ]]
local WX = {
    ["Lluvia"] = {
        tex = TEX_RAIN, rate = 400, speed = 105, life = 1.0, size = 0.9,
        squash = 6, spread = 1.5, drag = 0, accel = Vector3.new(0, -35, 0),
        transp = 0.45, light = 0.15, rot = 0, rotSpeed = 0, tilt = -3,
    },
    ["Lluvia fuerte"] = {
        tex = TEX_RAIN, rate = 1400, speed = 150, life = 0.85, size = 1.15,
        squash = 9, spread = 2.5, drag = 0, accel = Vector3.new(-14, -70, 0),
        transp = 0.3, light = 0.2, rot = -9, rotSpeed = 0, tilt = -9,
    },
    ["Nieve"] = {
        tex = TEX_SNOW, rate = 190, speed = 6, life = 6.5, size = 0.28,
        squash = 0, spread = 26, drag = 2.8, accel = Vector3.new(1.2, -2.4, 0.7),
        transp = 0.25, light = 0.05, rot = 0, rotSpeed = 22, tilt = 0,
    },
}

function V:_wxRig()
    if self._wxPart and self._wxPart.Parent then return self._wxPart, self._wxEmit end
    local p = Instance.new("Part")
    p.Name = "Camera"          -- nombre inocuo dentro de workspace
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = Vector3.new(1, 1, 1)
    p.Parent = workspace
    local e = Instance.new("ParticleEmitter")
    e.Enabled = false
    e.EmissionDirection = Enum.NormalId.Bottom
    e.LockedToPart = false
    e.Parent = p
    self._wxPart, self._wxEmit = p, e
    table.insert(self._made, p)
    return p, e
end

function V:_applyWeather()
    if not self:_flag("Weather", false) then
        if self._wxEmit then self._wxEmit.Enabled = false end
        self._lastWx = nil
        return
    end
    local mode = self:_flag("WeatherMode", "Lluvia")
    local cfg = WX[mode]
    if not cfg then return end
    local part, emit = self:_wxRig()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local area = self:_flag("WeatherArea", 90)
    -- el emisor va arriba de la camara y la sigue
    part.Size = Vector3.new(area, 1, area)
    part.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 28, 0))

    if self._lastWx ~= mode then       -- reconfigurar solo al cambiar de modo
        self._lastWx = mode
        emit.Texture   = cfg.tex
        emit.Drag      = cfg.drag
        emit.Squash    = NumberSequence.new(cfg.squash)
        emit.SpreadAngle = Vector2.new(cfg.spread, cfg.spread)
        emit.Rotation  = NumberRange.new(cfg.rot)          -- FIJA: la lluvia cae pareja
        emit.RotSpeed  = NumberRange.new(-cfg.rotSpeed, cfg.rotSpeed)
        emit.ZOffset   = 0
        emit.EmissionDirection = Enum.NormalId.Bottom
    end
    local dens = self:_flag("WeatherDensity", 1)
    local spd  = self:_flag("WeatherSpeed", 1)
    local sz   = self:_flag("WeatherSize", 1)
    emit.Rate       = cfg.rate * dens
    emit.Lifetime   = NumberRange.new(cfg.life * 0.85, cfg.life)
    emit.Speed      = NumberRange.new(cfg.speed * spd * 0.9, cfg.speed * spd)
    emit.Acceleration = cfg.accel * spd
    emit.Size       = NumberSequence.new(cfg.size * sz)
    emit.Color      = ColorSequence.new(self:_flag("WeatherColor", self.Settings.WeatherColor))
    -- glow/transparencia configurables: la sutileza NO viene de forzar el color
    emit.LightEmission = self:_flag("WeatherGlow", cfg.light)
    emit.Transparency  = NumberSequence.new(self:_flag("WeatherTransparency", cfg.transp))
    emit.Enabled    = true
end

----------------------------------------------------------------------
function V:_step()
    self:_applyMenuFX()   -- estetica del menu: fuera del master de visuales
    if not self:_flag("Enabled", false) then
        if self._wasOn then self:_off() end
        return
    end
    self._wasOn = true
    self:_applyWorld()
    self:_applyFog()
    self:_applyTint()
    self:_applySky()
    self:_applyWeather()
end

function V:_off()
    self._wasOn = false
    self._lastWx = nil
    if self._wxEmit then self._wxEmit.Enabled = false end
    if self._fxCache then
        for class, inst in pairs(self._fxCache) do
            -- el bloom del menu NO se apaga aca: no depende del master
            if class ~= "BloomEffect" then
                pcall(function() if inst:IsA("PostEffect") then inst.Enabled = false end end)
            end
        end
    end
    self:_killAtmosphere()   -- destruir, no Density=0: si queda, mata el fog
    self:_restoreAll()
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function V:BuildUI(Library, Window)
    if self._uiTab then return self._uiTab end
    self._lib = Library          -- para saber si el menu esta abierto (bloom)
    local T = Window:AddTab("Mundo")
    self._uiTab = T

    -- Bloom = estetica del MENU, no del mundo -> se inyecta en Settings y no
    -- depende del master de visuales.
    local st = Window:GetTab("Settings")
    if st then
        local mb  = st:AddLeftGroupbox("Menu FX")
        local mbe = mb:AddToggle("Vis_MenuBloom", { Text = "Bloom con el menu abierto", Default = false })
        mbe:AddSlider("Vis_MenuBloomIntensity", { Text = "Intensidad", Min = 0, Max = 5, Default = 0.7, Decimals = 2 })
        mbe:AddSlider("Vis_MenuBloomSize",      { Text = "Tamano", Min = 0, Max = 56, Default = 24 })
        mbe:AddSlider("Vis_MenuBloomThreshold", { Text = "Umbral", Min = 0, Max = 3, Default = 0.9, Decimals = 2 })
        self._menuBox, self._menuTab = mb, st
    end

    local w = T:AddLeftGroupbox("Mundo")
    local en = w:AddToggle("Vis_Enabled", { Text = "Enable visuales", Default = false, Keybind = true })
    en:AddToggle("Vis_Fullbright", { Text = "Fullbright", Default = false })
    en:AddToggle("Vis_NoShadows",  { Text = "Sin sombras", Default = false })
    en:AddColorPicker("Vis_Ambient", { Text = "Ambient", Default = Color3.fromRGB(120, 120, 125) })
    en:AddSlider("Vis_Brightness", { Text = "Brillo", Min = 0, Max = 10, Default = 3, Decimals = 1 })
    en:AddSlider("Vis_ClockTime",  { Text = "Hora del dia", Min = 0, Max = 24, Default = 12, Decimals = 1, Suffix = "h" })
    en:AddSlider("Vis_Exposure",   { Text = "Exposicion", Min = -3, Max = 3, Default = 0, Decimals = 2 })

    local f = T:AddLeftGroupbox("Fog / Atmosfera")
    f:AddToggle("Vis_NoFog", { Text = "Sin fog (ver lejos)", Default = false })
    f:AddSlider("Vis_FogStart", { Text = "Fog inicio", Min = 0, Max = 2000, Default = 0, Suffix = "st" })
    f:AddSlider("Vis_FogEnd",   { Text = "Fog fin", Min = 100, Max = 10000, Default = 2500, Suffix = "st" })
    f:AddColorPicker("Vis_FogColor", { Text = "Color fog", Default = Color3.fromRGB(190, 195, 210) })
    f:AddLabel("Atmosfera ON = el fog de arriba se ignora")
    local atm = f:AddToggle("Vis_Atmosphere", { Text = "Atmosfera (reemplaza el fog)", Default = false })
    atm:AddSlider("Vis_AtmDensity", { Text = "Densidad", Min = 0, Max = 1, Default = 0.3, Decimals = 3 })
    atm:AddSlider("Vis_AtmOffset",  { Text = "Offset", Min = 0, Max = 1, Default = 0.25, Decimals = 2 })
    atm:AddSlider("Vis_AtmGlare",   { Text = "Glare", Min = 0, Max = 10, Default = 0, Decimals = 1 })
    atm:AddSlider("Vis_AtmHaze",    { Text = "Haze", Min = 0, Max = 10, Default = 0, Decimals = 1 })
    atm:AddColorPicker("Vis_AtmColor", { Text = "Color", Default = Color3.fromRGB(199, 199, 199) })
    atm:AddColorPicker("Vis_AtmDecay", { Text = "Decay", Default = Color3.fromRGB(106, 112, 125) })

    local t = T:AddRightGroupbox("Tinte / post")
    local ti = t:AddToggle("Vis_Tint", { Text = "Tinte (ColorCorrection)", Default = false })
    ti:AddSlider("Vis_TintBrightness", { Text = "Brillo", Min = -1, Max = 1, Default = 0, Decimals = 2 })
    ti:AddSlider("Vis_TintContrast",   { Text = "Contraste", Min = -1, Max = 1, Default = 0, Decimals = 2 })
    ti:AddSlider("Vis_TintSaturation", { Text = "Saturacion", Min = -1, Max = 3, Default = 0, Decimals = 2 })
    ti:AddColorPicker("Vis_TintColor", { Text = "Color", Default = Color3.fromRGB(255, 255, 255) })
    local bl = t:AddToggle("Vis_Blur", { Text = "Blur", Default = false })
    bl:AddSlider("Vis_BlurSize", { Text = "Tamano", Min = 0, Max = 30, Default = 4 })
    local sr = t:AddToggle("Vis_SunRays", { Text = "Rayos de sol", Default = false })
    sr:AddSlider("Vis_SunRaysIntensity", { Text = "Intensidad", Min = 0, Max = 1, Default = 0.05, Decimals = 3 })
    sr:AddSlider("Vis_SunRaysSpread",    { Text = "Dispersion", Min = 0, Max = 1, Default = 0.5, Decimals = 2 })

    local s = T:AddRightGroupbox("Cielo / nubes")
    s:AddToggle("Vis_NoSky", { Text = "Sin cuerpos celestes", Default = false })
    local cl = s:AddToggle("Vis_Clouds", { Text = "Nubes custom", Default = false })
    cl:AddToggle("Vis_NoClouds",     { Text = "Sin nubes", Default = false })
    cl:AddSlider("Vis_CloudCover",   { Text = "Cobertura", Min = 0, Max = 1, Default = 0.5, Decimals = 2 })
    cl:AddSlider("Vis_CloudDensity", { Text = "Densidad", Min = 0, Max = 1, Default = 0.7, Decimals = 2 })
    cl:AddColorPicker("Vis_CloudColor", { Text = "Color nubes", Default = Color3.fromRGB(255, 255, 255) })

    local c = T:AddLeftGroupbox("Clima")
    c:AddLabel("Particulas locales: solo las ves vos")
    local wx = c:AddToggle("Vis_Weather", { Text = "Clima", Default = false, Keybind = true })
    wx:AddDropdown("Vis_WeatherMode", { Text = "Tipo", Values = { "Lluvia", "Lluvia fuerte", "Nieve" }, Default = "Lluvia" })
    wx:AddColorPicker("Vis_WeatherColor", { Text = "Color", Default = Color3.fromRGB(220, 230, 255) })
    wx:AddSlider("Vis_WeatherTransparency", { Text = "Transparencia", Min = 0, Max = 1, Default = 0.35, Decimals = 2 })
    wx:AddSlider("Vis_WeatherGlow",    { Text = "Brillo propio", Min = 0, Max = 1, Default = 0.15, Decimals = 2 })
    wx:AddSlider("Vis_WeatherDensity", { Text = "Densidad", Min = 0.1, Max = 4, Default = 1, Decimals = 2, Suffix = "x" })
    wx:AddSlider("Vis_WeatherSpeed",   { Text = "Velocidad", Min = 0.1, Max = 3, Default = 1, Decimals = 2, Suffix = "x" })
    wx:AddSlider("Vis_WeatherSize",    { Text = "Tamano", Min = 0.2, Max = 4, Default = 1, Decimals = 2, Suffix = "x" })
    wx:AddSlider("Vis_WeatherArea",    { Text = "Area", Min = 30, Max = 200, Default = 90, Suffix = "st" })
    c:AddLabel("Brillo bajo = el color se ve real")

    return T
end

function V:Init()
    if self.Loaded then return self end
    self.Loaded = true
    self.Conns[#self.Conns + 1] = RunService.RenderStepped:Connect(function()
        local ok, err = pcall(function() self:_step() end)
        if not ok then warn("[RivalsVisuals] " .. tostring(err)) end
    end)
    return self
end

function V:Unload()
    if not self.Loaded then return end
    self.Loaded = false
    for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
    table.clear(self.Conns)
    self:_restoreAll()
    if self._menuBox and self._menuTab and self._menuTab.RemoveGroupbox then
        pcall(function() self._menuTab:RemoveGroupbox(self._menuBox) end)
    end
    self._menuBox, self._menuTab = nil, nil
    for _, inst in ipairs(self._made) do pcall(function() inst:Destroy() end) end
    table.clear(self._made)
    self._fxCache = nil
    self._wxPart, self._wxEmit, self._lastWx = nil, nil, nil
end

return V
