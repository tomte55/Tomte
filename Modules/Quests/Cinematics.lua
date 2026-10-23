local addonName, ns = ...

-- Quests: skipping cinematics. Movies (PLAY_MOVIE, with an ID) are remembered once seen, so "skip ones you've
-- seen" lets a new one play; in-engine cutscenes (CINEMATIC_START) have no ID and follow "also skip in-engine
-- cutscenes" under that choice. Quick skip ends a cutscene or movie with one press of Space, Enter or Esc instead
-- of the game's "Are you sure?" (from the frames' own key handlers, so it's a real key press). Policy in Data.lua;
-- started and stopped by Quests.lua.
-- Skipping goes through the same calls as Blizzard's own "Yes" buttons: StopCinematic (when CINEMATIC_START said
-- it can be cancelled) or CancelScene for a cutscene (CinematicFrame_CancelCinematic), MovieFrame:FinishMovie for
-- a movie; both one frame after the event, once Blizzard's frame has shown it. Vehicle cutscenes (neither real
-- nor a scene) are left alone: ending those means leaving the vehicle.

local OWNER = "cinematics"
local QUICK_KEYS = { SPACE = true, ENTER = true, ESCAPE = true }

local events = ns.Quests_Events

local db
local enabled = false
local hooked = false
-- From CINEMATIC_START's payload until CINEMATIC_STOP: running, and whether it's a real (cancellable) cinematic.
local running, cancellable = false, false

-- Ends the running in-engine cutscene, when it can be ended. CancelScene can error on some scenes (warcraft.wiki.gg
-- notes it), which only means this one can't be skipped.
local function StopCutscene()
	if running and cancellable then
		StopCinematic()
		return true
	end
	if IsInCinematicScene() and CanCancelScene() then
		return (pcall(CancelScene))
	end
	return false
end

local function FinishMovie()
	if MovieFrame and MovieFrame:IsShown() and MovieFrame.FinishMovie then
		MovieFrame:FinishMovie()
	end
end

local function OnCinematicStart(canBeCancelled)
	running = true
	cancellable = canBeCancelled == true
	if ns.Quests_SkipCinematic(db.cinematics, "cinematic", nil, nil, db.inEngine) then
		C_Timer.After(0, function() -- once CinematicFrame (which handles the same event) has shown it
			if enabled and running then
				StopCutscene()
			end
		end)
	end
end

local function OnPlayMovie(movieID)
	if ns.IsSecret(movieID) or type(movieID) ~= "number" then
		return
	end
	local skip = ns.Quests_SkipCinematic(db.cinematics, "movie", movieID, db.seenMovies, db.inEngine)
	db.seenMovies[movieID] = true
	if skip then
		C_Timer.After(0, FinishMovie) -- once MovieFrame (which handles the same event) has started it
	end
end

events:On(OWNER, "CINEMATIC_START", function(_, canBeCancelled)
	OnCinematicStart(canBeCancelled)
end)
events:On(OWNER, "CINEMATIC_STOP", function()
	running, cancellable = false, false
end)
events:On(OWNER, "PLAY_MOVIE", function(_, movieID)
	OnPlayMovie(movieID)
end)

-- Quick skip ------------------------------------------------------------------------------------------------------

local function QuickSkip()
	return enabled and db.quickSkip
end

local function OnCinematicKey(frame, key)
	if not (QuickSkip() and QUICK_KEYS[key]) then
		return
	end
	if StopCutscene() and frame.closeDialog then
		frame.closeDialog:Hide()
	end
end

local function OnMovieKey(_, key)
	if QuickSkip() and QUICK_KEYS[key] then
		FinishMovie()
	end
end

local function Hook()
	if hooked then
		return
	end
	hooked = true -- scripts hooked once and never unhooked: the handlers check QuickSkip()
	if CinematicFrame then
		CinematicFrame:HookScript("OnKeyDown", OnCinematicKey)
	end
	if MovieFrame then
		MovieFrame:HookScript("OnKeyUp", OnMovieKey)
	end
end

function ns.QuestsCinematics_Start(moduleDB)
	db = moduleDB
	enabled = true
	Hook()
	events:Watch(OWNER, "CINEMATIC_START")
	events:Watch(OWNER, "CINEMATIC_STOP")
	events:Watch(OWNER, "PLAY_MOVIE")
end

function ns.QuestsCinematics_Stop()
	enabled = false
	running, cancellable = false, false
	events:UnwatchAll(OWNER)
end
