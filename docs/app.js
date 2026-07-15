/* Rivals - showcase
   El menu se declara igual que en la lib: tabs -> groupboxes -> elementos,
   con dependientes colgando de un toggle. Los flags viven en un solo objeto,
   como Library.Flags. */

const F = {};                       // Library.Flags
const subs = [];                    // suscriptores (escaner, HUD, tema)
const notify = () => subs.forEach(f => f());
const set = (k, v) => { F[k] = v; notify(); };

const THEME = {
  Accent: "#6082ff", Background: "#121214", Header: "#18181c", Section: "#1a1a1e",
  Element: "#222228", Outline: "#08080a", Text: "#ebebf0", DimText: "#96969f",
};
const CSSVAR = { Accent: "--accent", Background: "--bg", Header: "--header", Section: "--section",
                 Element: "--element", Outline: "--outline", Text: "--text", DimText: "--dim" };

/* ---------------------------------------------------------------- menu data */
const TABS = [
  { name: "Visuals", boxes: [
    { side: 0, title: "ESP", els: [
      { t: "toggle", f: "ESP_Enabled", x: "Enable ESP", d: true, key: "E", deps: [
        { t: "toggle", f: "ESP_Box", x: "Box", d: true },
        { t: "toggle", f: "ESP_Name", x: "Nombre", d: true },
        { t: "toggle", f: "ESP_Health", x: "Barra vida", d: true },
        { t: "toggle", f: "ESP_Skeleton", x: "Esqueleto" },
        { t: "toggle", f: "ESP_Tracer", x: "Tracers" },
        { t: "toggle", f: "ESP_ArenaOnly", x: "Solo mi arena", d: true },
        { t: "slider", f: "ESP_MaxDistance", x: "Alcance", min: 100, max: 2000, d: 1200, sfx: "m" },
        { t: "dropdown", f: "ESP_TracerOrigin", x: "Tracer: origen", vals: ["Abajo", "Centro pantalla", "Arriba", "Mouse", "Punta del arma"] },
      ]},
    ]},
    { side: 0, title: "ESP: colores", els: [
      { t: "toggle", f: "ESP_TeamColors", x: "Color por team", deps: [
        { t: "color", f: "ESP_EnemyColor", x: "Enemigo", d: "#ff5050" },
        { t: "color", f: "ESP_AllyColor", x: "Aliado", d: "#5abeff" },
      ]},
      { t: "toggle", f: "ESP_Arrows", x: "Flechas (fuera de pantalla)" },
      { t: "toggle", f: "ESP_Items", x: "Granadas y trampas", key: "G" },
      { t: "toggle", f: "ESP_Chams", x: "Chams enemigos" },
    ]},
    { side: 1, title: "HUD", els: [
      { t: "toggle", f: "HUD_Watermark", x: "Watermark (fps/ping/hora)", d: true },
      { t: "toggle", f: "HUD_KeybindList", x: "Lista de keybinds", d: true },
    ]},
    { side: 1, title: "Arms", els: [
      { t: "toggle", f: "Local_ArmChams", x: "Arm chams", deps: [
        { t: "dropdown", f: "Local_ArmMaterial", x: "Material", vals: ["Neon", "ForceField", "Glass", "Metal"] },
        { t: "color", f: "Local_ArmColor", x: "Color", d: "#4678ff" },
        { t: "toggle", f: "Local_ArmFade", x: "Fade (rainbow)" },
      ]},
    ]},
  ]},

  { name: "Combat", boxes: [
    { side: 0, title: "Aimbot", els: [
      { t: "toggle", f: "Aim_Enabled", x: "Enable Aimbot", key: "V", deps: [
        { t: "dropdown", f: "Aim_Method", x: "Método", vals: ["Mouse", "Camera"] },
        { t: "dropdown", f: "Aim_Activation", x: "Activación", vals: ["Hold Right Click", "Hold Left Click", "Always"] },
        { t: "slider", f: "Aim_FOV", x: "FOV", min: 10, max: 600, d: 120, sfx: "px" },
        { t: "slider", f: "Aim_Smoothness", x: "Smooth", min: 1, max: 30, d: 6 },
        { t: "toggle", f: "Aim_VisibleCheck", x: "Solo visibles" },
      ]},
    ]},
    { side: 0, title: "Efectos enemigos", els: [
      { t: "toggle", f: "Cbt_AntiFlash", x: "Anti-flashbang", key: "F" },
      { t: "toggle", f: "Cbt_AntiSmoke", x: "Anti-humo" },
      { t: "label", x: "Clientside: solo cambia lo que ves vos" },
    ]},
    { side: 1, title: "Cámara (API del juego)", els: [
      { t: "label", x: "Sin hooks: usa la API del propio Rivals" },
      { t: "toggle", f: "Cbt_ThirdPerson", x: "Tercera persona", key: "T" },
      { t: "slider", f: "Cbt_FOV", x: "FOV extra", min: -30, max: 50, d: 0, sfx: "°" },
      { t: "toggle", f: "Cbt_NoShake", x: "Sin sacudida de cámara" },
    ]},
    { side: 1, title: "Triggerbot", els: [
      { t: "toggle", f: "Trig_Enabled", x: "Enable Trigger", deps: [
        { t: "slider", f: "Trig_Delay", x: "Delay", min: 0, max: 300, d: 30, sfx: "ms" },
      ]},
    ]},
  ]},

  { name: "Mundo", boxes: [
    { side: 0, title: "Mundo", els: [
      { t: "toggle", f: "Vis_Enabled", x: "Enable visuales", deps: [
        { t: "toggle", f: "Vis_Fullbright", x: "Fullbright" },
        { t: "color", f: "Vis_Ambient", x: "Ambient", d: "#78787d" },
        { t: "slider", f: "Vis_ClockTime", x: "Hora del día", min: 0, max: 24, d: 12, dec: 1, sfx: "h" },
      ]},
    ]},
    { side: 0, title: "Clima", els: [
      { t: "label", x: "Partículas locales: solo las ves vos" },
      { t: "toggle", f: "Vis_Weather", x: "Clima", key: "K", deps: [
        { t: "dropdown", f: "Vis_WeatherMode", x: "Tipo", vals: ["Lluvia", "Lluvia fuerte", "Nieve"] },
        { t: "color", f: "Vis_WeatherColor", x: "Color", d: "#dce6ff" },
        { t: "slider", f: "Vis_WeatherGlow", x: "Brillo propio", min: 0, max: 1, d: 0.15, dec: 2 },
      ]},
    ]},
    { side: 1, title: "Tinte / post", els: [
      { t: "toggle", f: "Vis_Tint", x: "Tinte (ColorCorrection)", deps: [
        { t: "slider", f: "Vis_TintSaturation", x: "Saturación", min: -1, max: 3, d: 0, dec: 2 },
        { t: "color", f: "Vis_TintColor", x: "Color", d: "#ffffff" },
      ]},
      { t: "toggle", f: "Vis_Bloom", x: "Bloom" },
    ]},
    { side: 1, title: "Cielo / nubes", els: [
      { t: "toggle", f: "Vis_Clouds", x: "Nubes custom", deps: [
        { t: "slider", f: "Vis_CloudCover", x: "Cobertura", min: 0, max: 1, d: 0.5, dec: 2 },
      ]},
    ]},
  ]},

  { name: "Settings", boxes: [
    { side: 0, title: "Config", els: [
      { t: "label", x: "Carpeta: RivalsConfigs/" },
      { t: "dropdown", f: "Config_Profile", x: "Config", vals: ["default", "hvh", "legit"] },
      { t: "button", x: "Guardar como (nombre)" },
      { t: "button", x: "Cargar" },
    ]},
    { side: 0, title: "Menu FX", els: [
      { t: "toggle", f: "Vis_MenuBlur", x: "Blur con el menú abierto" },
    ]},
    { side: 1, title: "Tema", els: [
      { t: "color", f: "Theme_Accent", x: "Acento", d: THEME.Accent, theme: "Accent" },
      { t: "color", f: "Theme_Background", x: "Fondo", d: THEME.Background, theme: "Background" },
      { t: "color", f: "Theme_Section", x: "Sección", d: THEME.Section, theme: "Section" },
      { t: "color", f: "Theme_Text", x: "Texto", d: THEME.Text, theme: "Text" },
    ]},
    { side: 1, title: "Modulos", els: [
      { t: "label", x: "Base = limpio (sin hooks)." },
      { t: "button", x: "Cargar modulo avanzado", act: "rage" },
      { t: "toggle", f: "Modules_AdvAuto", x: "Cargar al ejecutar (guardado)" },
    ]},
    { side: 1, title: "Menu", els: [
      { t: "label", x: "RightShift = toggle menu" },
      { t: "toggle", f: "Menu_Showcase", x: "Arma 3D girando" },
    ]},
  ]},
];

