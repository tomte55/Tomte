local addonName, ns = ...

-- Drawers: the on-screen drawers. Each drawer is a secure toggle button (named TomteDrawer<n> for its CLICK key
-- binding) whose restricted _onclick snippet shows or hides its flyout, so a drawer opens and closes in combat too;
-- each entry in the flyout is a secure action button, wrapped so a use can close the flyout from restricted code.
-- Secure frames are made lazily out of combat, and any change asked for in combat waits for PLAYER_REGEN_ENABLED.
-- Pure layout in Data.lua, entry reading in Read.lua; registered in Drawers.lua.

local SIZE = 36 -- toggle and entry buttons, in pixels
local GAP = 4 -- between buttons
local EMPTY_ALPHA = 0.45 -- a drawer whose searches find nothing right now
local FLYOUT_ALPHA = 0.55 -- the open drawer's backdrop
local PAD = 4 -- flyout background around its buttons
local BUTTON_PREFIX = "TomteDrawer" -- TomteDrawer1..N: the CLICK bindings in Bindings.xml need these names
-- In a pet battle or a vehicle the action bars go away; the drawers too (a state driver, so it works in combat).
local VISIBILITY = "[petbattle][vehicleui] hide; show"
local UI = ns.UI
local IsSecret = ns.IsSecret

local events = ns.NewEvents()
ns.Drawers_Events = events
local owner = {}

local db, module
local drawers = {} -- [i] = { toggle = button, flyout = frame, buttons = { entry buttons } }
local pending = false -- a refresh asked for in combat, done when it ends

-- Restricted code (runs in combat). A right click only opens the editor (PostClick); a left click or the key
-- binding opens this drawer's flyout and closes the others, or closes it when it's open.
local TOGGLE_SNIPPET = [[
	if button == "RightButton" then
		return
	end
	local flyout = self:GetFrameRef("flyout")
	if flyout:IsShown() then
		flyout:Hide()
		return
	end
	for i = 1, ]] .. ns.DRAWERS_COUNT .. [[ do
		local other = self:GetFrameRef("other" .. i)
		if other then
			other:Hide()
		end
	end
	flyout:Show()
]]
-- Around each entry's click: after the secure action, close the flyout when "Close after use" is on (an
-- attribute on the flyout, set out of combat). The post body only runs when the pre body returns a message.
local ENTRY_PRE = [[
	if self:GetParent():GetAttribute("closeonuse") then
		return nil, "close"
	end
]]
local ENTRY_POST = [[
	self:GetParent():Hide()
]]

local function Binding(i)
	return "CLICK " .. BUTTON_PREFIX .. i .. ":LeftButton"
end
ns.Drawers_Binding = Binding

-- Drawer i's settings and its entries.
local function DrawerDB(i)
	return ns.Drawers_Saved(db, i)
end

-- Seconds before reading again when a searched item's data was still loading.
local LOAD_RETRY = 1
local retrying = false
local Refresh

-- What drawer i's buttons show: its entries with each search filled in from the bags (Data.lua's Drawers_Expand).
local function Shown(i)
	local _, entries = DrawerDB(i)
	if not ns.Drawers_HasSearch(entries) then
		return entries
	end
	local found, loading = ns.Drawers_Found(entries)
	if loading and not retrying then
		retrying = true
		C_Timer.After(LOAD_RETRY, function()
			retrying = false
			if module.active then
				Refresh()
			end
		end)
	end
	return ns.Drawers_Expand(entries, found)
end

-- Looks (not protected: these run in combat too) -------------------------------------------------------------

local function SetCooldown(cd, start, duration)
	if IsSecret(start) or IsSecret(duration) or not start or not duration or start <= 0 or duration <= 0 then
		cd:Clear()
	else
		cd:SetCooldown(start, duration)
	end
end

-- Also fills the settings preview's plain copies (DrawSample below), so they show the same icons and counts.
local function UpdateButton(b)
	local entry = b.entry
	if not entry then
		return
	end
	local _, icon, have = ns.Drawers_Info(entry)
	b.icon:SetTexture(icon)
	b.icon:SetDesaturated(not have)
	if entry.kind == "item" then
		local count = C_Item.GetItemCount(entry.id, false, true)
		b.count:SetText((not IsSecret(count) and count and count > 1) and ns.Thousands(count) or "")
	else
		b.count:SetText("")
	end
	if entry.kind == "item" or entry.kind == "toy" then
		local start, duration = C_Item.GetItemCooldown(entry.id)
		SetCooldown(b.cooldown, start, duration)
	elseif entry.kind == "spell" then
		local info = C_Spell.GetSpellCooldown(entry.id)
		SetCooldown(b.cooldown, info and info.startTime, info and info.duration)
	else
		b.cooldown:Clear()
	end
