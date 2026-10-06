--[[ StatsMythic · PlayerStats.lua
Pure data module (no frames): reads live stats from Blizzard's own API and
computes the "Recommended" proportional redistribution.
© 2026 TavoD_Gus_KrG · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

-- "Character" reads straight from Blizzard's API, never computed by us.
-- "Recommended" is the one formula that's ours: redistribute the player's
-- current total secondary rating proportionally by the configured weights.
-- "Personaje" se lee directo de la API de Blizzard, nunca lo calculamos
-- nosotros. "Recomendado" es la unica formula propia: repartir el rating
-- secundario total actual de forma proporcional segun los pesos cargados.

local PlayerStats = {}
ns.PlayerStats = PlayerStats

local STAT_KEYS = { "crit", "haste", "mastery", "vers" }
PlayerStats.STAT_KEYS = STAT_KEYS

-- Blizzard's "Secret Values" protection: in some contexts (reliably during
-- combat) combat-rating/unit-stat getters return a number that can be
-- *displayed* but throws on arithmetic AND on comparison. Each named value
-- keeps its own last-known-good number and freezes on that while secreted,
-- instead of falling back to 0 (which flashed the whole panel to zero the
-- moment combat started).
-- Proteccion "Secret Values" de Blizzard: en ciertos contextos (de forma
-- confiable, en combate) los getters de rating/stat devuelven un numero que
-- se puede *mostrar* pero truena en aritmetica Y en comparaciones. Cada
-- valor nombrado guarda su propio ultimo numero bueno conocido y se congela
-- ahi mientras este protegido, en vez de caer a 0 (que hacia parpadear todo
-- el panel a cero en cuanto empezaba el combate).
local lastGoodValues = {}

local function SafeNumber(key, value)
	if type(value) == "number" then
		local ok, result = pcall(function() return value + 0 end)
		if ok then
			lastGoodValues[key] = result
			return result
		end
	end
	return lastGoodValues[key] or 0
end

local function DetectPrimaryStat()
	-- Cached per-attribute, not just the final answer, so one attribute
	-- going secret mid-combat can't flip which stat counts as primary.
	-- Cacheado por atributo, no solo la respuesta final, para que un solo
	-- atributo protegido a mitad de combate no cambie cual stat cuenta
	-- como principal.
	local str = SafeNumber("attr_str", UnitStat("player", 1))
	local agi = SafeNumber("attr_agi", UnitStat("player", 2))
	local int = SafeNumber("attr_int", UnitStat("player", 4))
	if str >= agi and str >= int then
		return "Strength", 1
	elseif agi >= int then
		return "Agility", 2
	else
		return "Intellect", 4
	end
end

-- Returns name, current value (effective, including gear/buffs).
-- Devuelve nombre, valor actual (efectivo, con equipo/buffs incluidos).
function PlayerStats:GetPrimaryStat()
	local name, index = DetectPrimaryStat()
	local base, effective = UnitStat("player", index)
	return name, SafeNumber("primaryValue", effective or base)
end

-- Returns equipped ilvl, overall (bags-included) ilvl.
-- Devuelve ilvl equipado, ilvl general (bolsas incluidas).
function PlayerStats:GetItemLevel()
	local overall, equipped = GetAverageItemLevel()
	return SafeNumber("ilvlEquipped", equipped), SafeNumber("ilvlOverall", overall)
end

-- Season ilvl ceiling + upgrade-track floors, for the Item Level power bar
-- (see Panel.lua). Blizzard exposes no API for this -- not even large
-- libraries like LibOpenRaid/Details rely on one, they hand-edit it every
-- patch too. Checked against real data mined by KeystoneLoot
-- (Libs\..\KeystoneLoot\data\upgrade_tracks.lua, auto-generated) + the
-- Method.gg guide. Update by hand each season.
-- Techo de ilvl de temporada + pisos de racha, para la barra de poder de
-- Item Level (ver Panel.lua). Blizzard no expone ninguna API para esto -- ni
-- siquiera librerias grandes como LibOpenRaid/Details confian en una, lo
-- anotan a mano cada parche tambien. Verificado contra datos reales minados
-- por KeystoneLoot (Libs\..\KeystoneLoot\data\upgrade_tracks.lua, generado
-- automaticamente) + la guia de Method.gg. Actualizar a mano cada temporada.
local FALLBACK_ILVL_DATA = {
	max = 344, -- absolute season ceiling / techo absoluto de la temporada
	veteran = 279, -- Veteran track floor / piso de la racha Veterano
	champion = 292, -- Champion track floor / piso de la racha Campeon
	myth = 318, -- Myth track floor (Hero folds into this transition) / piso de la racha Mitico
}

-- Keyed by the real season ID from C_SeasonInfo.GetCurrentDisplaySeasonID()
-- (see /stm debugseason) -- empty for now since the real ID can't be
-- confirmed without being in the client. Once confirmed, add an entry here
-- as SEASON_ILVL_DATA[realId] = {...}; FALLBACK_ILVL_DATA then becomes just
-- the fallback for an unrecognized season.
-- Llave = ID real de temporada de C_SeasonInfo.GetCurrentDisplaySeasonID()
-- (ver /stm debugseason) -- vacia por ahora porque el ID real no se puede
-- confirmar sin estar en el cliente. Al confirmarlo, se agrega aqui como
-- SEASON_ILVL_DATA[idReal] = {...}; FALLBACK_ILVL_DATA pasa a ser solo el
-- respaldo para una temporada no reconocida.
local SEASON_ILVL_DATA = {}

-- C_SeasonInfo.GetCurrentDisplaySeasonID() is the real modern function
-- (confirmed in use in SimulationCraft's bonusrolls.lua); C_MythicPlus.
-- GetCurrentSeason() is the older fallback, unreliable without calling
-- RequestMapInfo() first. Neither returns an ilvl -- only a season ID, used
-- to pick a SEASON_ILVL_DATA entry.
-- C_SeasonInfo.GetCurrentDisplaySeasonID() es la funcion moderna real
-- (confirmada en uso en bonusrolls.lua de SimulationCraft); C_MythicPlus.
-- GetCurrentSeason() es el respaldo mas viejo, poco fiable sin llamar
-- RequestMapInfo() antes. Ninguna devuelve un ilvl -- solo un ID de
-- temporada, usado para elegir una entrada de SEASON_ILVL_DATA.
function PlayerStats:GetSeasonID()
	if C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
		local id = C_SeasonInfo.GetCurrentDisplaySeasonID()
		if id and id > 0 then
			return id
		end
	end
	if C_MythicPlus then
		if C_MythicPlus.RequestMapInfo then
			C_MythicPlus.RequestMapInfo()
		end
		if C_MythicPlus.GetCurrentSeason then
			local id = C_MythicPlus.GetCurrentSeason()
			if id and id > 0 then
				return id
			end
		end
	end
	return nil
end

-- Ilvl data for the active season -- a recognized ID uses its own entry;
-- otherwise (or if no ID could be detected) falls back to the last known
-- season's data. Never errors; worst case it's just outdated.
-- Datos de ilvl de la temporada activa -- un ID reconocido usa su propia
-- entrada; si no (o si no se detecto ningun ID), cae a los datos de la
-- ultima temporada conocida. Nunca falla; en el peor caso queda
-- desactualizado.
function PlayerStats:GetSeasonIlvlData()
	local id = self:GetSeasonID()
	return (id and SEASON_ILVL_DATA[id]) or FALLBACK_ILVL_DATA
end

-- { crit = {rating=, pct=}, haste = {...}, mastery = {...}, vers = {...} }
function PlayerStats:GetSecondaryActuals()
	return {
		crit = {
			rating = SafeNumber("critRating", GetCombatRating(CR_CRIT_MELEE)),
			pct = SafeNumber("critPct", GetCritChance()),
		},
		haste = {
			rating = SafeNumber("hasteRating", GetCombatRating(CR_HASTE_MELEE)),
			pct = SafeNumber("hastePct", GetHaste()),
		},
		mastery = {
			rating = SafeNumber("masteryRating", GetCombatRating(CR_MASTERY)),
			pct = SafeNumber("masteryPct", GetMasteryEffect()),
		},
		-- Versatility has no simple no-arg "current % from this rating"
		-- getter -- GetVersatilityBonus needs a unit + bonus type and
		-- returns the damage-reduction side. GetCombatRatingBonus(CR) is
		-- the generic getter that actually returns the damage-done percent
		-- (confirmed against Stats+'s own use of the same call).
		-- Versatility no tiene un getter simple sin argumentos para "tu %
		-- actual de este rating" -- GetVersatilityBonus pide una unidad +
		-- tipo de bono y devuelve el lado de reduccion de daño.
		-- GetCombatRatingBonus(CR) es el getter generico que si devuelve el
		-- porcentaje de daño hecho (confirmado contra el uso real de
		-- Stats+ de esta misma llamada).
		vers = {
			rating = SafeNumber("versRating", GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)),
			pct = SafeNumber("versPct", GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)),
		},
	}
end

-- Tertiary stats (Leech, Avoidance) don't share a common itemization budget
-- with the 4 secondaries (separate optional rolls, mostly on Mythic+ gear),
-- so they're Character-only -- never fed into GetExpected's redistribution.
-- APIs confirmed against Stats+'s own GetTertiaries().
-- { leech = {rating=, pct=}, avoidance = {rating=, pct=} }
-- Los stats terciarios (Leech, Avoidance) no comparten presupuesto de
-- itemizacion con los 4 secundarios (son tiradas extra opcionales, sobre
-- todo en equipo de Mitica+), asi que son solo-Personaje -- nunca entran al
-- reparto de GetExpected. APIs confirmadas contra el GetTertiaries() real
-- de Stats+.
function PlayerStats:GetTertiaryActuals()
	return {
		leech = {
			rating = SafeNumber("leechRating", GetCombatRating(CR_LIFESTEAL)),
			pct = SafeNumber("leechPct", GetLifesteal()),
		},
		avoidance = {
			rating = SafeNumber("avoidanceRating", GetCombatRating(CR_AVOIDANCE)),
			pct = SafeNumber("avoidancePct", GetAvoidance()),
		},
	}
end

-- The "budget" (total secondary rating) that Recommended redistributes by
-- weight -- frozen instead of recalculated on every refresh, so the target
-- stays stable while swapping gear with the same scale. Recalculates only
-- on first use, or when the active scale changes (compared by table
-- identity, not name, so nothing has to hook every place that touches
-- profile.activeScale); can also be forced by hand with `/stm recalc`.
-- El "presupuesto" (rating secundario total) que Recomendado reparte segun
-- los pesos -- congelado en vez de recalculado en cada refresco, para que
-- el objetivo se quede estable mientras se prueba equipo con la misma
-- escala. Se recalcula solo la primera vez, o si cambia la escala activa
-- (comparada por identidad de tabla, no por nombre); tambien se puede
-- forzar a mano con `/stm recalc`.
local expectedBudget
local lastScaleRef

function PlayerStats:RecalculateExpectedBudget(actuals)
	actuals = actuals or self:GetSecondaryActuals()
	local total = 0
	for _, key in ipairs(STAT_KEYS) do
		total = total + (actuals[key] and actuals[key].rating or 0)
	end
	expectedBudget = total
	return total
end

-- scale: {crit=weight, haste=weight, mastery=weight, vers=weight}, from the
-- user's own SimC numbers. actuals: result of GetSecondaryActuals().
-- Returns the same shape as actuals, so Panel.lua/CharacterPane.lua can
-- show either side directly. pct is a linear estimate derived from the
-- player's own current rating->percent ratio for that stat, not a second
-- Blizzard API call.
-- scale: {crit=peso, haste=peso, mastery=peso, vers=peso}, de los numeros
-- propios de SimC del usuario. actuals: resultado de GetSecondaryActuals().
-- Devuelve la misma forma que actuals, para que Panel.lua/CharacterPane.lua
-- puedan mostrar cualquier lado directo. pct es una estimacion lineal
-- derivada de la propia relacion rating->porcentaje actual del jugador para
-- ese stat, no una segunda llamada a la API de Blizzard.
function PlayerStats:GetExpected(scale, actuals)
	local expected = {}
	if not scale then
		return expected
	end

	local weightSum = 0
	for _, key in ipairs(STAT_KEYS) do
		weightSum = weightSum + (scale[key] or 0)
	end

	if weightSum <= 0 then
		return expected
	end

	if expectedBudget == nil or scale ~= lastScaleRef then
		lastScaleRef = scale
		self:RecalculateExpectedBudget(actuals)
	end

	for _, key in ipairs(STAT_KEYS) do
		local rating = expectedBudget * (scale[key] or 0) / weightSum
		local pct = 0
		local a = actuals[key]
		if a and a.rating and a.rating > 0 and a.pct then
			pct = rating * (a.pct / a.rating)
		end
		expected[key] = { rating = rating, pct = pct }
	end
	return expected
end

function PlayerStats:Init()
	-- Nothing to set up -- pure on-demand data, no frames or events.
	-- Nada que configurar -- datos puros a pedido, sin frames ni eventos.
end