/* ---------------------------------------------------------------- helpers */
const el = (tag, cls, txt) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (txt != null) n.textContent = txt;
  return n;
};
const fmt = (v, dec) => dec ? v.toFixed(dec) : String(Math.round(v));

/* ---------------------------------------------------------------- widgets */
function widget(spec, depth) {
  const wrap = el("div", "el-wrap");

  if (spec.t === "toggle") {
    if (F[spec.f] === undefined) F[spec.f] = !!spec.d;
    const row = el("div", "el" + (depth ? " dep" : ""));
    const b = el("button", "tg");
    b.type = "button";
    b.setAttribute("aria-pressed", String(F[spec.f]));
    const box = el("span", "box"); box.appendChild(el("i"));
    b.append(box, el("span", "txt", spec.x));
    b.onclick = () => {
      set(spec.f, !F[spec.f]);
      b.setAttribute("aria-pressed", String(F[spec.f]));
      kids.hidden = !F[spec.f];
    };
    row.appendChild(b);
    if (spec.key) {
      const k = el("div", "key", spec.key);
      k.tabIndex = 0;
      k.title = "click para bindear";
      const cap = () => {
        k.classList.add("cap"); k.textContent = "...";
        const on = ev => {
          ev.preventDefault();
          k.textContent = ev.key === "Escape" ? "---" : ev.key.toUpperCase().slice(0, 3);
          k.classList.remove("cap");
          window.removeEventListener("keydown", on, true);
        };
        window.addEventListener("keydown", on, true);
      };
      k.onclick = cap;
      k.onkeydown = e => { if (e.key === "Enter") { e.preventDefault(); cap(); } };
      row.appendChild(k);
    }
    wrap.appendChild(row);

    const kids = el("div", "col");
    kids.style.gap = "6px";
    kids.hidden = !F[spec.f];
    (spec.deps || []).forEach(d => kids.appendChild(widget(d, depth + 1)));
    if (spec.deps) wrap.appendChild(kids);
    return wrap;
  }

  if (spec.t === "slider") {
    if (F[spec.f] === undefined) F[spec.f] = spec.d;
    const s = el("div", "sl" + (depth ? " dep" : ""));
    const row = el("div", "sl-r");
    const val = el("span", null, fmt(F[spec.f], spec.dec) + (spec.sfx || ""));
    row.append(el("span", null, spec.x), val);
    const track = el("div", "sl-t");
    const fill = el("div", "sl-f");
    track.appendChild(fill);
    s.append(row, track);
    const pct = () => ((F[spec.f] - spec.min) / (spec.max - spec.min)) * 100;
    fill.style.width = pct() + "%";
    const move = e => {
      const r = track.getBoundingClientRect();
      const x = ((e.clientX ?? e.touches[0].clientX) - r.left) / r.width;
      let v = spec.min + (spec.max - spec.min) * Math.min(1, Math.max(0, x));
      const step = spec.dec ? Math.pow(10, -spec.dec) : 1;
      v = Math.round(v / step) * step;
      set(spec.f, v);
      val.textContent = fmt(v, spec.dec) + (spec.sfx || "");
      fill.style.width = pct() + "%";
    };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    track.onpointerdown = e => { move(e); window.addEventListener("pointermove", move); window.addEventListener("pointerup", up); };
    return s;
  }

  if (spec.t === "dropdown") {
    if (F[spec.f] === undefined) F[spec.f] = spec.vals[0];
    const d = el("div", "dd" + (depth ? " dep" : ""));
    d.append(el("div", "dd-l", spec.x));
    const b = el("div", "dd-b");
    const cur = el("span", null, F[spec.f]);
    b.append(cur, el("span", "arw", "v"));
    const list = el("div", "dd-list");
    spec.vals.forEach(v => {
      const o = el("button", null, v);
      o.type = "button";
      if (v === F[spec.f]) o.dataset.sel = "1";
      o.onclick = e => {
        e.stopPropagation();
        set(spec.f, v); cur.textContent = v;
        list.querySelectorAll("[data-sel]").forEach(n => delete n.dataset.sel);
        o.dataset.sel = "1";
        d.classList.remove("open");
      };
      list.appendChild(o);
    });
    b.onclick = e => {
      e.stopPropagation();
      document.querySelectorAll(".dd.open").forEach(n => n !== d && n.classList.remove("open"));
      d.classList.toggle("open");
    };
    d.append(b, list);
    return d;
  }

  if (spec.t === "color") {
    if (F[spec.f] === undefined) F[spec.f] = spec.d || "#ffffff";
    const c = el("div", "el cp" + (depth ? " dep" : ""));
    c.append(el("span", null, spec.x));
    const sw = el("button", "sw");
    sw.type = "button";
    sw.style.background = F[spec.f];
    sw.setAttribute("aria-label", spec.x);
    sw.onclick = e => { e.stopPropagation(); openPicker(sw, spec); };
    c.appendChild(sw);
    return c;
  }

  if (spec.t === "button") {
    const b = el("button", "btn", spec.x);
    b.type = "button";
    if (spec.act === "rage") b.onclick = openRage;
    return b;
  }

  return el("div", "lb", spec.x);
}

