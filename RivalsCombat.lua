--[[
    RivalsCombat  -  combat legit (build 0.8)
    ------------------------------------------------------------------
    TODO via la API del propio juego. Cero hooks, cero funciones de
    executor: solo se llaman metodos y se escriben campos que el
    CameraController ya lee por su cuenta.

      Tercera persona : CameraController:SetThirdPersonOverride(true)
          HasThirdPersonAccess() arranca con
              if _third_person_override ~= nil then return _third_person_override
          y si no, solo la da con handicaps o en mobile (Touch). El override
          la desbloquea. El POV se cambia con CameraState:TogglePOV(), que
          es el mismo camino que el keybind SwitchCameraPOV del juego.

      FOV : CameraController:SetExternalFOVOffset(key, n)
          El Update hace _fov_gameplay_spring.Target = _base_fov + v29 +
          GetExternalFOVOffset(), o sea que el juego aplica el offset con su
          propio spring (suave, sin pelear). Verificado: 80 -> 105.

      Sin sacudida : CameraController._shake_enabled = false
          En _Setup: ShakeCFrame = if _shake_enabled and p12 then p12 else
          CFrame.identity. Es el switch que el juego ya consulta.

    DESCARTADO: ViewModelOffsetCFrame. En papel es un punto de entrada libre
    (se inicializa a identity y solo se lee al componer la CFrame de camara y
    viewmodel), y la escritura entra -- pero no produce efecto visible. Algo
    mas abajo en la cadena la anula. Sacado hasta entender por que.

    NO se puede sin hooks (probado): quitar el bobeo. El de camara se
    calcula dentro de CameraController:Update y el del viewmodel dentro de
    ClientViewModel:SetCFrame; ninguno tiene flag para desactivarlo.

    NO se hace a proposito: crosshair y hitmarker. Rivals ya los trae con
    settings propios (escala, rotacion, transparencia, criticos) -> usar los
    del juego es mejor y no agrega superficie.
------------------------------------------------------------------ ]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local FOV_KEY = "RivalsMenu"

local C = {
    Conns = {}, Loaded = false, Flags = nil,
    _cc = nil, _shakeOrig = nil,
    Settings = {
        ThirdPerson = false,
        FOV = 0,                -- offset sobre el FOV base del juego (80)
        NoShake = false,
        AntiFlash = false,
        AntiSmoke = false,
        SmokeLevel = 1,      -- 1 = humo invisible; 0.5 = a medias
    },
}

function C:_flag(k, d)
    if self.Flags then local v = self.Flags["Cbt_" .. k]; if v ~= nil then return v end end
    local s = self.Settings[k]
    if s ~= nil then return s end
    return d
end
function C:BindFlags(ft) self.Flags = ft end

function C:_cam()
    if self._cc then return self._cc end
    local ok, cc = pcall(require, LocalPlayer.PlayerScripts.Controllers.CameraController)
    if ok then self._cc = cc end
    return self._cc
end

function C:TogglePOV()
    local cc = self:_cam()
    if not cc or not cc.CameraState then return end
    pcall(function() cc.CameraState:TogglePOV() end)
end

--[[ Reconciliacion por frame: se escribe SOLO si el valor difiere.
     Barato, y sobrevive a que el juego reinicie sus campos (por ejemplo
     _external_fov_offsets se vacia en el setup del controller). ]]
function C:_step()
    local cc = self:_cam()
    if not cc then return end

    -- tercera persona
    local want3p = self:_flag("ThirdPerson", false)
    local cur = cc._third_person_override
    if want3p and cur ~= true then
        pcall(function() cc:SetThirdPersonOverride(true) end)
    elseif (not want3p) and cur ~= nil then
        pcall(function() cc:SetThirdPersonOverride(nil) end)
        -- si quedaste en 3ra sin acceso, el juego te devuelve a 1ra solo
    end

    -- FOV (el juego lo suaviza con su spring)
    local fov = self:_flag("FOV", 0)
    local ok, curFov = pcall(function() return cc._external_fov_offsets and cc._external_fov_offsets[FOV_KEY] end)
    if ok and (curFov or 0) ~= fov then
        pcall(function() cc:SetExternalFOVOffset(FOV_KEY, fov) end)
    end

    -- sacudida de camara
    local noShake = self:_flag("NoShake", false)
    if self._shakeOrig == nil then self._shakeOrig = cc._shake_enabled end
    local want = not noShake
    if cc._shake_enabled ~= want then cc._shake_enabled = want end

    self:_applySmoke()

    -- flash ya en pantalla al prender el toggle: barrer una vez
    if self:_flag("AntiFlash", false) then
        for _, d in ipairs(game:GetService("Lighting"):GetChildren()) do self:_killFlash(d) end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then for _, d in ipairs(pg:GetChildren()) do self:_killFlash(d) end end
    end
end

--[[ ------------------------------------------------------------------
    ANTI-FLASH / ANTI-SMOKE
    Sin hooks: el flashbang se arma con instancias identificables y el humo
    con ParticleEmitters. Se los intercepta por evento (ChildAdded /
    DescendantAdded), no escaneando cada frame.

      Flash (Modules.ClientReplicatedClasses...FighterInterface.Flashed:Flash):
        - clona FlashbangGui -> PlayerGui   (el destello blanco)
        - crea ColorCorrectionEffect "Flashbang" -> Lighting  (la ceguera)
      Los dos se neutralizan al aparecer. El resto del efecto (sonido de
      pitido) se deja: no tapa la pantalla.

      Humo: los ParticleEmitter del cloud. Se bajan por Transparency en vez
      de Destroy, asi el juego puede seguir con su ciclo de vida normal.
------------------------------------------------------------------ ]]
local SMOKE_NAMES = { ["Smoke Grenade"] = true, ["Smoke"] = true, ["SmokeCloud"] = true }

function C:_isSmoke(inst)
    if not inst:IsA("ParticleEmitter") then return false end
    local p = inst.Parent
    while p and p ~= workspace do
        if SMOKE_NAMES[p.Name] then return true end
        p = p.Parent
    end
    return false
end

function C:_killFlash(inst)
    if not self:_flag("AntiFlash", false) then return end
    if inst:IsA("ColorCorrectionEffect") and inst.Name == "Flashbang" then
        pcall(function() inst.Enabled = false end)
    elseif inst:IsA("ScreenGui") and inst.Name == "FlashbangGui" then
        pcall(function() inst.Enabled = false end)
    end
end

function C:_watch()
    local Lighting = game:GetService("Lighting")
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    self.Conns[#self.Conns + 1] = Lighting.ChildAdded:Connect(function(d) pcall(function() self:_killFlash(d) end) end)
    if pg then
        self.Conns[#self.Conns + 1] = pg.ChildAdded:Connect(function(d) pcall(function() self:_killFlash(d) end) end)
    end
    -- humo: se registra al aparecer; el nivel se aplica en _step
    self._smoke = {}
    self.Conns[#self.Conns + 1] = workspace.DescendantAdded:Connect(function(d)
        pcall(function() if self:_isSmoke(d) then self._smoke[d] = d.Transparency end end)
    end)
end

function C:_applySmoke()
    local lvl = self:_flag("AntiSmoke", false) and self:_flag("SmokeLevel", 1) or 0
    for e, orig in pairs(self._smoke or {}) do
        if not e.Parent then
            self._smoke[e] = nil
        else
            local ok = pcall(function()
                if lvl > 0 then
                    e.Transparency = NumberSequence.new(math.clamp(lvl, 0, 1))
                elseif typeof(orig) == "NumberSequence" then
                    e.Transparency = orig
                end
            end)
            if not ok then self._smoke[e] = nil end
        end
    end
end

function C:BuildUI(Library, Window)
    if self._uiTab then return self._uiTab end
    local T = Window:GetTab("Combat") or Window:AddTab("Combat")
    self._uiTab = T

    local g = T:AddRightGroupbox("Camara (API del juego)")
    g:AddLabel("Sin hooks: usa la API del propio Rivals")
    local tp = g:AddToggle("Cbt_ThirdPerson", { Text = "Tercera persona", Default = false, Keybind = true })
    tp:AddLabel("El juego la restringe a handicaps/mobile")
    g:AddButton("Cambiar POV (1ra <-> 3ra)", function() self:TogglePOV() end)
    g:AddSlider("Cbt_FOV", { Text = "FOV extra", Min = -30, Max = 50, Default = 0, Suffix = "°" })
    -- OJO: este toggle NO usa hooks (es _shake_enabled, un campo que el juego
    -- consulta solo). El label del bobeo estaba aca abajo y se leia como si
    -- fuera su advertencia -> movido a su propio groupbox.
    g:AddToggle("Cbt_NoShake", { Text = "Sin sacudida de camara", Default = false, Keybind = true })

    local nb = T:AddRightGroupbox("No disponible")
    nb:AddLabel("Sin bobeo: requiere hooks, no esta")

    local e = T:AddLeftGroupbox("Efectos enemigos")
    e:AddToggle("Cbt_AntiFlash", { Text = "Anti-flashbang", Default = false, Keybind = true })
    local sm = e:AddToggle("Cbt_AntiSmoke", { Text = "Anti-humo", Default = false, Keybind = true })
    sm:AddSlider("Cbt_SmokeLevel", { Text = "Transparencia humo", Min = 0, Max = 1, Default = 1, Decimals = 2 })
    e:AddLabel("Clientside: solo cambia lo que tú ves")

    return T
end

function C:Init()
    if self.Loaded then return self end
    self.Loaded = true
    self:_watch()
    self.Conns[#self.Conns + 1] = RunService.RenderStepped:Connect(function()
        local ok, err = pcall(function() self:_step() end)
        if not ok then warn("[RivalsCombat] " .. tostring(err)) end
    end)
    return self
end

function C:Unload()
    if not self.Loaded then return end
    self.Loaded = false
    for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
    table.clear(self.Conns)
    local cc = self._cc
    if cc then
        pcall(function() cc:SetExternalFOVOffset(FOV_KEY, 0) end)
        pcall(function() cc:SetThirdPersonOverride(nil) end)
        if self._shakeOrig ~= nil then pcall(function() cc._shake_enabled = self._shakeOrig end) end
    end
    self._shakeOrig = nil
    -- devolver el humo que hayamos bajado
    for e, orig in pairs(self._smoke or {}) do
        pcall(function() if e.Parent and typeof(orig) == "NumberSequence" then e.Transparency = orig end end)
    end
    self._smoke = nil
end

return C
