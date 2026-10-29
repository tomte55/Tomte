local addonName, ns = ...

-- "Tomte window": settings for the Tomte window itself and its Home screen. Always on (no enable checkbox).

local MOCK_W, MOCK_H = 260, 196 -- the theme preview's mock window
local MOCK_PAD = 12
local SURFACE_H = 66
local SURFACE_RULE = 0.35 -- the surface box's rule alpha, as UI.Surface
local SWITCH_W, SWITCH_H = 28, 14
local CHIP_H = 18
local CHIP_FILL = 0.16 -- a chip's fill: its status color, faint
local NINE_SLICE_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge" }

local UI = ns.UI

local function Redraw()
	ns.Panel_Refresh()
end

local MOTION_CHOICES = {
	{ value = "full", text = "Full" },
	{ value = "subtle", text = "Subtle" },
	{ value = "off", text = "Off" },
}

local SOUND_CHOICES = {
	{ value = "all", text = "All" },
	{ value = "important", text = "Only important" },
	{ value = "off", text = "Off" },
}

local function MotionChoices()
	return MOTION_CHOICES
end

local function SoundChoices()
	return SOUND_CHOICES
end

-- Setup and sharing (Panel/Setup.lua, Panel/Share.lua, Panel/Bug.lua): last on the page, above the Reset rows.
local SHARE = {
	{ type = "header", label = "Setup and sharing" },
	{ type = "button", label = "Pick a preset (Collector, Crafter, Minimal, Everything)", text = "Run setup",
		onClick = function()
			ns.SetupUI_Show()
		end,
		tooltip = "Turns modules on or off to fit how you play. Settings inside modules stay." },
	{ type = "button", label = "Your settings as a string for a friend", text = "Export",
		onClick = function()
			ns.ShareUI_Export()
		end,
		tooltip = "Settings only: no characters, history, flight times or lists." },
	{ type = "button", label = "Use a friend's settings", text = "Import",
		onClick = function()
			ns.ShareUI_Import()
		end,
		tooltip = "Paste their string, see what changes, then confirm. Your UI reloads." },
	{ type = "button", label = "Back to your settings from before the last import", text = "Undo import",
		shown = function()
			return ns.ShareUI_HasBackup()
		end,
		onClick = function()
			ns.ShareUI_Undo()
		end,
		tooltip = "Shows what changes back, then reloads your UI." },
	{ type = "button", label = "Something broke? A report to copy and send", text = "Bug report",
		onClick = function()
			ns.BugUI_Show()
		end,
		tooltip = "Versions, modules, other addons and Tomte's last errors. Sent nowhere by itself." },
	{ type = "checkbox", key = "bugToast", label = "Tell me when Tomte has an error",
		tooltip = "A small toast when one of Tomte's Lua errors happens, at most one a minute, held back until combat ends. "
			.. "Click it for the bug report to copy and send." },
}

-- Theme preview ---------------------------------------------------------------------------------------------------

-- A small mock window in the hovered theme's own colors and fonts (its Theme.Get definition). The real drawing code
-- (UI.Panel, UI.Text, UI.Switch) only knows the applied theme, and switching themes takes a reload, so this mock
-- mirrors their look by hand: tooltip nine-slice or a gradient fill with a dark edge and an inset rule, a surface box,
-- an accent bar and switch, status chips.

-- Edges `inset` px inside their frame (top, bottom, left, right).
local function PlaceEdges(edges, inset)
	local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
	top:SetPoint("TOPLEFT", inset, -inset)
	top:SetPoint("TOPRIGHT", -inset, -inset)
	bottom:SetPoint("BOTTOMLEFT", inset, inset)
	bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
	left:SetPoint("TOPLEFT", inset, -inset)
	left:SetPoint("BOTTOMLEFT", inset, inset)
	right:SetPoint("TOPRIGHT", -inset, -inset)
	right:SetPoint("BOTTOMRIGHT", -inset, inset)
end

