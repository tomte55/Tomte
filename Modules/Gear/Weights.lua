local addonName, ns = ...

-- Gear Check, part 5: stat weights. This character's imported weights, the Pawn import dialog, the Raidbots how-to
-- steps, the weights printout, the "Sim on Raidbots" suggestion and the hidden spec check. Contexts are in
-- Context.lua; the commands that call these are registered in Gear.lua.

local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local UI = ns.UI

local function DB()
	return ns.gearDB
end

local PRIMARY_KEYS = ns.GEAR_PRIMARY_KEYS
local Context = ns.Gear_OwnContext
local CurrentSeason = ns.Gear_CurrentSeason
local InvalidateVerdicts = ns.Gear_InvalidateVerdicts
local MaxLevel = ns.GearHints_MaxLevel

local _, classToken = UnitClass("player")

local function CharWeights()
	local guid = UnitGUID("player")
	DB().weights[guid] = DB().weights[guid] or {}
	return DB().weights[guid]
end

local SIM_STEPS = {
	"How to check gear the tooltip can't judge (Raidbots Top Gear, free):",
	"  1. Type /simc and press Ctrl+C to copy the text it shows.",
	"  2. Open raidbots.com/simbot/topgear in a browser and paste it into the big box.",
	"  3. Tick the items you're unsure about (it lists your bags), then press Run Top Gear.",
	"  4. The result at the top is the best set to wear. Equip what it lists.",
}

local WEIGHT_STEPS = {
	"How to get stat weights that fit your gear (Raidbots Stat Weights, free):",
	"  1. Type /simc and press Ctrl+C to copy the text it shows.",
	"  2. Open raidbots.com/simbot/stats in a browser, paste it into the big box and press Run Stat Weights.",
	"  3. In the result, copy the Pawn string and paste it into the import box (/tomte gear import).",
}

local function PrintSteps(steps)
	for _, line in ipairs(steps) do
		print(line)
	end
	if not (C_AddOns.IsAddOnLoaded("Simulationcraft")) then
		print("  (/simc needs the SimulationCraft addon, which isn't loaded.)")
	end
end

local function PrintSimSteps()
	PrintSteps(SIM_STEPS)
end

