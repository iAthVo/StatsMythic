--[[ StatsMythic · PlayerStats.lua
Pure data module (no frames): reads live stats from Blizzard's own API and
computes the "Recommended" proportional redistribution.
© 2026 iAthVo_Kr · MIT License ]]
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

-- Maps each of our stat keys to Blizzard's CR_* constant, for
-- GetCombatRatingBonusForCombatRatingValue(ratingIndex, value) -- the one
-- Blizzard API that converts an ARBITRARY rating amount to a percent,
-- independent of what the player currently has equipped (confirmed via
-- warcraft.wiki.gg/wiki/API:GetCombatRatingBonusForCombatRatingValue). See
-- GetExpected below for why this matters over GetCombatRatingBonus (which
-- only reports the bonus from your CURRENT rating).
-- Mapea cada una de nuestras llaves de stat a la constante CR_* de Blizzard,
-- para GetCombatRatingBonusForCombatRatingValue(ratingIndex, value) -- la
-- unica API de Blizzard que convierte una cantidad ARBITRARIA de rating a
-- porcentaje, sin importar lo que el jugador tenga equipado ahorita
-- (confirmado via
-- warcraft.wiki.gg/wiki/API:GetCombatRatingBonusForCombatRatingValue). Ver
-- GetExpected abajo para el porque esto importa sobre GetCombatRatingBonus
-- (que solo reporta el bono de tu rating ACTUAL).
local CR_BY_KEY = {
	crit = CR_CRIT_MELEE,
	haste = CR_HASTE_MELEE,
	mastery = CR_MASTERY,
	vers = CR_VERSATILITY_DAMAGE_DONE,
}

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

-- Tracks which SafeNumber-protected keys are CURRENTLY frozen (still
-- returning the cached last-known-good number because the game's own
-- getter is returning a Secret Value right now) -- Panel.lua/
-- CharacterPane.lua read this via IsStatFrozen() to mark a stat as
-- protected instead of showing a frozen number that looks identical to a
-- live one. Confirmed real behavior (warcraft.wiki.gg/wiki/Secret_Values):
-- GetCombatRating is flagged SecretWhenUnitStatsRestricted, which can stay
-- active for a whole Mythic+/PvP context, not just an instant combat flash.
-- Rastrea que llaves protegidas por SafeNumber estan congeladas AHORITA
-- (siguen devolviendo el ultimo numero bueno cacheado porque el getter
-- real del juego esta devolviendo un "Secret Value" en este momento) --
-- Panel.lua/CharacterPane.lua leen esto via IsStatFrozen() para marcar un
-- stat como protegido en vez de mostrar un numero congelado identico a uno
-- en vivo. Comportamiento real confirmado
-- (warcraft.wiki.gg/wiki/Secret_Values): GetCombatRating esta marcada
-- SecretWhenUnitStatsRestricted, que puede quedarse activa toda una corrida
-- de Mitica+/contexto JcJ, no solo un flash instantaneo de combate.
local frozenKeys = {}

local function SafeNumber(key, value)
	if type(value) == "number" then
		local ok, result = pcall(function() return value + 0 end)
		if ok then
			lastGoodValues[key] = result
			frozenKeys[key] = nil
			return result
		end
	end
	frozenKeys[key] = true
	return lastGoodValues[key] or 0
end

-- Maps a Panel.lua/CharacterPane.lua-facing stat key to the internal
-- SafeNumber cache keys that make it up, so callers don't need to know
-- SafeNumber's own naming.
-- Mapea una llave de stat como la ven Panel.lua/CharacterPane.lua a las
-- llaves internas de cache de SafeNumber que la componen, para que quien
-- llama no necesite conocer el nombrado interno de SafeNumber.
local STAT_FROZEN_KEYS = {
	crit = { "critRating", "critPct" },
	haste = { "hasteRating", "hastePct" },
	mastery = { "masteryRating", "masteryPct" },
	vers = { "versRating", "versPct" },
	leech = { "leechRating", "leechPct" },
	avoidance = { "avoidanceRating", "avoidancePct" },
	primary = { "primaryValue" },
	ilvl = { "ilvlEquipped", "ilvlOverall" },
}

