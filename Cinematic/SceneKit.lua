local addonName, ns = ...

-- Small drawing helpers shared by the cinematic scenes (flight, AFK): text, gold divider lines and a
-- fade-out/swap/fade-in group used for rotating stat pages.

local SWAP_FADE = 0.3 -- cross-fade half time

ns.SCENE_GOLD = { 1, 0.82, 0.45 }
ns.SCENE_GREY = { 0.62, 0.62, 0.62 }
ns.SCENE_WHITE = { 0.92, 0.92, 0.92 }
ns.SCENE_TITLE_FONT = "Fonts\\MORPHEUS.TTF"

function ns.SceneText(parent, size, color, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(font or STANDARD_TEXT_FONT, size, "")
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowOffset(1, -1)
	return fs
end

-- Only on change: SetText re-lays out the card even with the same text.
function ns.SceneSetText(fs, text)
	text = text or ""
	if (fs:GetText() or "") ~= text then
		fs:SetText(text)
	end
end

-- Pixel-exact placement. Text and hairlines on fractional pixels round differently each time the card is
-- laid out again (1px flicker), so the card is placed from band edges/centers (whole pixels, see the
-- engine) with snapped offsets. Font strings anchor by a top edge: their height is fractional.
-- ScenePlace sets the point right away; SceneSnap re-snaps all of them once the card's scale is final.
function ns.ScenePlace(card, region, point, relativeTo, relativePoint, x, y)
	card.places = card.places or {}
	card.places[#card.places + 1] = { region, point, relativeTo, relativePoint, x, y }
	region:SetPoint(point, relativeTo, relativePoint, x, y)
end

function ns.SceneSnap(card)
	for _, p in ipairs(card.places or {}) do
		local region = p[1]
		region:ClearAllPoints()
		PixelUtil.SetPoint(region, p[2], p[3], p[4], p[5], p[6])
		if region.pixelHeight then
			PixelUtil.SetHeight(region, region.pixelHeight, region.pixelHeight)
			if region.pair then
				PixelUtil.SetHeight(region.pair, region.pixelHeight, region.pixelHeight)
			end
		end
	end
end

-- "Now flying to" -> "N O W   F L Y I N G   T O"
function ns.Spaced(text)
	return (text:upper():gsub(".", "%0 "):sub(1, -2))
end

-- A 1px gold line that fades out to both ends. Returns the left half; anchor that.
function ns.SceneGoldLine(parent, width, alpha)
	local gold = ns.SCENE_GOLD
	local half = width / 2
	local left = parent:CreateTexture(nil, "OVERLAY")
	left:SetColorTexture(1, 1, 1, 1)
	left:SetSize(half, 1)
	left:SetGradient("HORIZONTAL", CreateColor(gold[1], gold[2], gold[3], 0), CreateColor(gold[1], gold[2], gold[3], alpha or 0.8))
	local right = parent:CreateTexture(nil, "OVERLAY")
	right:SetColorTexture(1, 1, 1, 1)
	right:SetSize(half, 1)
	right:SetGradient("HORIZONTAL", CreateColor(gold[1], gold[2], gold[3], alpha or 0.8), CreateColor(gold[1], gold[2], gold[3], 0))
	right:SetPoint("LEFT", left, "RIGHT")
	left.pixelHeight, left.pair = 1, right
	return left
end

-- Fade a group out, run swap.fn(), fade it back in.
function ns.NewSwap(group)
	return { group = group }
end

function ns.StartSwap(swap, fn)
	if not (swap.t and swap.fn) then
		-- Not already fading out: start the fade-out from the group's current alpha (no pop).
		swap.t = SWAP_FADE * (1 - swap.group:GetAlpha())
	end
	swap.fn = fn
end

function ns.ResetSwap(swap)
	swap.t, swap.fn = nil, nil
	swap.group:SetAlpha(1)
end

function ns.UpdateSwap(swap, elapsed)
	if not swap.t then
		return
	end
	swap.t = swap.t + elapsed
	if swap.t < SWAP_FADE then
		swap.group:SetAlpha(1 - swap.t / SWAP_FADE)
		return
	end
	if swap.fn then
		swap.fn()
		swap.fn = nil
	end
	local a = (swap.t - SWAP_FADE) / SWAP_FADE
	if a >= 1 then
		swap.group:SetAlpha(1)
		swap.t = nil
	else
		swap.group:SetAlpha(a)
	end
end