/* ---------------------------------------------------------------- colorpicker (SV + hue, como el real) */
let pop, popOwner;
function hsv2hex(h, s, v) {
  const f = n => {
    const k = (n + h * 6) % 6;
    const x = v - v * s * Math.max(0, Math.min(k, 4 - k, 1));
    return Math.round(x * 255).toString(16).padStart(2, "0");
  };
  return "#" + f(5) + f(3) + f(1);
}
function openPicker(sw, spec) {
  if (!pop) {
    pop = el("div", "cp-pop");
    pop.innerHTML = '<canvas class="cp-sv" width="140" height="140"></canvas><canvas class="cp-hue" width="14" height="140"></canvas>';
    document.getElementById("stage").appendChild(pop);
    pop.onclick = e => e.stopPropagation();
  }
  if (popOwner === spec.f && pop.classList.contains("open")) { pop.classList.remove("open"); popOwner = null; return; }
  popOwner = spec.f;
  let h = 0.62, s = .6, v = 1;

  const sv = pop.querySelector(".cp-sv"), hue = pop.querySelector(".cp-hue");
  const draw = () => {
    const a = sv.getContext("2d");
    for (let y = 0; y < 14; y++) for (let x = 0; x < 14; x++) {
      a.fillStyle = hsv2hex(h, (x + .5) / 14, 1 - (y + .5) / 14);
      a.fillRect(x * 10, y * 10, 10, 10);
    }
    const b = hue.getContext("2d");
    for (let i = 0; i < 24; i++) { b.fillStyle = hsv2hex(i / 23, 1, 1); b.fillRect(0, i * (140 / 24), 14, 140 / 24 + 1); }
  };
  const apply = () => {
    const hex = hsv2hex(h, s, v);
    sw.style.background = hex;
    set(spec.f, hex);
    if (spec.theme) document.documentElement.style.setProperty(CSSVAR[spec.theme], hex);
  };
  sv.onpointerdown = e => {
    const r = sv.getBoundingClientRect();
    s = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    v = 1 - Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
    apply();
  };
  hue.onpointerdown = e => {
    const r = hue.getBoundingClientRect();
    h = Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
    draw(); apply();
  };
  draw();
  const r = sw.getBoundingClientRect(), st = document.getElementById("stage").getBoundingClientRect();
  pop.style.left = Math.min(r.left - st.left, st.width - 190) + "px";
  pop.style.top = (r.bottom - st.top + 3) + "px";
  pop.classList.add("open");
}
document.addEventListener("click", () => pop && pop.classList.remove("open"));

