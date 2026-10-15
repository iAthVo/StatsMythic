--[[ StatsMythic · Panel.lua
The floating stat panel: plain list, one-line, and "Power bars" layouts.
© 2026 TavoD_Gus_KrG · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

local Panel = {}
ns.Panel = Panel

-- Stat names always show in English, regardless of menu/UI language
-- (Config.lua's "uiLocale" only affects config labels, never these) -- they
-- match the terms players already see in SimC/Raidbots output and the
-- character pane's combat ratings.
-- Los nombres de los stats siempre se muestran en ingles, sin importar el
-- idioma del menu (el "uiLocale" de Config.lua solo afecta etiquetas de
-- configuracion, nunca estos) -- coinciden con los terminos que ya se ven
-- en SimC/Raidbots y en los ratings de combate del panel de personaje.
local ORDER = { "ilvl", "primary", "crit", "haste", "mastery", "vers", "leech", "avoidance" }
local LABELS = {
	primary = "Primary Stat",
	ilvl = "Item Level",
	crit = "Crit",
	haste = "Haste",
	mastery = "Mastery",
	vers = "Versatility",
	leech = "Leech",
	avoidance = "Avoidance",
}

-- Tertiary stats (Leech/Avoidance) -- Character-only, no Recommended column
-- (see PlayerStats:GetTertiaryActuals for why).
-- Stats terciarios (Leech/Avoidance) -- solo Personaje, sin columna
-- Recomendado (ver PlayerStats:GetTertiaryActuals para el motivo).
local TERTIARY_KEYS = { leech = true, avoidance = true }

-- One distinguishable color per stat -- not an official Blizzard standard,
-- just a clean, consistent palette for this addon's own display.
-- Un color distinguible por stat -- no es un estandar oficial de Blizzard,
-- solo una paleta limpia y consistente para la presentacion propia de este
-- addon.
local COLORS = {
	primary = { 0.95, 0.82, 0.10 },
	ilvl = { 0.80, 0.80, 0.80 },
	crit = { 0.90, 0.30, 0.20 },
	haste = { 0.25, 0.65, 0.90 },
	mastery = { 0.65, 0.35, 0.80 },
	vers = { 0.30, 0.75, 0.35 },
	leech = { 0.85, 0.40, 0.60 },
	avoidance = { 0.90, 0.55, 0.15 },
}

-- Custom icon badges per stat (own art, no Blizzard icon exists for these
-- abstract stats -- confirmed by research: Stats+/Pawn only use text, and
-- the only addon that draws icons for them, GW2_UI, ships its own texture
-- too). Path built from ADDON_NAME so it keeps working under any folder
-- name (StatsMythic, StatsMythic_Beta, ...).
-- Insignias propias por stat (arte propio, no existe icono de Blizzard
-- para estos stats abstractos -- confirmado por investigacion: Stats+/
-- Pawn solo usan texto, y el unico addon que dibuja iconos para ellos,
-- GW2_UI, tambien usa una textura propia). Ruta armada con ADDON_NAME
-- para que siga funcionando bajo cualquier nombre de carpeta
-- (StatsMythic, StatsMythic_Beta, ...).
local ICON_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\Icon\\"
-- Filenames updated when the user swapped in a new icon set without the
-- old art's baked-in glow/shine -- the new files are named "...@3x@3x.png"
-- (double suffix), not "...@3x.png" like the originals.
-- Nombres de archivo actualizados cuando el usuario cambio el set de
-- iconos por uno nuevo sin el brillo/destello que traia pintado el arte
-- anterior -- los archivos nuevos se llaman "...@3x@3x.png" (sufijo
-- doble), no "...@3x.png" como los originales.
local ICONS = {
	primary = ICON_PATH .. "StatPrincipal@3x@3x.png",
	ilvl = ICON_PATH .. "ItemLevel@3x@3x.png",
	crit = ICON_PATH .. "Critical@3x@3x.png",
	haste = ICON_PATH .. "Celeridad@3x@3x.png",
	mastery = ICON_PATH .. "Maestria@3x@3x.png",
	vers = ICON_PATH .. "Versa@3x@3x.png",
	leech = ICON_PATH .. "Leech@3x@3x.png",
	avoidance = ICON_PATH .. "Aviodance@3x@3x.png", -- filename typo kept on purpose, matches the actual file / typo del nombre de archivo conservado a proposito, coincide con el archivo real
}

-- Colorblind-safe swaps for the two stats most likely to clash (Crit's red
-- vs. Versatility's green, the classic red/green pair) -- the other two
-- stats (Haste=blue, Mastery=purple) already read apart from both, so they
-- stay the same in either mode.
-- Alternativas a prueba de daltonismo para los dos stats que mas pueden
-- confundirse (el rojo de Crit contra el verde de Versatility, el clasico
-- par rojo/verde) -- los otros dos (Haste=azul, Mastery=morado) ya se leen
-- distinto de ambos, asi que quedan igual en los dos modos.
local COLORBLIND_OVERRIDES = {
	crit = { 0.90, 0.55, 0.15 }, -- orange instead of red / naranja en vez de rojo
	vers = { 0.25, 0.55, 0.95 }, -- blue instead of green / azul en vez de verde
}

local function GetStatColor(key, panel)
	if panel and panel.barColorblind and COLORBLIND_OVERRIDES[key] then
		return COLORBLIND_OVERRIDES[key]
	end
	return COLORS[key]
end

-- Per-preset look: border color/alpha (a static, always-visible trait --
-- not just the glow, which only flashes briefly during the twinkle and is
-- too subtle on its own to read as "a different style"), how strong the
-- glow is, how big the spark itself renders, and whether the bar gets the
-- rounded-corner mask (curve = true).
-- Aspecto por preset: color/alpha del borde (un rasgo estatico, siempre
-- visible -- no solo el destello, que nomas destella un momento durante el
-- titileo y es demasiado sutil por si solo para notarse como "un estilo
-- distinto"), que tan fuerte es el destello, que tan grande se dibuja el
-- destello mismo, y si la barra lleva la mascara de esquinas redondeadas
-- (curve = true).
-- NEON, CURVE and CURVE_NEON's own track border is transparent on
-- purpose -- the user wants these effects on the BAR itself only (fill
-- color + glow + rounded corners), never drawn as a square outline
-- around the track. MINIMAL's was already transparent for the same
-- underlying reason. CLASSIC is the only preset that still draws its own
-- border this way; the rounded presets rely on "Borde decorativo"
-- (which itself now follows the curve shape, see decorBorderFill above)
-- for any visible delimitation instead.
-- El borde propio de la barra en NEON, CURVE y CURVE_NEON es
-- transparente a proposito -- el usuario quiere estos efectos solo en la
-- BARRA misma (color de relleno + destello + esquinas redondeadas),
-- nunca dibujados como un contorno cuadrado alrededor de la barra. El de
-- MINIMAL ya era transparente por la misma razon de fondo. CLASSIC es el
-- unico preset que sigue dibujando su propio borde asi; los presets
-- redondeados dependen de "Borde decorativo" (que ahora tambien sigue la
-- forma de curva, ver decorBorderFill arriba) para cualquier
-- delimitacion visible en su lugar.
local STYLE_PRESETS = {
	CLASSIC = { glowBoost = 1.0, sparkScale = 1.0, borderColor = { 0, 0, 0, 0.8 } },
	NEON = { glowBoost = 2.2, sparkScale = 1.5, borderColor = { 0, 0, 0, 0 } },
	MINIMAL = { glowBoost = 0.6, sparkScale = 0.7, borderColor = { 0, 0, 0, 0 } },
	CURVE = { glowBoost = 1.0, sparkScale = 0.85, borderColor = { 0, 0, 0, 0 }, curve = true },
	CURVE_NEON = { glowBoost = 2.2, sparkScale = 1.3, borderColor = { 0, 0, 0, 0 }, curve = true },
}

-- Rounded-corner mask (white rounded-rect on transparent, stretched over
-- the bar's own bounds via CreateMaskTexture+AddMaskTexture) -- real WoW
-- technique, confirmed against BetterBlizzPlates'
-- prd.lua:ApplyPRDBarMask and Details' Libs/DF/mixins.lua:CreateTextureMask,
-- both of which mask a StatusBar's own fill texture the same way. The
-- corner radius is modest (30% of the mask's height) -- a first version
-- used a full capsule (radius = 50%, fully round ends) and the user
-- didn't like the look, asked for a smaller radius like a typical
-- rounded-rect instead (renamed "Pildora" -> "Curva" to match). A single
-- stretched mask (not a 3-piece proportional cap) -- looks right at
-- normal bar sizes; at extreme width-vs-height ratios the corners read
-- as slightly less round than the mask's own proportions (accepted
-- tradeoff, not a bug).
-- Mascara de esquinas redondeadas (rectangulo blanco de esquinas
-- redondeadas sobre transparente, estirada sobre el area de la barra via
-- CreateMaskTexture+AddMaskTexture) -- tecnica real de WoW, confirmada
-- contra prd.lua:ApplyPRDBarMask de BetterBlizzPlates y
-- Libs/DF/mixins.lua:CreateTextureMask de Details, las dos enmascaran la
-- textura de relleno de una StatusBar de la misma forma. El radio es
-- moderado (30% del alto de la mascara) -- una primera version usaba una
-- capsula completa (radio = 50%, puntas totalmente redondas) y al
-- usuario no le gusto como se veia, pidio un radio mas chico como un
-- rectangulo de esquinas redondeadas comun (se renombro "Pildora" ->
-- "Curva" para que haga juego). Es una sola mascara estirada (no 3
-- piezas proporcionales) -- se ve bien a tamaños normales de barra; en
-- relaciones de ancho-vs-alto muy extremas las esquinas se notan un poco
-- menos redondeadas que las proporciones propias de la mascara (tradeoff
-- aceptado, no un bug).
local CURVE_MASK_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\Mask\\CurveMask.png"

-- Ring (donut) version of the same shape, used ONLY for the decorative
-- border -- a solid CURVE_MASK_PATH shape there would fill the bar's
-- whole interior with the border color, bleeding through now that the
-- track's own backdrop is fully transparent (see "Fondo de Barra"
-- below). This ring is hollow in the middle (built as outer rounded-rect
-- minus a smaller inner one, even-odd fill rule), so only a thin stripe
-- near decorBorder's own edge ever shows.
-- Version anillo (dona) de la misma forma, usada SOLO para el borde
-- decorativo -- una forma solida de CURVE_MASK_PATH ahi rellenaria todo
-- el interior de la barra con el color del borde, mostrandose a traves
-- ahora que el fondo propio de la barra es totalmente transparente (ver
-- "Fondo de Barra" mas abajo). Este anillo esta hueco en el medio
-- (armado como un rectangulo redondeado exterior menos uno interior mas
-- chico, regla de relleno par-impar), asi que solo se ve una franja
-- delgada cerca del borde propio de decorBorder.
local CURVE_RING_MASK_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\Mask\\CurveRingMask.png"

-- Dedicated mask for the overflow stripe, canvas-tuned for its own
-- typical aspect ratio instead of reusing CURVE_MASK_PATH (tuned for the
-- FULL track, which is usually much wider than an overflow stripe ever
-- is). Reusing the track's mask on something consistently narrower than
-- what it was tuned for flattened the rounding more than intended (the
-- same non-uniform-stretch effect as before, just on a different
-- element) -- a separate, narrower-tuned canvas keeps it closer to a
-- true 50% look across the overflow widths that actually come up.
-- Mascara dedicada para la franja de overflow, con el lienzo ajustado a
-- su propia proporcion tipica en vez de reusar CURVE_MASK_PATH (ajustada
-- para TODA la barra, que suele ser mucho mas ancha que cualquier franja
-- de overflow). Reusar la mascara de la barra sobre algo
-- consistentemente mas angosto de lo que fue pensada aplastaba el
-- redondeo mas de lo esperado (el mismo efecto de estiramiento no
-- uniforme de antes, solo que en otro elemento) -- un lienzo aparte, mas
-- angosto, lo mantiene mas cerca de un 50% real en los anchos de
-- overflow que de verdad se dan.
local OVERFLOW_CURVE_MASK_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\Mask\\OverflowCurveMask.png"

local function GetStylePreset(panel)
	return STYLE_PRESETS[panel.barStyle] or STYLE_PRESETS.CLASSIC
end

-- RAID_CLASS_COLORS is a real Blizzard global (the same table the default
-- UI uses for class-colored names/health bars).
-- RAID_CLASS_COLORS es un global real de Blizzard (la misma tabla que usa
-- la UI nativa para nombres/barras de vida con color de clase).
local function GetClassColor()
	local _, classFile = UnitClass("player")
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then
		return c.r, c.g, c.b
	end
	return 0.6, 0.6, 0.6
end

-- Decorative border's own color, same "pick one or fall back" pattern as
-- "Fondo de Barra" (GetClassColor above) -- panel.barDecorBorderColor is
-- nil until the player actually picks something in Config.lua, so this
-- is what makes it the old fixed gold by default instead of static.
-- Color propio del borde decorativo, mismo patron de "elige uno o cae al
-- default" que "Fondo de Barra" (GetClassColor arriba) --
-- panel.barDecorBorderColor es nil hasta que el jugador elige algo de
-- verdad en Config.lua, asi que esto es lo que lo deja en el dorado fijo
-- de antes por defecto en vez de ser estatico.
local DEFAULT_DECOR_BORDER_COLOR = { 0.78, 0.65, 0.28 }
local function GetDecorBorderColor(panel)
	local c = panel.barDecorBorderColor
	if c then
		return c[1], c[2], c[3]
	end
	return DEFAULT_DECOR_BORDER_COLOR[1], DEFAULT_DECOR_BORDER_COLOR[2], DEFAULT_DECOR_BORDER_COLOR[3]
end

-- Exposed so Config.lua can reuse the same stat names/colors in the "which
-- stats to show" checkboxes instead of duplicating the strings.
-- Expuesto para que Config.lua reuse los mismos nombres/colores de stat en
-- los checkboxes de "que stats mostrar" en vez de duplicar los strings.
Panel.ORDER = ORDER
Panel.LABELS = LABELS
Panel.COLORS = COLORS

-- The only 4 stats with both Character AND Recommended values (see
-- PlayerStats:GetExpected) -- the only ones that make sense as a
-- Character/Recommended bar with an overflow stripe.
-- Los unicos 4 stats con valor Personaje Y Recomendado (ver
-- PlayerStats:GetExpected) -- los unicos que tiene sentido mostrar como
-- barra Personaje/Recomendado con franja de overflow.
local BAR_KEYS = { crit = true, haste = true, mastery = true, vers = true }

-- Primary Stat/Leech/Avoidance have no Recommended value to compare
-- against (Primary doesn't share the 4 secondaries' budget; Leech/
-- Avoidance are optional extra rolls, see TERTIARY_KEYS) -- in bar mode
-- they show as a static bar, always full at 100%, purely cosmetic: the
-- live value goes as text on top, with no overflow stripe or Recommended
-- half.
-- Primary Stat/Leech/Avoidance no tienen un valor Recomendado contra el
-- cual compararse (Primary no comparte presupuesto con los 4 secundarios;
-- Leech/Avoidance son tiradas extra opcionales, ver TERTIARY_KEYS) -- en
-- modo barras se muestran como una barra estatica, siempre llena al 100%,
-- puramente cosmetica: el valor en vivo va como texto encima, sin franja
-- de overflow ni mitad "Recomendado".
local STATIC_BAR_KEYS = { primary = true, leech = true, avoidance = true }

-- Item Level also has no Recommended value, but unlike Primary Stat it
-- DOES have a real fill (equipped ÷ season max) -- its own third kind
-- ("gauge"): a dynamic fill with no comparison or overflow stripe. Its
-- color is dynamic too (see ComputeIlvlColor), not COLORS.ilvl's fixed one.
-- Item Level tampoco tiene un valor Recomendado, pero a diferencia de
-- Primary Stat SI tiene un relleno real (equipado ÷ maximo de temporada)
-- -- su propio tercer tipo ("gauge"): relleno dinamico, sin comparacion ni
-- franja de overflow. Su color tambien es dinamico (ver ComputeIlvlColor),
-- no el fijo de COLORS.ilvl.
local GAUGE_BAR_KEYS = { ilvl = true }

local function IsBarKey(key)
	return BAR_KEYS[key] or STATIC_BAR_KEYS[key] or GAUGE_BAR_KEYS[key]
end

-- Rows with no labelExpected/overflowBar/overflowSpark/lapText -- just the
-- Character side and its bar (static or gauge rows).
-- Filas sin labelExpected/overflowBar/overflowSpark/lapText -- solo el
-- lado Personaje y su barra (filas estaticas o "gauge").
local function IsSimpleBarKey(key)
	return STATIC_BAR_KEYS[key] or GAUGE_BAR_KEYS[key]
end

local PADDING = 8
local BAR_HEIGHT = 14
local BAR_LABEL_HEIGHT = 14
local ICON_GAP = 6 -- space between a bar and its icon, in icon mode / espacio entre una barra y su icono, en modo icono

-- The badge art has a lot of transparent padding around the actual emblem
-- (by design, so it reads well at any size) -- sized 1:1 with barHeight,
-- the visible emblem shrinks to a blur at normal bar heights (e.g. 20px),
-- so it's drawn oversized relative to the bar instead.
-- El arte de la insignia tiene mucho margen transparente alrededor del
-- emblema real (a proposito, para que se vea bien a cualquier tamaño) -- a
-- 1:1 con barHeight, el emblema visible se reduce a una mancha borrosa en
-- alturas de barra normales (ej. 20px), asi que se dibuja sobredimensionado
-- respecto a la barra en vez de eso.
local function GetIconSize(barHeight)
	return math.max(barHeight * 1.7, 20)
end

local frame
local rows = {} -- per-stat FontStrings, used in the default (list) layout / FontStrings por stat, usados en el layout de lista
local combinedRow -- single FontString, used when oneLineLayout is on / un solo FontString, usado con oneLineLayout activo
-- [key] = { labelActual, labelExpected, track, spark, overflowBar, overflowSpark, lapText, static }
-- Used when barMode is on -- labelExpected/overflowBar/overflowSpark/
-- lapText are nil for simple rows (static or gauge), which have no
-- Recommended value to compare against.
-- Se usa cuando barMode esta activo -- labelExpected/overflowBar/
-- overflowSpark/lapText son nil en filas simples (estaticas o "gauge"),
-- que no tienen un valor Recomendado contra el cual compararse.
local barRows = {}

local function ToHex(c)
	return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function ColorWrap(key, text)
	local c = COLORS[key]
	if not c then
		return text
	end
	return "|cff" .. ToHex(c) .. text .. "|r"
end

local function CreateRows()
	for _, key in ipairs(ORDER) do
		local fs = frame:CreateFontString(nil, "OVERLAY")
		rows[key] = fs
	end
	combinedRow = frame:CreateFontString(nil, "OVERLAY")
end

-- Blends a stat color toward a warm tone (like sunset light), for the bars'
-- glow -- never pure white. mix = 0 keeps the stat color pure, mix = 1 is
-- pure warm tone.
-- Mezcla un color de stat hacia un tono tibio (como la luz de un atardecer),
-- para el destello de las barras -- nunca blanco puro. mix = 0 deja el
-- color del stat puro, mix = 1 da el tono tibio puro.
local WARM_R, WARM_G, WARM_B = 1.0, 0.86, 0.68
local function WarmTint(c, mix)
	mix = mix or 0.35
	return c[1] * (1 - mix) + WARM_R * mix,
		c[2] * (1 - mix) + WARM_G * mix,
		c[3] * (1 - mix) + WARM_B * mix
end

-- A more intense version of a stat color -- pushes each channel closer to
-- its max (never past 1.0), for the overflow stripe: it needs to read
-- stronger than the base bar while staying the stat's own color (unlike
-- WarmTint, which blends toward a warm tone -- this only saturates/
-- brightens the same color).
-- Version mas intensa de un color de stat -- empuja cada canal mas cerca de
-- su maximo (sin pasar de 1.0), para la franja de overflow: tiene que
-- notarse mas fuerte que la barra base sin dejar de ser el color propio del
-- stat (a diferencia de WarmTint, que mezcla hacia un tono calido -- esto
-- solo satura/aclara el mismo color).
local function IntensifyColor(c, boost)
	boost = boost or 1.5
	return math.min(c[1] * boost, 1), math.min(c[2] * boost, 1), math.min(c[3] * boost, 1)
end

-- Linear interpolation between two colors -- t=0 gives pure c1, t=1 gives
-- pure c2.
-- Interpolacion lineal entre dos colores -- t=0 da c1 puro, t=1 da c2 puro.
local function LerpColor(c1, c2, t)
	return c1[1] + (c2[1] - c1[1]) * t,
		c1[2] + (c2[2] - c1[2]) * t,
		c1[3] + (c2[3] - c1[3]) * t
end

-- ITEM_QUALITY_COLORS is a real Blizzard global table (confirmed in use in
-- several installed addons, e.g. Details/window_end_of_run.lua's direct
-- "rarityColor.r/g/b") -- the same colors the game uses for white/blue/
-- purple/orange item quality, so the RGB values are never invented here.
-- ITEM_QUALITY_COLORS es una tabla global real de Blizzard (confirmada en
-- uso en varios addons instalados, ej. el "rarityColor.r/g/b" directo de
-- Details/window_end_of_run.lua) -- los mismos colores que usa el juego
-- para blanco/azul/morado/naranja en la calidad de los objetos, asi que el
-- RGB nunca se inventa aqui.
local function QualityColor(quality)
	local c = ITEM_QUALITY_COLORS[quality]
	return { c.r, c.g, c.b }
end

-- Item Level bar's color, blended smoothly white->blue->purple->orange by
-- current ilvl -- no hard jumps (each segment linearly interpolates
-- between the two colors of the floors that bound it, from seasonData --
-- see PlayerStats:GetSeasonIlvlData).
-- Color de la barra de Item Level, degradado sin saltos entre
-- blanco->azul->morado->naranja segun el ilvl actual (cada tramo interpola
-- de forma lineal entre los dos colores de los pisos que lo delimitan,
-- segun seasonData -- ver PlayerStats:GetSeasonIlvlData).
local function ComputeIlvlColor(ilvl, seasonData)
	local white = QualityColor(Enum.ItemQuality.Common)
	local blue = QualityColor(Enum.ItemQuality.Rare)
	local purple = QualityColor(Enum.ItemQuality.Epic)
	local orange = QualityColor(Enum.ItemQuality.Legendary)

	if ilvl <= 0 then
		return white[1], white[2], white[3]
	elseif ilvl < seasonData.veteran then
		return LerpColor(white, blue, ilvl / seasonData.veteran)
	elseif ilvl < seasonData.champion then
		return LerpColor(blue, purple, (ilvl - seasonData.veteran) / (seasonData.champion - seasonData.veteran))
	elseif ilvl < seasonData.myth then
		return LerpColor(purple, orange, (ilvl - seasonData.champion) / (seasonData.myth - seasonData.champion))
	else
		return orange[1], orange[2], orange[3]
	end
end

-- A glow (ADD-blend texture + looping Alpha AnimationGroup) anchored to a
-- StatusBar's leading edge -- spark texture confirmed real
-- (Interface\CastingBar\UI-CastingBar-Spark, already used with
-- SetBlendMode "ADD" in installed addons, e.g. WorldQuestTracker's split
-- bar). CreateAnimationGroup works directly on a texture, no separate
-- frame needed (confirmed in WorldQuestTracker_CreateWidgets.lua and
-- Details/frames/window_main.lua).
-- Un destello (textura ADD + AnimationGroup de Alpha en loop) anclado al
-- borde de avance de un StatusBar -- textura confirmada real
-- (Interface\CastingBar\UI-CastingBar-Spark, ya usada con SetBlendMode
-- "ADD" en addons instalados, ej. el split bar de WorldQuestTracker).
-- CreateAnimationGroup funciona directo sobre una textura, sin frame
-- aparte (confirmado en WorldQuestTracker_CreateWidgets.lua y
-- Details/frames/window_main.lua).
local function CreateSpark(statusBar, c, fromAlpha, toAlpha, duration)
	local spark = statusBar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
	spark:SetBlendMode("ADD")
	spark:SetSize(16, BAR_HEIGHT + 8)
	spark:SetVertexColor(WarmTint(c, 0.35))
	spark:SetPoint("CENTER", statusBar:GetStatusBarTexture(), "RIGHT", 0, 0)

	-- "Titilante": 4 chained Alpha steps of uneven duration (SetOrder,
	-- confirmed real sequential-animation pattern -- e.g.
	-- WorldQuestTracker_CreateWidgets.lua:436-447's In/On/Out flash)
	-- instead of one smooth up/down pulse -- reads as an irregular
	-- twinkle rather than a steady breathing glow.
	-- "Titilante": 4 pasos de Alpha encadenados de duracion dispareja
	-- (SetOrder, patron real de animaciones secuenciales confirmado --
	-- ej. el flash In/On/Out de WorldQuestTracker_CreateWidgets.lua:
	-- 436-447) en vez de un solo pulso suave de ida y vuelta -- se lee
	-- como un titileo irregular en vez de un brillo constante que
	-- respira.
	local animGroup = spark:CreateAnimationGroup()
	animGroup:SetLooping("REPEAT")

	local mid = fromAlpha + (toAlpha - fromAlpha) * 0.3
	local steps = {
		{ from = fromAlpha, to = toAlpha, dur = duration * 0.3 },
		{ from = toAlpha, to = mid, dur = duration * 0.15 },
		{ from = mid, to = toAlpha, dur = duration * 0.2 },
		{ from = toAlpha, to = fromAlpha, dur = duration * 0.35 },
	}
	for i, step in ipairs(steps) do
		local anim = animGroup:CreateAnimation("Alpha")
		anim:SetFromAlpha(step.from)
		anim:SetToAlpha(step.to)
		anim:SetDuration(step.dur)
		anim:SetOrder(i)
	end
	animGroup:Play()

	return spark
end

-- "Power bars": one StatusBar per stat, with a glow at its leading edge.
-- The 4 secondaries (dynamic) get a second stripe (overflowBar) shown only
-- past 100%, marking the extra lap with its own, faster/more intense
-- glow. Static rows (Primary/Leech/Avoidance) have none of that -- always
-- full. Item Level (gauge) has a real fill but no overflow either.
-- "Barras de poder": un StatusBar por stat, con un destello en su borde de
-- avance. Los 4 secundarios (dinamicos) llevan ademas una segunda franja
-- (overflowBar), mostrada solo al pasar el 100%, que marca la vuelta extra
-- con su propio destello, mas rapido/intenso. Las filas estaticas
-- (Primary/Leech/Avoidance) no tienen nada de eso -- siempre llenas. Item
-- Level ("gauge") tiene relleno real pero tampoco overflow.
local function CreateBarRows()
	for _, key in ipairs({ "primary", "ilvl", "crit", "haste", "mastery", "vers", "leech", "avoidance" }) do
		local c = COLORS[key]
		local isStatic = STATIC_BAR_KEYS[key]
		local isSimple = IsSimpleBarKey(key)
		-- Item Level has no overflow/lap mechanic (STATIC_BAR_KEYS doesn't
		-- either), but unlike Primary/Leech/Avoidance it DOES have a
		-- second value worth pinning to the right -- the season max,
		-- right-aligned the exact same way as the other bars' Recommended
		-- side, so its "/" lands in the same spot instead of following
		-- panel.textAlign like the rest of its text.
		-- Item Level no tiene mecanica de overflow/vuelta (STATIC_BAR_KEYS
		-- tampoco), pero a diferencia de Primary/Leech/Avoidance SI tiene
		-- un segundo valor que vale la pena fijar a la derecha -- el
		-- maximo de temporada, alineado a la derecha exactamente igual que
		-- el lado Recomendado de las demas barras, para que su "/" caiga
		-- en el mismo lugar en vez de seguir panel.textAlign como el resto
		-- de su texto.
		local needsExpectedLabel = not isStatic

		local track = CreateFrame("StatusBar", nil, frame, "BackdropTemplate")
		track:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
		track:SetMinMaxValues(0, 100)
		track:SetValue(isStatic and 100 or 0)
		track:SetStatusBarColor(c[1], c[2], c[3])
		track:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		-- No flat dark panel behind the track anymore -- "Tinte de clase"
		-- (classTint, below) is the only thing that puts color behind the
		-- fill now, conditional on its own toggle. With class tint off and
		-- no decorative border, the empty part of the bar is fully
		-- transparent on purpose -- "Borde decorativo" is what the user
		-- wants to own delimiting the bar's bounds, not a hardcoded
		-- backdrop color.
		-- Ya no hay un panel oscuro plano detras de la barra -- "Tinte de
		-- clase" (classTint, abajo) es lo unico que pone color detras del
		-- relleno ahora, condicionado a su propio toggle. Con el tinte de
		-- clase apagado y sin borde decorativo, la parte vacia de la barra
		-- queda totalmente transparente a proposito -- "Borde decorativo"
		-- es lo que el usuario quiere que se encargue de delimitar los
		-- bordes de la barra, no un color de fondo fijo.
		track:SetBackdropColor(0, 0, 0, 0)
		track:SetBackdropBorderColor(0, 0, 0, 0.8)
		local spark = CreateSpark(track, c, 0.75, 1, 1.3)

		-- Curve mask -- created once per row, only actually applied (see
		-- ApplyAppearance) when panel.barStyle is CURVE/CURVE_NEON. Stays
		-- unattached otherwise, so non-curve styles never pay for it.
		-- Mascara de curva -- creada una vez por fila, solo se aplica de
		-- verdad (ver ApplyAppearance) cuando panel.barStyle es CURVE/
		-- CURVE_NEON. Se queda sin usar en los demas estilos.
		local curveMask = track:CreateMaskTexture()
		curveMask:SetTexture(CURVE_MASK_PATH)
		curveMask:SetAllPoints(track)

		-- "Fondo de Barra" wash, BEHIND the fill (BACKGROUND layer,
		-- SetStatusBarTexture's own fill lives on ARTWORK) -- color/alpha
		-- both come from panel.barBgColor/panel.barBgAlpha, applied fresh
		-- in ApplyAppearance (panel.barBgColor falls back to the player's
		-- class color when the player hasn't picked one of their own).
		-- Tinte "Fondo de Barra", DETRAS del relleno (capa BACKGROUND, el
		-- relleno propio de SetStatusBarTexture vive en ARTWORK) --
		-- color/alpha salen de panel.barBgColor/panel.barBgAlpha,
		-- aplicados en ApplyAppearance (panel.barBgColor cae al color de
		-- clase del jugador si todavia no eligio uno propio).
		local classTint = track:CreateTexture(nil, "BACKGROUND")
		classTint:SetAllPoints(track)
		classTint:Hide()

		-- Curve mask for classTint -- always matches the FULL track (never
		-- resized to a fill percentage, unlike curveMask above), since
		-- "Fondo de Barra" is meant to tint the whole empty track, not
		-- just the filled portion. Without this, classTint stayed a
		-- square wash behind an otherwise-rounded CURVE/CURVE_NEON bar,
		-- with its square corners sticking out past the rounded fill.
		-- Mascara de curva para classTint -- siempre coincide con TODA la
		-- barra (nunca se redimensiona a un porcentaje de relleno, a
		-- diferencia de curveMask arriba), ya que "Fondo de Barra" tiene
		-- que teñir toda la barra vacia, no solo la parte llena. Sin esto,
		-- classTint se quedaba como un lavado cuadrado detras de una barra
		-- CURVE/CURVE_NEON ya redondeada, con sus esquinas cuadradas
		-- asomando por fuera del relleno redondeado.
		local classTintCurveMask = track:CreateMaskTexture()
		classTintCurveMask:SetTexture(CURVE_MASK_PATH)
		classTintCurveMask:SetAllPoints(track)

		-- Reference ticks at 25/50/75% -- repositioned in ApplyAppearance
		-- whenever the bar's real width changes.
		-- Marcas de referencia en 25/50/75% -- se reposicionan en
		-- ApplyAppearance cada vez que cambia el ancho real de la barra.
		local ticks = {}
		for i = 1, 3 do
			local tick = track:CreateTexture(nil, "OVERLAY")
			tick:SetColorTexture(0, 0, 0, 0.45)
			tick:SetWidth(1)
			tick:Hide()
			ticks[i] = tick
		end

		-- Decorative border: a second, slightly larger frame with a gold
		-- edge wrapping the track -- shown/hidden as a whole instead of
		-- the plain dark backdrop border, so it reads as an ornamented
		-- frame rather than just a different color. Used as-is (square
		-- BackdropTemplate edge) for CLASSIC/MINIMAL.
		--
		-- CURVE/CURVE_NEON use a different piece instead (decorBorderFill,
		-- below): a thin square edge wouldn't match the bar's rounded
		-- corners, and BackdropTemplate's own edge texture isn't something
		-- this API can mask directly (no public, version-stable way to grab
		-- its internal texture object). Easier and more robust: a plain
		-- Texture, solid gold, masked into the same curve shape as the bar
		-- -- since it's a few px larger than track and sits one frame level
		-- BEHIND it, only that few-px margin peeks out around track's own
		-- rounded edges, reading as a rounded border frame instead of a
		-- square one.
		--
		-- Borde decorativo: un segundo frame, un poco mas grande, con
		-- borde dorado que envuelve la barra -- se muestra/oculta entero
		-- en vez del borde oscuro plano, para que se lea como un marco
		-- ornamentado en vez de solo un color distinto. Se usa tal cual
		-- (borde cuadrado de BackdropTemplate) para CLASSIC/MINIMAL.
		--
		-- CURVE/CURVE_NEON usan otra pieza en su lugar (decorBorderFill,
		-- abajo): un borde cuadrado delgado no haria juego con las
		-- esquinas redondeadas de la barra, y la textura de borde propia
		-- de BackdropTemplate no es algo que esta API pueda enmascarar
		-- directo (no hay forma publica y estable entre versiones de
		-- tomar su textura interna). Mas facil y robusto: una Texture
		-- plana, dorada solida, enmascarada con la misma forma de curva
		-- que la barra -- como es unos px mas grande que track y esta un
		-- nivel de frame por DETRAS de el, solo ese margen de pocos px se
		-- asoma alrededor de los bordes ya redondeados de track,
		-- leyendose como un marco redondeado en vez de uno cuadrado.
		local decorBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		decorBorder:SetFrameLevel(math.max(track:GetFrameLevel() - 1, 0))
		decorBorder:SetBackdrop({
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 2,
		})
		decorBorder:SetBackdropBorderColor(0.78, 0.65, 0.28, 1)
		decorBorder:Hide()

		local decorBorderFill = decorBorder:CreateTexture(nil, "BACKGROUND")
		decorBorderFill:SetColorTexture(0.78, 0.65, 0.28, 1)
		decorBorderFill:SetAllPoints(decorBorder)
		local decorBorderMask = decorBorder:CreateMaskTexture()
		decorBorderMask:SetTexture(CURVE_RING_MASK_PATH)
		decorBorderMask:SetAllPoints(decorBorder)
		decorBorderFill:AddMaskTexture(decorBorderMask)
		decorBorderFill:Hide()

		-- Invisible frame, well above both track AND overflowBar (which
		-- already draws one level above track) -- owns this row's labels,
		-- so the text always shows above the bar's fill color. Labels
		-- used to belong to "frame" (the panel), a lower frame level than
		-- track, so the bar drew over them.
		-- Frame invisible, bien por encima de track Y de overflowBar (que
		-- ya se dibuja un nivel por encima de track) -- dueño de las
		-- etiquetas de esta fila, para que el texto siempre se vea por
		-- encima del relleno de la barra. Antes las etiquetas eran de
		-- "frame" (el panel), un nivel mas bajo que track, asi que la
		-- barra las tapaba.
		local textLayer = CreateFrame("Frame", nil, frame)
		textLayer:SetFrameLevel(track:GetFrameLevel() + 10)

		-- Stat icon (own art, see ICONS) -- alternative to the text label
		-- when panel.barLabelMode == "ICON". Owned by textLayer (same fix
		-- as the labels below) instead of "frame" directly -- a plain
		-- child of "frame" sat at a lower frame level than track and
		-- rendered underneath the bar's own fill, which is why it was
		-- invisible. Anchored left or right per panel.barLabelIconSide
		-- (see Refresh).
		-- Icono del stat (arte propio, ver ICONS) -- alternativa al texto
		-- cuando panel.barLabelMode == "ICON". Pertenece a textLayer (el
		-- mismo arreglo que las etiquetas de abajo) en vez de a "frame"
		-- directamente -- un hijo plano de "frame" quedaba en un nivel de
		-- frame mas bajo que track y se dibujaba debajo del relleno de la
		-- barra, por eso era invisible. Anclado a la izquierda o derecha
		-- segun panel.barLabelIconSide (ver Refresh).
		local icon
		local iconHitbox
		if ICONS[key] then
			icon = textLayer:CreateTexture(nil, "OVERLAY")
			icon:SetTexture(ICONS[key])
			icon:Hide()

			-- Textures can't have scripts (no OnEnter/OnLeave) -- this
			-- invisible Frame sits exactly on top of the icon
			-- (SetAllPoints(icon), re-applied whenever the icon moves/
			-- resizes) purely to catch the mouse and show a tooltip
			-- naming the stat, since icon mode drops the stat's name from
			-- the visible text.
			-- Las Texturas no pueden tener scripts (sin OnEnter/OnLeave) --
			-- este Frame invisible se pone justo encima del icono
			-- (SetAllPoints(icon), reaplicado cada vez que el icono se
			-- mueve/redimensiona) solo para capturar el mouse y mostrar un
			-- tooltip con el nombre del stat, ya que el modo icono le
			-- quita el nombre al texto visible.
			iconHitbox = CreateFrame("Frame", nil, textLayer)
			iconHitbox:EnableMouse(true)
			iconHitbox:Hide()
			iconHitbox:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(LABELS[key])
				GameTooltip:Show()
			end)
			iconHitbox:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end

		-- "Character" side -- spans the full frame width and follows
		-- panel.textAlign (see ApplyAppearance), same as the plain-text
		-- rows. The only side Primary Stat/Leech/Avoidance/Item Level have.
		-- Lado "Personaje" -- ocupa todo el ancho del frame y respeta
		-- panel.textAlign (ver ApplyAppearance), igual que las filas de
		-- texto plano. El unico lado que tienen Primary Stat/Leech/
		-- Avoidance/Item Level.
		local labelActual = textLayer:CreateFontString(nil, "OVERLAY")

		local row = {
			labelActual = labelActual,
			track = track,
			spark = spark,
			static = isStatic,
			classTint = classTint,
			classTintCurveMask = classTintCurveMask,
			ticks = ticks,
			decorBorder = decorBorder,
			decorBorderFill = decorBorderFill,
			icon = icon,
			iconHitbox = iconHitbox,
			curveMask = curveMask,
		}

		if needsExpectedLabel then
			-- "Recommended" side -- always pinned to the right edge,
			-- moves with the bar's real width (see Refresh). For Item
			-- Level this holds "/ <season max>" instead of a comparison
			-- value, but the anchor/justify logic is identical either way.
			-- Lado "Recomendado" -- siempre pegado al borde derecho, se
			-- mueve junto con el ancho real de la barra (ver Refresh). En
			-- Item Level esto contiene "/ <maximo de temporada>" en vez de
			-- un valor de comparacion, pero la logica de ancla/alineacion
			-- es identica en ambos casos.
			row.labelExpected = textLayer:CreateFontString(nil, "OVERLAY")
		end

		if not isSimple then
			-- Overflow stripe -- hidden until the % passes 100. Explicit
			-- frame level above track so its fill always draws on top,
			-- regardless of creation order.
			-- Franja de overflow -- oculta hasta que el % pase de 100.
			-- Nivel de frame explicito por encima de track para que su
			-- relleno se dibuje siempre arriba, sin depender del orden de
			-- creacion.
			local overflowBar = CreateFrame("StatusBar", nil, frame)
			overflowBar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
			overflowBar:SetMinMaxValues(0, 100)
			overflowBar:SetValue(100)
			overflowBar:SetStatusBarColor(IntensifyColor(c, 1.5))
			overflowBar:SetPoint("TOPLEFT", track, "TOPLEFT")
			overflowBar:SetHeight(BAR_HEIGHT)
			overflowBar:SetFrameLevel(track:GetFrameLevel() + 1)
			overflowBar:Hide()
			row.overflowBar = overflowBar
			row.overflowSpark = CreateSpark(overflowBar, c, 0.6, 1, 0.9)

			-- Curve mask for the overflow stripe -- unlike track's own
			-- mask, this one can just stay SetAllPoints forever: overflowBar
			-- always shows its value at 100% of ITS OWN frame, and that
			-- frame's width is already the thing being resized to the
			-- overflow amount (see RefreshDynamicBarRow's
			-- overflowBar:SetWidth call) -- so frame width and fill width
			-- always match here, with no internal StatusBar crop to chase
			-- like track has.
			-- Mascara de curva para la franja de overflow -- a diferencia
			-- de la de track, esta se puede dejar en SetAllPoints para
			-- siempre: overflowBar siempre muestra su valor al 100% de SU
			-- PROPIO frame, y ese frame es lo que ya se redimensiona segun
			-- el sobrante (ver el overflowBar:SetWidth en
			-- RefreshDynamicBarRow) -- asi que el ancho del frame y el del
			-- relleno siempre coinciden aqui, sin el recorte interno de
			-- StatusBar que si hay que perseguir en track.
			local overflowCurveMask = overflowBar:CreateMaskTexture()
			overflowCurveMask:SetTexture(OVERFLOW_CURVE_MASK_PATH)
			overflowCurveMask:SetAllPoints(overflowBar)
			row.overflowCurveMask = overflowCurveMask

			local lapText = frame:CreateFontString(nil, "OVERLAY")
			lapText:Hide()
			row.lapText = lapText
		end

		barRows[key] = row
	end
end

local function HideBarRows()
	for _, row in pairs(barRows) do
		row.labelActual:Hide()
		if row.labelExpected then row.labelExpected:Hide() end
		row.track:Hide()
		if row.overflowBar then row.overflowBar:Hide() end
		if row.lapText then row.lapText:Hide() end
		row.classTint:Hide()
		for _, tick in ipairs(row.ticks) do tick:Hide() end
		row.decorBorder:Hide()
		if row.icon then row.icon:Hide() end
		if row.iconHitbox then row.iconHitbox:Hide() end
	end
end

function Panel:CreateMainFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "StatsMythicPanel", UIParent, "BackdropTemplate")
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")

	frame:SetScript("OnDragStart", function(f)
		if ns.db.profile.panel.locked then
			return
		end
		f:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local point, _, _, x, y = f:GetPoint(1)
		ns.db.profile.panelPosition = { point = point, x = x, y = y }
	end)

	CreateRows()
	CreateBarRows()
	self:ApplyPosition()

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function()
		Panel:UpdateVisibility()
	end)

	return frame
end

-- Re-anchors the panel from db.profile.panelPosition -- called on creation
-- and again whenever the AceDB profile changes (a different profile can
-- have a different saved position).
-- Reancla el panel desde db.profile.panelPosition -- se llama al crearlo y
-- de nuevo cada vez que cambia el perfil de AceDB (un perfil distinto
-- puede tener una posicion guardada distinta).
function Panel:ApplyPosition()
	if not frame then
		return
	end
	local pos = ns.db.profile.panelPosition or { point = "CENTER", x = 0, y = 0 }
	frame:ClearAllPoints()
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

function Panel:ApplyAppearance()
	if not frame then
		return
	end
	local panel = ns.db.profile.panel

	local LSM = LibStub("LibSharedMedia-3.0", true)
	local fontPath = (LSM and LSM:Fetch("font", panel.font)) or STANDARD_TEXT_FONT
	local flags = panel.fontOutline and "OUTLINE" or ""

	for key, fs in pairs(rows) do
		fs:SetFont(fontPath, panel.fontSize or 12, flags)
		fs:SetJustifyH(panel.textAlign or "LEFT")
		local c = COLORS[key]
		if c then
			fs:SetTextColor(c[1], c[2], c[3])
		end
	end
	combinedRow:SetFont(fontPath, panel.fontSize or 12, flags)
	combinedRow:SetJustifyH(panel.textAlign or "LEFT")

	local barHeight = panel.barHeight or BAR_HEIGHT
	local iconSize = GetIconSize(barHeight)
	-- Icon mode draws the icon OUTSIDE the bar (left or right of it, see
	-- Refresh) instead of overlapping its fill -- the track has to shrink
	-- to make room, or the icon would either overlap the bar or spill past
	-- the panel's own edge.
	-- El modo icono dibuja el icono FUERA de la barra (a la izquierda o
	-- derecha, ver Refresh) en vez de encima de su relleno -- la barra
	-- tiene que achicarse para dejarle espacio, o el icono se encimaria con
	-- la barra o se saldria del borde del panel.
	local iconReserved = (panel.barLabelMode == "ICON") and (iconSize + ICON_GAP) or 0
	local barWidth = math.max(panel.width - PADDING * 2 - iconReserved, 10)
	local preset = GetStylePreset(panel)
	-- Fetch BEFORE coloring: SetStatusBarTexture has to run before
	-- SetStatusBarColor or the color doesn't take (confirmed earlier in
	-- this project against TidyPlates_ThreatPlates/Elements/Healthbar.lua).
	-- Buscar la textura ANTES de colorear: SetStatusBarTexture tiene que
	-- correr antes que SetStatusBarColor o el color no toma efecto
	-- (confirmado antes en este proyecto contra
	-- TidyPlates_ThreatPlates/Elements/Healthbar.lua).
	local barTexturePath = (LSM and panel.barTexture and LSM:Fetch("statusbar", panel.barTexture))
		or [[Interface\TargetingFrame\UI-StatusBar]]

	for key, row in pairs(barRows) do
		local sc = GetStatColor(key, panel)

		-- With text inside the bar, OUTLINE is forced regardless of "Font
		-- outline" -- the background color varies a lot (Item Level goes
		-- from white to orange, each stat has its own color), so it needs
		-- fixed contrast to stay readable no matter the bar's current color.
		-- Con el texto dentro de la barra, se fuerza OUTLINE sin importar
		-- "Contorno de fuente" -- el color de fondo varia mucho (Item Level
		-- va de blanco a naranja, cada stat tiene su propio color), asi que
		-- necesita contraste fijo para seguir leyendose bien sin importar
		-- el color actual de la barra.
		local barLabelFlags = panel.barTextInside and "OUTLINE" or flags

		-- "Character" side: follows panel.textAlign, same as the
		-- plain-text rows -- only moves with that option, never with the
		-- bar's width.
		-- Lado "Personaje": respeta panel.textAlign, igual que las filas
		-- de texto plano -- solo se mueve con esa opcion, nunca con el
		-- ancho de la barra.
		row.labelActual:SetFont(fontPath, panel.fontSize or 12, barLabelFlags)
		row.labelActual:SetJustifyH(panel.textAlign or "LEFT")
		if sc then
			row.labelActual:SetTextColor(sc[1], sc[2], sc[3])
		end

		if row.labelExpected then
			-- "Recommended" side: always pinned right -- the anchor in
			-- Refresh() is what makes it move with the bar's real width.
			-- Lado "Recomendado": siempre pegado a la derecha -- el anclaje
			-- en Refresh() es lo que lo hace moverse con el ancho real de
			-- la barra.
			row.labelExpected:SetFont(fontPath, panel.fontSize or 12, barLabelFlags)
			row.labelExpected:SetJustifyH("RIGHT")
			if sc then
				row.labelExpected:SetTextColor(sc[1], sc[2], sc[3])
			end
		end

		row.track:SetStatusBarTexture(barTexturePath)
		row.track:SetWidth(barWidth)
		row.track:SetHeight(barHeight)

		-- Curve mask: re-applied every time (not just once) because
		-- SetStatusBarTexture just above can hand back a fresh texture
		-- object, which would otherwise lose a mask added to the old one
		-- -- same reason BetterBlizzPlates hooks SetStatusBarTexture to
		-- re-add its own bar mask.
		-- Mascara de curva: se vuelve a aplicar cada vez (no solo una vez)
		-- porque SetStatusBarTexture, justo arriba, puede devolver un
		-- objeto de textura nuevo, que de otra forma perderia una mascara
		-- agregada al objeto viejo -- la misma razon por la que
		-- BetterBlizzPlates enganchan SetStatusBarTexture para volver a
		-- agregar su propia mascara de barra.
		if row.curveMask then
			local fillTexture = row.track:GetStatusBarTexture()
			fillTexture:RemoveMaskTexture(row.curveMask)
			if preset.curve then
				fillTexture:AddMaskTexture(row.curveMask)
			end
		end
		-- Item Level's color is dynamic (ComputeIlvlColor, set in
		-- RefreshIlvlBarRow) -- never overwrite it here with the stat's
		-- static color.
		-- El color de Item Level es dinamico (ComputeIlvlColor, se pone en
		-- RefreshIlvlBarRow) -- nunca se sobreescribe aqui con el color
		-- estatico del stat.
		if key ~= "ilvl" and sc then
			row.track:SetStatusBarColor(sc[1], sc[2], sc[3])
		end
		local bc = preset.borderColor or { 0, 0, 0, 0.8 }
		row.track:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])

		-- Glow strength and size per style preset -- Neon/Pill Neon get a
		-- brighter AND bigger spark, Minimal a dimmer/smaller one, on top
		-- of the border color above -- so each preset reads as visibly
		-- different even though the spark itself only flashes briefly.
		-- Fuerza y tamaño del destello segun el preset -- Neon/Pildora Neon
		-- reciben un destello mas brillante Y mas grande, Minimalista uno
		-- mas tenue/chico, ademas del color de borde de arriba -- para que
		-- cada preset se note distinto aunque el destello en si solo
		-- destelle un momento.
		local gr, gg, gb = IntensifyColor({ WarmTint(sc, 0.35) }, preset.glowBoost)
		row.spark:SetVertexColor(gr, gg, gb)
		local sparkScale = preset.sparkScale or 1.0
		row.spark:SetSize(16 * sparkScale, barHeight + 8)

		if row.overflowBar then
			row.overflowBar:SetStatusBarTexture(barTexturePath)
			row.overflowBar:SetHeight(barHeight)
			row.overflowSpark:SetSize(16 * sparkScale, barHeight + 8)

			if row.overflowCurveMask then
				local overflowFillTexture = row.overflowBar:GetStatusBarTexture()
				overflowFillTexture:RemoveMaskTexture(row.overflowCurveMask)
				if preset.curve then
					overflowFillTexture:AddMaskTexture(row.overflowCurveMask)
				end
			end
		end
		if row.lapText then
			row.lapText:SetFont(fontPath, (panel.fontSize or 12) - 1, flags)
		end

		-- "Fondo de Barra" wash behind the fill -- color is whatever the
		-- player picked (panel.barBgColor), or their class color as a
		-- sensible default while they haven't chosen one yet. Alpha is
		-- player-adjustable too (panel.barBgAlpha, "Opacidad de Fondo de
		-- Barras") -- kept low by default so it never competes with the
		-- stat's own color.
		-- Tinte "Fondo de Barra" detras del relleno -- el color es el que
		-- eligio el jugador (panel.barBgColor), o su color de clase como
		-- default razonable mientras no eligio uno. El alpha tambien es
		-- ajustable por el jugador (panel.barBgAlpha, "Opacidad de Fondo
		-- de Barras") -- bajo por defecto para que nunca compita con el
		-- color propio del stat.
		local bg = panel.barBgColor
		if bg then
			row.classTint:SetColorTexture(bg[1], bg[2], bg[3])
		else
			row.classTint:SetColorTexture(GetClassColor())
		end
		row.classTint:SetAlpha(panel.barBgAlpha or 0.18)
		row.classTint:SetShown(panel.barClassTint)

		-- Re-added every time (not just once) for the same reason as
		-- track's own mask: SetColorTexture isn't documented to always
		-- keep a previously-added mask attached, so this plays it safe.
		-- Vuelta a agregar cada vez (no solo una vez) por la misma razon
		-- que la mascara propia de track: SetColorTexture no esta
		-- documentado para garantizar que una mascara ya agregada se
		-- quede pegada, asi que esto juega seguro.
		if row.classTintCurveMask then
			row.classTint:RemoveMaskTexture(row.classTintCurveMask)
			if preset.curve then
				row.classTint:AddMaskTexture(row.classTintCurveMask)
			end
		end

		-- Reference ticks at 25/50/75% of the bar's real width.
		-- Marcas de referencia en 25/50/75% del ancho real de la barra.
		for i, tick in ipairs(row.ticks) do
			tick:ClearAllPoints()
			tick:SetPoint("TOPLEFT", row.track, "TOPLEFT", barWidth * (i * 0.25), 0)
			tick:SetHeight(barHeight)
			tick:SetShown(panel.barTicks)
		end

		-- Decorative border: a few px outset from the track, following it
		-- via anchors (works regardless of where track itself moves).
		-- Borde decorativo: unos pocos px afuera de la barra, siguiendola
		-- via anclas (funciona sin importar a donde se mueva la barra).
		row.decorBorder:ClearAllPoints()
		row.decorBorder:SetPoint("TOPLEFT", row.track, "TOPLEFT", -3, 3)
		row.decorBorder:SetPoint("BOTTOMRIGHT", row.track, "BOTTOMRIGHT", 3, -3)
		row.decorBorder:SetShown(panel.barDecorativeBorder)

		-- CURVE/CURVE_NEON: show the masked gold fill (rounded, matches
		-- the bar), hide the square edge. Everything else: the usual
		-- square edge, no fill.
		-- CURVE/CURVE_NEON: se muestra el relleno dorado enmascarado
		-- (redondeado, hace juego con la barra), se oculta el borde
		-- cuadrado. El resto: el borde cuadrado de siempre, sin relleno.
		local dbr, dbg, dbb = GetDecorBorderColor(panel)
		if preset.curve then
			row.decorBorder:SetBackdropBorderColor(dbr, dbg, dbb, 0)
			row.decorBorderFill:SetColorTexture(dbr, dbg, dbb, 1)
			row.decorBorderFill:Show()
		else
			row.decorBorder:SetBackdropBorderColor(dbr, dbg, dbb, 1)
			row.decorBorderFill:Hide()
		end

		if row.icon then
			row.icon:SetSize(iconSize, iconSize)
			-- No vertex-color dimming anymore -- that was compensating
			-- for the OLD icon set's baked-in glow/shine. The user swapped
			-- in a new set without that effect, so dimming it further
			-- would just wash out art that no longer needs correcting.
			-- Sin atenuado de vertex-color ya -- eso compensaba el brillo/
			-- destello pintado del set de iconos VIEJO. El usuario cambio
			-- a un set nuevo sin ese efecto, asi que seguir atenuandolo
			-- solo deslavaria un arte que ya no necesita corregirse.
			row.icon:SetVertexColor(1, 1, 1)
		end
	end

	frame:SetBackdropColor(0, 0, 0, panel.bgAlpha or 0)
	frame:SetBackdropBorderColor(0, 0, 0, panel.showBorder and 1 or 0)

	frame:SetWidth(panel.width)
end

function Panel:UpdateVisibility()
	if not frame then
		return
	end
	local mode = ns.db.profile.panel.showStatsMode
	local shouldShow = ns.db.profile.panelShown
	if shouldShow then
		if mode == "IN_COMBAT" and not InCombatLockdown() then
			shouldShow = false
		elseif mode == "OUT_OF_COMBAT" and InCombatLockdown() then
			shouldShow = false
		end
	end
	if shouldShow then
		frame:Show()
	else
		frame:Hide()
	end
end

-- Renders one side (Character or Recommended) of a stat per a format code
-- (NUMBER | PERCENT | PERCENT_NUMBER | NUMBER_PERCENT) -- shared by both
-- sides so each can be set independently via panel.secondaryFormat
-- (Character) and panel.expectedFormat (Recommended).
-- Renderiza un lado (Personaje o Recomendado) de un stat segun un codigo de
-- formato (NUMBER | PERCENT | PERCENT_NUMBER | NUMBER_PERCENT) -- comun a
-- ambos lados, cada uno configurable por separado via
-- panel.secondaryFormat (Personaje) y panel.expectedFormat (Recomendado).
local function FormatOneSide(dp, format, rating, pct)
	local ratingStr = tostring(math.floor(rating + 0.5))
	local pctStr = string.format("%." .. dp .. "f%%", pct)

	if format == "NUMBER" then
		return ratingStr
	elseif format == "PERCENT" then
		return pctStr
	elseif format == "PERCENT_NUMBER" then
		return pctStr .. " (" .. ratingStr .. ")"
	else -- NUMBER_PERCENT (default)
		return ratingStr .. " (" .. pctStr .. ")"
	end
end

-- actual/expected: {rating=, pct=} tables (see PlayerStats:GetSecondaryActuals
-- / :GetExpected). expected may be nil (no active scale).
-- actual/expected: tablas {rating=, pct=} (ver
-- PlayerStats:GetSecondaryActuals / :GetExpected). expected puede ser nil
-- (sin escala activa).
local function FormatSecondary(panel, label, actual, expected)
	local dp = panel.decimalPlaces or 2
	local actualStr = FormatOneSide(dp, panel.secondaryFormat, actual.rating, actual.pct)

	if expected then
		local expectedStr = FormatOneSide(dp, panel.expectedFormat or "NUMBER", expected.rating, expected.pct)
		return string.format("%s: %s / %s", label, actualStr, expectedStr)
	end
	return string.format("%s: %s", label, actualStr)
end

-- Resizes the curve mask to match the bar's CURRENT fill width instead
-- of the whole track -- otherwise the mask's right-rounded-corner only
-- ever lines up with the fill's leading edge when the bar happens to be
-- at exactly 100%; at any other percentage the fill's own edge (which
-- the StatusBar crops on its own via its internal texture width) would
-- just be a flat cut, nowhere near where the mask's rounding actually
-- lives (which stays fixed to the full track's bounds otherwise). Safe
-- to call unconditionally -- styles that never got the mask added via
-- AddMaskTexture (see ApplyAppearance) just resize an unused texture.
-- Cambia el tamaño de la mascara de curva para que coincida con el ancho
-- ACTUAL de relleno en vez de con toda la barra -- si no, la esquina
-- redondeada derecha de la mascara solo coincide con el borde de avance
-- del relleno cuando la barra esta justo al 100%; en cualquier otro
-- porcentaje el borde del relleno (que la StatusBar recorta por su
-- cuenta via el ancho de su textura interna) seria un corte plano, lejos
-- de donde vive de verdad el redondeo de la mascara (que si no se queda
-- fijo a los limites de toda la barra). Se puede llamar sin condicion --
-- en los estilos donde nunca se le agrego la mascara via AddMaskTexture
-- (ver ApplyAppearance) solo se redimensiona una textura sin uso.
local function UpdateCurveMaskFill(row, pct)
	if not row.curveMask then
		return
	end
	local trackWidth = row.track:GetWidth() or 0
	local clampedPct = math.min(math.max(pct or 0, 0), 100)
	local fillWidth = math.max(trackWidth * (clampedPct / 100), 1)
	row.curveMask:ClearAllPoints()
	row.curveMask:SetPoint("TOPLEFT", row.track, "TOPLEFT")
	row.curveMask:SetWidth(fillWidth)
	row.curveMask:SetHeight(row.track:GetHeight() or 1)
end

-- Fills a StatusBar per Character/Recommended -- 100% means you hit your
-- Recommended value exactly; past that, the base bar stays full and
-- overflowBar (width = the excess, always restarting from the left) marks
-- the extra lap, with an "xN" counter next to it. With no active scale
-- (expected nil) the bar stays empty -- nothing to compute a % from, same
-- case as the rest of the panel without a scale.
-- Llena un StatusBar segun Personaje/Recomendado -- 100% significa que
-- llegaste exacto a tu valor Recomendado; pasado eso, la barra base se
-- queda llena y overflowBar (ancho = el sobrante, siempre arrancando de
-- nuevo desde la izquierda) marca la vuelta extra, con un contador "xN" al
-- lado. Sin escala activa (expected nil) la barra se queda vacia -- no hay
-- con que calcular un %, mismo caso que el resto del panel sin escala.
local function RefreshDynamicBarRow(row, key, panel, actual, expected)
	local dp = panel.decimalPlaces or 2
	local actualStr = FormatOneSide(dp, panel.secondaryFormat, actual.rating, actual.pct)
	-- Icon mode replaces the stat NAME with the icon (see Refresh) -- the
	-- value itself (rating/percent) still has to show next to it, so only
	-- the "LABELS[key]: " prefix is dropped here, never actualStr.
	-- El modo icono reemplaza el NOMBRE del stat con el icono (ver
	-- Refresh) -- el valor en si (rating/porcentaje) tiene que seguir
	-- mostrandose junto a el, asi que aqui solo se quita el prefijo
	-- "LABELS[key]: ", nunca actualStr.
	if panel.barLabelMode == "ICON" then
		row.labelActual:SetText(actualStr)
	else
		row.labelActual:SetText(string.format("%s: %s", LABELS[key], actualStr))
	end

	if not expected or not expected.rating or expected.rating <= 0 then
		row.track:SetValue(0)
		UpdateCurveMaskFill(row, 0)
		row.overflowBar:Hide()
		row.lapText:Hide()
		row.labelExpected:SetText("")
		return
	end

	local pct = (actual.rating / expected.rating) * 100

	if pct <= 100 then
		row.track:SetValue(math.max(pct, 0))
		UpdateCurveMaskFill(row, pct)
		row.overflowBar:Hide()
		row.lapText:Hide()
	else
		row.track:SetValue(100)
		UpdateCurveMaskFill(row, 100)
		local laps = math.floor(pct / 100)
		local overflowPct = pct - laps * 100
		local trackWidth = row.track:GetWidth() or 0
		row.overflowBar:SetWidth(math.max(trackWidth * (overflowPct / 100), 0.01))
		row.overflowBar:Show()
		row.lapText:SetText(string.format("x%d", laps))
		row.lapText:ClearAllPoints()
		row.lapText:SetPoint("LEFT", row.track, "RIGHT", 4, 0)
		row.lapText:Show()
	end

	local expectedStr = FormatOneSide(dp, panel.expectedFormat or "NUMBER", expected.rating, expected.pct)
	row.labelExpected:SetText("/ " .. expectedStr)
end

-- Primary Stat/Leech/Avoidance: always-full bar (cosmetic, no comparison
-- possible) -- just updates the label text with the live value.
-- Primary Stat/Leech/Avoidance: barra siempre llena (cosmetica, sin
-- comparacion posible) -- solo actualiza el texto de la etiqueta con el
-- valor en vivo.
local function RefreshStaticBarRow(row, text)
	row.track:SetValue(100)
	UpdateCurveMaskFill(row, 100)
	row.labelActual:SetText(text)
end

-- Item Level: real fill (equipped ÷ season max), with a dynamic color
-- (ComputeIlvlColor) instead of COLORS.ilvl's fixed one -- on both the bar
-- and its glow, so the glow always matches the current color.
-- Item Level: relleno real (equipado ÷ maximo de temporada), con color
-- dinamico (ComputeIlvlColor) en vez del fijo de COLORS.ilvl -- tanto en la
-- barra como en su destello, para que el destello siempre combine con el
-- color actual.
local function RefreshIlvlBarRow(row, equippedIlvl, overallIlvl, seasonData, iconMode)
	local pct = 0
	if seasonData.max and seasonData.max > 0 then
		pct = math.min(math.max(equippedIlvl / seasonData.max * 100, 0), 100)
	end
	row.track:SetValue(pct)
	UpdateCurveMaskFill(row, pct)

	local r, g, b = ComputeIlvlColor(equippedIlvl, seasonData)
	row.track:SetStatusBarColor(r, g, b)
	row.spark:SetVertexColor(WarmTint({ r, g, b }, 0.35))

	if iconMode then
		row.labelActual:SetText(string.format("%d / %d", equippedIlvl, overallIlvl))
	else
		row.labelActual:SetText(string.format("%s: %d / %d", LABELS.ilvl, equippedIlvl, overallIlvl))
	end

	-- Season max goes on labelExpected, pinned to the bar's right edge the
	-- same way every other bar's "/ <value>" is -- so its "/" lines up in
	-- the same column as the rest instead of drifting with
	-- panel.textAlign like the rest of this row's text does.
	-- El maximo de temporada va en labelExpected, fijo al borde derecho de
	-- la barra igual que el "/ <valor>" de cualquier otra barra -- para
	-- que su "/" quede alineado en la misma columna que las demas en vez
	-- de moverse con panel.textAlign como el resto del texto de esta fila.
	if row.labelExpected then
		row.labelExpected:SetText("/ " .. tostring(seasonData.max or 0))
	end
end

function Panel:Refresh()
	if not frame then
		self:CreateMainFrame()
		self:ApplyAppearance()
	end

	self:UpdateVisibility()

	local panel = ns.db.profile.panel
	local show = panel.showStats
	local scaleName = ns.db.profile.activeScale
	local scale = scaleName and ns.db.char.scales[scaleName]

	local actuals = ns.PlayerStats:GetSecondaryActuals()
	local expected = ns.PlayerStats:GetExpected(scale, actuals)
	local tertiaries = ns.PlayerStats:GetTertiaryActuals()
	local primaryName, primaryValue = ns.PlayerStats:GetPrimaryStat()
	local equippedIlvl, overallIlvl = ns.PlayerStats:GetItemLevel()
	local seasonData = ns.PlayerStats:GetSeasonIlvlData()

	-- iconMode (only ever true for the Power-bars Character side, see the
	-- barMode call sites below) drops the "name: " prefix and keeps just
	-- the value, since the icon takes over showing which stat it is. The
	-- plain-text rows below always call TextFor(key) with no 2nd argument,
	-- so they keep the full "name: value" text regardless of
	-- panel.barLabelMode.
	-- iconMode (solo verdadero para el lado Personaje de Barras de poder,
	-- ver los call sites de barMode abajo) quita el prefijo "nombre: " y
	-- deja solo el valor, ya que el icono se encarga de mostrar de que
	-- stat se trata. Las filas de texto plano de abajo siempre llaman a
	-- TextFor(key) sin 2do argumento, asi que conservan el texto completo
	-- "nombre: valor" sin importar panel.barLabelMode.
	local function TextFor(key, iconMode)
		if key == "primary" then
			if iconMode then
				return tostring(primaryValue)
			end
			return string.format("%s: %d", primaryName, primaryValue)
		elseif key == "ilvl" then
			return string.format("%s: %d / %d / %d", LABELS.ilvl, equippedIlvl, overallIlvl, seasonData.max or 0)
		elseif TERTIARY_KEYS[key] then
			local dp = panel.decimalPlaces or 2
			local t = tertiaries[key]
			local valueStr = FormatOneSide(dp, panel.secondaryFormat, t.rating, t.pct)
			if iconMode then
				return valueStr
			end
			return string.format("%s: %s", LABELS[key], valueStr)
		else
			return FormatSecondary(panel, LABELS[key], actuals[key], expected[key])
		end
	end

	if panel.barMode then
		combinedRow:Hide()
		for _, fs in pairs(rows) do
			fs:Hide()
		end

		-- Icon mode draws the icon OUTSIDE the bar (see below) -- when it
		-- sits on the LEFT, the track itself has to start further right to
		-- leave room for it (the track's width was already shrunk by this
		-- same amount in ApplyAppearance). On the RIGHT, the track keeps
		-- its normal left edge since the icon goes after its own right
		-- edge instead.
		-- El modo icono dibuja el icono FUERA de la barra (ver abajo) --
		-- cuando va del lado IZQUIERDO, la barra misma tiene que arrancar
		-- mas a la derecha para dejarle espacio (su ancho ya se achico esa
		-- misma cantidad en ApplyAppearance). Del lado DERECHO, la barra
		-- mantiene su borde izquierdo normal ya que el icono va despues de
		-- su propio borde derecho.
		local iconModeActive = panel.barLabelMode == "ICON"
		local trackLeftOffset = PADDING
		if iconModeActive and panel.barLabelIconSide ~= "RIGHT" then
			trackLeftOffset = PADDING + GetIconSize(panel.barHeight or BAR_HEIGHT) + ICON_GAP
		end

		local y = -PADDING
		for _, key in ipairs(ORDER) do
			if show[key] then
				if IsBarKey(key) then
					local row = barRows[key]
					if STATIC_BAR_KEYS[key] then
						RefreshStaticBarRow(row, TextFor(key, panel.barLabelMode == "ICON"))
					elseif GAUGE_BAR_KEYS[key] then
						RefreshIlvlBarRow(row, equippedIlvl, overallIlvl, seasonData, panel.barLabelMode == "ICON")
					else
						RefreshDynamicBarRow(row, key, panel, actuals[key], expected[key])
					end

					if panel.barTextInside then
						-- Text on top of the bar itself -- no separate
						-- label row, so the bar is placed first and both
						-- sides of the text anchor to it (vertically
						-- centered via "LEFT"/"RIGHT", the UI engine
						-- centers them on the target frame's height).
						-- Texto encima de la barra misma -- no hay fila de
						-- etiqueta aparte, asi que la barra se ubica
						-- primero y ambos lados del texto se anclan a ella
						-- (centrados verticalmente via "LEFT"/"RIGHT", el
						-- motor de UI los centra solo en la altura del
						-- frame destino).
						row.track:ClearAllPoints()
						row.track:SetPoint("TOPLEFT", frame, "TOPLEFT", trackLeftOffset, y)
						row.track:SetHeight(panel.barHeight or BAR_HEIGHT)
						row.track:Show()

						row.labelActual:ClearAllPoints()
						row.labelActual:SetPoint("LEFT", row.track, "LEFT", 4, 0)
						row.labelActual:SetPoint("RIGHT", row.track, "RIGHT", -4, 0)
						row.labelActual:Show()

						if row.labelExpected then
							row.labelExpected:ClearAllPoints()
							row.labelExpected:SetPoint("RIGHT", row.track, "RIGHT", -4, 0)
							row.labelExpected:Show()

							-- Right-aligned text draws from the right edge of
							-- its own box inward -- labelActual's box used to
							-- span the WHOLE bar (same right edge as
							-- labelExpected), so right-aligned text landed on
							-- top of labelExpected's text. Pulling labelActual's
							-- right edge back to labelExpected's left edge
							-- instead of the bar's own gives it its own lane.
							-- Item Level/Primary/Leech/Avoidance have no
							-- labelExpected, so they never hit this.
							-- El texto alineado a la derecha se dibuja desde el
							-- borde derecho de su propia caja hacia adentro --
							-- la caja de labelActual antes abarcaba TODA la
							-- barra (el mismo borde derecho que labelExpected),
							-- asi que el texto alineado a la derecha caia
							-- encima del texto de labelExpected. Recortar el
							-- borde derecho de labelActual hasta el borde
							-- izquierdo de labelExpected en vez del de la barra
							-- le da su propio carril. Item Level/Primary/Leech/
							-- Avoidance no tienen labelExpected, asi que nunca
							-- les pasa esto.
							if panel.textAlign == "RIGHT" then
								row.labelActual:SetPoint("RIGHT", row.labelExpected, "LEFT", -4, 0)
							end
						end
					else
						-- "Character" side: spans the BAR's own width (not
						-- the full frame), its real position decided by
						-- panel.textAlign (see ApplyAppearance). Spanning
						-- the bar instead of the frame matters in icon
						-- mode: the bar is narrower there (room reserved
						-- for the icon, see trackLeftOffset above) -- if
						-- the label still spanned the full frame,
						-- right-aligned text would land on top of the
						-- icon instead of stopping at the bar's own edge.
						-- Lado "Personaje": ocupa el ancho de la BARRA
						-- misma (no el del frame completo), su posicion
						-- real la decide panel.textAlign (ver
						-- ApplyAppearance). Que ocupe el ancho de la barra
						-- en vez del frame importa en modo icono: ahi la
						-- barra es mas angosta (deja espacio reservado
						-- para el icono, ver trackLeftOffset arriba) -- si
						-- la etiqueta siguiera ocupando todo el frame, el
						-- texto alineado a la derecha caeria encima del
						-- icono en vez de detenerse en el borde de la
						-- barra.
						--
						-- The bar's own position (trackY) uses a FIXED
						-- reserved slot (BAR_LABEL_HEIGHT), never
						-- panel.barLabelGap -- so the bar-to-bar rhythm
						-- (and every other row's position) is controlled
						-- exclusively by "Espacio entre barras"
						-- (barSpacing). barLabelGap only nudges the LABEL
						-- itself closer to/further from its own bar; at
						-- the default value (barLabelGap == BAR_LABEL_HEIGHT)
						-- the label sits exactly where it always did.
						--
						-- La posicion de la barra misma (trackY) usa un
						-- espacio FIJO reservado (BAR_LABEL_HEIGHT), nunca
						-- panel.barLabelGap -- asi que el ritmo barra-a-
						-- barra (y la posicion de cualquier otra fila) lo
						-- controla exclusivamente "Espacio entre barras"
						-- (barSpacing). barLabelGap solo acerca/aleja la
						-- ETIQUETA de su propia barra; en el valor por
						-- defecto (barLabelGap == BAR_LABEL_HEIGHT) la
						-- etiqueta queda exactamente donde siempre estuvo.
						local trackY = y - BAR_LABEL_HEIGHT
						-- (More-negative y = further down in this file's
						-- convention.) Delta from the default gap is what
						-- actually moves things: 0 at the default value,
						-- positive (moves up, away from the bar) above it,
						-- negative (moves down, into the bar) below it.
						-- Both labelActual and labelExpected apply this
						-- SAME delta, so they move together.
						-- (Y mas negativo = mas abajo, en la convencion de
						-- este archivo.) Lo que realmente mueve las cosas
						-- es la diferencia respecto al valor por defecto:
						-- 0 en el valor por defecto, positivo (sube,
						-- alejandose de la barra) por encima, negativo
						-- (baja, hacia la barra) por debajo. labelActual Y
						-- labelExpected aplican esta MISMA diferencia, asi
						-- que se mueven juntos.
						local gapDelta = (panel.barLabelGap or BAR_LABEL_HEIGHT) - BAR_LABEL_HEIGHT
						local labelGap = panel.barLabelGap or BAR_LABEL_HEIGHT

						row.track:ClearAllPoints()
						row.track:SetPoint("TOPLEFT", frame, "TOPLEFT", trackLeftOffset, trackY)
						row.track:SetHeight(panel.barHeight or BAR_HEIGHT)
						row.track:Show()

						row.labelActual:ClearAllPoints()
						row.labelActual:SetPoint("TOPLEFT", row.track, "TOPLEFT", 0, labelGap)
						row.labelActual:SetPoint("TOPRIGHT", row.track, "TOPRIGHT", 0, labelGap)
						row.labelActual:Show()

						-- "Recommended" side: pinned to the bar's OWN
						-- right edge (not the panel's) -- follows the
						-- bar's real width. Anchored to row.track, which
						-- is already positioned above (no longer relies on
						-- same-tick anchor resolution order). Static rows
						-- have no such side.
						-- Lado "Recomendado": pegado al borde derecho de
						-- la barra MISMA (no del panel) -- sigue el ancho
						-- real de la barra. Anclado a row.track, que ya
						-- quedo posicionado arriba (ya no depende del
						-- orden de resolucion de anclas en el mismo tick).
						-- Las filas estaticas no tienen este lado.
						if row.labelExpected then
							row.labelExpected:ClearAllPoints()
							row.labelExpected:SetPoint("BOTTOMRIGHT", row.track, "TOPRIGHT", 0, gapDelta)
							row.labelExpected:Show()

							-- Same right-aligned overlap as the barTextInside
							-- branch above, just in the "label in its own row"
							-- layout: labelActual spans the whole frame width
							-- (same right edge as labelExpected, which sits
							-- directly above the bar's own top-right corner),
							-- so right-aligned text landed on top of it.
							-- Mismo solape de texto alineado a la derecha que
							-- la rama de barTextInside de arriba, solo que en
							-- el layout de "etiqueta en su propia fila":
							-- labelActual ocupa todo el ancho del frame (el
							-- mismo borde derecho que labelExpected, que esta
							-- justo arriba de la esquina superior derecha de
							-- la barra), asi que el texto alineado a la
							-- derecha le caia encima.
							if panel.textAlign == "RIGHT" then
								row.labelActual:SetPoint("TOPRIGHT", row.labelExpected, "TOPLEFT", -4, 0)
							end
						end

						y = trackY
					end

					-- Icon mode: the stat icon sits OUTSIDE the bar, beside it
					-- on the chosen side (never overlapping the fill) --
					-- the track was already shrunk and offset above to
					-- leave exactly this much room. labelActual keeps its
					-- normal anchors (set above) since nothing overlaps it
					-- anymore -- only the stat NAME is dropped from its
					-- text (see RefreshDynamicBarRow/RefreshStaticBarRow/
					-- RefreshIlvlBarRow/TextFor), never the data.
					-- Modo icono: el icono del stat va FUERA de la barra, a
					-- un lado (nunca encima del relleno) -- la barra ya se
					-- achico y desplazo arriba para dejarle exactamente ese
					-- espacio. labelActual conserva sus anclas normales
					-- (puestas arriba) porque ya nada se le encima -- solo
					-- se le quita el NOMBRE del stat al texto (ver
					-- RefreshDynamicBarRow/RefreshStaticBarRow/
					-- RefreshIlvlBarRow/TextFor), nunca el dato.
					if row.icon then
						if panel.barLabelMode == "ICON" then
							row.icon:ClearAllPoints()
							if panel.barLabelIconSide == "RIGHT" then
								row.icon:SetPoint("LEFT", row.track, "RIGHT", ICON_GAP, 0)
							else
								row.icon:SetPoint("RIGHT", row.track, "LEFT", -ICON_GAP, 0)
							end
							row.icon:Show()
							if row.iconHitbox then
								row.iconHitbox:ClearAllPoints()
								row.iconHitbox:SetAllPoints(row.icon)
								row.iconHitbox:Show()
							end
						else
							row.icon:Hide()
							if row.iconHitbox then
								row.iconHitbox:Hide()
							end
						end
					end

					y = y - (panel.barHeight or BAR_HEIGHT) - (panel.barSpacing or 6)
				else
					local fs = rows[key]
					fs:ClearAllPoints()
					fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
					fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y)
					fs:SetText(TextFor(key))
					fs:Show()
					y = y - (panel.lineSpacing or 16)
				end
			elseif IsBarKey(key) then
				local row = barRows[key]
				row.labelActual:Hide()
				if row.labelExpected then row.labelExpected:Hide() end
				row.track:Hide()
				if row.overflowBar then row.overflowBar:Hide() end
				if row.lapText then row.lapText:Hide() end
				row.classTint:Hide()
				for _, tick in ipairs(row.ticks) do
					tick:Hide()
				end
				row.decorBorder:Hide()
				if row.icon then row.icon:Hide() end
				if row.iconHitbox then row.iconHitbox:Hide() end
			end
		end

		frame:SetWidth(panel.width)
		frame:SetHeight(-y + PADDING - (panel.barSpacing or 6))
	elseif panel.oneLineLayout then
		HideBarRows()
		for _, fs in pairs(rows) do
			fs:Hide()
		end

		local parts = {}
		for _, key in ipairs(ORDER) do
			if show[key] then
				table.insert(parts, ColorWrap(key, TextFor(key)))
			end
		end

		combinedRow:ClearAllPoints()
		combinedRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
		combinedRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)
		combinedRow:SetText(table.concat(parts, "  |  "))
		combinedRow:Show()

		frame:SetWidth(panel.width)
		frame:SetHeight(PADDING * 2 + (panel.fontSize or 12) + 4)
	else
		HideBarRows()
		combinedRow:Hide()

		local visibleCount = 0
		for _, key in ipairs(ORDER) do
			local fs = rows[key]
			if show[key] then
				visibleCount = visibleCount + 1
				fs:ClearAllPoints()
				local y = -PADDING - (visibleCount - 1) * (panel.lineSpacing or 16)
				fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
				fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y)
				fs:SetText(TextFor(key))
				fs:Show()
			else
				fs:Hide()
			end
		end

		frame:SetWidth(panel.width)
		frame:SetHeight(PADDING * 2 + math.max(visibleCount, 1) * (panel.lineSpacing or 16))
	end
end

function Panel:Init()
	self:CreateMainFrame()
	self:ApplyAppearance()
	self:Refresh()
end
