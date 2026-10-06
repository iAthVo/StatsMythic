# StatsMythic

A World of Warcraft (Retail) addon that combines a live stat panel
(Character / Recommended) with Pawn-style tooltip comparisons, using
weights you load yourself from your own SimulationCraft runs — no
external website, no database, no simulation running inside the addon.

**Author:** TavoD_Gus_KrG · **License:** [MIT](LICENSE) · see
[CREDITS.md](CREDITS.md) for bundled libraries and data sources.

🇬🇧 **[English](#english)** · 🇲🇽 **[Español](#español)**

---

## English

StatsMythic never calculates weights or runs a simulation on its own —
you give it the numbers (from SimC), and it applies them consistently in
two places: the floating panel and the tooltip of any item.

### Getting started

1. **Run SimulationCraft** (free, open source) with your current
   character to get your spec's stat weights. You'll get something like:

   ```
   Agility 3.73
   Off Hand Weapon DPS 2.21
   Haste 1.35
   Critical Strike 1.20
   Versatility 0.91
   Mastery 0.24
   Weapon DPS 18.33
   ```

2. In-game, open the config with `/stm config` (or `/stm m`) and go to
   the **"Scales"** tab.
3. **By hand**: type a name for your scale under "New Scale" and press
   Enter, so you have an active scale before pasting anything.
4. **Paste Result**: whether your output is full Pawn format (Raidbots
   and SimC both export this way, e.g.
   `( Pawn: v1: "Name": Class=.., CritRating=.., ... )`) or just the bare
   `Key=Number` pairs with no name, paste it into **"Paste Result"**:
   - If you already have an **active scale** (from step 3), its weights
     get updated — your scale's own name wins over whatever name the
     pasted text carries, even if they differ.
   - If nothing is active and the pasted text has a name, a new scale is
     created under that name.
5. Done — the floating panel and tooltip comparisons now use those
   weights.

You can create several scales (e.g. one for PvE, one for PvP) and switch
which one is active from the same panel. **Scales are saved per
character** — each character has its own list, never shared across the
whole account.

Named a scale wrong? In the "Character Scales" tab, every card has its
own "Rename" button — clicking it reveals a textbox for the new name
(the button turns into "Cancel" if you change your mind), and Enter
renames that scale without losing any of its weights.

Besides the "Active scale" dropdown, `/stm config` also shows a card per
saved scale (a summary of its weights + "Use this scale" / "Delete"
buttons), so you can see all of them at a glance.

### The 7 weights

| Field | What it is | Where it's used |
|---|---|---|
| Primary stat (Agility/Strength/Intellect, per your class) | Your character's primary stat | Tooltip comparison only |
| Crit | Critical Strike | Panel (Character/Recommended) + tooltip |
| Haste | Haste | Panel (Character/Recommended) + tooltip |
| Mastery | Mastery | Panel (Character/Recommended) + tooltip |
| Versatility | Versatility | Panel (Character/Recommended) + tooltip |
| Weapon DPS | Main-hand weapon DPS | Tooltip comparison only |
| Off Hand Weapon DPS | Off-hand weapon DPS | Tooltip comparison only |

A weight of `0` simply doesn't participate — each class/spec only loads
what applies to it (e.g. a class with no off-hand weapon leaves that
field at 0).

**Note on Weapon DPS**: unlike the other stats, there's no official
Blizzard function that returns this directly — it's calculated by
reading the weapon's min/max damage and speed off its tooltip (same
general idea as Pawn, but only for these 3 numbers). It's the least
battle-tested part of the addon; if a weapon comparison looks off, check
with `/stm debugitem`.

### The floating panel

For each stat, it shows the **Character** value (live, updates on gear
changes, potions, buffs, procs) and the **Recommended** value — your
current total secondary rating, redistributed proportionally according
to your weights. It tells you "here's how you'd be distributed per your
own priorities," without inventing any external number.

