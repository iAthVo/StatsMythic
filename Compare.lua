--[[ StatsMythic · Compare.lua
Pawn-style item tooltip comparison, scored against one or more saved scales.
© 2026 TavoD_Gus_KrG · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

-- Uses the modern C_Item.GetItemStats API instead of Pawn's tooltip-text
-- regex parsing (Pawn does that for historical reasons -- 15+ years of
-- accumulated edge cases). GetItemStats is the official, documented,
-- simpler path for a fresh addon.
--
-- Exception: weapon DPS. There's no GetItemStats key for it (confirmed --
-- no installed addon references one either), so like Pawn it's computed
-- from the weapon's min/max damage and speed, read off the tooltip -- but
-- narrowly, via the structured C_TooltipInfo line data, not raw regex on
-- displayed text. Still locale-sensitive for the "Speed" keyword; if it
-- comes back wrong, `/stm debugitem` also prints the scanned values.
--
-- Usa la API moderna C_Item.GetItemStats en vez del parseo por regex del
-- texto del tooltip que usa Pawn (por razones historicas -- 15+ años de
-- casos especiales acumulados). GetItemStats es el camino oficial,
-- documentado y mas simple para un addon nuevo.
--
-- Excepcion: Weapon DPS. No hay ninguna llave de GetItemStats para esto
-- (confirmado -- ningun addon instalado referencia una tampoco), asi que,
-- igual que Pawn, se calcula leyendo el daño minimo/maximo y la velocidad
-- del arma desde su tooltip -- pero de forma puntual, vía los datos
-- estructurados de C_TooltipInfo, no regex crudo sobre el texto mostrado.
-- Sigue siendo sensible al idioma para la palabra "Speed"/"Velocidad"; si
-- sale mal, `/stm debugitem` tambien imprime los valores escaneados.

local Compare = {}
ns.Compare = Compare

-- C_Item.GetItemStats returns a table keyed by each ITEM_MOD_* constant's
-- literal name. If a comparison looks wrong (always 0, or missing a stat),
-- run `/stm debugitem` while hovering the item -- it dumps the raw keys so
-- this map can be corrected. All three primary-stat keys map to "primary";
-- only one will ever actually be present on a given item.
-- C_Item.GetItemStats devuelve una tabla indexada por el nombre literal de
-- cada constante ITEM_MOD_*. Si una comparacion se ve mal (siempre 0, o
-- falta un stat), corre `/stm debugitem` con el mouse sobre el objeto --
-- imprime las llaves crudas para corregir este mapa. Las tres llaves de
-- stat principal mapean a "primary"; solo una va a estar presente en un
-- objeto dado.
local STAT_KEY_MAP = {
	ITEM_MOD_CRIT_RATING_SHORT = "crit",
	ITEM_MOD_HASTE_RATING_SHORT = "haste",
	ITEM_MOD_MASTERY_RATING_SHORT = "mastery",
	ITEM_MOD_VERSATILITY = "vers",
	ITEM_MOD_AGILITY_SHORT = "primary",
	ITEM_MOD_STRENGTH_SHORT = "primary",
	ITEM_MOD_INTELLECT_SHORT = "primary",
}

local EQUIP_LOC_TO_SLOT = {
	INVTYPE_HEAD = INVSLOT_HEAD,
	INVTYPE_NECK = INVSLOT_NECK,
	INVTYPE_SHOULDER = INVSLOT_SHOULDER,
	INVTYPE_CLOAK = INVSLOT_BACK,
	INVTYPE_CHEST = INVSLOT_CHEST,
	INVTYPE_ROBE = INVSLOT_CHEST,
	INVTYPE_WRIST = INVSLOT_WRIST,
	INVTYPE_HAND = INVSLOT_HAND,
	INVTYPE_WAIST = INVSLOT_WAIST,
	INVTYPE_LEGS = INVSLOT_LEGS,
	INVTYPE_FEET = INVSLOT_FEET,
}

local function GetActiveScale()
	local scaleName = ns.db.profile.activeScale
	local scale = scaleName and ns.db.char.scales[scaleName]
	return scale, scaleName
end

-- Scans the item's tooltip lines (structured C_TooltipInfo data, not raw
-- displayed text) for a "min - max" damage pair and a "Speed X.X" line,
-- returning the resulting DPS -- same formula Pawn uses.
-- Escanea las lineas del tooltip del objeto (datos estructurados de
-- C_TooltipInfo, no el texto mostrado) buscando un par "min - max" de daño
-- y una linea "Speed X.X"/"Velocidad X.X", devolviendo el DPS resultante --
-- misma formula que usa Pawn.
local function GetWeaponDps(itemLink)
	if not C_TooltipInfo then
		return nil
	end
	local info = C_TooltipInfo.GetHyperlink(itemLink)
	if not info or not info.lines then
		return nil
	end

	local minDmg, maxDmg, speed
	for _, line in ipairs(info.lines) do
		local text = line.leftText
		if text then
			if not minDmg then
				local a, b = text:match("(%d[%d,]*)%s*%-%s*(%d[%d,]*)%s*[Dd]amage")
				if a and b then
					minDmg = tonumber((a:gsub(",", "")))
					maxDmg = tonumber((b:gsub(",", "")))
				end
			end
			if not speed then
				speed = tonumber(text:match("[Ss]peed%s+([%d%.]+)") or text:match("[Vv]elocidad%s+([%d%.]+)"))
			end
		end
	end

	if minDmg and maxDmg and speed and speed > 0 then
		return (minDmg + maxDmg) / 2 / speed
	end
	return nil
