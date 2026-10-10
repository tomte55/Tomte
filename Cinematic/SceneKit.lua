local addonName, ns = ...

-- Small drawing helpers shared by the cinematic scenes (flight, AFK): text, divider lines and a
-- fade-out/swap/fade-in group used for rotating stat pages. Colors and fonts are theme roles (Core/Theme.lua).

local SWAP_FADE = 0.3 -- cross-fade half time

-- role: a color role (default "text") or an { r, g, b } that carries game meaning (class, quality);
-- fontRole: "body" (default) | "title" | "number".
function ns.SceneText(parent, size, role, fontRole)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(fs, fontRole or "body", size)
	if type(role) == "table" then
		fs:SetTextColor(role[1], role[2], role[3])
	else
		fs:SetTextColor(ns.Theme.Color(role or "text"))
	end
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
	return (text:upper():gsub("[%z\1-\127\194-\244][\128-\191]*", "%0 "):sub(1, -2)) -- whole UTF-8 characters
end

-- A 1px line that fades out to both ends (role: default "frame"). Returns the left half; anchor that.
function ns.SceneLine(parent, width, alpha, role)
	local r, g, b = ns.Theme.Color(role or "frame")
	local half = width / 2
	local left = parent:CreateTexture(nil, "OVERLAY")
	left:SetColorTexture(1, 1, 1, 1)
	left:SetSize(half, 1)
	left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, alpha or 0.8))
	local right = parent:CreateTexture(nil, "OVERLAY")
	right:SetColorTexture(1, 1, 1, 1)
	right:SetSize(half, 1)
	right:SetGradient("HORIZONTAL", CreateColor(r, g, b, alpha or 0.8), CreateColor(r, g, b, 0))
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