The total redistributed for "Recommended" stays **fixed** while you keep
the same active scale — it doesn't recalculate every time you swap gear.
It only recalculates if you change the active scale, or by hand with
`/stm recalc` if you want to update the target after a real gear
upgrade.

#### Power bars (optional)

Instead of text, Crit/Haste/Mastery/Versatility can be shown as bars
that fill according to Character ÷ Recommended — enable it with **Power
bars** in `/stm config`. Each bar has a soft glow at its leading edge, in
that stat's own color. Past 100% (you have more of that stat than your
scale recommends), the bar stays full and a more intense stripe marks
the extra lap, with a `×N` counter next to it. The gap between one bar
and the next is set with **Bar spacing**, independent of line spacing
(which only affects the plain-text rows). **Bar height** and the
**label-to-bar gap** each have their own slider too. Bar width follows
the panel's own **Width** — there's no separate slider for it, since
that would just duplicate the same control.

With **Text inside the bar** enabled, each bar's label is drawn on top
of the bar itself instead of on its own row above it (saves vertical
space) — in that mode the text always gets an outline, regardless of
"Font outline," so it stays readable no matter the bar's current fill
color.

Each secondary bar's label is split into **two independent parts**: the
Character side (left, e.g. "Crit: 620 29%") follows **Text alignment**,
same as the plain-text rows — it doesn't move with the bar's width. The
Recommended side (right, e.g. "/ 980 33%") always sits at the right edge
and moves together with the bar's actual width.

**Primary Stat, Leech and Avoidance** are also shown as a bar with
"Power bars" on, but **static** — always full at 100% in their own
color, with no overflow stripe or comparison (they have no Recommended
value to measure against), just the live value as text.

**Item Level** is also a bar, but the only one with a **real fill and a
dynamic color**: the fill is your equipped ilvl ÷ the season's highest
achievable ilvl, and the color blends smoothly from white → blue →
purple → orange depending on which gear-upgrade track (Veteran,
Champion, Myth) that ilvl would fall into — the same colors the game
uses for Rare/Epic/Legendary items. Its label shows all three numbers:
equipped / overall / season max (e.g. "Item Level: 300 / 305 / 344").
These reference numbers get updated by hand each season, because
Blizzard exposes no function to pull them automatically — not even large
libraries like LibOpenRaid (used by Details) rely on one. `/stm
debugseason` prints the detected season ID, in case automatic
multi-season support gets added later.

- Dragged freely (unless locked).
- Fully customizable — see the Configuration section below.
- Stat names always show in English (Crit, Haste, Mastery, Versatility,
  Primary Stat, Item Level, Leech, Avoidance), regardless of menu
  language — same terms SimC/Raidbots use.
- **Leech and Avoidance** (tertiary stats) only show the Character
  value — they have no Recommended value, since they don't share the
  secondary-rating budget with the 4 main secondaries (they're optional
  extra rolls, not always present on gear).

### Native character pane (`C` key)

Hovering Crit, Haste, Mastery or Versatility on the character pane adds
a tooltip line `Optimal: <number> (<percent>%)`, using the same
calculation as the floating panel.

Works with both Blizzard's native pane and **GW2_UI**'s (auto-detects
whichever is active). The line keeps re-asserting itself while the mouse
stays over it, so it doesn't vanish if the pane redraws underneath it.

### Equipment comparison (item tooltips)