end

-- Drawer i's button t: its first button's icon, its name when names show, its key. Real or preview button. shown:
-- what the drawer shows now. Empty (a search that finds nothing in the bags): emptyIcon (what it last showed, else the
-- drawer bag), grey and faded, so it reads as "nothing in here right now".
local function FillToggle(t, i, name, showNames, shown, emptyIcon)
	local empty = shown[1] == nil
	t.icon:SetTexture(empty and (emptyIcon or ns.DRAWERS_EMPTY_ICON) or select(2, ns.Drawers_Info(shown[1])))
	t.icon:SetDesaturated(empty)
	t.icon:SetAlpha(empty and EMPTY_ALPHA or 1)
	t.label:SetText(showNames and ns.Drawers_Name(name, i) or "")
	local key = GetBindingKey(Binding(i))
	t.hotkey:SetText(key and GetBindingText(key, 1) or "") -- 1: abbreviated, as on Blizzard's action buttons
end

local function UpdateToggle(i)
	local d = drawers[i]
	local saved = DrawerDB(i)
	local shown = d.shown or {}
	if shown[1] then
		d.lastIcon = select(2, ns.Drawers_Info(shown[1]))
	end
	FillToggle(d.toggle, i, saved.name, db.showNames, shown, d.lastIcon)
end

local function UpdateLooks()
	for i, d in ipairs(drawers) do
		if d.toggle:IsShown() then
			UpdateToggle(i)
			if d.flyout:IsShown() then
				for _, b in ipairs(d.buttons) do
					if b:IsShown() then
						UpdateButton(b)
					end
				end
			end
		end
	end
end

-- Tooltips ----------------------------------------------------------------------------------------------------

local function EntryOnEnter(self)
	if self.entry then
		ns.Drawers_Tooltip(self, self.entry)
	end
end

local function ToggleOnEnter(self)
	local i = self:GetID()
	local saved = DrawerDB(i)
	local n = #(drawers[i].shown or {})
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.Drawers_Name(saved.name, i), UI.RGB("heading"))
	UI.TipLine(n == 1 and "1 entry" or (n .. " entries"), "textMuted")
	UI.TipLine("Click: open or close", "text")
	UI.TipLine("Right-click: edit (out of combat)", "text")
	local key = GetBindingKey(Binding(i))
	UI.TipLine(key and ("Key: " .. GetBindingText(key)) or "No key: Key Bindings > Tomte", "textMuted")
	GameTooltip:Show()
end

local function TogglePostClick(self, button)
	if button == "RightButton" and not InCombatLockdown() then
		ns.Drawers_OpenEditor(self:GetID())
	end
end

-- Frames (out of combat only) ---------------------------------------------------------------------------------

local function Icon(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	UI.ActionIcon(b, b.icon, SIZE, 0.8)
end

-- The looks of an entry button, a drawer's button and its flyout, shared by the real (secure) frames and the
-- settings preview's plain ones.
local function EntryLooks(b)
	b:SetSize(SIZE, SIZE)
	Icon(b)
	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	local inset = UI.ActionIconInset(SIZE)
	b.cooldown:SetPoint("TOPLEFT", inset, -inset)
	b.cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)
	-- The count sits above the cooldown sweep, outlined: the shadow alone didn't read on bright icons.
	local over = CreateFrame("Frame", nil, b)
	over:SetAllPoints()
	over:SetFrameLevel(b.cooldown:GetFrameLevel() + 1)
	b.count = UI.Text(over, 11, "text", "number")
	UI.SetFont(b.count, "number", 11, "OUTLINE")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
end

local function ToggleLooks(t)
	t:SetSize(SIZE, SIZE)
	Icon(t)
	t.label = UI.Text(t, 10, "textMuted", "label")
	t.label:SetPoint("TOP", t, "BOTTOM", 0, -3)
	t.hotkey = UI.Text(t, 10, "heading", "number")
	UI.SetFont(t.hotkey, "number", 10, "OUTLINE")
	t.hotkey:SetPoint("TOPRIGHT", -2, -2)