-- True while ANY value behind this stat key is currently frozen (showing a
-- cached number instead of a fresh read from the game).
-- Verdadero mientras CUALQUIER valor detras de esta llave de stat este
-- congelado ahorita (mostrando un numero cacheado en vez de una lectura
-- fresca del juego).
function PlayerStats:IsStatFrozen(statKey)
	local keys = STAT_FROZEN_KEYS[statKey]
	if not keys then
		return false
	end
	for _, k in ipairs(keys) do
		if frozenKeys[k] then
			return true
		end
	end
	return false
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
-- stays stable while swapping a single piece of gear with the same scale.
-- Recalculates on first use, when the active scale changes (compared by
-- table identity, not name, so nothing has to hook every place that touches
-- profile.activeScale), automatically when a PLAYER_EQUIPMENT_CHANGED swing
-- is big enough to mean a whole different gear set (see MaybeRebaseBudget
-- below -- this is what makes a PvE <-> PvP gear swap correct itself
-- without `/stm recalc`), or still by hand with `/stm recalc` for anything
-- that slips past the automatic check.
-- El "presupuesto" (rating secundario total) que Recomendado reparte segun
-- los pesos -- congelado en vez de recalculado en cada refresco, para que
-- el objetivo se quede estable mientras se prueba una sola pieza de equipo
-- con la misma escala. Se recalcula la primera vez, si cambia la escala
-- activa (comparada por identidad de tabla, no por nombre), automaticamente
-- cuando un PLAYER_EQUIPMENT_CHANGED trae un cambio lo bastante grande como
-- para ser un set de equipo distinto (ver MaybeRebaseBudget abajo -- esto es
-- lo que hace que cambiar entre equipo PvE y PvP se corrija solo, sin
-- `/stm recalc`), o todavia a mano con `/stm recalc` para lo que se escape
-- del chequeo automatico.
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

-- Two triggers rebase the frozen budget automatically: an equipment change
-- big enough to mean a genuinely different gear set (a full PvE <-> PvP
-- swap) rather than a single piece, and leaving an instance
-- (PLAYER_ENTERING_WORLD -- an arena/M+/raid ending, or any loading
-- screen) -- both call CheckExpectedBudget (Core.lua). A single swapped
-- piece still leaves the "stable target while comparing items" behavior
-- above alone, since that case never crosses REBASE_THRESHOLD.
-- Debounced because swapping a full set (by hand or via Equipment Manager)
-- fires one PLAYER_EQUIPMENT_CHANGED per slot, not one event total.
-- PLAYER_ENTERING_WORLD is what fixes the real reported case: leaving an
-- arena (or any restricted PvP/M+ content) with every secondary stat
-- Secret-Values-frozen at the moment the budget was first calculated this
-- session (e.g. UI loaded already inside the instance) locks the budget at
-- 0 forever, because nothing about leaving the instance touches your gear
-- -- PLAYER_EQUIPMENT_CHANGED alone never fires, so the old version needed
-- a full `/reload` to reset `expectedBudget` back to nil. Now
-- expectedBudget <= 0 always forces a rebase the next time ANY of these
-- triggers sees a clean (unfrozen) reading, regardless of which one fired.
-- Dos disparadores rebasan el presupuesto congelado automaticamente: un
-- cambio de equipo lo bastante grande como para ser un set de equipo
-- genuinamente distinto (un cambio completo PvE <-> PvP) en vez de una sola
-- pieza, y salir de una instancia (PLAYER_ENTERING_WORLD -- que termine una
-- arena/Mitica+/banda, o cualquier pantalla de carga) -- ambos llaman a
-- CheckExpectedBudget (Core.lua). Una sola pieza cambiada sigue sin tocar
-- el comportamiento de "objetivo estable mientras se comparan piezas" de
-- arriba, porque ese caso nunca cruza REBASE_THRESHOLD.
-- Con antirrebote porque cambiar un set completo (a mano o via
-- Administrador de Equipo) dispara un PLAYER_EQUIPMENT_CHANGED por ranura,
-- no un solo evento. PLAYER_ENTERING_WORLD es lo que arregla el caso real
-- reportado: salir de una arena (o cualquier contenido JcJ/Mitica+
-- restringido) con todos los stats secundarios congelados por Secret
-- Values justo cuando se calculo el presupuesto por primera vez en la
-- sesion (ej. la UI cargo ya adentro de la instancia) deja el presupuesto
-- fijo en 0 para siempre, porque salir de la instancia no toca tu equipo
-- -- PLAYER_EQUIPMENT_CHANGED solo nunca dispara, asi que la version vieja
-- necesitaba un `/reload` completo para resetear `expectedBudget` de
-- vuelta a nil. Ahora expectedBudget <= 0 siempre fuerza un rebase la
-- proxima vez que CUALQUIERA de estos disparadores vea una lectura limpia
-- (sin congelar), sin importar cual haya disparado.
local REBASE_THRESHOLD = 0.15 -- 15% swing in total secondary rating / cambio de 15% en el rating secundario total
local REBASE_CHECK_DEBOUNCE = 0.5 -- seconds / segundos
local rebaseCheckPending = false

local function MaybeRebaseBudget()
	rebaseCheckPending = false
	if expectedBudget == nil then
		return -- nothing computed yet; the next GetExpected call seeds it fresh / nada calculado todavia; la proxima llamada a GetExpected lo siembra fresco
	end

	local actuals = PlayerStats:GetSecondaryActuals()
	for _, key in ipairs(STAT_KEYS) do
		if PlayerStats:IsStatFrozen(key) then
			return -- wait for a clean reading instead of baking in a frozen one / espera una lectura limpia en vez de fijar una congelada
		end
	end

	local total = 0
	for _, key in ipairs(STAT_KEYS) do
		total = total + (actuals[key] and actuals[key].rating or 0)
	end

	if expectedBudget <= 0 or math.abs(total - expectedBudget) / expectedBudget > REBASE_THRESHOLD then
		PlayerStats:RecalculateExpectedBudget(actuals)
		if ns.Panel then ns.Panel:Refresh() end
		if ns.CharacterPane then ns.CharacterPane:Refresh() end
	end