local function PrintWeights()
	local ctx = Context()
	if not ctx then
		ns.Print("Gear Check: no specialization yet.")
		return
	end
	if ctx.source == "none" then
		ns.Print(("Gear Check (%s): no stat weights. Main stat 1.0, secondary stats 0.5, so higher item level "
			.. "wins. Sim stat weights on Raidbots and /tomte gear import."):format(ctx.spec.name))
	else
		local parts = {}
		for key, value in pairs(ctx.weights) do
			parts[#parts + 1] = ("%s %.2f"):format(key, value)
		end
		table.sort(parts)
		ns.Print(("Gear Check (%s): %s - %s"):format(ctx.spec.name, ns.Gear_SourceText(ctx.source, ctx.label),
			table.concat(parts, ", ")))
	end
	if ctx.best then
		print(("  Best gem: %s (%s)"):format(ctx.best.name, ns.Gear_StatLabel(ctx.best.stats)))
	end
	print(("  Built-in set: %s. Season ID: %s."):format(ns.Gear_ScalesName(ctx.scales, ns.ContentExpansion()),
		tostring(CurrentSeason())))
end

-- Panel row label: where the current spec's weights come from.
local function SourceLabel()
	local ctx = ns.gearModule.active and DB() and Context()
	if not ctx then
		return "Weights in use"
	end
	local source = ctx.source == "imported" and "imported" or ns.Gear_SourceText(ctx.source, ctx.label)
		or "none, item level decides"
	return ("%s: %s"):format(ctx.spec.name, source)
end

local function ClearWeights()
	local ctx = Context()
	if ctx then
		CharWeights()[ctx.spec.id] = nil
		ns.GearAlts_Invalidate()
		local after = ctx.scales.specs[ctx.spec.id] and "the built-in weights" or "item level"
		ns.Print(("Gear Check: imported weights for %s cleared, back to %s."):format(ctx.spec.name, after))
		InvalidateVerdicts()
		ns.GearSheet_Refresh()
	end
end

local dialog

local function Import(text)
	local ctx = Context()
	if not ctx then
		return "No specialization yet."
	end
	local parsed, err = ns.Gear_ParsePawn(strtrim(text or ""))
	if not parsed then
		return err
	end
	if parsed.class ~= classToken or parsed.spec ~= ctx.spec.index then
		return ("That string is for another class or spec. You're %s right now."):format(ctx.spec.name)
	end
	CharWeights()[ctx.spec.id] = { name = parsed.name, weights = parsed.weights }
	ns.GearAlts_Invalidate()
	ns.Print(("Gear Check: imported \"%s\" for %s."):format(parsed.name, ctx.spec.name))
	InvalidateVerdicts()
	ns.GearSheet_Refresh()
	return nil
end

local function BuildDialog()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(480, 230)
	f:SetPoint("CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	UI.Panel(f)

	f.title = UI.Text(f, 15, "heading", "title")
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.help = UI.Text(f, 12, "textMuted")
	f.help:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.help:SetPoint("RIGHT", -16, 0)
	f.help:SetJustifyH("LEFT")
	f.help:SetWordWrap(true)
	f.help:SetText("Optional. On raidbots.com choose Stat Weights, paste your /simc text, run it, then copy the "
		.. "Pawn string from the result and paste it here.")

	local box = CreateFrame("EditBox", nil, f)
	box:SetMultiLine(true)
	box:SetAutoFocus(true)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(6, 6, 6, 6)
	box:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", 0, -10)
	box:SetPoint("RIGHT", -16, 0)
	box:SetHeight(80)
	UI.Surface(box, 0.35)
	box:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	f.box = box

	f.error = UI.Text(f, 12, "danger")
	f.error:SetPoint("BOTTOMLEFT", 16, 18)
	f.error:SetPoint("RIGHT", -200, 0)
	f.error:SetJustifyH("LEFT")
	f.error:SetWordWrap(true)

	local cancel = UI.Button(f, 80, "Cancel")
	cancel:SetPoint("BOTTOMRIGHT", -16, 12)
	cancel:SetScript("OnClick", function()
		f:Hide()
	end)
	local ok = UI.Button(f, 80, "Import")
	ok:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
	ok:SetScript("OnClick", function()
		local err = Import(box:GetText())
		if err then
			f.error:SetText(err)
		else
			f:Hide()
		end
	end)
	f:Hide()
	return f
end

local function OpenImport()
	local ctx = Context()
	if not ctx then
		ns.Print("Gear Check: no specialization yet.")
		return
	end
	dialog = dialog or BuildDialog()
	dialog.title:SetText("Import stat weights for " .. ctx.spec.name)
	dialog.box:SetText("")
	dialog.error:SetText("")
	dialog:Show()
end

-- Next up "Sim on Raidbots": this character, built-in weights, max level. Not now hides it like any other source.
local function NextSim()
	local ctx = Context()
	if not (ctx and ns.Gear_SimSuggested(ctx.source, UnitLevel("player"), MaxLevel())) then
		return {}
	end
	return { {
		key = "gearsim:" .. ctx.spec.id,
		text = ("Sim %s on Raidbots"):format(ctx.spec.name),
		why = "Built-in weights are a guide; your own sim fits your gear",
		icon = ctx.spec.icon,
		hint = "Click: how to sim, and the import box",
		onClick = function()
			PrintSteps(WEIGHT_STEPS)
			OpenImport()
		end,
	} }
end

-- Hidden (/tomte gear specs): every class's specs as the game reports them, against the built-in set of this
-- character's content expansion. Lines marked "check" are a missing spec or a different main stat.
local function PrintSpecs()
	local seen, bad = {}, 0
	local scales = ns.Gear_ScalesForLevel()
	ns.Print(("Gear Check specs (ID, name, role, main stat) against the built-in set %s:"):format(
		ns.Gear_ScalesName(scales, ns.ContentExpansion())))
	for cid = 1, GetNumClasses() do
		local info = C_CreatureInfo.GetClassInfo(cid)
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(cid) or 0 do
			local specID, name, _, _, role, primaryStat = GetSpecializationInfo(i, false, false, nil, nil, nil, cid)
			if specID and specID ~= 0 then
				seen[specID] = true
				local main = PRIMARY_KEYS[primaryStat]
				local scale = scales.specs[specID]
				local problem = not scale and "no built-in weights"
					or (main and not scale.weights[main]) and "built-in has another main stat" or nil
				bad = bad + (problem and 1 or 0)
				print(("  |c%s%d %s %s, %s, %s%s|r"):format(UI.Hex(problem and "warning" or "textMuted"), specID,
					name or "?", info and info.className or cid, tostring(role), tostring(main),
					problem and (": check, " .. problem) or ""))
			end
		end
	end
	for specID in pairs(scales.specs) do
		if not seen[specID] then
			bad = bad + 1
			print("  " .. UI.Wrap(("%d is in the built-in set but the game has no such spec: check"):format(specID), "warning"))
		end
	end
	ns.Print(bad == 0 and "every spec matches the built-in set." or (bad .. " to check."))
end

-- Hides the import box when Gear Check is switched off.
local function HideDialog()
	if dialog then
		dialog:Hide()
	end
end

ns.Gear_OpenImport = OpenImport
ns.Gear_ClearWeights = ClearWeights
ns.Gear_PrintSimSteps = PrintSimSteps
ns.GearWeights_Print = PrintWeights
ns.GearWeights_SourceLabel = SourceLabel
ns.GearWeights_NextSim = NextSim
ns.GearWeights_PrintSpecs = PrintSpecs
ns.GearWeights_HideDialog = HideDialog