/* ---------------------------------------------------------------- render */
const tabsEl = document.getElementById("tabs"), panelsEl = document.getElementById("panels");
TABS.forEach((tab, i) => {
  const b = el("button", "tab", tab.name);
  b.type = "button"; b.role = "tab";
  b.setAttribute("aria-selected", String(i === 0));
  b.onclick = () => showTab(i);
  tabsEl.appendChild(b);

  const p = el("div", "panel");
  p.id = "panel-" + i;
  if (i === 0) p.dataset.open = "1";
  const cols = [el("div", "col"), el("div", "col")];
  tab.boxes.forEach(box => {
    const g = el("div", "gb");
    g.append(el("div", "gb-t", box.title));
    const body = el("div", "gb-b");
    box.els.forEach(e => body.appendChild(widget(e, 0)));
    g.appendChild(body);
    cols[box.side].appendChild(g);
  });
  p.append(cols[0], cols[1]);
  panelsEl.appendChild(p);
});
function showTab(i) {
  [...tabsEl.children].forEach((b, j) => b.setAttribute("aria-selected", String(i === j)));
  [...panelsEl.children].forEach((p, j) => j === i ? p.dataset.open = "1" : delete p.dataset.open);
}

/* ---------------------------------------------------------------- drag */
const menu = document.getElementById("menu"), stage = document.getElementById("stage");
document.getElementById("menu-h").onpointerdown = e => {
  const r = menu.getBoundingClientRect(), s = stage.getBoundingClientRect();
  const ox = e.clientX - r.left, oy = e.clientY - r.top;
  menu.classList.add("drag");
  const mv = ev => {
    menu.style.left = Math.max(0, Math.min(ev.clientX - s.left - ox, s.width - r.width)) + "px";
    menu.style.top = Math.max(0, Math.min(ev.clientY - s.top - oy, s.height - 40)) + "px";
  };
  const up = () => { menu.classList.remove("drag"); window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); };
  window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
};

