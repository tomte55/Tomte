local addonName, ns = ...

-- Almost Done: an achievement's tooltip beside a dock row, with what its reward is to you, the metas it is part
-- of and the row's clicks. Used by Dock.lua.

local UI = ns.UI
local TOOLTIP_GAP = 18 -- from a row's right edge to the tooltip: past the scroll thumb and the dock's edge

local function AddExtraLines(record)
	local info = ns.Ach_RewardInfo(record)
	if info then
		local kind = ns.ACH_REWARD_NAMES[info.type] or "Reward"
		if info.owned then
			GameTooltip:AddLine(kind .. " already owned", UI.RGB("textMuted"))
		elseif info.type ~= "other" then
			GameTooltip:AddLine("New " .. kind:lower(), UI.RGB("success"))
		end
	end
	local parents = ns.Ach_ParentsOf(record.id)
	for i = 1, math.min(#parents, 2) do
		local _, name = GetAchievementInfo(parents[i])
		if name then
			GameTooltip:AddLine("Part of: " .. name, UI.RGB("heading"))
		end
	end
	GameTooltip:AddLine("Click: open  -  Shift-click: link in chat  -  Right-click: pin, ignore", UI.RGB("textMuted"))
end

local function ShowAchievementTooltip(owner, id, record)
	local link = GetAchievementLink(id)
	if not link then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	if ns.FOREVER then -- the dock ends near the screen's edge there: over the Legacy window, not off the screen
		GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -TOOLTIP_GAP, 0)
	else
		GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", TOOLTIP_GAP, 0)
	end
	GameTooltip:SetHyperlink(link)
	if record then
		AddExtraLines(record)
	end
	GameTooltip:Show()
end

-- For Dock.lua.
ns.AchTooltip_Show = ShowAchievementTooltip
