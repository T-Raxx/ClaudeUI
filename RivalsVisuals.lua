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

local PARTICLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

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
        Bloom = false,
        BloomIntensity = 0.4,
        BloomSize = 24,
        BloomThreshold = 0.95,
        Blur = false,
        BlurSize = 4,
        SunRays = false,
        SunRaysIntensity = 0.05,
        SunRaysSpread = 0.5,
        -- cielo
        NoSky = false,
        CloudsMode = "Juego",     -- Juego | Custom | Off
        CloudCover = 0.5,
        CloudDensity = 0.7,
        CloudColor = Color3.fromRGB(255, 255, 255),
        -- clima
        Weather = "Off",          -- Off | Lluvia | Lluvia fuerte | Nieve
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
    if self:_flag("Atmosphere", false) then
        local a = self:_fx("Atmosphere")
        a.Density = self:_flag("AtmDensity", 0.3)
        a.Offset  = self:_flag("AtmOffset", 0.25)
        a.Glare   = self:_flag("AtmGlare", 0)
        a.Haze    = self:_flag("AtmHaze", 0)
        a.Color   = self:_flag("AtmColor", self.Settings.AtmColor)
        a.Decay   = self:_flag("AtmDecay", self.Settings.AtmDecay)
    elseif self._fxCache and self._fxCache.Atmosphere then
        self._fxCache.Atmosphere.Density = 0
    end
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
    local bl = self:_fx("BloomEffect")
    bl.Enabled = self:_flag("Bloom", false)
    if bl.Enabled then
        bl.Intensity = self:_flag("BloomIntensity", 0.4)
        bl.Size      = self:_flag("BloomSize", 24)
        bl.Threshold = self:_flag("BloomThreshold", 0.95)
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
    local mode = self:_flag("CloudsMode", "Juego")
    if mode == "Juego" then
        if clouds and self._orig[clouds] then
            for prop, val in pairs(self._orig[clouds]) do pcall(function() clouds[prop] = val end) end
        end
        return
    end
    if not clouds then
        if mode == "Off" then return end
        clouds = self:_fx("Clouds", Terrain)
    end
    if mode == "Off" then
        self:_set(clouds, "Enabled", false)
    else
        self:_set(clouds, "Enabled", true)
        self:_set(clouds, "Cover", self:_flag("CloudCover", 0.5))
        self:_set(clouds, "Density", self:_flag("CloudDensity", 0.7))
        self:_set(clouds, "Color", self:_flag("CloudColor", Color3.new(1, 1, 1)))
    end
end

