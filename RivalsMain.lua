--[[
    RivalsMain  -  script principal (build 1.0)
    ------------------------------------------------------------------
    Se carga con:
        loadstring(game:HttpGet(".../Loader.lua"))()
    RightShift = toggle menu.

    BASE LIMPIA: ESP + aimbot + triggerbot + chams locales + HUD + config.
    Cero hooks, cero setthreadidentity, cero sethiddenproperty: solo lee
    instancias y usa la API que el juego ya expone.

    Modulos que baja solo (legit, sin hooks):
        RivalsUI       la libreria de UI (Drawing, 0 instancias)
        RivalsVisuals  mundo: lighting/fog/tinte/cielo/clima
        RivalsCombat   camara: 3ra persona/FOV/sacudida + anti-flash/humo

    Modulo que NO baja solo:
        RivalsRage     hookea __index, mueve el HRP real, escribe
                       propiedades ocultas. Se pide a mano en
                       Settings > Modulos, con aviso y chequeo de que tu
                       ejecutor soporte las funciones. El flag de autocarga
                       vive en RivalsMenu_modules.json.

    Configs con nombre en RivalsConfigs/. Cargar una que traiga rage activo
    pide confirmacion; Rage_Enabled y Rage_VoidSpam nunca se guardan.
------------------------------------------------------------------ ]]

local UI_URL     = "https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/RivalsUI.lua"
local HttpService = game:GetService("HttpService")
local CONFIG_PATH = "RivalsMenu_config.json"   -- config legacy (se migra a la carpeta)
local CONFIG_DIR  = "RivalsConfigs"           -- carpeta de configs con nombre

if getgenv().RivalsMenu then
    pcall(function()
        local m = getgenv().RivalsMenu
        for _, mod in ipairs({ "Rage", "Visuals", "Combat", "HUD", "Trigger", "Local", "Aim", "ESP" }) do if m[mod] then m[mod]:Unload() end end
        if m.Library then m.Library:Unload() end
    end)
    getgenv().RivalsMenu = nil
end

local Library = loadstring(game:HttpGet(UI_URL))()

--==================================================================
-- ESP
--   Drawing puro: 0 instancias nuevas (los chams cambian Material/Color
--   de partes que ya existen, por eso NO atraviesan paredes; un
--   Highlight lo haria pero mete una Instance por enemigo).
--   Datos del juego: EnvironmentID (arena/duelo), TeamID, Level,
--   FighterController._player_to_fighter -> EquippedItem.
--==================================================================
local ESP = (function()
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local CollectionService = game:GetService("CollectionService")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer

    -- R15: pares de partes que forman el esqueleto. Los dummies del range no
    -- tienen estas partes -> el esqueleto simplemente no se dibuja en ellos.
    local BONES = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
    }

    local ESP = { Drawings = {}, Objects = {}, Conns = {}, Loaded = false, Flags = nil, orig = {},
        Settings = {
            Enabled = true, Box = true, Name = true, Health = true, Distance = true,
            Tracer = false, TracerOrigin = "Abajo", TracerEnd = "Pies",
            PlayersOnly = false, MaxDistance = 1200,
            ArenaOnly = true,                       -- solo tu duelo (EnvironmentID)
            Items = false, ItemColor = Color3.fromRGB(255, 170, 60), ItemDistance = 400,
            Skeleton = false,
            TeamColors = false, EnemyColor = Color3.fromRGB(255, 80, 80), AllyColor = Color3.fromRGB(90, 190, 255),
            ShowLevel = false, ShowWeapon = false,
            Arrows = false, ArrowRadius = 200, ArrowSize = 16, ArrowColor = Color3.fromRGB(255, 200, 60),
            VisCheck = false, VisibleColor = Color3.fromRGB(120, 240, 120), HiddenColor = Color3.fromRGB(240, 120, 120),
            Chams = false, ChamsMaterial = "Neon", ChamsColor = Color3.fromRGB(255, 60, 200),
            BoxColor = Color3.fromRGB(235, 235, 240), NameColor = Color3.fromRGB(235, 235, 240),
            TracerColor = Color3.fromRGB(96, 130, 255), Font = 2, TextSize = 13,
        } }

    function ESP:_flag(k, d)
        if self.Flags then local v = self.Flags["ESP_" .. k]; if v ~= nil then return v end end
        local s = self.Settings[k]; if s ~= nil then return s end
        return d
    end
    function ESP:_draw(c, p)
        local o = Drawing.new(c); o.Visible = false
        if p then for k, v in pairs(p) do o[k] = v end end
        table.insert(self.Drawings, o); return o
    end
    function ESP:BindFlags(ft) self.Flags = ft end

    function ESP:_make()
        local S = self.Settings
        local b = {
            box = self:_draw("Square", { Filled = false, Thickness = 1, Color = S.BoxColor }),
            boxOl = self:_draw("Square", { Filled = false, Thickness = 3, Color = Color3.new(0, 0, 0) }),
            name = self:_draw("Text", { Font = S.Font, Size = S.TextSize, Center = true, Outline = true, Color = S.NameColor }),
            dist = self:_draw("Text", { Font = S.Font, Size = S.TextSize, Center = true, Outline = true, Color = Color3.fromRGB(180, 180, 185) }),
            weapon = self:_draw("Text", { Font = S.Font, Size = S.TextSize, Center = true, Outline = true, Color = Color3.fromRGB(200, 200, 210) }),
            hpBg = self:_draw("Square", { Filled = true, Color = Color3.new(0, 0, 0) }),
            hpBar = self:_draw("Square", { Filled = true, Color = Color3.fromRGB(90, 220, 90) }),
            tracer = self:_draw("Line", { Thickness = 1, Color = S.TracerColor }),
            arrow = self:_draw("Triangle", { Filled = true, Color = S.ArrowColor }),
            bones = {},
        }
        for i = 1, #BONES do b.bones[i] = self:_draw("Line", { Thickness = 1, Color = S.BoxColor }) end
        return b
    end
    local function hide(b)
        for k, o in pairs(b) do
            if k == "bones" then for _, l in ipairs(o) do l.Visible = false end
            else o.Visible = false end
        end
    end
    local function alive(model)
        if not model:IsA("Model") then return end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local root = model:FindFirstChild("HumanoidRootPart")
        local head = model:FindFirstChild("Head")
        if not root or not head then return end
        return hum, root, head
    end
    function ESP:_hc(f) return Color3.fromRGB(math.floor(220 * (1 - f)) + 20, math.floor(200 * f) + 20, 40) end

    ---------------------------------------------------------------- datos del juego
    function ESP:_fighterCtl()
        if not self._fc then local ok, f = pcall(require, LocalPlayer.PlayerScripts.Controllers.FighterController) if ok then self._fc = f end end
        return self._fc
    end
    function ESP:_equipped()
        if not self._mech then local ok, m = pcall(require, LocalPlayer.PlayerScripts.Controllers.MechanicsController) if ok then self._mech = m end end
        local mech = self._mech
        return mech and mech.LocalFighter and mech.LocalFighter.EquippedItem
    end
    -- arma que lleva OTRO jugador (via el mapa del propio FighterController)
    function ESP:_weaponOf(player)
        local fc = self:_fighterCtl()
        local f = fc and fc._player_to_fighter and fc._player_to_fighter[player]
        if not f then return nil end
        local ok, name = pcall(function()
            local it = f.EquippedItem
            return it and it.Info and (it.Info.Name or it.Name)
        end)
        return ok and name or nil
    end
    -- EnvironmentID = en que arena/duelo esta. Rivals corre varios duelos por
    -- server -> sin este filtro el ESP dibuja gente de OTRAS arenas.
    function ESP:_sameArena(model, player)
        if not self:_flag("ArenaOnly", true) then return true end
        local mine = LocalPlayer:GetAttribute("EnvironmentID")
        if mine == nil then return true end
        local theirs = (player and player:GetAttribute("EnvironmentID")) or model:GetAttribute("EnvironmentID")
        if theirs == nil then return true end
        return mine == theirs
    end
    function ESP:_isAlly(player)
        if not player then return false end
        local mine = LocalPlayer:GetAttribute("TeamID")
        local theirs = player:GetAttribute("TeamID")
        if mine == nil or theirs == nil then return false end
        return mine == theirs
    end
    function ESP:_visible(camPos, part, model)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild("ViewModels") }
        local r = workspace:Raycast(camPos, part.Position - camPos, rp)
        return (not r) or r.Instance:IsDescendantOf(model)
    end

    ---------------------------------------------------------------- tracer
    function ESP:_muzzleScreen(C)
        local item = self:_equipped()
        if not item then return nil end
        local ok, class = pcall(function() return item.Info and item.Info.Class end)
        if ok and class == "Melee" then return nil end       -- melee: sin cano -> centro
        local ok2, pos = pcall(function() return item.ViewModel and item.ViewModel:GetMuzzlePosition() end)
        if not ok2 or typeof(pos) ~= "Vector3" then return nil end
        local sp = C:WorldToViewportPoint(pos)
        if sp.Z <= 0 then return nil end
        return Vector2.new(sp.X, sp.Y)
    end
    function ESP:_tracerOrigin(C)
        local vp = C.ViewportSize
        local mode = self:_flag("TracerOrigin", "Abajo")
        if mode == "Mouse" then local m = UserInputService:GetMouseLocation() return Vector2.new(m.X, m.Y) end
        if mode == "Punta del arma" then return self:_muzzleScreen(C) or Vector2.new(vp.X / 2, vp.Y / 2) end
        if mode == "Centro pantalla" then return Vector2.new(vp.X / 2, vp.Y / 2) end
        if mode == "Arriba" then return Vector2.new(vp.X / 2, 0) end
        return Vector2.new(vp.X / 2, vp.Y)
    end

    ---------------------------------------------------------------- chams (sin instancias)
    local function matEnum(n) local ok, m = pcall(function() return Enum.Material[n] end) return ok and m or Enum.Material.Neon end
    --[[ PERF: self.orig se indexa por MODELO, no por parte.
         Antes era orig[part] y _unCham(model) recorria TODA la tabla llamando
         IsDescendantOf por parte. Como _update llama _unCham por cada entity sin
         Humanoid vivo (172 en el range), eran ~90k recorridos de arbol por frame:
         medido 46.8 ms/frame = 19 fps. Indexado por modelo, el caso comun
         ("este entity no tiene chams") es un lookup y sale. ]]
    local function restorePart(part, o)
        part.Material = o.Material
        part.Color = o.Color
        if o.TextureID ~= nil then part.TextureID = o.TextureID end
    end
    function ESP:_cham(model, part, mat, col)
        local mt = self.orig[model]
        if not mt then mt = {}; self.orig[model] = mt end
        local o = mt[part]
        if not o then
            o = { Material = part.Material, Color = part.Color }
            if part:IsA("MeshPart") then o.TextureID = part.TextureID end
            mt[part] = o
        end
        if part.Material ~= mat then part.Material = mat end
        if part.Color ~= col then part.Color = col end
        -- textura tapa el material (mismo motivo que en los self-chams)
        if part:IsA("MeshPart") and part.TextureID ~= "" then part.TextureID = "" end
    end
    function ESP:_unCham(model)
        if model then
            local mt = self.orig[model]
            if not mt then return end            -- caso comun: O(1) y afuera
            for part, o in pairs(mt) do pcall(restorePart, part, o) end
            self.orig[model] = nil
        else
            for m in pairs(self.orig) do self:_unCham(m) end
        end
    end

    ---------------------------------------------------------------- flecha off-screen
    function ESP:_arrow(b, C, worldPos, color)
        local vp = C.ViewportSize
        local center = Vector2.new(vp.X / 2, vp.Y / 2)
        local rel = C.CFrame:PointToObjectSpace(worldPos)
        local dir = Vector2.new(rel.X, -rel.Z)
        if dir.Magnitude < 1e-3 then b.arrow.Visible = false return end
        dir = dir.Unit
        local pos = center + dir * self:_flag("ArrowRadius", 200)
        local sz = self:_flag("ArrowSize", 16)
        local perp = Vector2.new(-dir.Y, dir.X)
        b.arrow.PointA = pos + dir * sz
        b.arrow.PointB = pos - dir * sz * 0.5 + perp * sz * 0.6
        b.arrow.PointC = pos - dir * sz * 0.5 - perp * sz * 0.6
        b.arrow.Color = color
        b.arrow.ZIndex = 5
        b.arrow.Visible = true
    end

    --[[ ESP de granadas / trampas desplegadas.
         Los throwables y proyectiles son clones de PlayerScripts.Assets.
         Throwables / .Projectiles, asi que el catalogo da los nombres. Se
         cazan por DescendantAdded (evento) y NO escaneando workspace cada
         frame: escanear 200+ entities por frame ya nos costo 19 fps una vez. ]]
    function ESP:_itemNames()
        if self._names then return self._names end
        local set = { ["Subspace Tripmine"] = true, ["Tripmine"] = true }
        local A = LocalPlayer.PlayerScripts:FindFirstChild("Assets")
        for _, folder in ipairs({ "Throwables", "Projectiles" }) do
            local f = A and A:FindFirstChild(folder)
            if f then for _, m in ipairs(f:GetChildren()) do set[m.Name] = true end end
        end
        self._names = set
        return set
    end
