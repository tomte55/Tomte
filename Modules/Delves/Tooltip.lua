local addonName, ns = ...

-- Delves: coffer key and shard caps on tooltips: the key and shard currencies, the shard items and the weekly caches
-- that give them (Data/<Expansion>/Delves.lua). The lines come from Delves_CapLines (Data.lua) over the readers'
-- cache (Read.lua): nothing is read from the game while a tooltip builds. Started and stopped from Delves.lua.

local UI = ns.UI

local db
local on = false -- post-calls can't be removed: they do nothing while this is false
local hooked = false
local kinds, kindsFor -- [currency or item ID] = "keys" or "shards", built for the expansion kindsFor

local function Kinds()
	local expansion = ns.ContentExpansion()
	if kindsFor == expansion then
		return kinds
	end
	kinds, kindsFor = { currency = {}, item = {} }, expansion
	local def = ns.Content_Get(expansion, "delves")
	if not def then
		return kinds
	end
	kinds.currency[def.keyCurrency] = "keys"
	local s = def.shards or {}
	if s.currency then
		kinds.currency[s.currency] = "shards"
	end
	for _, id in ipairs(s.items or {}) do
		kinds.item[id] = "shards"
	end
	for kind, ids in pairs(def.capItems or {}) do
		for _, id in ipairs(ids) do
			kinds.item[id] = kind
		end
	end
	return kinds
end

local function Add(tooltip, kind)
	local lines = ns.Delves_CapLines(ns.DelvesRead_State().keys, kind)
	if #lines == 0 then
		return
	end
	tooltip:AddLine(" ")
	local lr, lg, lb = UI.RGB("textMuted")
	for _, line in ipairs(lines) do
		local rr, rg, rb = UI.RGB(line.role)
		tooltip:AddDoubleLine(line.left, line.right, lr, lg, lb, rr, rg, rb)
	end
end

local function Handler(which)
	return function(tooltip, data)
		if not (on and db.capTooltips and tooltip.AddDoubleLine and data) then
			return
		end
		local id = data.id
		if not id or ns.IsSecret(id) or type(id) ~= "number" then
			return
		end
		local kind = Kinds()[which][id]
		if kind then
			Add(tooltip, kind)
		end
	end
end

function ns.DelvesTooltip_Start(saved)
	db = saved
	on = true
	kindsFor = nil
	if not hooked then
		hooked = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, ns.Perf_Wrap(Handler("currency"), "tooltip"))
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(Handler("item"), "tooltip"))
	end
end

function ns.DelvesTooltip_Stop()
	on = false
end