end

-- Called from Core.lua on PLAYER_EQUIPMENT_CHANGED and PLAYER_ENTERING_WORLD.
-- Llamado desde Core.lua en PLAYER_EQUIPMENT_CHANGED y PLAYER_ENTERING_WORLD.
function PlayerStats:CheckExpectedBudget()
	if rebaseCheckPending then
		return
	end
	rebaseCheckPending = true
	C_Timer.After(REBASE_CHECK_DEBOUNCE, MaybeRebaseBudget)
end

-- scale: {crit=weight, haste=weight, mastery=weight, vers=weight}, from the
-- user's own SimC numbers. actuals: result of GetSecondaryActuals().
-- Returns the same shape as actuals, so Panel.lua/CharacterPane.lua can
-- show either side directly. pct comes from Blizzard's own
-- GetCombatRatingBonusForCombatRatingValue (see the loop below) -- a real
-- conversion, not a guess -- with the old current-ratio linear estimate
-- kept only as a fallback if that API ever errors.
-- scale: {crit=peso, haste=peso, mastery=peso, vers=peso}, de los numeros
-- propios de SimC del usuario. actuals: resultado de GetSecondaryActuals().
-- Devuelve la misma forma que actuals, para que Panel.lua/CharacterPane.lua
-- puedan mostrar cualquier lado directo. pct sale de
-- GetCombatRatingBonusForCombatRatingValue de Blizzard (ver el bucle abajo)
-- -- una conversion real, no una adivinanza -- con la vieja estimacion
-- lineal por proporcion actual solo como respaldo si esa API llega a
-- tronar.
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
		if a and a.pct then
			-- Preferred: ask Blizzard directly what percent the EXPECTED
			-- rating would give, via GetCombatRatingBonusForCombatRatingValue
			-- (takes an arbitrary rating amount, not just the one currently
			-- equipped). a.pct includes a non-rating baseline for crit/
			-- mastery (GetCritChance/GetMasteryEffect, unlike vers's own pct
			-- which is already rating-only) -- isolate that baseline by
			-- subtracting what the ACTUAL rating converts to, then add back
			-- what the EXPECTED rating converts to. This is what makes a
			-- stat sitting at 0 actual rating (real case: PvP gear with no
			-- Crit itemized at all) still show a correct Expected percent
			-- instead of 0 -- the old version divided by a.rating, which is
			-- undefined/0 right when a.rating is 0.
			-- Preferido: preguntarle a Blizzard directo que porcentaje daria
			-- el rating ESPERADO, via
			-- GetCombatRatingBonusForCombatRatingValue (acepta una cantidad
			-- arbitraria de rating, no solo la equipada ahorita). a.pct
			-- incluye una base sin rating para crit/mastery
			-- (GetCritChance/GetMasteryEffect, a diferencia del pct de vers
			-- que ya es puro rating) -- se aisla esa base restando lo que el
			-- rating ACTUAL convierte, y se suma lo que el rating ESPERADO
			-- convierte. Esto es lo que hace que un stat con 0 rating actual
			-- (caso real: equipo PvP sin nada de Critico) siga mostrando un
			-- porcentaje Esperado correcto en vez de 0 -- la version vieja
			-- dividia entre a.rating, que es indefinido/0 justo cuando
			-- a.rating es 0.
			local crId = CR_BY_KEY[key]
			local ok1, actualFromRating = pcall(GetCombatRatingBonusForCombatRatingValue, crId, a.rating or 0)
			local ok2, expectedFromRating = pcall(GetCombatRatingBonusForCombatRatingValue, crId, rating)
			if ok1 and ok2 and type(actualFromRating) == "number" and type(expectedFromRating) == "number" then
				pct = (a.pct - actualFromRating) + expectedFromRating
			elseif a.rating and a.rating > 0 then
				-- Fallback for the rare case the precise API errors or isn't
				-- available: the old linear estimate from the player's own
				-- current ratio, same as before.
				-- Respaldo para el caso raro de que la API precisa truene o
				-- no este disponible: la vieja estimacion lineal desde la
				-- propia proporcion actual del jugador, igual que antes.
				pct = rating * (a.pct / a.rating)
			end
		end
		expected[key] = { rating = rating, pct = pct }
	end
	return expected
end

function PlayerStats:Init()
	-- Nothing to set up -- pure on-demand data, no frames or events.
	-- Nada que configurar -- datos puros a pedido, sin frames ni eventos.
end