end

-- isOffHand picks between the "weaponDps"/"offHandWeaponDps" weight so an
-- off-hand weapon scores against the off-hand weight, not the main-hand one.
-- isOffHand elige entre el peso "weaponDps"/"offHandWeaponDps" para que un
-- arma de mano izquierda se puntúe contra el peso de offhand, no el de
-- mano principal.
local function ScoreItemLink(itemLink, scale, isOffHand)
	if not itemLink or not scale then
		return nil
	end

	local total = 0
	local matched = false

	local stats = C_Item.GetItemStats(itemLink)
	if stats then
		for statKey, quantity in pairs(stats) do
			local ourKey = STAT_KEY_MAP[statKey]
			if ourKey and scale[ourKey] and scale[ourKey] ~= 0 then
				total = total + quantity * scale[ourKey]
				matched = true
			end
		end
	end

	local dpsWeightKey = isOffHand and "offHandWeaponDps" or "weaponDps"
	local dpsWeight = scale[dpsWeightKey]
	if dpsWeight and dpsWeight ~= 0 then
		local dps = GetWeaponDps(itemLink)
		if dps then
			total = total + dps * dpsWeight
			matched = true
		end
	end

	if not matched then
		return nil
	end
	return total
end

-- Returns one or two equipped item links to compare against (rings/trinkets
-- have two slots -- compares against the weaker of the pair, same approach
-- Pawn uses).
-- Devuelve uno o dos links de objetos equipados contra los cuales comparar
-- (anillos/abalorios tienen dos espacios -- compara contra el mas debil del
-- par, mismo criterio que usa Pawn).
local function GetEquippedLinksForCompare(itemLink)
	local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemLink)
	if not equipLoc or equipLoc == "" then
		return nil
	end

	if equipLoc == "INVTYPE_FINGER" then
		return GetInventoryItemLink("player", INVSLOT_FINGER1), GetInventoryItemLink("player", INVSLOT_FINGER2)
	end
	if equipLoc == "INVTYPE_TRINKET" then
		return GetInventoryItemLink("player", INVSLOT_TRINKET1), GetInventoryItemLink("player", INVSLOT_TRINKET2)
	end
	if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
		return GetInventoryItemLink("player", INVSLOT_MAINHAND)
	end
	if equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD" then
		return GetInventoryItemLink("player", INVSLOT_OFFHAND)
	end

	local slot = EQUIP_LOC_TO_SLOT[equipLoc]
	if not slot then
		return nil
	end
	return GetInventoryItemLink("player", slot)
end

local function IsOffHandLoc(equipLoc)
	return equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD"
end