/* ---------------------------------------------------------------- modal de rage (el real) */
const modal = document.getElementById("modal");
function openRage() {
  const L = [
    ["w", "Este modulo NO es seguro. Usa hooks y funciones"],
    ["w", "de bajo nivel que el juego puede detectar:"],
    ["", "&nbsp;"],
    ["", "&nbsp;&nbsp;hookmetamethod(game, \"__index\") — spoof de posicion"],
    ["", "&nbsp;&nbsp;setthreadidentity(2) — disparo interno"],
    ["", "&nbsp;&nbsp;sethiddenproperty(PhysicsRep...) — weld al enemigo"],
    ["", "&nbsp;"],
    ["r", "DETECCION"],
    ["", "&nbsp;&nbsp;Los hooks son rastreables desde el cliente. El AC de"],
    ["", "&nbsp;&nbsp;Rivals banea movement cheats. Usar SOLO en VIP / alt."],
    ["", "&nbsp;"],
    ["r", "COMPATIBILIDAD"],
    ["", "&nbsp;&nbsp;Ejecutores de gama baja (Solara, Xeno, Luna) no"],
    ["", "&nbsp;&nbsp;implementan estas funciones: crashea o no hace nada."],
  ];
  const body = document.getElementById("modal-body");
  body.innerHTML = L.map(([c, t]) => `<p class="${c}">${t}</p>`).join("");
  modal.classList.add("open");
  document.getElementById("modal-yes").focus();
}
document.getElementById("modal-no").onclick = () => modal.classList.remove("open");
document.getElementById("modal-yes").onclick = () => {
  modal.classList.remove("open");
  set("__rage", true);
  document.getElementById("hudline").hidden = false;
};
document.addEventListener("keydown", e => { if (e.key === "Escape") modal.classList.remove("open"); });

