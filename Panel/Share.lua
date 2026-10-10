local addonName, ns = ...

-- Settings profiles, game side: export to a string, import a friend's string with a preview of what changes, and
-- undo the last import. What a setting is and every check on imported data live in Core/Profile.lua (pure).
-- Nothing is sent anywhere: the player copies and pastes the string.

local UI = ns.UI
local ARROW = " -> "

-- C_EncodingUtil (11.1.5+; warcraft.wiki.gg API_C_EncodingUtil.*, Blizzard_APIDocumentationGenerated/
-- EncodingUtilDocumentation.lua): CBOR, then raw Deflate, then Base64. The compress and Base64 calls may return
-- nothing on bad input; Profile_Encode/Decode call these in pcall. CBOR carries only data (no functions).
local codec = {
	encode = function(payload)
		local cbor = C_EncodingUtil.SerializeCBOR(payload)
		local packed = cbor and C_EncodingUtil.CompressString(cbor, Enum.CompressionMethod.Deflate)
		return packed and C_EncodingUtil.EncodeBase64(packed, Enum.Base64Variant.Standard)
	end,
	decode = function(body)
		local packed = C_EncodingUtil.DecodeBase64(body, Enum.Base64Variant.Standard)
		local cbor = packed and C_EncodingUtil.DecompressString(packed, Enum.CompressionMethod.Deflate)
		if not cbor or #cbor > ns.PROFILE_MAX_DATA then
			return nil
		end
		return C_EncodingUtil.DeserializeCBOR(cbor)
	end,
}

-- Your settings as a "Tomte1:..." string, or nil, error.
function ns.ShareUI_ExportText()
	return ns.Profile_Encode(ns.Profile_Collect(ns.db, ns.modules, ns.VERSION), codec)
end

function ns.ShareUI_HasBackup()
	local backup = ns.db and ns.db.profileBackup
	return type(backup) == "table" and type(backup.text) == "string"
end

function ns.ShareUI_Export()
	local text, err = ns.ShareUI_ExportText()
	if not text then
		ns.Print("couldn't build the string: " .. tostring(err))
		return
	end
	ns.Dialog_Show({
		title = "Your Tomte settings",
		hint = "Ctrl+C, then paste it to a friend. It has your settings, not your data (no characters, history or "
			.. "lists).",
		text = text,
		readOnly = true,
		height = 220,
	})
end

-- Preview ------------------------------------------------------------------------------------------------------

local preview

local function UpdateImportButton()
	local any = false
	for _, on in pairs(preview.chosen) do
		any = any or on
	end
	preview.import:SetEnabled(any)
	preview.import:SetAlpha(any and 1 or 0.4)
end

local function Apply()
	if InCombatLockdown() then
		ns.Print("Import after combat.")
		return
	end
	if not preview.undo then
		local text = ns.ShareUI_ExportText()
		if not text then
			ns.Print("couldn't save a backup of your settings first, so nothing was imported.")
			return
		end
		ns.db.profileBackup = { at = time(), text = text }
	end
	ns.Profile_Apply(ns.db, preview.result, preview.chosen)
	C_UI.Reload() -- needs a hardware event: this click is one. Modules and the theme read settings on load.
end

local function BuildPreview()
	preview = CreateFrame("Frame", "TomteImportPreview", UIParent)
	preview:SetSize(520, 460)
	preview:SetPoint("CENTER")
	preview:SetFrameStrata("DIALOG")
	preview:SetToplevel(true)
	preview:EnableMouse(true)
	preview:SetMovable(true)
	preview:SetClampedToScreen(true)
	preview:RegisterForDrag("LeftButton")
	preview:SetScript("OnDragStart", preview.StartMoving)
	preview:SetScript("OnDragStop", preview.StopMovingOrSizing)
	preview:Hide()
	UI.Panel(preview)
	tinsert(UISpecialFrames, "TomteImportPreview") -- Escape closes it

	preview.title = UI.Text(preview, 14, "heading", "title")
	preview.title:SetPoint("TOPLEFT", 14, -12)
	preview.summary = UI.Text(preview, 11, "textMuted")
	preview.summary:SetPoint("TOPLEFT", preview.title, "BOTTOMLEFT", 0, -4)
	preview.summary:SetPoint("RIGHT", -14, 0)
	preview.summary:SetJustifyH("LEFT")

	local box = CreateFrame("Frame", nil, preview)
	box:SetPoint("TOPLEFT", preview.summary, "BOTTOMLEFT", 0, -8)
	box:SetPoint("BOTTOMRIGHT", -14, 40)
	UI.Surface(box)
	preview.scroll = UI.Scroll(box)
	preview.scroll:SetPoint("TOPLEFT", 8, -6)
	preview.scroll:SetPoint("BOTTOMRIGHT", -12, 6)
	preview.headers, preview.lines = {}, {}

	preview.cancel = UI.Button(preview, 80, "Cancel")
	preview.cancel:SetPoint("BOTTOMRIGHT", -14, 10)
	preview.cancel:SetScript("OnClick", function()
		preview:Hide()
	end)
	preview.import = UI.Button(preview, 130, "Import and reload")
	preview.import:SetPoint("RIGHT", preview.cancel, "LEFT", -8, 0)
	preview.import:SetScript("OnClick", Apply)
end

