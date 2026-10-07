--[[ StatsMythic · Config.lua
The `/stm config` AceConfig options table, scale management, and slash
commands.
© 2026 TavoD_Gus_KrG · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

local Config = {}
ns.Config = Config

-- Session-only UI state (not saved) -- which scale cards currently have
-- their rename textbox expanded. Keyed by scale name, reset on relog,
-- which is fine since it's just "is this one open right now", nothing
-- durable.
-- Estado de UI solo-de-sesion (no se guarda) -- que tarjetas de escala
-- tienen su textbox de renombrar expandido ahorita. Indexado por nombre de
-- escala, se resetea al reloguear, lo cual esta bien porque es solo "esta
-- abierto ahorita", nada durable.
local renameExpanded = {}

-- "primary"/"weaponDps"/"offHandWeaponDps" sit on top of the original 4 --
-- they only matter for classes/specs that use them (primary stat is
-- usually the single highest weight of all, and weapon DPS matters for
-- melee). A weight left at 0 simply doesn't contribute to scoring, so
-- unrelated classes can just leave them alone.
-- "primary"/"weaponDps"/"offHandWeaponDps" se agregan encima de los 4
-- originales -- solo importan para clases/specs que los usan (el stat
-- principal suele ser el peso mas alto de todos, y Weapon DPS importa
-- para cuerpo a cuerpo). Un peso en 0 simplemente no participa en el
-- puntaje, asi que las clases que no lo usan lo pueden dejar asi.
local STAT_KEYS = { "primary", "crit", "haste", "mastery", "vers", "weaponDps", "offHandWeaponDps" }

-- Labels for the weight fields that aren't part of Panel's displayed stat
-- rows (Panel.LABELS covers primary/ilvl/the 4 secondaries/the 2
-- tertiaries for the floating panel -- these two are tooltip-scoring-only
-- concepts).
-- Etiquetas para los campos de peso que no son parte de las filas de stat
-- que muestra Panel (Panel.LABELS cubre primary/ilvl/los 4 secundarios/
-- los 2 terciarios para el panel flotante -- estos dos son conceptos solo
-- de puntaje de tooltip).
local EXTRA_WEIGHT_LABELS = {
	weaponDps = "Weapon DPS",
	offHandWeaponDps = "Off Hand Weapon DPS",
}

local function WeightLabel(key)
	if key == "primary" then
		local name = ns.PlayerStats and select(1, ns.PlayerStats:GetPrimaryStat())
		return name or "Primary Stat"
	end
	return (ns.Panel and ns.Panel.LABELS[key]) or EXTRA_WEIGHT_LABELS[key] or key
end

-- Maps the stat names used in a "Pawn string" (the format Raidbots/SimC
-- export, e.g. `CritRating=16.58, Versatility=13.66`) to our own weight
-- keys. Primary stat is whichever of Strength/Agility/Intellect shows up
-- -- only one ever will, since a scale is always for one specific class.
-- Unrecognized keys (Class, Spec, anything else) are simply skipped, not
-- guessed at.
-- Mapea los nombres de stat que usa un "string de Pawn" (el formato que
-- exportan Raidbots/SimC, ej. `CritRating=16.58, Versatility=13.66`) a
-- nuestras propias llaves de peso. El stat principal es el que aparezca de
-- Strength/Agility/Intellect -- solo uno va a aparecer, ya que una escala
-- siempre es para una clase especifica. Las llaves no reconocidas (Class,
-- Spec, cualquier otra) simplemente se ignoran, no se adivinan.
local PAWN_STAT_MAP = {
	Strength = "primary",
	Agility = "primary",
	Intellect = "primary",
	CritRating = "crit",
	HasteRating = "haste",
	MasteryRating = "mastery",
	Versatility = "vers",
	VersatilityRating = "vers",
	Dps = "weaponDps",
	WeaponDps = "weaponDps",
	OffhandDps = "offHandWeaponDps",
	OffHandDps = "offHandWeaponDps",
}

-- Parses a Pawn-format string, e.g.:
--   ( Pawn: v1: "MyCharacter - Demonology - Patchwerk (Raidbots)":
--     Class=Warlock, Spec=Demonology, Intellect=39.54, CritRating=16.58, ... )
-- The quoted name is optional -- pasting just the raw "Key=Value, ..."
-- pairs (no Pawn wrapper, no quoted name) is also accepted, since not
-- every simulator's output includes one. Returns name (may be nil),
-- weights (a table of our keys -> numbers) -- or nil, nil if no usable
-- pair was found at all (text doesn't look like Pawn/SimC output).
-- Parsea un string formato Pawn, ej.:
--   ( Pawn: v1: "MiPersonaje - Demonology - Patchwerk (Raidbots)":
--     Class=Warlock, Spec=Demonology, Intellect=39.54, CritRating=16.58, ... )
-- El nombre entre comillas es opcional -- pegar solo los pares crudos
-- "Clave=Valor, ..." (sin el envoltorio de Pawn, sin nombre entre
-- comillas) tambien se acepta, ya que no todo simulador lo incluye.
-- Devuelve nombre (puede ser nil), pesos (una tabla de nuestras llaves ->
-- numeros) -- o nil, nil si no se encontro ningun par usable (el texto no
-- parece salida de Pawn/SimC).
local function ParsePawnString(text)
	if type(text) ~= "string" then
		return nil, nil
	end

	local name = text:match('"([^"]+)"') -- nil if the paste has no name, that's fine / nil si el pegado no trae nombre, esta bien

	local weights = {}
	local found = false
	-- "(%a+)=([%-%d%.]+)" only matches when the value is purely numeric,
	-- so non-numeric fields like Class=Warlock/Spec=Demonology are
	-- naturally skipped without needing a separate exclusion list.
	-- "(%a+)=([%-%d%.]+)" solo hace match cuando el valor es puramente
	-- numerico, asi que campos no numericos como Class=Warlock/
	-- Spec=Demonology se ignoran solos, sin necesitar una lista de
	-- exclusion aparte.
	for statName, value in text:gmatch("(%a+)=([%-%d%.]+)") do
		local ourKey = PAWN_STAT_MAP[statName]
		if ourKey then
			weights[ourKey] = tonumber(value)
			found = true
		end
	end

	if not found then
		return nil, nil
	end
	return name, weights
end

-- Menu/UI chrome text only -- stat names (Panel.LABELS) are never affected
-- by this, they're always English.
-- Solo texto de menu/UI -- los nombres de los stats (Panel.LABELS) nunca
-- se ven afectados por esto, siempre son en ingles.
local STRINGS = {
	es = {
		generalHeader = "General",
		scalesHeader = "Escalas",
		activeScale = "Escala activa",
		newScaleName = "Nueva Escala",
		renameScale = "Renombrar",
		cancelRename = "Cancelar",
		renameScaleExists = "Ya existe una escala con ese nombre.",
		deleteScale = "Eliminar escala activa",
		deleteScaleConfirm = "Esto borra la escala activa. Continuar?",
		pastePawnLabel = "Pegar Resultado",
		pastePawnDesc = "Pega el resultado de Raidbots/SimC o cualquier otro simulador, con o sin nombre. Si hay una escala activa, siempre actualiza sus pesos (el nombre de la escala activa manda sobre el nombre pegado). Si no hay ninguna activa y el texto trae nombre, crea una escala nueva con ese nombre.",
		pastePawnError = "No se pudo leer ese texto. Tiene que traer al menos un peso reconocible (ej. CritRating=.., HasteRating=..).",
		pastePawnSuccess = "Escala '%s' cargada desde Pawn/Raidbots.",
		pastePawnSuccessNoName = "Pesos actualizados en la escala activa '%s'.",
		pastePawnNoActive = "Ese texto no trae nombre y no hay ninguna escala activa. Elegi o crea una escala primero, o pega el formato completo con nombre.",
		scaleListHeader = "Escalas de Personaje",
		scaleListEmpty = "Todavia no creaste ninguna escala.",
		scaleListActiveTag = " (activa)",
		useScale = "Usar esta escala",
		showInTooltip = "Mostrar en tooltip",
		showInTooltipDesc = "Muestra la comparacion de esta escala tambien en el tooltip de los objetos, ademas de la escala activa (no hace falta activarla para esto).",
		removeScale = "Eliminar",
		removeScaleConfirm = "Eliminar la escala '%s'?",
		panelHeader = "Panel",
		width = "Ancho",
		font = "Fuente",
		fontSize = "Tamaño de fuente",
		fontOutline = "Contorno de fuente",
		lineSpacing = "Espaciado entre lineas",
		barSpacing = "Espacio entre barras",
		barSpacingDesc = "Separacion entre una barra y la siguiente en 'Barras de poder' -- aparte del espaciado entre lineas, que sigue aplicando solo a las filas de texto (Stat Principal, Item Level, etc).",
		barHeight = "Alto de las barras",
		barHeightDesc = "Que tan altas (gruesas) se ven las barras en 'Barras de poder'.",
		barLabelGap = "Espacio etiqueta-barra",
		barLabelGapDesc = "Separacion vertical entre la etiqueta de una barra (el texto con los numeros) y la barra misma, en 'Barras de poder'.",
		barTextInside = "Texto dentro de la barra",
		barTextInsideDesc = "La etiqueta de cada barra (el texto con los numeros) se dibuja encima de la barra misma, en vez de en su propia fila arriba -- ahorra espacio vertical. El texto lleva contorno siempre en este modo, para seguir leyendose bien sin importar el color de fondo.",
		decimalPlaces = "Decimales en porcentajes",
		textAlign = "Alineacion del texto",
		alignLeft = "Izquierda", alignCenter = "Centro", alignRight = "Derecha",
		oneLineLayout = "Diseño en una sola linea",
		barMode = "Barras de poder",
		barModeDesc = "Crit/Haste/Mastery/Versatility como barras que se llenan segun Personaje/Recomendado, con un destello en el borde de avance. Si se pasa del 100%, la barra se queda llena y una franja marca la vuelta extra.",
		secondaryFormat = "Formato Personaje",
		expectedFormat = "Formato Recomendado",
		fmtNumberPercent = "Numero / Porcentaje",
		fmtNumber = "Numero",
		fmtPercent = "Porcentaje",
		showStatsMode = "Mostrar panel",
		modeAlways = "Siempre",
		modeCombat = "Solo en combate",
		modeOutOfCombat = "Solo fuera de combate",
		locked = "Bloquear posicion",
		resetPosition = "Restablecer posicion",
		bgAlpha = "Opacidad del fondo",
		showBorder = "Mostrar borde",
		showStatsHeader = "Mostrar Stats",
		showAllSecondaries = "Ocultar Stats Secundarios",
		uiLanguage = "Idioma del menu",
		showMinimapIcon = "Mostrar icono de minimapa",
		profilesHeader = "Perfiles",
		-- Our own translation of AceDBOptions-3.0's built-in text -- that
		-- library follows the WoW client's own language (GetLocale()),
		-- not our "Idioma del menu" toggle, so we override its labels
		-- with our own after building the table (see Config:Init())
		-- instead of editing the shared library file itself.
		-- Traduccion propia del texto incorporado de AceDBOptions-3.0 --
		-- esa libreria sigue el idioma del cliente de WoW (GetLocale()),
		-- no nuestro toggle "Idioma del menu", asi que sobreescribimos sus
		-- etiquetas con las propias despues de armar la tabla (ver
		-- Config:Init()) en vez de editar el archivo compartido de la
		-- libreria.
		profIntro = "Podes cambiar el perfil activo, asi cada personaje puede tener su propia configuracion.",
		profResetDesc = "Reinicia el perfil actual a los valores por defecto, por si se rompio la configuracion o simplemente queres empezar de cero.",
		profReset = "Reiniciar Perfil",
		profResetSub = "Reinicia el perfil actual al de por defecto.",
		profCurrentPrefix = "Perfil actual:",
		profChooseDesc = "Podes crear un perfil nuevo escribiendo un nombre en el cuadro, o elegir uno de los que ya existen.",
		profNew = "Nuevo",
		profNewSub = "Crea un perfil nuevo, vacio.",
		profChoose = "Perfiles existentes",
		profChooseSub = "Elegi uno de tus perfiles disponibles.",
		profCopyDesc = "Copia la configuracion de un perfil existente al perfil activo.",
		profCopy = "Copiar de",
		profDeleteDesc = "Borra perfiles existentes sin uso, para ahorrar espacio y limpiar el archivo de SavedVariables.",
		profDelete = "Borrar un Perfil",
		profDeleteSub = "Borra un perfil de la base de datos.",
		profDeleteConfirm = "Seguro que queres borrar el perfil seleccionado?",
		errorsTitle = "Errores recientes",
		errorsNoBugGrabber = "Necesitas tener !BugGrabber instalado para usar esto (ya viene con BugSack).",
		errorsNone = "No hay ningun error guardado todavia.",
	},
	en = {
		generalHeader = "General",
		scalesHeader = "Scales",
		activeScale = "Active scale",
		newScaleName = "New Scale",
		renameScale = "Rename",
		cancelRename = "Cancel",
		renameScaleExists = "A scale with that name already exists.",
		deleteScale = "Delete active scale",
		deleteScaleConfirm = "This deletes the active scale. Continue?",
		pastePawnLabel = "Paste Result",
		pastePawnDesc = "Paste Raidbots/SimC output (or any other simulator's), with or without a name. If a scale is active, it always updates that scale's weights (the active scale's own name wins over the pasted name). If none is active and the text has a name, creates a new scale under that name.",
		pastePawnError = "Couldn't read that text. It needs at least one recognizable weight (e.g. CritRating=.., HasteRating=..).",
		pastePawnSuccess = "Scale '%s' loaded from Pawn/Raidbots.",
		pastePawnSuccessNoName = "Weights updated on active scale '%s'.",
		pastePawnNoActive = "That text has no name and there's no active scale. Pick or create a scale first, or paste the full format with a name.",
		scaleListHeader = "Character Scales",
		scaleListEmpty = "No scales created yet.",
		scaleListActiveTag = " (active)",
		useScale = "Use this scale",
		showInTooltip = "Show in tooltip",
		showInTooltipDesc = "Also shows this scale's comparison in item tooltips, alongside the active scale (no need to activate it for this).",
		removeScale = "Delete",
		removeScaleConfirm = "Delete scale '%s'?",
		panelHeader = "Panel",
		width = "Width",
		font = "Font",
		fontSize = "Font size",
		fontOutline = "Font outline",
		lineSpacing = "Line spacing",
		barSpacing = "Bar spacing",
		barSpacingDesc = "Gap between one bar and the next in 'Power bars' -- separate from line spacing, which still only applies to the plain-text rows (Primary Stat, Item Level, etc).",
		barHeight = "Bar height",
		barHeightDesc = "How tall (thick) the bars look in 'Power bars'.",
		barLabelGap = "Label-to-bar gap",
		barLabelGapDesc = "Vertical gap between a bar's label (the text with the numbers) and the bar itself, in 'Power bars'.",
		barTextInside = "Text inside the bar",
		barTextInsideDesc = "Each bar's label (the text with the numbers) is drawn on top of the bar itself instead of on its own row above it -- saves vertical space. The text always gets an outline in this mode, to stay readable no matter the bar's current fill color.",
		decimalPlaces = "Percentage decimal places",
		textAlign = "Text alignment",
		alignLeft = "Left", alignCenter = "Center", alignRight = "Right",
		oneLineLayout = "One line layout",
		barMode = "Power bars",
		barModeDesc = "Crit/Haste/Mastery/Versatility as bars that fill according to Character/Recommended, with a glow at the leading edge. Past 100%, the bar stays full and a stripe marks the extra lap.",
		secondaryFormat = "Character Format",
		expectedFormat = "Recommended Format",
		fmtNumberPercent = "Number / Percent",
		fmtNumber = "Number",
		fmtPercent = "Percent",
		showStatsMode = "When to show the panel",
		modeAlways = "Always",
		modeCombat = "In combat only",
		modeOutOfCombat = "Out of combat only",
		locked = "Lock position",
		resetPosition = "Reset position",
		bgAlpha = "Background opacity",
		showBorder = "Show border",
		showStatsHeader = "Which stats to show",
		showAllSecondaries = "Show/hide all 4 secondaries",
		uiLanguage = "Menu language",
		showMinimapIcon = "Show minimap icon",
		profilesHeader = "Profiles",
		profIntro = "You can change the active profile, so each character can have its own settings.",
		profResetDesc = "Reset the current profile back to its default values, in case your configuration is broken, or you simply want to start over.",
		profReset = "Reset Profile",
		profResetSub = "Reset the current profile to the default.",
		profCurrentPrefix = "Current Profile:",
		profChooseDesc = "You can either create a new profile by entering a name in the editbox, or choose one of the already existing profiles.",
		profNew = "New",
		profNewSub = "Create a new empty profile.",
		profChoose = "Existing Profiles",
		profChooseSub = "Select one of your currently available profiles.",
		profCopyDesc = "Copy the settings from one existing profile into the currently active profile.",
		profCopy = "Copy From",
		profDeleteDesc = "Delete existing and unused profiles to save space, and cleanup the SavedVariables file.",
		profDelete = "Delete a Profile",
		profDeleteSub = "Deletes a profile from the database.",
		profDeleteConfirm = "Are you sure you want to delete the selected profile?",
		errorsTitle = "Recent errors",
		errorsNoBugGrabber = "You need !BugGrabber installed to use this (it ships with BugSack).",
		errorsNone = "No errors recorded yet.",
	},
}

local function L()
	return STRINGS[ns.db.global.uiLocale] or STRINGS.es
end

local function GetActiveScale()
	local name = ns.db.profile.activeScale
	return name and ns.db.char.scales[name]
end

local function ScaleValues()
	local values = {}
	for name in pairs(ns.db.char.scales) do
		values[name] = name
	end
	return values
end

-- Weight/scale changes affect both the floating Panel and the numbers
-- appended to Blizzard's native Character pane -- refresh both together
-- instead of scattering CharacterPane refresh calls next to every Panel one.
-- Los cambios de peso/escala afectan tanto al Panel flotante como a los
-- numeros agregados al panel de personaje nativo de Blizzard -- se
-- refrescan juntos en vez de esparcir llamadas a CharacterPane junto a
-- cada una de Panel.
local function RefreshAll()
	if ns.Panel then ns.Panel:Refresh() end
	if ns.CharacterPane then ns.CharacterPane:Refresh() end
end

local function GetOptions()
	return {
		type = "group",
		name = "StatsMythic",
		childGroups = "tab",
		args = {
			scales = {
				type = "group",
				name = function() return L().scalesHeader end,
				order = 1,
				args = {
					active = {
						type = "select",
						name = function() return L().activeScale end,
						order = 1,
						values = ScaleValues,
						get = function() return ns.db.profile.activeScale end,
						set = function(_, v)
							ns.db.profile.activeScale = v
							RefreshAll()
						end,
					},
					-- Single-step: typing a name and pressing Enter (or
					-- clicking away) creates the scale immediately. A
					-- two-step "type name, then click a separate button"
					-- flow has a real failure mode: clicking the button
					-- before the input loses focus can run with the old
					-- (empty) name, silently doing nothing.
					-- Un solo paso: escribir un nombre y presionar Enter
					-- (o hacer clic afuera) crea la escala de inmediato.
					-- Un flujo de dos pasos ("escribe el nombre, despues
					-- haz clic en un boton aparte") tiene una falla real:
					-- hacer clic en el boton antes de que el campo pierda
					-- el foco puede correr con el nombre viejo (vacio),
					-- sin hacer nada en silencio.
					newName = {
						type = "input",
						name = function() return L().newScaleName end,
						order = 2,
						get = function() return "" end,
						set = function(_, v)
							if not v or v == "" then return end
							if not ns.db.char.scales[v] then
								local scale = {}
								for _, k in ipairs(STAT_KEYS) do
									scale[k] = 0
								end
								ns.db.char.scales[v] = scale
							end
							ns.db.profile.activeScale = v
							RefreshAll()
						end,
					},
					-- Paste-and-go: the "Pawn string" format Raidbots/SimC
					-- export (Class=.., Spec=.., CritRating=.., ...),
					-- parsed via ParsePawnString. The ACTIVE scale's own
					-- name always wins over whatever name the pasted text
					-- carries -- hand-naming a scale, then pasting a
					-- Raidbots string with a different embedded name,
					-- must never leave the hand-named scale empty while
					-- spawning a second scale under the pasted name. So:
					-- if a scale is active, the paste always updates ITS
					-- weights, name in the pasted text or not. Only when
					-- nothing is active does a named paste create a new
					-- scale under that name.
					-- Pegar y listo: el formato "string de Pawn" que
					-- exportan Raidbots/SimC (Class=.., Spec=..,
					-- CritRating=.., ...), parseado via ParsePawnString.
					-- El nombre de la escala ACTIVA siempre manda sobre el
					-- que traiga el texto pegado -- nombrar una escala a
					-- mano y despues pegar un string de Raidbots con un
					-- nombre distinto adentro nunca debe dejar vacia la
					-- escala nombrada a mano mientras crea una segunda
					-- escala huerfana con el nombre pegado. Entonces: si
					-- hay una escala activa, el pegado siempre actualiza
					-- SUS pesos, traiga nombre el texto o no. Solo cuando
					-- no hay ninguna activa, un pegado con nombre crea una
					-- escala nueva bajo ese nombre.
					pastePawn = {
						type = "input",
						name = function() return L().pastePawnLabel end,
						desc = function() return L().pastePawnDesc end,
						order = 2.5,
						multiline = 3,
						width = "full",
						get = function() return "" end,
						set = function(_, v)
							local name, weights = ParsePawnString(v)
							if not weights then
								ns.addon:Print(L().pastePawnError)
								return
							end

							local activeName = ns.db.profile.activeScale
							local activeScale = activeName and ns.db.char.scales[activeName]

							if activeScale then
								for key, value in pairs(weights) do
									activeScale[key] = value
								end
								RefreshAll()
								ns.addon:Print(string.format(L().pastePawnSuccessNoName, activeName))
							elseif name then
								local scale = ns.db.char.scales[name]
								if not scale then
									scale = {}
									for _, k in ipairs(STAT_KEYS) do
										scale[k] = 0
									end
									ns.db.char.scales[name] = scale
								end
								for key, value in pairs(weights) do
									scale[key] = value
								end

								ns.db.profile.activeScale = name
								RefreshAll()
								ns.addon:Print(string.format(L().pastePawnSuccess, name))
							else
								ns.addon:Print(L().pastePawnNoActive)
							end
						end,
					},
					deleteScale = {
						type = "execute",
						name = function() return L().deleteScale end,
						order = 12, -- after all 7 weight fields (orders 5-11), at the very bottom / despues de los 7 campos de peso (orders 5-11), al final
						width = "full",
						-- This AceConfig build (the copy that ends up
						-- winning via LibStub, bundled with BlizzMove)
						-- validates confirmText as a plain string, not a
						-- function -- unlike name/values/disabled, which
						-- do accept functions. Resolved once here instead
						-- of reactively; acceptable since this confirm
						-- string rarely needs to update mid-session.
						-- Esta version de AceConfig (la copia que termina
						-- ganando via LibStub, empaquetada con BlizzMove)
						-- valida confirmText como un string plano, no una
						-- funcion -- a diferencia de name/values/disabled,
						-- que si aceptan funciones. Resuelto una sola vez
						-- aqui en vez de reactivo; aceptable porque este
						-- texto de confirmacion rara vez necesita
						-- actualizarse a mitad de sesion.
						confirm = true,
						confirmText = L().deleteScaleConfirm,
						disabled = function() return not GetActiveScale() end,
						func = function()
							local name = ns.db.profile.activeScale
							if not name then return end
							ns.db.char.scales[name] = nil
							ns.db.profile.activeScale = nil
							RefreshAll()
						end,
					},
				},
			},
			-- Populated dynamically by BuildScaleListArgs -- one visible
			-- sub-group per saved scale (this character's scales, since
			-- they live in AceDB's "char" scope), each showing its
			-- non-zero weights and a quick "use"/"delete" pair, so more
			-- than one scale can be seen at a glance instead of only
			-- through the collapsed dropdown above.
			-- Rellenado dinamicamente por BuildScaleListArgs -- un
			-- subgrupo visible por escala guardada (las escalas de este
			-- personaje, ya que viven en el scope "char" de AceDB), cada
			-- uno mostrando sus pesos distintos de cero y un par rapido de
			-- "usar"/"eliminar", para ver mas de una escala de un vistazo
			-- en vez de solo a traves del dropdown colapsado de arriba.
			scaleList = {
				type = "group",
				name = function() return L().scaleListHeader end,
				order = 1.5,
				args = {},
			},
			panelGroup = {
				type = "group",
				name = function() return L().panelHeader end,
				order = 2,
				args = {
					-- Slider (left) + dropdown (right) paired on the same
					-- row. IMPORTANT: use width="relative" + relWidth=0.5,
					-- NOT width="half" -- "half" in this AceConfig build
					-- is a FIXED 85px (width_multiplier=170 / 2, see
					-- AceConfigDialog-3.0.lua:49), not 50% of the real
					-- container, so two "half" controls leave room for
					-- more items to pack onto the same row.
					-- "relative"/relWidth is a genuine fraction of the
					-- actual row width, so 0.5+0.5 fills it exactly
					-- regardless of how wide the dialog is. Sliders
					-- ("dinamicas") sit in the LEFT column, dropdowns in
					-- the RIGHT one, consistently through this whole tab.
					-- A slider left without a dropdown partner (e.g.
					-- "Bar spacing") stays at its usual half-width with
					-- an invisible filler alongside it, so the next
					-- control doesn't pack onto the same row.
					--
					-- Slider (izquierda) + dropdown (derecha) emparejados
					-- en la misma fila. IMPORTANTE: usar
					-- width="relative" + relWidth=0.5, NO width="half" --
					-- "half" en esta version de AceConfig es un valor
					-- FIJO de 85px (width_multiplier=170 / 2, ver
					-- AceConfigDialog-3.0.lua:49), no 50% real del
					-- contenedor, asi que dos controles "half" dejan
					-- espacio libre para que mas controles se amontonen
					-- en la misma fila. "relative"/relWidth si es una
					-- fraccion real del ancho de la fila, asi que 0.5+0.5
					-- la llena exacto sin importar que tan ancho sea el
					-- dialogo. Los sliders ("dinamicas") van en la
					-- columna IZQUIERDA, los dropdowns en la DERECHA, de
					-- forma consistente en toda esta pestaña. Un slider
					-- que se queda sin pareja de dropdown (ej. "Espacio
					-- entre barras") se queda en su medio-ancho de
					-- siempre con un relleno invisible al lado, para que
					-- el siguiente control no se amontone en la misma
					-- fila.
					width = {
						type = "range",
						name = function() return L().width end,
						order = 1,
						width = "relative",
						relWidth = 0.5,
						min = 120, max = 1000, step = 10,
						get = function() return ns.db.profile.panel.width end,
						set = function(_, v)
							ns.db.profile.panel.width = v
							if ns.Panel then ns.Panel:ApplyAppearance() end; RefreshAll()
						end,
					},
					font = {
						type = "select",
						dialogControl = "LSM30_Font",
						name = function() return L().font end,
						order = 2,
						width = "relative",
						relWidth = 0.5,
						values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font,
						get = function() return ns.db.profile.panel.font end,
						set = function(_, v)
							ns.db.profile.panel.font = v
							if ns.Panel then ns.Panel:ApplyAppearance() end
						end,
					},
					fontSize = {
						type = "range",
						name = function() return L().fontSize end,
						order = 3,
						width = "relative",
						relWidth = 0.5,
						min = 8, max = 32, step = 1,
						get = function() return ns.db.profile.panel.fontSize end,
						set = function(_, v)
							ns.db.profile.panel.fontSize = v
							if ns.Panel then ns.Panel:ApplyAppearance() end; RefreshAll()
						end,
					},
					textAlign = {
						type = "select",
						name = function() return L().textAlign end,
						order = 4,
						width = "relative",
						relWidth = 0.5,
						values = function()
							local l = L()
							return { LEFT = l.alignLeft, CENTER = l.alignCenter, RIGHT = l.alignRight }
						end,
						get = function() return ns.db.profile.panel.textAlign end,
						set = function(_, v)
							ns.db.profile.panel.textAlign = v
							if ns.Panel then ns.Panel:ApplyAppearance() end; RefreshAll()
						end,
					},
					lineSpacing = {
						type = "range",
						name = function() return L().lineSpacing end,
						order = 5,
						width = "relative",
						relWidth = 0.5,
						min = 10, max = 40, step = 1,
						get = function() return ns.db.profile.panel.lineSpacing end,
						set = function(_, v)
							ns.db.profile.panel.lineSpacing = v
							RefreshAll()
						end,
					},
					secondaryFormat = {
						type = "select",
						name = function() return L().secondaryFormat end,
						order = 6,
						width = "relative",
						relWidth = 0.5,
						-- Exactly 3 choices (not 4) -- PERCENT_NUMBER
						-- (percent first, number in parens) is
						-- intentionally left out of the dropdown: it's
						-- not part of the Number/Percent/Number+Percent
						-- grid the user actually picks from, and a 4th
						-- near-duplicate choice caused mix-ups.
						-- FormatOneSide in Panel.lua still understands
						-- PERCENT_NUMBER if it's ever set some other way.
						-- Exactamente 3 opciones (no 4) -- PERCENT_NUMBER
						-- (porcentaje primero, numero entre parentesis) se
						-- deja fuera del dropdown a proposito: no es
						-- parte de la grilla Numero/Porcentaje/
						-- Numero+Porcentaje de la que de verdad se elige,
						-- y una 4ta opcion casi-duplicada causaba
						-- confusion. FormatOneSide en Panel.lua sigue
						-- entendiendo PERCENT_NUMBER si llega a
						-- configurarse de otra forma.
						values = function()
							local l = L()
							return {
								NUMBER = l.fmtNumber,
								PERCENT = l.fmtPercent,
								NUMBER_PERCENT = l.fmtNumberPercent,
							}
						end,
						get = function() return ns.db.profile.panel.secondaryFormat end,
						set = function(_, v)
							ns.db.profile.panel.secondaryFormat = v
							RefreshAll()
						end,
					},
					barSpacing = {
						type = "range",
						name = function() return L().barSpacing end,
						desc = function() return L().barSpacingDesc end,
						order = 11,
						width = "relative",
						relWidth = 0.5,
						min = 0, max = 30, step = 1,
						get = function() return ns.db.profile.panel.barSpacing end,
						set = function(_, v)
							ns.db.profile.panel.barSpacing = v
							RefreshAll()
						end,
					},
					-- Shares a row with "Bar spacing" -- bar height
					-- (thickness) in "Power bars". (There used to be a
					-- "Bar width" here, but it duplicated the panel's own
					-- Width -- Panel.lua's ApplyAppearance already uses
					-- panel.width - PADDING*2 for the bar's real width.
					-- Height, not width, was the one actually missing.)
					-- Comparte fila con "Espacio entre barras" -- alto
					-- (grosor) de las barras en "Barras de poder". (Hubo
					-- un "Ancho de las barras" aqui antes, pero duplicaba
					-- el Ancho del panel -- ApplyAppearance en Panel.lua
					-- ya usa panel.width - PADDING*2 para el ancho real
					-- de la barra. Lo que de verdad faltaba era el alto,
					-- no el ancho.)
					barHeight = {
						type = "range",
						name = function() return L().barHeight end,
						desc = function() return L().barHeightDesc end,
						order = 11.5,
						width = "relative",
						relWidth = 0.5,
						min = 6, max = 40, step = 1,
						get = function() return ns.db.profile.panel.barHeight end,
						set = function(_, v)
							ns.db.profile.panel.barHeight = v
							if ns.Panel then ns.Panel:ApplyAppearance() end; RefreshAll()
						end,
					},
					-- Vertical gap between a bar's label and the bar
					-- itself -- used to be a fixed value (BAR_LABEL_HEIGHT
					-- in Panel.lua) with no control to move it.
					-- Espacio vertical entre la etiqueta de una barra y la
					-- barra misma -- antes era un valor fijo
					-- (BAR_LABEL_HEIGHT en Panel.lua) sin ningun control
					-- para moverlo.
					barLabelGap = {
						type = "range",
						name = function() return L().barLabelGap end,
						desc = function() return L().barLabelGapDesc end,
						order = 11.6,
						width = "relative",
						relWidth = 0.5,
						min = 0, max = 30, step = 1,
						get = function() return ns.db.profile.panel.barLabelGap end,
						set = function(_, v)
							ns.db.profile.panel.barLabelGap = v
							RefreshAll()
						end,
					},
					-- Filler so "Label-to-bar gap" stays alone on its row
					-- (same reason as the other fillers in this tab).
					-- Relleno para que "Espacio etiqueta-barra" quede
					-- solo en su fila (mismo motivo que los demas
					-- rellenos de esta pestaña).
					barLabelGapFiller = {
						type = "description",
						name = "",
						order = 11.7,
						width = "relative",
						relWidth = 0.5,
					},
					expectedFormat = {
						type = "select",
						name = function() return L().expectedFormat end,
						order = 8,
						width = "relative",
						relWidth = 0.5,
						-- Same 3-choices-not-4 reasoning as secondaryFormat
						-- above.
						-- Mismo razonamiento de 3-opciones-no-4 que
						-- secondaryFormat arriba.
						values = function()
							local l = L()
							return {
								NUMBER = l.fmtNumber,
								PERCENT = l.fmtPercent,
								NUMBER_PERCENT = l.fmtNumberPercent,
							}
						end,
						get = function() return ns.db.profile.panel.expectedFormat end,
						set = function(_, v)
							ns.db.profile.panel.expectedFormat = v
							RefreshAll()
						end,
					},
					decimalPlaces = {
						type = "range",
						name = function() return L().decimalPlaces end,
						order = 7,
						width = "relative",
						relWidth = 0.5,
						min = 0, max = 3, step = 1,
						get = function() return ns.db.profile.panel.decimalPlaces end,
						set = function(_, v)
							ns.db.profile.panel.decimalPlaces = v
							RefreshAll()
						end,
					},
					showStatsMode = {
						type = "select",
						name = function() return L().showStatsMode end,
						order = 10,
						width = "relative",
						relWidth = 0.5,
						values = function()
							local l = L()
							return { ALWAYS = l.modeAlways, IN_COMBAT = l.modeCombat, OUT_OF_COMBAT = l.modeOutOfCombat }
						end,
						get = function() return ns.db.profile.panel.showStatsMode end,
						set = function(_, v)
							ns.db.profile.panel.showStatsMode = v
							if ns.Panel then ns.Panel:UpdateVisibility() end
						end,
					},
					bgAlpha = {
						type = "range",
						name = function() return L().bgAlpha end,
						order = 9,
						width = "relative",
						relWidth = 0.5,
						min = 0, max = 1, step = 0.05,
						get = function() return ns.db.profile.panel.bgAlpha end,
						set = function(_, v)
							ns.db.profile.panel.bgAlpha = v
							if ns.Panel then ns.Panel:ApplyAppearance() end
						end,
					},
					-- Toggles paired 50/50 (real relative width, not
					-- "half" -- "half" is a fixed 85px in this AceConfig
					-- build, too narrow for longer labels, which were
					-- getting cut off).
					-- Toggles emparejados 50/50 (ancho relativo real, no
					-- "half" -- "half" es un valor fijo de 85px en esta
					-- version de AceConfig, muy angosto para etiquetas
					-- largas, que se veian cortadas).
					fontOutline = {
						type = "toggle",
						name = function() return L().fontOutline end,
						order = 12,
						width = "relative",
						relWidth = 0.5,
						get = function() return ns.db.profile.panel.fontOutline end,
						set = function(_, v)
							ns.db.profile.panel.fontOutline = v
							if ns.Panel then ns.Panel:ApplyAppearance() end
						end,
					},
					oneLineLayout = {
						type = "toggle",
						name = function() return L().oneLineLayout end,
						order = 13,
						width = "relative",
						relWidth = 0.5,
						get = function() return ns.db.profile.panel.oneLineLayout end,
						set = function(_, v)
							ns.db.profile.panel.oneLineLayout = v
							RefreshAll()
						end,
					},
					barMode = {
						type = "toggle",
						name = function() return L().barMode end,
						desc = function() return L().barModeDesc end,
						order = 14,
						width = "relative",
						relWidth = 0.5,
						get = function() return ns.db.profile.panel.barMode end,
						set = function(_, v)
							ns.db.profile.panel.barMode = v
							RefreshAll()
						end,
					},
					showBorder = {
						type = "toggle",
						name = function() return L().showBorder end,
						order = 15,
						width = "relative",
						relWidth = 0.5,
						get = function() return ns.db.profile.panel.showBorder end,
						set = function(_, v)
							ns.db.profile.panel.showBorder = v
							if ns.Panel then ns.Panel:ApplyAppearance() end
						end,
					},
					locked = {
						type = "toggle",
						name = function() return L().locked end,
						order = 16,
						width = "relative",
						relWidth = 0.5,
						get = function() return ns.db.profile.panel.locked end,
						set = function(_, v) ns.db.profile.panel.locked = v end,
					},
					-- Filler so "Lock position" stays alone on its row
					-- (same reason as barSpacingFiller above).
					-- Relleno para que "Bloquear posicion" quede solo en
					-- su fila (mismo motivo que barSpacingFiller arriba).
					lockedFiller = {
						type = "description",
						name = "",
						order = 16.5,
						width = "relative",
						relWidth = 0.5,
					},
					-- Draws each bar's label on top of the bar itself
					-- (instead of in its own row above it) -- forces a
					-- font outline always, regardless of "Font outline",
					-- so the text stays readable no matter the bar's
					-- current fill color (see ApplyAppearance).
					-- Dibuja la etiqueta de cada barra encima de la barra
					-- misma (en vez de en su propia fila arriba) --
					-- fuerza contorno de fuente siempre, sin importar
					-- "Contorno de fuente", para que el texto siga
					-- leyendose bien sin importar el color de fondo
					-- actual de la barra (ver ApplyAppearance).
					barTextInside = {
						type = "toggle",
						name = function() return L().barTextInside end,
						desc = function() return L().barTextInsideDesc end,
						order = 16.6,
						width = "relative",
						relWidth = 0.5,
						get = function() return ns.db.profile.panel.barTextInside end,
						set = function(_, v)
							ns.db.profile.panel.barTextInside = v
							if ns.Panel then ns.Panel:ApplyAppearance() end; RefreshAll()
						end,
					},
					barTextInsideFiller = {
						type = "description",
						name = "",
						order = 16.7,
						width = "relative",
						relWidth = 0.5,
					},
					-- Left-side filler to push "Reset position" toward
					-- the right of its own row (instead of pinned left).
					-- Relleno a la izquierda para empujar "Restablecer
					-- posicion" hacia el lado derecho de su propia fila
					-- (en vez de pegado a la izquierda).
					resetPositionFiller = {
						type = "description",
						name = "",
						order = 17,
						width = "relative",
						relWidth = 0.5,
					},
					resetPosition = {
						type = "execute",
						name = function() return L().resetPosition end,
						order = 18,
						width = "relative",
						relWidth = 0.4,
						func = function()
							ns.db.profile.panelPosition = { point = "CENTER", x = 0, y = 0 }
							if ns.Panel then ns.Panel:ApplyPosition() end
						end,
					},
				},
			},
			-- New dedicated tab for Power Bars settings, split out of
			-- Panel -- empty for now, controls move here next.
			-- Nueva pestaña dedicada para la config de Barras de poder,
			-- separada de Panel -- vacía por ahora, los controles se
			-- mueven aquí después.
			barsGroup = {
				type = "group",
				name = function() return L().barMode end,
				order = 2.5,
				args = {},
			},
			showStats = {
				type = "group",
				name = function() return L().showStatsHeader end,
				order = 3,
				args = {
					allSecondaries = {
						type = "toggle",
						name = function() return L().showAllSecondaries end,
						order = 0,
						get = function()
							local s = ns.db.profile.panel.showStats
							return s.crit and s.haste and s.mastery and s.vers
						end,
						set = function(_, v)
							local s = ns.db.profile.panel.showStats
							s.crit, s.haste, s.mastery, s.vers = v, v, v, v
							RefreshAll()
						end,
					},
				},
			},
		},
	}
end

-- Checkbox per stat key -- always labeled with Panel's English stat names,
-- never translated, so it stays consistent with what the panel itself shows.
-- Checkbox por cada stat -- siempre con el nombre en ingles que usa Panel,
-- nunca traducido, para que quede consistente con lo que muestra el panel.
local function BuildShowStatsArgs(options)
	local order = 1
	for _, key in ipairs(ns.Panel.ORDER) do
		options.args.showStats.args[key] = {
			type = "toggle",
			name = ns.Panel.LABELS[key],
			order = order,
			get = function() return ns.db.profile.panel.showStats[key] end,
			set = function(_, v)
				ns.db.profile.panel.showStats[key] = v
				RefreshAll()
			end,
		}
		order = order + 1
	end
end

-- 7 weight fields in 2 rows: first 4 (primary/crit/haste/mastery) at 0.24
-- each (0.96 total), last 3 (vers/weaponDps/offHandWeaponDps) at 0.32 each
-- (0.96 total) -- "relative"/relWidth, not "half"/"double", since those
-- are fixed-pixel widths in this AceConfig build, not real fractions of
-- the row (see the Panel tab's width_multiplier note above).
-- 7 campos de peso en 2 filas: los primeros 4 (primary/crit/haste/mastery)
-- a 0.24 cada uno (0.96 en total), los ultimos 3
-- (vers/weaponDps/offHandWeaponDps) a 0.32 cada uno (0.96 en total) --
-- "relative"/relWidth, no "half"/"double", ya que esos son anchos fijos en
-- pixeles en esta version de AceConfig, no fracciones reales de la fila
-- (ver la nota de width_multiplier de la pestaña Panel, arriba).
local function BuildWeightArgs(options)
	local order = 5
	for i, key in ipairs(STAT_KEYS) do
		options.args.scales.args["weight_" .. key] = {
			type = "input",
			name = function() return WeightLabel(key) end,
			order = order,
			width = "relative",
			relWidth = (i <= 4) and 0.24 or 0.32,
			get = function()
				local scale = GetActiveScale()
				return scale and tostring(scale[key] or 0) or "0"
			end,
			set = function(_, v)
				local scale = GetActiveScale()
				if not scale then return end
				scale[key] = tonumber(v) or scale[key]
				RefreshAll()
			end,
			disabled = function() return not GetActiveScale() end,
		}
		order = order + 1
	end
end

-- One visible sub-group per saved scale, so more than one can be seen at
-- once (with its non-zero weights summarized) instead of only through the
-- collapsed "Active scale" dropdown. Rebuilt fresh each time the options
-- table is requested (see Config:Init(), which registers a function
-- instead of a static table) so newly created/deleted scales show up
-- immediately.
-- Un subgrupo visible por escala guardada, para ver mas de una a la vez
-- (con sus pesos distintos de cero resumidos) en vez de solo a traves del
-- dropdown colapsado "Escala activa". Se reconstruye cada vez que se pide
-- la tabla de opciones (ver Config:Init(), que registra una funcion en
-- vez de una tabla estatica) para que las escalas creadas/eliminadas
-- aparezcan de inmediato.
local function BuildScaleListArgs(options)
	local group = options.args.scaleList
	group.args = {}

	local names = {}
	for name in pairs(ns.db.char.scales) do
		table.insert(names, name)
	end
	table.sort(names)

	if #names == 0 then
		group.args.empty = {
			type = "description",
			order = 0,
			name = function() return L().scaleListEmpty end,
		}
		return
	end

	for i, name in ipairs(names) do
		local scale = ns.db.char.scales[name]

		group.args["entry_" .. i] = {
			type = "group",
			inline = true,
			order = i,
			-- Functions, not snapshot values, so clicking "Use this
			-- scale" on ANY entry immediately updates which one shows
			-- "(active)" and which "Use" button is disabled, without
			-- closing/reopening the panel (AceConfigDialog re-evaluates
			-- these after every set-callback in the same open dialog).
			-- Funciones, no valores capturados una vez, para que hacer
			-- clic en "Usar esta escala" en CUALQUIER tarjeta actualice
			-- de inmediato cual muestra "(activa)" y cual boton "Usar"
			-- esta deshabilitado, sin cerrar/reabrir el panel
			-- (AceConfigDialog reevalua esto despues de cada callback
			-- set, en el mismo dialogo abierto).
			name = function()
				if ns.db.profile.activeScale == name then
					return name .. L().scaleListActiveTag
				end
				return name
			end,
			args = {
				summary = {
					type = "description",
					order = 1,
					name = function()
						local parts = {}
						for _, key in ipairs(STAT_KEYS) do
							local w = scale[key]
							if w and w ~= 0 then
								table.insert(parts, WeightLabel(key) .. "=" .. tostring(w))
							end
						end
						if #parts == 0 then
							return "(" .. L().scaleListEmpty .. ")"
						end
						return table.concat(parts, "   ")
					end,
				},
				-- The active scale always shows in the tooltip (as
				-- always) -- this toggle is for seeing other scales
				-- ALSO, at the same time (see Compare.lua, AddScaleLine),
				-- without having to activate them.
				-- La escala activa siempre aparece en el tooltip (como
				-- siempre) -- este toggle es para ver ADEMAS otras
				-- escalas al mismo tiempo (ver Compare.lua,
				-- AddScaleLine), sin tener que activarlas.
				showInTooltip = {
					type = "toggle",
					order = 1.5,
					name = function() return L().showInTooltip end,
					desc = function() return L().showInTooltipDesc end,
					get = function() return scale.showInTooltip end,
					set = function(_, v) scale.showInTooltip = v end,
				},
				use = {
					type = "execute",
					order = 2,
					name = function() return L().useScale end,
					disabled = function() return ns.db.profile.activeScale == name end,
					func = function()
						ns.db.profile.activeScale = name
						RefreshAll()
					end,
				},
				remove = {
					type = "execute",
					order = 3,
					name = function() return L().removeScale end,
					confirm = true,
					confirmText = string.format(L().removeScaleConfirm, name),
					func = function()
						ns.db.char.scales[name] = nil
						if ns.db.profile.activeScale == name then
							ns.db.profile.activeScale = nil
						end
						RefreshAll()
					end,
				},
				-- "Rename" starts as just a button; clicking it reveals
				-- the textbox below (renameExpanded, session-only UI
				-- state) -- keeps the card compact when nothing is being
				-- renamed, and the input gets its own row with room to
				-- spare so its accept checkmark doesn't overlap the text.
				-- "Renombrar" arranca como solo un boton; al hacer clic
				-- revela el textbox de abajo (renameExpanded, estado de
				-- UI solo-de-sesion) -- mantiene la tarjeta compacta
				-- cuando no se esta renombrando nada, y el campo tiene su
				-- propia fila con espacio de sobra para que su check de
				-- aceptar no se sobreponga con el texto.
				renameToggle = {
					type = "execute",
					order = 4,
					name = function()
						return renameExpanded[name] and L().cancelRename or L().renameScale
					end,
					func = function()
						if renameExpanded[name] then
							renameExpanded[name] = nil
						else
							renameExpanded[name] = true
						end
					end,
				},
				-- Renames THIS card's scale specifically (not necessarily
				-- the active one) -- moves its weight table to the new
				-- key in char.scales, keeps every weight, and follows
				-- activeScale along if this happened to be the active
				-- one. Refuses to clobber an existing scale with the
				-- same name.
				-- Renombra la escala de ESTA tarjeta en particular (no
				-- necesariamente la activa) -- mueve su tabla de pesos a
				-- la nueva llave en char.scales, conserva todos los
				-- pesos, y sigue a activeScale si esta resulto ser la
				-- activa. Se niega a pisar una escala existente con el
				-- mismo nombre.
				renameInput = {
					type = "input",
					order = 4.5,
					width = "double",
					name = function() return L().renameScale end,
					hidden = function() return not renameExpanded[name] end,
					get = function() return "" end,
					set = function(_, v)
						if not v or v == "" or v == name then return end
						if ns.db.char.scales[v] then
							ns.addon:Print(L().renameScaleExists)
							return
						end
						ns.db.char.scales[v] = ns.db.char.scales[name]
						ns.db.char.scales[name] = nil
						if ns.db.profile.activeScale == name then
							ns.db.profile.activeScale = v
						end
						renameExpanded[name] = nil
						RefreshAll()
					end,
				},
			},
		}
	end
end

local function ShowVersionTag(container)
	if not container or not container.frame then
		return
	end
	local frame = container.frame
	if frame.stmVersionText then
		return
	end
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local version = getMeta and getMeta(ADDON_NAME, "Version")
	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -8)
	fs:SetText(version and ("v" .. version) or "")
	frame.stmVersionText = fs
end

local function OpenPanel()
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")
	AceConfigDialog:Open("StatsMythic")
	ShowVersionTag(AceConfigDialog.OpenFrames["StatsMythic"])
end

-- Reads from !BugGrabber's own error database (BugGrabber:GetDB(), a real
-- global it exposes -- confirmed by reading its source, not guessed)
-- instead of hooking the error handler ourselves, since BugGrabber
-- already owns that and is commonly installed alongside BugSack. Shows
-- the most recent errors in a plain AceGUI MultiLineEditBox --
-- select-all-and-copy, same pattern BugSack itself uses, just easier to
-- grab in one go without hunting for a copy button.
-- Lee de la propia base de errores de !BugGrabber (BugGrabber:GetDB(), un
-- global real que expone -- confirmado leyendo su codigo fuente, no
-- adivinado) en vez de enganchar el manejador de errores nosotros mismos,
-- ya que BugGrabber ya es dueño de eso y suele instalarse junto con
-- BugSack. Muestra los errores mas recientes en un MultiLineEditBox plano
-- de AceGUI -- seleccionar-todo-y-copiar, mismo patron que usa BugSack,
-- solo que mas facil de agarrar de una vez sin buscar un boton de copiar.
local errorViewerFrame
local function OpenErrorViewer()
	if not BugGrabber then
		ns.addon:Print(L().errorsNoBugGrabber)
		return
	end

	local db = BugGrabber:GetDB()
	if not db or #db == 0 then
		ns.addon:Print(L().errorsNone)
		return
	end

	local MAX_ERRORS = 10
	local parts = {}
	local shown = 0
	for i = #db, 1, -1 do
		local err = db[i]
		shown = shown + 1
		table.insert(parts, string.format("[%s] (x%d)\n%s\n%s",
			date("%H:%M:%S", err.time), err.counter or 1, err.message or "", err.stack or ""))
		if shown >= MAX_ERRORS then break end
	end

	local AceGUI = LibStub("AceGUI-3.0")
	if not errorViewerFrame then
		errorViewerFrame = AceGUI:Create("Frame")
		errorViewerFrame:SetLayout("Fill")
		errorViewerFrame:SetWidth(720)
		errorViewerFrame:SetHeight(520)
		errorViewerFrame:SetCallback("OnClose", function(widget) widget:Hide() end)

		local editbox = AceGUI:Create("MultiLineEditBox")
		editbox:SetLabel("")
		editbox:DisableButton(true)
		editbox:SetNumLines(28)
		errorViewerFrame.stmEditBox = editbox
		errorViewerFrame:AddChild(editbox)
	end

	errorViewerFrame:SetTitle(string.format("StatsMythic - %s (%d)", L().errorsTitle, shown))
	errorViewerFrame.stmEditBox:SetText(table.concat(parts, "\n\n----------\n\n"))
	errorViewerFrame:Show()
	errorViewerFrame.stmEditBox:SetFocus()
end

local function PrintStatus()
	local name = ns.db.profile.activeScale or "(ninguna)"
	local count = 0
	for _ in pairs(ns.db.char.scales) do count = count + 1 end
	ns.addon:Print(string.format("Escala activa: %s | %d escalas guardadas | Perfil: %s", name, count, ns.db:GetCurrentProfile()))
end

function Config:Init()
	local AceConfig = LibStub("AceConfig-3.0")
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")
	local AceDBOptions = LibStub("AceDBOptions-3.0")

	-- Full AceDB profile management (create/copy/delete/switch/reset) --
	-- since the whole panel look lives in db.profile, switching profiles
	-- here switches the entire customization at once, same idea as
	-- Stats+'s own profile system. Built once and reused both as its own
	-- Blizzard Options sub-category AND embedded directly as a tab
	-- inside /stm config -- AceDBOptions' own get/set/values are already
	-- dynamic functions, so the same table works either way without a
	-- separate rebuild.
	-- Manejo completo de perfiles de AceDB (crear/copiar/eliminar/
	-- cambiar/reiniciar) -- ya que toda la apariencia del panel vive en
	-- db.profile, cambiar de perfil aqui cambia toda la personalizacion
	-- de una sola vez, misma idea que el sistema de perfiles propio de
	-- Stats+. Se arma una sola vez y se reusa tanto como su propia
	-- subcategoria de Opciones de Blizzard COMO embebido directo en una
	-- pestaña dentro de /stm config -- los get/set/values propios de
	-- AceDBOptions ya son funciones dinamicas, asi que la misma tabla
	-- funciona en los dos casos sin reconstruirla aparte.
	local profileOptions = AceDBOptions:GetOptionsTable(ns.db)
	profileOptions.name = function() return L().profilesHeader end
	profileOptions.order = 0.5 -- leftmost tab / pestaña mas a la izquierda

	-- AceDBOptions-3.0's own labels ("New", "Copy From", "Delete a
	-- Profile", etc.) follow the WoW CLIENT's own language (GetLocale(),
	-- verified at AceDBOptions-3.0.lua:45), completely separate from our
	-- own "Menu language" toggle -- toggling ours never changed that
	-- tab's contents. Fix: `profileOptions.args` points at AceDBOptions'
	-- own module-level `optionsTable`, SHARED via LibStub with every
	-- other addon that embeds this same library version -- mutating
	-- those entries in place would leak our overrides into other addons'
	-- profile screens too. So instead we build our OWN shallow-copied
	-- args table (copy each entry, override name/desc/confirmText with
	-- our own L() strings) and point profileOptions.args at that copy --
	-- the shared library table itself is never touched.
	-- Las etiquetas propias de AceDBOptions-3.0 ("New", "Copy From",
	-- "Delete a Profile", etc.) siguen el idioma del CLIENTE de WoW
	-- (GetLocale(), verificado en AceDBOptions-3.0.lua:45), totalmente
	-- separado de nuestro propio toggle "Idioma del menu" -- cambiar el
	-- nuestro nunca cambiaba el contenido de esa pestaña. Fix:
	-- `profileOptions.args` apunta a la `optionsTable` propia de
	-- AceDBOptions, a nivel de modulo, COMPARTIDA via LibStub con
	-- cualquier otro addon que embeba esta misma version de la libreria
	-- -- mutar esas entradas en el lugar filtraria nuestros cambios a las
	-- pantallas de perfil de otros addons tambien. Por eso armamos
	-- nuestra PROPIA copia superficial de la tabla args (copiando cada
	-- entrada, sobreescribiendo name/desc/confirmText con nuestros
	-- propios strings de L()) y apuntamos profileOptions.args a esa
	-- copia -- la tabla compartida de la libreria nunca se toca.
	do
		local shared = profileOptions.args
		local ownArgs = {}
		for key, entry in pairs(shared) do
			local copy = {}
			for k, v in pairs(entry) do
				copy[k] = v
			end
			ownArgs[key] = copy
		end

		ownArgs.desc.name = function() return L().profIntro .. "\n" end
		ownArgs.descreset.name = function() return L().profResetDesc end
		ownArgs.reset.name = function() return L().profReset end
		ownArgs.reset.desc = function() return L().profResetSub end
		ownArgs.current.name = function(info)
			return L().profCurrentPrefix .. " " .. NORMAL_FONT_COLOR_CODE .. info.handler:GetCurrentProfile() .. FONT_COLOR_CODE_CLOSE
		end
		ownArgs.choosedesc.name = function() return "\n" .. L().profChooseDesc end
		ownArgs.new.name = function() return L().profNew end
		ownArgs.new.desc = function() return L().profNewSub end
		ownArgs.choose.name = function() return L().profChoose end
		ownArgs.choose.desc = function() return L().profChooseSub end
		ownArgs.copydesc.name = function() return "\n" .. L().profCopyDesc end
		ownArgs.copyfrom.name = function() return L().profCopy end
		ownArgs.copyfrom.desc = function() return L().profCopyDesc end
		ownArgs.deldesc.name = function() return "\n" .. L().profDeleteDesc end
		ownArgs.delete.name = function() return L().profDelete end
		ownArgs.delete.desc = function() return L().profDeleteSub end
		-- confirmText must be a plain string, not a function, in this
		-- bundled AceConfig build (same constraint already hit on
		-- deleteScale/removeScale above) -- resolved once here, won't
		-- hot-swap if the language toggle changes later in the same
		-- session, same tradeoff already accepted there.
		-- confirmText tiene que ser un string plano, no una funcion, en
		-- esta version empaquetada de AceConfig (misma limitacion ya
		-- encontrada en deleteScale/removeScale arriba) -- resuelto una
		-- sola vez aqui, no se actualiza solo si el idioma cambia despues
		-- en la misma sesion, mismo trade-off ya aceptado ahi.
		ownArgs.delete.confirmText = L().profDeleteConfirm

		-- Language + minimap icon live here as their own boxed
		-- sub-section at the bottom of Profiles (used to be a separate
		-- "General" tab).
		-- Idioma + icono de minimapa viven aqui, como su propio recuadro
		-- al final de Perfiles (antes era una pestaña "General" aparte).
		ownArgs.generalSettings = {
			type = "group",
			order = 100,
			inline = true,
			name = function() return L().generalHeader end,
			args = {
				language = {
					type = "select",
					name = function() return L().uiLanguage end,
					order = 1,
					values = { es = "Español", en = "English" },
					get = function() return ns.db.global.uiLocale end,
					set = function(_, v) ns.db.global.uiLocale = v end,
				},
				showIcon = {
					type = "toggle",
					name = function() return L().showMinimapIcon end,
					order = 2,
					get = function() return not ns.db.global.minimapIcon.hide end,
					set = function(_, v)
						ns.db.global.minimapIcon.hide = not v
						local LDBIcon = LibStub("LibDBIcon-1.0", true)
						if LDBIcon then
							if v then LDBIcon:Show("StatsMythic") else LDBIcon:Hide("StatsMythic") end
						end
					end,
				},
			},
		}

		profileOptions.args = ownArgs
	end

	-- Registered as a FUNCTION (not a pre-built table) so it's rebuilt
	-- fresh every time the panel opens -- BuildScaleListArgs needs this
	-- to reflect newly created/deleted scales without requiring a UI
	-- reload.
	-- Registrado como una FUNCION (no una tabla ya armada) para que se
	-- reconstruya cada vez que se abre el panel -- BuildScaleListArgs
	-- necesita esto para reflejar escalas creadas/eliminadas sin
	-- necesitar un reload de la UI.
	local function BuildFullOptions()
		local options = GetOptions()
		BuildShowStatsArgs(options)
		BuildWeightArgs(options)
		BuildScaleListArgs(options)
		options.args.profiles = profileOptions
		return options
	end

	AceConfig:RegisterOptionsTable("StatsMythic", BuildFullOptions)
	AceConfigDialog:AddToBlizOptions("StatsMythic", "StatsMythic")

	AceConfig:RegisterOptionsTable("StatsMythic-Profiles", profileOptions)
	AceConfigDialog:AddToBlizOptions("StatsMythic-Profiles", "Perfiles", "StatsMythic")

	ns.addon:RegisterChatCommand("statsmythic", "OnSlash")
	-- "/stm m" also opens the config -- "/stats" would collide with
	-- Stats+'s own slash command, so it's deliberately avoided.
	-- "/stm m" tambien abre la configuracion -- "/stats" chocaria con el
	-- comando propio de Stats+, asi que se evita a proposito.
	ns.addon:RegisterChatCommand("stm", "OnSlash")

	function ns.addon:OnSlash(input)
		local cmd, rest = input:match("^(%S*)%s*(.-)$")
		cmd = (cmd or ""):lower()

		if cmd == "" or cmd == "config" or cmd == "m" then
			OpenPanel()
		elseif cmd == "lock" then
			ns.db.profile.panel.locked = true
			self:Print("Panel bloqueado.")
		elseif cmd == "unlock" then
			ns.db.profile.panel.locked = false
			self:Print("Panel desbloqueado.")
		elseif cmd == "debugitem" then
			if ns.Compare then ns.Compare:DebugCurrentTooltipItem() end
		elseif cmd == "debugchar" then
			if ns.CharacterPane then ns.CharacterPane:DebugDump() end
		elseif cmd == "debugseason" then
			local id = ns.PlayerStats and ns.PlayerStats:GetSeasonID()
			self:Print(id and ("ID de temporada detectado: " .. id) or "No se pudo detectar ningun ID de temporada (C_SeasonInfo/C_MythicPlus no disponibles o devolvieron 0).")
		elseif cmd == "status" then
			PrintStatus()
		elseif cmd == "errors" or cmd == "bugs" then
			OpenErrorViewer()
		elseif cmd == "recalc" then
			if ns.PlayerStats then
				ns.PlayerStats:RecalculateExpectedBudget()
			end
			if ns.Panel then ns.Panel:Refresh() end
			if ns.CharacterPane then ns.CharacterPane:Refresh() end
			self:Print("Objetivo de Esperado recalculado con tu rating actual.")
		else
			self:Print("Comandos: /stm config | lock | unlock | debugitem | debugchar | debugseason | status | errors | recalc")
		end
	end
end
