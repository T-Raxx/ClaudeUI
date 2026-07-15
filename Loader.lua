--[[
    Rivals  -  loader
    ------------------------------------------------------------------
        loadstring(game:HttpGet("https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/Loader.lua"))()

    Baja y ejecuta el script principal. El resto de los modulos los pide el
    principal por su cuenta.
    RightShift abre el menu.
------------------------------------------------------------------ ]]

local BASE = "https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/"

if not (Drawing and Drawing.new) then
    return error("[Rivals] tu ejecutor no tiene Drawing API: el menu no puede dibujarse", 0)
end

-- ?t= rompe el cache del CDN de GitHub (si no, podes quedarte con una version vieja
-- hasta 5 min despues de un push)
local url = BASE .. "RivalsMain.lua?t=" .. tostring(math.random(1, 1e9))

local ok, src = pcall(function() return game:HttpGet(url) end)
if not ok or type(src) ~= "string" or #src < 500 then
    return error("[Rivals] no se pudo descargar: " .. tostring(src), 0)
end

local chunk, err = loadstring(src)
if not chunk then
    return error("[Rivals] el script no compila: " .. tostring(err), 0)
end

return chunk()
