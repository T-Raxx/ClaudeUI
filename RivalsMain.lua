--[[
    RivalsMain  -  script principal self-contained.
    Carga la UI lib desde GitHub (HttpGet) + ESP + Aimbot inline + menú.
    Un solo archivo: loadstring(game:HttpGet("<raw de este archivo>"))()
    RightShift = toggle menu.
------------------------------------------------------------------ ]]

local UI_URL = "https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/RivalsUI.lua"

-- unload build previo si re-ejecutas
if getgenv().RivalsMenu then
    pcall(function()
        local m = getgenv().RivalsMenu
        if m.Aim then m.Aim:Unload() end
        if m.ESP then m.ESP:Unload() end
        if m.Library then m.Library:Unload() end
    end)
    getgenv().RivalsMenu = nil
end

local Library = loadstring(game:HttpGet(UI_URL))()

--==================================================================
-- ESP  (Drawing, client-only)
--==================================================================
local ESP = (function()
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local CollectionService = game:GetService("CollectionService")
    local LocalPlayer       = Players.LocalPlayer

    local ESP = { Drawings={}, Objects={}, Conns={}, Loaded=false, Flags=nil,
        Settings={ Enabled=true, Box=true, Name=true, Health=true, Distance=true, Tracer=false, PlayersOnly=false, MaxDistance=1200,
            BoxColor=Color3.fromRGB(235,235,240), NameColor=Color3.fromRGB(235,235,240), TracerColor=Color3.fromRGB(96,130,255), Font=2, TextSize=13 } }

    function ESP:_flag(k,d) if self.Flags then local v=self.Flags["ESP_"..k] if v~=nil then return v end end local s=self.Settings[k] if s~=nil then return s end return d end
    function ESP:_draw(c,p) local o=Drawing.new(c) o.Visible=false if p then for k,v in pairs(p) do o[k]=v end end table.insert(self.Drawings,o) return o end
    function ESP:BindFlags(ft) self.Flags=ft end
    function ESP:_make() local S=self.Settings return {
        box=self:_draw("Square",{Filled=false,Thickness=1,Color=S.BoxColor}), boxOl=self:_draw("Square",{Filled=false,Thickness=3,Color=Color3.new(0,0,0)}),
        name=self:_draw("Text",{Font=S.Font,Size=S.TextSize,Center=true,Outline=true,Color=S.NameColor}), dist=self:_draw("Text",{Font=S.Font,Size=S.TextSize,Center=true,Outline=true,Color=Color3.fromRGB(180,180,185)}),
        hpBg=self:_draw("Square",{Filled=true,Color=Color3.new(0,0,0)}), hpBar=self:_draw("Square",{Filled=true,Color=Color3.fromRGB(90,220,90)}), tracer=self:_draw("Line",{Thickness=1,Color=S.TracerColor}) } end
    local function hide(b) for _,o in pairs(b) do o.Visible=false end end
    local function resolveEntity(model) if not model:IsA("Model") then return end local hum=model:FindFirstChildOfClass("Humanoid") if not hum or hum.Health<=0 then return end local root=model:FindFirstChild("HumanoidRootPart") local head=model:FindFirstChild("Head") if not root or not head then return end return hum,root,head end
    function ESP:_hc(f) return Color3.fromRGB(math.floor(220*(1-f))+20,math.floor(200*f)+20,40) end
    function ESP:_update()
        if not self.Loaded then return end
        local enabled=self:_flag("Enabled",true) local C=workspace.CurrentCamera local myChar=LocalPlayer.Character local origin=C.CFrame.Position
        local live={} if enabled then local po=self:_flag("PlayersOnly",false) local cs if po then cs={} for _,p in ipairs(Players:GetPlayers()) do if p.Character then cs[p.Character]=true end end end
            for _,m in ipairs(CollectionService:GetTagged("Entity")) do if m~=myChar and (not cs or cs[m]) then live[m]=true end end end
        for model,b in pairs(self.Objects) do if not live[model] or not model.Parent then hide(b) if not model.Parent then self.Objects[model]=nil end end end
        if not enabled then return end
        local sBox=self:_flag("Box",true) local sName=self:_flag("Name",true) local sHp=self:_flag("Health",true) local sDist=self:_flag("Distance",true) local sTr=self:_flag("Tracer",false) local maxD=self:_flag("MaxDistance",1200) local vpY=C.ViewportSize.Y
        for model in pairs(live) do local hum,root,head=resolveEntity(model) local b=self.Objects[model]
            if not hum then if b then hide(b) end else local dist=(root.Position-origin).Magnitude
                if dist>maxD then if b then hide(b) end else if not b then b=self:_make() self.Objects[model]=b end
                    local tV=C:WorldToViewportPoint(head.Position+Vector3.new(0,0.6,0)) local bV=C:WorldToViewportPoint(root.Position-Vector3.new(0,3,0))
                    if tV.Z<=0 and bV.Z<=0 then hide(b) else local top=Vector2.new(tV.X,tV.Y) local bot=Vector2.new(bV.X,bV.Y) local h=math.abs(bot.Y-top.Y) local w=h*0.62 local x=top.X-w/2 local y=top.Y
                        b.box.Visible,b.boxOl.Visible=sBox,sBox if sBox then b.box.Size=Vector2.new(w,h) b.box.Position=Vector2.new(x,y) b.box.ZIndex=2 b.boxOl.Size=b.box.Size b.boxOl.Position=b.box.Position b.boxOl.ZIndex=1 end
                        local frac=math.clamp(hum.Health/(hum.MaxHealth>0 and hum.MaxHealth or 100),0,1) b.hpBg.Visible,b.hpBar.Visible=sHp,sHp if sHp then local bx=x-5 b.hpBg.Position=Vector2.new(bx,y-1) b.hpBg.Size=Vector2.new(3,h+2) b.hpBg.ZIndex=2 local bh=h*frac b.hpBar.Position=Vector2.new(bx,y+(h-bh)) b.hpBar.Size=Vector2.new(3,bh) b.hpBar.Color=self:_hc(frac) b.hpBar.ZIndex=3 end
                        b.name.Visible=sName if sName then b.name.Text=model.Name b.name.Position=Vector2.new(top.X,y-self.Settings.TextSize-2) b.name.ZIndex=4 end
                        b.dist.Visible=sDist if sDist then b.dist.Text=math.floor(dist).."m" b.dist.Position=Vector2.new(top.X,bot.Y+2) b.dist.ZIndex=4 end
                        b.tracer.Visible=sTr if sTr then b.tracer.From=Vector2.new(C.ViewportSize.X/2,vpY) b.tracer.To=Vector2.new(top.X,bot.Y) b.tracer.ZIndex=1 end
                    end end end end
    end
    function ESP:Init() if self.Loaded then return self end self.Loaded=true self.Conns[#self.Conns+1]=RunService.RenderStepped:Connect(function() local ok,err=pcall(function() self:_update() end) if not ok then warn("[ESP] "..tostring(err)) end end) return self end
    function ESP:Unload() if not self.Loaded then return end self.Loaded=false for _,c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end for _,o in ipairs(self.Drawings) do pcall(function() o.Visible=false o:Remove() end) end table.clear(self.Drawings) table.clear(self.Objects) table.clear(self.Conns) end
    return ESP
end)()

--==================================================================
-- AIMBOT  (Mouse + Camera)
--==================================================================
local Aim = (function()
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local UserInputService  = game:GetService("UserInputService")
    local CollectionService = game:GetService("CollectionService")
    local LocalPlayer       = Players.LocalPlayer
    local mouseMove = rawget(getfenv(), "mousemoverel") or mousemoverel

    local Aim = { Drawings={}, Conns={}, Loaded=false, Flags=nil, CurrentTarget=nil,
        Settings={ Enabled=false, Method="Mouse", Activation="Hold Right Click", TargetPart="Head", FOV=120, Smoothness=6, MaxDistance=1000, VisibleCheck=false, ShowFOV=true, FOVColor=Color3.fromRGB(96,130,255) } }

    function Aim:_flag(k,d) if self.Flags then local v=self.Flags["Aim_"..k] if v~=nil then return v end end local s=self.Settings[k] if s~=nil then return s end return d end
    function Aim:_draw(c,p) local o=Drawing.new(c) o.Visible=false if p then for k,v in pairs(p) do o[k]=v end end table.insert(self.Drawings,o) return o end
    function Aim:BindFlags(ft) self.Flags=ft end
    local function partName(sel) return sel=="Body" and "HitboxBody" or "HitboxHead" end
    function Aim:_active() if not self:_flag("Enabled",false) then return false end local mode=self:_flag("Activation","Hold Right Click")
        if mode=="Always" then return true end
        if mode=="Hold Right Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
        if mode=="Hold Left Click" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
        return false end
    function Aim:_visible(cam,part,model) if not self:_flag("VisibleCheck",false) then return true end
        local p=RaycastParams.new() p.FilterType=Enum.RaycastFilterType.Exclude p.FilterDescendantsInstances={LocalPlayer.Character}
        local r=workspace:Raycast(cam.CFrame.Position,part.Position-cam.CFrame.Position,p) return (not r) or r.Instance:IsDescendantOf(model) end
    function Aim:_getTarget()
        local C=workspace.CurrentCamera local vp=C.ViewportSize local center=Vector2.new(vp.X/2,vp.Y/2)
        local fov=self:_flag("FOV",120) local maxD=self:_flag("MaxDistance",1000) local pName=partName(self:_flag("TargetPart","Head")) local myChar=LocalPlayer.Character local origin=C.CFrame.Position
        local best,bestScore,bestPart=nil,fov,nil
        for _,model in ipairs(CollectionService:GetTagged("Entity")) do
            if model~=myChar then local hum=model:FindFirstChildOfClass("Humanoid") local part=model:FindFirstChild(pName) or model:FindFirstChild("Head")
                if hum and hum.Health>0 and part then local sp=C:WorldToViewportPoint(part.Position)
                    if sp.Z>0 then local d=(Vector2.new(sp.X,sp.Y)-center).Magnitude local dist=(part.Position-origin).Magnitude
                        if d<=bestScore and dist<=maxD and self:_visible(C,part,model) then best,bestScore,bestPart=model,d,part end
                    end end end end
        return best,bestPart end
    function Aim:_step()
        local model,part=self:_getTarget() self.CurrentTarget=model if not part then return end
        local C=workspace.CurrentCamera local method=self:_flag("Method","Mouse") local smooth=math.max(self:_flag("Smoothness",6),1)
        if method=="Camera" then local desired=CFrame.lookAt(C.CFrame.Position,part.Position) C.CFrame=C.CFrame:Lerp(desired,math.clamp(1/smooth,0,1))
        else if not mouseMove then return end local sp=C:WorldToViewportPoint(part.Position) local vp=C.ViewportSize mouseMove((sp.X-vp.X/2)/smooth,(sp.Y-vp.Y/2)/smooth) end
    end
    function Aim:_updateFOV()
        if not self.fovCircle then self.fovCircle=self:_draw("Circle",{Thickness=1,NumSides=48,Filled=false,Color=self.Settings.FOVColor}) end
        local show=self:_flag("Enabled",false) and self:_flag("ShowFOV",true) self.fovCircle.Visible=show
        if show then local vp=workspace.CurrentCamera.ViewportSize self.fovCircle.Position=Vector2.new(vp.X/2,vp.Y/2) self.fovCircle.Radius=self:_flag("FOV",120) self.fovCircle.ZIndex=1 end
    end
    function Aim:Init() if self.Loaded then return self end self.Loaded=true self.Conns[#self.Conns+1]=RunService.RenderStepped:Connect(function() local ok,err=pcall(function() self:_updateFOV() if self:_active() then self:_step() else self.CurrentTarget=nil end end) if not ok then warn("[Aim] "..tostring(err)) end end) return self end
    function Aim:Unload() if not self.Loaded then return end self.Loaded=false for _,c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end for _,o in ipairs(self.Drawings) do pcall(function() o.Visible=false o:Remove() end) end table.clear(self.Drawings) table.clear(self.Conns) self.fovCircle=nil end
    return Aim
end)()

--==================================================================
-- WIRING
--==================================================================
ESP:BindFlags(Library.Flags) ESP:Init()
Aim:BindFlags(Library.Flags) Aim:Init()

local Window = Library:CreateWindow({ Title = "RIVALS  |  build 0.3", Size = Vector2.new(580, 560), Position = Vector2.new(160, 120) })

-- VISUALS
local Visuals = Window:AddTab("Visuals")
local eb = Visuals:AddLeftGroupbox("ESP")
local en = eb:AddToggle("ESP_Enabled", { Text = "Enable ESP", Default = true })
en:AddToggle("ESP_Box",         { Text = "Box",            Default = true })
en:AddToggle("ESP_Name",        { Text = "Nombre",         Default = true })
en:AddToggle("ESP_Health",      { Text = "Barra vida",     Default = true })
en:AddToggle("ESP_Distance",    { Text = "Distancia",      Default = true })
en:AddToggle("ESP_Tracer",      { Text = "Tracers",        Default = false })
en:AddToggle("ESP_PlayersOnly", { Text = "Solo jugadores", Default = false })
en:AddSlider("ESP_MaxDistance", { Text = "Alcance", Min = 100, Max = 2000, Default = 1200, Suffix = "m" })

-- COMBAT
local Combat = Window:AddTab("Combat")
local ab = Combat:AddLeftGroupbox("Aimbot")
local aen = ab:AddToggle("Aim_Enabled", { Text = "Enable Aimbot", Default = false })
aen:AddDropdown("Aim_Method",     { Text = "Método",     Values = { "Mouse", "Camera" }, Default = "Mouse" })
aen:AddDropdown("Aim_Activation", { Text = "Activación", Values = { "Hold Right Click", "Hold Left Click", "Always" }, Default = "Hold Right Click" })
aen:AddDropdown("Aim_TargetPart", { Text = "Parte",      Values = { "Head", "Body" }, Default = "Head" })
aen:AddSlider("Aim_FOV",          { Text = "FOV",     Min = 10,  Max = 600,  Default = 120, Suffix = "px" })
aen:AddSlider("Aim_Smoothness",   { Text = "Smooth",  Min = 1,   Max = 30,   Default = 6 })
aen:AddSlider("Aim_MaxDistance",  { Text = "Alcance", Min = 100, Max = 2000, Default = 1000, Suffix = "m" })
aen:AddToggle("Aim_VisibleCheck", { Text = "Solo visibles", Default = false })
aen:AddToggle("Aim_ShowFOV",      { Text = "Mostrar FOV",   Default = true })

-- SETTINGS
local Settings = Window:AddTab("Settings")
local mb = Settings:AddLeftGroupbox("Menu")
mb:AddLabel("RightShift = toggle menu")
mb:AddButton("Unload todo", function() Aim:Unload() ESP:Unload() Library:Unload() end)

getgenv().RivalsMenu = { Library = Library, ESP = ESP, Aim = Aim }
print("[RivalsMain] build 0.3 cargado (UI desde GitHub).")
return getgenv().RivalsMenu
