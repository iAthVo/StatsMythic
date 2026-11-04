--[[ StatsMythic · Sync.lua
Addon-to-addon stat sync: a lightweight request/response over
C_ChatInfo.SendAddonMessage so two players who both run StatsMythic can see
each other's real numbers -- a hover tooltip for party/raid frames, plus
"/stm ver <nombre>" for anyone. There is no other way to read another
player's secondary stats: Blizzard's own REST API (the one behind the
Armory website) can return them, but addon Lua has no network access at
all, so only another StatsMythic client -- not a website -- can ever be
the data source here.
© 2026 iAthVo_Kr · MIT License ]]
-- Comment style: English first, Spanish second.
-- Estilo de comentarios: primero inglés, luego español.

local ADDON_NAME, ns = ...

local Sync = {}
ns.Sync = Sync

-- Wire format, plain pipe-delimited text (every field is a short number or
-- an ASCII word, nothing that can contain a "|"), no serializer library
-- needed. A request is just the literal string "R". A data reply is
-- "D|1|classFile|specID|primaryName|primary|critR|critP|hasteR|hasteP|
-- masteryR|masteryP|versR|versP|leechR|leechP|avoidR|avoidP|ilvlEq|
-- ilvlAll" -- about 100 characters in practice, well under
-- CHAT_MSG_ADDON's 255-char limit. The "1" right after "D" is a format
-- version, so a later field can be appended without breaking an older
-- client mid-patch (it just stops reading fields it doesn't recognize).
-- Formato del mensaje, texto plano separado por "|" (cada campo es un
-- numero corto o una palabra ASCII, nada que pueda llevar un "|"), sin
-- necesitar ninguna libreria de serializacion. Una solicitud es solo el
-- string literal "R". Una respuesta de datos es la de arriba -- unos 100
-- caracteres en la practica, muy por debajo del limite de 255 caracteres
-- de CHAT_MSG_ADDON. El "1" justo despues de "D" es una version de
-- formato, para poder agregar un campo despues sin romper un cliente mas
-- viejo a mitad de parche (simplemente deja de leer los campos que no
-- reconoce).
local PREFIX = "StatsMythic1"
local MSG_REQUEST = "R"
local MSG_DATA = "D"
local DATA_VERSION = "1"

local REQUEST_THROTTLE = 10 -- seconds between requests to the same name / segundos entre solicitudes al mismo nombre

local cache = {} -- [bareName] = { data = {...}, receivedAt = GetTime() }
local pendingRequests = {} -- [bareName] = GetTime() of the last request sent

-- CHAT_MSG_ADDON's sender isn't guaranteed to carry "-Realm" the same way
-- GetUnitName(unit, true) always does, so both sides of a cache lookup are
-- normalized down to the bare name before comparing -- the lowest common
-- form that matches regardless of which one included the realm suffix.
-- El sender de CHAT_MSG_ADDON no esta garantizado a llevar "-Reino" igual
-- que siempre lo hace GetUnitName(unit, true), asi que ambos lados de una
-- busqueda en cache se normalizan al nombre sin reino antes de comparar --
-- la forma minima en comun que coincide sin importar cual de los dos
-- traia el sufijo de reino.
local function BareName(name)
	return name and name:match("^[^%-]+") or name
end

function Sync:GetCached(name)
	local entry = cache[BareName(name)]
	return entry and entry.data
end

function Sync:IsSharingEnabled()
	return ns.db.profile.syncShareEnabled ~= false
end

local function BuildPayload()
	local ps = ns.PlayerStats
	local classFile = select(2, UnitClass("player")) or "?"
	local specIndex = GetSpecialization()
	local specID = (specIndex and select(1, GetSpecializationInfo(specIndex))) or 0
	local primaryName, primaryVal = ps:GetPrimaryStat()
	local secs = ps:GetSecondaryActuals()
	local ters = ps:GetTertiaryActuals()
	local ilvlEq, ilvlAll = ps:GetItemLevel()

	local fields = {
		MSG_DATA, DATA_VERSION, classFile, specID, primaryName, math.floor(primaryVal),
		math.floor(secs.crit.rating), string.format("%.2f", secs.crit.pct),
		math.floor(secs.haste.rating), string.format("%.2f", secs.haste.pct),
		math.floor(secs.mastery.rating), string.format("%.2f", secs.mastery.pct),
		math.floor(secs.vers.rating), string.format("%.2f", secs.vers.pct),
		math.floor(ters.leech.rating), string.format("%.2f", ters.leech.pct),
		math.floor(ters.avoidance.rating), string.format("%.2f", ters.avoidance.pct),
		math.floor(ilvlEq), math.floor(ilvlAll),
	}
	return table.concat(fields, "|")
end

local function OnMessage(prefix, message, _channel, sender)
	if prefix ~= PREFIX then
		return
	end

	if message == MSG_REQUEST then
		if Sync:IsSharingEnabled() then
			C_ChatInfo.SendAddonMessage(PREFIX, BuildPayload(), "WHISPER", sender)
		end
		return
	end

	local fields = { strsplit("|", message) }
	if fields[1] ~= MSG_DATA or fields[2] ~= DATA_VERSION then
		return
	end

	local function num(i)
		return tonumber(fields[i]) or 0
	end

	cache[BareName(sender)] = {
		receivedAt = GetTime(),
		data = {
			classFile = fields[3],
			specID = num(4),
			primaryName = fields[5],
			primary = num(6),
			crit = { rating = num(7), pct = num(8) },
			haste = { rating = num(9), pct = num(10) },
			mastery = { rating = num(11), pct = num(12) },
			vers = { rating = num(13), pct = num(14) },
			leech = { rating = num(15), pct = num(16) },
			avoidance = { rating = num(17), pct = num(18) },
			ilvlEquipped = num(19),
			ilvlOverall = num(20),
		},
	}
end

-- fullName is sent to SendAddonMessage exactly as given (same rules as a
-- plain /w: bare name same-realm, "Name-Realm" cross-realm) -- only the
-- throttle/cache side gets normalized, not the whisper target itself.
-- fullName se manda a SendAddonMessage exactamente como se recibe (mismas
-- reglas que un /w normal: nombre simple en el mismo reino, "Nombre-Reino"
-- entre reinos) -- solo el lado del throttle/cache se normaliza, no el
-- destino del whisper en si.
function Sync:RequestStats(fullName)
	if not fullName or fullName == "" then
		return
	end
	local key = BareName(fullName)
	local last = pendingRequests[key]
	if last and (GetTime() - last) < REQUEST_THROTTLE then
		return
	end
	pendingRequests[key] = GetTime()
	C_ChatInfo.SendAddonMessage(PREFIX, MSG_REQUEST, "WHISPER", fullName)
end

local TOOLTIP_STAT_ORDER = { "crit", "haste", "mastery", "vers", "leech", "avoidance" }

local function AppendTooltipLines(tooltip, data)
	tooltip:AddLine(" ")
	tooltip:AddLine("StatsMythic", 0.6, 0.6, 1)
	tooltip:AddLine(string.format("%s: %d", data.primaryName, data.primary))
	for _, key in ipairs(TOOLTIP_STAT_ORDER) do
		local s = data[key]
		local label = (ns.Panel and ns.Panel.LABELS and ns.Panel.LABELS[key]) or key
		tooltip:AddLine(string.format("%s: %d (%.2f%%)", label, s.rating, s.pct))
	end
	tooltip:AddLine(string.format("ilvl: %d / %d", data.ilvlEquipped, data.ilvlOverall))
end

-- Scoped to party/raid frames on purpose -- an arbitrary mouseover (a
-- stranger's nameplate in a city) would fire a whisper request at someone
-- who never asked for one. "/stm ver <nombre>" is the deliberate,
-- explicit path for anyone outside the group.
-- Limitado a marcos de party/raid a proposito -- un mouseover cualquiera
-- (la placa de un desconocido en una ciudad) dispararia una solicitud de
-- whisper a alguien que nunca la pidio. "/stm ver <nombre>" es el camino
-- deliberado y explicito para cualquiera fuera del grupo.
function Sync:OnTooltipSetUnit(tooltip)
	local _, unit = tooltip:GetUnit()
	if not unit or unit == "player" or not UnitIsPlayer(unit) then
		return
	end
	if not (UnitInParty(unit) or UnitInRaid(unit)) then
		return
	end

	local fullName = GetUnitName(unit, true)
	if not fullName then
		return
	end

	local data = self:GetCached(fullName)
	if data then
		AppendTooltipLines(tooltip, data)
	else
		tooltip:AddLine(" ")
		local waitingText = (ns.Config and ns.Config.L and ns.Config.L().syncTooltipWaiting) or "StatsMythic: syncing..."
		tooltip:AddLine(waitingText, 0.6, 0.6, 0.6)
	end
	tooltip:Show()

	self:RequestStats(fullName)

	-- No cached data yet: give the in-flight reply a moment, then nudge the
	-- tooltip to redraw itself if it's still open on the same unit, so the
	-- numbers can appear without a second hover.
	-- Todavia sin datos cacheados: le da un momento a la respuesta en
	-- camino, y si el tooltip sigue abierto en la misma unidad lo empuja a
	-- redibujarse, para que los numeros puedan aparecer sin un segundo
	-- mouseover.
	if not data then
		C_Timer.After(0.8, function()
			if GameTooltip:IsShown() then
				local _, stillUnit = GameTooltip:GetUnit()
				if stillUnit and GetUnitName(stillUnit, true) == fullName then
					GameTooltip:SetUnit(stillUnit)
				end
			end
		end)
	end
end

function Sync:Init()
	if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then
		return
	end
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

	ns.addon:RegisterEvent("CHAT_MSG_ADDON", function(_event, prefix, message, channel, sender)
		OnMessage(prefix, message, channel, sender)
	end)

	GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
		Sync:OnTooltipSetUnit(tooltip)
	end)
end