-- Four 1 px edges `inset` px inside frame.
local function Edges(frame, layer, inset)
	local top, bottom = frame:CreateTexture(nil, layer), frame:CreateTexture(nil, layer)
	local left, right = frame:CreateTexture(nil, layer), frame:CreateTexture(nil, layer)
	top:SetHeight(1)
	bottom:SetHeight(1)
	left:SetWidth(1)
	right:SetWidth(1)
	local edges = { top, bottom, left, right }
	PlaceEdges(edges, inset)
	return edges
end

local function ColorEdges(edges, c, alpha)
	for _, t in ipairs(edges) do
		t:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
		t:SetShown((alpha or 1) > 0)
	end
end

local function Fill(t, c, alpha)
	t:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function Gradient(t, orientation, from, to, alpha)
	t:SetColorTexture(1, 1, 1, 1)
	t:SetGradient(orientation, CreateColor(from[1], from[2], from[3], alpha or 1), CreateColor(to[1], to[2], to[3],
		alpha or 1))
end

local function BuildMock(host)
	local m = CreateFrame("Frame", nil, host)
	m:SetPoint("TOPLEFT")
	m:SetSize(MOCK_W, MOCK_H)

	-- Blizzard-style themes: the tooltip's nine-slice, as UI.Panel's BlizzardPanel. Art themes: the layers below.
	m.nine = CreateFrame("Frame", nil, m)
	m.nine:SetAllPoints()
	m.nine:SetFrameLevel(m:GetFrameLevel())
	NineSliceUtil.ApplyLayoutByName(m.nine, "TooltipDefaultLayout")
	m.art = CreateFrame("Frame", nil, m)
	m.art:SetAllPoints()
	m.art:SetFrameLevel(m:GetFrameLevel())
	m.fill = m.art:CreateTexture(nil, "BACKGROUND", nil, -8)
	m.fill:SetAllPoints()
	m.outer = Edges(m.art, "BORDER", 0)
	m.inner = Edges(m.art, "BORDER", 0)

	m.content = CreateFrame("Frame", nil, m)
	m.content:SetAllPoints()
	m.content:SetFrameLevel(m:GetFrameLevel() + 2)
	local c = m.content
	m.title = UI.Text(c, 16, "heading", "title")
	m.title:SetPoint("TOPLEFT", MOCK_PAD, -MOCK_PAD)
	m.rule = c:CreateTexture(nil, "ARTWORK")
	m.rule:SetPoint("TOPLEFT", MOCK_PAD, -(MOCK_PAD + 24))
	m.rule:SetPoint("TOPRIGHT", -MOCK_PAD, -(MOCK_PAD + 24))
	m.rule:SetHeight(1)

	m.surface = CreateFrame("Frame", nil, c)
	m.surface:SetPoint("TOPLEFT", MOCK_PAD, -(MOCK_PAD + 32))
	m.surface:SetPoint("TOPRIGHT", -MOCK_PAD, -(MOCK_PAD + 32))
	m.surface:SetHeight(SURFACE_H)
	m.surface.bg = m.surface:CreateTexture(nil, "BACKGROUND")
	m.surface.bg:SetAllPoints()
	m.surface.edges = Edges(m.surface, "BORDER", 0)
	m.heading = UI.Text(m.surface, 12, "heading", "label")
	m.heading:SetPoint("TOPLEFT", 8, -7)
	m.count = UI.Text(m.surface, 12, "accent", "number")
	m.count:SetPoint("TOPRIGHT", -8, -7)
	m.count:SetJustifyH("RIGHT")
	m.line = UI.Text(m.surface, 12, "text")
	m.line:SetPoint("TOPLEFT", m.heading, "BOTTOMLEFT", 0, -4)
	m.muted = UI.Text(m.surface, 11, "textMuted")
	m.muted:SetPoint("TOPLEFT", m.line, "BOTTOMLEFT", 0, -3)
	m.track = m.surface:CreateTexture(nil, "ARTWORK")
	m.track:SetPoint("BOTTOMLEFT", 8, 7)
	m.track:SetPoint("BOTTOMRIGHT", -8, 7)
	m.track:SetHeight(4)
	m.track:SetColorTexture(0, 0, 0, 0.4)
	m.bar = m.surface:CreateTexture(nil, "ARTWORK", nil, 1)
	m.bar:SetPoint("TOPLEFT", m.track)
	m.bar:SetPoint("BOTTOMLEFT", m.track)
	m.bar:SetWidth((MOCK_W - 2 * MOCK_PAD - 16) * 3 / 8)

	local switchY = -(MOCK_PAD + 32 + SURFACE_H + 12)
	m.switchLabel = UI.Text(c, 12, "text")
	m.switchLabel:SetPoint("TOPLEFT", MOCK_PAD, switchY)
	m.switch = CreateFrame("Frame", nil, c)
	m.switch:SetSize(SWITCH_W, SWITCH_H)
	m.switch:SetPoint("TOPRIGHT", -MOCK_PAD, switchY + 1)
	m.switch.track = m.switch:CreateTexture(nil, "BACKGROUND")
	m.switch.track:SetAllPoints()
	m.switch.track:SetColorTexture(0, 0, 0, 0.3)
	m.switch.fill = m.switch:CreateTexture(nil, "BACKGROUND", nil, 1)
	m.switch.fill:SetPoint("TOPLEFT", 1, -1)
	m.switch.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	m.switch.fill:SetAlpha(0.85)
	m.switch.edges = Edges(m.switch, "BORDER", 0)
	m.switch.knob = m.switch:CreateTexture(nil, "ARTWORK")
	m.switch.knob:SetPoint("TOPRIGHT", -3, -3)
	m.switch.knob:SetPoint("BOTTOMRIGHT", -3, 3)
	m.switch.knob:SetWidth(SWITCH_H - 6)

	m.chips = {}
	for i = 1, 3 do
		local chip = CreateFrame("Frame", nil, c)
		chip:SetHeight(CHIP_H)
		chip.bg = chip:CreateTexture(nil, "BACKGROUND")
		chip.bg:SetAllPoints()
		chip.text = UI.Text(chip, 11, "text", "label")
		chip.text:SetPoint("CENTER")
		if i == 1 then
			chip:SetPoint("TOPLEFT", MOCK_PAD, switchY - 24)
		else
			chip:SetPoint("LEFT", m.chips[i - 1], "RIGHT", 6, 0)
		end
		m.chips[i] = chip
	end
	m.faint = UI.Text(c, 10, "textFaint")
	m.faint:SetPoint("BOTTOMLEFT", MOCK_PAD, MOCK_PAD - 2)
	return m