----------------------------------------------------------------------
-- CLIMA
--   Part anclado arriba de la camara + ParticleEmitter. Sigue a la
--   camara cada frame -> el clima te acompana por todo el mapa sin
--   tocar nada del juego.
----------------------------------------------------------------------
local WX = {
    ["Lluvia"] = {
        rate = 220, speed = 90, life = 1.1, size = 0.32, squash = 14,
        spread = 3, drag = 0, accel = Vector3.new(0, -30, 0), transp = 0.35, light = 0.4,
    },
    ["Lluvia fuerte"] = {
        rate = 900, speed = 135, life = 0.9, size = 0.42, squash = 20,
        spread = 6, drag = 0, accel = Vector3.new(-8, -60, 0), transp = 0.2, light = 0.5,
    },
    ["Nieve"] = {
        rate = 240, speed = 7, life = 5.5, size = 0.45, squash = 0,
        spread = 28, drag = 2.5, accel = Vector3.new(1.5, -3, 0.8), transp = 0.1, light = 0.8,
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
    e.Texture = PARTICLE_TEX
    e.Enabled = false
    e.EmissionDirection = Enum.NormalId.Bottom
    e.Rotation = NumberRange.new(0, 360)
    e.LockedToPart = false
    e.Parent = p
    self._wxPart, self._wxEmit = p, e
    table.insert(self._made, p)
    return p, e
end

function V:_applyWeather()
    local mode = self:_flag("Weather", "Off")
    if mode == "Off" then
        if self._wxEmit then self._wxEmit.Enabled = false end
        return
    end
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
        emit.EmissionDirection = Enum.NormalId.Bottom
        emit.Drag     = cfg.drag
        emit.Squash   = NumberSequence.new(cfg.squash)
        emit.SpreadAngle = Vector2.new(cfg.spread, cfg.spread)
        emit.Transparency = NumberSequence.new(cfg.transp)
        emit.LightEmission = cfg.light
        emit.ZOffset = 0
    end
    local dens = self:_flag("WeatherDensity", 1)
    local spd  = self:_flag("WeatherSpeed", 1)
    local sz   = self:_flag("WeatherSize", 1)
    emit.Rate       = cfg.rate * dens
    emit.Lifetime   = NumberRange.new(cfg.life)
    emit.Speed      = NumberRange.new(cfg.speed * spd)
    emit.Acceleration = cfg.accel * spd
    emit.Size       = NumberSequence.new(cfg.size * sz)
    emit.Color      = ColorSequence.new(self:_flag("WeatherColor", self.Settings.WeatherColor))
    emit.Enabled    = true
end

----------------------------------------------------------------------
function V:_step()
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
        for _, inst in pairs(self._fxCache) do
            pcall(function() if inst:IsA("PostEffect") then inst.Enabled = false end end)
        end
        if self._fxCache.Atmosphere then pcall(function() self._fxCache.Atmosphere.Density = 0 end) end
    end
    self:_restoreAll()
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function V:BuildUI(Library, Window)
    if self._uiTab then return self._uiTab end
    local T = Window:AddTab("Mundo")
    self._uiTab = T

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
    local atm = f:AddToggle("Vis_Atmosphere", { Text = "Atmosfera", Default = false })
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
    local bm = t:AddToggle("Vis_Bloom", { Text = "Bloom", Default = false })
    bm:AddSlider("Vis_BloomIntensity", { Text = "Intensidad", Min = 0, Max = 5, Default = 0.4, Decimals = 2 })
    bm:AddSlider("Vis_BloomSize",      { Text = "Tamano", Min = 0, Max = 56, Default = 24 })
    bm:AddSlider("Vis_BloomThreshold", { Text = "Umbral", Min = 0, Max = 3, Default = 0.95, Decimals = 2 })
    local bl = t:AddToggle("Vis_Blur", { Text = "Blur", Default = false })
    bl:AddSlider("Vis_BlurSize", { Text = "Tamano", Min = 0, Max = 30, Default = 4 })
    local sr = t:AddToggle("Vis_SunRays", { Text = "Rayos de sol", Default = false })
    sr:AddSlider("Vis_SunRaysIntensity", { Text = "Intensidad", Min = 0, Max = 1, Default = 0.05, Decimals = 3 })
    sr:AddSlider("Vis_SunRaysSpread",    { Text = "Dispersion", Min = 0, Max = 1, Default = 0.5, Decimals = 2 })

    local s = T:AddRightGroupbox("Cielo / nubes")
    s:AddToggle("Vis_NoSky", { Text = "Sin cuerpos celestes", Default = false })
    s:AddDropdown("Vis_CloudsMode", { Text = "Nubes", Values = { "Juego", "Custom", "Off" }, Default = "Juego" })
    s:AddSlider("Vis_CloudCover",   { Text = "Cobertura", Min = 0, Max = 1, Default = 0.5, Decimals = 2 })
    s:AddSlider("Vis_CloudDensity", { Text = "Densidad", Min = 0, Max = 1, Default = 0.7, Decimals = 2 })
    s:AddColorPicker("Vis_CloudColor", { Text = "Color nubes", Default = Color3.fromRGB(255, 255, 255) })

    local c = T:AddLeftGroupbox("Clima")
    c:AddLabel("Particulas locales: solo las ves vos")
    c:AddDropdown("Vis_Weather", { Text = "Clima", Values = { "Off", "Lluvia", "Lluvia fuerte", "Nieve" }, Default = "Off" })
    c:AddSlider("Vis_WeatherDensity", { Text = "Densidad", Min = 0.1, Max = 4, Default = 1, Decimals = 2, Suffix = "x" })
    c:AddSlider("Vis_WeatherSpeed",   { Text = "Velocidad", Min = 0.1, Max = 3, Default = 1, Decimals = 2, Suffix = "x" })
    c:AddSlider("Vis_WeatherSize",    { Text = "Tamano", Min = 0.2, Max = 4, Default = 1, Decimals = 2, Suffix = "x" })
    c:AddSlider("Vis_WeatherArea",    { Text = "Area", Min = 30, Max = 200, Default = 90, Suffix = "st" })
    c:AddColorPicker("Vis_WeatherColor", { Text = "Color", Default = Color3.fromRGB(220, 230, 255) })

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
    for _, inst in ipairs(self._made) do pcall(function() inst:Destroy() end) end
    table.clear(self._made)
    self._fxCache = nil
    self._wxPart, self._wxEmit, self._lastWx = nil, nil, nil
end

return V