end

-- A soft dark backdrop behind the open drawer's buttons, no outline. Its color is set again on each refresh
-- (FlyoutColor), so a theme switch reaches it.
local function FlyoutColor(f)
	local r, g, b = UI.Color("bg")
	f.bg:SetColorTexture(r, g, b, FLYOUT_ALPHA)
end

local function FlyoutLooks(f)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	FlyoutColor(f)
end

-- Places the first n of buttons around anchor's center as the drawer opens (direction, perLine) and the flyout
-- around them. Returns the flyout buttons' box (Drawers_Layout), relative to anchor's center.
local function Arrange(anchor, flyout, buttons, n, direction, perLine)
	local points, box = ns.Drawers_Layout(n, direction, perLine, SIZE, GAP)
	for j = 1, n do
		buttons[j]:ClearAllPoints()
		buttons[j]:SetPoint("CENTER", anchor, "CENTER", points[j].x, points[j].y)
	end
	flyout:ClearAllPoints()
	flyout:SetPoint("TOPLEFT", anchor, "CENTER", box.left - PAD, box.top + PAD)
	flyout:SetPoint("BOTTOMRIGHT", anchor, "CENTER", box.right + PAD, box.bottom - PAD)
	return box
end

local function CreateEntryButton(d)
	local b = CreateFrame("Button", nil, d.flyout, "SecureActionButtonTemplate")
	-- Mouse only (no binding): SecureActionButton_OnClick ignores useOnKeyDown for a real mouse press and acts on
	-- the up click, so a button registered for down clicks only would never act. Up only also keeps the close-after-use
	-- wrapper from hiding the flyout on the down click before the action's up click arrives.
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	EntryLooks(b)
	b:SetScript("OnEnter", EntryOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	SecureHandlerWrapScript(b, "OnClick", d.toggle, ENTRY_PRE, ENTRY_POST)
	b:Hide()
	d.buttons[#d.buttons + 1] = b
	return b
end

local function CreateDrawer(i)
	-- The toggle is the frame Edit Mode moves; protected, so the flyout and its buttons may anchor to it.
	local t = CreateFrame("Button", BUTTON_PREFIX .. i, UIParent, "SecureHandlerClickTemplate")
	t:SetID(i)
	t:SetMovable(true)
	t:SetClampedToScreen(true)
	t:SetFrameStrata("MEDIUM")
	-- Down clicks only: the key binding's press opens the drawer once, not again on release.
	t:RegisterForClicks("AnyDown")
	t:SetAttribute("_onclick", TOGGLE_SNIPPET)
	t:SetScript("PostClick", TogglePostClick)
	t:SetScript("OnEnter", ToggleOnEnter)
	t:SetScript("OnLeave", GameTooltip_Hide)
	ToggleLooks(t)
	t:Hide()

	local f = CreateFrame("Frame", nil, t, "SecureFrameTemplate")
	f:SetFrameStrata("DIALOG")
	FlyoutLooks(f)
	f:Hide()
	f:HookScript("OnShow", UpdateLooks)
	t:SetFrameRef("flyout", f)
	drawers[i] = { toggle = t, flyout = f, buttons = {} }
end

local function CreateAll()
	for i = 1, ns.DRAWERS_COUNT do
		CreateDrawer(i)
	end
	for i, d in ipairs(drawers) do
		for j, other in ipairs(drawers) do
			if j ~= i then
				d.toggle:SetFrameRef("other" .. j, other.flyout)
			end
		end
	end
end

-- Secure attributes for one entry. Mounts by a /cast macro: type=spell with a mount's spell runs but never
-- summons it (measured in game, 12.1).
local function SetEntry(b, entry)
	b.entry = entry
	local kind, id = entry.kind, entry.id
	b:SetAttribute("item", nil)
	b:SetAttribute("toy", nil)
	b:SetAttribute("spell", nil)
	b:SetAttribute("macrotext", nil)
	if kind == "item" then
		b:SetAttribute("type", "item")
		b:SetAttribute("item", "item:" .. id)
	elseif kind == "toy" then
		b:SetAttribute("type", "toy")
		b:SetAttribute("toy", id)
	elseif kind == "spell" then
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", id)
	else
		local _, _, _, spellID = ns.Drawers_Info(entry)
		local name = spellID and C_Spell.GetSpellName(spellID)
		b:SetAttribute("type", name and "macro" or nil)
		b:SetAttribute("macrotext", name and ("/cast " .. name) or nil)
	end
end

local function ClearEntry(b)
	b.entry = nil
	b:SetAttribute("type", nil)
	b:Hide()
end

local function ApplyLayout(i)
	local t, f = drawers[i].toggle, drawers[i].flyout
	local d = (DrawerDB(i))
	t:ClearAllPoints()
	t:SetPoint(d.frame.point, UIParent, d.frame.relPoint, d.frame.x, d.frame.y)
	t:SetScale(db.scale)
	f:SetAttribute("closeonuse", db.closeOnUse and true or nil)
	FlyoutColor(f)
end

local function Build(i)
	local d = drawers[i]
	local saved = DrawerDB(i)
	local entries = Shown(i)
	d.shown = entries
	for j, entry in ipairs(entries) do
		local b = d.buttons[j] or CreateEntryButton(d)
		SetEntry(b, entry)
		b:Show()
	end
	for j = #entries + 1, #d.buttons do
		ClearEntry(d.buttons[j])
	end
	Arrange(d.toggle, d.flyout, d.buttons, #entries, saved.direction, saved.perLine)
	if #entries == 0 then
		d.flyout:Hide()
	end
end

local function SetShown(d, show)
	if show and not d.driven then
		-- Starts closed: its key binding still clicks the hidden toggle while the drawer is off.
		d.flyout:Hide()
		RegisterStateDriver(d.toggle, "visibility", VISIBILITY)
		d.driven = true
	elseif not show then
		if d.driven then
			UnregisterStateDriver(d.toggle, "visibility")
			d.driven = false
		end
		d.toggle:Hide()
		d.flyout:Hide()
	end
end

function Refresh()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	if #drawers == 0 then
		if not module.active then
			return
		end
		CreateAll() -- here, out of combat: a /reload in combat can't make or place protected frames
	end
	local preview = ns.EditMode_Active()
	for i, d in ipairs(drawers) do
		local saved, entries = DrawerDB(i)
		ns.Drawers_Clean(entries)
		ApplyLayout(i)
		Build(i)
		SetShown(d, module.active and saved.enabled and (#entries > 0 or preview))
	end
	UpdateLooks()
end
ns.Drawers_Refresh = Refresh

function ns.Drawers_SavePosition(i)
	local t = drawers[i] and drawers[i].toggle
	if not t then
		return
	end
	local point, _, relPoint, x, y = t:GetPoint()
	local frame = (DrawerDB(i)).frame
	frame.point, frame.relPoint, frame.x, frame.y = point, relPoint, x, y
end

function ns.Drawers_Toggle(i)
	return drawers[i] and drawers[i].toggle
end

-- Settings preview ---------------------------------------------------------------------------------------------

-- An empty drawer previews with these (module icons elsewhere in Tomte, so known to exist), enough to show a
-- second line at the default "Buttons per line".
local SAMPLE_ICONS = {
	136245, 136248, 136243, 237429, 132268, 134441, 133785, 135934, 237387, 132161,
}
local LABEL_ROOM = 16 -- the name under the drawer's button: its 3 pixel gap and a line of 10 point text

-- Drawer i opened (Panel/Preview.lua), drawn by plain copies of its frames with the same looks and layout code:
-- nothing secure, nothing clickable. Its own entries, or sample icons while it's empty. get reads the settings.
function ns.Drawers_DrawSample(host, get, i)
	local v = host.drawer
	if not v then
		v = { buttons = {} }
		v.root = CreateFrame("Frame", nil, host)
		v.root:SetPoint("TOPLEFT")
		v.flyout = CreateFrame("Frame", nil, v.root)
		FlyoutLooks(v.flyout)
		v.toggle = CreateFrame("Button", nil, v.root)
		ToggleLooks(v.toggle)
		host.drawer = v
	end
	local key = "d" .. i
	local _, saved = DrawerDB(i)
	local entries = Shown(i)
	local n = #entries > 0 and #entries or #SAMPLE_ICONS
	for j = 1, n do
		local b = v.buttons[j]
		if not b then
			b = CreateFrame("Button", nil, v.flyout)
			EntryLooks(b)
			v.buttons[j] = b
		end
		b.entry = entries[j]
		if b.entry then
			UpdateButton(b)
		else
			b.icon:SetTexture(SAMPLE_ICONS[j])
			b.icon:SetDesaturated(false)
			b.count:SetText("")
			b.cooldown:Clear()
		end
		b:Show()
	end
	for j = n + 1, #v.buttons do
		v.buttons[j]:Hide()
	end
	local showNames = get("showNames")
	FillToggle(v.toggle, i, get(key .. ".name"), showNames, entries, drawers[i] and drawers[i].lastIcon)
	if #saved == 0 then -- nothing added yet: the sample, in full color
		v.toggle.icon:SetTexture(SAMPLE_ICONS[1])
		v.toggle.icon:SetDesaturated(false)
		v.toggle.icon:SetAlpha(1)
	end
	local box = Arrange(v.toggle, v.flyout, v.buttons, n, get(key .. ".direction"), get(key .. ".perLine"))

	-- The picture's bounds around the drawer button's center: the button, the open flyout, the name under it.
	local half = SIZE / 2
	local left, right = math.min(-half, box.left - PAD), math.max(half, box.right + PAD)
	local top, bottom = math.max(half, box.top + PAD), math.min(-half, box.bottom - PAD)
	if showNames then
		local w = v.toggle.label:GetUnboundedStringWidth() / 2
		left, right = math.min(left, -w), math.max(right, w)
		bottom = math.min(bottom, -half - LABEL_ROOM)
	end
	v.toggle:ClearAllPoints()
	v.toggle:SetPoint("CENTER", v.root, "TOPLEFT", -left, -top)
	local scale = get("scale")
	v.root:SetScale(scale)
	v.root:SetSize(right - left, top - bottom)
	return (right - left) * scale, (top - bottom) * scale
end

-- Events ------------------------------------------------------------------------------------------------------

events:On(owner, "PLAYER_REGEN_ENABLED", function()
	if pending then
		Refresh()
	end
	if not module.active then
		events:UnwatchAll(owner) -- the module was turned off in combat: now everything is hidden
	end
end)
events:On(owner, "PLAYER_ENTERING_WORLD", Refresh)
events:On(owner, "UPDATE_BINDINGS", UpdateLooks)
for _, event in ipairs({ "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "TOYS_UPDATED" }) do
	events:On(owner, event, UpdateLooks)
end

-- A click anywhere else closes an open drawer. Out of combat only: the flyout is protected, so in combat only its own
-- secure code (its button, close after use) can hide it.
events:On(owner, "GLOBAL_MOUSE_DOWN", function()
	if InCombatLockdown() then
		return
	end
	for _, d in ipairs(drawers) do
		if d.flyout:IsShown() and not (d.flyout:IsMouseOver() or d.toggle:IsMouseOver()) then
			d.flyout:Hide()
		end
	end
end)

-- The bags changed: a drawer with a search fills in again (after combat, when you're fighting: its buttons are
-- protected), the others only update their counts.
events:On(owner, "BAG_UPDATE_DELAYED", function()
	for i = 1, #drawers do
		local _, entries = DrawerDB(i)
		if ns.Drawers_HasSearch(entries) then
			Refresh()
			return
		end
	end
	UpdateLooks()
end)

local WATCH = {
	"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN",
	"SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "TOYS_UPDATED", "GLOBAL_MOUSE_DOWN",
}

function ns.Drawers_BarStart()
	for _, event in ipairs(WATCH) do
		events:TryWatch(owner, event) -- Forever has no toy box: no TOYS_UPDATED there
	end
	Refresh()
end

function ns.Drawers_BarStop()
	if InCombatLockdown() then
		-- Hidden when combat ends (PLAYER_REGEN_ENABLED stops watching then); nothing else to update meanwhile.
		pending = true
		for _, event in ipairs(WATCH) do
			if event ~= "PLAYER_REGEN_ENABLED" then
				events:Unwatch(owner, event)
			end
		end
		return
	end
	events:UnwatchAll(owner)
	Refresh() -- module.active is false by now: hides every drawer
end

function ns.Drawers_BarSetup(moduleDB, mod)
	db, module = moduleDB, mod
end
