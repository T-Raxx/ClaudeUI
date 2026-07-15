# Rivals

Menú de cheats para Rivals (Roblox), construido sobre una UI propia de Drawing API.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/T-Raxx/ClaudeUI/refs/heads/main/Loader.lua"))()
```

`RightShift` abre el menú.

## Cómo está armado

El script base es **limpio**: no hookea nada, no usa `setthreadidentity` ni
`sethiddenproperty`. Lee instancias y usa la API que el propio juego expone.

Todo lo que sí necesita hooks vive fuera, en un módulo aparte que hay que pedir
a mano (Settings > Modulos) y que avisa antes de cargarse. Si no lo cargás, ese
código nunca entra al cliente.

| Archivo | Qué es | Carga |
|---|---|---|
| `Loader.lua` | Baja el principal | — |
| `RivalsMain.lua` | Base: ESP, aimbot, triggerbot, chams, HUD, configs | siempre |
| `RivalsUI.lua` | La librería de UI (Drawing) | siempre |
| `RivalsVisuals.lua` | Mundo: lighting, fog, tinte, cielo, clima | siempre |
| `RivalsCombat.lua` | Cámara y efectos, vía API del juego | siempre |
| `RivalsRage.lua` | Rage. Usa hooks | bajo demanda |

## Features

**ESP** — box, nombre, vida, distancia, tracers, esqueleto (R15), chams de
enemigos, flechas para los que están fuera de pantalla, color por team o por
visibilidad, nivel, arma equipada, y ESP de granadas y trampas desplegadas.

Filtro por arena: Rivals corre varios duelos en el mismo servidor, así que por
defecto solo se muestra gente de tu duelo (`EnvironmentID`).

**Aimbot / Triggerbot** — apuntado por mouse (movimiento real) o por cámara,
FOV configurable, chequeo de visibilidad, activación por hold o always.

**Chams locales** — brazos, arma y cuerpo, con material y color. Los chams
limpian lo que tapa el material (el decal de la manga, las texturas de las
partes, la ropa y los accesorios) y lo devuelven al apagarse.

**Mundo** — fullbright, ambient, brillo, hora, exposición, sombras, fog,
atmósfera, tinte, bloom, rayos de sol, nubes, y clima local: lluvia, lluvia
fuerte y nieve, con color, densidad, velocidad y brillo configurables.

**Cámara** — tercera persona, FOV extra y sin sacudida. Los tres usan la API
del propio Rivals, no hooks.

**Efectos enemigos** — anti-flashbang y anti-humo.

**HUD** — watermark con FPS, ping y hora; lista de keybinds.

**UI** — tema completo editable (8 colores y fuente), keybinds en cualquier
toggle con modos Toggle/Hold/Always, configs con nombre en `RivalsConfigs/`,
paneles con scroll y un modelo 3D del arma girando en el menú.

## Sobre detección

"Sin hooks" no es lo mismo que "invisible". Lo que la base deja a la vista:

- El menú es Drawing puro: **cero instancias**, no aparece en un scan del árbol.
- El clima crea un `Part` en `workspace` mientras está activo.
- El tinte, la atmósfera y el bloom crean efectos en `Lighting`.
- El modelo 3D sólido crea un `ScreenGui` con `ViewportFrame`. Va a `gethui()`
  cuando el ejecutor lo tiene, que los scripts del juego no pueden leer. Hay un
  modo wireframe que no crea nada.
- La cámara escribe campos del `CameraController` del juego
  (`_third_person_override`, `_external_fov_offsets`, `_shake_enabled`). Son
  campos suyos: un anticheat que los revise los ve.
- Los chams cambian material y color de partes que ya existen.

El módulo Rage es otra cosa: hookea `__index`, mueve el `HumanoidRootPart` real
y escribe propiedades ocultas. Es detectable y el aviso lo dice.

## Requisitos del ejecutor

La base necesita Drawing API y `game:HttpGet`. El módulo Rage además necesita
`hookmetamethod`, `checkcaller`, `getgenv`, `setthreadidentity` y
`sethiddenproperty`; el aviso chequea cuáles te faltan antes de cargar.

## Configs

Se guardan por nombre en `RivalsConfigs/`. El dropdown lee la carpeta, así que
podés borrar un `.json` a mano y se actualiza.

Cargar una config que traiga features de rage activas pide confirmación y las
nombra. `Rage_Enabled` y `Rage_VoidSpam` no se guardan nunca: ninguna config
puede activarlos sola.