-- Adds ONE comparison line for one specific scale -- split out from
-- UpdateTooltip so it can run once for the active scale and again for every
-- scale flagged "Show in tooltip" (see BuildScaleListArgs in Config.lua).
-- Agrega UNA linea de comparacion para una escala puntual -- separado de
-- UpdateTooltip para poder correrlo una vez por la escala activa y otra vez
-- por cada escala marcada "Mostrar en tooltip" (ver BuildScaleListArgs en
-- Config.lua).
local function AddScaleLine(tooltip, itemLink, isOffHand, equippedA, equippedB, scaleName, scale)
	local newScore = ScoreItemLink(itemLink, scale, isOffHand)
	if not newScore then
		return
	end

	local equippedScore
	if equippedA then
		equippedScore = ScoreItemLink(equippedA, scale, isOffHand)
	end
	if equippedB then
		local scoreB = ScoreItemLink(equippedB, scale, isOffHand)
		if scoreB and (not equippedScore or scoreB < equippedScore) then
			equippedScore = scoreB
		end
	end

	if not equippedScore then
		tooltip:AddLine(string.format("%s: %.1f", scaleName, newScore), 0.6, 0.6, 1)
		-- Forces the tooltip to resize around the new line (confirmed via
		-- Pawn's own code, which does the same after AddLine on an
		-- already-shown tooltip) -- without this the box stays its old
		-- size and the text overlaps the bottom edge.
		-- Fuerza al tooltip a redimensionarse con la nueva linea
		-- (confirmado contra el codigo real de Pawn, que hace lo mismo
		-- despues de un AddLine sobre un tooltip ya visible) -- sin esto
		-- el cuadro se queda con su tamaño viejo y el texto se superpone
		-- con el borde inferior.
		tooltip:Show()
		return
	end

	local diff = newScore - equippedScore
	local pct = (equippedScore ~= 0) and (diff / math.abs(equippedScore) * 100) or 0

	local r, g, b = 1, 1, 1
	if diff > 0 then
		r, g, b = 0.2, 1, 0.2
	elseif diff < 0 then
		r, g, b = 1, 0.3, 0.3
	end

	tooltip:AddLine(string.format("%s: %+.1f%%", scaleName, pct), r, g, b)
	tooltip:Show() -- same resize-forcing call as above / mismo llamado de arriba para forzar el redimensionado
end

local function UpdateTooltip(tooltip, itemLink)
	if not itemLink or not tooltip or tooltip:IsForbidden() then
		return
	end

	local activeScale, activeName = GetActiveScale()

	-- The active scale always shows (as always); others show only if the
	-- user flagged them "Show in tooltip" in the "Character Scales" tab --
	-- this lets several show at once without losing the usual one.
	-- La escala activa siempre se muestra (como siempre); las demas solo si
	-- el usuario las marco "Mostrar en tooltip" en la pestaña "Escalas de
	-- Personaje" -- esto permite ver varias a la vez sin perder la de
	-- siempre.
	local extraNames = {}
	for name, scale in pairs(ns.db.char.scales) do
		if scale.showInTooltip and name ~= activeName then
			table.insert(extraNames, name)
		end
	end
	if not activeScale and #extraNames == 0 then
		return
	end
	table.sort(extraNames)

	local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemLink)
	local isOffHand = IsOffHandLoc(equipLoc)
	local equippedA, equippedB = GetEquippedLinksForCompare(itemLink)

	if activeScale then
		AddScaleLine(tooltip, itemLink, isOffHand, equippedA, equippedB, activeName, activeScale)
	end
	for _, name in ipairs(extraNames) do
		AddScaleLine(tooltip, itemLink, isOffHand, equippedA, equippedB, name, ns.db.char.scales[name])
	end
end

local function ResolveItemLink(tooltip)
	local _, link = tooltip:GetItem()
	return link
end

local HOOKED_METHODS = {
	"SetBagItem",
	"SetInventoryItem",
	"SetMerchantItem",
	"SetLootItem",
	"SetLootRollItem",
	"SetAuctionItem",
	"SetHyperlink",
}

-- For `/stm debugitem` (Config.lua) -- prints the raw GetItemStats keys and
-- the scanned weapon DPS (if any) for whatever item is under the mouse, to
-- verify STAT_KEY_MAP and the weapon-damage scan.
-- Para `/stm debugitem` (Config.lua) -- imprime las llaves crudas de
-- GetItemStats y el Weapon DPS escaneado (si hay) del objeto bajo el mouse,
-- para verificar STAT_KEY_MAP y el escaneo de daño de arma.
function Compare:DebugCurrentTooltipItem()
	local link = ResolveItemLink(GameTooltip)
	if not link then
		ns.addon:Print("No hay ningun item bajo el mouse ahorita.")
		return
	end
	local stats = C_Item.GetItemStats(link)
	if stats then
		for key, value in pairs(stats) do
			ns.addon:Print(tostring(key) .. " = " .. tostring(value))
		end
	else
		ns.addon:Print("GetItemStats no devolvio nada para ese item.")
	end

	local dps = GetWeaponDps(link)
	ns.addon:Print("Weapon DPS calculado: " .. tostring(dps))
end

function Compare:Init()
	for _, method in ipairs(HOOKED_METHODS) do
		if GameTooltip[method] then
			hooksecurefunc(GameTooltip, method, function(tt)
				UpdateTooltip(tt, ResolveItemLink(tt))
			end)
		end
	end

	if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
		hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(tt)
			UpdateTooltip(tt, ResolveItemLink(tt))
		end)
	end
end