end

local CHIPS = { { "success", "Ready" }, { "warning", "Soon" }, { "danger", "Missing" } }

-- The theme's font for a role at size (as Theme.Font and Theme.FontSize do for the applied theme).
local function MockFont(fs, def, fonts, role, size)
	local resolved = fonts[role] and role or (role == "label" and fonts.title and "title") or "body"
	local path = fonts[resolved]
	local bump = def.fontBump and def.fontBump[resolved]
	if bump and path:find("^Interface\\AddOns\\") then
		size = size + bump
	end
	if not fs:SetFont(path, size, "") then
		ns.Theme.SetFont(fs, role, size) -- a file the game can't load yet (new media need a restart)
	end
end

local function MockText(fs, def, fonts, role, size, colorRole, text)
	MockFont(fs, def, fonts, role, size)
	local c = def.colors[colorRole]
	fs:SetTextColor(c[1], c[2], c[3], 1)
	fs:SetText(text)
end

local function ThemePreview(host, get)
	local name = ns.ChoiceOrDefault(get("theme"), ns.Theme.Choices(), ns.Theme.DEFAULT)
	local def = ns.Theme.Get(name)
	if not def then
		return nil
	end
	host.mock = host.mock or BuildMock(host)
	local m, colors = host.mock, def.colors
	local fonts = def.fonts(GetLocale())
	local art = def.art or {}

	local blizzard = def.panel == "blizzard"
	m.nine:SetShown(blizzard)
	m.art:SetShown(not blizzard)
	if blizzard then
		m.nine.Center:SetVertexColor(colors.bgTop[1], colors.bgTop[2], colors.bgTop[3], 1)
		for _, key in ipairs(NINE_SLICE_PIECES) do
			m.nine[key]:SetVertexColor(1, 1, 1, 1) -- the border art as it comes, as UI.Panel
		end
	else
		-- Art theme: Background opacity applies unless the theme turns it off (as Panel_ApplyLook).
		local alpha = art.opacity == false and 1 or get("opacity") or 1
		Gradient(m.fill, "VERTICAL", colors.bgBottom, colors.bgTop, alpha)
		local outer = art.outer or 2
		ColorEdges(m.outer, colors.frameDark, outer > 0 and alpha or 0)
		PlaceEdges(m.inner, art.inset or 5)
		ColorEdges(m.inner, colors.frame, art.rule or 0.45)
	end

	MockText(m.title, def, fonts, "title", 16, "heading", "Tomte")
	Fill(m.rule, colors.rule)
	Fill(m.surface.bg, colors.surface)
	ColorEdges(m.surface.edges, colors.frame, SURFACE_RULE)
	MockText(m.heading, def, fonts, "label", 12, "heading", "Great Vault")
	MockText(m.count, def, fonts, "number", 12, "accent", "3/8")
	MockText(m.line, def, fonts, "body", 12, "text", "Two more dungeons for a second slot")
	MockText(m.muted, def, fonts, "body", 11, "textMuted", "Resets in 2 days")
	Gradient(m.bar, "HORIZONTAL", colors.accentDeep, colors.accent)

	MockText(m.switchLabel, def, fonts, "body", 12, "text", "Counts on the rail")
	Gradient(m.switch.fill, "HORIZONTAL", colors.accentDeep, colors.accent)
	ColorEdges(m.switch.edges, colors.frame, 0.6)
	Fill(m.switch.knob, colors.text, 1)

	for i, chip in ipairs(m.chips) do
		local role, text = CHIPS[i][1], CHIPS[i][2]
		MockText(chip.text, def, fonts, "label", 11, role, text)
		Fill(chip.bg, colors[role], CHIP_FILL)
		chip:SetWidth(math.ceil(chip.text:GetUnboundedStringWidth()) + 14)
	end
	MockText(m.faint, def, fonts, "body", 10, "textFaint", "Updated 2 min ago")
	return MOCK_W, MOCK_H
