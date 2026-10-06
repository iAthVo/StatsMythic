--[[ StatsMythic · Core.lua
Addon bootstrap, saved-variable defaults, and the core AceAddon lifecycle.
© 2026 TavoD_Gus_KrG · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

local defaults = {
	global = {
		uiLocale = "es", -- "es" | "en" -- menu/UI text only, stat names stay English
		-- "es" | "en" -- solo texto del menu, los nombres de los stats siguen en ingles
		minimapIcon = { hide = false },
	},
	-- AceDB's "char" scope is keyed to this exact character ("Name - Realm"),
	-- independent of profiles -- every character gets its own scales for free.
	-- El scope "char" de AceDB se liga a este personaje exacto ("Nombre -
	-- Reino"), independiente de los perfiles -- cada personaje recibe sus
	-- propias escalas sin esfuerzo extra.
	char = {
		scales = {},
	},
	profile = {
		activeScale = nil,
		panelPosition = { point = "CENTER", x = 0, y = 0 },
		panelShown = true,
		-- Everything about how the panel LOOKS is per-profile, so different
		-- characters/specs can each have their own setup.
		-- Todo lo visual del panel vive por perfil, asi cada
		-- personaje/spec puede tener su propia configuracion.
		panel = {
			width = 220,
			barHeight = 14, -- bar thickness in "Power bars" / grosor de barra en "Barras de poder"
			barLabelGap = 14, -- vertical gap between a bar's label and the bar / espacio vertical entre etiqueta y barra
			barTextInside = false, -- draw the label on top of the bar / dibujar la etiqueta encima de la barra

			font = "Friz Quadrata TT",
			fontSize = 12,
			fontOutline = true,
			lineSpacing = 16,
			barSpacing = 6, -- gap between bars in "Power bars", separate from lineSpacing
			-- espacio entre barras en "Barras de poder", aparte de lineSpacing
			decimalPlaces = 2,
			textAlign = "LEFT", -- LEFT | CENTER | RIGHT
			oneLineLayout = false,
			barMode = false, -- "Power bars": secondaries as a StatusBar instead of text
			-- "Barras de poder": secundarios como StatusBar en vez de texto
			secondaryFormat = "NUMBER_PERCENT", -- Character side: NUMBER | PERCENT | NUMBER_PERCENT
			expectedFormat = "NUMBER_PERCENT", -- Recommended side, same 3 options, independent
			showStatsMode = "ALWAYS", -- ALWAYS | IN_COMBAT | OUT_OF_COMBAT
			showStats = {
				primary = true,
				ilvl = true,
				crit = true,
				haste = true,
				mastery = true,
				vers = true,
				leech = true,
				avoidance = true,
			},
			bgAlpha = 0.75, -- 0 = fully transparent / 0 = totalmente transparente
			showBorder = true,
			locked = false,
		},
	},
}

local StatsMythic = LibStub("AceAddon-3.0"):NewAddon("StatsMythic", "AceConsole-3.0", "AceEvent-3.0")
_G.StatsMythic = StatsMythic
ns.addon = StatsMythic

-- Isolates each module's startup so one module erroring in Init() never
-- blocks the modules after it from loading.
-- Aisla el arranque de cada modulo para que un error en el Init() de uno
-- no bloquee la carga de los que siguen.
local function SafeInit(name, module)
	if not module then
		return
	end
	local ok, err = pcall(module.Init, module)
	if not ok then
		StatsMythic:Print("Error al iniciar " .. name .. ": " .. tostring(err))
	end
end

function StatsMythic:OnInitialize()
	-- No third argument here: AceDB-3.0 treats a literal `true` as "use a
	-- profile literally named 'Default' for everyone", not "one profile per
	-- character". Omitting the argument is what gives each character its
	-- own profile automatically.
	-- Sin tercer argumento: AceDB-3.0 trata un `true` literal como "usar un
	-- perfil llamado 'Default' para todos", no "un perfil por personaje".
	-- Omitir el argumento es lo que da perfil-por-personaje automatico.
	self.db = LibStub("AceDB-3.0"):New("StatsMythicDB", defaults)
	ns.db = self.db
end

local function CreateMinimapIcon()
	local LDB = LibStub("LibDataBroker-1.1", true)
	local LDBIcon = LibStub("LibDBIcon-1.0", true)
	if not LDB or not LDBIcon then
		return
	end

	local dataObject = LDB:NewDataObject("StatsMythic", {
		type = "launcher",
		icon = "Interface\\Icons\\INV_Misc_Statue_02",
		OnClick = function()
			if ns.Config then
				LibStub("AceConfigDialog-3.0"):Open("StatsMythic")
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("StatsMythic")
			tooltip:AddLine("Clic izquierdo: abrir configuracion")
		end,
	})

	LDBIcon:Register("StatsMythic", dataObject, ns.db.global.minimapIcon)
end

function StatsMythic:OnEnable()
	SafeInit("PlayerStats", ns.PlayerStats)
	SafeInit("Panel", ns.Panel)
	SafeInit("Compare", ns.Compare)
	SafeInit("CharacterPane", ns.CharacterPane)
	SafeInit("Config", ns.Config)

	CreateMinimapIcon()

	-- A different AceDB profile can have an entirely different panel look --
	-- re-apply appearance/position whenever the active profile changes.
	-- Un perfil de AceDB distinto puede tener una apariencia de panel
	-- totalmente distinta -- se reaplica apariencia/posicion cada vez que
	-- cambia el perfil activo.
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	-- Anything that can change a live combat rating, buff/proc, or gear
	-- piece refreshes the panel, keeping it live instead of a login snapshot.
	-- Cualquier cosa que pueda cambiar un rating de combate en vivo,
	-- buff/proc, o pieza de equipo refresca el panel, para que sea en vivo
	-- y no una foto tomada solo al iniciar sesion.
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnStatsChanged")
	self:RegisterEvent("COMBAT_RATING_UPDATE", "OnStatsChanged")
	self:RegisterEvent("MASTERY_UPDATE", "OnStatsChanged")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnStatsChanged")
	-- AceEvent-3.0 has no unit-filtered RegisterUnitEvent (that's a raw Frame
	-- API method) -- register plain and filter by unit inside the handler.
	-- AceEvent-3.0 no tiene un RegisterUnitEvent filtrado por unidad (eso es
	-- un metodo de Frame, no del mixin) -- se registra normal y se filtra
	-- por unidad dentro del handler.
	self:RegisterEvent("UNIT_AURA", "OnUnitEvent")
	self:RegisterEvent("UNIT_STATS", "OnUnitEvent")

	self:OnStatsChanged()
end

function StatsMythic:OnProfileChanged()
	if ns.Panel then
		ns.Panel:ApplyPosition()
		ns.Panel:ApplyAppearance()
		ns.Panel:Refresh()
	end
end

function StatsMythic:OnUnitEvent(event, unit)
	if unit ~= "player" then
		return
	end
	self:OnStatsChanged()
end

function StatsMythic:OnStatsChanged()
	if ns.Panel then
		ns.Panel:Refresh()
	end
	if ns.CharacterPane then
		ns.CharacterPane:Refresh()
	end
end