Hover any item — in your bags, a vendor, loot, the auction house, or a
chat link — and a line appears with the percentage improvement compared
to whatever you have equipped in that slot (e.g. "Lock: +14.6%", green
if it's an upgrade, red if not), using the active scale. For rings and
trinkets, it compares against the weaker of the two you're wearing.

The active scale always shows on this line. If you also want to see
other scales at the same time (for example to compare an item against
PvE and PvP priorities at once, without switching which one is active),
check **"Show in tooltip"** on that scale's card, in the "Character
Scales" tab — it shows up as an extra line below the active scale's.

### Configuration (`/stm config`)

The panel is organized into tabs:

- **Scales**: pick the active scale, create a new one, paste a
  Pawn/Raidbots result, delete the active one, and the 7 weight fields.
- **Character Scales**: cards for every scale saved on this character,
  their non-zero weights, the "Show in tooltip" toggle, "Use this
  scale" / "Delete" buttons, and a "Rename" field per card.
- **Panel**: width, font (with a visual picker), font size and outline,
  line spacing, **bar spacing**, **bar height**, **label-to-bar gap**
  (all independent of line spacing — only affect "Power bars"), decimal
  places, text alignment, one-line layout, **Power bars**, **text inside
  the bar**, independent **Character Format** and **Recommended
  Format** (3 options each: Number, Number / Percent, Percent — 9
  possible combinations), background opacity, show border, when to show
  the panel (always / in combat only / out of combat only), lock
  position, reset position.
- **Which stats to show**: an individual toggle per stat, plus a button
  to show/hide all 4 secondaries at once.
- **Profiles**: all panel customization lives in an AceDB profile — you
  can create different profiles per character/spec and switch between
  them here. Weight scales are shared across all profiles (they're
  reusable data, not a visual preference). At the bottom of this same
  tab, in its own box, are the menu language (Spanish/English — only
  affects button/option text, never stat names) and the minimap icon.

### Commands

| Command | What it does |
|---|---|
| `/stm` or `/stm config` or `/stm m` | Opens the config panel |
| `/stm lock` | Locks the floating panel's position |
| `/stm unlock` | Unlocks the floating panel's position |
| `/stm status` | Prints the active scale, how many scales are saved, and the current profile |
| `/stm recalc` | Manually recalculates the "Recommended" target with your current rating |
| `/stm debugitem` | With an item under your mouse, prints the raw stats the API returns, to verify the comparison is mapped correctly |
| `/stm debugchar` | With the character pane open, prints the internal name of each stat row (native or GW2_UI) |
| `/stm debugseason` | Prints the detected season ID |
| `/stm errors` (alias `/stm bugs`) | Opens a window with the last 10 Lua errors, in a selectable textbox. Needs `!BugGrabber` installed (ships with BugSack) |

`/statsmythic` also works as a full alias for `/stm`.

### Compatibility

- **GW2_UI**: supported — the character pane detects whether GW2_UI
  replaced the native one and hooks there instead of (or alongside)
  Blizzard's.
- **BlizzMove, ElvUI, Pawn, Stats+**: no direct integration, but no known
  conflicts either — StatsMythic doesn't touch anything from those
  addons. The only thing avoided on purpose was the `/stats` command,
  already used by Stats+.

### Known limitations

- The "Recommended/Optimal" percentage for **Mastery** is an
  approximation (calculated proportionally to your own current
  rating→percent ratio), because Mastery has a base value that doesn't
  depend on rating, with no way to isolate it via the API.
- **Weapon DPS / Off Hand Weapon DPS** are calculated by reading the
  weapon's tooltip (no official function for this) — can fail on items
  with an unusual tooltip format.
- StatsMythic is a free, independent fan addon with no affiliation to or
  endorsement by Blizzard Entertainment, and is never monetized.

---

## Español

StatsMythic no calcula pesos por su cuenta ni corre ninguna simulación —
tú le das los números (sacados de SimC), y el addon los aplica de forma
consistente en dos lugares: el panel flotante y el tooltip de cualquier
objeto.

### Primeros pasos

1. **Corre SimulationCraft** (gratis, de código abierto) con tu
   personaje actual para sacar los pesos de stats de tu spec. Vas a
   obtener algo parecido a esto:

   ```
   Agility 3.73
   Off Hand Weapon DPS 2.21
   Haste 1.35
   Critical Strike 1.20
   Versatility 0.91
   Mastery 0.24
   Weapon DPS 18.33
   ```

2. En el juego, abre la configuración con `/stm config` (o `/stm m`) y
   anda a la pestaña **"Escalas"**.
3. **A mano**: escribe un nombre para tu escala en "Nueva Escala" y
   presiona Enter, para tener una escala activa antes de pegar nada.
4. **Pegar Resultado**: si tu resultado viene en formato Pawn (Raidbots
   y SimC lo tiran así, ej.
   `( Pawn: v1: "Nombre": Class=.., CritRating=.., ... )`) o incluso solo
   los pares `Clave=Numero` sueltos (sin el nombre), pégalo en el campo
   **"Pegar Resultado"**:
   - Si ya tienes una **escala activa** (la que creaste en el paso 3),
     se usan sus pesos ahí — el nombre de tu escala manda, no el que
     traiga el texto pegado, aunque sean distintos.
   - Si no hay ninguna escala activa y el texto sí trae nombre, se crea
     una escala nueva con ese nombre.
5. Listo — el panel flotante y las comparaciones de tooltip ya usan esos
   pesos.

Puedes crear varias escalas (por ejemplo una para PvE y otra para PvP) y
cambiar cuál está activa desde el mismo panel. **Las escalas se guardan
por personaje** — cada personaje tiene su propia lista, no se comparten
entre toda la cuenta.

¿Le pusiste mal el nombre a una escala? En la pestaña "Escalas de
Personaje", cada tarjeta tiene su propio botón "Renombrar" — al hacer
clic aparece el textbox para escribir el nombre nuevo (el botón pasa a
decir "Cancelar" si te arrepientes), y con Enter se renombra esa escala
sin perder ninguno de sus pesos.

Además del dropdown "Escala activa", en `/stm config` aparece una lista
con una tarjeta por cada escala guardada (resumen de sus pesos + botones
"Usar esta escala" / "Eliminar"), para verlas todas de un vistazo.

### Los 7 pesos

| Campo | Qué es | Dónde se usa |
|---|---|---|
| Stat principal (Agility/Strength/Intellect, según tu clase) | El stat primario de tu personaje | Solo en la comparación de tooltip |
| Crit | Crítico | Panel (Personaje/Recomendado) + tooltip |
| Haste | Aceleración | Panel (Personaje/Recomendado) + tooltip |
| Mastery | Maestría | Panel (Personaje/Recomendado) + tooltip |
| Versatility | Versatilidad | Panel (Personaje/Recomendado) + tooltip |
| Weapon DPS | DPS del arma principal | Solo en la comparación de tooltip |
| Off Hand Weapon DPS | DPS del arma secundaria (offhand) | Solo en la comparación de tooltip |

Un peso en `0` simplemente no participa — así cada clase/spec solo carga
lo que le aplica (por ejemplo, una clase que no usa arma en el offhand
deja ese campo en 0).

**Nota sobre Weapon DPS**: a diferencia de los demás stats, no hay una
función oficial de Blizzard que devuelva esto directo — se calcula
leyendo el daño mínimo/máximo y la velocidad del arma desde su tooltip
(igual que hace Pawn, pero solo para estos 3 números). Es la parte menos
probada del addon; si una comparación de arma se ve rara, revisa con
`/stm debugitem`.

### El panel flotante

Muestra, para cada stat, el valor **Personaje** (en vivo, se actualiza
solo con cambios de equipo, pociones, buffs, procs) y el **Recomendado**
— el total de rating secundario que ya tienes, repartido
proporcionalmente según tus pesos. Te dice "así deberías estar
distribuido según tus prioridades", sin inventar ningún número externo.

El total que se reparte para "Recomendado" queda **fijo** mientras sigas
con la misma escala activa — no se recalcula cada vez que cambias de
equipo. Se recalcula solo si cambias de escala activa, o a mano con
`/stm recalc` si quieres actualizar el objetivo después de una mejora
real de equipo.

#### Barras de poder (opcional)

En vez de texto, Crit/Haste/Mastery/Versatility se pueden mostrar como
barras que se llenan según Personaje ÷ Recomendado — actívalo con
**Barras de poder** en `/stm config`. Cada barra tiene un destello suave
en el borde de avance, con el color propio de ese stat. Si te pasas del
100%, la barra se queda llena y una franja más intensa marca la vuelta
extra, con un contador `×N` al lado. La separación entre una barra y la
siguiente se ajusta con **Espacio entre barras**, independiente del
espaciado entre líneas. El **alto de las barras** y el **espacio
etiqueta-barra** también tienen su propio slider cada uno. El ancho de
las barras sigue al ancho general del panel (**Ancho**) — no tienen un
slider separado, ya que sería lo mismo dos veces.

Con **Texto dentro de la barra** activo, la etiqueta se dibuja encima de
la barra misma en vez de en su propia fila arriba (ahorra espacio
vertical) — en ese modo el texto siempre lleva contorno, sin importar
"Contorno de fuente", para seguir leyéndose bien pase lo que pase con el
color de fondo.

La etiqueta de cada barra secundaria va en **dos partes independientes**:
el lado Personaje (izquierda, ej. "Crit: 620 29%") sigue la opción
**Alineación de texto**, igual que las filas de texto plano — no se
mueve con el ancho de la barra. El lado Recomendado (derecha, ej.
"/ 980 33%") siempre está pegado al borde derecho y se mueve junto con
el ancho real de la barra.

**Primary Stat, Leech y Avoidance** también se muestran como barra con
"Barras de poder" activo, pero **estáticas** — siempre llenas al 100%
con su propio color, sin franja de overflow ni comparación, solo el
valor real en vivo como texto.

**Item Level** también es una barra, pero la única con **relleno real y
color dinámico**: el relleno es tu ilvl equipado ÷ el máximo alcanzable
de la temporada actual, y el color se degrada sin saltos entre blanco →
azul → morado → naranja según en qué racha de mejora (Veterano, Campeón,
Mítico) caería ese ilvl — los mismos colores que usa el juego para
objetos Raro/Épico/Legendario. Su etiqueta muestra los tres números:
equipado / general / máximo de temporada (ej. "Item Level: 300 / 305 /
344"). Estos números se actualizan a mano cada temporada, porque
Blizzard no expone ninguna función para sacarlos automáticamente — ni
siquiera librerías grandes como LibOpenRaid (la que usa Details)
confían en una. `/stm debugseason` imprime el ID de temporada detectado,
por si en el futuro se agrega soporte para varias temporadas a la vez.

- Se arrastra libremente (a menos que lo bloquees).
- Totalmente personalizable — ver la sección de Configuración más abajo.
- Los nombres de los stats siempre aparecen en inglés (Crit, Haste,
  Mastery, Versatility, Primary Stat, Item Level, Leech, Avoidance), sin
  importar el idioma del menú — son los mismos términos que usan
  SimC/Raidbots.
- **Leech y Avoidance** (stats terciarios) solo muestran el valor
  Personaje — no tienen Recomendado, porque no comparten el presupuesto
  de rating de los 4 secundarios (son tiradas extra opcionales, no
  siempre presentes en el equipo).

### Panel de personaje nativo (tecla `C`)

Al pasar el mouse sobre Crítico, Aceleración, Maestría o Versatilidad en
el panel de personaje, aparece una línea `Optimo: <numero> (<porcentaje>%)`
en el tooltip, con el mismo cálculo que el panel flotante.

Funciona tanto con el panel nativo de Blizzard como con el de **GW2_UI**
(detecta cuál está activo automáticamente). La línea se reafirma sola
mientras el mouse siga encima, para que no desaparezca si el panel se
redibuja mientras lo tienes abierto.

### Comparación de equipo (tooltip de objetos)

Pasa el mouse sobre cualquier objeto — en bolsas, un vendedor, botín, la
casa de subastas, o un link en el chat — y aparece una línea con el
porcentaje de mejora comparado contra lo que tienes equipado en ese
espacio (ej. "Lock: +14.6%", verde si es mejora, rojo si no), usando la
escala activa. Para anillos y abalorios, compara contra el más débil de
los dos que tienes puestos.

La escala activa siempre aparece en esta línea. Si además quieres ver
otras escalas al mismo tiempo (por ejemplo para comparar un objeto
contra PvE y PvP a la vez, sin tener que cambiar cuál está activa),
marca **"Mostrar en tooltip"** en la tarjeta de esa escala, en la
pestaña "Escalas de Personaje" — aparece como una línea más, debajo de
la de la escala activa.

### Configuración (`/stm config`)

El panel se organiza en pestañas:

- **Escalas**: elegir escala activa, crear una nueva, pegar un
  resultado de Pawn/Raidbots, eliminar la activa, y los 7 campos de
  pesos.
- **Escalas de Personaje**: tarjetas con todas las escalas guardadas de
  este personaje, sus pesos distintos de cero, el toggle "Mostrar en
  tooltip", botones "Usar esta escala" / "Eliminar", y un campo
  "Renombrar" por tarjeta.
- **Panel**: ancho, tipografía (con selector visual), tamaño y contorno
  de fuente, espaciado entre líneas, **espacio entre barras**, **alto de
  las barras**, **espacio etiqueta-barra** (todos independientes del
  espaciado entre líneas), decimales en los porcentajes, alineación del
  texto, diseño en una sola línea, **Barras de poder**, **texto dentro
  de la barra**, **Formato Personaje** y **Formato Recomendado** por
  separado (3 opciones cada uno: Número, Número / Porcentaje,
  Porcentaje — 9 combinaciones posibles), opacidad de fondo, mostrar
  borde, cuándo mostrar el panel, bloquear posición, restablecer
  posición.
- **Qué stats mostrar**: toggle individual por stat, más un botón para
  mostrar/ocultar los 4 secundarios de una vez.
- **Perfiles**: toda la personalización del panel vive en un perfil de
  AceDB — puedes crear perfiles distintos por personaje/spec y cambiar
  entre ellos desde aquí. Las escalas de pesos son compartidas entre
  todos los perfiles. Al final de esta misma pestaña están el idioma
  del menú (español/inglés) y el ícono de minimapa.

### Comandos

| Comando | Qué hace |
|---|---|
| `/stm` o `/stm config` o `/stm m` | Abre el panel de configuración |
| `/stm lock` | Bloquea la posición del panel flotante |
| `/stm unlock` | Desbloquea la posición del panel flotante |
| `/stm status` | Imprime en el chat la escala activa, cuántas escalas hay guardadas, y el perfil actual |
| `/stm recalc` | Recalcula a mano el objetivo de "Recomendado" con tu rating actual |
| `/stm debugitem` | Con un objeto bajo el mouse, imprime las stats crudas que devuelve la API |
| `/stm debugchar` | Con el panel de personaje abierto, imprime los nombres internos de cada fila de stat |
| `/stm debugseason` | Imprime el ID de temporada detectado |
| `/stm errors` (alias `/stm bugs`) | Abre una ventana con los últimos 10 errores de Lua, en un cuadro de texto seleccionable. Necesita `!BugGrabber` instalado (viene junto con BugSack) |

`/statsmythic` también funciona como alias completo de `/stm`.

### Compatibilidad

- **GW2_UI**: soportado — el panel de personaje detecta si GW2_UI
  reemplazó el panel nativo y engancha ahí en vez de (o además de)
  Blizzard.
- **BlizzMove, ElvUI, Pawn, Stats+**: no hay integración directa, pero
  tampoco hay conflictos conocidos. El único cuidado tomado fue evitar
  el comando `/stats`, que ya usa Stats+.

### Limitaciones conocidas

- El porcentaje "Recomendado/Óptimo" para **Maestría** es una
  aproximación (se calcula proporcionalmente a tu propia relación
  rating→porcentaje) porque Maestría tiene un valor base que no depende
  del rating, sin forma de aislarlo por API.
- **Weapon DPS / Off Hand Weapon DPS** se calculan leyendo el tooltip
  del arma (no hay función oficial para esto) — puede fallar en items
  con formato de tooltip poco común.
- StatsMythic es un addon gratuito e independiente, sin afiliación ni
  respaldo de Blizzard Entertainment, y nunca se monetiza.
