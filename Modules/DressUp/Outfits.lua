local addonName, ns = ...

-- Dressing room outfits: the toolbar's Outfits button (a menu of the outfits saved in the dressing room, tried on the
-- model with one click) and /tomte dressup outfit <name>. Dressing room outfits are Blizzard's custom sets
-- (C_TransmogCollection). The transmog outfits a character wears (C_TransmogOutfitInfo, 12.0) switch through a secure
-- action only (Blizzard's /outfit command, an action button), so away from the transmogrifier the command names the
-- /outfit line to type. Name matching in Data.lua; the button itself in Tools.lua.

local UI = ns.UI
local BAR = ns.DressUpBar
local FindByName = ns.DressUp_FindByName

local function ByName(a, b)
	return a.name:lower() < b.name:lower()
end

-- The dressing room's saved outfits: { { id, name, icon, kind = "set" } }, sorted by name.
local function CustomSets()
	local list = {}
	for _, id in ipairs(C_TransmogCollection.GetCustomSets() or {}) do
		local name, icon = C_TransmogCollection.GetCustomSetInfo(id)
		if name and name ~= "" then
			list[#list + 1] = { id = id, name = name, icon = icon, kind = "set" }
		end
	end
	table.sort(list, ByName)
	return list
end

-- The character's transmog outfits: { { id, name, index (Blizzard's /outfit number), kind = "outfit" } }.
local function TransmogOutfits()
	local list = {}
	local infos = C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetOutfitsInfo() or {}
	for _, info in ipairs(infos) do
		if not info.isDisabled and info.name and info.name ~= "" then
			list[#list + 1] = { id = info.outfitID, name = info.name, index = info.playerFacingOutfitIndex,
				kind = "outfit" }
		end
	end
	return list
end

-- Dresses the open dressing room's model in an ItemTransmogInfo list (indexed by inventory slot), talking only to the
-- actor like the slot bar does. false when the window isn't open on the player.
local function TryOnModel(list)
	local frame = DressUpFrame
	local actor = BAR.Actor()
	if not (frame and frame:IsShown() and frame:GetMode() == "player" and actor) then
		return false
	end
	for slot, info in ipairs(list) do
		-- pcall: an outfit can hold a piece this character's model can't wear.
		pcall(actor.SetItemTransmogInfo, actor, info, slot, slot ~= INVSLOT_MAINHAND)
	end
	return true
end

local function Preview(set)
	local list = C_TransmogCollection.GetCustomSetItemTransmogInfoList(set.id)
	if not list then
		return
	end
	if not TryOnModel(list) then
		-- Closed: Blizzard's own function opens it on the list (what its /customset command does).
		DressUpItemTransmogInfoList(list)
	end
end

local function AtTransmogrifier()
	return C_Transmog.IsAtTransmogNPC() and TransmogFrame and TransmogFrame:IsShown()
end

-- The toolbar button's menu.
function ns.DressUp_OutfitMenu(button)
	local sets = CustomSets()
	if #sets == 0 then
		ns.Print("no saved outfits yet. Save one with the dressing room's outfit menu.")
		return
	end
	UI.ContextMenu(button, function(_, root)
		root:CreateTitle("Try on an outfit")
		for _, set in ipairs(sets) do
			root:CreateButton(set.name, function()
				Preview(set)
			end)
		end
	end)
end

local function Names(list)
	local names = {}
	for i, e in ipairs(list) do
		names[i] = e.name
	end
	return table.concat(names, ", ")
end

-- /tomte dressup outfit <name>
function ns.DressUp_OutfitCommand(arg)
	local sets, outfits = CustomSets(), TransmogOutfits()
	arg = strtrim(arg or "")
	if arg == "" then
		ns.Print("dressing room outfits: " .. (#sets > 0 and Names(sets) or "none"))
		ns.Print("transmog outfits: " .. (#outfits > 0 and Names(outfits) or "none"))
		return
	end
	local all = {}
	for _, e in ipairs(sets) do
		all[#all + 1] = e
	end
	for _, e in ipairs(outfits) do
		all[#all + 1] = e
	end
	local entry, names = FindByName(all, arg)
	if not entry then
		if #names > 0 then
			ns.Print("which one? " .. table.concat(names, ", "))
		else
			ns.Print(("no outfit called \"%s\". /tomte dressup outfit lists them."):format(arg))
		end
		return
	end
	if entry.kind == "set" then
		if AtTransmogrifier() then
			C_TransmogOutfitInfo.SetOutfitToCustomSet(entry.id)
			ns.Print(("%s is set up in the transmogrifier. Apply to keep it."):format(entry.name))
		else
			Preview(entry)
		end
	elseif AtTransmogrifier() then
		-- Switching drops what's pending; Blizzard's own outfit list asks first, so we don't switch at all then.
		if C_TransmogOutfitInfo.HasPendingOutfitTransmogs() then
			ns.Print("apply or clear your changes first.")
			return
		end
		C_TransmogOutfitInfo.ChangeViewedOutfit(entry.id)
	else
		ns.Print(("type %s %d to wear %s (outfits only switch by Blizzard's command or a key press)."):format(
			SLASH_TRANSMOG_OUTFIT1 or "/outfit", entry.index, entry.name))
	end
end
