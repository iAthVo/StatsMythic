--[[ StatsMythic · CharacterPane.lua
Adds the "Recommended" value to each secondary stat's tooltip on the native
Character pane ('C' key) and on GW2_UI's replacement.
© 2026 TavoD_Gus_KrG · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

-- Both the native pane and GW2_UI's place stat rows on a fixed-width grid
-- that isn't recomputed from content width, so adding inline text next to
-- a stat's value overlaps the neighboring cell instead of pushing it
-- aside. Showing the value in the stat's own tooltip avoids that risk
-- entirely -- a tooltip floats outside the grid.
--
-- Ambos paneles (nativo y GW2_UI) ubican las filas de stats en una grilla
-- de ancho fijo que no se recalcula segun el contenido, asi que agregar
-- texto en linea junto al valor de un stat se superpone con la celda
-- vecina en vez de empujarla. Mostrar el valor en el tooltip del stat
-- evita ese riesgo por completo -- un tooltip flota fuera de la grilla.
--
-- The periodic re-check below runs on our OWN ticker frame, never via
-- `pooledFrame:SetScript("OnUpdate", ...)` -- SetScript *replaces* any
-- script a frame already had, which would silently clobber GW2_UI's own
-- OnUpdate for that row. Every hook on a frame we don't own uses
-- `HookScript` (adds alongside, never replaces).
--
-- El re-chequeo periodico de mas abajo corre en un ticker frame PROPIO,
-- nunca via `pooledFrame:SetScript("OnUpdate", ...)` -- SetScript
-- *reemplaza* cualquier script que el frame ya tuviera, lo que pisaria en
-- silencio el OnUpdate propio de GW2_UI para esa fila. Todo hook sobre un
-- frame ajeno usa `HookScript` (se agrega al lado, nunca reemplaza).
--
-- Grounded on real, verified code, not guessed:
-- - Native: `CharacterStatsPane.statsFramePool` (confirmed via ElvUI's
--   skin code) and the hook target `PaperDollFrame_UpdateStats`
--   (confirmed via ElvUI's own `hooksecurefunc`).
-- - GW2_UI: confirmed by reading
--   "GW2_UI\Games\Mainline\Character\paperdoll_equipment.lua" directly --
--   its pane lives on a frame named "GwDressingRoom", with its own
--   `.statsFramePool` and an `OnEnter` per row.
--
-- Verificado contra codigo real, no adivinado:
-- - Nativo: `CharacterStatsPane.statsFramePool` (confirmado en el skin de
--   ElvUI) y el punto de hook `PaperDollFrame_UpdateStats` (confirmado en
--   el `hooksecurefunc` propio de ElvUI).
-- - GW2_UI: confirmado leyendo directo
--   "GW2_UI\Games\Mainline\Character\paperdoll_equipment.lua" -- su panel
--   vive en un frame llamado "GwDressingRoom", con su propio
--   `.statsFramePool` y un `OnEnter` por fila.
--
-- If the line doesn't show up with either UI, run `/stm debugchar` with
-- the Character panel open to dump the real field names and fix
-- STAT_ID_MAP below.
-- Si la linea no aparece con ninguna de las dos UI, corre `/stm debugchar`
-- con el panel de personaje abierto para volcar los nombres reales de
-- campo y corregir STAT_ID_MAP mas abajo.

local CharacterPane = {}
ns.CharacterPane = CharacterPane

local STAT_ID_MAP = {
	CRITCHANCE = "crit",
	HASTE = "haste",
	MASTERY = "mastery",
	VERSATILITY = "vers",
}

local hookedFrames = {} -- [pooledFrame] = true -- HookScript each physical frame only once / cada frame fisico se enlaza una sola vez

-- Returns every known stats-frame-pool source currently present, regardless
-- of which UI (native or GW2_UI) is managing the character pane.
-- Devuelve cada fuente de pool de frames de stats presente ahorita, sin
-- importar cual UI (nativa o GW2_UI) este manejando el panel de personaje.
local function GetStatPools()
	local pools = {}
	if CharacterStatsPane and CharacterStatsPane.statsFramePool then
		table.insert(pools, CharacterStatsPane.statsFramePool)
	end
	if _G.GwDressingRoom and _G.GwDressingRoom.statsFramePool then
		table.insert(pools, _G.GwDressingRoom.statsFramePool)
	end
	return pools
end

-- GwDressingRoom may not exist yet at Init() time (load order between
-- StatsMythic and GW2_UI isn't guaranteed) -- self-heals by attaching the
-- OnShow hook the first time it's noticed to exist, from inside the normal
-- refresh path, instead of only trying once at startup.
-- GwDressingRoom puede no existir todavia al momento de Init() (el orden
-- de carga entre StatsMythic y GW2_UI no esta garantizado) -- se
-- autorepara, enganchando el OnShow la primera vez que se nota que existe,
-- desde el camino normal de refresco, en vez de intentarlo solo una vez
-- al inicio.
local gwHooked = false
local function EnsureGwHook(onShowFn)
	if not gwHooked and _G.GwDressingRoom then
		_G.GwDressingRoom:HookScript("OnShow", onShowFn)
		gwHooked = true
	end
end

local OPTIMO_PREFIX = "Optimo:"

local function ComputeOptimoText(statKey)
	local scaleName = ns.db.profile.activeScale
	local scale = scaleName and ns.db.char.scales[scaleName]
	if not scale then
		return nil
	end

	local actuals = ns.PlayerStats:GetSecondaryActuals()
	local expected = ns.PlayerStats:GetExpected(scale, actuals)
	local value = expected[statKey]
	if not value then
		return nil
	end

	return string.format("%s %d (%.1f%%)", OPTIMO_PREFIX, math.floor(value.rating + 0.5), value.pct)
end

local function IsOptimoLineAlreadyLast()
	local n = GameTooltip:NumLines()
	if n == 0 then
		return false
	end
	local fs = _G["GameTooltipTextLeft" .. n]
	local text = fs and fs:GetText()
	return text ~= nil and text:sub(1, #OPTIMO_PREFIX) == OPTIMO_PREFIX
end

local function EnsureOptimoLine(frame, statKey)
	if not frame or not frame:IsMouseOver() or not GameTooltip:IsShown() then
		return false
	end
	if IsOptimoLineAlreadyLast() then
		return true
	end
	local text = ComputeOptimoText(statKey)
	if text then
		GameTooltip:AddLine(text, 0.6, 0.85, 1)
		GameTooltip:Show()
	end
	return true
end

-- Some panes (observed with GW2_UI) periodically rebuild the tooltip while
-- it's still open, silently wiping a line added only once on OnEnter --
-- keep re-asserting it for as long as the mouse stays over the stat.
-- Algunos paneles (observado en GW2_UI) reconstruyen el tooltip de forma
-- periodica mientras sigue abierto, borrando en silencio una linea
-- agregada solo una vez en OnEnter -- se reafirma mientras el mouse siga
-- encima del stat.
local currentHoverFrame, currentHoverStatKey

local function OnStatFrameEnter(frame)
	local statKey = frame.stat and STAT_ID_MAP[frame.stat]
	if not statKey then
		return
	end
	currentHoverFrame, currentHoverStatKey = frame, statKey
	EnsureOptimoLine(frame, statKey) -- assert immediately, don't wait for the first tick / reafirma de inmediato, sin esperar el primer tick
end

local function OnStatFrameLeave(frame)
	if currentHoverFrame == frame then
		currentHoverFrame, currentHoverStatKey = nil, nil
	end
end

-- No throttle: GW2_UI's own Mastery refresh fires often enough that even a
-- short delay let a visible gap show through. The check itself is cheap (a
-- string compare, only calling AddLine when actually needed).
-- Sin limite de frecuencia: el refresco propio de Mastery en GW2_UI corre
-- seguido, tanto que hasta un retraso corto dejaba ver un hueco visible. El
-- chequeo en si es barato (una comparacion de texto, solo llama AddLine
-- cuando de verdad hace falta).
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
	if not currentHoverFrame then
		return
	end
	if not EnsureOptimoLine(currentHoverFrame, currentHoverStatKey) then
		currentHoverFrame, currentHoverStatKey = nil, nil
	end
end)

local function HookPoolFrames()
	EnsureGwHook(HookPoolFrames) -- retry attaching GwDressingRoom's OnShow if it didn't exist yet / reintenta el OnShow de GwDressingRoom si no existia antes

	for _, pool in ipairs(GetStatPools()) do
		for frame in pool:EnumerateActive() do
			if not hookedFrames[frame] then
				hookedFrames[frame] = true
				frame:HookScript("OnEnter", OnStatFrameEnter)
				frame:HookScript("OnLeave", OnStatFrameLeave)
			end
		end
	end
end

-- For `/stm debugchar` -- dumps the real field names of every active
-- pooled stat frame (both UIs), to verify/correct STAT_ID_MAP above.
-- Para `/stm debugchar` -- vuelca los nombres reales de campo de cada
-- frame de stat activo (en ambas UI), para verificar/corregir
-- STAT_ID_MAP arriba.
function CharacterPane:DebugDump()
	local pools = GetStatPools()
	if #pools == 0 then
		ns.addon:Print("No se encontro ningun panel de stats activo (abri el panel de personaje con C primero).")
		return
	end
	local count = 0
	for _, pool in ipairs(pools) do
		for frame in pool:EnumerateActive() do
			count = count + 1
			ns.addon:Print(string.format(
				"stat=%s Value=%s Label=%s",
				tostring(frame.stat),
				tostring(frame.Value and frame.Value:GetText()),
				tostring(frame.Label and frame.Label:GetText())
			))
		end
	end
	if count == 0 then
		ns.addon:Print("No hay filas activas -- abri el panel de personaje con C primero.")
	end
end

function CharacterPane:Refresh()
	HookPoolFrames()
end

function CharacterPane:Init()
	if PaperDollFrame_UpdateStats then
		hooksecurefunc("PaperDollFrame_UpdateStats", HookPoolFrames)
	end
	if CharacterFrame then
		CharacterFrame:HookScript("OnShow", HookPoolFrames)
	end
	EnsureGwHook(HookPoolFrames) -- in case it already exists by now; otherwise self-heals later / por si ya existe; si no, se autorepara despues
end
