local addonName, ns = ...

-- Friend sharing: who can be reached. Battle.net friends online in this WoW (retail), by the session-only
-- gameAccountID, with the BattleTag everything saved is keyed by. Rebuilt lazily after the friend list changed
-- (Share.lua marks it dirty on the Battle.net friend events).

local online = {} -- [gameAccountID] = { tag = BattleTag, character = name }
local dirty = true

-- wowProjectID was added to the game account info in 12.1.0; when it's missing the client is still checked.
local function SameGame(game)
	return game.clientProgram == BNET_CLIENT_WOW and (game.wowProjectID == nil or game.wowProjectID == WOW_PROJECT_ID)
end

local function Rebuild()
	wipe(online)
	for i = 1, BNGetNumFriends() or 0 do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		if info and info.battleTag then
			for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
				local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
				if game and game.isOnline and game.gameAccountID and SameGame(game) then
					online[game.gameAccountID] = { tag = info.battleTag, character = game.characterName }
				end
			end
		end
	end
	dirty = false
end

function ns.Share_RosterDirty()
	dirty = true
end

function ns.Share_RosterGet(gameAccountID)
	if dirty then
		Rebuild()
	end
	return online[gameAccountID]
end

-- Every reachable gameAccountID.
function ns.Share_RosterIDs()
	if dirty then
		Rebuild()
	end
	local ids = {}
	for id in pairs(online) do
		ids[#ids + 1] = id
	end
	return ids
end
