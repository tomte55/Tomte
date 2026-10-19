local addonName, ns = ...

-- The readiness checks (Hunter Pets' pet check, Rogue Poisons' poison check): the same guards, chat lines and banner.
-- Each check keeps its own rules and passes what differs.

-- spec: {
--   active = bool (the module is on), verbose = bool (the slash command or options button: also say when all is
--   fine), offMessage = string|nil (printed when verbose and the module is off), name = "pet check" (chat prefix),
--   find = fn() -> lines, icon (called out of combat only; lines are the problems as text, icon the banner's),
--   banner = bool (banner and sound wanted), bannerOnVerbose = bool, owner, label, accent (the banner's) }
function ns.Check_Report(spec)
	if not spec.active then
		if spec.verbose and spec.offMessage then
			ns.Print(spec.offMessage)
		end
		return
	end
	if InCombatLockdown() then
		if spec.verbose then
			ns.Print_Combat("run the " .. spec.name)
		end
		return
	end
	if UnitIsDeadOrGhost("player") then
		if spec.verbose then
			ns.Print(("can't run the %s while you're dead."):format(spec.name))
		end
		return
	end
	local lines, icon = spec.find()
	if #lines == 0 then
		if spec.verbose then
			ns.Print(spec.name .. ": all good.")
		end
		return
	end
	for _, line in ipairs(lines) do
		ns.Print(ns.UI.Wrap(line, "warning"))
	end
	if spec.banner and (spec.bannerOnVerbose or not spec.verbose) then
		ns.Banner_Show({
			owner = spec.owner,
			label = spec.label,
			accent = spec.accent,
			title = lines[1],
			subtitle = #lines > 1 and table.concat(lines, "   -   ", 2) or nil,
			icon = icon,
			hold = 5,
		})
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

-- After zoning into a dungeon, raid or delve: fn() runs delay seconds later, once pets and auras are back.
function ns.Check_OnEnterWorld(delay, fn)
	local _, instanceType, difficultyID = GetInstanceInfo()
	if ns.Check_ContentKind(instanceType, difficultyID) then
		C_Timer.After(delay, fn)
	end
end
