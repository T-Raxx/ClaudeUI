# HUD — diseño (2026-07-15)

Estado: aprobado por el user. Build base 0.6 (rage ya separado en módulo remoto).

## Objetivo

Cerrar el rewrite de labels que quedó cortado + agregar HUD genérico a la base.

## Regla de arquitectura

La base (`RivalsMain`) nunca sabe que el rage existe. Todo lo que lea estado del
rage vive en `RivalsRage.lua` (módulo remoto, carga bajo demanda).

| Pieza | Vive en | Motivo |
|---|---|---|
| Línea de labels | módulo rage | lee target / void / HP del rage |
| Watermark | base | útil sin cargar el módulo |
| Widget keybind | UI lib | lo usan base y módulo |
| Lista de keybinds | UI lib (`Library.Keybinds`) | genérico, no toca el juego |

Desvío respecto de lo hablado: la lista de keybinds queda en la UI lib, no en la
base — lee solo estado de `Library`, así que ahí es reusable. La base solo la
prende y la posiciona.

## 1. Inyección de groupbox

`Window:GetTab(name)` → devuelve el tab por nombre (nil si no existe).

El módulo rage hace:

    Window:GetTab("Visuals"):AddRightGroupbox("HUD (labels)")

El groupbox aparece bajo Visuals pero lo crea el módulo. Sin módulo cargado, no
existe. Esto es lo que permite cumplir "mover HUD a Visuals" sin devolverle
flags `Rage_*` a la base.

## 2. Línea de labels (módulo rage)

Una línea horizontal centrada bajo el crosshair. Segmentos, cada uno su
`Drawing.Text` con su color (un solo Text no soporta color por segmento):

    Ragebot:  Void...  killing: <user>...  health: <hp>

- `Ragebot:` = 8 Text (uno por char) para el gradiente.
- `Void...` solo cuando el target murió / se espera en void.
- Ancho total = suma de `TextBounds.X`; arranca en `cx - total/2` y avanza.
- Segmentos ocultos no ocupan lugar → la línea se recentra sola.

**Gradiente viajero**: `phase = (tick() * HUDFadeSpeed) % 1`; para el char `i`,
`t = ((i-1)/n + phase) % 1` pasado por onda triangular → `from:Lerp(to, t)`.
Loop de izq a der.

**Flags**: se eliminan `HUDX` / `HUDY` (sin sentido anclado al crosshair).
Entran `HUDOffset` (px bajo el centro) y `HUDFadeSpeed` (loops/seg).
Se mantienen `HUDSize` + los 5 colorpickers.

## 3. Watermark (base)

`Drawing.Text` con FPS · ping · hora. Esquina configurable.
Ping real desde `workspace.ServerPing` (IntValue que expone el juego), no
estimado.

## 4. Keybinds (UI lib)

`AddToggle(flag, { Keybind = true })` → dibuja una caja chica de tecla a la
derecha de la fila del toggle.

- Click en la caja → captura: muestra `...`, la próxima tecla queda bindeada.
- Escape / click derecho → limpia el bind.
- Modos: `Toggle` (flip), `Hold` (true mientras se aprieta), `Always`.
- `Flags[flag .. "_Key"]` = nombre del KeyCode (string → serializa a JSON solo).
- `Flags[flag .. "_KeyMode"]` = modo.
- `Library.Keybinds` = lista para el HUD.

Bindeables al arrancar: ESP, Aimbot, Triggerbot.

## Cortado: "quién te espectea"

Infactible client-side. `SpectateController` solo expone estado propio
(`CurrentSubject`, `Subjects`, `_last_spectating_user_id`); espectar es cámara
local y no replica nada. Los atributos replicados por jugador son `GroupRank`,
`EnvironmentID`, `IsInfluencer`, `IsRobloxEmployee`, `TeamID`, `Level`,
`IsTrustworthy`, `StatisticDuelsWinStreak` — ninguno indica a quién mira nadie.

(Esos atributos sirven para el ESP mejorado: `Level`, `TeamID`, `IsInfluencer`.)

## Gotchas conocidos

- symbol.lua guarda las escrituras a props de Drawing por frame para evitar
  flicker. El gradiente obliga a escribir `Color` cada frame; `Text` / `Visible`
  / `Position` sí se escriben solo al cambiar.
- El juego tiene `LightingController` que reaplica lighting por mapa (relevante
  para la tanda visual, no para esta).