end

local module

-- "Around you shows": one switch per "around" block of every module (on or off), added on ADDON_LOADED (init), when
-- every module has registered; Setup and sharing after them. A block never touched starts ticked.
local function AddRows(db)
	if module.rowsAdded then
		return
	end
	module.rowsAdded = true
	for _, choice in ipairs(ns.Home_AroundChoices()) do
		module.defaults.around[choice.key] = true -- what Reset puts back
		if db.around[choice.key] == nil then
			db.around[choice.key] = true
		end
		module.options[#module.options + 1] = { type = "checkbox", key = "around." .. choice.key, label = choice.name,
			onChange = Redraw, tooltip = "This block in Home's \"Around you\" column (it still needs its module on)." }
	end
	for _, spec in ipairs(SHARE) do
		module.options[#module.options + 1] = spec
	end
end

module = ns.RegisterModule({
	key = "window",
	name = "Tomte window",
	category = "tomte",
	icon = 134063, -- inv_misc_gear_01
	summary = "Pick a theme and choose what the rail and Home show.",
	description = "How this window looks, where it opens, and what the rail and Home show.",
	alwaysOn = true,
	toasts = "Tomte errors", -- the bug toast (Panel/Bug.lua)
	init = AddRows,
	defaults = {
		theme = ns.Theme.DEFAULT, -- read by Core.lua on ADDON_LOADED, before anything draws
		opacity = 0.96,
		resume = 5,
		pills = true, -- counts on the rail
		whatsNew = true, -- after an update, the first login shows what's new (Panel/Changes.lua)
		bugToast = true, -- a toast when one of Tomte's Lua errors happens (Panel/Bug.lua)
		motion = "full", -- "full" | "subtle" | "off": how much Tomte animates (Panel/Motion.lua)
		sounds = "all", -- "all" | "important" | "off": which interface sounds play (UI.Sound)
		around = {}, -- [home entry key] = false hides that "Around you" block (one true per block, set in AddRows)
	},
	options = {
		{ type = "header", label = "Look" },
		{ type = "dropdown", key = "theme", label = "Theme", onChange = Redraw, choices = ns.Theme.Choices,
			preview = ThemePreview, previewInList = true, tooltip = "How every Tomte window, widget and toast looks. Takes effect after a reload." },
		{ type = "button", label = "The new theme shows after a reload", text = "Reload now",
			shown = function()
				return ns.ChoiceOrDefault(ns.db.window.theme, ns.Theme.Choices(), ns.Theme.DEFAULT) ~= ns.Theme.name
			end,
			onClick = function()
				if InCombatLockdown() then
					ns.Print_Combat("reload to switch themes")
					return
				end
				C_UI.Reload() -- needs a hardware event: this click is one
			end,
			tooltip = "Reloads your UI so Tomte draws with the theme picked above." },
		{ type = "header", label = "Window" },
		{ type = "slider", key = "opacity", label = "Background opacity", min = 0.5, max = 1, step = 0.02,
			shown = function()
				return ns.Theme.panel == "art" and ns.Theme.art.opacity -- Blizzard default always looks like a tooltip
			end,
			format = function(value)
				return ("%d%%"):format(math.floor(value * 100 + 0.5))
			end,
			onChange = function()
				ns.Panel_ApplyLook()
			end,
			tooltip = "Lower lets the game show through the window; 100% is solid." },
		{ type = "slider", key = "resume", label = "Reopen where I left off for", min = 0, max = 30, step = 1,
			format = function(value)
				return value == 0 and "never" or ("%d min"):format(value)
			end,
			tooltip = "Opening Tomte within this long after closing it goes back to the page you were on. After that, "
				.. "or at 0, it opens on Home." },
		{ type = "checkbox", key = "pills", label = "Counts on the rail", onChange = Redraw,
			tooltip = "A small count beside a page in the list on the left when it has something for you: crafting "
				.. "list steps for this character (Alts), vault rewards and full Concentration (Weekly board)." },
		{ type = "checkbox", key = "whatsNew", label = "What's new after an update",
			tooltip = "The first time you log in after updating Tomte, a small window says what's new and what's "
				.. "fixed. /tomte changes shows it any time." },
		{ type = "button", label = "This version's changes", text = "Show", onClick = function()
			ns.ChangesUI_Show()
		end, tooltip = "The window with what's new in this Tomte version." },
		{ type = "header", label = "Motion and sound" },
		{ type = "dropdown", key = "motion", label = "Motion", choices = MotionChoices,
			tooltip = "Full: windows fade, lists glide, finished things sparkle. Subtle: only soft fades and glides. "
				.. "Off: everything shows at once." },
		{ type = "dropdown", key = "sounds", label = "Sounds", choices = SoundChoices,
			tooltip = "All: soft clicks for opening, moving around and switches. Only important: just confirmations, "
				.. "errors and rewards. Off: Tomte's windows stay silent (alerts like whispers keep their own sound "
				.. "settings)." },
		{ type = "header", label = "Around you shows" },
	},
})

-- Whether what's new shows after an update, and the window's "Don't show this after updates" (Panel/Changes.lua).
function ns.Window_WhatsNew()
	return not (module.db and module.db.whatsNew == false)
end

-- Whether Tomte's Lua errors get a toast (Panel/Bug.lua).
function ns.Window_BugToast()
	return not (module.db and module.db.bugToast == false)
end

function ns.Window_SetWhatsNew(on)
	if module.db then
		module.db.whatsNew = on and true or false
	end
end

function ns.Window_Motion()
	return ns.ChoiceOrDefault(module.db and module.db.motion, MotionChoices(), "full")
end

function ns.Window_Sounds()
	return ns.ChoiceOrDefault(module.db and module.db.sounds, SoundChoices(), "all")
end