/* ---------------------------------------------------------------- HUD vivo */
const hudRage = document.getElementById("hud-rage");
"Ragebot:".split("").forEach(ch => { const s = el("span", null, ch); hudRage.appendChild(s); });
let t0 = performance.now();
const tri = t => { t %= 1; return t < .5 ? t * 2 : 2 - t * 2; };
function frame(now) {
  const ph = ((now - t0) / 1000 * 0.6) % 1;
  const n = hudRage.children.length;
  [...hudRage.children].forEach((s, i) => {
    const k = tri(i / n + ph);
    const c = Math.round(255 * (1 - k));
    s.style.color = `rgb(${c},${c},${c})`;
  });
  requestAnimationFrame(frame);
}
if (!matchMedia("(prefers-reduced-motion: reduce)").matches) requestAnimationFrame(frame);
else [...hudRage.children].forEach((s, i, a) => s.style.color = `rgb(${255 - i * 30},${255 - i * 30},${255 - i * 30})`);

setInterval(() => {
  document.getElementById("clock").textContent = new Date().toTimeString().slice(0, 8);
}, 1000);

/* ---------------------------------------------------------------- escaner (firma) */
const SURFACE = [
  { f: "Vis_Weather",   path: "workspace.Camera",                    who: "clima (Part + ParticleEmitter)" },
  { f: "Vis_Tint",      path: "Lighting.LightingController",         who: "tinte (ColorCorrectionEffect)" },
  { f: "Vis_Bloom",     path: "Lighting.LightingController",         who: "bloom (BloomEffect)" },
  { f: "Vis_Clouds",    path: "workspace.Terrain.LightingController", who: "nubes (Clouds)" },
  { f: "Menu_Showcase", path: "CoreGui...LightingController",        who: "arma 3D (ScreenGui, va a gethui)" },
  { f: "Cbt_ThirdPerson", path: "CameraController._third_person_override", who: "campo del juego = true" },
  { f: "Cbt_NoShake",   path: "CameraController._shake_enabled",     who: "campo del juego = false" },
  { f: "ESP_Chams",     path: "<enemigo>.UpperTorso.Material",       who: "material cambiado" },
];
const SCAN_FLAGS = ["Vis_Weather", "Vis_Tint", "Vis_Bloom", "Vis_Clouds", "Menu_Showcase", "Cbt_ThirdPerson", "Cbt_NoShake", "ESP_Chams", "ESP_Enabled", "Aim_Enabled"];

const ctl = document.getElementById("scan-ctl");
SCAN_FLAGS.forEach(f => {
  const spec = { t: "toggle", f, x: labelOf(f) };
  ctl.appendChild(widget(spec, 0));
});
function labelOf(f) {
  const m = {
    Vis_Weather: "Clima", Vis_Tint: "Tinte", Vis_Bloom: "Bloom", Vis_Clouds: "Nubes custom",
    Menu_Showcase: "Arma 3D (sólido)", Cbt_ThirdPerson: "Tercera persona", Cbt_NoShake: "Sin sacudida",
    ESP_Chams: "Chams enemigos", ESP_Enabled: "ESP", Aim_Enabled: "Aimbot",
  };
  return m[f] || f;
}

