local addonName, ns = ...

-- Games: sounds and small effects shared by the games (Table.lua, PokerMachine.lua, SlotMachine.lua): text that pops
-- in, floating numbers that rise and fade, a shake, a glow that flashes and settles, a number that rolls to its new
-- value, and eased tweens (the slot reels). Animation groups, plus one OnUpdate for tweens that runs only while one is
-- moving. A tween's step must not start another tween (the driver is walking the list): defer that with C_Timer.

local FLOAT_RISE = 34 -- pixels a floating number rises
local FLOAT_TIME = 1.3 -- seconds it takes
local FLOAT_FADE_AFTER = 0.7 -- seconds before it starts to fade
local SHAKE = 5 -- pixels each way
local SHAKE_STEP = 0.045 -- seconds per swing

local UI = ns.UI

-- Sound names -> SOUNDKIT keys (Blizzard_SharedXML/Mainline/SoundKitConstants.lua, all in 12.1.5). Read at play
-- time, and a key missing on some client is skipped.
local SOUNDS = {
	deal = "IG_ABILITY_PAGE_TURN",
	flip = "UI_TRANSMOG_PAGE_TURN",
	chip = "IG_BACKPACK_COIN_SELECT",
	clear = "IG_BACKPACK_COIN_CANCEL",
	push = "IG_BACKPACK_COIN_OK",
	win = "LOOT_WINDOW_COIN_SOUND",
	bigWin = "TRADING_POST_UI_COLLECTING_COINS",
	blackjack = "TRADING_POST_UI_REWARD_TIER_COMPLETE",
	lose = "UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_FAIL",
	refill = "TRADING_POST_UI_COLLECTING_COINS",
	open = "IG_SPELLBOOK_OPEN",
	close = "IG_SPELLBOOK_CLOSE",
	hold = "IG_MAINMENU_OPTION_CHECKBOX_ON",
	release = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
	spin = "UI_80_AZERITEARMOR_ROTATIONSTARTCLICKS",
	reelStop = "UI_PROFESSION_SPEC_PIP_LOCKIN",
	jackpot = "TRADING_POST_UI_REWARD_TIER_COMPLETE",
	tab = "IG_CHARACTER_INFO_TAB",
}

-- On the Effects channel, so the game's sound effects volume (and its mute) applies.
function ns.GamesFx_Sound(name)
	local id = SOUNDKIT[SOUNDS[name]]
	if id then
		PlaySound(id, "SFX")
	end
end

-- A sideways shake (a busted hand, a dealer bust).
function ns.GamesFx_Shake(region)
	local ag = region.fxShake
	if not ag then
		ag = region:CreateAnimationGroup()
		for i, dx in ipairs({ SHAKE, -2 * SHAKE, 2 * SHAKE, -2 * SHAKE, SHAKE }) do
			local t = ag:CreateAnimation("Translation")
			t:SetOffset(dx, 0)
			t:SetDuration((i == 1 or i == 5) and SHAKE_STEP or SHAKE_STEP * 2)
			t:SetOrder(i)
		end
		region.fxShake = ag
	end
	ag:Stop()
	ag:Play()
end

-- Glow texture: flashes up, then rests at `rest` alpha (0 fades it out).
function ns.GamesFx_Flash(texture, rest)
	local ag = texture.fxFlash
	if not ag then
		ag = texture:CreateAnimationGroup()
		ag:SetToFinalAlpha(true)
		ag.up = ag:CreateAnimation("Alpha")
		ag.up:SetFromAlpha(0)
		ag.up:SetToAlpha(1)
		ag.up:SetDuration(0.2)
		ag.up:SetOrder(1)
		ag.down = ag:CreateAnimation("Alpha")
		ag.down:SetFromAlpha(1)
		ag.down:SetDuration(0.9)
		ag.down:SetSmoothing("IN")
		ag.down:SetOrder(2)
		texture.fxFlash = ag
	end
	ag:Stop()
	ag.down:SetToAlpha(rest)
	texture:Show()
	ag:Play()
end

-- Tweens --------------------------------------------------------------------------------------------------------

-- Values eased over time by one OnUpdate, shown only while something is moving: [key] = { start, seconds, step }.
local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()