local function Header(i)
	local h = preview.headers[i]
	if not h then
		h = CreateFrame("Frame", nil, preview.scroll.content)
		h:SetHeight(22)
		h.check = UI.Checkbox(h)
		h.check:SetPoint("LEFT", 2, 0)
		h.check.onChange = function(on)
			preview.chosen[h.key] = on
			UpdateImportButton()
		end
		h.text = UI.Text(h, 12, "heading", "label")
		h.text:SetPoint("LEFT", h.check, "RIGHT", 8, 0)
		h.text:SetPoint("RIGHT", -4, 0)
		h.text:SetJustifyH("LEFT")
		h.text:SetWordWrap(false)
		preview.headers[i] = h
	end
	return h
end

local function Line(i)
	local fs = preview.lines[i]
	if not fs then
		fs = UI.Text(preview.scroll.content, 11, "text")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		preview.lines[i] = fs
	end
	return fs
end

local function ShowPreview(result, title, undo)
	if not preview then
		BuildPreview()
	end
	preview.result, preview.undo = result, undo
	preview.chosen = {}
	preview.title:SetText(title)
	preview.summary:SetText(("%d %s in %d %s. %d %s skipped (this Tomte doesn't have them, or their values "
		.. "didn't fit)."):format(result.changes, result.changes == 1 and "change" or "changes", #result.groups,
		#result.groups == 1 and "group" or "groups", result.skipped, result.skipped == 1 and "setting" or "settings"))

	for _, h in ipairs(preview.headers) do
		h:Hide()
	end
	for _, fs in ipairs(preview.lines) do
		fs:Hide()
	end
	local content = preview.scroll.content
	local y, lineIndex = 0, 0
	for i, group in ipairs(result.groups) do
		local h = Header(i)
		h.key = group.key
		preview.chosen[group.key] = true
		h.check:SetChecked(true)
		h.text:SetText(("%s (%d)"):format(group.name, #group.rows))
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		h:SetPoint("RIGHT", content, "RIGHT")
		h:Show()
		y = y + 24
		for _, row in ipairs(group.rows) do
			lineIndex = lineIndex + 1
			local fs = Line(lineIndex)
			fs:SetText(("%s: %s%s%s"):format(row.label, ns.Theme.Wrap(ns.Profile_ValueText(row.old), "textMuted"),
				ARROW, ns.Profile_ValueText(row.new)))
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", 26, -y)
			fs:SetPoint("RIGHT", content, "RIGHT", -4, 0)
			fs:Show()
			y = y + 16
		end
		y = y + 6
	end
	preview.scroll:SetContentHeight(y)
	preview.scroll:SetScroll(0)
	UpdateImportButton()
	preview:Show()
end

-- Import -------------------------------------------------------------------------------------------------------

-- Decode and check text; nil, error when it can't be imported or nothing would change.
local function Check(text)
	local payload, err = ns.Profile_Decode(text, codec)
	if not payload then
		return nil, err
	end
	local result
	result, err = ns.Profile_Check(payload, ns.modules, ns.db)
	if not result then
		return nil, err
	end
	if result.changes == 0 then
		return nil, "Your settings already match."
	end
	return result
end

function ns.ShareUI_Import()
	if InCombatLockdown() then
		ns.Print("Import after combat.")
		return
	end
	ns.Dialog_Show({
		title = "Import Tomte settings",
		hint = "Paste a string from /tomte profile export (Ctrl+V). Nothing changes until you confirm.",
		text = "",
		saveText = "Check",
		height = 240,
		onSave = function(text)
			local result, err = Check(text)
			if not result then
				return err
			end
			ShowPreview(result, "What changes", false)
			return nil
		end,
	})
end

function ns.ShareUI_Undo()
	if InCombatLockdown() then
		ns.Print("Undo after combat.")
		return
	end
	if not ns.ShareUI_HasBackup() then
		ns.Print("nothing to undo.")
		return
	end
	local backup = ns.db.profileBackup
	local result, err = Check(backup.text)
	if not result then
		ns.Print("undo: " .. err)
		return
	end
	local when = type(backup.at) == "number" and date("%Y-%m-%d %H:%M", backup.at) or "?"
	ShowPreview(result, ("Undo last import (from %s)"):format(when), true)
end

-- Hidden /tomte profile selftest: every schema builds, and your own settings survive a real round trip.
function ns.ShareUI_SelfTest()
	for _, module in ipairs(ns.modules) do
		local ok, err = pcall(ns.Profile_Schema, module)
		if not ok then
			ns.Print("profile selftest failed: schema of " .. module.key .. ": " .. tostring(err))
			return
		end
	end
	local payload = ns.Profile_Collect(ns.db, ns.modules, ns.VERSION)
	local n = 0
	for _ in pairs(payload.enabled) do
		n = n + 1
	end
	for _, values in pairs(payload.settings) do
		for _ in pairs(values) do
			n = n + 1
		end
	end
	local text, err = ns.Profile_Encode(payload, codec)
	if not text then
		ns.Print("profile selftest failed: encode: " .. tostring(err))
		return
	end
	local decoded
	decoded, err = ns.Profile_Decode(text, codec)
	if not decoded then
		ns.Print("profile selftest failed: decode: " .. tostring(err))
		return
	end
	local result
	result, err = ns.Profile_Check(decoded, ns.modules, ns.db)
	if not result then
		ns.Print("profile selftest failed: check: " .. tostring(err))
		return
	end
	if result.changes ~= 0 then
		local first = result.groups[1].rows[1]
		ns.Print(("profile selftest failed: %d changes against yourself (first: %s %s)"):format(result.changes,
			result.groups[1].key, first.path))
		return
	end
	-- Skipped here: a saved dropdown value that isn't a choice right now (a toy you no longer own, say).
	ns.Print(("profile selftest ok: %d settings, %d characters, 0 changes, %d skipped."):format(n, #text,
		result.skipped))
end