const tree = document.getElementById("tree");
function renderTree() {
  tree.innerHTML = "";
  const hits = SURFACE.filter(s => F[s.f]);
  const seen = new Set();
  hits.forEach(s => {
    if (seen.has(s.path + s.who)) return;
    seen.add(s.path + s.who);
    const ln = el("div", "ln");
    ln.append(el("span", null, "+"), el("span", "path", s.path), el("span", "who", "← " + s.who));
    tree.appendChild(ln);
  });
  const menuLn = el("div", "ln ok");
  menuLn.append(el("span", null, "·"), el("span", "path", "el menú (RivalsUI)"), el("span", null, "← Drawing: no está en el árbol"));
  tree.appendChild(menuLn);

  const f = el("div", "found " + (hits.length ? "some" : "zero"));
  f.textContent = hits.length
    ? hits.length + " instancia(s) o campo(s) visibles para un scan del juego"
    : "0 rastros. Solo ESP y aimbot: nada nuevo en el árbol.";
  tree.appendChild(f);
}
subs.push(renderTree);
renderTree();

/* HUD / watermark reaccionan a los flags */
subs.push(() => {
  document.getElementById("wm").hidden = !F.HUD_Watermark;
  document.getElementById("hudline").hidden = !F.__rage;
});
document.getElementById("wm").hidden = !F.HUD_Watermark;

/* ---------------------------------------------------------------- features -> llevan al control */
const FEATS = [
  { h: "ESP completo", p: "Box, nombre, vida, distancia, esqueleto R15, chams, flechas para los que no ves, color por team o visibilidad, nivel y arma equipada.", tab: 0 },
  { h: "Filtro por arena", p: "Rivals corre varios duelos por servidor. Por defecto solo ves gente de tu duelo, no de las otras arenas.", tab: 0 },
  { h: "Granadas y trampas", p: "Las que se despliegan durante la ronda, cazadas por evento: no escanea el mapa por frame.", tab: 0 },
  { h: "Aimbot y triggerbot", p: "Apuntado por mouse real o por cámara, con FOV, suavizado y chequeo de visibilidad.", tab: 1 },
  { h: "Anti-flash y anti-humo", p: "El flashbang se arma con instancias reconocibles y el humo con partículas. Se neutralizan sin hooks.", tab: 1 },
  { h: "Cámara", p: "Tercera persona, FOV extra y sin sacudida — los tres con la API del propio Rivals.", tab: 1 },
  { h: "Mundo y clima", p: "Fullbright, fog, atmósfera, tinte, nubes y clima local: lluvia, lluvia fuerte y nieve.", tab: 2 },
  { h: "Tema y configs", p: "Los 8 colores del menú son editables en vivo. Configs con nombre en RivalsConfigs/.", tab: 3 },
];
const feats = document.getElementById("feats");
FEATS.forEach(f => {
  const c = el("div", "feat");
  c.append(el("h3", null, f.h), el("p", null, f.p));
  const b = el("button", "go", "ver en el menú →");
  b.type = "button";
  b.onclick = () => { showTab(f.tab); document.getElementById("probar").scrollIntoView({ block: "center" }); };
  c.appendChild(b);
  feats.appendChild(c);
});

/* ---------------------------------------------------------------- copiar loader */
const copyBtn = document.getElementById("copy");
copyBtn.onclick = async () => {
  try {
    await navigator.clipboard.writeText(document.getElementById("loadline").textContent.trim());
    copyBtn.textContent = "copiado"; copyBtn.classList.add("done");
    setTimeout(() => { copyBtn.textContent = "copiar"; copyBtn.classList.remove("done"); }, 1600);
  } catch { copyBtn.textContent = "copialo a mano"; }
};
