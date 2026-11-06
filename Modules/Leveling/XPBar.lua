local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): the XP block on the page and on Home. Your level, a bar that also shows how
-- far your finished quests would take you, and a line that says it in words. Numbers from ns.Leveling_XPView (Data.lua).

local BAR_H = 10
local BAR_Y = -30 -- under the level line
local COMPACT_BAR_Y = -21 -- under the smaller level line on Home
local TEXT_GAP = 7
local RESTED_H = 2 -- a thin line along the bar's foot, so it can overlap the turn-in part and both still read

local UI = ns.UI

-- A part of the bar from one share of its width to another.
local function PlacePart(bar, part, from, to)
	local width = bar:GetWidth() * (to - from)
	part:SetShown(width >= 1)
	if width >= 1 then
		part:ClearAllPoints()
		part:SetPoint(part.anchor, bar, part.anchor, bar:GetWidth() * from, 0)
		part:SetWidth(width)
		if part.barArt then
			bar:SetPartRange(part, from, to)
		end
	end
end

local function PlaceParts(bar)
	local v = bar.view
	if v then
		PlacePart(bar, bar.turnIn, v.fraction, v.turnInEnd)
		PlacePart(bar, bar.rested, v.fraction, v.restedEnd)
	end
end

local function Sentence(state)
	local v = state.xp
	if not v then
		return state.atCap and "You're at the level cap." or ""
	end
	local nextLevel = state.level + 1
	local parts = { ("%s XP to level %d."):format(ns.Thousands(v.toGo), nextLevel) }
	if v.reachesLevel then
		parts[#parts + 1] = UI.Wrap(("Your finished quests reach level %d."):format(nextLevel), "success")
	elseif v.turnIn > 0 then
		parts[#parts + 1] = UI.Wrap(("%s XP in finished quests."):format(ns.Thousands(v.turnIn)), "success")
	end
	if v.rested > 0 then
		parts[#parts + 1] = UI.Wrap(("Rested for %s XP."):format(ns.Thousands(v.rested)), "info")
	end
	return table.concat(parts, " ")
end

-- block:Set(state) (ns.LevelingRead_State) returns its height. The caller gives it a width. compact: under a section
-- heading (Home), so the level is a plain small line rather than a second heading.
function ns.LevelingXP_Create(parent, compact)
	local barY = compact and COMPACT_BAR_Y or BAR_Y
	local block = CreateFrame("Frame", nil, parent)
	if compact then
		block.level = UI.Text(block, 13, "text")
		block.percent = UI.Text(block, 13, "textMuted", "number")
		block.percent:SetPoint("TOPRIGHT")
	else
		block.level = UI.Text(block, 20, "heading", "title")
		block.percent = UI.Text(block, 14, "textMuted", "number")
		block.percent:SetPoint("TOPRIGHT", 0, -6)
	end
	block.level:SetPoint("TOPLEFT")

	local bar = UI.Bar(block, BAR_H)
	bar:SetPoint("TOPLEFT", 0, barY)
	bar:SetPoint("TOPRIGHT", 0, barY)
	bar.turnIn = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	bar.turnIn.anchor = "LEFT"
	bar.turnIn:SetHeight(BAR_H)
	bar.rested = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.rested.anchor = "BOTTOMLEFT"
	bar.rested:SetHeight(RESTED_H)
	bar:HookScript("OnSizeChanged", PlaceParts)
	block.bar = bar

	block.text = UI.Text(block, 12, "textMuted")
	block.text:SetJustifyH("LEFT")
	block.text:SetWordWrap(true)

	function block:Set(state)
		local v = state.xp
		self.level:SetText(("Level %d"):format(state.level))
		self.percent:SetText(v and ("%d%%"):format(v.percent) or "")
		self.bar:SetShown(v ~= nil)
		self.text:ClearAllPoints()
		if v then
			self.text:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -TEXT_GAP)
			self.bar.view = v
			if self.bar.SetPartRole then -- a bar drawn with the game's art (Forever theme) has a green of its own
				self.bar.turnIn.barArt = true
				self.bar:SetPartRole(self.bar.turnIn, "success")
			else
				self.bar.turnIn:SetColorTexture(UI.RGBA("success", 0.75))
			end
			self.bar.rested:SetColorTexture(UI.RGBA("info"))
			self.bar:SetValue(v.fraction)
			PlaceParts(self.bar)
		else
			self.text:SetPoint("TOPLEFT", 0, barY)
		end
		self.text:SetWidth(self:GetWidth()) -- a set width, so the height below is right on the first draw
		self.text:SetText(Sentence(state))
		local top = v and -barY + BAR_H + TEXT_GAP or -barY
		local height = top + self.text:GetStringHeight()
		self:SetHeight(height)
		return height
	end

	return block
end
