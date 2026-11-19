local addonName, ns = ...

-- Tomte map: the window fades while you move and the mouse isn't on it, as the game's map does (its mapFade setting),
-- so you see where you're going. Eased each frame from the view's OnUpdate (Window.lua), which only runs while the
-- window shows; settings in Map.lua.
-- A window's alpha reaches every layer on its own: at half alpha the window's background, its well, the sea colour and
-- each level of map art all showed through each other, muddy and hardly see-through (seen 2026-11-19). So the frame
-- (background, border, title) fades out entirely, and the map, its pins and the side panel keep the faded alpha
-- themselves (they ignore the frame's), with the art under the top level faded out too (Art.lua, MapArt_SetCover).
-- Each zone is one merged picture where Tomte_MapArt has it (tools/mapart.py), so a faded zone shows through evenly.

local FADE_SPEED = 4 -- alpha per second toward the target: a quarter second from faded to solid

local db
local parts = {} -- the frames that keep the faded alpha: the view, the pin layer, the side panel
local alpha = 1 -- the map's alpha now (1: solid)
local apart = false -- parts ignore the frame's alpha (only while faded at all)

function ns.MapFade_Init(moduleDB)
	db = moduleDB
end

local window

-- Window.lua, once built.
function ns.MapFade_Parts(frame, list)
	window, parts = frame, list
end

local function Moving()
	local speed = GetUnitSpeed("player")
	return speed ~= nil and not ns.IsSecret(speed) and speed > 0
end

local function Apply(frame)
	local depth = 1 - db.fadeAlpha
	local cover = depth > 0 and math.min(1, math.max(0, (1 - alpha) / depth)) or 0
	local split = alpha < 1
	if split ~= apart then
		apart = split
		for _, part in ipairs(parts) do
			part:SetIgnoreParentAlpha(split)
		end
	end
	if frame:GetAlpha() ~= 1 - cover then
		frame:SetAlpha(1 - cover)
	end
	ns.MapArt_SetCover(cover, split)
	for i, part in ipairs(parts) do
		local a = split and alpha or 1
		if i == 1 and split then
			-- The view holds several pictures on top of each other (Art.lua, MapArt_Layers), each at the view's alpha:
			-- n of them at a let 1 - (1 - a)^n through, so a is set for the stack to come out at the faded alpha.
			-- At 50% two of them each at 50% hid three quarters of the world behind (measured 2026-11-19).
			a = 1 - (1 - alpha) ^ (1 / ns.MapArt_Layers())
		end
		if math.abs(part:GetAlpha() - a) > 0.001 then
			part:SetAlpha(a)
		end
	end
	-- The quest area sits in the view but is one picture over the map: the plain faded alpha, as the pins have (inside
	-- the view's lower alpha it all but vanished, seen 2026-11-19). Made on first need, so looked up each time.
	local area = ns.MapArea_Frame()
	if area then
		if area.fadeApart ~= split then
			area.fadeApart = split
			area:SetIgnoreParentAlpha(split)
		end
		local a = split and alpha or 1
		if math.abs(area:GetAlpha() - a) > 0.001 then
			area:SetAlpha(a)
		end
	end
end

-- Each frame while the window shows: the map eased toward faded (moving, mouse off the window) or solid.
function ns.MapFade_Update(frame, elapsed)
	local want = 1
	if db.fadeMoving and Moving() and not frame:IsMouseOver() then
		want = db.fadeAlpha
	end
	if alpha ~= want then
		local step = FADE_SPEED * elapsed
		alpha = alpha < want and math.min(want, alpha + step) or math.max(want, alpha - step)
		Apply(frame)
	elseif apart then
		Apply(frame) -- faded: a zoom can bring in or take away a level of pictures (cheap when nothing changed)
	end
end

-- "/tomte map fade": three seconds on (time to start walking), each faded part's own and effective alpha.
function ns.MapFade_Why()
	local frame = window
	if not frame then
		ns.Print("map fade: open the map once first.")
		return
	end
	ns.Print("map fade: walk with the mouse off the map; measuring in 3 seconds.")
	C_Timer.After(3, function()
		local function Line(name, f)
			if f then
				print(("  %s: alpha %.2f, effective %.2f, ignores parent %s, shown %s"):format(name, f:GetAlpha(),
					f:GetEffectiveAlpha(), tostring(f.IsIgnoringParentAlpha and f:IsIgnoringParentAlpha()),
					tostring(f:IsVisible())))
			end
		end
		print(("  fading: %s, faded to %.2f, map alpha now %.2f, moving %s"):format(tostring(db.fadeMoving),
			db.fadeAlpha, alpha, tostring(Moving())))
		Line("window", frame)
		Line("view", parts[1])
		Line("canvas", parts[1] and parts[1].GetScrollChild and parts[1]:GetScrollChild())
		Line("pins", parts[2])
		Line("side panel", parts[3])
		local art = ns.MapArt_TopFrame()
		Line("top map art", art)
		print(("  pictures stacked: %.2f; every zone in view merged: %s"):format(ns.MapArt_Layers(),
			tostring(ns.MapArt_AllFlat())))
	end)
end

-- The window hid: solid again for next time.
function ns.MapFade_Reset(frame)
	if frame and alpha ~= 1 then
		alpha = 1
		Apply(frame)
	end
end