local function Ease(t)
	return 1 - (1 - t) * (1 - t)
end

driver:SetScript("OnUpdate", ns.Perf_Wrap(function(self)
	local now = GetTime()
	local finished = {}
	for key, tw in pairs(tweens) do
		local t = math.min((now - tw.start) / tw.seconds, 1)
		tw.step(Ease(t))
		if t >= 1 then
			finished[#finished + 1] = key
		end
	end
	for _, key in ipairs(finished) do
		tweens[key] = nil
	end
	if not next(tweens) then
		self:Hide()
	end
end, "OnUpdate"))

-- step(e) runs every frame with e eased from 0 to 1 over `seconds`, ending on 1. A new tween on the same key
-- replaces the old one.
local function Tween(key, seconds, step)
	tweens[key] = { start = GetTime(), seconds = seconds, step = step }
	driver:Show()
end
ns.GamesFx_Tween = Tween

-- Ends the tween on key now: finish runs its last step (e = 1), otherwise it just stops where it is.
function ns.GamesFx_TweenStop(key, finish)
	local tw = tweens[key]
	tweens[key] = nil
	if tw and finish then
		tw.step(1)
	end
end

-- Grows a font string's text from `from` times `size` down to `size` (in fontRole). Font size, not a scale
-- animation: a scaled font string grows from its anchor side, this stays centered on its justification.
function ns.GamesFx_PopText(fs, fontRole, size, from, seconds)
	fs.fxPopKey = fs.fxPopKey or {}
	Tween(fs.fxPopKey, seconds or 0.25, function(e)
		UI.SetFont(fs, fontRole, size * (from + (1 - from) * e))
	end)
end

-- Rolls fs from one number to another over `seconds`, in `during` color, ending in `role`. format(n) -> text.
function ns.GamesFx_CountTo(fs, from, to, seconds, format, role, during)
	if from == to then
		tweens[fs] = nil
		fs:SetText(format(to))
		UI.SetTextRole(fs, role)
		return
	end
	UI.SetTextRole(fs, during or role)
	Tween(fs, seconds, function(e)
		fs:SetText(format(math.floor(from + (to - from) * e + 0.5)))
		if e >= 1 then
			UI.SetTextRole(fs, role)
		end
	end)
end

-- Floating text ---------------------------------------------------------------------------------------------------

local floats = {}

local function NewFloat(parent)
	local fs = UI.Text(parent, 16, "text", "number")
	fs:SetJustifyH("CENTER")
	local ag = fs:CreateAnimationGroup()
	fs.rise = ag:CreateAnimation("Translation")
	fs.rise:SetDuration(FLOAT_TIME)
	fs.rise:SetSmoothing("OUT")
	local fade = ag:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetStartDelay(FLOAT_FADE_AFTER)
	fade:SetDuration(FLOAT_TIME - FLOAT_FADE_AFTER)
	ag:SetScript("OnFinished", function()
		fs:Hide()
	end)
	fs.ag = ag
	return fs
end

-- Text that rises from (x, y) off anchor's `point` and fades, in a color role. parent: a frame above whatever it
-- floats over (a window's own regions draw under its child frames). opts: size, rise (pixels, negative drifts down),
-- own (the text's point put on (x, y), default CENTER). anchor must hold still while the text floats: re-laying out
-- the anchor (a rolling count's SetText, a popping text's font size) restarts the rise every frame, so the text sits
-- frozen and jumps when the anchor settles. Anchor to a fixed frame next to such text instead.
function ns.GamesFx_Float(parent, text, role, anchor, point, x, y, opts)
	opts = opts or {}
	local fs
	for _, f in ipairs(floats) do
		if not f:IsShown() and f:GetParent() == parent then
			fs = f
			break
		end
	end
	if not fs then
		fs = NewFloat(parent)
		floats[#floats + 1] = fs
	end
	UI.SetFont(fs, "number", opts.size or 16)
	UI.SetTextRole(fs, role)
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint(opts.own or "CENTER", anchor, point, x or 0, y or 0)
	fs.rise:SetOffset(0, opts.rise or FLOAT_RISE)
	fs:Show()
	fs.ag:Stop()
	fs.ag:Play()
end
