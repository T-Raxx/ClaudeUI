--[[
    RivalsRage  -  Ragebot interno para Rivals (build 0.5)
    ------------------------------------------------------------------
    Descubrimiento clave: el disparo NO se simula ni se arma a mano.
    Se llama la ruta de disparo interna del juego:

        MechanicsController:EquippedItemInput("StartShooting")

    que internamente hace ClientFighter:GetCameraData() -> raycast desde
    workspace.CurrentCamera -> construye el payload UseItem valido
    (origin CFrame + hitbox impactada + hit-local) -> el server valida
    origin<->hitbox geometricamente y ACEPTA. Cero mouse, cero payload,
    cero hooks.

    GOTCHA identidad: GetCameraData hace un require interno bloqueado en
    la identidad elevada del executor -> hay que bajar a identidad 2
    (setthreadidentity(2)) alrededor del EquippedItemInput y restaurar.

    GOTCHA anti-hook: ClientFighter corre un loop cada 5s que detecta si
    GetCameraData esta HOOKEADA (debug.info + getfenv().hookfunction) y
    reporta. Por eso NUNCA se hookea: solo se LLAMA.

    Piezas:
      - Aimbot camara (setea CurrentCamera al hitbox -> GetCameraData lo capta)
      - Autoshoot interno (EquippedItemInput en identidad 2)
      - Void spam (mueve el HRP real al void; engine replica -> ininvulnerable)
      - OOB disable (client-driven: neutraliza el reporter OutOfBoundsParts)

    Flags (prefijo Rage_): ver RivalsMain wiring.

    ADVERTENCIA: VoidSpam mueve el HumanoidRootPart real. El anticheat de
    server de Rivals banea "Movement Cheats". Probar SOLO en VIP/alt.
------------------------------------------------------------------ ]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService= game:GetService("CollectionService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local LocalPlayer      = Players.LocalPlayer

-- identidad de thread (bajar a 2 para que el require interno de GetCameraData pase)
local getId = getthreadidentity or getidentity or (syn and syn.get_thread_identity)
local setId = setthreadidentity or setidentity or (syn and syn.set_thread_identity)

local Rage = {
    Conns   = {},
    Loaded  = false,
    Flags   = nil,
    _mech   = nil,          -- MechanicsController singleton
    _oob    = nil,          -- OutOfBoundsParts singleton
    _oobOrigUpdate = nil,   -- Update original para restaurar
    _inVoid = false,
    _voidCF = CFrame.new(0, 1e6, 0),
    _lastFire = 0,
    Settings = {
        Enabled = false,
        Activation = "Always",     -- Always | Hold Right Click | Hold Left Click
        FOV = 400,                 -- px; grande = pantalla completa (rage)
        MaxDistance = 2000,
        VisibleCheck = false,
        AutoShoot = true,
        FireRate = 20,
        TeamCheck = true,          -- no pegarle a companeros (TeamID attr, o spawn mas cercano si no hay teams)
        IgnoreDummies = true,      -- ignorar dummies del shooting range (models Entity sin Player)             -- intentos/seg (el juego auto-cooldownea)
        RoundOnly = true,          -- SOLO actuar en ronda real (IsInDuel + RoundStarted) = anti-lobby
        VoidSpam = false,          -- MUEVE EL HRP REAL - riesgo AC
        DisableOOB = true,         -- neutraliza el reporter OOB (para no morir en void)
        LocalHook = true,          -- spoof de pos (__index hook GLOBAL idempotente, no apila). Streaming se queda en pos fake -> void gigante sin estres.
        VoidDistance = 100000,     -- studs de offset al void (con spoof podes ir mucho mas, hasta ~2.1B)
        VoidTime = 0.6,            -- s en void entre tiros (cadencia lenta)
        PeekHeight = 20,           -- studs ENCIMA del target donde se hace el peek
        PeekWait = 0.18,           -- s de espera en el peek antes de disparar (que replique la pos al server -> sin mismatch)
        ShootHold = 0.2,           -- s manteniendo peek + aim tras disparar (proyectil viaja/registra + delay del arma)
        PeekTolerance = 8,         -- studs: cuan cerca del peek debe estar la pos real para confirmar y disparar
        HUD = true,                -- labels en pantalla (Ragebot: / Void... / killing / health)
        HUDOffset = 42,            -- px debajo del centro de pantalla (la linea se ancla al crosshair)
        HUDFadeSpeed = 0.6,        -- loops/seg del gradiente viajero de "Ragebot:"
        HUDSize = 17,
        HUDFadeFrom = Color3.fromRGB(255,255,255), HUDFadeTo = Color3.fromRGB(0,0,0),   -- fade "Ragebot:" izq->der
        HUDVoidColor = Color3.fromRGB(150,150,160),
        HUDKillColor = Color3.fromRGB(255,255,255),
        HUDHealthColor = Color3.fromRGB(120,230,120),
        Weld = false,              -- CONNECTION/WELD exploit: soldarse al enemigo (PhysicsRepRootPart + CFrame). Para melee/escudo.
        WeldMeleeOnly = true,      -- weld solo cuando tenes melee equipado (Info.Class=="Melee", slot 3)
        WeldBehind = 2.5,          -- studs detras del enemigo (+ = atras)
        WeldHeight = 0,            -- offset de altura
        WeldAutoAttack = false,    -- auto-melee/uso del item mientras soldado (siempre conecta)
    },
}

function Rage:_flag(k, d)
    if self.Flags then local v = self.Flags["Rage_" .. k]; if v ~= nil then return v end end
    local s = self.Settings[k]; if s ~= nil then return s end
    return d
end
function Rage:BindFlags(ft) self.Flags = ft end

----------------------------------------------------------------------
-- requires perezosos de controllers del juego
----------------------------------------------------------------------
function Rage:_getMech()
    if self._mech then return self._mech end
    local ok, m = pcall(require, LocalPlayer.PlayerScripts.Controllers.MechanicsController)
    if ok then self._mech = m end
    return self._mech
end

function Rage:_equippedItem()
    local mech = self:_getMech()
    return mech and mech.LocalFighter and mech.LocalFighter.EquippedItem
end

-- item equipado es melee (Info.Class == "Melee", ej Fists / slot 3)
function Rage:_isMelee()
    local item = self:_equippedItem()
    return item and item.Info and item.Info.Class == "Melee" or false
end

-- se puede disparar YA? (no recargando, no en cooldown, con balas). Evita peekear/disparar al pedo.
function Rage:_canShoot()
    local item = self:_equippedItem()
    if not item then return true end
    if item.IsEquipping and item:IsEquipping() then return false end
    local now = tick()
    if item._reload_cooldown and now < item._reload_cooldown then return false end   -- recargando
    if item._shoot_cooldown and now < item._shoot_cooldown then return false end     -- cooldown de tiro
    local ammo; pcall(function() ammo = item:Get("Ammo") end)
    if type(ammo) == "number" and ammo <= 0 then return false end                    -- sin balas (necesita recarga)
    return true
end

function Rage:_getFighterCtl()
    if self._fighterCtl then return self._fighterCtl end
    local ok, f = pcall(require, LocalPlayer.PlayerScripts.Controllers.FighterController)
    if ok then self._fighterCtl = f end
    return self._fighterCtl
end

function Rage:_getDuelCtl()
    if self._duelCtl then return self._duelCtl end
    local ok, d = pcall(require, LocalPlayer.PlayerScripts.Controllers.DuelController)
    if ok then self._duelCtl = d end
    return self._duelCtl
end

-- en el duelo (IsInDuel): gate para QUEDARSE en void aunque sea entre rondas / target muerto
function Rage:_inMatch()
    if not self:_flag("RoundOnly", true) then return true end
    local fc = self:_getFighterCtl()
    local lf = fc and fc.LocalFighter
    if not lf then return false end
    local ok, inDuel = pcall(function() return lf:Get("IsInDuel") end)
    return (ok and inDuel) or false
end

-- ronda activa: en duelo Y Status == "RoundStarted" (estados: RoundStarting/RoundStarted/Voting/GameOver)
function Rage:_inRound()
    local fc = self:_getFighterCtl()
    local lf = fc and fc.LocalFighter
    if not lf then return false end
    local ok, inDuel = pcall(function() return lf:Get("IsInDuel") end)
    if not ok or not inDuel then return false end
    local dc = self:_getDuelCtl()
    if not dc then return true end   -- en duelo pero sin controller -> asumir activo
    local okd, duel = pcall(function() return dc:GetDuel(LocalPlayer) end)
    if not okd or not duel then return true end
    local oks, st = pcall(function() return duel:Get("Status") end)
    if not oks then return true end
    return st == "RoundStarted"
end

----------------------------------------------------------------------
-- OOB disable (client-driven: OutOfBoundsParts.Update -> no reporta muerte)
----------------------------------------------------------------------
function Rage:_setOOB(disabled)
    local ok, oob = pcall(require, LocalPlayer.PlayerScripts.Modules.GameComponents.OutOfBoundsParts)
    if not ok or not oob then return end
    self._oob = oob
    if disabled then
        if not self._oobOrigUpdate then
            self._oobOrigUpdate = oob.Update
            oob.Update = function() end   -- mata detect->warn->report; el remote OOB nunca se fira
            oob._oob_details = nil
        end
    else
        if self._oobOrigUpdate then
            oob.Update = self._oobOrigUpdate
            self._oobOrigUpdate = nil
        end
    end
end

----------------------------------------------------------------------
-- target: player-entity mas cercano a la mira dentro del FOV, vivo
----------------------------------------------------------------------
local function alive(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0 and hum
end

function Rage:_visible(camPos, part, model)
    if not self:_flag("VisibleCheck", false) then return true end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild("ViewModels") }
    local r = workspace:Raycast(camPos, part.Position - camPos, rp)
    return (not r) or r.Instance:IsDescendantOf(model)
end

function Rage:_getTarget()
    local cam = workspace.CurrentCamera
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local fov = self:_flag("FOV", 400)
    local maxD = self:_flag("MaxDistance", 2000)
    local myChar = LocalPlayer.Character
    local origin = cam.CFrame.Position
    local best, bestScore, bestHead
    for _, model in ipairs(CollectionService:GetTagged("Entity")) do
        if model ~= myChar and model.Parent then
            local hum = alive(model)
            local head = model:FindFirstChild("HitboxHead")
            if hum and head then
                local sp = cam:WorldToViewportPoint(head.Position)
                if sp.Z > 0 then
                    local d2 = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    local dist = (head.Position - origin).Magnitude
                    if d2 <= fov and dist <= maxD and self:_visible(origin, head, model) and not self:_isDummy(model) and self:_isEnemy(model) then
                        if not bestScore or d2 < bestScore then
                            best, bestScore, bestHead = model, d2, head
                        end
                    end
                end
            end
        end
    end
    return best, bestHead
end

----------------------------------------------------------------------
-- TEAM CHECK: no pegarle a compañeros. TeamID (attr) o, si no hay, spawn mas cercano.
----------------------------------------------------------------------
-- TeamID de un player/modelo, CACHEADO (el attr parpadea a nil en respawn/transicion;
-- el team no cambia en el match -> guardamos el ultimo no-nil).
function Rage:_teamId(player, model)
    self._teamCache = self._teamCache or {}
    local key = player or model
    if not key then return nil end
    local t = (player and player:GetAttribute("TeamID"))
        or (model and model:GetAttribute("TeamID"))
        or (player and player.Team and player.Team.Name)
    if t == nil and player then
        local fc = self:_getFighterCtl()
        local pf = fc and fc._player_to_fighter and fc._player_to_fighter[player]
        if pf then pcall(function() local x = pf:Get("TeamID"); if x ~= nil then t = x end end) end
    end
    if t ~= nil then self._teamCache[key] = "id:" .. tostring(t) end
    return self._teamCache[key]
end
function Rage:_spawnCache()
    if self._spawns and (tick() - (self._spawnsT or 0)) < 5 then return self._spawns end
    local list = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("SpawnLocation") or (d:IsA("BasePart") and d.Name:lower():find("spawn")) then list[#list + 1] = d end
    end
    self._spawns, self._spawnsT = list, tick()
    return list
end
function Rage:_nearestSpawn(pos)
    local best, bd
    for _, d in ipairs(self:_spawnCache()) do
        local dd = (d.Position - pos).Magnitude
        if not bd or dd < bd then best, bd = d, dd end
    end
    return best
end
-- true = enemigo (dispararle). false = companero (NO).
function Rage:_isEnemy(model)
    if not self:_flag("TeamCheck", true) then return true end
    local myT = self:_teamId(LocalPlayer, LocalPlayer.Character)
    if not myT then return true end                 -- yo sin team (FFA/duelo) -> todos enemigos
    local tp = Players:GetPlayerFromCharacter(model)
    local tgtT = self:_teamId(tp, model)
    if tgtT then return myT ~= tgtT end             -- ambos conocidos: enemigo si distinto team
    -- target sin team conocido en team-mode -> spawn fallback
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local tPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HitboxBody")
    if myHRP and tPart then
        local ms, ts = self:_nearestSpawn(myHRP.Position), self:_nearestSpawn(tPart.Position)
        if ms and ts then return ms ~= ts end
    end
    return false                                    -- desconocido en team-mode -> conservador, NO disparar (podria ser aliado)
end

-- dummy (shooting range) = modelo Entity SIN Player asociado. Los players reales SI tienen Player.
function Rage:_isDummy(model)
    if not self:_flag("IgnoreDummies", true) then return false end
    return Players:GetPlayerFromCharacter(model) == nil
end

-- enemigo mas cercano IGNORANDO FOV/pantalla (para void spam: siempre hay target aunque no lo mires)
function Rage:_nearestEnemy()
    local myChar = LocalPlayer.Character
    local myPos = (self._fakeCF and self._fakeCF.Position)
        or (myChar and myChar:FindFirstChild("HumanoidRootPart") and myChar.HumanoidRootPart.Position)
    if not myPos then return end
    local maxD = self:_flag("MaxDistance", 2000)
    local best, bd, bh
    for _, model in ipairs(CollectionService:GetTagged("Entity")) do
        if model ~= myChar and model.Parent then
            local hum = alive(model)
            local head = model:FindFirstChild("HitboxHead")
            if hum and head and not self:_isDummy(model) and self:_isEnemy(model) then
                local d = (head.Position - myPos).Magnitude
                if d <= maxD and (not bd or d < bd) then best, bd, bh = model, d, head end
            end
        end
    end
    return best, bh
end

----------------------------------------------------------------------
-- activacion
----------------------------------------------------------------------
function Rage:_active()
    if not self:_flag("Enabled", false) then return false end
    local m = self:_flag("Activation", "Always")
    if m == "Always" then return true end
    if m == "Hold Right Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
    if m == "Hold Left Click"  then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
    return false
end

----------------------------------------------------------------------
-- disparo interno (identidad 2 alrededor del EquippedItemInput)
----------------------------------------------------------------------
local function fireState(mech, state)
    local old = getId and getId() or nil
    if setId then pcall(setId, 2) end
    pcall(function() mech:EquippedItemInput(state) end)
    if setId and old then pcall(setId, old) end
end

function Rage:_fire()
    local mech = self:_getMech()
    if not mech or not mech.LocalFighter then return end
    fireState(mech, "StartShooting")
    task.delay(0.03, function() fireState(mech, "FinishShooting") end)
end

----------------------------------------------------------------------
-- HUD (labels en pantalla via Drawing)
----------------------------------------------------------------------
function Rage:_hudDraw(class, props)
    local o = Drawing.new(class)
    o.Visible = false
    if props then for k, v in pairs(props) do o[k] = v end end
    self._hudDrawings = self._hudDrawings or {}
    table.insert(self._hudDrawings, o)
    return o
end

--[[ ------------------------------------------------------------------
    HUD: UNA linea horizontal centrada bajo el crosshair (estilo symbol.hit).

        Ragebot:  Void...  killing: <user>...  health: <hp>

    Un Drawing.Text no soporta color por segmento -> cada segmento es su
    propio Text y se los apila a mano. "Ragebot:" ademas va char por char
    para el gradiente. Se mide el ancho total (TextBounds.X) y se arranca
    en cx - total/2, asi los segmentos ocultos no dejan hueco: la linea se
    recentra sola.
------------------------------------------------------------------ ]]
local HUD_WORD = "Ragebot:"
local HUD_GAP  = 10   -- px entre segmentos

function Rage:_ensureHUD()
    if self._hud then return self._hud end
    local size = self:_flag("HUDSize", 17)
    local h = { chars = {} }
    for i = 1, #HUD_WORD do
        h.chars[i] = self:_hudDraw("Text", { Text = HUD_WORD:sub(i, i), Font = 3, Size = size, Outline = true })
    end
    h.void    = self:_hudDraw("Text", { Font = 3, Size = size, Outline = true })
    h.killing = self:_hudDraw("Text", { Font = 3, Size = size, Outline = true })
    h.health  = self:_hudDraw("Text", { Font = 3, Size = size, Outline = true })
    self._hud = h
    return h
end

function Rage:_hudHide()
    if not self._hud then return end
    for _, c in ipairs(self._hud.chars) do c.Visible = false end
    self._hud.void.Visible = false; self._hud.killing.Visible = false; self._hud.health.Visible = false
end

-- onda triangular 0->1->0, para que el gradiente cicle sin saltar
local function tri(t)
    t = t % 1
    return (t < 0.5) and (t * 2) or (2 - t * 2)
end

function Rage:_updateHUD()
    if not self:_flag("HUD", true) then self:_hudHide(); return end
    local hud  = self:_ensureHUD()
    local size = self:_flag("HUDSize", 17)
    local cam  = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2 + self:_flag("HUDOffset", 42)

    -- que segmentos se muestran
    local showVoid = self._hudWaiting == true
    local showTgt  = self._hudTargetName ~= nil
    local voidTxt  = "Void..."
    local killTxt  = showTgt and ("killing: " .. self._hudTargetName .. "...") or ""
    local hpTxt    = showTgt and ("health: " .. tostring(math.floor((self._hudTargetHP or 0) + 0.5))) or ""

    -- medir: hay que setear Text/Size ANTES de leer TextBounds
    local charW = {}
    local total = 0
    for i, ch in ipairs(hud.chars) do
        ch.Size = size
        local w = ch.TextBounds.X
        if w <= 0 then w = size * 0.55 end   -- fallback si el executor no reporto bounds aun
        charW[i] = w
        total = total + w
    end
    if showVoid then
        hud.void.Text = voidTxt; hud.void.Size = size
        total = total + HUD_GAP + hud.void.TextBounds.X
    end
    if showTgt then
        hud.killing.Text = killTxt; hud.killing.Size = size
        hud.health.Text  = hpTxt;   hud.health.Size  = size
        total = total + HUD_GAP + hud.killing.TextBounds.X + HUD_GAP + hud.health.TextBounds.X
    end

    -- dibujar de izquierda a derecha desde el centro
    local x = cx - total / 2
    local from  = self:_flag("HUDFadeFrom", Color3.new(1, 1, 1))
    local to    = self:_flag("HUDFadeTo", Color3.new(0, 0, 0))
    local speed = self:_flag("HUDFadeSpeed", 0.6)
    local phase = (tick() * speed) % 1        -- gradiente viajero izq->der
    local n = #hud.chars
    for i, ch in ipairs(hud.chars) do
        ch.Color    = from:Lerp(to, tri((i - 1) / n + phase))
        ch.Position = Vector2.new(x, cy)
        ch.ZIndex   = 200
        ch.Visible  = true
        x = x + charW[i]
    end
    if showVoid then
        x = x + HUD_GAP
        hud.void.Color = self:_flag("HUDVoidColor", Color3.fromRGB(150, 150, 160))
        hud.void.Position = Vector2.new(x, cy); hud.void.ZIndex = 200; hud.void.Visible = true
        x = x + hud.void.TextBounds.X
    else
        hud.void.Visible = false
    end
    if showTgt then
        x = x + HUD_GAP
        hud.killing.Color = self:_flag("HUDKillColor", Color3.new(1, 1, 1))
        hud.killing.Position = Vector2.new(x, cy); hud.killing.ZIndex = 200; hud.killing.Visible = true
        x = x + hud.killing.TextBounds.X + HUD_GAP
        hud.health.Color = self:_flag("HUDHealthColor", Color3.fromRGB(120, 230, 120))
        hud.health.Position = Vector2.new(x, cy); hud.health.ZIndex = 200; hud.health.Visible = true
    else
        hud.killing.Visible = false; hud.health.Visible = false
    end
end

----------------------------------------------------------------------
-- void spam helpers
----------------------------------------------------------------------
function Rage:_myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- patron de posicion del HRP real por frame segun el preset de desync.
-- valores FINITOS (nada de inf/NaN real: CFrame.new(NaN) tira error).
-- posicion del HRP real por frame. SIEMPRE POSITIVA (cruzar negativos = te mata el void).
-- Random 10k-3B por eje cada frame = inhittable + rompe resolvers, sin matarte.
function Rage:_desyncPos(base)
    local preset = self:_flag("DesyncPreset", "Random")
    local function r() return 10000 + math.random() * (3e9 - 10000) end   -- positivo 10k..3B
    if preset == "Fixed" then
        local d = self:_flag("VoidDistance", 100000)
        return Vector3.new(math.abs(base.X) + d, math.abs(base.Y) + d, math.abs(base.Z) + d)
    elseif preset == "infswitch" then
        self._sw = not self._sw
        local v = self._sw and 2.5e9 or 3e8   -- alterna 2 valores POSITIVOS grandes (rompe resolvers)
        return Vector3.new(v, v, v)
    end
    -- "Random" (default): random positivo cada frame
    return Vector3.new(r(), r(), r())
end

function Rage:_toVoid(hrp)
    -- base real capturada 1 vez al entrar al void (para volver a disparar)
    if not self._inVoid then self._voidBase = hrp.Position; self._inVoid = true end
    hrp.CFrame = CFrame.new(self:_desyncPos(self._voidBase or hrp.Position))
end

-- camara Scriptable durante void = vista estable (CameraModule deja de pelear)
function Rage:_setScriptCam(on)
    local cam = workspace.CurrentCamera
    if not cam then return end
    if on then
        if cam.CameraType ~= Enum.CameraType.Scriptable then
            -- NUNCA guardar Scriptable como "original" (se quedaria bugeada)
            if self._origCamType == nil or self._origCamType == Enum.CameraType.Scriptable then
                self._origCamType = Enum.CameraType.Custom
            end
            cam.CameraType = Enum.CameraType.Scriptable
        end
    else
        cam.CameraType = self._origCamType or Enum.CameraType.Custom
        self._origCamType = nil
    end
end

-- __index hook: lecturas LOCALES de MI HRP (.CFrame/.Position) por scripts del juego
-- devuelven _maskCF (pos normal) mientras el part real esta en void. checkcaller()
-- deja pasar NUESTRAS lecturas (necesitamos la real). NO hookea GetCameraData (trampa AC).
-- UN solo hook global (sobrevive reloads via getgenv, NO apila = no lag creciente).
-- Lee una tabla mask global; cualquier instancia la actualiza. La hook enmascara
-- la pos de TU HRP a scripts locales -> spoof: el streaming/replicacion se queda en
-- la pos fake -> podes irte a 2.1B studs sin estres. checkcaller() deja pasar lo nuestro.
function Rage:_installHook()
    local G = (getgenv and getgenv()) or shared
    if not G.RivalsMask then G.RivalsMask = { on = false } end
    self._gmask = G.RivalsMask
    if G.RivalsHookInstalled then return end
    if not (hookmetamethod and checkcaller) then self._hookFail = true; return end
    local mask = G.RivalsMask
    local old
    old = hookmetamethod(game, "__index", function(t, k)
        if mask.on and t == mask.hrp and not checkcaller() then
            if k == "CFrame" then return mask.cf end
            if k == "Position" then return mask.cf and mask.cf.Position end
        end
        return old(t, k)
    end)
    G.RivalsHookInstalled = true
    G.RivalsHookOld = old
end

----------------------------------------------------------------------
-- loop principal
----------------------------------------------------------------------
function Rage:_weldClear(hrp)
    self._weldTarget = nil; self._weldOffset = nil
    if hrp then pcall(function() sethiddenproperty(hrp, "PhysicsRepRootPart", nil) end) end
end

function Rage:_resetVoid(hrp)
    local gm = (getgenv and getgenv().RivalsMask) or self._gmask   -- limpiar la mask GLOBAL (aunque este instancia no tenga ref) -> arregla camara offset
    if gm then gm.on = false end
    self._realTargetCF = nil      -- el loop deja de imponer posicion
    if self._voidState and hrp and self._fakeCF then pcall(function() hrp.CFrame = self._fakeCF end) end
    self._voidState = nil; self._inVoid = false; self._peekStart = nil; self._peekShotDone = false
    self:_setScriptCam(false)     -- devolver control de camara al juego
end

function Rage:_step()
    if not self.Loaded then return end
    local enabled = self:_flag("Enabled", false)
    -- inMatch = estas en el duelo (te quedas en void aunque sea entre rondas / target muerto).
    -- roundActive = Status "RoundStarted" (solo entonces peekeas y disparas).
    local inMatch     = self:_inMatch()
    local roundActive = (not self:_flag("RoundOnly", true)) or self:_inRound()
    local voidOn = enabled and self:_flag("VoidSpam", false)
    local wantOOBoff = voidOn and inMatch and self:_flag("DisableOOB", true)
    if wantOOBoff and not self._oobOrigUpdate then self:_setOOB(true)
    elseif (not wantOOBoff) and self._oobOrigUpdate then self:_setOOB(false) end

    local hrp = self:_myHRP()

    if not enabled or not inMatch then
        self:_resetVoid(hrp)   -- fuera del duelo: volver a normal
        self:_weldClear(hrp)
        self._hudTargetName = nil; self._hudWaiting = false
        return
    end
    if not self:_flag("Weld", false) then self:_weldClear(hrp) end   -- weld off -> soltar

    local active = self:_active()
    local weldOn = self:_flag("Weld", false)
    -- void/weld: enemigo mas cercano IGNORANDO FOV. aimbot normal: por FOV/mira.
    local target, head
    if voidOn or weldOn then target, head = self:_nearestEnemy() else target, head = self:_getTarget() end
    local canFight = roundActive and active and target and head
    local cam = workspace.CurrentCamera
    local now = tick()
    local voidTime = self:_flag("VoidTime", 0.6)
    local peekWait = self:_flag("PeekWait", 0.1)
    local peekH    = self:_flag("PeekHeight", 20)

    -- estado HUD
    if target then
        local tp = Players:GetPlayerFromCharacter(target)
        self._hudTargetName = tp and tp.Name or target.Name
        local thum = target:FindFirstChildOfClass("Humanoid")
        self._hudTargetHP = thum and thum.Health or 0
    else
        self._hudTargetName = nil; self._hudTargetHP = nil
    end
    -- "Void..." cuando el target murio/no hay y seguimos en void/weld esperando
    self._hudWaiting = (not canFight) and (self:_flag("VoidSpam", false) or self:_flag("Weld", false))

    -- ============ WELD / CONNECTION (soldarse al enemigo: melee/escudo) ============
    if weldOn and hrp then
        local eHRP = target and target:FindFirstChild("HumanoidRootPart")
        -- solo weld con melee equipado (si WeldMeleeOnly); si no hay pelea/target/melee -> soltar
        local meleeOk = (not self:_flag("WeldMeleeOnly", true)) or self:_isMelee()
        if not (canFight and eHRP and meleeOk) then self:_weldClear(hrp); return end
        self:_setScriptCam(false)   -- weld no controla camara (jugas normal, pegado al enemigo)
        self._weldTarget = eHRP
        self._weldOffset = CFrame.new(0, self:_flag("WeldHeight", 0), self:_flag("WeldBehind", 2.5))
        -- el enforcement loop aplica PhysicsRepRootPart + CFrame cada frame (le gana al controller)
        if self:_flag("WeldAutoAttack", false) and self:_canShoot() then self:_fire() end
        return
    end

    -- ============ VOID SPAM (state machine) ============
    if voidOn and hrp then
        if not self._fakeCF then self._fakeCF = hrp.CFrame end
        -- spoof de pos (mask): scripts locales te leen en la pos fake -> streaming/replicacion
        -- se queda ahi -> void distance gigante sin estres. Hook GLOBAL idempotente (no apila).
        if self:_flag("LocalHook", true) then
            self:_installHook()
            if self._gmask then self._gmask.hrp = hrp; self._gmask.cf = self._fakeCF; self._gmask.on = true end
        elseif self._gmask then self._gmask.on = false end
        local shootHold = self:_flag("ShootHold", 0.12)

        -- SIN pelea (entre rondas / target muerto-respawneando): QUEDARSE oculto en void; soltar camara.
        if not canFight then
            self:_setScriptCam(false)
            self._realTargetCF = CFrame.new(self:_desyncPos(self._fakeCF.Position))
            self._voidState = "void"; self._phaseUntil = now + voidTime
            self._inVoid = true; self._peekShotDone = false
            return
        end

        self:_setScriptCam(true)               -- con target: yo controlo la camara
        if not self._voidState then self._voidState = "void"; self._phaseUntil = now + voidTime end
        -- CAMARA SIEMPRE ENCIMA DEL TARGET (vista estable, ya lista para el tiro limpio; sin salto void->peek)
        local anchor = head.Position + Vector3.new(0, peekH, 0)
        if self._voidState == "void" then
            self._weldTarget = nil   -- void: sin weld, teleport random positivo
            self._realTargetCF = CFrame.new(self:_desyncPos(self._fakeCF.Position))  -- server: void
            self._inVoid = true
            cam.CFrame = CFrame.lookAt(anchor, head.Position)   -- camara encima del target
            if now >= self._phaseUntil then
                if self:_canShoot() then   -- solo peekear si podes disparar (no recargando)
                    self._voidState = "peek"; self._peekStart = now; self._peekShotDone = false
                    self._peekCF = CFrame.new(anchor)   -- LOCK pos (server sincroniza estable; PhysicsRepRootPart en el peek rompe el origin)
                else
                    self._phaseUntil = now + 0.1   -- recargando: seguir oculto en void
                end
            end
        elseif self._voidState == "peek" then
            self._weldTarget = nil
            self._realTargetCF = self._peekCF; self._inVoid = false   -- pos LOCKEADA
            cam.CFrame = CFrame.lookAt(self._peekCF.Position, head.Position)   -- aim a la cabeza actual
            local myHead = hrp.Parent and hrp.Parent:FindFirstChild("Head")
            local realPos = myHead and myHead.Position or hrp.Position
            local atPeek = (realPos - self._peekCF.Position).Magnitude < self:_flag("PeekTolerance", 8)   -- confirmado encima
            if not self._peekShotDone then
                if (now - self._peekStart) >= peekWait and atPeek then
                    self:_fire()
                    self._peekShotDone = true; self._shotAt = now
                elseif (now - self._peekStart) > (peekWait + 0.6) then
                    self._voidState = "void"; self._phaseUntil = now + voidTime      -- timeout: reintentar
                end
            elseif (now - self._shotAt) >= shootHold then
                self._voidState = "void"; self._phaseUntil = now + voidTime; self._peekShotDone = false
            end
        end
        return
    end

    -- ============ AIMBOT + AUTOSHOOT normal (sin void) ============
    if canFight then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, head.Position)
        local rate = math.max(self:_flag("FireRate", 20), 1)
        if self:_flag("AutoShoot", true) and self:_canShoot() and (now - self._lastFire) >= (1 / rate) then
            self:_fire(); self._lastFire = now
        end
    end
end

----------------------------------------------------------------------
function Rage:Init()
    if self.Loaded then return self end
    self.Loaded = true
    self:_getMech()
    local gm0 = getgenv and getgenv().RivalsMask; if gm0 then gm0.on = false end   -- limpiar mask pegada de sesion previa (camara)
    -- OOB se gestiona en _step (solo off cuando VoidSpam activo). NO tocar aqui.
    self.Conns[#self.Conns + 1] = RunService.RenderStepped:Connect(function()
        local ok, err = pcall(function() self:_step() end)
        if not ok then warn("[RivalsRage] " .. tostring(err)) end
        pcall(function() self:_updateHUD() end)
    end)
    -- Enforcement en loop task.wait(): resume DESPUES de todas las conexiones Heartbeat
    -- (incluida la del character controller del juego) -> nuestra escritura del RootPart
    -- es la ultima antes de replicar -> el void/peek se replican de verdad.
    -- (Heartbeat:Connect corre ANTES del controller y lo pisa -> no sirve.)
    task.spawn(function()
        while self.Loaded do
            local hrp = self:_myHRP()
            if hrp and self:_flag("Enabled", false) then
                -- WELD: PhysicsRepRootPart (el controller lo limpia cada frame -> re-setear) + CFrame relativo al enemigo
                if self._weldTarget and self._weldTarget.Parent and self:_flag("Weld", false) then
                    pcall(function() sethiddenproperty(hrp, "PhysicsRepRootPart", self._weldTarget) end)
                    pcall(function() hrp.CFrame = self._weldTarget.CFrame * (self._weldOffset or CFrame.new()) end)
                -- VOID/PEEK: imponer la posicion (le gana al controller)
                elseif self._realTargetCF and self:_flag("VoidSpam", false) then
                    pcall(function() hrp.CFrame = self._realTargetCF end)
                end
            end
            task.wait()
        end
    end)
    self.Conns[#self.Conns + 1] = LocalPlayer.CharacterAdded:Connect(function()
        self._inVoid = false; self._voidState = nil; self._realTargetCF = nil
    end)
    return self
end

--[[ ------------------------------------------------------------------
    UI  -  el modulo se construye SU PROPIO tab.
    RivalsMain no contiene ninguna referencia a rage: solo hace
    mod:BindFlags(Library.Flags) / mod:BuildUI(Library, Window) / mod:Init().
------------------------------------------------------------------ ]]
function Rage:BuildUI(Library, Window)
    if self._uiTab then return self._uiTab end
    local T = Window:AddTab("Rage")

    local rg  = T:AddLeftGroupbox("Rage Aimbot")
    local ren = rg:AddToggle("Rage_Enabled", { Text = "Enable Rage", Default = false })
    ren:AddDropdown("Rage_Activation",  { Text = "Activacion", Values = { "Always", "Hold Right Click", "Hold Left Click" }, Default = "Always" })
    ren:AddToggle("Rage_AutoShoot",     { Text = "Auto disparo (interno)", Default = true })
    ren:AddToggle("Rage_RoundOnly",     { Text = "Solo en ronda (anti-lobby)", Default = true })
    ren:AddToggle("Rage_TeamCheck",     { Text = "Team check (no aliados)", Default = true })
    ren:AddToggle("Rage_IgnoreDummies", { Text = "Ignorar dummies", Default = true })
    ren:AddSlider("Rage_FOV",           { Text = "FOV",      Min = 10,  Max = 2000, Default = 400, Suffix = "px" })
    ren:AddSlider("Rage_FireRate",      { Text = "Cadencia",  Min = 1,   Max = 30,   Default = 20,  Suffix = "/s" })
    ren:AddSlider("Rage_MaxDistance",   { Text = "Alcance",  Min = 100, Max = 30000000, Default = 30000000, Suffix = "m" })
    ren:AddToggle("Rage_VisibleCheck",  { Text = "Solo visibles", Default = false })

    local rw = T:AddLeftGroupbox("Weld (melee / escudo)")
    rw:AddLabel("Soldarse al enemigo (PhysicsRepRootPart)")
    local rwen = rw:AddToggle("Rage_Weld", { Text = "Weld al target", Default = false })
    rwen:AddToggle("Rage_WeldMeleeOnly",  { Text = "Solo con melee (slot 3)", Default = true })
    rwen:AddToggle("Rage_WeldAutoAttack", { Text = "Auto-atacar (melee)", Default = false })
    rwen:AddSlider("Rage_WeldBehind",     { Text = "Detras (atras)", Min = -5, Max = 8, Default = 2.5, Decimals = 1, Suffix = "st" })
    rwen:AddSlider("Rage_WeldHeight",     { Text = "Altura", Min = -6, Max = 6, Default = 0, Decimals = 1, Suffix = "st" })

    local rv = T:AddRightGroupbox("Void Spam  (AVANZADO)")
    rv:AddLabel("Mueve el HRP real. Riesgo ban AC.")
    rv:AddLabel("Probar SOLO en VIP/alt, no en main.")
    local rven = rv:AddToggle("Rage_VoidSpam", { Text = "Void Spam", Default = false })
    rven:AddDropdown("Rage_DesyncPreset", { Text = "Preset desync", Values = { "Random", "Fixed", "infswitch" }, Default = "Random" })
    rven:AddToggle("Rage_DisableOOB",  { Text = "Disable OOB check", Default = true })
    rven:AddToggle("Rage_LocalHook",   { Text = "Spoof pos (__index hook)", Default = true })
    rven:AddSlider("Rage_VoidTime",      { Text = "Tiempo en void (out)", Min = 0.15, Max = 3, Default = 0.6, Decimals = 2, Suffix = "s" })
    rven:AddSlider("Rage_PeekWait",      { Text = "Espera peek (sync)", Min = 0.02, Max = 0.6, Default = 0.18, Decimals = 2, Suffix = "s" })
    rven:AddSlider("Rage_ShootHold",     { Text = "Hold tras tiro", Min = 0, Max = 0.6, Default = 0, Decimals = 2, Suffix = "s" })
    rven:AddSlider("Rage_PeekTolerance", { Text = "Tolerancia peek", Min = 2, Max = 30, Default = 8, Suffix = "st" })
    rven:AddSlider("Rage_PeekHeight",    { Text = "Altura peek (encima)", Min = 5, Max = 260, Default = 260, Suffix = "st" })
    rven:AddSlider("Rage_VoidDistance",  { Text = "Distancia void (Fixed)", Min = 5000, Max = 2000000000, Default = 100000, Suffix = "st" })

    -- HUD va inyectado en el tab Visuals de la BASE (no en el tab Rage): la base
    -- nunca referencia rage, pero el groupbox aparece donde el user lo quiere.
    local visuals = Window:GetTab("Visuals")
    local rh = (visuals and visuals.AddRightGroupbox)
        and visuals:AddRightGroupbox("HUD (labels)")
        or  T:AddRightGroupbox("HUD (labels)")   -- fallback: si no hay Visuals, queda en Rage
    self._hudBox, self._hudTab = rh, visuals or T
    local rhen = rh:AddToggle("Rage_HUD", { Text = "Mostrar HUD", Default = true })
    rhen:AddSlider("Rage_HUDOffset",    { Text = "Bajo el crosshair", Min = -300, Max = 400, Default = 42, Suffix = "px" })
    rhen:AddSlider("Rage_HUDFadeSpeed", { Text = "Velocidad fade", Min = 0, Max = 4, Default = 0.6, Decimals = 2, Suffix = "/s" })
    rhen:AddSlider("Rage_HUDSize", { Text = "Tamano", Min = 10, Max = 40, Default = 17 })
    rhen:AddColorPicker("Rage_HUDFadeFrom",    { Text = "Ragebot fade desde", Default = Color3.fromRGB(255, 255, 255) })
    rhen:AddColorPicker("Rage_HUDFadeTo",      { Text = "Ragebot fade hasta", Default = Color3.fromRGB(0, 0, 0) })
    rhen:AddColorPicker("Rage_HUDVoidColor",   { Text = "Color Void", Default = Color3.fromRGB(150, 150, 160) })
    rhen:AddColorPicker("Rage_HUDKillColor",   { Text = "Color killing", Default = Color3.fromRGB(255, 255, 255) })
    rhen:AddColorPicker("Rage_HUDHealthColor", { Text = "Color health", Default = Color3.fromRGB(120, 230, 120) })

    self._uiTab = T
    return T
end

function Rage:Unload()
    if not self.Loaded then return end
    self.Loaded = false
    self:_resetVoid(self:_myHRP())   -- devolver pos + camara antes de soltar
    self:_weldClear(self:_myHRP())   -- soltar PhysicsRepRootPart
    if self._hudDrawings then for _, o in ipairs(self._hudDrawings) do pcall(function() o.Visible = false; o:Remove() end) end table.clear(self._hudDrawings) end
    self._hud = nil
    -- soltar el groupbox que inyectamos en Visuals (si no, queda con flags muertos)
    if self._hudBox and self._hudTab and self._hudTab.RemoveGroupbox then
        pcall(function() self._hudTab:RemoveGroupbox(self._hudBox) end)
    end
    self._hudBox, self._hudTab = nil, nil
    for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
    table.clear(self.Conns)
    self:_setOOB(false)   -- restaurar el reporter OOB
    self._inVoid = false
end

return Rage
