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

	local animGroup = spark:CreateAnimationGroup()
	animGroup:SetLooping("BOUNCE")
	local pulse = animGroup:CreateAnimation("Alpha")
	pulse:SetFromAlpha(fromAlpha)
	pulse:SetToAlpha(toAlpha)
	pulse:SetDuration(duration)
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
		track:SetBackdropColor(0, 0, 0, 0.55)
		track:SetBackdropBorderColor(0, 0, 0, 0.8)
		local spark = CreateSpark(track, c, 0.75, 1, 1.3)

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
		}

		if not isSimple then
			-- "Recommended" side -- always pinned to the right edge,
			-- moves with the bar's real width (see Refresh).
			-- Lado "Recomendado" -- siempre pegado al borde derecho, se
			-- mueve junto con el ancho real de la barra (ver Refresh).
			row.labelExpected = textLayer:CreateFontString(nil, "OVERLAY")

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

	local barWidth = math.max(panel.width - PADDING * 2, 10)
	local barHeight = panel.barHeight or BAR_HEIGHT
	for key, row in pairs(barRows) do
		local c = COLORS[key]

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
		if c then
			row.labelActual:SetTextColor(c[1], c[2], c[3])
		end

		if row.labelExpected then
			-- "Recommended" side: always pinned right -- the anchor in
			-- Refresh() is what makes it move with the bar's real width.
			-- Lado "Recomendado": siempre pegado a la derecha -- el anclaje
			-- en Refresh() es lo que lo hace moverse con el ancho real de
			-- la barra.
			row.labelExpected:SetFont(fontPath, panel.fontSize or 12, barLabelFlags)
			row.labelExpected:SetJustifyH("RIGHT")
			if c then
				row.labelExpected:SetTextColor(c[1], c[2], c[3])
			end
		end

		row.track:SetWidth(barWidth)
		row.track:SetHeight(barHeight)
		row.spark:SetSize(16, barHeight + 8)
		if row.overflowBar then
			row.overflowBar:SetHeight(barHeight)
			row.overflowSpark:SetSize(16, barHeight + 8)
		end
		if row.lapText then
			row.lapText:SetFont(fontPath, (panel.fontSize or 12) - 1, flags)
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
	row.labelActual:SetText(string.format("%s: %s", LABELS[key], actualStr))

	if not expected or not expected.rating or expected.rating <= 0 then
		row.track:SetValue(0)
		row.overflowBar:Hide()
		row.lapText:Hide()
		row.labelExpected:SetText("")
		return
	end

	local pct = (actual.rating / expected.rating) * 100

	if pct <= 100 then
		row.track:SetValue(math.max(pct, 0))
		row.overflowBar:Hide()
		row.lapText:Hide()
	else
		row.track:SetValue(100)
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
	row.labelActual:SetText(text)
end

-- Item Level: real fill (equipped ÷ season max), with a dynamic color
-- (ComputeIlvlColor) instead of COLORS.ilvl's fixed one -- on both the bar
-- and its glow, so the glow always matches the current color.
-- Item Level: relleno real (equipado ÷ maximo de temporada), con color
-- dinamico (ComputeIlvlColor) en vez del fijo de COLORS.ilvl -- tanto en la
-- barra como en su destello, para que el destello siempre combine con el
-- color actual.
local function RefreshIlvlBarRow(row, equippedIlvl, overallIlvl, seasonData)
	local pct = 0
	if seasonData.max and seasonData.max > 0 then
		pct = math.min(math.max(equippedIlvl / seasonData.max * 100, 0), 100)
	end
	row.track:SetValue(pct)

	local r, g, b = ComputeIlvlColor(equippedIlvl, seasonData)
	row.track:SetStatusBarColor(r, g, b)
	row.spark:SetVertexColor(WarmTint({ r, g, b }, 0.35))

	row.labelActual:SetText(string.format("%s: %d / %d / %d", LABELS.ilvl, equippedIlvl, overallIlvl, seasonData.max or 0))
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

	local function TextFor(key)
		if key == "primary" then
			return string.format("%s: %d", primaryName, primaryValue)
		elseif key == "ilvl" then
			return string.format("%s: %d / %d", LABELS.ilvl, equippedIlvl, overallIlvl)
		elseif TERTIARY_KEYS[key] then
			local dp = panel.decimalPlaces or 2
			local t = tertiaries[key]
			return string.format("%s: %s", LABELS[key], FormatOneSide(dp, panel.secondaryFormat, t.rating, t.pct))
		else
			return FormatSecondary(panel, LABELS[key], actuals[key], expected[key])
		end
	end

	if panel.barMode then
		combinedRow:Hide()
		for _, fs in pairs(rows) do
			fs:Hide()
		end

		local y = -PADDING
		for _, key in ipairs(ORDER) do
			if show[key] then
				if IsBarKey(key) then
					local row = barRows[key]
					if STATIC_BAR_KEYS[key] then
						RefreshStaticBarRow(row, TextFor(key))
					elseif GAUGE_BAR_KEYS[key] then
						RefreshIlvlBarRow(row, equippedIlvl, overallIlvl, ns.PlayerStats:GetSeasonIlvlData())
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
						row.track:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
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
						end
					else
						-- "Character" side: spans the full width, its real
						-- position decided by panel.textAlign (see
						-- ApplyAppearance).
						-- Lado "Personaje": ocupa todo el ancho, su
						-- posicion real la decide panel.textAlign (ver
						-- ApplyAppearance).
						row.labelActual:ClearAllPoints()
						row.labelActual:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
						row.labelActual:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y)
						row.labelActual:Show()

						-- "Recommended" side: pinned to the bar's OWN
						-- right edge (not the panel's) -- follows the
						-- bar's real width. Anchored to row.track rather
						-- than "frame": the UI engine resolves track's
						-- final position regardless of its own SetPoint
						-- call running later in this same tick. Static
						-- rows have no such side.
						-- Lado "Recomendado": pegado al borde derecho de
						-- la barra MISMA (no del panel) -- sigue el ancho
						-- real de la barra. Anclado a row.track en vez de
						-- a "frame": el motor de UI resuelve la posicion
						-- final de track sin importar que su propio
						-- SetPoint corra despues en este mismo tick. Las
						-- filas estaticas no tienen este lado.
						if row.labelExpected then
							row.labelExpected:ClearAllPoints()
							row.labelExpected:SetPoint("BOTTOMRIGHT", row.track, "TOPRIGHT", 0, 0)
							row.labelExpected:Show()
						end
						y = y - (panel.barLabelGap or BAR_LABEL_HEIGHT)

						row.track:ClearAllPoints()
						row.track:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
						row.track:SetHeight(panel.barHeight or BAR_HEIGHT)
						row.track:Show()
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
