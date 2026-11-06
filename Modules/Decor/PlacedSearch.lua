local addonName, ns = ...

-- Decorating tools: a search box over Blizzard's placed-decor list (Expert mode). Rows whose name doesn't match fade
-- out; Blizzard's list and its data are never changed, only the rows' alpha. Also reads the open list for the
-- panel's "Export decor placed in this house" (the game only gives the placed decor to Blizzard's list).
-- Rules in ToolsData.lua; registered in Decorate.lua.

local FADED = 0.2 -- alpha of a row that doesn't match
local UI = ns.UI

local db
local active, editing = false, false
local list, box
local callbackOwner = {} -- our owner on the list's ScrollBox callbacks
local registered = false

local function List()
	local expert = HouseEditorFrame and HouseEditorFrame.ExpertDecorModeFrame
	return expert and expert.PlacedDecorList
end

local function Query()
	return box and box:IsShown() and box:GetText() or ""
end

local function Dim()
	if not (list and list.ScrollBox) then
		return
	end
	local query = Query()
	for _, frame in list.ScrollBox:EnumerateFrames() do
		local data = frame.elementData
		frame:SetAlpha(ns.DecorTools_Matches(data and data.name, query) and 1 or FADED)
	end
end

local function CreateBox()
	list = list or List()
	if box or not list then
		return
	end
	box = CreateFrame("EditBox", nil, list)
	box:SetHeight(22)
	box:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 8, 4)
	box:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -8, 4)
	box:SetAutoFocus(false)
	UI.SearchBoxClear(box)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.5)
	local placeholder = UI.Text(box, 12, "textFaint")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search placed decor")
	box:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		Dim()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
end

local function Update()
	local on = active and editing and db.placedSearch
	if on then
		CreateBox()
	end
	if box then
		box:SetShown(on == true)
		if not on then
			box:SetText("")
		end
	end
	local scrollBox = list and list.ScrollBox
	if scrollBox and BaseScrollBoxEvents then
		if on and not registered then
			scrollBox:RegisterCallback(BaseScrollBoxEvents.OnLayout, Dim, callbackOwner)
			registered = true
		elseif not on and registered then
			scrollBox:UnregisterCallback(BaseScrollBoxEvents.OnLayout, callbackOwner)
			registered = false
		end
	end
	Dim()
end

-- The decor IDs placed in this house, one per piece, from Blizzard's open placed-decor list; or nil and why not.
function ns.DecoratePlaced_IDs()
	local placed = List()
	local provider = placed and placed:IsShown() and placed.ScrollBox and placed.ScrollBox:GetDataProvider()
	if not provider then
		return nil, "Open Blizzard's placed decor list first (Expert mode, the list button)."
	end
	local ids = {}
	for _, data in provider:Enumerate() do
		local ok, info = pcall(C_HousingDecor.GetDecorInstanceInfoForGUID, data.decorGUID)
		if ok and type(info) == "table" and info.decorID then
			ids[#ids + 1] = info.decorID
		end
	end
	if #ids == 0 then
		return nil, "No decor is placed in this house."
	end
	return ids
end

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecoratePlaced_Init(saved)
	db = saved
end

function ns.DecoratePlaced_Start()
	active = true
	Update()
end

function ns.DecoratePlaced_Stop()
	active = false
	Update()
end

function ns.DecoratePlaced_Editing(on)
	editing = on
	Update()
end

function ns.DecoratePlaced_Apply()
	Update()
end