--[[ Filtrar por nombre solo no alcanza: "Camera" y "RPG" estan en el
     catalogo de armas, asi que un escaneo del mapa levanta decoracion
     (rpg_bundle, Beach Ball del lobby), partes del viewmodel propio y hasta
     el emisor de clima de RivalsVisuals. Dos reglas lo resuelven:
       1) NO escanear el mapa al init. Lo desplegado (granadas, minas) nace
          DESPUES de cargar; la decoracion ya estaba -> solo escuchamos
          DescendantAdded.
       2) Solo Models. Los falsos positivos que quedaban eran BaseParts. ]]
    function ESP:_watchItems()
        self._items = {}
        local names = self:_itemNames()
        local function consider(d)
            if not d:IsA("Model") or not names[d.Name] then return end
            if d:FindFirstAncestor("ViewModels") or d:FindFirstAncestor("Lobby") then return end
            if d:FindFirstAncestor("LooseWeaponDisplay") or d:FindFirstAncestor("Weapons") then return end
            self._items[d] = true
        end
        self.Conns[#self.Conns + 1] = workspace.DescendantAdded:Connect(function(d) pcall(consider, d) end)
        self.Conns[#self.Conns + 1] = workspace.DescendantRemoving:Connect(function(d) self._items[d] = nil end)
    end
    function ESP:_itemPos(d)
        if d:IsA("BasePart") then return d.Position end
        local ok, cf = pcall(function() return d:GetPivot() end)
        return ok and cf.Position or nil
    end
    function ESP:_drawItems(C, origin)
        self._itemDraw = self._itemDraw or {}
        local show = self:_flag("Items", false)
        local maxD = self:_flag("ItemDistance", 400)
        local col = self:_flag("ItemColor", self.Settings.ItemColor)
        local i = 0
        if show then
            for d in pairs(self._items or {}) do
                if not d.Parent then
                    self._items[d] = nil
                else
                    local pos = self:_itemPos(d)
                    if pos then
                        local dist = (pos - origin).Magnitude
                        if dist <= maxD then
                            local sp = C:WorldToViewportPoint(pos)
                            if sp.Z > 0 then
                                i = i + 1
                                local o = self._itemDraw[i]
                                if not o then
                                    o = {
                                        dot = self:_draw("Circle", { Filled = true, NumSides = 8, Radius = 3 }),
                                        txt = self:_draw("Text", { Font = self.Settings.Font, Size = self.Settings.TextSize, Center = true, Outline = true }),
                                    }
                                    self._itemDraw[i] = o
                                end
                                o.dot.Position = Vector2.new(sp.X, sp.Y); o.dot.Color = col; o.dot.ZIndex = 4; o.dot.Visible = true
                                o.txt.Text = d.Name .. "  " .. math.floor(dist) .. "m"
                                o.txt.Position = Vector2.new(sp.X, sp.Y + 6); o.txt.Color = col; o.txt.ZIndex = 4; o.txt.Visible = true
                            end
                        end
                    end
                end
            end
        end
        for j = i + 1, #self._itemDraw do
            self._itemDraw[j].dot.Visible = false
            self._itemDraw[j].txt.Visible = false
        end
    end

    ---------------------------------------------------------------- update
    function ESP:_update()
        if not self.Loaded then return end
        local enabled = self:_flag("Enabled", true)
        local C = workspace.CurrentCamera
        local myChar = LocalPlayer.Character
        local origin = C.CFrame.Position

        local live = {}
        if enabled then
            local po = self:_flag("PlayersOnly", false)
            local cs
            if po then cs = {} for _, p in ipairs(Players:GetPlayers()) do if p.Character then cs[p.Character] = p end end end
            for _, m in ipairs(CollectionService:GetTagged("Entity")) do
                if m ~= myChar and (not cs or cs[m]) then
                    local pl = Players:GetPlayerFromCharacter(m)
                    if self:_sameArena(m, pl) then live[m] = true end
                end
            end
        end
        for model, b in pairs(self.Objects) do
            if not live[model] or not model.Parent then
                hide(b)
                if not model.Parent then self.Objects[model] = nil end
            end
        end
        if not enabled then
            if next(self.orig) then self:_unCham(nil) end
            for _, o in ipairs(self._itemDraw or {}) do o.dot.Visible = false; o.txt.Visible = false end
            return
        end

        local sBox, sName = self:_flag("Box", true), self:_flag("Name", true)
        local sHp, sDist = self:_flag("Health", true), self:_flag("Distance", true)
        local sTr = self:_flag("Tracer", false)
        local sSkel = self:_flag("Skeleton", false)
        local sArrow = self:_flag("Arrows", false)
        local sVis = self:_flag("VisCheck", false)
        local sTeam = self:_flag("TeamColors", false)
        local sLevel, sWeapon = self:_flag("ShowLevel", false), self:_flag("ShowWeapon", false)
        local sChams = self:_flag("Chams", false)
        local maxD = self:_flag("MaxDistance", 1200)
        local vp = C.ViewportSize
        local trFrom = sTr and self:_tracerOrigin(C) or nil
        local trEnd = self:_flag("TracerEnd", "Pies")
        self:_drawItems(C, origin)
        local chamMat, chamCol = matEnum(self:_flag("ChamsMaterial", "Neon")), self:_flag("ChamsColor", self.Settings.ChamsColor)
        if not sChams and next(self.orig) then self:_unCham(nil) end

        for model in pairs(live) do
            local hum, root, head = alive(model)
            local b = self.Objects[model]
            if not hum then
                if b then hide(b) end
                self:_unCham(model)
            else
                local dist = (root.Position - origin).Magnitude
                if dist > maxD then
                    if b then hide(b) end
                    self:_unCham(model)   -- fuera de rango: soltar chams (si no, quedaba pintado para siempre)
                else
                    if not b then b = self:_make(); self.Objects[model] = b end
                    local player = Players:GetPlayerFromCharacter(model)
                    local seen = (not sVis) or self:_visible(origin, head, model)

                    -- color: team manda sobre visibilidad
                    local col = self:_flag("BoxColor", self.Settings.BoxColor)
                    if sTeam and player then
                        col = self:_isAlly(player) and self:_flag("AllyColor", self.Settings.AllyColor) or self:_flag("EnemyColor", self.Settings.EnemyColor)
                    elseif sVis then
                        col = seen and self:_flag("VisibleColor", self.Settings.VisibleColor) or self:_flag("HiddenColor", self.Settings.HiddenColor)
                    end

                    if sChams then
                        for _, d in ipairs(model:GetChildren()) do
                            if d:IsA("BasePart") and not d.Name:find("Hitbox") and d.Name ~= "FakeMass" and d.Transparency < 1 then
                                self:_cham(model, d, chamMat, chamCol)
                            end
                        end
                    end

                    local tV = C:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                    local bV = C:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                    local onScreen = (tV.Z > 0 or bV.Z > 0)
                        and (tV.X >= 0 and tV.X <= vp.X and tV.Y >= 0 and tV.Y <= vp.Y)

                    -- flecha: SOLO cuando el enemigo NO esta en pantalla
                    if sArrow and not onScreen then
                        self:_arrow(b, C, head.Position, sTeam and col or self:_flag("ArrowColor", self.Settings.ArrowColor))
                    else
                        b.arrow.Visible = false
                    end

                    if tV.Z <= 0 and bV.Z <= 0 then
                        for k, o in pairs(b) do
                            if k ~= "arrow" then
                                if k == "bones" then for _, l in ipairs(o) do l.Visible = false end else o.Visible = false end
                            end
                        end
                    else
                        local top, bot = Vector2.new(tV.X, tV.Y), Vector2.new(bV.X, bV.Y)
                        local h = math.abs(bot.Y - top.Y)
                        local w = h * 0.62
                        local x, y = top.X - w / 2, top.Y

                        b.box.Visible, b.boxOl.Visible = sBox, sBox
                        if sBox then
                            b.box.Size = Vector2.new(w, h); b.box.Position = Vector2.new(x, y); b.box.ZIndex = 2; b.box.Color = col
                            b.boxOl.Size = b.box.Size; b.boxOl.Position = b.box.Position; b.boxOl.ZIndex = 1
                        end

                        local frac = math.clamp(hum.Health / (hum.MaxHealth > 0 and hum.MaxHealth or 100), 0, 1)
                        b.hpBg.Visible, b.hpBar.Visible = sHp, sHp
                        if sHp then
                            local bx = x - 5
                            b.hpBg.Position = Vector2.new(bx, y - 1); b.hpBg.Size = Vector2.new(3, h + 2); b.hpBg.ZIndex = 2
                            local bh = h * frac
                            b.hpBar.Position = Vector2.new(bx, y + (h - bh)); b.hpBar.Size = Vector2.new(3, bh)
                            b.hpBar.Color = self:_hc(frac); b.hpBar.ZIndex = 3
                        end

                        b.name.Visible = sName
                        if sName then
                            local txt = player and player.Name or model.Name
                            if sLevel and player then
                                local lvl = player:GetAttribute("Level")
                                if lvl then txt = txt .. "  [" .. tostring(lvl) .. "]" end
                            end
                            b.name.Text = txt
                            b.name.Color = col
                            b.name.Position = Vector2.new(top.X, y - self.Settings.TextSize - 2); b.name.ZIndex = 4
                        end

                        local by = bot.Y + 2
                        b.dist.Visible = sDist
                        if sDist then
                            b.dist.Text = math.floor(dist) .. "m"
                            b.dist.Position = Vector2.new(top.X, by); b.dist.ZIndex = 4
                            by = by + self.Settings.TextSize
                        end
                        b.weapon.Visible = sWeapon and player ~= nil
                        if b.weapon.Visible then
                            local wn = self:_weaponOf(player)
                            if wn then
                                b.weapon.Text = tostring(wn)
                                b.weapon.Position = Vector2.new(top.X, by); b.weapon.ZIndex = 4
                            else
                                b.weapon.Visible = false
                            end
                        end

                        -- esqueleto (R15; los dummies no tienen estas partes)
                        for i, pair in ipairs(BONES) do
                            local line = b.bones[i]
                            local p1, p2 = model:FindFirstChild(pair[1]), model:FindFirstChild(pair[2])
                            if sSkel and p1 and p2 then
                                local s1 = C:WorldToViewportPoint(p1.Position)
                                local s2 = C:WorldToViewportPoint(p2.Position)
                                if s1.Z > 0 and s2.Z > 0 then
                                    line.From = Vector2.new(s1.X, s1.Y); line.To = Vector2.new(s2.X, s2.Y)
                                    line.Color = col; line.ZIndex = 3; line.Visible = true
                                else line.Visible = false end
                            else line.Visible = false end
                        end

                        b.tracer.Visible = sTr and trFrom ~= nil
                        if b.tracer.Visible then
                            local to
                            if trEnd == "Cabeza" then to = top
                            elseif trEnd == "HRP" then local rV = C:WorldToViewportPoint(root.Position); to = Vector2.new(rV.X, rV.Y)
                            else to = bot end
                            b.tracer.From = trFrom; b.tracer.To = to; b.tracer.Color = col; b.tracer.ZIndex = 1
                        end
                    end
                end
            end
        end
    end

    function ESP:Init()
        if self.Loaded then return self end
        self.Loaded = true
        pcall(function() self:_watchItems() end)
        self.Conns[#self.Conns + 1] = RunService.RenderStepped:Connect(function() pcall(function() self:_update() end) end)
        return self
    end
    function ESP:Unload()
        if not self.Loaded then return end
        self.Loaded = false
        for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
        self:_unCham(nil)
        for _, o in ipairs(self.Drawings) do pcall(function() o.Visible = false; o:Remove() end) end
        table.clear(self.Drawings); table.clear(self.Objects); table.clear(self.Conns); table.clear(self.orig)
    end
    return ESP
end)()

--==================================================================
-- AIMBOT (Mouse + Camera)
--==================================================================
local Aim = (function()
    local Players=game:GetService("Players") local RunService=game:GetService("RunService") local UserInputService=game:GetService("UserInputService") local CollectionService=game:GetService("CollectionService") local LocalPlayer=Players.LocalPlayer
    local mouseMove=rawget(getfenv(),"mousemoverel") or mousemoverel
    local Aim={Drawings={},Conns={},Loaded=false,Flags=nil,CurrentTarget=nil,Settings={Enabled=false,Method="Mouse",Activation="Hold Right Click",TargetPart="Head",FOV=120,Smoothness=6,MaxDistance=1000,VisibleCheck=false,ShowFOV=true,FOVColor=Color3.fromRGB(96,130,255)}}
    function Aim:_flag(k,d) if self.Flags then local v=self.Flags["Aim_"..k] if v~=nil then return v end end local s=self.Settings[k] if s~=nil then return s end return d end
    function Aim:_draw(c,p) local o=Drawing.new(c) o.Visible=false if p then for k,v in pairs(p) do o[k]=v end end table.insert(self.Drawings,o) return o end
    function Aim:BindFlags(ft) self.Flags=ft end
    local function pn(sel) return sel=="Body" and "HitboxBody" or "HitboxHead" end
    function Aim:_active() if not self:_flag("Enabled",false) then return false end local m=self:_flag("Activation","Hold Right Click") if m=="Always" then return true end if m=="Hold Right Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end if m=="Hold Left Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end return false end
    function Aim:_visible(cam,part,model) if not self:_flag("VisibleCheck",false) then return true end local p=RaycastParams.new() p.FilterType=Enum.RaycastFilterType.Exclude p.FilterDescendantsInstances={LocalPlayer.Character} local r=workspace:Raycast(cam.CFrame.Position,part.Position-cam.CFrame.Position,p) return (not r) or r.Instance:IsDescendantOf(model) end
    function Aim:_getTarget() local C=workspace.CurrentCamera local vp=C.ViewportSize local center=Vector2.new(vp.X/2,vp.Y/2) local fov=self:_flag("FOV",120) local maxD=self:_flag("MaxDistance",1000) local pName=pn(self:_flag("TargetPart","Head")) local myChar=LocalPlayer.Character local origin=C.CFrame.Position local best,bs,bp=nil,fov,nil
        for _,model in ipairs(CollectionService:GetTagged("Entity")) do if model~=myChar then local hum=model:FindFirstChildOfClass("Humanoid") local part=model:FindFirstChild(pName) or model:FindFirstChild("Head")
            if hum and hum.Health>0 and part then local sp=C:WorldToViewportPoint(part.Position) if sp.Z>0 then local d=(Vector2.new(sp.X,sp.Y)-center).Magnitude local dist=(part.Position-origin).Magnitude if d<=bs and dist<=maxD and self:_visible(C,part,model) then best,bs,bp=model,d,part end end end end end return best,bp end
    function Aim:_step() local model,part=self:_getTarget() self.CurrentTarget=model if not part then return end local C=workspace.CurrentCamera local method=self:_flag("Method","Mouse") local smooth=math.max(self:_flag("Smoothness",6),1)
        if method=="Camera" then local desired=CFrame.lookAt(C.CFrame.Position,part.Position) C.CFrame=C.CFrame:Lerp(desired,math.clamp(1/smooth,0,1)) else if not mouseMove then return end local sp=C:WorldToViewportPoint(part.Position) local vp=C.ViewportSize mouseMove((sp.X-vp.X/2)/smooth,(sp.Y-vp.Y/2)/smooth) end end
    function Aim:_updateFOV() if not self.fovCircle then self.fovCircle=self:_draw("Circle",{Thickness=1,NumSides=48,Filled=false,Color=self.Settings.FOVColor}) end local show=self:_flag("Enabled",false) and self:_flag("ShowFOV",true) self.fovCircle.Visible=show if show then local vp=workspace.CurrentCamera.ViewportSize self.fovCircle.Position=Vector2.new(vp.X/2,vp.Y/2) self.fovCircle.Radius=self:_flag("FOV",120) self.fovCircle.ZIndex=1 end end
    function Aim:Init() if self.Loaded then return self end self.Loaded=true self.Conns[#self.Conns+1]=RunService.RenderStepped:Connect(function() pcall(function() self:_updateFOV() if self:_active() then self:_step() else self.CurrentTarget=nil end end) end) return self end
    function Aim:Unload() if not self.Loaded then return end self.Loaded=false for _,c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end for _,o in ipairs(self.Drawings) do pcall(function() o.Visible=false o:Remove() end) end table.clear(self.Drawings) table.clear(self.Conns) self.fovCircle=nil end
    return Aim end)()

--==================================================================
-- TRIGGERBOT
--==================================================================
local Trigger = (function()
    local Players=game:GetService("Players") local RunService=game:GetService("RunService") local UserInputService=game:GetService("UserInputService") local CollectionService=game:GetService("CollectionService") local LocalPlayer=Players.LocalPlayer
    local click=mouse1click local press=mouse1press local release=mouse1release
    local Trigger={Conns={},Loaded=false,Flags=nil,_lastShot=0,_armedAt=nil,Settings={Enabled=false,Activation="Hold Middle Click",Delay=30,Refire=120,MaxDistance=1000,HeadOnly=false}}
    function Trigger:_flag(k,d) if self.Flags then local v=self.Flags["Trig_"..k] if v~=nil then return v end end local s=self.Settings[k] if s~=nil then return s end return d end
    function Trigger:BindFlags(ft) self.Flags=ft end
    function Trigger:_active() if not self:_flag("Enabled",false) then return false end local m=self:_flag("Activation","Hold Middle Click") if m=="Always" then return true end if m=="Hold Right Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end if m=="Hold Middle Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) end return false end
    function Trigger:_targetUnderCrosshair() local C=workspace.CurrentCamera local p=RaycastParams.new() p.FilterType=Enum.RaycastFilterType.Exclude p.FilterDescendantsInstances={LocalPlayer.Character,workspace:FindFirstChild("ViewModels")} local r=workspace:Raycast(C.CFrame.Position,C.CFrame.LookVector*self:_flag("MaxDistance",1000),p) if not r then return false end
        local m=r.Instance:FindFirstAncestorWhichIsA("Model") while m do if CollectionService:HasTag(m,"Entity") and m~=LocalPlayer.Character then local hum=m:FindFirstChildOfClass("Humanoid") if hum and hum.Health>0 then if self:_flag("HeadOnly",false) then return r.Instance.Name:find("Head")~=nil end return true end end m=m:FindFirstAncestorWhichIsA("Model") end return false end
    function Trigger:_tick() if not self:_active() then self._armedAt=nil return end local now=tick()*1000 if not self:_targetUnderCrosshair() then self._armedAt=nil return end if not self._armedAt then self._armedAt=now return end if now-self._armedAt<self:_flag("Delay",30) then return end if now-self._lastShot<self:_flag("Refire",120) then return end self._lastShot=now if click then click() elseif press and release then press() release() end end
    function Trigger:Init() if self.Loaded then return self end self.Loaded=true self.Conns[#self.Conns+1]=RunService.Heartbeat:Connect(function() pcall(function() self:_tick() end) end) return self end
    function Trigger:Unload() if not self.Loaded then return end self.Loaded=false for _,c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end table.clear(self.Conns) end
    return Trigger end)()

--==================================================================
-- LOCAL VISUALS (chams body/arms/weapon + Fade)
--==================================================================
local LocalV = (function()
    local Players=game:GetService("Players") local RunService=game:GetService("RunService") local LocalPlayer=Players.LocalPlayer
    local COLORS={Red=Color3.fromRGB(255,60,60),Blue=Color3.fromRGB(70,120,255),Green=Color3.fromRGB(70,230,110),White=Color3.fromRGB(245,245,245),Purple=Color3.fromRGB(170,90,255),Cyan=Color3.fromRGB(70,230,240),Yellow=Color3.fromRGB(250,230,70),Black=Color3.fromRGB(15,15,18)}
    local L={Conns={},Loaded=false,Flags=nil,orig={},Settings={BodyChams=false,BodyForceVisible=false,BodyMaterial="Neon",BodyColor=COLORS.Red,BodyFade=false,ArmChams=false,ArmMaterial="Neon",ArmColor=COLORS.Blue,ArmFade=false,WeaponChams=false,WeaponMaterial="Neon",WeaponColor=COLORS.Purple,WeaponFade=true,FadeSpeed=0.4}}
    function L:_flag(k,d) if self.Flags then local v=self.Flags["Local_"..k] if v~=nil then return v end end local s=self.Settings[k] if s~=nil then return s end return d end
    function L:BindFlags(ft) self.Flags=ft end
    -- col = Color3 (from colorpicker) or a legacy string name; fade overrides with animated rainbow
    function L:_color(col,seed,fade) if fade then local h=((tick()*(self:_flag("FadeSpeed",4)*0.1))+(seed or 0))%1 return Color3.fromHSV(h,1,1) end if typeof(col)=="Color3" then return col end return COLORS[col] or COLORS.Red end
    local function matEnum(n) local ok,m=pcall(function() return Enum.Material[n] end) return ok and m or Enum.Material.Neon end
    --[[ POR QUE los chams "no cambiaban el material" (verificado live):
         - Brazos (viewmodel): LeftArm/RightArm son Part con un DECAL encima.
           El decal tapa la cara entera -> el material cambia pero no se ve.
         - Cuerpo: casi todos los MeshPart tienen TextureID (brazos, piernas,
           cabeza, Handle del accesorio) + Shirt/Pants. La textura gana.
         - Arma: MeshParts sin textura -> el material ya andaba.
         Fix: al aplicar chams se apaga lo que tapa (decal transp=1, TextureID="",
         ropa y accesorios ocultos) y se restaura TODO al desactivar.
         Ademas Rivals deja tu character en Transparency=1 (usa viewmodel), asi
         que el body chams necesita ForceVisible para verse. ]]
    function L:_apply(part,mat,col,cat,seed,fade)
        if not self.orig[part] then
            local o={Material=part.Material,Color=part.Color,category=cat}
            if part:IsA("MeshPart") then o.TextureID=part.TextureID end
            self.orig[part]=o
        end
        part.Material=matEnum(mat) part.Color=self:_color(col,seed,fade)
        -- MeshPart con textura: la textura pisa el material -> limpiarla
        if part:IsA("MeshPart") and part.TextureID~="" then pcall(function() part.TextureID="" end) end
    end
    -- ocultar/restaurar lo que tapa el material: decals, ropa, accesorios
    -- OJO: el juego REESCRIBE ShirtTexture.Transparency=0 continuamente (verificado:
    -- escribir 1 aguanta <0.5s y el Decal no se recrea, se lo reescribe). Por eso
    -- esto NO puede escribir una sola vez: impone cada frame, escribiendo solo si
    -- el valor difiere.
    function L:_hideCover(inst,cat)
        local o=self.orig[inst]
        if not o then
            if inst:IsA("Clothing") or inst:IsA("ShirtGraphic") then
                o={Parent=inst.Parent,category=cat,cover=true}
            elseif inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("BasePart") then
                o={Transparency=inst.Transparency,category=cat,cover=true}
            else return end
            self.orig[inst]=o
        end
        if o.Parent~=nil then
            if inst.Parent~=nil then pcall(function() inst.Parent=nil end) end
        elseif inst.Transparency~=1 then
            pcall(function() inst.Transparency=1 end)
        end
    end
    function L:_restore(part)
        local o=self.orig[part]
        if not o then return end
        pcall(function()
            if o.cover then
                if o.Parent~=nil then part.Parent=o.Parent else part.Transparency=o.Transparency end
            else
                part.Material=o.Material part.Color=o.Color
                if o.TextureID~=nil then part.TextureID=o.TextureID end
                if o.Transparency~=nil then part.Transparency=o.Transparency end
            end
        end)
        self.orig[part]=nil
    end
    function L:_restoreCategory(cat) for part,o in pairs(self.orig) do if o.category==cat then self:_restore(part) end end end
    function L:_update() if not self.Loaded then return end
        -- BODY: limpiar texturas + esconder ropa/accesorios; opcionalmente forzar visible
        if self:_flag("BodyChams",false) then local ch=LocalPlayer.Character if ch then
            local mat,col,fade=self:_flag("BodyMaterial","Neon"),self:_flag("BodyColor",COLORS.Red),self:_flag("BodyFade",false)
            local force=self:_flag("BodyForceVisible",false)
            local i=0
            for _,d in ipairs(ch:GetChildren()) do
                if d:IsA("MeshPart") and not d.Name:find("Hitbox") and d.Name~="FakeMass" then
                    i=i+1 self:_apply(d,mat,col,"body",i*0.06,fade)
                    if force then
                        local o=self.orig[d] if o and o.Transparency==nil then o.Transparency=d.Transparency end
                        if d.Transparency>0 then pcall(function() d.Transparency=0 end) end
                    end
                elseif d:IsA("Clothing") or d:IsA("ShirtGraphic") then self:_hideCover(d,"body")
                elseif d:IsA("Accessory") then
                    for _,h in ipairs(d:GetDescendants()) do
                        if h:IsA("BasePart") then self:_hideCover(h,"body")
                        elseif h:IsA("Decal") or h:IsA("Texture") then self:_hideCover(h,"body") end
                    end
                end
            end
            -- decal de la cara (DefaultHeadMesh)
            for _,d in ipairs(ch:GetDescendants()) do if d:IsA("Decal") and not self.orig[d] then self:_hideCover(d,"body") end end
        end else self:_restoreCategory("body") end
        local vm=workspace:FindFirstChild("ViewModels") local fp=vm and vm:FindFirstChild("FirstPerson")
        -- ARMS: el decal del brazo es LA razon por la que el material no se veia
        if self:_flag("ArmChams",false) and fp then
            local mat,col,fade=self:_flag("ArmMaterial","Neon"),self:_flag("ArmColor",COLORS.Blue),self:_flag("ArmFade",false)
            local i=0
            for _,d in ipairs(fp:GetDescendants()) do
                if d:IsA("BasePart") and d.Transparency<1 and (d.Name:find("Arm") or d.Name:find("Hand")) then
                    i=i+1 self:_apply(d,mat,col,"arm",i*0.15,fade)
                    for _,c in ipairs(d:GetChildren()) do
                        if c:IsA("Decal") or c:IsA("Texture") then self:_hideCover(c,"arm") end
                    end
                end
            end
        else self:_restoreCategory("arm") end
        if self:_flag("WeaponChams",false) and fp then
            local mat,col,fade=self:_flag("WeaponMaterial","Neon"),self:_flag("WeaponColor",COLORS.Purple),self:_flag("WeaponFade",true)
            local i=0
            for _,d in ipairs(fp:GetDescendants()) do
                if d:IsA("MeshPart") and d.Transparency<1 and not (d.Name:find("Arm") or d.Name:find("Hand")) then
                    i=i+1 self:_apply(d,mat,col,"weapon",i*0.04,fade)
                    for _,c in ipairs(d:GetChildren()) do
                        if c:IsA("Decal") or c:IsA("Texture") then self:_hideCover(c,"weapon") end
                    end
                end
            end
        else self:_restoreCategory("weapon") end
    end
    function L:Init() if self.Loaded then return self end self.Loaded=true self.Conns[#self.Conns+1]=RunService.RenderStepped:Connect(function() pcall(function() self:_update() end) end) return self end
    function L:Unload() if not self.Loaded then return end self.Loaded=false for _,c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end for part in pairs(self.orig) do self:_restore(part) end table.clear(self.orig) table.clear(self.Conns) end
    return L end)()


--==================================================================
-- HUD BASE (watermark + lista de keybinds)
--   Sin hooks: FPS por RenderStepped, ping real del IntValue que el
--   juego expone en workspace.ServerPing (no estimado).
--==================================================================
local HUDBase = (function()
    local RunService = game:GetService("RunService")
    local H = { Conns = {}, Loaded = false, Flags = nil, _frames = 0, _fps = 0, _last = 0,
        Settings = { Watermark = true, WatermarkX = 12, WatermarkY = 12, KeybindList = true, KeybindX = 12, KeybindY = 120,
                     WatermarkColor = Color3.fromRGB(235,235,240) } }
    function H:_flag(k, d) if self.Flags then local v = self.Flags["HUD_" .. k] if v ~= nil then return v end end local s = self.Settings[k] if s ~= nil then return s end return d end
    function H:BindFlags(ft) self.Flags = ft end
    -- OJO: workspace.ServerPing NO son ms (marcaba 963 con ping real de 101).
    -- La fuente correcta es Stats.Network.ServerStatsItem["Data Ping"].
    function H:_ping()
        local ok, v = pcall(function()
            return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
        end)
        return (ok and type(v) == "number") and v or -1
    end
    function H:_update(dt)
        -- FPS promediado en ventanas de 0.5s (no por frame = no titila)
        self._frames = self._frames + 1
        local now = tick()
        if now - self._last >= 0.5 then
            self._fps = math.floor(self._frames / (now - self._last) + 0.5)
            self._frames, self._last = 0, now
        end
        if self:_flag("Watermark", true) then
            if not self._wm then
                self._wm   = Library:Draw("Text", { Font = Library.Font, Size = Library.FontSize, Color = Library.Theme.Text })
                self._wmBg = Library:Draw("Square", { Filled = true, Color = Library.Theme.Background, Transparency = 0.75 })
                self._wmAc = Library:Draw("Square", { Filled = true, Color = Library.Theme.Accent })
            end
            local ping = self:_ping()
            local txt = string.format("RIVALS  |  %d fps  |  %s  |  %s",
                self._fps, (ping >= 0 and (ping .. " ms") or "-- ms"), os.date("%H:%M:%S"))
            self._wm.Text  = txt
            self._wm.Color = self:_flag("WatermarkColor", Library.Theme.Text)
            local x, y = self:_flag("WatermarkX", 12), self:_flag("WatermarkY", 12)
            local w, h = self._wm.TextBounds.X + 12, Library.FontSize + 8
            self._wmBg.Position = Vector2.new(x, y); self._wmBg.Size = Vector2.new(w, h); self._wmBg.ZIndex = 90; self._wmBg.Visible = true
            self._wmAc.Position = Vector2.new(x, y); self._wmAc.Size = Vector2.new(w, 2);  self._wmAc.ZIndex = 92; self._wmAc.Visible = true
            self._wm.Position   = Vector2.new(x + 6, y + 4); self._wm.ZIndex = 91; self._wm.Visible = true
        elseif self._wm then
            self._wm.Visible, self._wmBg.Visible, self._wmAc.Visible = false, false, false
        end
        Library:KeybindList({
            Enabled = self:_flag("KeybindList", true),
            X = self:_flag("KeybindX", 12),
            Y = self:_flag("KeybindY", 120),
        })
    end
    function H:Init()
        if self.Loaded then return self end
        self.Loaded = true; self._last = tick()
        self.Conns[#self.Conns+1] = RunService.RenderStepped:Connect(function(dt) pcall(function() self:_update(dt) end) end)
        return self
    end
    function H:Unload()
        if not self.Loaded then return end
        self.Loaded = false
        for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
        table.clear(self.Conns)
        pcall(function() Library:KeybindList({ Enabled = false }) end)
        for _, o in ipairs({ self._wm, self._wmBg, self._wmAc }) do if o then pcall(function() o.Visible = false end) end end
    end
    return H
end)()

--==================================================================
-- SHOWCASE: arma random girando en el menu
--   El catalogo del juego (49 armas) esta en
--   PlayerScripts.Assets.ViewModels.Weapons. La lib solo sabe dibujar
--   wireframes; quien elige el modelo es esto.
--==================================================================
local Showcase = (function()
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local S = { _pool = nil, _last = nil }
    function S:_weapons()
        if self._pool then return self._pool end
        local ok, folder = pcall(function()
            return LocalPlayer.PlayerScripts.Assets.ViewModels:FindFirstChild("Weapons")
        end)
        if not ok or not folder then return nil end
        local list = {}
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") then list[#list + 1] = m end
        end
        self._pool = #list > 0 and list or nil
        return self._pool
    end
    -- arma nueva en cada apertura (evita repetir la anterior si hay de donde)
    function S:Pick()
        local pool = self:_weapons()
        if not pool then return end
        local pick = pool[math.random(1, #pool)]
        if #pool > 1 and pick == self._last then
            pick = pool[(table.find(pool, pick) % #pool) + 1]
        end
        self._last = pick
        Library:ShowcaseFromModel(pick, pick.Name)
    end
    return S
end)()

--==================================================================
-- CONFIG (save / load / autoload)
--==================================================================
-- Color3 is userdata -> JSONEncode chokes. Serialize picker colors as {__c3,R,G,B}.
-- flags que NUNCA se guardan (evita que rage/void se auto-activen al cargar = peligroso)
-- Modules_AdvAuto vive en RivalsMenu_modules.json, no en la config (fuente unica)
local NO_SAVE = { Rage_Enabled = true, Rage_VoidSpam = true, Modules_AdvAuto = true,
                  Config_Profile = true, Config_Name = true }
local function serFlags()
    local t = {}
    for k, v in pairs(Library.Flags) do
        if NO_SAVE[k] then
            -- omitir
        elseif typeof(v) == "Color3" then
            t[k] = { __c3 = true, R = math.floor(v.R * 255 + 0.5), G = math.floor(v.G * 255 + 0.5), B = math.floor(v.B * 255 + 0.5) }
        else
            t[k] = v
        end
    end
    return t
end
--[[ Configs con nombre, cada una su archivo dentro de RivalsConfigs/.
     La lista sale de listfiles() sobre la carpeta: es la fuente de verdad
     real (si borras un archivo a mano, el dropdown se entera). ]]
local function cleanName(n)
    n = tostring(n or ""):gsub("[^%w_%- ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return n
end
local function ensureDir()
    pcall(function() if makefolder and isfolder and not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end end)
end
ensureDir()
local function profilePath(name) return CONFIG_DIR .. "/" .. cleanName(name) .. ".json" end
local function listProfiles()
    local out = {}
    local ok = pcall(function()
        for _, f in ipairs(listfiles(CONFIG_DIR)) do
            local base = tostring(f):match("([^/\\]+)%.json$")
            if base then out[#out + 1] = base end
        end
    end)
    if not ok then return { "default" } end
    table.sort(out)
    if #out == 0 then out[1] = "default" end
    return out
end
local function saveConfig(name)
    ensureDir()
    local ok = pcall(function() writefile(profilePath(name), HttpService:JSONEncode(serFlags())) end)
    return ok
end
local function readConfig(name)
    local path = profilePath(name)
    if not (isfile and isfile(path)) then return nil end
    local ok, t = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    return ok and t or nil
end
-- migrar la config vieja de la raiz a la carpeta (una vez)
do
    ensureDir()
    if isfile and isfile(CONFIG_PATH) and not (isfile(profilePath("default"))) then
        pcall(function() writefile(profilePath("default"), readfile(CONFIG_PATH)) end)
    end
end
local Profiles = listProfiles()

-- Una config "usa rage" si trae flags del modulo avanzado con algo activado.
-- Solo mirar que existan no sirve: cualquier config guardada con el modulo
-- cargado los trae en false.
local function configUsesRage(t)
    if type(t) ~= "table" then return false end
    local hits = {}
    for k, v in pairs(t) do
        if type(k) == "string" and k:sub(1, 5) == "Rage_" then
            local on = (v == true) or (type(v) == "number" and v ~= 0 and k:find("Void") ~= nil)
            if on then hits[#hits + 1] = k:sub(6) end
        end
    end
    return #hits > 0, hits
end
local function applyConfig(t)
    if not t then return false end
    for k, v in pairs(t) do
        local cur = Library.Flags[k]
        if cur ~= nil then
            if typeof(cur) == "Color3" then
                -- colorpicker flag: only accept a serialized Color3, ignore legacy string values
                if type(v) == "table" and v.__c3 then
                    Library.Flags[k] = Color3.fromRGB(v.R or 255, v.G or 255, v.B or 255)
                end
            elseif type(v) == "table" and v.__c3 then
                Library.Flags[k] = Color3.fromRGB(v.R or 255, v.G or 255, v.B or 255)
            else
                Library.Flags[k] = v
            end
        end
    end
    for _, w in ipairs(Library.Windows) do w:Refresh() end
    return true
end

--==================================================================
-- WIRING
--==================================================================
ESP:BindFlags(Library.Flags)     ESP:Init()
Aim:BindFlags(Library.Flags)     Aim:Init()
Trigger:BindFlags(Library.Flags) Trigger:Init()
LocalV:BindFlags(Library.Flags)  LocalV:Init()
HUDBase:BindFlags(Library.Flags) HUDBase:Init()

local MATS = { "Neon", "ForceField", "Glass", "SmoothPlastic", "Plastic", "DiamondPlate", "Foil", "Wood", "Ice", "Metal", "Marble" }

local Window = Library:CreateWindow({ Title = "RIVALS  |  1.0", Size = Vector2.new(600, 580), Position = Vector2.new(150, 110) })

-- VISUALS
local Visuals = Window:AddTab("Visuals")
local eb = Visuals:AddLeftGroupbox("ESP")
local en = eb:AddToggle("ESP_Enabled", { Text = "Enable ESP", Default = true, Keybind = true })
en:AddToggle("ESP_Box",         { Text = "Box",            Default = true })
en:AddToggle("ESP_Name",        { Text = "Nombre",         Default = true })
en:AddToggle("ESP_Health",      { Text = "Barra vida",     Default = true })
en:AddToggle("ESP_Distance",    { Text = "Distancia",      Default = true })
en:AddToggle("ESP_Tracer",      { Text = "Tracers",        Default = false })
en:AddToggle("ESP_PlayersOnly", { Text = "Solo jugadores", Default = false })
en:AddSlider("ESP_MaxDistance", { Text = "Alcance", Min = 100, Max = 2000, Default = 1200, Suffix = "m" })
en:AddDropdown("ESP_TracerOrigin", { Text = "Tracer: origen", Values = { "Abajo", "Centro pantalla", "Arriba", "Mouse", "Punta del arma" }, Default = "Abajo" })
en:AddDropdown("ESP_TracerEnd",    { Text = "Tracer: punta",  Values = { "Pies", "HRP", "Cabeza" }, Default = "Pies" })
en:AddToggle("ESP_ArenaOnly", { Text = "Solo mi arena", Default = true })
en:AddToggle("ESP_Skeleton",  { Text = "Esqueleto", Default = false })
en:AddToggle("ESP_ShowLevel", { Text = "Nivel", Default = false })
en:AddToggle("ESP_ShowWeapon",{ Text = "Arma equipada", Default = false })

local ei = Visuals:AddLeftGroupbox("ESP: colores")
ei:AddLabel("Team manda sobre visibilidad")
local tc = ei:AddToggle("ESP_TeamColors", { Text = "Color por team", Default = false })
tc:AddColorPicker("ESP_EnemyColor", { Text = "Enemigo", Default = Color3.fromRGB(255, 80, 80) })
tc:AddColorPicker("ESP_AllyColor",  { Text = "Aliado",  Default = Color3.fromRGB(90, 190, 255) })
local vc = ei:AddToggle("ESP_VisCheck", { Text = "Color por visibilidad", Default = false })
vc:AddColorPicker("ESP_VisibleColor", { Text = "Visible", Default = Color3.fromRGB(120, 240, 120) })
vc:AddColorPicker("ESP_HiddenColor",  { Text = "Tapado",  Default = Color3.fromRGB(240, 120, 120) })
local ar = ei:AddToggle("ESP_Arrows", { Text = "Flechas (fuera de pantalla)", Default = false })
ar:AddSlider("ESP_ArrowRadius", { Text = "Radio", Min = 60, Max = 500, Default = 200, Suffix = "px" })
ar:AddSlider("ESP_ArrowSize",   { Text = "Tamano", Min = 6, Max = 40, Default = 16 })
ar:AddColorPicker("ESP_ArrowColor", { Text = "Color", Default = Color3.fromRGB(255, 200, 60) })
local it = ei:AddToggle("ESP_Items", { Text = "Granadas y trampas", Default = false, Keybind = true })
it:AddLabel("Throwables + proyectiles + tripmines")
it:AddSlider("ESP_ItemDistance", { Text = "Alcance", Min = 50, Max = 1500, Default = 400, Suffix = "m" })
it:AddColorPicker("ESP_ItemColor", { Text = "Color", Default = Color3.fromRGB(255, 170, 60) })
local ec = ei:AddToggle("ESP_Chams", { Text = "Chams enemigos", Default = false })
ec:AddLabel("Sin instancias: NO atraviesa paredes")
ec:AddDropdown("ESP_ChamsMaterial", { Text = "Material", Values = MATS, Default = "Neon" })
ec:AddColorPicker("ESP_ChamsColor", { Text = "Color", Default = Color3.fromRGB(255, 60, 200) })

local hb = Visuals:AddRightGroupbox("HUD")
local wm = hb:AddToggle("HUD_Watermark", { Text = "Watermark (fps/ping/hora)", Default = true })
wm:AddSlider("HUD_WatermarkX", { Text = "Pos X", Min = 0, Max = 1920, Default = 12 })
wm:AddSlider("HUD_WatermarkY", { Text = "Pos Y", Min = 0, Max = 1080, Default = 12 })
wm:AddColorPicker("HUD_WatermarkColor", { Text = "Color", Default = Color3.fromRGB(235, 235, 240) })
local kl = hb:AddToggle("HUD_KeybindList", { Text = "Lista de keybinds", Default = true })
kl:AddSlider("HUD_KeybindX", { Text = "Pos X", Min = 0, Max = 1920, Default = 12 })
kl:AddSlider("HUD_KeybindY", { Text = "Pos Y", Min = 0, Max = 1080, Default = 120 })
hb:AddLabel("Click en la tecla = bindear")
hb:AddLabel("Click derecho = Toggle/Hold/Always")

-- COMBAT
local Combat = Window:AddTab("Combat")
local ab = Combat:AddLeftGroupbox("Aimbot")
local aen = ab:AddToggle("Aim_Enabled", { Text = "Enable Aimbot", Default = false, Keybind = true })
aen:AddDropdown("Aim_Method",     { Text = "Método",     Values = { "Mouse", "Camera" }, Default = "Mouse" })
aen:AddDropdown("Aim_Activation", { Text = "Activación", Values = { "Hold Right Click", "Hold Left Click", "Always" }, Default = "Hold Right Click" })
aen:AddDropdown("Aim_TargetPart", { Text = "Parte",      Values = { "Head", "Body" }, Default = "Head" })
aen:AddSlider("Aim_FOV",          { Text = "FOV",     Min = 10,  Max = 600,  Default = 120, Suffix = "px" })
aen:AddSlider("Aim_Smoothness",   { Text = "Smooth",  Min = 1,   Max = 30,   Default = 6 })
aen:AddSlider("Aim_MaxDistance",  { Text = "Alcance", Min = 100, Max = 2000, Default = 1000, Suffix = "m" })
aen:AddToggle("Aim_VisibleCheck", { Text = "Solo visibles", Default = false })
aen:AddToggle("Aim_ShowFOV",      { Text = "Mostrar FOV",   Default = true })

local tb = Combat:AddRightGroupbox("Triggerbot")
local ten = tb:AddToggle("Trig_Enabled", { Text = "Enable Trigger", Default = false, Keybind = true })
ten:AddDropdown("Trig_Activation", { Text = "Activación", Values = { "Hold Middle Click", "Hold Right Click", "Always" }, Default = "Hold Middle Click" })
ten:AddToggle("Trig_HeadOnly",     { Text = "Solo cabeza", Default = false })
ten:AddSlider("Trig_Delay",        { Text = "Delay",  Min = 0, Max = 300, Default = 30,  Suffix = "ms" })
ten:AddSlider("Trig_Refire",       { Text = "Refire", Min = 0, Max = 500, Default = 120, Suffix = "ms" })
ten:AddSlider("Trig_MaxDistance",  { Text = "Alcance", Min = 100, Max = 2000, Default = 1000, Suffix = "m" })

-- LOCAL (chams) -> viven en el tab Visuals (son visuales del personaje)
local Locals = Visuals
local bch = Locals:AddLeftGroupbox("Body")
local ben = bch:AddToggle("Local_BodyChams", { Text = "Body chams", Default = false })
bch:AddLabel("Rivals te esconde el cuerpo (usa viewmodel)")
ben:AddToggle("Local_BodyForceVisible", { Text = "Forzar visible (si no, no se ve)", Default = false })
ben:AddDropdown("Local_BodyMaterial", { Text = "Material", Values = MATS, Default = "Neon" })
ben:AddColorPicker("Local_BodyColor", { Text = "Color", Default = Color3.fromRGB(255, 60, 60) })
ben:AddToggle("Local_BodyFade",       { Text = "Fade (rainbow)", Default = false })

local ach = Locals:AddLeftGroupbox("Arms")
local aench = ach:AddToggle("Local_ArmChams", { Text = "Arm chams", Default = false })
aench:AddDropdown("Local_ArmMaterial", { Text = "Material", Values = MATS, Default = "Neon" })
aench:AddColorPicker("Local_ArmColor", { Text = "Color", Default = Color3.fromRGB(70, 120, 255) })
aench:AddToggle("Local_ArmFade",       { Text = "Fade (rainbow)", Default = false })

local wch = Locals:AddRightGroupbox("Weapon")
local wench = wch:AddToggle("Local_WeaponChams", { Text = "Weapon chams", Default = false })
wench:AddDropdown("Local_WeaponMaterial", { Text = "Material", Values = MATS, Default = "Neon" })
wench:AddColorPicker("Local_WeaponColor", { Text = "Color", Default = Color3.fromRGB(170, 90, 255) })
wench:AddToggle("Local_WeaponFade",       { Text = "Fade (rainbow)", Default = true })

local fx = Locals:AddRightGroupbox("Fade")
fx:AddLabel("Fade = rainbow animado (toggle por parte)")
fx:AddSlider("Local_FadeSpeed", { Text = "Velocidad Fade", Min = 1, Max = 30, Default = 4, Decimals = 0 })

-- SETTINGS / CONFIG
local Settings = Window:AddTab("Settings")
local cfg = Settings:AddLeftGroupbox("Config")
cfg:AddToggle("Config_Autoload", { Text = "Autoload al iniciar", Default = true })
cfg:AddLabel("Carpeta: " .. CONFIG_DIR .. "/")
local profDD = cfg:AddDropdown("Config_Profile", { Text = "Config", Values = Profiles, Default = Profiles[1] })
local nameIn = cfg:AddInput("Config_Name", { Text = "Nombre", Placeholder = "escribi y Enter", MaxLen = 24 })
local function refreshProfiles(pick)
    Profiles = listProfiles()
    profDD:SetValues(Profiles, true)
    if pick then profDD:Set(pick) end
end
local function saveAs(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    saveConfig(name)
    refreshProfiles(name)
    nameIn:Set("")
end
nameIn.Finished = function(v) saveAs(v) end
cfg:AddButton("Guardar como (nombre)", function() saveAs(Library.Flags.Config_Name) end)
cfg:AddButton("Guardar en la actual", function() saveConfig(Library.Flags.Config_Profile) end)
-- Cargar avisa si la config trae rage activo (hooks) antes de aplicarla
cfg:AddButton("Cargar", function()
    local name = Library.Flags.Config_Profile
    local t = readConfig(name)
    if not t then return end
    local usa, hits = configUsesRage(t)
    if not usa then applyConfig(t) return end
    local lines = {
        { Text = "\"" .. tostring(name) .. "\" trae features de RAGE activas:", Color = Library.Theme.Text },
        "",
    }
    for i, h in ipairs(hits) do
        if i > 8 then lines[#lines + 1] = "  ... y " .. (#hits - 8) .. " mas" break end
        lines[#lines + 1] = { Text = "  " .. h, Color = Color3.fromRGB(255, 95, 95) }
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = { Text = "El modulo Rage usa hooks y es detectable.", Color = Color3.fromRGB(255, 95, 95) }
    lines[#lines + 1] = "Cargar la config NO carga el modulo: si no esta"
    lines[#lines + 1] = "cargado, esos flags se ignoran."
    Library:Prompt({
        Title = "Config con features de Rage",
        Lines = lines,
        Buttons = {
            { Text = "Cargar igual", Accent = true, Callback = function() applyConfig(t) end },
            { Text = "Cancelar" },
        },
    })
end)
cfg:AddButton("Borrar config", function()
    local cur = Library.Flags.Config_Profile
    pcall(function() if delfile and isfile(profilePath(cur)) then delfile(profilePath(cur)) end end)
    refreshProfiles()
    profDD:Set(Profiles[1])
end)

-- ---------- tema del menu ----------
local th = Settings:AddRightGroupbox("Tema")
local THEME_KEYS = {
    { "Accent", "Acento" }, { "Background", "Fondo" }, { "Header", "Cabecera" },
    { "Section", "Seccion" }, { "Element", "Elemento" }, { "Outline", "Borde" },
    { "Text", "Texto" }, { "DimText", "Texto tenue" },
}
for _, e in ipairs(THEME_KEYS) do
    local key, label = e[1], e[2]
    th:AddColorPicker("Theme_" .. key, { Text = label, Default = Library.Theme[key], Callback = function(c)
        Library:SetTheme(key, c)
    end })
end
th:AddDropdown("Theme_Font", { Text = "Fuente", Values = { "UI", "System", "Plain", "Monospace" }, Default = "Plain", Callback = function(v)
    local map = { UI = 0, System = 1, Plain = 2, Monospace = 3 }
    Library:SetFont(map[v] or 2)
end })
local mn = Settings:AddRightGroupbox("Menu")
mn:AddLabel("RightShift = toggle menu")
local sc = mn:AddToggle("Menu_Showcase", { Text = "Arma 3D girando", Default = false, Callback = function(v)
    Library.ShowcaseOn = v
    if v then Showcase:Pick() else Library:_hideShowcase(); Library:_killShowcaseGui() end
end })
sc:AddDropdown("Menu_ShowcaseMode", { Text = "Modo", Values = { "Solido", "Wireframe" }, Default = "Solido", Callback = function(v)
    Library.ShowcaseMode = v
    if v == "Wireframe" then Library:_killShowcaseGui() end   -- soltar las instancias
    Showcase:Pick()
end })
sc:AddLabel("Solido = ViewportFrame (mete instancias)")
sc:AddLabel("Wireframe = Drawing (0 instancias)")
sc:AddSlider("Menu_ShowcaseSpeed", { Text = "Velocidad", Min = 0, Max = 4, Default = 0.6, Decimals = 2, Callback = function(v) Library.ShowcaseSpeed = v end })
sc:AddSlider("Menu_ShowcaseSize",  { Text = "Tamano", Min = 120, Max = 700, Default = 360, Callback = function(v) Library.ShowcaseSize = v end })
sc:AddSlider("Menu_ShowcaseDim",   { Text = "Oscurecer juego", Min = 0, Max = 1, Default = 0.75, Decimals = 2, Callback = function(v) Library.ShowcaseDim = v end })
sc:AddColorPicker("Menu_ShowcaseColor", { Text = "Color (wireframe)", Default = Color3.fromRGB(96, 130, 255), Callback = function(c) Library.ShowcaseColor = c end })

-- al abrir el menu: arma nueva
Library.OnOpen = function() if Library.ShowcaseOn then Showcase:Pick() end end

getgenv().RivalsMenu = { Library = Library, ESP = ESP, Aim = Aim, Trigger = Trigger, Local = LocalV, HUD = HUDBase }

--==================================================================
-- MODULOS EXTERNOS  (carga bajo demanda desde GitHub)
--   El script base NO contiene ni una linea del modulo avanzado:
--   sin hooks, sin identidad de thread, sin propiedades ocultas.
--   Se baja y ejecuta solo si el usuario lo pide (o si dejo el
--   autoload guardado en la workspace).
--==================================================================
local function fnExists(name)
    local ok, f = pcall(function()
        local g = (getgenv and getgenv()[name])
        if g ~= nil then return g end
        local env = (getfenv and getfenv()) or _G
        return rawget(env, name) or env[name] or _G[name]
    end)
    return ok and type(f) == "function"
end
local function anyFn(names)
    for _, n in ipairs(names) do if fnExists(n) then return true end end
    return false
end

-- requisitos reales del modulo avanzado (lo que rompe en ejecutores flojos)
local REQS = {
    { label = "hookmetamethod",    names = { "hookmetamethod" },                          why = "spoof de posicion" },
    { label = "checkcaller",       names = { "checkcaller" },                             why = "spoof de posicion" },
    { label = "getgenv",           names = { "getgenv" },                                 why = "hook global unico" },
    { label = "setthreadidentity", names = { "setthreadidentity", "setidentity" },        why = "disparo interno" },
    { label = "sethiddenproperty", names = { "sethiddenproperty" },                       why = "weld al enemigo" },
}
local function missingReqs()
    local miss = {}
    for _, r in ipairs(REQS) do
        if not anyFn(r.names) then miss[#miss + 1] = r end
    end
    return miss
end

local VIS_URL   = "https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/RivalsVisuals.lua"
local CBT_URL   = "https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/RivalsCombat.lua"
local MODS_PATH = "RivalsMenu_modules.json"
local MOD_URL   = "https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/RivalsRage.lua"
local function readMods()
    if not (isfile and isfile(MODS_PATH)) then return {} end
    local ok, t = pcall(function() return HttpService:JSONDecode(readfile(MODS_PATH)) end)
    return (ok and type(t) == "table") and t or {}
end
local Mods = readMods()
local function writeMods()
    pcall(function() writefile(MODS_PATH, HttpService:JSONEncode(Mods)) end)
end

local Adv   -- modulo cargado (nil = script 100% limpio)
local function loadAdvanced()
    if Adv then return true end
    local ok, src = pcall(function() return game:HttpGet(MOD_URL) end)
    if not ok or type(src) ~= "string" or #src < 200 then
        Library:Prompt({ Title = "Error de descarga", Lines = { "No se pudo bajar el modulo:", tostring(src):sub(1, 90) } })
        return false
    end
    local chunk, cerr = loadstring(src)
    if not chunk then
        Library:Prompt({ Title = "Error de compilacion", Lines = { tostring(cerr):sub(1, 90) } })
        return false
    end
    local ok2, mod = pcall(chunk)
    if not ok2 or type(mod) ~= "table" then
        Library:Prompt({ Title = "Error de ejecucion", Lines = { tostring(mod):sub(1, 90) } })
        return false
    end
    Adv = mod
    pcall(function() mod:BindFlags(Library.Flags) end)
    pcall(function() mod:BuildUI(Library, Window) end)
    pcall(function() mod:Init() end)
    applyConfig(readConfig())          -- restaurar los ajustes del modulo (si habia config)
    Library.Flags.Rage_Enabled  = false   -- NO_SAVE igual, pero por si acaso
    Library.Flags.Rage_VoidSpam = false
    getgenv().RivalsMenu.Rage = Adv
    for _, w in ipairs(Library.Windows) do w:Refresh() end
    return true
end

local function advWarning()
    if Adv then
        Library:Prompt({ Title = "Modulo avanzado", Lines = { "Ya esta cargado. Tab 'Rage'." } })
        return
    end
    local exec = "desconocido"
    pcall(function() if identifyexecutor then exec = tostring(identifyexecutor()) end end)

    local RED   = Color3.fromRGB(255, 95, 95)
    local WHITE = Library.Theme.Text
    local GREEN = Color3.fromRGB(120, 230, 120)

    local L = {
        { Text = "Este modulo NO es seguro. Usa hooks y funciones", Color = WHITE },
        { Text = "de bajo nivel que el juego puede detectar:",      Color = WHITE },
        "",
        "  hookmetamethod(game, \"__index\")   -  spoof de posicion",
        "  setthreadidentity(2)              -  disparo interno",
        "  sethiddenproperty(PhysicsRep...)  -  weld al enemigo",
        "",
        { Text = "DETECCION", Color = RED },
        "  Los hooks son rastreables desde el cliente. El AC de",
        "  Rivals banea movement cheats. Usar SOLO en VIP / alt.",
        "",
        { Text = "COMPATIBILIDAD", Color = RED },
        "  Ejecutores de gama baja (Solara, Xeno, Luna) no",
        "  implementan estas funciones: crashea o no hace nada.",
        "",
        { Text = "Ejecutor detectado: " .. exec, Color = WHITE },
    }
    local miss = missingReqs()
    if #miss == 0 then
        L[#L + 1] = { Text = "Todas las funciones requeridas estan presentes.", Color = GREEN }
    else
        L[#L + 1] = { Text = "FALTAN funciones en tu ejecutor:", Color = RED }
        for _, r in ipairs(miss) do
            L[#L + 1] = { Text = "  " .. r.label .. "  ->  " .. r.why, Color = RED }
        end
        L[#L + 1] = { Text = "Cargar igual = features rotas o crash.", Color = RED }
    end

    Library:Prompt({
        Title   = "AVISO  -  modulo avanzado (Rage)",
        Lines   = L,
        Buttons = {
            { Text = "Cargar ahora",       Accent = true, Callback = function() loadAdvanced() end },
            { Text = "Cargar siempre",     Callback = function()
                Mods.AdvAuto, Mods.AdvSkipWarn = true, true
                writeMods()
                Library.Flags.Modules_AdvAuto = true
                loadAdvanced()
            end },
            { Text = "Cancelar" },
        },
    })
end

local md = Settings:AddRightGroupbox("Modulos")
md:AddLabel("Base = limpio (sin hooks).")
md:AddButton("Cargar modulo avanzado", advWarning)
md:AddToggle("Modules_AdvAuto", {
    Text = "Cargar al ejecutar (guardado)",
    Default = Mods.AdvAuto == true,
    Callback = function(v)
        Mods.AdvAuto = v or nil
        if not v then Mods.AdvSkipWarn = nil end
        writeMods()
        if v and not Adv then loadAdvanced() end
    end,
})
md:AddButton("Cargar siempre sin avisos", function()
    Mods.AdvAuto, Mods.AdvSkipWarn = true, true
    writeMods()
    Library.Flags.Modules_AdvAuto = true
    for _, w in ipairs(Library.Windows) do w:Refresh() end
    if not Adv then loadAdvanced() end
end)
md:AddButton("Olvidar autocarga", function()
    Mods = {}
    writeMods()
    Library.Flags.Modules_AdvAuto = false
    for _, w in ipairs(Library.Windows) do w:Refresh() end
end)

mn:AddButton("Unload todo", function()
    if Adv then pcall(function() Adv:Unload() end) end
    -- OJO: leer del export, NO de un local (el modulo visual se carga mas abajo
    -- en el archivo -> un `local Vis` aca seria global nil dentro de este closure)
    local m = getgenv().RivalsMenu
    for _, k in ipairs({ "Rage", "Visuals", "Combat" }) do
        if m and m[k] then pcall(function() m[k]:Unload() end) end
    end
    HUDBase:Unload() Trigger:Unload() LocalV:Unload() Aim:Unload() ESP:Unload() Library:Unload()
end)

-- VISUALES: modulo legit (sin hooks) -> carga siempre, sin gate ni aviso.
local Vis
do
    local ok, src = pcall(function() return game:HttpGet(VIS_URL) end)
    if ok and type(src) == "string" and #src > 200 then
        local chunk = loadstring(src)
        local ok2, mod = pcall(chunk)
        if ok2 and type(mod) == "table" then
            Vis = mod
            pcall(function() Vis:BindFlags(Library.Flags) end)
            pcall(function() Vis:BuildUI(Library, Window) end)
            pcall(function() Vis:Init() end)
            getgenv().RivalsMenu.Visuals = Vis
        else
            warn("[RivalsMain] modulo visual no ejecuto: " .. tostring(mod))
        end
    else
        warn("[RivalsMain] modulo visual no descargo: " .. tostring(src))
    end
end

-- COMBAT: modulo legit (API del juego, sin hooks) -> carga siempre.
local Cbt
do
    local ok, src = pcall(function() return game:HttpGet(CBT_URL) end)
    if ok and type(src) == "string" and #src > 200 then
        local chunk = loadstring(src)
        local ok2, mod = pcall(chunk)
        if ok2 and type(mod) == "table" then
            Cbt = mod
            pcall(function() Cbt:BindFlags(Library.Flags) end)
            pcall(function() Cbt:BuildUI(Library, Window) end)
            pcall(function() Cbt:Init() end)
            getgenv().RivalsMenu.Combat = Cbt
        else
            warn("[RivalsMain] modulo combat no ejecuto: " .. tostring(mod))
        end
    else
        warn("[RivalsMain] modulo combat no descargo: " .. tostring(src))
    end
end

-- AUTOLOAD: si hay config guardada con autoload on, aplicarla
do
    local t = readConfig("default") or readConfig(Profiles[1])
    if t and t.Config_Autoload ~= false then applyConfig(t) end
end

-- AUTOCARGA del modulo avanzado segun lo guardado en la workspace
if Mods.AdvAuto then
    if Mods.AdvSkipWarn then loadAdvanced() else advWarning() end
end

print("[Rivals] 1.0 cargado. RightShift = menu.")
return getgenv().RivalsMenu