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

      Offset : CameraController.ViewModelOffsetCFrame
          Solo se inicializa a identity y despues se LEE para componer la
          CFrame de la camara y del viewmodel. Nadie mas la escribe -> es un
          punto de entrada libre. OJO: mueve camara Y viewmodel juntos.

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
        Offset = false,
        OffsetX = 0, OffsetY = 0, OffsetZ = 0,
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

    -- offset de camara + viewmodel
    if self:_flag("Offset", false) then
        local o = CFrame.new(self:_flag("OffsetX", 0), self:_flag("OffsetY", 0), self:_flag("OffsetZ", 0))
        if cc.ViewModelOffsetCFrame ~= o then cc.ViewModelOffsetCFrame = o end
    elseif cc.ViewModelOffsetCFrame ~= CFrame.identity then
        cc.ViewModelOffsetCFrame = CFrame.identity
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
    g:AddToggle("Cbt_NoShake", { Text = "Sin sacudida de camara", Default = false, Keybind = true })
    g:AddLabel("El bobeo NO se puede quitar sin hooks")

    local o = T:AddRightGroupbox("Offset camara + viewmodel")
    local oe = o:AddToggle("Cbt_Offset", { Text = "Activar offset", Default = false })
    oe:AddLabel("Mueve camara Y arma juntas")
    oe:AddSlider("Cbt_OffsetX", { Text = "X (lateral)", Min = -5, Max = 5, Default = 0, Decimals = 2, Suffix = "st" })
    oe:AddSlider("Cbt_OffsetY", { Text = "Y (altura)", Min = -5, Max = 5, Default = 0, Decimals = 2, Suffix = "st" })
    oe:AddSlider("Cbt_OffsetZ", { Text = "Z (adelante)", Min = -5, Max = 5, Default = 0, Decimals = 2, Suffix = "st" })
    return T
end

function C:Init()
    if self.Loaded then return self end
    self.Loaded = true
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
        pcall(function() cc.ViewModelOffsetCFrame = CFrame.identity end)
        if self._shakeOrig ~= nil then pcall(function() cc._shake_enabled = self._shakeOrig end) end
    end
    self._shakeOrig = nil
end

return C
